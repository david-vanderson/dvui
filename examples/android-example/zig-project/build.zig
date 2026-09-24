const std = @import("std");
const dvui_build = @import("dvui");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // e.g. -Dandroid_include_path=$ANDROID_HOME/ndk/<version>/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/include
    const android_include_path = b.option(std.Build.LazyPath, "android_include_path", "NDK sysroot usr/include path");

    const dvui_dep = b.dependency("dvui", .{
        .target = target,
        .optimize = optimize,
        .backend = .sdl3,
        .android_include_path = android_include_path,
    });
    const dvui = dvui_dep.module("dvui_sdl3");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .pic = true, // linked into the app's JNI .so
    });
    mod.addImport("dvui", dvui);

    {
        const sdl_hello_lib = b.addLibrary(.{
            .name = "sdl_hello",
            .root_module = mod,
        });
        // Debug C code (SDL, stb) calls __ubsan_handle_*; the NDK linker has no zig ubsan
        // runtime, so ship it inside this archive.
        sdl_hello_lib.bundle_ubsan_rt = true;
        sdl_hello_lib.bundle_compiler_rt = true; // ubsan_rt needs __extendxftf2, which the NDK lacks

        const lib_step = b.step("lib", "Install libsdl_hello.a + libSDL3.a + SDL's Java sources for the Android project");
        lib_step.dependOn(&b.addInstallArtifact(sdl_hello_lib, .{}).step);
        // SDL3 built from source: the Android project links this libSDL3.a and compiles
        // these Java sources, so native and Java SDL always come from the same version.
        dvui_build.installAndroidSdl3(b, dvui_dep, lib_step);
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
