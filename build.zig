const std = @import("std");
const Pkg = std.build.Pkg;
const Builder = @import("std").build.Builder;
const freetype = @import("libs/mach-freetype/build.zig");

const Packages = struct {
    // Declared here because submodule may not be cloned at the time build.zig runs.
    const zmath = std.build.Pkg{
        .name = "zmath",
        .source = .{ .path = "libs/zmath/src/zmath.zig" },
    };
};

pub fn build(b: *Builder) void {
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
        const example_app = mach.App.init(
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
        example_app.link(.{});

        const compile_step = b.step("compile-" ++ name, "Compile " ++ name);
        compile_step.dependOn(&b.addInstallArtifact(example_app.step).step);
        b.getInstallStep().dependOn(compile_step);

        const run_cmd = example_app.run();
        run_cmd.step.dependOn(compile_step);

        const run_step = b.step(name, "Run " ++ name);
        run_step.dependOn(&run_cmd.step);
    }

    // sdl apps
    inline for ([2][]const u8{"sdl-test", "podcast"}) |name| {
        const exe = b.addExecutable(name, name ++ ".zig");
        exe.addIncludeDir("/usr/local/include");
        exe.defineCMacro("_THREAD_SAFE", "1");
        exe.addLibPath("/usr/local/lib");
        exe.linkSystemLibrary("SDL2");

        exe.addPackage(freetype.pkg);
        freetype.link(b, exe, .{});

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

        exe.setTarget(target);
        exe.setBuildMode(mode);

        const compile_step = b.step("compile-" ++ name, "Compile " ++ name);
        compile_step.dependOn(&b.addInstallArtifact(exe).step);
        b.getInstallStep().dependOn(compile_step);

        const run_cmd = exe.run();
        run_cmd.step.dependOn(compile_step);

        const run_step = b.step(name, "Run " ++ name);
        run_step.dependOn(&run_cmd.step);
    }
}
