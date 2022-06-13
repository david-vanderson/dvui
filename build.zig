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
    const zigimg = std.build.Pkg{
        .name = "zigimg",
        .source = .{ .path = "libs/zigimg/zigimg.zig" },
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


    if (true) {
      const mach = @import("libs/mach/build.zig");
      const example_app = mach.App.init(
          b,
          .{
              .name = "mach-gui-test",
              .src = "mach-gui-test.zig",
              .target = target,
              .deps = &[_]Pkg{ Packages.zmath, freetype.freetype_pkg },
          },
      );
      example_app.setBuildMode(mode);
      freetype.link(example_app.b, example_app.step, .{});
      example_app.link(.{});
      example_app.install();
      const example_run_cmd = example_app.run();
      example_run_cmd.step.dependOn(&example_app.getInstallStep().?.step);
      const example_run_step = b.step("run-mach-gui-test", "Run mach-gui-test example");
      example_run_step.dependOn(&example_run_cmd.step);
    }

    if (true)
    {
      const exe = b.addExecutable("gui-test", "gui-test.zig");
      exe.addIncludeDir("/usr/local/include");
      exe.defineCMacro("_THREAD_SAFE", "1");
      exe.addLibPath("/usr/local/lib");
      exe.linkSystemLibrary("SDL2");
      //exe.linkSystemLibrary("SDL2_image");
      //exe.linkSystemLibrary("SDL2_ttf");

      exe.addPackage(freetype.freetype_pkg);
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
      exe.install();

      const run_cmd = exe.run();
      run_cmd.step.dependOn(b.getInstallStep());
      if (b.args) |args| {
          run_cmd.addArgs(args);
      }

      const run_step = b.step("gui-test", "Run gui-test");
      run_step.dependOn(&run_cmd.step);
    }

    if (false)
    {
      const exe = b.addExecutable("podcast", "podcast.zig");
      exe.addIncludeDir("/usr/local/include");
      exe.defineCMacro("_THREAD_SAFE", "1");
      exe.addLibPath("/usr/local/lib");
      exe.linkSystemLibrary("SDL2");
      //exe.linkSystemLibrary("SDL2_image");

      exe.addPackage(freetype.freetype_pkg);
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
      exe.install();

      const run_cmd = exe.run();
      run_cmd.step.dependOn(b.getInstallStep());
      if (b.args) |args| {
          run_cmd.addArgs(args);
      }

      const run_step = b.step("podcast", "Run Podcast");
      run_step.dependOn(&run_cmd.step);
    }
}
