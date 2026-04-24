const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const android_include_path: std.Build.LazyPath = .{ .cwd_relative = "/Users/shehabellithy/Library/Android/sdk/ndk/27.0.12077973/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/include" };

    const dvui = b.dependency("dvui", .{
        .target = target,
        .optimize = optimize,
        .backend = .sdl3,
        .android_include_path = android_include_path,
    }).module("dvui_sdl3");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("dvui", dvui);

    {
        const sdl_hello_lib = b.addLibrary(.{
            .name = "sdl_hello",
            .root_module = mod,
        });

        b.step("lib", "Install a lib").dependOn(&b.addInstallArtifact(sdl_hello_lib, .{}).step);
    }

    {
        const exe = b.addExecutable(.{
            .name = "sdl_hello",
            .root_module = mod,
        });

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| run_cmd.addArgs(args);

        b.step("run", "Run the app").dependOn(&run_cmd.step);
    }
}
