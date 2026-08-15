const std = @import("std");
const dvui_build = @import("dvui");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Point these at an iOS SDK, e.g.:
    //   -Dsystem_include_path=$(xcrun --sdk iphoneos --show-sdk-path)/usr/include
    //   -Dsystem_framework_path=$(xcrun --sdk iphoneos --show-sdk-path)/System/Library/Frameworks
    //   -Dlibrary_path=$(xcrun --sdk iphoneos --show-sdk-path)/usr/lib
    // (swap iphoneos for iphonesimulator when targeting the simulator). See ../README.md.
    const system_include_path = b.option(std.Build.LazyPath, "system_include_path", "iOS SDK usr/include path");
    const system_framework_path = b.option(std.Build.LazyPath, "system_framework_path", "iOS SDK System/Library/Frameworks path");
    const library_path = b.option(std.Build.LazyPath, "library_path", "iOS SDK usr/lib path");

    const dvui_dep = b.dependency("dvui", .{
        .target = target,
        .optimize = optimize,
        .backend = .sdl3,
        .system_include_path = system_include_path,
        .system_framework_path = system_framework_path,
        .library_path = library_path,
    });
    const dvui = dvui_dep.module("dvui_sdl3");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addImport("dvui", dvui);
    mod.addIncludePath(dvui_dep.namedLazyPath("sdl3_include"));
    if (system_include_path) |p| mod.addSystemIncludePath(p);

    const lib = b.addLibrary(.{
        .name = "dvui_ios_hello",
        .root_module = mod,
    });
    lib.bundle_compiler_rt = true;
    lib.root_module.strip = true;

    const lib_step = b.step("lib", "Build a static lib for the Xcode project to link");
    lib_step.dependOn(&b.addInstallArtifact(lib, .{}).step);
    // Installs the SDL3 static lib + headers dvui was built against, so Xcode's
    // HEADER_SEARCH_PATHS / linked .a have real files on disk at a fixed, checkout-relative
    // path -- no need to know which SDL3 fork dvui uses or depend on it directly.
    dvui_build.installIosSdl3(b, dvui_dep, lib_step);
}
