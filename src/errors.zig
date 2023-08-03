pub const std = @import("std");
pub const internal = @import("internal.zig");
pub const zend = @import("zend.zig");

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
pub fn wrongExpectedCountError(min_args: u32, max_args: u32) void {
    internal.zend_wrong_parameters_count_error(min_args, max_args);
}

pub fn wrongParameterError(error_code: ErrorCode, num: u32, name: []const u8, expected: zend.types.TypeInfo, argument: *zend.ZVal) void {
    _ = argument;
    _ = expected;
    _ = name;
    _ = num;
    _ = error_code;
}
