const builtin = @import("builtin");
const std = @import("std");
/// Internal modules that could be used by the user
pub const internal = @import("internal.zig");
pub const zend = @import("zend.zig");
pub const types = @import("types.zig");
pub const errors = @import("errors.zig");
/// Exposed types for use in the user's code
pub const Module = @import("Module.zig");

/// The maximum size of a value that can be formatted into the printInfoHeaderMap function
const MaxInfoBufferValueSize = 1024;

pub const CallingConv = if (builtin.os.tag == .windows) std.os.windows.WINAPI else .C;

pub const printInfoStart = internal.php_info_print_table_start;
pub const printInfoHeader = internal.php_info_print_table_header;
pub const printInfoEnd = internal.php_info_print_table_end;

pub fn printInfoHeaderSimple(key: []const u8, value: []const u8) void {
    internal.php_info_print_table_header(2, key.ptr, value.ptr);
}

pub fn printInfoHeaderMap(map: anytype) void {
    const map_type_info = @typeInfo(@TypeOf(map));
    // ensure that the map is a struct
    if (map_type_info != .Struct) {
        @compileError("expected tuple or struct argument, found " ++ @typeName(@TypeOf(map)));
    }

    var buf: [MaxInfoBufferValueSize]u8 = undefined;
    inline for (map_type_info.Struct.fields) |field| {
        // prints the key and the formatted value of the map
        const value = @field(map, field.name);
        const fmt = switch (@typeInfo(@TypeOf(value))) {
            .Int => "{d}",
            .Float => "{f}",
            .Bool => "{b}",
            .Pointer => |ptr| blk: {
                // if it is a simple pointer to a u8, then print it as a string
                if (ptr.child == u8) {
                    break :blk "{s}";
                }
                // check for a slice of u8
                const child_type_info = @typeInfo(ptr.child);
                if (child_type_info == .Array and child_type_info.Array.child == u8) {
                    break :blk "{s}";
                }
                // otherwise, print it as a pointer
                break :blk "{p}";
            },
            else => "{any}",
        };
        printInfoHeaderSimple(
            // note: this is a workaround for a bug that will print all of the keys
            // e.g., if the keys are "foo", "bar", and "buzz", it'll print "foobarbuzz", "barbuzz", and "buzz"
            field.name ++ "\x00",
            // append null terminator to the format string to ensure that PHP doesn't read past the end of the string
            // this is so that we can just use a small buffer on the stack instead of allocating a new string
            std.fmt.bufPrint(&buf, fmt ++ "\x00", .{value}) catch @panic("error formatting string into buffer"),
        );
    }
}
