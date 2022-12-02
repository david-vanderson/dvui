const std = @import("std");
const Pkg = std.build.Pkg;
const Builder = @import("std").build.Builder;
const freetype = @import("libs/mach/libs/freetype/build.zig");

const mbedtls = @import("libs/zig-mbedtls/mbedtls.zig");
const libssh2 = @import("libs/zig-libssh2/libssh2.zig");
const libcurl = @import("libs/zig-libcurl/libcurl.zig");
const libzlib = @import("libs/zig-zlib/zlib.zig");
const libxml2 = @import("libs/zig-libxml2/libxml2.zig");

const Packages = struct {
    // Declared here because submodule may not be cloned at the time build.zig runs.
    const zmath = std.build.Pkg{
        .name = "zmath",
        .source = .{ .path = "libs/zmath/src/zmath.zig" },
    };
};

pub fn build(b: *Builder) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    // mach example
    {
        const name = "mach-test";
        const mach = @import("libs/mach/build.zig");
        const example_app = try mach.App.init(
            b,
            .{
                .name = "mach-test",
                .src = "mach-test.zig",
                .target = target,
                .deps = &[_]Pkg{ Packages.zmath, freetype.pkg },
            },
        );
        example_app.setBuildMode(mode);
        freetype.link(example_app.b, example_app.step, .{});
        try example_app.link(.{});

        const compile_step = b.step("compile-" ++ name, "Compile " ++ name);
        compile_step.dependOn(&b.addInstallArtifact(example_app.step).step);
        b.getInstallStep().dependOn(compile_step);

        const run_cmd = try example_app.run();
        run_cmd.dependOn(compile_step);

        const run_step = b.step(name, "Run " ++ name);
        run_step.dependOn(run_cmd);
    }

    // sdl test
    {
        const exe = b.addExecutable("sdl-test", "sdl-test" ++ ".zig");

        exe.addPackage(freetype.pkg);
        freetype.link(b, exe, .{});

        exe.linkSystemLibrary("SDL2");
        //exe.addIncludePath("/home/dvanderson/SDL/build/include");
        //exe.addObjectFile("/home/dvanderson/SDL/build/lib/libSDL2.a");

        if (target.isDarwin()) {
            exe.linkSystemLibrary("z");
            exe.linkSystemLibrary("bz2");
            exe.linkSystemLibrary("iconv");
            exe.linkFramework("AppKit");
            exe.linkFramework("AudioToolbox");
            exe.linkFramework("Carbon");
            exe.linkFramework("Cocoa");
            exe.linkFramework("CoreAudio");
            exe.linkFramework("CoreFoundation");
            exe.linkFramework("CoreGraphics");
            exe.linkFramework("CoreHaptics");
            exe.linkFramework("CoreVideo");
            exe.linkFramework("ForceFeedback");
            exe.linkFramework("GameController");
            exe.linkFramework("IOKit");
            exe.linkFramework("Metal");
        }

        exe.setTarget(target);
        exe.setBuildMode(mode);

        const compile_step = b.step("compile-" ++ "sdl-test", "Compile " ++ "sdl-test");
        compile_step.dependOn(&b.addInstallArtifact(exe).step);
        b.getInstallStep().dependOn(compile_step);

        const run_cmd = exe.run();
        run_cmd.step.dependOn(compile_step);

        const run_step = b.step("sdl-test", "Run " ++ "sdl-test");
        run_step.dependOn(&run_cmd.step);
    }

    // podcast example application
    {
        const exe = b.addExecutable("podcast", "podcast" ++ ".zig");
        exe.linkSystemLibrary("SDL2");

        exe.addPackage(freetype.pkg);
        freetype.link(b, exe, .{ .freetype = .{ .use_system_zlib = true } });

        const sqlite = b.addStaticLibrary("sqlite", null);
        sqlite.addCSourceFile("libs/zig-sqlite/c/sqlite3.c", &[_][]const u8{"-std=c99"});
        sqlite.linkLibC();

        exe.linkLibrary(sqlite);
        exe.addPackagePath("sqlite", "libs/zig-sqlite/sqlite.zig");
        exe.addIncludePath("libs/zig-sqlite/c");

        const tls = mbedtls.create(b, target, mode);
        tls.link(exe);

        const ssh2 = libssh2.create(b, target, mode);
        tls.link(ssh2.step);
        ssh2.link(exe);

        const zlib = libzlib.create(b, target, mode);
        zlib.link(exe, .{});

        const curl = try libcurl.create(b, target, mode);
        tls.link(curl.step);
        ssh2.link(curl.step);
        curl.link(exe, .{ .import_name = "curl" });

        const libxml = try libxml2.create(b, target, mode, .{
            .iconv = false,
            .lzma = false,
            .zlib = true,
        });

        libxml.link(exe);

        if (target.isDarwin()) {
            exe.linkSystemLibrary("z");
            exe.linkSystemLibrary("bz2");
            exe.linkSystemLibrary("iconv");
            exe.linkFramework("AppKit");
            exe.linkFramework("AudioToolbox");
            exe.linkFramework("Carbon");
            exe.linkFramework("Cocoa");
            exe.linkFramework("CoreAudio");
            exe.linkFramework("CoreFoundation");
            exe.linkFramework("CoreGraphics");
            exe.linkFramework("CoreHaptics");
            exe.linkFramework("CoreVideo");
            exe.linkFramework("ForceFeedback");
            exe.linkFramework("GameController");
            exe.linkFramework("IOKit");
            exe.linkFramework("Metal");
        }

        exe.setTarget(target);
        exe.setBuildMode(mode);

        const compile_step = b.step("compile-" ++ "podcast", "Compile " ++ "podcast");
        compile_step.dependOn(&b.addInstallArtifact(exe).step);
        b.getInstallStep().dependOn(compile_step);

        const run_cmd = exe.run();
        run_cmd.step.dependOn(compile_step);

        const run_step = b.step("podcast", "Run " ++ "podcast");
        run_step.dependOn(&run_cmd.step);
    }
}
