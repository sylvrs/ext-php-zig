const std = @import("std");
const builtin = @import("builtin");

const UsingZTS = true;
const PHPVersion = "8.2.7";
// By default, we compile for the current architecture
const Arch = switch (builtin.cpu.arch) {
    .x86_64 => "x64",
    .x86 => "x86",
    else => @compileError("Unsupported architecture"),
};

/// PHPIncludePaths is the list of include paths to use inside the PHP devel pack
const PHPIncludePaths = [_][]const u8{ "", "main", "TSRM", "Zend", "ext" };
/// PHPLibraryName is the name of the PHP library to link against based on ZTS
const PHPLibraryName = "php8" ++ if (UsingZTS) "ts" else "";
/// PHPDevelPath is the path to the PHP devel pack based on the PHP version & arch
// const PHPDevelPath = std.fmt.comptimePrint("php-devel-pack-{s}{s}-Win32-vs16-{s}", .{
//     PHPVersion,
//     if (!UsingZTS) "-nts" else "",
//     Arch,
// });
const PHPDevelPath = "php-devel-pack";
/// PHPDevelURL is the URL to the PHP devel pack based on the PHP version & arch
// const PHPDevelURL = std.fmt.comptimePrint("https://windows.php.net/downloads/releases/archives/{s}.zip", .{
//     PHPDevelPath,
// });

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

    // TODO: resolve segfault from this step
    // var devel_step = std.Build.Step.init(.{
    //     .id = .custom,
    //     .name = "Setup PHP devel pack",
    //     .makeFn = setupDevelPack,
    //     .owner = b,
    // });
    // lib.step.dependOn(&devel_step);

    inline for (PHPIncludePaths) |path| {
        lib.addIncludePath(std.fmt.comptimePrint("{s}/include/{s}", .{ PHPDevelPath, path }));
    }
    // include the library path for the PHP dll
    lib.addLibraryPath(std.fmt.comptimePrint("{s}/lib", .{PHPDevelPath}));
    // link the PHP lib file
    lib.linkSystemLibraryName(PHPLibraryName);
    // add the artifact
    const build_step = b.addInstallArtifact(lib);
    // run php
    const run_php = b.addSystemCommand(&.{
        "C:\\Users\\Matt\\Downloads\\php-8.2.7-Win32-vs16-x64\\php.exe",
        // "php",
        "-d",
        std.fmt.comptimePrint("extension=zig-out/lib/{s}", .{
            libraryName ++ switch (builtin.os.tag) {
                .windows => ".dll",
                .macos => ".dylib",
                else => ".so",
            },
        }),
        "examples/test.php",
    });
    // PHP run step depends on building to complete
    run_php.step.dependOn(&build_step.step);
    example_step.dependOn(&run_php.step);
}
