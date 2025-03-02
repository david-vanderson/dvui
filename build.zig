const std = @import("std");
const Pkg = std.Build.Pkg;
const Compile = std.Build.Step.Compile;

// NOTE: Keep in-sync with raylib's definition
pub const LinuxDisplayBackend = enum {
    X11,
    Wayland,
    Both,
};

const Backend = enum {
    raylib,
    sdl,
    dx11,
    web,
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const backend = b.option(Backend, "backend", "Set the chosen backend (default is SDL)") orelse .sdl;
    const standalone = b.option(bool, "standalone", "Whether to launch example standalone or ontop") orelse true;
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

    // DVUI mod
    const dvui_mod = b.addModule("dvui", .{
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
    dvui_mod.addOptions("build_options", options);
    dvui_mod.addIncludePath(b.path("src/stb"));

    if (target.result.cpu.arch == .wasm32) {
        dvui_mod.addCSourceFiles(.{
            .files = &.{"src/stb/stb_truetype_impl.c"},
            .flags = &.{ "-DINCLUDE_CUSTOM_LIBC_FUNCS=1", "-DSTBI_NO_STDLIB=1", "-DSTBIW_NO_STDLIB=1" },
        });
    } else {
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

    // backend mod
    const backend_mod_name = "dvui_default_backend";
    const backend_path = std.mem.concat(b.allocator, u8, &.{ "src/backends/", @tagName(backend), ".zig" }) catch @panic("OOM");
    const backend_mod = b.addModule(backend_mod_name, .{
        .root_source_file = b.path(backend_path),
        .target = target,
        .optimize = optimize,
        .link_libc = switch (backend) {
            .web, .sdl, .dx11, .raylib => true,
        },
    });
    backend_mod.addImport("dvui", dvui_mod);

    dvui_mod.addImport(backend_mod_name, backend_mod);

    switch (backend) {
        .raylib => {
            if (target.result.os.tag == .macos) {
                std.debug.panic("Invalid backend ({s}) choosen on os {s}", .{ @tagName(backend), @tagName(target.result.os.tag) });
            }

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
        },
        .sdl => {
            backend_mod.addCSourceFiles(.{ .files = &.{
                "src/stb/stb_image_impl.c",
                "src/stb/stb_image_write_impl.c",
            } });
            var sdl_options = b.addOptions();
            const compile_sdl3 = b.option(bool, "sdl3", "Use SDL3 compiled from source") orelse false;
            if (b.systemIntegrationOption("sdl2", .{})) {
                // SDL2 from system
                sdl_options.addOption(std.SemanticVersion, "version", .{ .major = 2, .minor = 0, .patch = 0 });
                backend_mod.linkSystemLibrary("SDL2", .{});
            } else if (b.systemIntegrationOption("sdl3", .{})) {
                // SDL3 from system
                sdl_options.addOption(std.SemanticVersion, "version", .{ .major = 3, .minor = 0, .patch = 0 });
                backend_mod.linkSystemLibrary("SDL3", .{});
            } else if (compile_sdl3) {
                // SDL3 compiled from source
                sdl_options.addOption(std.SemanticVersion, "version", .{ .major = 3, .minor = 0, .patch = 0 });
                if (b.lazyDependency("sdl3", .{
                    .target = target,
                    .optimize = optimize,
                })) |sdl3| {
                    backend_mod.linkLibrary(sdl3.artifact("SDL3"));
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
            if (target.result.os.tag != .windows) {
                std.debug.panic("Invalid backend ({s}) chosen on os {s}", .{ @tagName(backend), @tagName(target.result.os.tag) });
            }

            backend_mod.addCSourceFiles(.{ .files = &.{
                "src/stb/stb_image_impl.c",
                "src/stb/stb_image_write_impl.c",
            } });

            if (b.lazyDependency("zigwin32", .{})) |zigwin32| {
                backend_mod.addImport("zigwin32", zigwin32.module("zigwin32"));
            }
        },
        .web => {
            if (target.result.cpu.arch != .wasm32) {
                std.debug.panic("Invalid backend ({s}) chosen on os {s}", .{ @tagName(backend), @tagName(target.result.os.tag) });
            }

            dvui_mod.addCSourceFiles(.{
                .files = &.{
                    "src/stb/stb_image_impl.c",
                    "src/stb/stb_image_write_impl.c",
                },
                .flags = &.{ "-DINCLUDE_CUSTOM_LIBC_FUNCS=1", "-DSTBI_NO_STDLIB=1", "-DSTBIW_NO_STDLIB=1" },
            });

            backend_mod.export_symbol_names = &[_][]const u8{
                "app_init",
                "app_deinit",
                "app_update",
                "add_event",
                "arena_u8",
                "gpa_u8",
                "gpa_free",
                "new_font",
            };
        },
    }

    // example
    {
        const example_name = std.mem.concat(b.allocator, u8, &.{
            @tagName(backend),
            if (standalone) "-standalone" else "-ontop",
        }) catch @panic("OOM");
        const example_path = std.mem.concat(b.allocator, u8, &.{ "examples/", example_name, ".zig" }) catch @panic("OOM");
        const example = b.addExecutable(.{
            .name = example_name,
            .root_source_file = b.path(example_path),
            .target = target,
            .optimize = optimize,
            .link_libc = false,
        });
        example.root_module.addImport("dvui", dvui_mod);

        if (target.result.os.tag == .windows) example.win32_manifest = b.path("src/main.manifest");
        if (backend == .web) {
            example.entry = .disabled;
            example.root_module.strip = optimize == .ReleaseFast or optimize == .ReleaseSmall;
        }

        if (target.result.os.tag == .windows) {
            example.subsystem = .Windows;
            // TODO: This may just be only used for directx
            if (b.lazyDependency("zigwin32", .{})) |zigwin32| {
                example.root_module.addImport("zigwin32", zigwin32.module("zigwin32"));
            }
        }

        const compile_step = b.step("compile-example", "Compile example");
        b.getInstallStep().dependOn(compile_step);

        if (backend == .web) {
            const install_wasm = b.addInstallArtifact(example, .{ .dest_dir = .{ .override = .{ .custom = "bin" } } });
            const install_noto = b.addInstallBinFile(b.path("src/fonts/NotoSansKR-Regular.ttf"), "NotoSansKR-Regular.ttf");
            const cb = b.addExecutable(.{
                .name = "cacheBuster",
                .root_source_file = b.path("src/cacheBuster.zig"),
                .target = b.graph.host,
            });
            const cb_run = b.addRunArtifact(cb);
            cb_run.addFileArg(b.path("src/backends/index.html"));
            cb_run.addFileArg(b.path("src/backends/web.js"));
            cb_run.addFileArg(example.getEmittedBin());
            const output = cb_run.captureStdOut();

            compile_step.dependOn(&b.addInstallFileWithDir(output, .prefix, "bin/index.html").step);
            compile_step.dependOn(&b.addInstallFileWithDir(b.path("src/backends/web.js"), .prefix, "bin/web.js").step);
            compile_step.dependOn(&install_wasm.step);
            compile_step.dependOn(&install_noto.step);
        } else {
            compile_step.dependOn(&b.addInstallArtifact(example, .{}).step);

            const run_cmd = b.addRunArtifact(example);
            run_cmd.step.dependOn(compile_step);

            const run_step = b.step("example", "Run example");
            run_step.dependOn(&run_cmd.step);
        }
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
