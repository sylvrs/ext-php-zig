const builtin = @import("builtin");
const std = @import("std");
const internal = @import("internal.zig");
const zend = @import("zend.zig");

const Self = @This();
/// The name of the extension
name: []const u8,
/// The version of the extension
version: []const u8,
/// The allocator used to hold parts of the extension's data
allocator: std.mem.Allocator,
/// Whether the extension is built for PHP's debug mode
debug: bool,
/// Whether the extension is built for PHP's thread-safe mode
thread_safe: bool,
/// The build ID associated with the extension
build_id: []const u8,
/// The generated entry for exporting in `get_module`
entry: zend.ModuleEntry = undefined,

pub fn init(comptime options: struct {
    name: []const u8,
    version: []const u8,
    allocator: std.mem.Allocator,
    debug: bool = false,
    thread_safe: bool = true,
}) Self {
    return Self{
        .name = options.name,
        .version = options.version,
        .allocator = options.allocator,
        .debug = options.debug,
        .thread_safe = options.thread_safe,
        .build_id = std.fmt.comptimePrint("API{d},{s}{s}", .{
            internal.ZEND_MODULE_API_NO,
            if (options.thread_safe) "TS" else "NTS",
            if (builtin.os.tag == .windows) ",VS16" else "",
        }),
    };
}

/// `build` will build the module entry for the extension
fn build(self: *Self) void {
    self.entry.size = @sizeOf(zend.ModuleEntry);
    self.entry.zend_api = internal.ZEND_MODULE_API_NO;
    self.entry.zend_debug = if (self.debug) 1 else 0;
    self.entry.zts = if (self.thread_safe) 1 else 0;
    self.entry.ini_entry = null;
    self.entry.deps = null;
    self.entry.name = self.name.ptr;
    self.entry.functions = null;
    self.entry.module_startup_func = null;
    self.entry.module_shutdown_func = null;
    self.entry.request_startup_func = null;
    self.entry.request_shutdown_func = null;
    self.entry.info_func = null;
    self.entry.version = self.version.ptr;
    self.entry.globals_size = 0;
    // Resolve field name at compile time
    const field = comptime blk: {
        for (&.{ "globals_ptr", "globals_id_ptr" }) |field| {
            if (@hasField(zend.ModuleEntry, field)) {
                break :blk field;
            }
        }
        @compileError("ModuleEntry does not have globals_ptr or globals_id_ptr");
    };
    @field(self.entry, field) = null;
    self.entry.globals_ctor = null;
    self.entry.globals_dtor = null;
    self.entry.post_deactivate_func = null;
    self.entry.module_started = 0;
    self.entry.type = 0;
    self.entry.handle = null;
    self.entry.module_number = 0;
    self.entry.build_id = self.build_id.ptr;
}

/// MethodCallbackMap is a map of the searched method name to the Module's `setXCallback` equivalent
/// This reduces boilerplate and the need to manually assign the callbacks (which could be desireable, but not the default)
const MethodCallbackMap = std.ComptimeStringMap([]const u8, .{
    .{ "handleStartup", "setStartupCallback" },
    .{ "handleShutdown", "setShutdownCallback" },
    .{ "displayInfo", "setInfoCallback" },
});

/// `setStartupCallback` will assign the startup function for the module
pub fn setStartupCallback(self: *Self, comptime callback: *const fn (version: usize, module_number: usize) anyerror!void) void {
    self.entry.module_startup_func = struct {
        fn startup(@"type": c_int, version_number: c_int) callconv(.C) c_int {
            callback(@as(usize, @intCast(@"type")), @as(usize, @intCast(version_number))) catch |err| {
                std.debug.print("Failed to startup module: {any}\n", .{err});
                return @intCast(1);
            };
            return @intCast(0);
        }
    }.startup;
}

/// `setShutdownCallback` will assign the shutdown function for the module
pub fn setShutdownCallback(self: *Self, comptime callback: *const fn (version: usize, module_number: usize) anyerror!void) void {
    self.entry.module_shutdown_func = struct {
        fn shutdown(@"type": c_int, version_number: c_int) callconv(.C) c_int {
            callback(@as(usize, @intCast(@"type")), @as(usize, @intCast(version_number))) catch |err| {
                std.debug.print("Failed to shutdown module: {any}\n", .{err});
                return @intCast(1);
            };
            return @intCast(0);
        }
    }.shutdown;
}

/// `setInfoCallback` will assign the info function for the module
pub fn setInfoCallback(self: *Self, comptime callback: *const fn (module: *const zend.ModuleEntry) void) void {
    self.entry.info_func = struct {
        fn info(c_entry: [*c]const zend.ModuleEntry) callconv(.C) void {
            callback(@as(*const zend.ModuleEntry, c_entry));
        }
    }.info;
}

/// `resolveModuleFuncs` will attempt to resolve and assign the module functions from the given context
/// Here are the methods that can be resolved:
/// - `handleStartup(version: usize: module_number: usize) !void` - The startup function for the module
/// - `handleShutdown(version: usize: module_number: usize) !void` - The shutdown function for the module
/// - `displayInfo(module: *const zend.ModuleEntry) void` - The info function for the module
fn resolveModuleFuncs(self: *Self, comptime ctx: anytype) void {
    inline for (MethodCallbackMap.kvs) |entry| {
        if (comptime std.meta.trait.hasFn(entry.key)(ctx)) {
            const field = @field(ctx, entry.key);
            // get method from callback name & call it
            const callbackMethod = @field(@This(), entry.value);
            @call(.auto, callbackMethod, .{ self, field });
        }
    }
}

/// `create` will generate and return a pointer to the module entry
pub fn create(self: *Self, comptime ctx: anytype) *zend.ModuleEntry {
    self.build();
    self.resolveModuleFuncs(ctx);
    return &self.entry;
}
