const std = @import("std");
const Pkg = std.Build.Pkg;
const Compile = std.Build.Step.Compile;

pub const BackendToBuild = enum {
    all,
    custom,
    sdl,
    raylib,
    dx11,
    web,
};

// NOTE: Keep in-sync with raylib's definition
pub const LinuxDisplayBackend = enum {
    X11,
    Wayland,
    Both,
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const back_to_build: BackendToBuild = b.option(BackendToBuild, "backend", "Backend to build") orelse .all;

    if (back_to_build == .custom) {
        // For export to users who are bringing their own backend.  Use in your build.zig:
        // const dvui_mod = dvui_dep.module("dvui");
        // @import("dvui").linkBackend(dvui_mod, your backend module);
        _ = addDvuiModule(b, target, optimize, "dvui", true);
    }

    // SDL
    if (back_to_build == .all or back_to_build == .sdl) {
        const sdl_mod = b.addModule("sdl", .{
            .root_source_file = b.path("src/backends/sdl.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });

        var sdl_options = b.addOptions();
        const compile_sdl3 = b.option(bool, "sdl3", "SDL3 instead of SDL2") orelse false;
        if (b.systemIntegrationOption("sdl2", .{})) {
            // SDL2 from system
            sdl_options.addOption(std.SemanticVersion, "version", .{ .major = 2, .minor = 0, .patch = 0 });
            sdl_mod.linkSystemLibrary("SDL2", .{});
        } else if (b.systemIntegrationOption("sdl3", .{})) {
            // SDL3 from system
            sdl_options.addOption(std.SemanticVersion, "version", .{ .major = 3, .minor = 0, .patch = 0 });
            sdl_mod.linkSystemLibrary("SDL3", .{});
        } else if (compile_sdl3) {
            // SDL3 compiled from source
            sdl_options.addOption(std.SemanticVersion, "version", .{ .major = 3, .minor = 0, .patch = 0 });
            if (b.lazyDependency("sdl3", .{
                .target = target,
                .optimize = optimize,
            })) |sdl3| {
                sdl_mod.linkLibrary(sdl3.artifact("SDL3"));
            }
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
                    sdl_mod.linkLibrary(sd.artifact("SDL2"));
                }
            } else {
                const sdl_dep = b.lazyDependency("sdl", .{ .target = target, .optimize = optimize });
                if (sdl_dep) |sd| {
                    sdl_mod.linkLibrary(sd.artifact("SDL2"));
                }
            }
        }
        sdl_mod.addOptions("sdl_options", sdl_options);

        const dvui_sdl = addDvuiModule(b, target, optimize, "dvui_sdl", true);
        linkBackend(dvui_sdl, sdl_mod);
        addExample(b, target, optimize, "sdl-standalone", b.path("examples/sdl-standalone.zig"), dvui_sdl);
        addExample(b, target, optimize, "sdl-ontop", b.path("examples/sdl-ontop.zig"), dvui_sdl);
        addExample(b, target, optimize, "sdl-app", b.path("examples/app.zig"), dvui_sdl);
    }

    // Raylib
    if (back_to_build == .all or back_to_build == .raylib) {
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

        const raylib_mod = b.addModule("raylib", .{
            .root_source_file = b.path("src/backends/raylib.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });

        const maybe_ray = b.lazyDependency(
            "raylib",
            .{
                .target = target,
                .optimize = optimize,
                .linux_display_backend = linux_display_backend,
            },
        );
        if (maybe_ray) |ray| {
            raylib_mod.linkLibrary(ray.artifact("raylib"));
            // This seems wonky to me, but is copied from raylib's src/build.zig
            if (b.lazyDependency("raygui", .{})) |raygui_dep| {
                if (b.lazyImport(@This(), "raylib")) |_| {
                    // we want to write this:
                    //raylib_build.addRaygui(b, ray.artifact("raylib"), raygui_dep);
                    // but that causes a second invocation of the raylib dependency but without our linux_display_backend
                    // so it defaults to .Both which causes an error if there is no wayland-scanner

                    const raylib = ray.artifact("raylib");
                    var gen_step = b.addWriteFiles();
                    raylib.step.dependOn(&gen_step.step);

                    const raygui_c_path = gen_step.add("raygui.c", "#define RAYGUI_IMPLEMENTATION\n#include \"raygui.h\"\n");
                    raylib.addCSourceFile(.{ .file = raygui_c_path });
                    raylib.addIncludePath(raygui_dep.path("src"));
                    raylib.addIncludePath(ray.path("src"));

                    raylib.installHeader(raygui_dep.path("src/raygui.h"), "raygui.h");
                }
            }
        }

        const dvui_raylib = addDvuiModule(b, target, optimize, "dvui_raylib", false);
        linkBackend(dvui_raylib, raylib_mod);
        addExample(b, target, optimize, "raylib-standalone", b.path("examples/raylib-standalone.zig"), dvui_raylib);
        addExample(b, target, optimize, "raylib-ontop", b.path("examples/raylib-ontop.zig"), dvui_raylib);
    }

    // Dx11
    if (back_to_build == .all or back_to_build == .dx11) {
        if (target.result.os.tag == .windows) {
            const dx11_mod = b.addModule("dx11", .{
                .root_source_file = b.path("src/backends/dx11.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            });

            if (b.lazyDependency("win32", .{})) |zigwin32| {
                dx11_mod.addImport("win32", zigwin32.module("win32"));
            }

            const dvui_dx11 = addDvuiModule(b, target, optimize, "dvui_dx11", true);
            linkBackend(dvui_dx11, dx11_mod);
            addExample(b, target, optimize, "dx11-standalone", b.path("examples/dx11-standalone.zig"), dvui_dx11);
            addExample(b, target, optimize, "dx11-ontop", b.path("examples/dx11-ontop.zig"), dvui_dx11);
        }
    }

    // Web
    if (back_to_build == .all or back_to_build == .web) {
        const web_target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        });

        const web_mod = b.addModule("WebBackend", .{
            .root_source_file = b.path("src/backends/web.zig"),
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

        const dvui_web = addDvuiModule(b, web_target, optimize, "dvui_web", true);
        linkBackend(dvui_web, web_mod);

        const web_test = b.addExecutable(.{
            .name = "web-test",
            .root_source_file = b.path("examples/web-test.zig"),
            .target = web_target,
            .optimize = optimize,
            .link_libc = false,
            .strip = if (optimize == .ReleaseFast or optimize == .ReleaseSmall) true else false,
        });

        web_test.entry = .disabled;
        web_test.root_module.addImport("dvui", dvui_web);

        const install_wasm = b.addInstallArtifact(web_test, .{
            .dest_dir = .{ .override = .{ .custom = "bin" } },
        });

        const cb = b.addExecutable(.{
            .name = "cacheBuster",
            .root_source_file = b.path("src/cacheBuster.zig"),
            .target = b.graph.host,
        });
        const cb_run = b.addRunArtifact(cb);
        cb_run.addFileArg(b.path("src/backends/index.html"));
        cb_run.addFileArg(b.path("src/backends/web.js"));
        cb_run.addFileArg(web_test.getEmittedBin());
        const output = cb_run.captureStdOut();

        const install_noto = b.addInstallBinFile(b.path("src/fonts/NotoSansKR-Regular.ttf"), "NotoSansKR-Regular.ttf");

        const compile_step = b.step("web-test", "Compile the Web test");
        compile_step.dependOn(&b.addInstallFileWithDir(output, .prefix, "bin/index.html").step);
        const web_js = b.path("src/backends/web.js");
        compile_step.dependOn(&b.addInstallFileWithDir(web_js, .prefix, "bin/web.js").step);
        b.addNamedLazyPath("web.js", web_js);
        compile_step.dependOn(&install_wasm.step);
        compile_step.dependOn(&install_noto.step);

        b.getInstallStep().dependOn(compile_step);
    }

    // Docs
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
        // Seems a bit drastic but by default only index.html is installed
        // and I override it below. Maybe there is a cleaner way ?
        .exclude_extensions = &.{".html"},
    });

    const docs_step = b.step("docs", "Build and install the documentation");
    docs_step.dependOn(&install_docs.step);

    b.getInstallStep().dependOn(docs_step);

    // Use customized index.html
    const add_doc_logo = b.addExecutable(.{
        .name = "addDocLogo",
        .root_source_file = b.path("docs/add_doc_logo.zig"),
        .target = b.graph.host,
    });
    const run_add_logo = b.addRunArtifact(add_doc_logo);
    run_add_logo.addFileArg(b.path("docs/index.html"));
    run_add_logo.addFileArg(b.path("docs/favicon.svg"));
    run_add_logo.addFileArg(b.path("docs/logo.svg"));
    const indexhtml_file = run_add_logo.captureStdOut();
    docs_step.dependOn(&b.addInstallFileWithDir(indexhtml_file, .prefix, "docs/index.html").step);
}

pub fn linkBackend(dvui_mod: *std.Build.Module, backend_mod: *std.Build.Module) void {
    backend_mod.addImport("dvui", dvui_mod);
    dvui_mod.addImport("backend", backend_mod);
}

fn addDvuiModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    comptime name: []const u8,
    add_stb_image: bool,
) *std.Build.Module {
    const dvui_mod = b.addModule(name, .{
        .root_source_file = b.path("src/dvui.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (target.result.os.tag == .windows) {
        // tinyfiledialogs needs this
        dvui_mod.linkSystemLibrary("comdlg32", .{});
        dvui_mod.linkSystemLibrary("ole32", .{});
    }

    dvui_mod.addIncludePath(b.path("src/stb"));

    if (target.result.cpu.arch == .wasm32) {
        dvui_mod.addCSourceFiles(.{
            .files = &.{
                "src/stb/stb_image_impl.c",
                "src/stb/stb_image_write_impl.c",
                "src/stb/stb_truetype_impl.c",
            },
            .flags = &.{ "-DINCLUDE_CUSTOM_LIBC_FUNCS=1", "-DSTBI_NO_STDLIB=1", "-DSTBIW_NO_STDLIB=1" },
        });
    } else {
        if (add_stb_image) {
            dvui_mod.addCSourceFiles(.{ .files = &.{
                "src/stb/stb_image_impl.c",
                "src/stb/stb_image_write_impl.c",
            } });
        }
        dvui_mod.addCSourceFiles(.{ .files = &.{"src/stb/stb_truetype_impl.c"} });

        dvui_mod.addIncludePath(b.path("src/tfd"));
        dvui_mod.addCSourceFiles(.{ .files = &.{"src/tfd/tinyfiledialogs.c"} });

        if (b.systemIntegrationOption("freetype", .{})) {
            dvui_mod.linkSystemLibrary("freetype2", .{});
        } else {
            const freetype_dep = b.lazyDependency("freetype", .{
                .target = target,
                .optimize = optimize,
            });
            if (freetype_dep) |fd| {
                dvui_mod.linkLibrary(fd.artifact("freetype"));
            }
        }
    }

    return dvui_mod;
}

fn addExample(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    comptime name: []const u8,
    file: std.Build.LazyPath,
    dvui_mod: *std.Build.Module,
) void {
    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = file,
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("dvui", dvui_mod);

    if (target.result.os.tag == .windows) {
        exe.win32_manifest = b.path("./src/main.manifest");
        exe.subsystem = .Windows;
        // TODO: This may just be only used for directx
        if (b.lazyDependency("win32", .{})) |zigwin32| {
            exe.root_module.addImport("win32", zigwin32.module("win32"));
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
