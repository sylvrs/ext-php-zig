const builtin = @import("builtin");
const std = @import("std");
const Fn = std.builtin.Type.Fn;
const zend = @import("zend.zig");
const types = @import("types.zig");
const TypeInfo = types.TypeInfo;
const TypeInfoError = types.TypeInfoError;
const errors = @import("errors.zig");
const internal = @import("internal.zig");
const php = @import("php.zig");

const NativeCallSignature = *const fn (zend_execute_data: *anyopaque, zend_return_value: *anyopaque) callconv(php.CallingConv) void;

pub const ExecuteData = struct {
    pub const ParseError = error{WrongType};
    zend_execute_data: *zend.ExecuteData,

    pub fn argCount(self: *ExecuteData) usize {
        return self.zend_execute_data.This.u2.num_args;
    }

    pub fn get(self: *ExecuteData, comptime T: type, offset: usize) ParseError!T {
        const zval = zend.resolveZVal(self.zend_execute_data, offset);
        const t_type = zend.types.resolveFromType(T);
        const zval_type = zend.types.resolve(zval) catch @panic("unexpected type");
        if (zval_type != t_type) {
            panicOnTypeMismatch(t_type, zval_type);
            return ParseError.WrongType;
        }
    }

    pub fn boolean(self: *ExecuteData, offset: usize) ParseError!bool {
        const zval = zend.resolveZVal(self.zend_execute_data, offset);
        const zval_type = zend.types.resolve(zval) catch @panic("unexpected type");
        if (zval_type != .True and zval_type != .False) {
            panicOnTypeMismatch(.Bool, zval_type);
            return ParseError.WrongType;
        }
        return zval_type == .True;
    }

    pub fn string(self: *ExecuteData, offset: usize) ParseError![]const u8 {
        const zval = zend.resolveZVal(self.zend_execute_data, offset);
        const zval_type = zend.types.resolve(zval) catch errors.panicWithFmt("unexpected type: 0x{x:0>3}", .{zval.u1.type_info});
        if (zval_type != .String and zval_type != .ExtendedString) {
            panicOnTypeMismatch(.String, zval_type);
            return ParseError.WrongType;
        }
        // extract len
        const len = zval.value.str.*.len;
        // get pointer to value
        const ptr = @as([*]const u8, &zval.value.str.*.val);
        // create string slice from ptr + len
        return ptr[0..len];
    }

    pub fn array(self: *ExecuteData, comptime T: type, offset: usize) ParseError![]T {
        const zval = zend.resolveZVal(self.zend_execute_data, offset);
        const zval_type = zend.types.resolve(zval) catch @panic("unexpected type");
        if (zval_type != .Array and zval_type != .ExtendedArray) {
            panicOnTypeMismatch(.Array, zval_type);
            return ParseError.WrongType;
        }
        const arr = zval.value.arr.*;
        const len = arr.nNumOfElements;
        return arr.unnamed_0.arPacked[0..len];
    }

    pub fn int(self: *ExecuteData, comptime T: type, offset: usize) ParseError!T {
        return @intCast(try self.long(offset));
    }

    pub fn long(self: *ExecuteData, offset: usize) ParseError!i64 {
        const zval = zend.resolveZVal(self.zend_execute_data, offset);
        const zval_type = zend.types.resolve(zval) catch @panic("unexpected type");
        if (zval_type != .Long) {
            panicOnTypeMismatch(.Long, zval_type);
            return ParseError.WrongType;
        }
        return zval.value.lval;
    }

    fn panicOnTypeMismatch(comptime expected: anytype, found: anytype) noreturn {
        errors.panicWithFmt("expected {any}, found {any}", .{ expected, found });
    }
};

pub const ReturnValue = union(types.TypeInfo) {
    Undefined: void,
    Null: void,
    False: void,
    True: void,
    Long: i64,
    Double: f64,
    String: []const u8,
    // TODO!: finish these types
    Array: void,
    Object: void,
    Resource: void,
    Reference: void,
    Constant: void,
    Callable: void,
    Iterable: void,
    Void: void,
    Static: void,
    Mixed: void,
    Never: void,
    Bool: bool,
    Number: void,
    // ref-counted types
    ExtendedString: []const u8,
    ExtendedArray: void,
    ExtendedObject: void,
    ExtendedResource: void,
    ExtendedReference: void,
    ExtendedConstant: void,
};

const ValueData = struct {
    zend_value: *zend.ZVal,

    pub fn set(self: *ValueData, data: anytype) void {
        switch (@typeInfo(@TypeOf(data))) {
            .Bool => self.setBool(data),
            .Null => self.setReturnType(.Null),
            .Int => self.setLong(@intCast(data)),
            .Float => self.setDouble(data),
            .Pointer => |ptr| if (ptr.size == .Slice and ptr.is_const and ptr.child == u8) {
                self.setString(data);
            } else {
                errors.panicWithFmt("unsupported pointer type: {any}", .{@typeName(@TypeOf(data))});
            },
            .Array => |array| switch (array.child) {
                u8 => self.setString(data),
                else => errors.panicWithFmt("unsupported array child type: {any}", .{@typeName(@TypeOf(data))}),
            },
            .Void => {},
            inline else => @compileError("unsupported return type: " ++ @typeName(@TypeOf(data))),
        }
    }

    pub fn setReturnType(self: *ValueData, type_info: TypeInfo) void {
        self.zend_value.u1.type_info = @intFromEnum(type_info);
    }

    pub fn setBool(self: *ValueData, value: bool) void {
        self.setReturnType(if (value) .True else .False);
    }

    pub fn setString(self: *ValueData, value: []const u8) void {
        self.setReturnType(.String);
        self.zend_value.value.str = internal.zend_string_init_fast(value.ptr, value.len);
    }

    pub fn setLong(self: *ValueData, value: i64) void {
        self.setReturnType(.Long);
        self.zend_value.value.lval = value;
    }

    pub fn setDouble(self: *ValueData, value: f64) void {
        self.setReturnType(.Double);
        self.zend_value.value.dval = value;
    }
};

