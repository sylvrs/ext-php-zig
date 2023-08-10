const std = @import("std");
const builtin = @import("builtin");
const internal = @import("internal.zig");
const Function = @import("Function.zig");
const zend = @import("zend.zig");
pub const ErrorCode = enum(u32) {
    Ok = 0,
    Failure = 1,
    WrongCallback = 2,
    WrongClass = 3,
    WrongClassOrNull = 4,
    WrongClassOrString = 5,
    WrongClassOrStringOrNull = 6,
    WrongClassOrLong = 7,
    WrongClassOrLongOrNull = 8,
    WrongArg = 9,
    WrongCount = 10,
    UnexpectedExtraNamed = 11,
    WrongCallbackOrNull = 12,
};

// TODO!: Many of the Zend error functions do not work yet on Windows because of their calling convention
// This is because when exported, the calling convention is attached to the symbol name (e.g., `zend_wrong_parameters_count_error@@16`)
// Due to the interaction of Zig's `@cImport` with PHP's C macros,
pub fn wrongExpectedCountError(min_args: u32, max_args: u32, execute_data: *Function.ExecuteData) void {
    switch (builtin.os.tag) {
        .windows => panicWithFmt("expected {d} arguments, got {d} arguments", .{ min_args, execute_data.argCount() }),
        else => internal.zend_wrong_parameters_count_error(min_args, max_args),
    }
}

pub fn wrongParameterError(error_code: ErrorCode, num: u32, name: []const u8, expected: zend.types.TypeInfo, argument: *zend.ZVal) void {
    _ = expected;
    switch (builtin.os.tag) {
        .windows => panicWithFmt("wrong parameter error", .{}),
        else => internal.zend_wrong_parameter_error(
            @intFromEnum(error_code),
            num,
            name,
            // TODO: implement expected type enum resolution
            internal.zend_expected_type.Z_EXPECTED_LAST,
            argument,
        ),
    }
}

pub fn throwException(message: []const u8, code: i64) void {
    _ = internal.zend_throw_exception(null, message.ptr, code);
}

pub fn panicWithFmt(comptime fmt: []const u8, args: anytype) noreturn {
    var buf: [1024]u8 = undefined;
    @panic(std.fmt.bufPrint(&buf, fmt, args) catch unreachable);
}
