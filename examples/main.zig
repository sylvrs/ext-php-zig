const php = @import("php");
const builtin = @import("builtin");
const std = @import("std");

// pub fn displayInfo(_: *const php.zend.ModuleEntry) void {
//     php.printInfoStart();
//     php.printInfoHeaderMap(.{
//         .@"test extension support" = "enabled",
//         .version = test_module.version,
//         .author = "sylvrs",
//         .os = switch (builtin.os.tag) {
//             .windows => "Windows",
//             .macos => "macOS",
//             .linux => "Linux",
//             else => "Unknown",
//         },
//     });
//     php.printInfoEnd();
// }

pub fn handleStartup(_: usize, _: usize) !void {}

pub fn handleShutdown(_: usize, _: usize) !void {
    // test_module.deinit();
    defer _ = gpa.deinit();
}

pub fn extFibonacci(n: i64) i64 {
    if (n <= 1) {
        return n;
    }
    return extFibonacci(n - 1) + extFibonacci(n - 2);
}

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
var module = php.Module.init(.{
    .name = "test_ext",
    .version = "0.0.2",
    .allocator = gpa.allocator(),
});
export fn get_module() *php.zend.ModuleEntry {
    // test_module.addFunction("ext_fibonacci", extFibonacci, &.{
    //     .{ .name = "n", .default_value = "5" },
    // });
    return module.create(@This());
}
