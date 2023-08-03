const builtin = @import("builtin");
const std = @import("std");
const Fn = std.builtin.Type.Fn;
const zend = @import("zend.zig");
const types = @import("types.zig");
const TypeInfo = types.TypeInfo;
const TypeInfoError = types.TypeInfoError;
const errors = @import("errors.zig");
const Self = @This();
const internal = @import("internal.zig");
const php = @import("php.zig");

pub const ArgumentMetadata = struct { name: []const u8, default_value: ?php.ReturnValue = null };

pub const ExecuteData = struct {
    pub const ParseError = error{WrongType};
    zend_execute_data: *zend.ExecuteData,

    pub fn argCount(self: *ExecuteData) usize {
        return self.zend_execute_data.This.u2.num_args;
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
        const zval_type = zend.types.resolve(zval) catch php.panicWithFmt("unexpected type: 0x{x:0>3}", .{zval.u1.type_info});
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
        php.panicWithFmt("expected {any}, found {any}", .{ expected, found });
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
    ExtendedString: []const u8,
    ExtendedArray: void,
    ExtendedObject: void,
    ExtendedResource: void,
    ExtendedReference: void,
    ExtendedConstant: void,
};
const ZendValueData = struct {
    zend_value: *zend.ZVal,

    pub fn setReturnType(self: *ZendValueData, type_info: TypeInfo) void {
        self.zend_value.u1.type_info = @intFromEnum(type_info);
    }

    pub fn setBool(self: *ZendValueData, value: bool) void {
        self.setReturnType(if (value) .True else .False);
    }

    pub fn setString(self: *ZendValueData, value: []const u8) void {
        self.setReturnType(.String);
        self.zend_value.value.str = internal.zend_string_init_fast(value.ptr, value.len);
    }

    pub fn setLong(self: *ZendValueData, value: i64) void {
        self.setReturnType(.Long);
        self.zend_value.value.lval = value;
    }

    pub fn setDouble(self: *ZendValueData, value: f64) void {
        self.setReturnType(.Double);
        self.zend_value.value.dval = value;
    }
};
// exposed function fields
name: []const u8,
arg_info: ?[]const zend.InternalArgInfo = null,
num_args: u32 = 0,
flags: u32 = 0,
// internal called function
// pub const zif_handler = ?*const fn ([*c]zend_execute_data, [*c]zval) callconv(.C) void;
caller: *const fn (execute_data: *anyopaque, return_value: *anyopaque) callconv(php.CallingConv) void = undefined,

pub fn init(name: []const u8, comptime func: anytype, comptime metadata: []const ArgumentMetadata) Self {
    const func_info = @typeInfo(@TypeOf(func));
    if (func_info != .Fn) {
        @compileError("expected function, found " ++ @typeName(@TypeOf(func)));
    }

    const fn_info = func_info.Fn;
    return Self{
        .name = name,
        .caller = struct {
            // TODO!: These opaque pointers are a workaround for a dependency loop bug in Zig
            pub fn call(zend_execute_data: *anyopaque, zend_return_value: *anyopaque) callconv(php.CallingConv) void {
                // convert to a ZendExecuteData pointer
                var execute_data = php.ExecuteData{ .zend_execute_data = opaqueCast(zend.ExecuteData, zend_execute_data) };
                // call the function
                // TODO: optional & default values
                if (execute_data.argCount() != fn_info.params.len) {
                    php.panicWithFmt(
                        "expected {d} arguments, got {d} arguments",
                        .{ fn_info.params.len, execute_data.argCount() },
                    );
                }

                // extract arguments as tuple
                const args_type = std.meta.ArgsTuple(@TypeOf(func));
                // create value for each argument
                var args: args_type = undefined;
                // iterate & map each argument
                inline for (@typeInfo(args_type).Struct.fields, 0..) |field, i| {
                    args[i] = mapFieldToData(field.type, &execute_data, i);
                }
                // if there isn't a return type, call the function and return
                const return_type = fn_info.return_type orelse {
                    @call(.auto, func, args);
                    return;
                };

                const result: return_type = @call(.auto, func, args);
                // map the result to the return value
                var return_data = ZendValueData{ .zend_value = opaqueCast(zend.ZVal, zend_return_value) };
                switch (@typeInfo(@TypeOf(result))) {
                    .Bool => return_data.setBool(result),
                    .Null => return_data.setReturnType(.Null),
                    .Int => return_data.setLong(@intCast(result)),
                    .Float => return_data.setDouble(result),
                    .Pointer => |ptr| if (ptr.size == .Slice and ptr.is_const and ptr.child == u8) {
                        return_data.setString(result);
                    } else {
                        php.panicWithFmt("unsupported pointer type: {any}", .{return_type});
                    },
                    .Array => |array| switch (array.child) {
                        u8 => return_data.setString(result),
                        else => php.panicWithFmt("unsupported array child type: {any}", .{return_type}),
                    },
                    .Type => {},
                    .Void => {},
                    inline else => @compileError("unsupported return type: " ++ @typeName(return_type)),
                }
            }
        }.call,
        .arg_info = &[_]zend.InternalArgInfo{
            // return type is always the first argument
            .{
                .name = "",
                .type = mapTypeToZendType(fn_info.return_type),
                .default_value = null,
            },
        } ++ mapArgumentsToInfo(fn_info.params, metadata),
    };
}

fn mapFieldToData(comptime T: type, execute_data: *ExecuteData, offset: usize) T {
    return switch (@typeInfo(T)) {
        .Null => null,
        .Bool => execute_data.boolean(offset) catch php.panicWithFmt("expected bool, got {any}", .{@typeName(T)}),
        .Int => @intCast(execute_data.long(offset) catch php.panicWithFmt("expected int, got {any}", .{@typeName(T)})),
        // Check for string slice
        .Pointer => |ptr| switch (ptr.size == .Slice and ptr.is_const and ptr.child == u8) {
            true => execute_data.string(offset) catch php.panicWithFmt("expected string, got {any}", .{@typeName(T)}),
            false => execute_data.array(ptr.child, offset) catch php.panicWithFmt("expected array, got {any}", .{@typeName(T)}),
        },
        .Array => |array| execute_data.array(array.child, offset) catch php.panicWithFmt("expected array, got {any}", .{@typeName(T)}),
        inline else => @compileError("unsupported argument type: " ++ @typeName(T)),
    };
}

fn mapTypeToZendTypeInfo(comptime T: type) types.TypeInfo {
    return switch (@typeInfo(T)) {
        .Int => .Long,
        .Float => .Double,
        .Bool => .Bool,
        .Void => .Void,
        .Pointer => |ptr| if (ptr.size == .Slice and ptr.is_const and ptr.child == u8) .String else @compileError("unsupported pointer type: " ++ @typeName(ptr)),
        inline else => @compileError("unsupported type info: " ++ @typeName(T)),
    };
}

fn mapTypeToZendType(comptime T: ?type) zend.Type {
    const current_type = T orelse return types.Void;
    return switch (@typeInfo(current_type)) {
        .Int => types.Long,
        .Float => types.Double,
        .Bool => types.Bool,
        .Void => types.Void,
        .Pointer => |ptr| if (ptr.size == .Slice and ptr.is_const and ptr.child == u8) {
            return types.String;
        } else {
            return types.Array;
        },
        inline else => @compileError("unsupported type: " ++ @typeName(current_type)),
    };
}

fn opaqueCast(comptime T: type, ptr: *anyopaque) *T {
    return @alignCast(@ptrCast(ptr));
}

// TODO: Simplify this and enhance the error messages?
fn mapArgumentsToInfo(comptime params: []const Fn.Param, comptime metadata: []const ArgumentMetadata) [params.len]zend.InternalArgInfo {
    var arg_types: [params.len]zend.InternalArgInfo = undefined;
    inline for (params, 0..) |param, index| {
        if (index < metadata.len) {
            arg_types[index] = .{
                .name = metadata[index].name.ptr,
                .type = mapTypeToZendType(param.type),
                .default_value = null,
            };
        } else {
            arg_types[index] = .{
                .name = "",
                .type = mapTypeToZendType(param.type),
                .default_value = null,
            };
        }
    }
    return arg_types;
}
