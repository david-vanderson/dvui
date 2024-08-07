const std = @import("std");
const Pkg = std.Build.Pkg;
const Compile = std.Build.Step.Compile;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dvui_mod = b.addModule("dvui", .{
        .root_source_file = b.path("src/dvui.zig"),
        .target = target,
        .optimize = optimize,
    });

    dvui_mod.addCSourceFiles(.{
        .files = &.{
            "src/stb/stb_image_impl.c",
            "src/stb/stb_truetype_impl.c",
        },
    });

    dvui_mod.addIncludePath(b.path("src/stb"));

    // need a separate module that doesn't include stb_image since raylib
    // bundles it (otherwise duplicate symbols)
    const dvui_mod_raylib = b.addModule("dvui_raylib", .{
        .root_source_file = b.path("src/dvui.zig"),
        .target = target,
        .optimize = optimize,
    });

    dvui_mod_raylib.addCSourceFiles(.{
        .files = &.{
            "src/stb/stb_truetype_impl.c",
        },
    });

    dvui_mod_raylib.addIncludePath(b.path("src/stb"));

    if (b.systemIntegrationOption("freetype", .{})) {
        dvui_mod.linkSystemLibrary("freetype", .{});
        dvui_mod_raylib.linkSystemLibrary("freetype", .{});
    } else {
        const freetype_dep = b.lazyDependency("freetype", .{
            .target = target,
            .optimize = optimize,
        });

        if (freetype_dep) |fd| {
            dvui_mod.linkLibrary(fd.artifact("freetype"));
            dvui_mod_raylib.linkLibrary(fd.artifact("freetype"));
        }
    }

    const sdl_mod = b.addModule("SDLBackend", .{
        .root_source_file = b.path("src/backends/SDLBackend.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sdl_mod.addImport("dvui", dvui_mod);

    if (b.systemIntegrationOption("sdl2", .{}) or target.result.os.tag == .linux) {
        sdl_mod.linkSystemLibrary("SDL2", .{});
    } else {
        const sdl_dep = b.lazyDependency("sdl", .{
            .target = target,
            .optimize = optimize,
        });

        if (sdl_dep) |sd| {
            sdl_mod.linkLibrary(sd.artifact("SDL2"));
        }
    }

    // EXPERIMENTAL: for now I make a raylib symlink that points to the raylib git checkout
    const raylib_mod = b.addModule("RaylibBackend", .{
        .root_source_file = b.path("src/backends/RaylibBackend.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    raylib_mod.addImport("dvui", dvui_mod_raylib);
    raylib_mod.addIncludePath(b.path("raylib/src"));
    raylib_mod.addObjectFile(b.path("raylib/src/libraylib.a"));
    raylib_mod.linkSystemLibrary("GL", .{});
    // TODO: systemIntegration for raylib
    // In the future we'll use something like this:
    //const ray = b.lazyDependency("raylib", .{ .target = target, .optimize = optimize });
    //dvui_mod_raylib.linkLibrary(ray.?.artifact("raylib"));
    //raylib_mod.linkLibrary(ray.?.artifact("raylib"));
    //raylib_mod.addIncludePath(ray.?.path("src"));

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

    const sdl_examples = [_][]const u8{
        "sdl-standalone",
        "sdl-ontop",
    };

    inline for (sdl_examples) |ex| {
        const exe = b.addExecutable(.{
            .name = ex,
            .root_source_file = b.path("examples/" ++ ex ++ ".zig"),
            .target = target,
            .optimize = optimize,
        });

        exe.root_module.addImport("dvui", dvui_mod);
        exe.root_module.addImport("SDLBackend", sdl_mod);

        const compile_step = b.step("compile-" ++ ex, "Compile " ++ ex);
        compile_step.dependOn(&b.addInstallArtifact(exe, .{}).step);
        b.getInstallStep().dependOn(compile_step);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(compile_step);

        const run_step = b.step(ex, "Run " ++ ex);
        run_step.dependOn(&run_cmd.step);
    }

    // raylib example
    {
        const exe = b.addExecutable(.{
            .name = "raylib-standalone",
            .root_source_file = b.path("examples/raylib-standalone.zig"),
            .target = target,
            .optimize = optimize,
        });

        exe.root_module.addImport("dvui", dvui_mod_raylib);
        exe.root_module.addImport("RaylibBackend", raylib_mod);

        const exe_install = b.addInstallArtifact(exe, .{});

        const compile_step = b.step("compile-raylib-standalone", "Compile the Raylib standalone example");
        compile_step.dependOn(&exe_install.step);
        // not ready for this to be in a standard zig build
        //b.getInstallStep().dependOn(compile_step);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(compile_step);

        const run_step = b.step("raylib-standalone", "Run the Raylib standalone example");
        run_step.dependOn(&run_cmd.step);
    }

    // web test
    {
        const webtarget = std.Target.Query{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
            .abi = .musl,
        };

        const dvui_mod_web = b.addModule("dvui_web", .{
            .root_source_file = b.path("src/dvui.zig"),
            .target = b.resolveTargetQuery(webtarget),
            .optimize = optimize,
        });

        dvui_mod_web.addCSourceFiles(.{
            .files = &.{
                "src/stb/stb_image_impl.c",
                "src/stb/stb_truetype_impl.c",
            },
            .flags = &.{"-DINCLUDE_CUSTOM_LIBC_FUNCS=1"},
        });

        dvui_mod_web.addIncludePath(b.path("src/stb"));

        const wasm = b.addExecutable(.{
            .name = "web-test",
            .root_source_file = b.path("examples/web-test.zig"),
            .target = b.resolveTargetQuery(webtarget),
            .optimize = optimize,
            .link_libc = true,
        });

        wasm.entry = .disabled;

        wasm.root_module.addImport("dvui", dvui_mod_web);

        const web_mod = b.addModule("WebBackend", .{
            .root_source_file = b.path("src/backends/WebBackend.zig"),
        });

        web_mod.export_symbol_names = &[_][]const u8{
            "app_init",
            "app_deinit",
            "app_update",
            "add_event",
            "arena_u8",
        };

        wasm.root_module.addImport("WebBackend", web_mod);
        web_mod.addImport("dvui", dvui_mod_web);

        const install_wasm = b.addInstallArtifact(wasm, .{
            .dest_dir = .{ .override = .{ .custom = "bin" } },
        });

        const cb = b.addExecutable(.{
            .name = "cacheBuster",
            .root_source_file = b.path("src/cacheBuster.zig"),
            .target = b.host,
        });
        const cb_run = b.addRunArtifact(cb);
        cb_run.addFileArg(b.path("src/backends/index.html"));
        cb_run.addFileArg(b.path("src/backends/WebBackend.js"));
        cb_run.addFileArg(wasm.getEmittedBin());
        const output = cb_run.captureStdOut();

        const compile_step = b.step("web-test", "Compile the Web test");
        compile_step.dependOn(&b.addInstallFileWithDir(output, .prefix, "bin/index.html").step);
        compile_step.dependOn(&b.addInstallFileWithDir(b.path("src/backends/WebBackend.js"), .prefix, "bin/WebBackend.js").step);
        compile_step.dependOn(&install_wasm.step);

        b.getInstallStep().dependOn(compile_step);
    }
}
