const std = @import("std");
const builtin = @import("builtin");

const UsingZTS = true;
const PHPVersion = "8.2.8";
// By default, we compile for the current architecture
const Arch = switch (builtin.cpu.arch) {
    .x86_64 => "x64",
    .x86 => "x86",
    else => @compileError("Unsupported architecture"),
};

/// PHPIncludePaths is the list of include paths to use inside the PHP devel pack
const PHPIncludePaths = [_][]const u8{ "", "main", "TSRM", "Zend", "ext" };
// PHPDevelPath is the path to the PHP devel pack on Windows
const PHPDevelPath = "php-devel-pack";

const PHPOptions = struct {
    include_path: []const u8,
    library_path: ?[]const u8 = null,
    library_name: ?[]const u8 = null,
    executable_path: []const u8,
};

const php_options: PHPOptions = switch (builtin.os.tag) {
    .windows => .{
        .include_path = std.fmt.comptimePrint("{s}/include", .{PHPDevelPath}),
        .library_path = std.fmt.comptimePrint("{s}/lib", .{PHPDevelPath}),
        .library_name = "php8" ++ if (UsingZTS) "ts" else "",
        // .executable_path = "C:\\Users\\Matt\\Downloads\\php-8.2.7-Win32-vs16-x64\\php.exe",
        .executable_path = "php",
    },
    .linux => .{
        .include_path = "/home/matthew/php/php7/include/php",
        .executable_path = "php",
    },
    inline else => @compileError("MacOS is not supported yet"),
};

// Here is the line used to resolve the dependency loop upon a new build
// Once Zig fixes their dependency loop issue, this can be removed
// pub const zif_handler = ?*const fn (*anyopaque, *anyopaque) callconv(.C) void;
pub fn build(b: *std.Build) !void {
    var target = b.standardTargetOptions(.{});
    // MSVC is needed for PHP on Windows
    if (target.isWindows()) {
        target.abi = .msvc;
    }
    const optimize = b.standardOptimizeOption(.{});

    // create Zig module
    const module = b.addModule("php-ext-zig", .{
        .source_file = .{ .path = "src/php.zig" },
        .dependencies = &.{},
    });

    // zig build example
    const example_step = b.step("example", "Runs the main example");

    // create library
    const libraryName = "test_ext";
    const lib = b.addSharedLibrary(.{
        .name = libraryName,
        .root_source_file = .{ .path = "examples/main.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    lib.addModule("php", module);

    inline for (PHPIncludePaths) |path| {
        lib.addIncludePath(.{
            .cwd_relative = std.fmt.comptimePrint("{s}/{s}", .{
                php_options.include_path,
                path,
            }),
        });
    }
    // link the PHP library
    if (php_options.library_path) |library_path| {
        lib.addLibraryPath(.{ .cwd_relative = library_path });
    }
    if (php_options.library_name) |library_name| {
        lib.linkSystemLibrary(library_name);
    }
    // add the artifact
    b.installArtifact(lib);
    // add the library to the build step

    // run php
    const run_php = b.addSystemCommand(&.{
        php_options.executable_path,
        "-d",
        std.fmt.comptimePrint("extension=zig-out/lib/{s}", .{
            switch (builtin.os.tag) {
                .windows => libraryName ++ ".dll",
                .macos => libraryName ++ ".dylib",
                else => "lib" ++ libraryName ++ ".so",
            },
        }),
        "examples/test.php",
    });

    const build_step = b.addInstallArtifact(lib, .{});
    // PHP run step depends on building to complete
    run_php.step.dependOn(&build_step.step);
    example_step.dependOn(&run_php.step);
}
