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

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const back_to_build: ?enums_backend.Backend = b.option(enums_backend.Backend, "backend", "Backend to build");

    const test_step = b.step("test", "Test the dvui codebase");
    const check_step = b.step("check", "Check that the entire dvui codebase has no syntax errors");

    // Setting this to false may fix linking errors: https://github.com/david-vanderson/dvui/issues/269
    const use_lld = b.option(bool, "use-lld", "The value of the use_lld executable option");
    const test_filters = b.option([]const []const u8, "test-filter", "Skip tests that do not match any filter") orelse &[0][]const u8{};

    const generate_doc_images = b.option(bool, "generate-images", "Add this to 'docs' to generate images") orelse false;

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

    var sdl3_options = b.addOptions();
    sdl3_options.addOption(
        ?bool,
        "callbacks",
        b.option(bool, "sdl3-callbacks", "Use callbacks for live resizing on windows/mac"),
    );

    const dvui_opts = DvuiModuleOptions{
        .b = b,
        .target = target,
        .optimize = optimize,
        .test_step = test_step,
        .test_filters = test_filters,
        .check_step = check_step,
        .use_lld = use_lld,
        .build_options = build_options,
    };

    if (back_to_build == .custom) {
        // For export to users who are bringing their own backend.  Use in your build.zig:
        // const dvui_mod = dvui_dep.module("dvui");
        // @import("dvui").linkBackend(dvui_mod, your_backend_module);
        _ = addDvuiModule("dvui", dvui_opts);
        // does not need to be tested as only dependent would hit this path and test themselves
    }

    // Deprecated modules
    if (back_to_build == null or back_to_build == .sdl) {
        // The sdl backend name is deprecated. This is here to provide a useful error during transition
        const files = b.addWriteFiles();
        const source_path = files.add("sdl-deprecated.zig",
            \\comptime { @compileError("The module 'dvui_sdl' is deprecated. Use either 'dvui_sdl2' or 'dvui_sdl3'"); }
        );
        _ = b.addModule("sdl", .{ .root_source_file = source_path });
        _ = b.addModule("dvui_sdl", .{ .root_source_file = source_path });

        if (back_to_build == .sdl) {
            const deprecation_message = b.addFail("Backend 'sdl' is deprecated. Use either 'sdl2' or 'sdl3'");
            b.getInstallStep().dependOn(&deprecation_message.step);
        }
    }

    // Testing
    if (back_to_build == null or back_to_build == .testing) {
        const test_dvui_and_app = back_to_build == .testing;

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
        addExample("testing-app", b.path("examples/app.zig"), dvui_testing, test_dvui_and_app, dvui_opts);
    }

    // SDL2
    if (back_to_build == null or back_to_build == .sdl2) {
        const test_dvui_and_app = back_to_build == .sdl2;

        const sdl_mod = b.addModule("sdl2", .{
            .root_source_file = b.path("src/backends/sdl.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        dvui_opts.addChecks(sdl_mod, "sdl2-backend");
        dvui_opts.addTests(sdl_mod, "sdl2-backend");

        var sdl2_options = b.addOptions();

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

        const dvui_sdl = addDvuiModule("dvui_sdl2", dvui_opts);
        dvui_opts.addChecks(dvui_sdl, "dvui_sdl2");
        if (test_dvui_and_app) {
            dvui_opts.addTests(dvui_sdl, "dvui_sdl2");
        }

        linkBackend(dvui_sdl, sdl_mod);
        addExample("sdl2-dir-grid", b.path("examples/sdl-dir-grid.zig"), dvui_sdl, true, dvui_opts);
        addExample("sdl2-standalone", b.path("examples/sdl-standalone.zig"), dvui_sdl, true, dvui_opts);
        addExample("sdl2-ontop", b.path("examples/sdl-ontop.zig"), dvui_sdl, true, dvui_opts);
        addExample("sdl2-app", b.path("examples/app.zig"), dvui_sdl, test_dvui_and_app, dvui_opts);
    }

    // SDL3
    if (back_to_build == null or back_to_build == .sdl3) {
        // if we are building all the backends, here's where we do dvui tests
        const test_dvui_and_app = true;

        const sdl_mod = b.addModule("sdl3", .{
            .root_source_file = b.path("src/backends/sdl.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        dvui_opts.addChecks(sdl_mod, "sdl3-backend");
        dvui_opts.addTests(sdl_mod, "sdl3-backend");

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

        const dvui_sdl = addDvuiModule("dvui_sdl3", dvui_opts);
        dvui_opts.addChecks(dvui_sdl, "dvui_sdl3");
        if (test_dvui_and_app) {
            dvui_opts.addTests(dvui_sdl, "dvui_sdl3");
        }

        linkBackend(dvui_sdl, sdl_mod);
        addExample("sdl3-standalone", b.path("examples/sdl-standalone.zig"), dvui_sdl, true, dvui_opts);
        addExample("sdl3-ontop", b.path("examples/sdl-ontop.zig"), dvui_sdl, true, dvui_opts);
        addExample("sdl3-app", b.path("examples/app.zig"), dvui_sdl, test_dvui_and_app, dvui_opts);
    }

    // Raylib
    if (back_to_build == null or back_to_build == .raylib) {
        const test_dvui_and_app = back_to_build == .raylib;

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
        dvui_opts.addChecks(raylib_mod, "raylib-backend");
        dvui_opts.addTests(raylib_mod, "raylib-backend");

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

            // This is to support variable framerate
            raylib_mod.addIncludePath(ray.path("src/external/glfw/include/GLFW"));

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

        linkBackend(dvui_raylib, raylib_mod);
        addExample("raylib-standalone", b.path("examples/raylib-standalone.zig"), dvui_raylib, true, dvui_opts_raylib);
        addExample("raylib-ontop", b.path("examples/raylib-ontop.zig"), dvui_raylib, true, dvui_opts_raylib);
        addExample("raylib-app", b.path("examples/app.zig"), dvui_raylib, test_dvui_and_app, dvui_opts_raylib);
    }

    // Dx11
    if (back_to_build == null or back_to_build == .dx11) {
        const test_dvui_and_app = back_to_build == .dx11;

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
            addExample("dx11-standalone", b.path("examples/dx11-standalone.zig"), dvui_dx11, true, dvui_opts);
            addExample("dx11-ontop", b.path("examples/dx11-ontop.zig"), dvui_dx11, true, dvui_opts);
            addExample("dx11-app", b.path("examples/app.zig"), dvui_dx11, test_dvui_and_app, dvui_opts);
        }
    }

    // Web
    if (back_to_build == null or back_to_build == .web) {
        const test_dvui_and_app = back_to_build == .web;

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
        dvui_opts.addChecks(web_mod, "dvui_web");
        if (test_dvui_and_app) {
            dvui_opts.addTests(web_mod, "dvui_web");
        }

        linkBackend(dvui_web, web_mod);

        // Examples, must be compiled for wasm32
        {
            const wasm_dvui_opts = DvuiModuleOptions{
                .b = b,
                .target = b.resolveTargetQuery(.{
                    .cpu_arch = .wasm32,
                    .os_tag = .freestanding,
                }),
                .optimize = optimize,
                .build_options = build_options,
                .test_filters = test_filters,
                // no tests or checks needed, they are check above in native build
            };

            const web_mod_wasm = b.createModule(.{
                .root_source_file = b.path("src/backends/web.zig"),
            });
            web_mod_wasm.export_symbol_names = export_symbol_names;

            const dvui_web_wasm = addDvuiModule("dvui_web_wasm", wasm_dvui_opts);
            linkBackend(dvui_web_wasm, web_mod_wasm);
            addWebExample("web-test", b.path("examples/web-test.zig"), dvui_web_wasm, wasm_dvui_opts);
            addWebExample("web-app", b.path("examples/app.zig"), dvui_web_wasm, wasm_dvui_opts);
        }
    }

    // Docs
    {
        const docs_step = b.step("docs", "Build documentation");
        const docs = b.addLibrary(.{ .name = "dvui", .root_module = b.createModule(.{
            .root_source_file = b.path("src/dvui.zig"),
            .target = target,
        }) });

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
    build_options: *std.Build.Step.Options,

    fn addChecks(self: *const @This(), mod: *std.Build.Module, name: []const u8) void {
        const tests = self.b.addTest(.{ .root_module = mod, .name = name, .filters = self.test_filters, .use_lld = self.use_lld });
        self.b.installArtifact(tests); // Compile check on default install step
        if (self.check_step) |step| {
            step.dependOn(&tests.step);
        }
    }
    fn addTests(self: *const @This(), mod: *std.Build.Module, name: []const u8) void {
        if (self.test_step) |step| {
            const tests = self.b.addTest(.{ .root_module = mod, .name = name, .filters = self.test_filters, .use_lld = self.use_lld });
            step.dependOn(&self.b.addRunArtifact(tests).step);
        }
    }
};

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
    dvui_mod.addImport("svg2tvg", b.dependency("svg2tvg", .{
        .target = target,
        .optimize = optimize,
    }).module("svg2tvg"));

    if (target.result.os.tag == .windows) {
        // tinyfiledialogs needs this
        dvui_mod.linkSystemLibrary("comdlg32", .{});
        dvui_mod.linkSystemLibrary("ole32", .{});
    }

    dvui_mod.addIncludePath(b.path("src/stb"));

    if (target.result.cpu.arch == .wasm32 or target.result.cpu.arch == .wasm64) {
        dvui_mod.addCSourceFiles(.{
            .files = &.{
                "src/stb/stb_image_impl.c",
                "src/stb/stb_image_write_impl.c",
                "src/stb/stb_truetype_impl.c",
            },
            .flags = &.{ "-DINCLUDE_CUSTOM_LIBC_FUNCS=1", "-DSTBI_NO_STDLIB=1", "-DSTBIW_NO_STDLIB=1" },
        });
    } else {
        if (opts.add_stb_image) {
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
    comptime name: []const u8,
    file: std.Build.LazyPath,
    dvui_mod: *std.Build.Module,
    add_tests: bool,
    opts: DvuiModuleOptions,
) void {
    const b = opts.b;

    const mod = b.createModule(.{
        .root_source_file = file,
        .target = opts.target,
        .optimize = opts.optimize,
    });
    mod.addImport("dvui", dvui_mod);

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

    const run_step = b.step(name, "Run " ++ name);
    run_step.dependOn(&run_cmd.step);
}

fn addWebExample(
    comptime name: []const u8,
    file: std.Build.LazyPath,
    dvui_mod: *std.Build.Module,
    opts: DvuiModuleOptions,
) void {
    const b = opts.b;

    const exeOptions: std.Build.ExecutableOptions = .{
        .name = "web",
        .root_source_file = file,
        .target = opts.target,
        .optimize = opts.optimize,
        .link_libc = false,
        .strip = if (opts.optimize == .ReleaseFast or opts.optimize == .ReleaseSmall) true else false,
    };
    const web_test = b.addExecutable(exeOptions);
    web_test.entry = .disabled;
    web_test.root_module.addImport("dvui", dvui_mod);

    const web_test_check = b.addExecutable(exeOptions);
    web_test_check.entry = .disabled;
    web_test_check.root_module.addImport("dvui", dvui_mod);
    if (opts.check_step) |step| step.dependOn(&web_test_check.step);

    const install_dir: std.Build.InstallDir = .{ .custom = "bin/" ++ name };

    const install_wasm = b.addInstallArtifact(web_test, .{
        .dest_dir = .{ .override = install_dir },
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
