const std = @import("std");
const builtin = @import("builtin");

/// PHPIncludePaths is the list of include paths to use inside the PHP devel pack
const PHPIncludePaths = [_][]const u8{ "", "main", "TSRM", "Zend", "ext" };
/// The paths needed to properly build a PHP extension
const PHPDevelopmentPaths = struct {
    include_path: []const u8,
    library_path: ?std.Build.LazyPath = null,
    library_name: ?[]const u8 = null,
    executable_path: []const u8,
};

/// A library struct with helper methods for building PHP extensions
/// This will automatically link the PHP library and add the include paths
/// This also provides methods for installing the library and running the PHP executable with the extension loaded
pub const PHPLibrary = struct {
    b: *std.Build,
    name: []const u8,
    development_paths: PHPDevelopmentPaths,
    debug: bool,
    thread_safe: bool,
    library: *std.Build.Step.Compile,

    pub fn init(
        b: *std.Build,
        options: struct {
            name: []const u8,
            entrypoint: []const u8,
            development_paths: PHPDevelopmentPaths,
            debug: bool,
            thread_safe: bool,
            target: *std.Build.ResolvedTarget,
            optimize: std.builtin.OptimizeMode,
        },
    ) !PHPLibrary {
        // MSVC is needed for PHP on Windows
        if (options.target.query.os_tag == .windows) {
            options.target.query.abi = .msvc;
        }

        // create Zig module
        const module = b.addModule("php-ext-zig", .{
            .root_source_file = b.path("src/php.zig"),
        });

        const lib = b.addSharedLibrary(.{
            .name = options.name,
            .root_source_file = b.path(options.entrypoint),
            .target = options.target.*,
            .optimize = options.optimize,
            .link_libc = true,
        });
        // Add module to library
        lib.root_module.addImport("php", module);

        var buf: [1024]u8 = undefined;
        inline for (PHPIncludePaths) |path| {
            lib.addIncludePath(.{
                .cwd_relative = try std.fmt.bufPrint(&buf, "{s}/{s}", .{
                    options.development_paths.include_path,
                    path,
                }),
            });
        }
        // link the PHP library
        if (options.development_paths.library_path) |library_path| {
            lib.addLibraryPath(library_path);
        }
        if (options.development_paths.library_name) |library_name| {
            lib.linkSystemLibrary(library_name);
        }
        return PHPLibrary{
            .b = b,
            .name = options.name,
            .development_paths = options.development_paths,
            .debug = options.debug,
            .thread_safe = options.thread_safe,
            .library = lib,
        };
    }

    /// `install` will install the library into the build
    pub fn install(self: *PHPLibrary) void {
        self.b.installArtifact(self.library);
    }

    /// `addInstallArtifact` will return a step that will install the library into the build
    pub fn addInstallArtifact(self: *PHPLibrary, options: std.Build.Step.InstallArtifact.Options) *std.Build.Step.InstallArtifact {
        return self.b.addInstallArtifact(self.library, options);
    }

    /// `addRunner` will return a step that will run the PHP executable with the extension loaded
    pub fn addRunnerStep(self: *PHPLibrary, args: []const []const u8) !*std.Build.Step.Run {
        var arguments = std.ArrayList([]const u8).init(self.b.allocator);
        defer arguments.deinit();
        const path = try std.fmt.allocPrint(self.b.allocator, "extension=zig-out/lib/{s}{s}{s}", .{
            // Libraries built on Linux are prepended with a `lib` prefix
            if (builtin.os.tag == .linux) "lib" else "",
            self.name,
            switch (builtin.os.tag) {
                .windows => ".dll",
                .linux => ".so",
                .macos => ".dylib",
                inline else => @compileError("Unsupported OS"),
            },
        });
        defer self.b.allocator.free(path);
        try arguments.appendSlice(&.{ self.development_paths.executable_path, "-d", path });
        try arguments.appendSlice(args);
        return self.b.addSystemCommand(arguments.items);
    }

    pub fn generateStubs(_: *PHPLibrary) void {}
};

const PHPDevelPath = "php-devel-pack";
const ThreadSafe = true;

// Here is the line used to resolve the dependency loop upon a new build
// Once Zig fixes their dependency loop issue, this can be removed
// pub const zif_handler = ?*const fn (*anyopaque, *anyopaque) callconv(.C) void;
pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    var target = b.standardTargetOptions(.{});

    var library = try PHPLibrary.init(b, .{
        .name = "test_ext",
        .entrypoint = "examples/main.zig",
        // TODO: automagically download the devel pack if compiling on Windows
        // or search for the include path on Linux
        .development_paths = switch (builtin.os.tag) {
            .windows => .{
                .include_path = PHPDevelPath ++ "/include",
                .library_path = .{ .cwd_relative = PHPDevelPath ++ "/lib" },
                .library_name = "php8" ++ if (ThreadSafe) "ts" else "",
                .executable_path = "C:\\Users\\Matt\\Downloads\\php-8.2.7-Win32-vs16-x64\\php.exe",
            },
            .linux => .{
                .include_path = "/home/matthew/php/php7/include/php",
                .executable_path = "php",
            },
            inline else => @compileError("Unsupported OS"),
        },
        .debug = true,
        .thread_safe = ThreadSafe,
        .target = &target,
        .optimize = optimize,
    });
    // Create install artifact step for use in build & run steps
    var install = library.addInstallArtifact(.{});

    // Build step
    const build_step = b.step("example", "Build the example extension");
    build_step.dependOn(&install.step);

    // Run step
    const run_step = b.step("run", "Run the example extension");
    var runner = try library.addRunnerStep(&.{"examples/test.php"});
    runner.step.dependOn(&install.step);
    run_step.dependOn(&runner.step);
}
