const std = @import("std");
const enums_backend = @import("src/enums_backend.zig");
const Pkg = std.Build.Pkg;
const Compile = std.Build.Step.Compile;

// NOTE: Keep in-sync with raylib's definition
pub const LinuxDisplayBackend = enum {
    X11,
    Wayland,
    Both,
};

const AccesskitOptions = enum {
    static,
    shared,
    off,

    pub fn enabled(self: AccesskitOptions) bool {
        return self != .off;
    }
};

const CommonSdl = struct {
    mod: *std.Build.Module,
    options: *std.Build.Step.Options,
};

pub fn linkSdl3(
    b: *std.Build,
    sdl_mod: *std.Build.Module,
    sdl3_options: *std.Build.Step.Options,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    if (b.systemIntegrationOption("sdl3", .{})) {
        // SDL3 from system
        sdl3_options.addOption(std.SemanticVersion, "version", .{ .major = 3, .minor = 0, .patch = 0 });
        sdl_mod.linkSystemLibrary("SDL3", .{});
    } else {
        // SDL3 compiled from source
        sdl3_options.addOption(std.SemanticVersion, "version", .{ .major = 3, .minor = 0, .patch = 0 });
        if (b.lazyDependency("sdl3", .{
            .target = target,
            .optimize = optimize,
        })) |sdl3| {
            sdl_mod.linkLibrary(sdl3.artifact("SDL3"));
        }
    }
    sdl_mod.addOptions("sdl_options", sdl3_options);
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var back_to_build = b.option(enums_backend.Backend, "backend", "Backend to build");

    const test_step = b.step("test", "Test the dvui codebase");
    const check_step = b.step("check", "Check that the entire dvui codebase has no syntax errors");

    // Setting this to false may fix linking errors: https://github.com/david-vanderson/dvui/issues/269
    const use_lld = b.option(bool, "use-lld", "The value of the use_lld executable option");
    const test_filters = b.option([]const []const u8, "test-filter", "Skip tests that do not match any filter") orelse &[0][]const u8{};

    const generate_doc_images = b.option(bool, "generate-images", "Add this to 'docs' to generate images") orelse false;
    if (generate_doc_images) {
        back_to_build = .sdl2;
    }

    const libc_option = b.option(bool, "libc", "Use libc (default is backend specific)");
    const freetype_option = b.option(bool, "freetype", "Freetype (or stb_truetype if false) for font rendering (default is backend specific)");
    const tiny_file_dialogs_option = b.option(bool, "tiny-file-dialogs", "OS-native file dialogs (default is backend specific)");

    // This option is triggered only if it involved with raylib backend of any kind
    var linux_display_backend: ?LinuxDisplayBackend = null;
    if (back_to_build == null or back_to_build.? == .raylib or back_to_build.? == .raylib_zig) {
        linux_display_backend = b.option(LinuxDisplayBackend, "linux_display_backend", "If using raylib, which linux display?") orelse blk: {
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
    }

    const build_options = b.addOptions();
    build_options.addOption(
        ?[]const u8,
        "snapshot_image_suffix",
        b.option([]const u8, "snapshot-images", "When this name is defined, dvui.testing.snapshot will save an image ending with the string provided"),
    );
    build_options.addOption(
        ?[]const u8,
        "image_dir",
        if (generate_doc_images)
            b.getInstallPath(.prefix, "docs")
        else
            b.option([]const u8, "image-dir", "Default directory for dvui.testing.saveImage"),
    );
    build_options.addOption(
        ?u8,
        "log_stack_trace",
        b.option(u8, "log-stack-trace", "The max number of stack frames to display in error log stack traces (32 shows almost everything, 0 to disable)"),
    );
    build_options.addOption(
        ?bool,
        "log_error_trace",
        b.option(bool, "log-error-trace", "If error logs should include the error return trace (automatically enabled with log stack traces)"),
    );

    const accesskit = b.option(AccesskitOptions, "accesskit", "Build with AccessKit support") orelse .off;

    build_options.addOption(
        AccesskitOptions,
        "accesskit",
        accesskit,
    );

    var dvui_opts = DvuiModuleOptions{
        .b = b,
        .target = target,
        .optimize = optimize,
        .test_step = test_step,
        .test_filters = test_filters,
        .check_step = check_step,
        .use_lld = use_lld,
        .accesskit = accesskit,
        .build_options = build_options,
        .libc = libc_option,
        .freetype = freetype_option,
        .tiny_file_dialogs = tiny_file_dialogs_option,
        .linux_display_backend = linux_display_backend,
    };

    if (back_to_build) |backend| {
        buildBackend(backend, true, dvui_opts);
    } else {
        for (std.meta.tags(enums_backend.Backend)) |backend| {
            switch (backend) {
                .custom, .sdl => continue,
                .web, .testing => dvui_opts.accesskit = .off,
                else => {},
            }
            // if we are building all the backends, here's where we do dvui tests
            const test_dvui_and_app = backend == .sdl3;
            buildBackend(backend, test_dvui_and_app, dvui_opts);
        }
    }

    // Docs
    {
        const docs_step = b.step("docs", "Build documentation");
        const dvui_mod = b.createModule(.{
            .root_source_file = b.path("src/dvui.zig"),
            .target = target,
        });
        dvui_mod.addOptions("build_options", build_options);
        const docs = b.addLibrary(.{ .name = "dvui", .root_module = dvui_mod });

        const install_docs = b.addInstallDirectory(.{
            .source_dir = docs.getEmittedDocs(),
            .install_dir = .prefix,
            .install_subdir = "docs",
            // Seems a bit drastic but by default only index.html is installed
            // and I override it below. Maybe there is a cleaner way ?
            .exclude_extensions = &.{".html"},
        });
        docs_step.dependOn(&install_docs.step);

        if (generate_doc_images) {
            if (b.modules.get("dvui_sdl2")) |dvui| {
                const image_tests = b.addTest(.{
                    .name = "generate-images",
                    .root_module = dvui,
                    .filters = &.{"DOCIMG"},
                    .test_runner = .{ .mode = .simple, .path = b.path("docs/image_gen_test_runner.zig") },
                    .use_lld = use_lld,
                });
                docs_step.dependOn(&b.addRunArtifact(image_tests).step);
            } else {
                docs_step.dependOn(&b.addFail("'generate-images' requires the sdl2 backend").step);
            }
        }

        // Don't add to normal install step as it fails in ci
        // b.getInstallStep().dependOn(docs_step);

        // Use customized index.html
        const add_doc_logo = b.addExecutable(.{
            .name = "addDocLogo",
            .root_module = b.createModule(.{
                .root_source_file = b.path("docs/add_doc_logo.zig"),
                .target = b.graph.host,
            }),
        });
        const run_add_logo = b.addRunArtifact(add_doc_logo);
        run_add_logo.addFileArg(b.path("docs/index.html"));
        run_add_logo.addFileArg(b.path("docs/favicon.svg"));
        run_add_logo.addFileArg(b.path("docs/logo.svg"));
        const indexhtml_file = run_add_logo.captureStdOut(.{});
        docs_step.dependOn(&b.addInstallFileWithDir(indexhtml_file, .prefix, "docs/index.html").step);
    }
}

pub fn buildBackend(backend: enums_backend.Backend, test_dvui_and_app: bool, dvui_opts_in: DvuiModuleOptions) void {
    var dvui_opts = dvui_opts_in;
    const b = dvui_opts.b;
    const target = dvui_opts.target;
    const optimize = dvui_opts.optimize;
    switch (backend) {
        .custom => {
            dvui_opts.setDefaults(.{ .libc = false, .freetype = false, .tiny_file_dialogs = false });

            // For export to users who are bringing their own backend.  Use in your build.zig:
            // const dvui_mod = dvui_dep.module("dvui");
            // @import("dvui").linkBackend(dvui_mod, your_backend_module);
            _ = addDvuiModule("dvui", dvui_opts);
            // does not need to be tested as only dependent would hit this path and test themselves
        },
        // Deprecated modules
        .sdl => {
            // The sdl backend name is deprecated. This is here to provide a useful error during transition
            const files = b.addWriteFiles();
            const source_path = files.add("sdl-deprecated.zig",
                \\comptime { @compileError("The module 'dvui_sdl' is deprecated. Use either 'dvui_sdl2' or 'dvui_sdl3'"); }
            );
            _ = b.addModule("sdl", .{ .root_source_file = source_path });
            _ = b.addModule("dvui_sdl", .{ .root_source_file = source_path });

            // This indicates that we are trying to build this specific backend only
            if (test_dvui_and_app) {
                const deprecation_message = b.addFail("Backend 'sdl' is deprecated. Use either 'sdl2' or 'sdl3'");
                b.getInstallStep().dependOn(&deprecation_message.step);
            }
        },
        .testing => {
            dvui_opts.setDefaults(.{ .libc = true, .freetype = true, .tiny_file_dialogs = true });
            const testing_mod = b.addModule("testing", .{
                .root_source_file = b.path("src/backends/testing.zig"),
                .target = target,
                .optimize = optimize,
            });
            dvui_opts.addChecks(testing_mod, "testing-backend");
            dvui_opts.addTests(testing_mod, "testing-backend");

            const dvui_testing = addDvuiModule("dvui_testing", dvui_opts);
            dvui_opts.addChecks(dvui_testing, "dvui_testing");
            if (test_dvui_and_app) {
                dvui_opts.addTests(dvui_testing, "dvui_testing");
            }

            linkBackend(dvui_testing, testing_mod);
            const example_opts: ExampleOptions = .{
                .dvui_mod = dvui_testing,
                .backend_name = "testing-backend",
                .backend_mod = testing_mod,
            };
            addExample("testing-app", b.path("examples/app.zig"), test_dvui_and_app, example_opts, dvui_opts);
        },
        .sdl2 => {
            dvui_opts.setDefaults(.{ .libc = true, .freetype = true, .tiny_file_dialogs = true });
            const sdl_mod = b.addModule("sdl2", .{
                .root_source_file = b.path("src/backends/sdl.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            });
            dvui_opts.addChecks(sdl_mod, "sdl2-backend");
            dvui_opts.addTests(sdl_mod, "sdl2-backend");

            const sdl2_options = b.addOptions();

            if (b.systemIntegrationOption("sdl2", .{})) {
                // SDL2 from system
                sdl2_options.addOption(std.SemanticVersion, "version", .{ .major = 2, .minor = 0, .patch = 0 });
                sdl_mod.linkSystemLibrary("SDL2", .{});
            } else {
                // SDL2 compiled from source
                sdl2_options.addOption(std.SemanticVersion, "version", .{ .major = 2, .minor = 0, .patch = 0 });
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
            sdl_mod.addOptions("sdl_options", sdl2_options);

            // Enable smooth scrolling on mac
            if (target.result.os.tag == .macos) {
                // SDL hard codes this so we have to overwrite it
                const objc_files = b.addWriteFiles();
                const objc_file = objc_files.add("config.mm",
                    // https://github.com/libsdl-org/SDL/issues/2176#issuecomment-2009687592
                    \\#import <Foundation/Foundation.h>
                    \\
                    \\void MACOS_enable_scroll_momentum() {
                    \\    [[NSUserDefaults standardUserDefaults]
                    \\    setBool: YES forKey: @"AppleMomentumScrollSupported"];
                    \\}
                );
                const lib = b.addLibrary(.{
                    .name = "SDL2_config",
                    .root_module = b.createModule(.{
                        .target = target,
                        .optimize = optimize,
                    }),
                });
                lib.addCSourceFile(.{
                    .file = objc_file,
                    .language = .objective_c,
                });
                sdl_mod.linkLibrary(lib);
            }

            const dvui_sdl = addDvuiModule("dvui_sdl2", dvui_opts);
            dvui_opts.addChecks(dvui_sdl, "dvui_sdl2");
            if (test_dvui_and_app) {
                dvui_opts.addTests(dvui_sdl, "dvui_sdl2");
            }

            linkBackend(dvui_sdl, sdl_mod);
            const example_opts: ExampleOptions = .{
                .dvui_mod = dvui_sdl,
                .backend_name = "sdl-backend",
                .backend_mod = sdl_mod,
            };
            addExample("sdl2-standalone", b.path("examples/sdl-standalone.zig"), true, example_opts, dvui_opts);
            addExample("sdl2-ontop", b.path("examples/sdl-ontop.zig"), true, example_opts, dvui_opts);
            addExample("sdl2-app", b.path("examples/app.zig"), test_dvui_and_app, example_opts, dvui_opts);
        },
        .sdl3gpu => {
            dvui_opts.setDefaults(.{ .libc = true, .freetype = true, .tiny_file_dialogs = true });
            const sdl_mod = b.addModule("sdl3", .{
                .root_source_file = b.path("src/backends/sdl3gpu.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            });
            dvui_opts.addChecks(sdl_mod, "sdl3gpu-backend");
            dvui_opts.addTests(sdl_mod, "sdl3gpu-backend");

            const sdl3_options = b.addOptions();
            // sdl3_options.addOption(
            //     ?bool,
            //     "callbacks",
            //     b.option(bool, "sdl3gpu-callbacks", "Use callbacks for live resizing on windows/mac"),
            // );
            linkSdl3(b, sdl_mod, sdl3_options, target, optimize);

            const dvui_sdl = addDvuiModule("dvui_sdl3gpu", dvui_opts);
            // dvui_opts.addChecks(dvui_sdl, "dvui_sdl3gpu");
            // if (test_dvui_and_app) {
            // dvui_opts.addTests(dvui_sdl, "dvui_sdl3gpu");
            // }

            linkBackend(dvui_sdl, sdl_mod);
            const example_opts: ExampleOptions = .{
                .dvui_mod = dvui_sdl,
                .backend_name = "sdl3gpu-backend",
                .backend_mod = sdl_mod,
            };
            addExample("sdl3gpu-standalone", b.path("examples/sdl3gpu-standalone.zig"), true, example_opts, dvui_opts);
            addExample("sdl3gpu-ontop", b.path("examples/sdl3gpu-ontop.zig"), true, example_opts, dvui_opts);
        },
        .sdl3 => {
            dvui_opts.setDefaults(.{ .libc = true, .freetype = true, .tiny_file_dialogs = true });
            const sdl_mod = b.addModule("sdl3", .{
                .root_source_file = b.path("src/backends/sdl.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            });

            dvui_opts.addChecks(sdl_mod, "sdl3gpu-backend");
            dvui_opts.addTests(sdl_mod, "sdl3gpu-backend");

            const sdl3_options = b.addOptions();
            sdl3_options.addOption(
                ?bool,
                "callbacks",
                b.option(bool, "sdl3-callbacks", "Use callbacks for live resizing on windows/mac"),
            );

            linkSdl3(b, sdl_mod, sdl3_options, target, optimize);

            const dvui_sdl = addDvuiModule("dvui_sdl3", dvui_opts);
            dvui_opts.addChecks(dvui_sdl, "dvui_sdl3");
            if (test_dvui_and_app) {
                dvui_opts.addTests(dvui_sdl, "dvui_sdl3");
            }

            linkBackend(dvui_sdl, sdl_mod);
            const example_opts: ExampleOptions = .{
                .dvui_mod = dvui_sdl,
                .backend_name = "sdl-backend",
                .backend_mod = sdl_mod,
            };
            addExample("sdl3-standalone", b.path("examples/sdl-standalone.zig"), true, example_opts, dvui_opts);
            addExample("sdl3-ontop", b.path("examples/sdl-ontop.zig"), true, example_opts, dvui_opts);
            addExample("sdl3-app", b.path("examples/app.zig"), test_dvui_and_app, example_opts, dvui_opts);
        },
        .raylib => {
            dvui_opts.setDefaults(.{ .libc = true, .freetype = true, .tiny_file_dialogs = true });

            const raylib_backend_mod = b.addModule("raylib", .{
                .root_source_file = b.path("src/backends/raylib-c.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            });
            dvui_opts.addChecks(raylib_backend_mod, "raylib-backend");
            dvui_opts.addTests(raylib_backend_mod, "raylib-backend");

            const maybe_ray = b.lazyDependency(
                "raylib",
                .{
                    .target = target,
                    .optimize = optimize,
                    .linux_display_backend = dvui_opts.linux_display_backend.?,
                },
            );
            if (maybe_ray) |ray| {
                raylib_backend_mod.linkLibrary(ray.artifact("raylib"));

                // This is to support variable framerate
                raylib_backend_mod.addIncludePath(ray.path("src/external/glfw/include/GLFW"));

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

            var dvui_opts_raylib = dvui_opts;
            dvui_opts_raylib.add_stb_image = false;
            const dvui_raylib = addDvuiModule("dvui_raylib", dvui_opts_raylib);
            dvui_opts.addChecks(dvui_raylib, "dvui_raylib");
            if (test_dvui_and_app) {
                dvui_opts.addTests(dvui_raylib, "dvui_raylib");
            }

            linkBackend(dvui_raylib, raylib_backend_mod);
            const example_opts: ExampleOptions = .{
                .dvui_mod = dvui_raylib,
                .backend_name = "raylib-backend",
                .backend_mod = raylib_backend_mod,
            };

            addExample("raylib-standalone", b.path("examples/raylib-standalone.zig"), true, example_opts, dvui_opts_raylib);
            addExample("raylib-ontop", b.path("examples/raylib-ontop.zig"), true, example_opts, dvui_opts_raylib);
            addExample("raylib-app", b.path("examples/app.zig"), test_dvui_and_app, example_opts, dvui_opts_raylib);
        },
        .raylib_zig => {
            dvui_opts.setDefaults(.{ .libc = dvui_opts_in.libc orelse true, .freetype = true, .tiny_file_dialogs = true });

            const raylib_backend_mod = b.addModule("raylib_zig", .{
                .root_source_file = b.path("src/backends/raylib-zig.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            });
            dvui_opts.addChecks(raylib_backend_mod, "raylib-zig-backend");
            dvui_opts.addTests(raylib_backend_mod, "raylib-zig-backend");

            const maybe_ray = b.lazyDependency(
                "raylib_zig",
                .{
                    .target = target,
                    .optimize = optimize,
                    .linux_display_backend = dvui_opts.linux_display_backend.?,
                },
            );
            if (maybe_ray) |ray| {
                raylib_backend_mod.linkLibrary(ray.artifact("raylib"));
                raylib_backend_mod.addImport("raylib", ray.module("raylib"));
                raylib_backend_mod.addImport("raygui", ray.module("raygui"));
            }

            const maybe_glfw = b.lazyDependency(
                "zglfw",
                .{
                    .target = target,
                    .optimize = optimize,
                },
            );
            if (maybe_glfw) |glfw| {
                raylib_backend_mod.addImport("zglfw", glfw.module("root"));
            }

            var dvui_opts_raylib = dvui_opts;
            dvui_opts_raylib.add_stb_image = false;
            const dvui_raylib = addDvuiModule("dvui_raylib_zig", dvui_opts_raylib);
            dvui_opts.addChecks(dvui_raylib, "dvui_raylib_zig");
            if (test_dvui_and_app) {
                dvui_opts.addTests(dvui_raylib, "dvui_raylib_zig");
            }

            linkBackend(dvui_raylib, raylib_backend_mod);
            const example_opts: ExampleOptions = .{
                .dvui_mod = dvui_raylib,
                .backend_name = "raylib-zig-backend",
                .backend_mod = raylib_backend_mod,
            };

            addExample("raylib-zig-standalone", b.path("examples/raylib-zig-standalone.zig"), true, example_opts, dvui_opts_raylib);
            addExample("raylib-zig-ontop", b.path("examples/raylib-zig-ontop.zig"), true, example_opts, dvui_opts_raylib);
            addExample("raylib-zig-app", b.path("examples/app.zig"), test_dvui_and_app, example_opts, dvui_opts_raylib);
        },
        .dx11 => {
            dvui_opts.setDefaults(.{ .libc = true, .freetype = true, .tiny_file_dialogs = true });
            if (target.result.os.tag == .windows) {
                const dx11_mod = b.addModule("dx11", .{
                    .root_source_file = b.path("src/backends/dx11.zig"),
                    .target = target,
                    .optimize = optimize,
                    .link_libc = true,
                });
                dvui_opts.addChecks(dx11_mod, "dx11-backend");
                dvui_opts.addTests(dx11_mod, "dx11-backend");

                if (b.lazyDependency("win32", .{})) |zigwin32| {
                    dx11_mod.addImport("win32", zigwin32.module("win32"));
                }

                const dvui_dx11 = addDvuiModule("dvui_dx11", dvui_opts);
                dvui_opts.addChecks(dvui_dx11, "dvui_dx11");
                if (test_dvui_and_app) {
                    dvui_opts.addTests(dvui_dx11, "dvui_dx11");
                }

                linkBackend(dvui_dx11, dx11_mod);
                const example_opts: ExampleOptions = .{
                    .dvui_mod = dvui_dx11,
                    .backend_name = "dx11-backend",
                    .backend_mod = dx11_mod,
                };
                addExample("dx11-standalone", b.path("examples/dx11-standalone.zig"), true, example_opts, dvui_opts);
                addExample("dx11-ontop", b.path("examples/dx11-ontop.zig"), true, example_opts, dvui_opts);
                addExample("dx11-app", b.path("examples/app.zig"), test_dvui_and_app, example_opts, dvui_opts);
            }
        },
        .web => {
            dvui_opts.setDefaults(.{ .libc = false, .freetype = false, .tiny_file_dialogs = false });
            const export_symbol_names = &[_][]const u8{
                "dvui_init",
                "dvui_deinit",
                "dvui_update",
                "add_event",
                "arena_u8",
                "gpa_u8",
                "gpa_free",
                "new_font",
            };

            const web_mod = b.addModule("web", .{
                .root_source_file = b.path("src/backends/web.zig"),
                .target = target,
                .optimize = optimize,
            });
            web_mod.export_symbol_names = export_symbol_names;
            dvui_opts.addChecks(web_mod, "web-backend");
            dvui_opts.addTests(web_mod, "web-backend");

            // NOTE: exported module uses the standard target so it can be overridden by users
            const dvui_web = addDvuiModule("dvui_web", dvui_opts);
            dvui_opts.addChecks(dvui_web, "dvui_web");
            if (test_dvui_and_app) {
                dvui_opts.addTests(dvui_web, "dvui_web");
            }

            linkBackend(dvui_web, web_mod);

            // Examples, must be compiled for wasm32
            {
                var wasm_dvui_opts = DvuiModuleOptions{
                    .b = b,
                    .target = b.resolveTargetQuery(.{
                        .cpu_arch = .wasm32,
                        .os_tag = .freestanding,
                    }),
                    .optimize = optimize,
                    .build_options = dvui_opts.build_options,
                    .test_filters = dvui_opts.test_filters,
                    .accesskit = .off,
                    .libc = false,
                    .freetype = false,
                    .tiny_file_dialogs = false,
                    // no tests or checks needed, they are check above in native build
                };

                wasm_dvui_opts.setDefaults(.{ .libc = false, .freetype = false, .tiny_file_dialogs = false });

                const web_mod_wasm = b.createModule(.{
                    .root_source_file = b.path("src/backends/web.zig"),
                });
                web_mod_wasm.export_symbol_names = export_symbol_names;

                const dvui_web_wasm = addDvuiModule("dvui_web_wasm", wasm_dvui_opts);
                linkBackend(dvui_web_wasm, web_mod_wasm);
                const example_opts: ExampleOptions = .{
                    .dvui_mod = dvui_web_wasm,
                    .backend_name = "web-backend",
                    .backend_mod = web_mod_wasm,
                };
                addWebExample("web-test", b.path("examples/web-test.zig"), example_opts, wasm_dvui_opts);
                addWebExample("web-app", b.path("examples/app.zig"), example_opts, wasm_dvui_opts);
            }
        },
    }
}

pub fn linkBackend(dvui_mod: *std.Build.Module, backend_mod: *std.Build.Module) void {
    backend_mod.addImport("dvui", dvui_mod);
    dvui_mod.addImport("backend", backend_mod);
}

const DvuiModuleOptions = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    check_step: ?*std.Build.Step = null,
    test_step: ?*std.Build.Step = null,
    test_filters: []const []const u8,
    add_stb_image: bool = true,
    use_lld: ?bool = null,
    accesskit: AccesskitOptions = .off,
    build_options: *std.Build.Step.Options,
    libc: ?bool,
    tiny_file_dialogs: ?bool,
    freetype: ?bool,
    linux_display_backend: ?LinuxDisplayBackend = null,

    pub const DefaultOptions = struct {
        libc: bool,
        freetype: bool,
        tiny_file_dialogs: bool,
    };

    fn setDefaults(self: *@This(), defaults: DefaultOptions) void {
        self.libc = self.libc orelse defaults.libc;
        self.tiny_file_dialogs = self.tiny_file_dialogs orelse defaults.tiny_file_dialogs;
        self.freetype = self.freetype orelse defaults.freetype;
    }

    fn makeDefaults(self: *const @This()) *std.Build.Step.Options {
        var ret = self.b.addOptions();
        ret.addOption(
            bool,
            "libc",
            self.libc orelse @panic("makeDefaults: libc was null"),
        );
        ret.addOption(
            bool,
            "tiny_file_dialogs",
            self.tiny_file_dialogs orelse @panic("makeDefaults: tiny_file_dialogs was null"),
        );
        ret.addOption(
            bool,
            "freetype",
            self.freetype orelse @panic("makeDefaults: freetype was null"),
        );

        return ret;
    }

    fn addChecks(self: *const @This(), mod: *std.Build.Module, name: []const u8) void {
        const tests = self.b.addTest(.{ .root_module = mod, .name = self.b.fmt("{s}-check", .{name}), .filters = self.test_filters, .use_lld = self.use_lld });
        self.b.getInstallStep().dependOn(&tests.step);
        if (self.check_step) |step| {
            step.dependOn(&tests.step);
        }
    }

    fn addTests(self: *const @This(), mod: *std.Build.Module, name: []const u8) void {
        if (self.test_step) |step| {
            const tests = self.b.addTest(.{
                .root_module = mod,
                .name = self.b.fmt("{s}-test", .{name}),
                .filters = self.test_filters,
                .use_lld = self.use_lld,
            });
            step.dependOn(&self.b.addRunArtifact(tests).step);
        }
    }
};

fn accessKitSupported(target: std.Build.ResolvedTarget) bool {
    if (target.result.os.tag == .windows) {
        return target.result.cpu.arch.isAARCH64() or target.result.cpu.arch.isX86();
    } else if (target.result.os.tag.isDarwin()) {
        return target.result.cpu.arch.isAARCH64() or target.result.cpu.arch == .x86_64;
    } else if (target.result.os.tag == .linux) {
        return target.result.cpu.arch.isX86();
    } else {
        return false;
    }
}

fn accessKitPath(b: *std.Build, target: std.Build.ResolvedTarget, ak_dep: *std.Build.Dependency, opt: AccesskitOptions, full_lib_path: bool) std.Build.LazyPath {
    const os_path = if (target.result.os.tag == .windows) "windows" //
        else if (target.result.os.tag.isDarwin()) "macos" //
        else if (target.result.os.tag == .linux) "linux" //
        else "unsupported";
    const arch_path = if (target.result.cpu.arch.isAARCH64()) "arm64" //
        else if (target.result.cpu.arch == .x86) "x86" //
        else if (target.result.cpu.arch == .x86_64) "x86_64" //
        else "unsupported";

    const abi_path = if (target.result.os.tag == .windows) "msvc" //
        else if (target.result.os.tag.isDarwin()) "" //
        else if (target.result.os.tag == .linux) "" //
        else "";

    const linkage_path = @tagName(opt);

    if (full_lib_path) {
        return ak_dep.path(b.pathJoin(&.{ "lib", os_path, arch_path, abi_path, linkage_path, accessKitLibName(target) }));
    } else {
        return ak_dep.path(b.pathJoin(&.{ "lib", os_path, arch_path, abi_path, linkage_path }));
    }
}

fn accessKitLibName(target: std.Build.ResolvedTarget) []const u8 {
    return if (target.result.os.tag == .windows) "accesskit.dll" //
    else if (target.result.os.tag.isDarwin()) "libaccesskit.dylib" //
    else if (target.result.os.tag == .linux) "libaccesskit.so" //
    else "unsupported";
}

fn addDvuiModule(
    comptime name: []const u8,
    opts: DvuiModuleOptions,
) *std.Build.Module {
    const b = opts.b;
    const target = opts.target;
    const optimize = opts.optimize;

    const dvui_mod = b.addModule(name, .{
        .root_source_file = b.path("src/dvui.zig"),
        .target = target,
        .optimize = optimize,
    });
    dvui_mod.addOptions("build_options", opts.build_options);
    dvui_mod.addOptions("default_options", opts.makeDefaults());
    dvui_mod.addImport("svg2tvg", b.dependency("svg2tvg", .{
        .target = target,
        .optimize = optimize,
    }).module("svg2tvg"));

    // the system integration option check has to always occur even if accesskit is disabled for
    // it to be displayed in the build help
    const accesskit_from_system = b.systemIntegrationOption("accesskit", .{});
    if (opts.accesskit.enabled()) {
        const ak_dep = b.dependency("accesskit", .{});
        dvui_mod.addIncludePath(ak_dep.path("include"));

        if (!accesskit_from_system) {
            dvui_mod.addLibraryPath(accessKitPath(b, target, ak_dep, opts.accesskit, false));
        }
        dvui_mod.linkSystemLibrary("accesskit", .{});

        if (target.result.os.tag == .linux) {
            dvui_mod.linkSystemLibrary("unwind", .{});
        }
    }

    const stb_source = "vendor/stb/";
    dvui_mod.addIncludePath(b.path(stb_source));

    const libc = opts.libc orelse @panic("libc was null");
    const stb_flags: []const []const u8 = if (!libc)
        &.{ "-DINCLUDE_CUSTOM_LIBC_FUNCS=1", "-DSTBI_NO_STDLIB=1", "-DSTBIW_NO_STDLIB=1", "-DSTBI_NO_SIMD=1" }
    else
        &.{};

    if (opts.add_stb_image) {
        dvui_mod.addCSourceFiles(.{
            .files = &.{
                stb_source ++ "stb_image_impl.c",
                stb_source ++ "stb_image_write_impl.c",
            },
            .flags = stb_flags,
        });
    }

    const freetype = opts.freetype orelse @panic("freetype was null");
    if (freetype) {
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
    } else {
        dvui_mod.addCSourceFiles(.{ .files = &.{stb_source ++ "stb_truetype_impl.c"}, .flags = stb_flags });
    }

    const tfd = opts.tiny_file_dialogs orelse @panic("tiny_file_dialogs was null");
    if (tfd) {
        dvui_mod.addIncludePath(b.path("vendor/tfd"));
        dvui_mod.addCSourceFiles(.{ .files = &.{"vendor/tfd/tinyfiledialogs.c"} });

        if (target.result.os.tag == .windows) {
            // tinyfiledialogs needs this
            dvui_mod.linkSystemLibrary("comdlg32", .{});
            dvui_mod.linkSystemLibrary("ole32", .{});
        }
    }

    return dvui_mod;
}

const ExampleOptions = struct {
    dvui_mod: *std.Build.Module,
    backend_name: []const u8,
    backend_mod: *std.Build.Module,
};

fn addExample(
    comptime name: []const u8,
    file: std.Build.LazyPath,
    add_tests: bool,
    example_opts: ExampleOptions,
    opts: DvuiModuleOptions,
) void {
    const b = opts.b;

    const mod = b.createModule(.{
        .root_source_file = file,
        .target = opts.target,
        .optimize = opts.optimize,
    });
    mod.addImport("dvui", example_opts.dvui_mod);
    mod.addImport(example_opts.backend_name, example_opts.backend_mod);

    const exe = b.addExecutable(.{ .name = name, .root_module = mod, .use_lld = opts.use_lld });
    if (opts.check_step) |step| {
        step.dependOn(&exe.step);
    }

    if (opts.target.result.os.tag == .windows) {
        exe.win32_manifest = b.path("./src/main.manifest");
        exe.subsystem = .Windows;
        // TODO: This may just be only used for directx
        if (b.lazyDependency("win32", .{})) |zigwin32| {
            mod.addImport("win32", zigwin32.module("win32"));
        }

        if (opts.accesskit.enabled()) {
            mod.linkSystemLibrary("ws2_32", .{});
            mod.linkSystemLibrary("Userenv", .{});
        }
    }

    if (add_tests) {
        opts.addChecks(mod, name);
        opts.addTests(mod, name);
        var test_step_opts = opts;
        test_step_opts.test_step = b.step("test-" ++ name, "Test " ++ name);
        test_step_opts.addTests(mod, name);
    }

    const compile_step = b.step("compile-" ++ name, "Compile " ++ name);
    const compile_cmd = b.addInstallArtifact(exe, .{});
    compile_step.dependOn(&compile_cmd.step);

    b.getInstallStep().dependOn(compile_step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(compile_step);

    if (opts.accesskit.enabled() and !accessKitSupported(opts.target)) {
        compile_step.dependOn(&b.addFail("Accesskit is not supported for this target. Build with -Daccesskit=off").step);
    } else if (opts.accesskit == .shared) {
        compile_step.dependOn(&b.addInstallFileWithDir(accessKitPath(
            b,
            opts.target,
            b.dependency("accesskit", .{}),
            opts.accesskit,
            true,
        ), .bin, accessKitLibName(opts.target)).step);
        // Converts shared lib path to be relative to exe install directory.
        exe.root_module.addRPathSpecial("$ORIGIN");
    }

    const run_step = b.step(name, "Run " ++ name);
    run_step.dependOn(&run_cmd.step);
}

fn addWebExample(
    comptime name: []const u8,
    file: std.Build.LazyPath,
    example_opts: ExampleOptions,
    opts: DvuiModuleOptions,
) void {
    const b = opts.b;

    const exeOptions: std.Build.ExecutableOptions = .{
        .name = "web",
        .root_module = b.createModule(.{
            .root_source_file = file,
            .target = opts.target,
            .optimize = opts.optimize,
            .link_libc = false,
            .strip = if (opts.optimize == .ReleaseFast or opts.optimize == .ReleaseSmall) true else false,
        }),
    };
    const web_test = b.addExecutable(exeOptions);
    web_test.entry = .disabled;
    web_test.root_module.addImport("dvui", example_opts.dvui_mod);
    web_test.root_module.addImport(example_opts.backend_name, example_opts.backend_mod);

    const web_test_check = b.addExecutable(exeOptions);
    web_test_check.entry = .disabled;
    web_test_check.root_module.addImport("dvui", example_opts.dvui_mod);
    web_test_check.root_module.addImport(example_opts.backend_name, example_opts.backend_mod);
    if (opts.check_step) |step| step.dependOn(&web_test_check.step);

    const install_dir: std.Build.InstallDir = .{ .custom = "bin/" ++ name };

    const install_wasm = b.addInstallArtifact(web_test, .{
        .dest_dir = .{ .override = install_dir },
    });

    const cb = b.addExecutable(.{
        .name = "cacheBuster",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cacheBuster.zig"),
            .target = b.graph.host,
        }),
    });
    const cb_run = b.addRunArtifact(cb);
    cb_run.addFileArg(b.path("src/backends/index.html"));
    cb_run.addFileArg(b.path("src/backends/web.js"));
    cb_run.addFileArg(web_test.getEmittedBin());
    const output = cb_run.captureStdOut(.{});

    const install_noto = b.addInstallFileWithDir(b.path("src/fonts/NotoSansKR-Regular.ttf"), install_dir, "NotoSansKR-Regular.ttf");

    const compile_step = b.step(name, "Compile " ++ name);
    compile_step.dependOn(&b.addInstallFileWithDir(output, install_dir, "index.html").step);
    const web_js = b.path("src/backends/web.js");
    compile_step.dependOn(&b.addInstallFileWithDir(web_js, install_dir, "web.js").step);
    b.addNamedLazyPath("web.js", web_js);
    compile_step.dependOn(&install_wasm.step);
    compile_step.dependOn(&install_noto.step);

    b.getInstallStep().dependOn(compile_step);
}
