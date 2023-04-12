const std = @import("std");
const Pkg = std.build.Pkg;

const Packages = struct {
    // Declared here because submodule may not be cloned at the time build.zig runs.
    const zmath = std.build.Pkg{
        .name = "zmath",
        .source = .{ .path = "libs/zmath/src/zmath.zig" },
    };
};

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gui_mod = b.addModule("gui", .{
        .source_file = .{ .path = "src/gui.zig" },
        .dependencies = &.{},
    });

    const sdl_mod = b.addModule("SDLBackend", .{
        .source_file = .{ .path = "src/SDLBackend.zig" },
        .dependencies = &.{
            .{ .name = "gui", .module = gui_mod },
        },
    });

    // mach example
    //{
    //    const name = "mach-test";
    //    const mach = @import("libs/mach/build.zig");
    //    const example_app = try mach.App.init(
    //        b,
    //        .{
    //            .name = "mach-test",
    //            .src = "mach-test.zig",
    //            .target = target,
    //            .deps = &[_]Pkg{ Packages.zmath, freetype.pkg },
    //        },
    //    );
    //    example_app.setBuildMode(mode);
    //    freetype.link(example_app.b, example_app.step, .{});
    //    try example_app.link(.{});

    //    const compile_step = b.step("compile-" ++ name, "Compile " ++ name);
    //    compile_step.dependOn(&b.addInstallArtifact(example_app.step).step);
    //    b.getInstallStep().dependOn(compile_step);

    //    const run_cmd = try example_app.run();
    //    run_cmd.dependOn(compile_step);

    //    const run_step = b.step(name, "Run " ++ name);
    //    run_step.dependOn(run_cmd);
    //}

    const examples = [_][]const u8{
        "standalone-sdl",
        "ontop-sdl",
    };

    inline for (examples) |ex| {
        const exe = b.addExecutable(.{
            .name = ex,
            .root_source_file = .{ .path = ex ++ ".zig" },
            .target = target,
            .optimize = optimize,
        });

        exe.addModule("gui", gui_mod);
        exe.addModule("SDLBackend", sdl_mod);
        const freetype_dep = b.dependency("freetype", .{
            .target = target,
            .optimize = optimize,
        });
        exe.linkLibrary(freetype_dep.artifact("freetype"));

        exe.linkSystemLibrary("SDL2");
        exe.linkLibC();

        const compile_step = b.step(ex, "Compile " ++ ex);
        compile_step.dependOn(&b.addInstallArtifact(exe).step);
        b.getInstallStep().dependOn(compile_step);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(compile_step);

        const run_step = b.step("run-" ++ ex, "Run " ++ ex);
        run_step.dependOn(&run_cmd.step);
    }

    // sdl test
    {
        const exe = b.addExecutable(.{
            .name = "sdl-test",
            .root_source_file = .{ .path = "sdl-test" ++ ".zig" },
            .target = target,
            .optimize = optimize,
        });

        exe.addModule("gui", gui_mod);
        exe.addModule("SDLBackend", sdl_mod);

        const freetype_dep = b.dependency("freetype", .{
            .target = target,
            .optimize = optimize,
        });
        exe.linkLibrary(freetype_dep.artifact("freetype"));

        //const sdl_dep = b.dependency("sdl", .{
        //.target = target,
        //.optimize = optimize,
        //});
        //exe.linkLibrary(sdl_dep.artifact("SDL2"));

        exe.linkSystemLibrary("SDL2");
        //exe.addIncludePath("/home/dvanderson/code/SDL/zig-out/include");
        //exe.addObjectFile("/home/dvanderson/code/SDL/zig-out/lib/libSDL2.a");

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

        const compile_step = b.step("compile-" ++ "sdl-test", "Compile " ++ "sdl-test");
        compile_step.dependOn(&b.addInstallArtifact(exe).step);
        b.getInstallStep().dependOn(compile_step);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(compile_step);

        const run_step = b.step("sdl-test", "Run " ++ "sdl-test");
        run_step.dependOn(&run_cmd.step);
    }
}
