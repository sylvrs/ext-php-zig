const php = @import("php");
const Module = php.Module;
const std = @import("std");

var test_module = Module.init(.{
    .name = "test_ext",
    .version = "0.0.2",
    .allocator = std.heap.page_allocator,
});
var rand: std.rand.Random = undefined;

pub fn displayInfo(_: *const php.ZendModuleEntry) void {
    php.printInfoStart();
    php.printInfoHeaderMap(.{
        .@"test extension support" = "enabled",
        .version = test_module.version,
        .author = "sylvrs",
    });
    php.printInfoEnd();
}

pub fn handleStartup(_: usize, _: usize) !void {
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.os.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    rand = prng.random();
}

pub fn handleShutdown(version: usize, module_number: usize) !void {
    _ = version;
    _ = module_number;
    test_module.deinit();
}

pub fn extAdd(a: u8, b: u8) u16 {
    return a + b;
}

pub fn extHello(name: []const u8) void {
    std.debug.print("Hello, {s}!\n", .{name});
}

pub fn extJoin(values: []php.zend.ZVal) void {
    for (values, 0..) |value, i| {
        std.debug.print("{d}{s}", .{
            value.value.lval,
            if (i < values.len - 1) ", " else "",
        });
    }
}

export fn get_module() *php.ZendModuleEntry {
    test_module.addFunction("ext_print_join", extJoin, &.{});
    test_module.addFunction("ext_add", extAdd, &.{});
    test_module.addFunction("ext_hello", extHello, &.{});
    return test_module.create(@This());
}
