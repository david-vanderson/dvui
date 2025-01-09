const std = @import("std");
const Pkg = std.Build.Pkg;
const Compile = std.Build.Step.Compile;

pub const LinuxDisplayBackend = enum {
    X11,
    Wayland,
    Both,
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const link_backend = b.option(bool, "link_backend", "Should dvui link the chosen backend?") orelse true;
    const linux_display_backend: LinuxDisplayBackend = b.option(LinuxDisplayBackend, "linux_display_backend", "If using raylib, which linux display?") orelse blk: {
        _ = std.process.getEnvVarOwned(b.allocator, "WAYLAND_DISPLAY") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => break :blk .X11,
            else => @panic("Unknown error checking for WAYLAND_DISPLAY environment variable"),
        };

        _ = std.process.getEnvVarOwned(b.allocator, "DISPLAY") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => break :blk .Wayland,
            else => @panic("Unknown error checking for DISPLAY environment variable"),
        };

        break :blk .Both;
    };

    const dvui_sdl = addDvuiModule(b, target, optimize, link_backend, .sdl, linux_display_backend);
    const dvui_raylib = addDvuiModule(b, target, optimize, link_backend, .raylib, linux_display_backend);

    addExample(b, target, optimize, "sdl-standalone", dvui_sdl);
    addExample(b, target, optimize, "sdl-ontop", dvui_sdl);
    addExample(b, target, optimize, "raylib-standalone", dvui_raylib);
    addExample(b, target, optimize, "raylib-ontop", dvui_raylib);

    if (target.result.os.tag == .windows) {
        const dvui_dx11 = addDvuiModule(b, target, optimize, link_backend, .dx11, linux_display_backend);
        addExample(b, target, optimize, "dx11-ontop", dvui_dx11);
        addExample(b, target, optimize, "dx11-standalone", dvui_dx11);
    }

    // web test
    {
        const webtarget_library = std.Target.Query{
            .cpu_arch = .wasm32,
            .os_tag = .wasi,
            .abi = .musl,
        };
        const webtarget_exe = std.Target.Query{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
            .abi = .musl,
        };

        const dvui_mod_web = b.addModule("dvui_web", .{
            .root_source_file = b.path("src/dvui.zig"),
            .target = b.resolveTargetQuery(webtarget_library),
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
            .target = b.resolveTargetQuery(webtarget_exe),
            .optimize = optimize,
            .link_libc = true,
            .strip = if (optimize == .ReleaseFast or optimize == .ReleaseSmall) true else false,
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
            "gpa_u8",
            "gpa_free",
            "new_font",
        };

        wasm.root_module.addImport("WebBackend", web_mod);
        web_mod.addImport("dvui", dvui_mod_web);
        dvui_mod_web.addImport("backend", web_mod);

        const install_wasm = b.addInstallArtifact(wasm, .{
            .dest_dir = .{ .override = .{ .custom = "bin" } },
        });

        const cb = b.addExecutable(.{
            .name = "cacheBuster",
            .root_source_file = b.path("src/cacheBuster.zig"),
            .target = b.graph.host,
        });
        const cb_run = b.addRunArtifact(cb);
        cb_run.addFileArg(b.path("src/backends/index.html"));
        cb_run.addFileArg(b.path("src/backends/WebBackend.js"));
        cb_run.addFileArg(wasm.getEmittedBin());
        const output = cb_run.captureStdOut();

        const install_noto = b.addInstallBinFile(b.path("src/fonts/NotoSansKR-Regular.ttf"), "NotoSansKR-Regular.ttf");

        const compile_step = b.step("web-test", "Compile the Web test");
        compile_step.dependOn(&b.addInstallFileWithDir(output, .prefix, "bin/index.html").step);
        compile_step.dependOn(&b.addInstallFileWithDir(b.path("src/backends/WebBackend.js"), .prefix, "bin/WebBackend.js").step);
        compile_step.dependOn(&install_wasm.step);
        compile_step.dependOn(&install_noto.step);

        b.getInstallStep().dependOn(compile_step);
    }

    const docs = b.addObject(.{
        .name = "dvui",
        .root_source_file = b.path("src/dvui.zig"),
        .target = target,
        .optimize = optimize,
    });

    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Build and install the documentation");
    docs_step.dependOn(&install_docs.step);

    b.getInstallStep().dependOn(docs_step);
}

const Backend = enum {
    raylib,
    sdl,
    dx11,
};

