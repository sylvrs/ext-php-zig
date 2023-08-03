# ext-php-zig

A Zig library to enable the writing of PHP extensions in Zig.

## DISCLAIMER!
This library is extremely early in development and as such, isn't feature complete nor ready for production use. Use at your own risk.

## Usage
A basic module can be created by creating a Zig file with the following contents:
```rs
const php = @import("php");
const std = @import("std");

var test_module = php.Module.init(.{
    .name = "test_ext",
    .version = "0.0.2",
    .allocator = std.heap.page_allocator,
});

// The library will automatically search for these three functions:
// - displayInfo - This is the function called when phpinfo() or php -i is called
// - handleStartup - This is the function called when the module is loaded
// - handleShutdown - This is the function called when the module is unloaded
pub fn displayInfo(_: *const php.ZendModuleEntry) void {
    php.printInfoStart();
    php.printInfoHeaderMap(.{
        .@"test extension support" = "enabled",
    });
    php.printInfoEnd();
}

pub fn handleStartup(version: usize, module_number: usize) !void {
    // do something on startup
}

pub fn handleShutdown(version: usize, module_number: usize) !void {
    // make sure our allocated memory is freed
    test_module.deinit();
}

pub fn extHello(name: []const u8) void {
    std.debug.print("Hello, {s}!\n", .{name});
}

// This is the most important function when creating a module as this is what PHP will look for when loading the module
export fn get_module() *php.ZendModuleEntry {
    test_module.addFunction("ext_hello", extHello, &.{});
    return test_module.create(@This());
}
```