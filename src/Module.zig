const php = @import("php.zig");
const internal = @import("internal.zig");
const zend = @import("zend.zig");
const builtin = @import("builtin");
const std = @import("std");

// Module API version parts
const BuildSystem: []const u8 = switch (builtin.os.tag) {
    .windows => "VS16",
    else => "",
};
const ThreadSafe = if (zend.ThreadSafe) "TS" else "NTS";

const MethodCallbackMap = std.ComptimeStringMap([]const u8, .{
    .{ "handleStartup", "setStartupCallback" },
    .{ "handleShutdown", "setShutdownCallback" },
    .{ "displayInfo", "setInfoCallback" },
});

const FunctionEntryTerminator = zend.FunctionEntry{
    .fname = null,
    .handler = null,
    .arg_info = null,
    .num_args = 0,
    .flags = 0,
};

pub const ModuleOptions = struct {
    name: []const u8,
    version: []const u8,
    allocator: std.mem.Allocator,
};

const Self = @This();

/// The name of the extension
name: []const u8,
/// The version of the extension
version: []const u8,
/// The allocator used by the module for function registration
allocator: std.mem.Allocator,
/// The internal entry created by the module
entry: zend.ModuleEntry = undefined,
functionEntries: std.ArrayList(zend.FunctionEntry),

/// The functions that will be called by the module on startup and shutdown
startupFn: ?*const fn (type: c_int, version_number: c_int) callconv(.C) c_int = null,
shutdownFn: ?*const fn (type: c_int, version_number: c_int) callconv(.C) c_int = null,
/// The function that will be called by phpinfo() to display information about the module
infoFn: ?*const fn (entry: [*c]const zend.ModuleEntry) callconv(.C) void = null,
/// The functions that will be added to the module
functions: std.ArrayList(php.Function),

