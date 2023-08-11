const builtin = @import("builtin");
const std = @import("std");
const zend = @import("zend.zig");
const utils = @import("utils.zig");
// pub const zif_handler = ?*const fn ([*c]zend_execute_data, [*c]zval) callconv(.C) void;
const NativeCallSignature = *const fn (zend_execute_data: *anyopaque, zend_return_value: *anyopaque) callconv(.C) void;

/// The library's structure for a function argument
pub const ArgumentInfo = struct { name: []const u8, type: *anyopaque, default_value: ?[]const u8 = null };

const Self = @This();
/// The name of the function
name: []const u8,
/// The attached argument info for the function.
/// This is used to store the actual values for the arguments
argument_info: []const ArgumentInfo,
/// The internal argument info for the function
/// Given that these are 
stored_internal_info: []const zend.InternalArgInfo,
/// The constructed function handler that is called when the function is called
handler: NativeCallSignature,
/// TODO: Figure out how this is used
flags: u32 = 0,

const ArgumentMetdata = struct { name: []const u8, default_value: ?[]const u8 = null };
pub fn init(name: []const u8, comptime func: anytype, comptime _: []const ArgumentMetdata) Self {
    const func_info = @typeInfo(@TypeOf(func));
    if (func_info != .Fn) {
        @compileError("expected function, found " ++ @typeName(@TypeOf(func)));
    }
    return Self{
        .name = name,
        .argument_info = undefined,
        .stored_internal_info = utils.map(zend.InternalArgInfo, func_info.Fn.params, struct {
            pub fn map(arg: builtin.Type.Fn.Param) zend.InternalArgInfo {
                return .{
                    .name = arg.name.ptr,
                    .type = null,
                    .default_value = null,
                };
            }
        }.map),
    };
}

pub fn deinit(self: *Self) void {
    self.stored_internal_info.deinit();
}
