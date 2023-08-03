const builtin = @import("builtin");
const std = @import("std");
pub const internal = @import("internal.zig");
pub const zend = @import("zend.zig");
pub const types = @import("types.zig");
pub const errors = @import("errors.zig");

// Common Zend types that should be exposed to the user at the top level
pub const ZendExecuteData = zend.ExecuteData;
pub const ZVal = zend.ZVal;
pub const ZendModuleEntry = zend.ModuleEntry;

pub const Module = @import("Module.zig");
pub const Function = @import("Function.zig");
pub const ExecuteData = Function.ExecuteData;
pub const ReturnValue = Function.ReturnValue;

pub const CallingConv = if (builtin.os.tag == .windows) std.os.windows.WINAPI else .C;

pub fn panicWithFmt(comptime fmt: []const u8, args: anytype) noreturn {
    var buf: [1024]u8 = undefined;
    @panic(std.fmt.bufPrint(&buf, fmt, args) catch unreachable);
}

fn print(value: anytype, comptime indent: []const u8) void {
    const data = value;
    const data_type_info = @typeInfo(@TypeOf(data));
    // ensure that the map is a struct
    if (data_type_info != .Struct) {
        std.debug.print("{s}- [{s}]\n", .{ indent, @typeName(@TypeOf(data)) });
        return;
    }

    const fields_info = data_type_info.Struct.fields;
    std.debug.print("{s}- {s}:\n", .{ indent, @typeName(@TypeOf(data)) });
    inline for (fields_info) |field| {
        std.debug.print("{s}- {s}:\n", .{ indent ++ "  ", field.name });
        print(@field(data, field.name), indent ++ "  ");
    }
}

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

    const fields_info = map_type_info.Struct.fields;
    var buf: [1024]u8 = undefined;
    inline for (fields_info) |field| {
        // prints the key and the formatted value of the map
        const value = @field(map, field.name);
        const fmt = switch (@typeInfo(@TypeOf(value))) {
            .Int => "{d}",
            .Float => "{f}",
            .Bool => "{b}",
            else => "{s}",
        };
        printInfoHeaderSimple(
            field.name,
            // append null terminator to the format string to ensure that PHP doesn't read past the end of the string
            // this is so that we can just use a small buffer on the stack instead of allocating a new string
            std.fmt.bufPrint(&buf, fmt ++ "\x00", .{value}) catch @panic("error formatting string into buffer"),
        );
    }
}