pub const ArgumentInfo = struct { name: []const u8, type: types.Type, default_value: ?[]const u8 = null };
pub const ArgumentMetadata = struct { name: []const u8, default_value: ?[]const u8 = null };

const Self = @This();
/// The name of the function
name: []const u8,
/// Mapped argument info for the function
argument_info: []const ArgumentInfo,
// Internal argument info for the function. This is mapped directly from the argument info slice
stored_arg_info: std.ArrayList(zend.InternalArgInfo),
// TODO: ?
flags: u32 = 0,
// pub const zif_handler = ?*const fn ([*c]zend_execute_data, [*c]zval) callconv(.C) void;
handler: *const fn (execute_data: *anyopaque, return_value: *anyopaque) callconv(php.CallingConv) void = undefined,

pub fn init(allocator: std.mem.Allocator, name: []const u8, comptime func: anytype, comptime metadata: []const ArgumentMetadata) Self {
    const func_info = @typeInfo(@TypeOf(func));
    if (func_info != .Fn) {
        @compileError("expected function, found " ++ @typeName(@TypeOf(func)));
    }

    const mapped_info = mapArgumentsToInfo(func_info.Fn.params, metadata);
    var self = Self{
        .name = name,
        .handler = createHandler(func, metadata),
        .argument_info = &mapped_info,
        .stored_arg_info = std.ArrayList(zend.InternalArgInfo).init(allocator),
    };
    // create the internal argument info from the given argument info
    // todo: is there *any* way to do this on the stack?
    inline for (mapped_info) |argument| {
        self.stored_arg_info.append(.{
            .name = argument.name.ptr,
            .type = argument.type,
            .default_value = argument.default_value.?.ptr,
        }) catch unreachable;
    }
    return self;
}

pub fn deinit(self: *const Self) void {
    self.stored_arg_info.deinit();
}

fn createHandler(comptime func: anytype, comptime metadata: []const ArgumentMetadata) NativeCallSignature {
    const fn_info = @typeInfo(@TypeOf(func)).Fn;
    // extract arguments as tuple
    const args_type = std.meta.ArgsTuple(@TypeOf(func));
    return struct {
        // TODO!: These opaque pointers are a workaround for a dependency loop bug in Zig
        pub fn call(zend_execute_data: *anyopaque, zend_return_value: *anyopaque) callconv(php.CallingConv) void {
            // convert to a ZendExecuteData pointer
            var execute_data = ExecuteData{ .zend_execute_data = opaqueCast(zend.ExecuteData, zend_execute_data) };
            @breakpoint();
            // call the function
            // TODO: optional & default values
            // if (execute_data.argCount() != fn_info.params.len) {
            //     errors.wrongExpectedCountError(fn_info.params.len, fn_info.params.len, &execute_data);
            //     return;
            // }
            // create value for each argument
            var args: args_type = undefined;
            // iterate & map each argument
            inline for (@typeInfo(args_type).Struct.fields, 0..) |field, i| {
                args[i] = mapFieldToData(field.type, &execute_data, i, metadata[i]);
            }

            var return_data = ValueData{ .zend_value = opaqueCast(zend.ZVal, zend_return_value) };
            if (@typeInfo(fn_info.return_type.?) == .ErrorUnion) {
                // map the result to the return value
                return_data.set(@call(.auto, func, args) catch |err| {
                    return errors.throwException(@errorName(err), 0xff);
                });
            } else {
                // map the result to the return value
                return_data.set(@call(.auto, func, args));
            }
        }
    }.call;
}

fn mapFieldToData(comptime T: type, execute_data: *ExecuteData, offset: usize, _: ArgumentMetadata) T {
    return switch (@typeInfo(T)) {
        .Null => null,
        .Optional => |optional| execute_data.optional(optional.child, offset),
        .Bool => execute_data.boolean(offset) catch errors.panicWithFmt("expected bool, got {any}", .{@typeName(T)}),
        .Int => @intCast(execute_data.long(offset) catch errors.panicWithFmt("expected int, got {any}", .{@typeName(T)})),
        // Check for string slice
        .Pointer => |ptr| switch (ptr.size == .Slice and ptr.is_const and ptr.child == u8) {
            true => execute_data.string(offset) catch errors.panicWithFmt("expected string, got {any}", .{@typeName(T)}),
            false => execute_data.array(ptr.child, offset) catch errors.panicWithFmt("expected array, got {any}", .{@typeName(T)}),
        },
        .Array => |array| execute_data.array(array.child, offset) catch errors.panicWithFmt("expected array, got {any}", .{@typeName(T)}),
        inline else => @compileError("unsupported argument type: " ++ @typeName(T)),
    };
}

fn opaqueCast(comptime T: type, ptr: *anyopaque) *T {
    return @alignCast(@ptrCast(ptr));
}

// TODO: Simplify this and enhance the error messages?
inline fn mapArgumentsToInfo(comptime params: []const Fn.Param, comptime metadata: []const ArgumentMetadata) [params.len]ArgumentInfo {
    var arg_types: [params.len]ArgumentInfo = undefined;
    inline for (params, 0..) |param, index| {
        arg_types[index] = .{
            .name = metadata[index].name,
            .type = types.mapToZendType(param.type),
            .default_value = metadata[index].default_value,
        };
    }
    return arg_types;
}
