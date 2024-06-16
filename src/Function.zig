const std = @import("std");
const zend = @import("zend.zig");
const types = @import("types.zig");
const utils = @import("utils.zig");

/// `NativeCallSignature` represents the function layout for a function that is called by PHP
/// The arguments must be specified as `*anyopaque` because of a false dependency loop bug in Zig
/// Here is what the function signature would look like if the bug was fixed:
/// pub const zif_handler = ?*const fn ([*c]zend_execute_data, [*c]zval) callconv(.C) void;
const NativeCallSignature = *const fn (zend_execute_data: *anyopaque, zend_return_value: *anyopaque) callconv(.C) void;

const Self = @This();

/// The name of the function
name: []const u8,
/// The constructed function handler that is called when the function is called
handler: NativeCallSignature,
/// TODO: Figure out how this is used
flags: u32 = 0,
/// The attached argument info for the function.
/// This is used to store the actual values for the arguments
argument_info: []const zend.InternalArgInfo,
/// `EntryTerminator` is a special function entry that is used to terminate a function entry list
pub const EntryTerminator = zend.FunctionEntry{
    .fname = null,
    .handler = null,
    .arg_info = null,
    .num_args = 0,
    .flags = 0,
};

/// `ArgumentMetadata` represents the metadata for a function argument
pub const ArgumentMetadata = struct { name: []const u8, default_value: ?[]const u8 = null };

/// `init` creates a new function with the given name, function, and metadata
pub fn init(name: []const u8, comptime func: anytype, comptime metadata: []const ArgumentMetadata) Self {
    const func_type_info = @typeInfo(@TypeOf(func));
    if (func_type_info != .Fn) {
        @compileError("expected function, found " ++ @typeName(@TypeOf(func)));
    }
    const func_info = func_type_info.Fn;
    if (func_info.params.len != metadata.len) {
        @compileError(std.fmt.comptimePrint("function parameter count ({d}) must match metadata length ({d})", .{ func_info.params.len, metadata.len }));
    }
    return Self{
        .name = name,
        .handler = createNativeWrapper(func),
        .argument_info = &[_]zend.InternalArgInfo{
            .{
                .name = metadata.len,
                .type = types.Mixed,
                .default_value = null,
            },
        } ++ comptime utils.map(metadata, struct {
            pub fn map(arg: ArgumentMetadata) zend.InternalArgInfo {
                return .{
                    .name = arg.name.ptr,
                    .type = types.Mixed,
                    .default_value = arg.default_value.?.ptr,
                };
            }
        }.map),
    };
}

/// `build` builds the function entry for the function
pub fn build(self: *Self) zend.FunctionEntry {
    return .{
        .fname = self.name.ptr,
        .handler = self.handler,
        .arg_info = self.argument_info.ptr,
        .num_args = @intCast(self.argument_info.len),
        .flags = self.flags,
    };
}

/// `createNativeWrapper` creates a wrapper for the given function to reduce friction between Zig and PHP
/// This will automatically handle errors, return values, and the function's arguments
fn createNativeWrapper(comptime func: anytype) NativeCallSignature {
    const func_type_info = @typeInfo(@TypeOf(func));
    if (func_type_info != .Fn) {
        @compileError("Parameter must be a function");
    }
    const func_data = func_type_info.Fn;
    _ = func_data;
    return struct {
        pub fn handle(execute_data: *anyopaque, return_value: *anyopaque) callconv(.C) void {
            _ = execute_data;
            _ = return_value;
        }
    }.handle;
}
