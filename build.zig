const std = @import("std");
const Pkg = std.Build.Pkg;
const Compile = std.Build.Step.Compile;

const Packages = struct {
    // Declared here because submodule may not be cloned at the time build.zig runs.
    const zmath = Pkg{
        .name = "zmath",
        .source = .{ .path = "libs/zmath/src/zmath.zig" },
    };
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_bundle = b.addStaticLibrary(.{
        .name = "dvui_libs",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    link_deps(b, lib_bundle);
    b.installArtifact(lib_bundle);

    const dvui_mod = b.addModule("dvui", .{
        .source_file = .{ .path = "src/dvui.zig" },
        .dependencies = &.{},
    });

    const sdl_mod = b.addModule("SDLBackend", .{
        .source_file = .{ .path = "src/backends/SDLBackend.zig" },
        .dependencies = &.{
            .{ .name = "dvui", .module = dvui_mod },
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

        exe.addModule("dvui", dvui_mod);
        exe.addModule("SDLBackend", sdl_mod);

        exe.linkLibrary(lib_bundle);
        add_include_paths(b, exe);

        const compile_step = b.step(ex, "Compile " ++ ex);
        compile_step.dependOn(&b.addInstallArtifact(exe, .{}).step);
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
            .root_source_file = .{ .path = "sdl-test.zig" },
            .target = target,
            .optimize = optimize,
        });

        exe.addModule("dvui", dvui_mod);
        exe.addModule("SDLBackend", sdl_mod);

        exe.linkLibrary(lib_bundle);
        add_include_paths(b, exe);

        const compile_step = b.step("compile-sdl-test", "Compile the SDL test");
        compile_step.dependOn(&b.addInstallArtifact(exe, .{}).step);
        b.getInstallStep().dependOn(compile_step);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(compile_step);

        const run_step = b.step("sdl-test", "Run the SDL test");
        run_step.dependOn(&run_cmd.step);
    }
}

pub fn link_deps(b: *std.Build, exe: *std.Build.Step.Compile) void {
    exe.addCSourceFile(.{ .file = .{ .path = "src/ok_color.c" }, .flags = &.{} });
    // TODO: remove this part about freetype (pulling it from the dvui_dep
    // sub-builder) once https://github.com/ziglang/zig/pull/14731 lands
    const freetype_dep = b.dependency("freetype", .{
        .target = exe.target,
        .optimize = exe.optimize,
    });
    exe.linkLibrary(freetype_dep.artifact("freetype"));

    // TODO: remove this part about stb_image once either:
    // - zig can successfully cimport stb_image.h
    // - zig can have a module depend on a c file
    const stbi_dep = b.dependency("stb_image", .{
        .target = exe.target,
        .optimize = exe.optimize,
    });
    exe.linkLibrary(stbi_dep.artifact("stb_image"));

    exe.linkLibC();

    if (exe.target.isWindows()) {
        const sdl_dep = b.dependency("sdl", .{
            .target = exe.target,
            .optimize = exe.optimize,
        });
        exe.linkLibrary(sdl_dep.artifact("SDL2"));

        exe.linkSystemLibrary("setupapi");
        exe.linkSystemLibrary("winmm");
        exe.linkSystemLibrary("gdi32");
        exe.linkSystemLibrary("imm32");
        exe.linkSystemLibrary("version");
        exe.linkSystemLibrary("oleaut32");
        exe.linkSystemLibrary("ole32");
    } else {
        if (exe.target.isDarwin()) {
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

        exe.linkSystemLibrary("SDL2");
        //exe.addIncludePath(.{.path = "/Users/dvanderson/SDL2-2.24.1/include"});
        //exe.addObjectFile(.{.path = "/Users/dvanderson/SDL2-2.24.1/build/.libs/libSDL2.a"});
    }
}

const build_runner = @import("root");
const deps = build_runner.dependencies;

pub fn get_dependency_build_root(dep_prefix: []const u8, name: []const u8) []const u8 {
    inline for (@typeInfo(deps.imports).Struct.decls) |decl| {
        if (std.mem.startsWith(u8, decl.name, dep_prefix) and
            std.mem.endsWith(u8, decl.name, name) and
            decl.name.len == dep_prefix.len + name.len)
        {
            return @field(deps.build_root, decl.name);
        }
    }

    std.debug.print("no dependency named '{s}'\n", .{name});
    std.process.exit(1);
}

/// prefix: library prefix. e.g. "dvui."
pub fn add_include_paths(b: *std.Build, exe: *std.Build.CompileStep) void {
    exe.addIncludePath(.{ .path = "src" });
    exe.addIncludePath(.{ .path = b.fmt("{s}{s}", .{ get_dependency_build_root(b.dep_prefix, "freetype"), "/include" }) });
    exe.addIncludePath(.{ .path = b.fmt("{s}{s}", .{ get_dependency_build_root(b.dep_prefix, "stb_image"), "/include" }) });
}