fn addDvuiModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    link_backend: bool,
    comptime backend: Backend,
    linux_display_backend: LinuxDisplayBackend,
) *std.Build.Module {
    const dvui_mod = b.addModule("dvui_" ++ @tagName(backend), .{
        .root_source_file = b.path("src/dvui.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (target.result.os.tag == .windows) {
        // tinyfiledialogs needs this
        dvui_mod.linkSystemLibrary("comdlg32", .{});
        dvui_mod.linkSystemLibrary("ole32", .{});
    }

    const options = b.addOptions();
    options.addOption(Backend, "backend", backend);
    dvui_mod.addOptions("build_options", options);

    const backend_mod = b.addModule("backend_" ++ @tagName(backend), .{
        .root_source_file = b.path("src/backends/" ++ @tagName(backend) ++ "_backend.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = switch (backend) {
            .raylib => true,
            .sdl => true,
            .dx11 => true,
        },
    });

    backend_mod.addImport("dvui", dvui_mod);
    dvui_mod.addImport("backend", backend_mod);

    dvui_mod.addIncludePath(b.path("src/stb"));
    dvui_mod.addCSourceFiles(.{ .files = &.{
        "src/stb/stb_truetype_impl.c",
    } });

    dvui_mod.addIncludePath(b.path("src/tfd"));
    dvui_mod.addCSourceFiles(.{ .files = &.{
        "src/tfd/tinyfiledialogs.c",
    } });

    if (link_backend) {
        switch (backend) {
            .raylib => {
                const maybe_ray = b.lazyDependency(
                    "raylib",
                    .{
                        .target = target,
                        .optimize = optimize,
                        .linux_display_backend = linux_display_backend,
                    },
                );
                if (maybe_ray) |ray| {
                    backend_mod.linkLibrary(ray.artifact("raylib"));
                    // This seems wonky to me, but is copied from raylib's src/build.zig
                    if (b.lazyDependency("raygui", .{})) |raygui_dep| {
                        if (b.lazyImport(@This(), "raylib")) |raylib_build| {
                            raylib_build.addRaygui(b, ray.artifact("raylib"), raygui_dep);
                        }
                    }
                }
            },
            .sdl => {
                dvui_mod.addCSourceFiles(.{ .files = &.{
                    "src/stb/stb_image_impl.c",
                } });
                var sdl_options = b.addOptions();
                if (b.systemIntegrationOption("sdl2", .{})) {
                    // SDL2 from system
                    sdl_options.addOption(std.SemanticVersion, "version", .{ .major = 2, .minor = 0, .patch = 0 });
                    backend_mod.linkSystemLibrary("SDL2", .{});
                } else if (b.option(bool, "sdl3", "Use SDL3 compiled from source") orelse false) {
                    // SDL3 compiled from source
                    sdl_options.addOption(std.SemanticVersion, "version", .{ .major = 3, .minor = 0, .patch = 0 });
                    if (b.lazyDependency("sdl3", .{})) |sdl3| {
                        backend_mod.linkLibrary(sdl3.artifact("sdl3"));
                        backend_mod.addImport("sdl3_c", sdl3.module("sdl"));
                    }
                } else if (b.systemIntegrationOption("sdl3", .{})) {
                    // SDL3 from system
                    sdl_options.addOption(std.SemanticVersion, "version", .{ .major = 3, .minor = 0, .patch = 0 });
                    sdl_options.addOption(bool, "from_system", true);
                    backend_mod.linkSystemLibrary("SDL3", .{});
                } else {
                    // SDL2 compiled from source
                    sdl_options.addOption(std.SemanticVersion, "version", .{ .major = 2, .minor = 0, .patch = 0 });
                    if (target.result.os.tag == .linux) {
                        const sdl_dep = b.lazyDependency("sdl", .{
                            .target = target,
                            .optimize = optimize,
                            // trying to compile opengles (version 1) fails on
                            // newer linux distros like arch, because they don't
                            // have /usr/include/gles/gl.h
                            // https://github.com/david-vanderson/dvui/issues/131
                            .render_driver_ogl_es = false,
                        });
                        if (sdl_dep) |sd| {
                            backend_mod.linkLibrary(sd.artifact("SDL2"));
                        }
                    } else {
                        const sdl_dep = b.lazyDependency("sdl", .{ .target = target, .optimize = optimize });
                        if (sdl_dep) |sd| {
                            backend_mod.linkLibrary(sd.artifact("SDL2"));
                        }
                    }
                }
                backend_mod.addOptions("sdl_options", sdl_options);
            },
            .dx11 => {
                dvui_mod.addCSourceFiles(.{ .files = &.{
                    "src/stb/stb_image_impl.c",
                } });

                if (b.lazyDependency("zigwin32", .{})) |zigwin32| {
                    backend_mod.addImport("zigwin32", zigwin32.module("zigwin32"));
                }
            },
        }
    }

    if (b.systemIntegrationOption("freetype", .{})) {
        dvui_mod.linkSystemLibrary("freetype", .{});
    } else {
        const freetype_dep = b.lazyDependency("freetype", .{
            .target = target,
            .optimize = optimize,
        });
        if (freetype_dep) |fd| {
            dvui_mod.linkLibrary(fd.artifact("freetype"));
        }
    }
    return dvui_mod;
}

fn addExample(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    comptime name: []const u8,
    dvui_mod: *std.Build.Module,
) void {
    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = b.path("examples/" ++ name ++ ".zig"),
        .target = target,
        .optimize = optimize,
        .win32_manifest = b.path("./src/main.manifest"),
    });
    exe.root_module.addImport("dvui", dvui_mod);

    if (target.result.os.tag == .windows) {
        exe.subsystem = .Windows;
        // TODO: This may just be only used for directx
        if (b.lazyDependency("zigwin32", .{})) |zigwin32| {
            exe.root_module.addImport("zigwin32", zigwin32.module("zigwin32"));
        }
    }

    const compile_step = b.step("compile-" ++ name, "Compile " ++ name);
    compile_step.dependOn(&b.addInstallArtifact(exe, .{}).step);
    b.getInstallStep().dependOn(compile_step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(compile_step);

    const run_step = b.step(name, "Run " ++ name);
    run_step.dependOn(&run_cmd.step);
}

// mach example build code
// note: Disabled currently until mach backend is updated
//
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
// }