pub fn init(options: ModuleOptions) Self {
    return Self{
        .name = options.name,
        .version = options.version,
        .allocator = options.allocator,
        .functions = std.ArrayList(php.Function).init(options.allocator),
        .functionEntries = std.ArrayList(zend.FunctionEntry).init(options.allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.functions.deinit();
}

fn createEntry(self: *Self) *zend.ModuleEntry {
    for (self.functions.items) |function| {
        self.functionEntries.append(zend.FunctionEntry{
            .fname = function.name.ptr,
            .handler = function.caller,
            .arg_info = function.arg_info.?.ptr,
            .num_args = 0,
            .flags = function.flags,
        }) catch @panic("Failed to append function entry");
    }
    self.functionEntries.append(FunctionEntryTerminator) catch @panic("Failed to append function entry terminator");
    // windows doesn't have the module entry struct field `globals_id_ptr` even in TS mode?
    if (zend.ThreadSafe and builtin.os.tag != .windows) {
        self.entry = .{
            // STANDARD_MODULE_PROPERTIES
            .size = @sizeOf(zend.ModuleEntry),
            .zend_api = zend.ModuleAPI,
            .zend_debug = if (zend.Debug) 1 else 0,
            .zts = if (zend.ThreadSafe) 1 else 0,
            .ini_entry = null,
            .deps = null,
            // actual used module fields
            .name = self.name.ptr,
            .functions = self.functionEntries.items.ptr,
            .module_startup_func = self.startupFn,
            .module_shutdown_func = self.shutdownFn,
            .request_startup_func = null,
            .request_shutdown_func = null,
            .info_func = self.infoFn,
            .version = self.version.ptr,
            // STANDARD_MODULES_PROPERTIES
            // NO_MODULE_GLOBALS
            .globals_size = 0,
            .globals_id_ptr = null,
            .globals_ctor = null,
            .globals_dtor = null,
            .post_deactivate_func = null,
            // STANDARD_MODULE_PROPERTIES_EX
            .module_started = 0,
            .type = 0,
            .handle = null,
            .module_number = 0,
            .build_id = std.fmt.comptimePrint("API{d},{s}", .{
                zend.ModuleAPI,
                ThreadSafe,
            }) ++ comptime if (BuildSystem.len > 0) "," ++ BuildSystem else "",
        };
    } else {
        self.entry = .{
            // STANDARD_MODULE_PROPERTIES
            .size = @sizeOf(zend.ModuleEntry),
            .zend_api = zend.ModuleAPI,
            .zend_debug = if (zend.Debug) 1 else 0,
            .zts = if (zend.ThreadSafe) 1 else 0,
            .ini_entry = null,
            .deps = null,
            // actual used module fields
            .name = self.name.ptr,
            .functions = self.functionEntries.items.ptr,
            .module_startup_func = self.startupFn,
            .module_shutdown_func = self.shutdownFn,
            .request_startup_func = null,
            .request_shutdown_func = null,
            .info_func = self.infoFn,
            .version = self.version.ptr,
            // STANDARD_MODULES_PROPERTIES
            // NO_MODULE_GLOBALS
            .globals_size = 0,
            .globals_ptr = null,
            .globals_ctor = null,
            .globals_dtor = null,
            .post_deactivate_func = null,
            // STANDARD_MODULE_PROPERTIES_EX
            .module_started = 0,
            .type = 0,
            .handle = null,
            .module_number = 0,
            .build_id = std.fmt.comptimePrint("API{d},{s}", .{
                zend.ModuleAPI,
                ThreadSafe,
            }) ++ comptime if (BuildSystem.len > 0) "," ++ BuildSystem else "",
        };
    }
    return &self.entry;
}

/// searchForCallbacks attempts to automatically add module callbacks from the struct passed
/// To do so, it will check for the following functions:
/// - handleStartup(type: usize, module_number: usize) usize - The function that will be called on module startup
/// - handleStartup(type: usize, module_number: usize) usize - The function that will be called on module shutdown
/// - displayInfo(entry: *const zend.ModuleEntry) void - The function that will be called by phpinfo() to display information about the module
///
/// These functions must be marked as `pub` in order to properly be found and not errored on
pub fn searchForCallbacks(self: *Self, comptime value: type) void {
    inline for (MethodCallbackMap.kvs) |entry| {
        const method = entry.key;
        const callbackName = entry.value;
        // if the method exists & is a function, attempt to call it
        if (@hasDecl(value, method)) {
            const field = @field(value, method);
            if (@typeInfo(@TypeOf(field)) != .Fn) {
                @compileError(method ++ " must be a function");
            }
            // get method from callback name & call it
            const callbackMethod = @field(@This(), callbackName);
            @call(.auto, callbackMethod, .{ self, field });
        }
    }
}

pub fn setStartupCallback(self: *Self, comptime callback: *const fn (type: usize, version_number: usize) anyerror!void) void {
    self.startupFn = struct {
        fn startup(@"type": c_int, version_number: c_int) callconv(.C) c_int {
            callback(@as(usize, @intCast(@"type")), @as(usize, @intCast(version_number))) catch |err| {
                std.debug.print("Failed to startup module: {any}\n", .{err});
                return @intCast(1);
            };
            return @intCast(0);
        }
    }.startup;
}

pub fn setShutdownCallback(self: *Self, comptime callback: *const fn (type: usize, version_number: usize) anyerror!void) void {
    self.shutdownFn = struct {
        fn shutdown(@"type": c_int, version_number: c_int) callconv(.C) c_int {
            callback(@as(usize, @intCast(@"type")), @as(usize, @intCast(version_number))) catch |err| {
                std.debug.print("Failed to shutdown module: {any}\n", .{err});
                return @intCast(1);
            };
            return @intCast(0);
        }
    }.shutdown;
}

pub fn setInfoCallback(self: *Self, comptime callback: *const fn (entry: *const zend.ModuleEntry) void) void {
    self.infoFn = struct {
        fn info(c_entry: [*c]const zend.ModuleEntry) callconv(.C) void {
            callback(@as(*const zend.ModuleEntry, c_entry));
        }
    }.info;
}

pub fn addFunction(self: *Self, name: []const u8, comptime func: anytype, comptime metadata: []const php.Function.ArgumentMetadata) void {
    self.functions.append(php.Function.init(name, func, metadata)) catch @panic("Failed to append function");
}

/// create creates the module entry for the module
/// It will automatically search for callbacks and initialize the module entry with the context passed
pub fn create(self: *Self, context: anytype) *zend.ModuleEntry {
    self.searchForCallbacks(context);
    return self.createEntry();
}
