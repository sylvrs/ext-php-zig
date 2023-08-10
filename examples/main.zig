const php = @import("php");
const zend = php.zend;
const Module = php.Module;
const builtin = @import("builtin");
const std = @import("std");

pub fn displayInfo(_: *const php.zend.ModuleEntry) void {
    php.printInfoStart();
    php.printInfoHeaderMap(.{
        .@"test extension support" = "enabled",
        .version = test_module.version,
        .author = "sylvrs",
        .os = switch (builtin.os.tag) {
            .windows => "Windows",
            .macos => "macOS",
            .linux => "Linux",
            else => "Unknown",
        },
    });
    php.printInfoEnd();
}

pub fn handleStartup(_: usize, _: usize) !void {}

pub fn handleShutdown(version: usize, module_number: usize) !void {
    _ = version;
    _ = module_number;
    test_module.deinit();
    defer _ = gpa.deinit();
}

pub fn extAdd(a: i64, b: i64) !i64 {
    if (a == 0 or b == 0) {
        return error.ZeroesNotAllowed;
    }
    return a + b;
}

pub fn extHello(name: []const u8) void {
    std.debug.print("Hello, {s}!\n", .{name});
}

pub fn extHelloWorld() void {
    std.debug.print("Hello, world!\n", .{});
}

pub fn extFibonacci(n: i64) i64 {
    if (n <= 1) {
        return n;
    }
    return extFibonacci(n - 1) + extFibonacci(n - 2);
}

pub fn extJoin(values: []php.zend.ZVal) void {
    for (values, 0..) |value, i| {
        std.debug.print("{d}{s}", .{
            value.value.lval,
            if (i < values.len - 1) ", " else "\n",
        });
    }
}

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
var test_module: Module = undefined;

export fn get_module() *php.zend.ModuleEntry {
    test_module = Module.init(.{
        .name = "test_ext",
        .version = "0.0.2",
        .allocator = gpa.allocator(),
    });

    test_module.addFunction("ext_fibonacci", extFibonacci, &.{
        .{ .name = "n", .default_value = "5" },
    });
    // test_module.addFunction("ext_print_join", extJoin, &.{});
    // test_module.addFunction("ext_add", extAdd, &.{});
    // test_module.addFunction("ext_hello", extHello, &.{});
    return test_module.create(@This());
}
