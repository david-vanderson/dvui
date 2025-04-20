const std = @import("std");
const enums = @import("src/enums.zig");
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

    const back_to_build: ?enums.Backend = b.option(enums.Backend, "backend", "Backend to build");

    const test_step = b.step("test", "Test the dvui codebase");
    const check_step = b.step("check", "Check that the dvui codebase compiles");

    const dvui_opts = DvuiModuleOptions{
        .b = b,
        .target = target,
        .optimize = optimize,
        .test_step = test_step,
        .check_step = check_step,
    };

    if (back_to_build == .custom) {
        // For export to users who are bringing their own backend.  Use in your build.zig:
        // const dvui_mod = dvui_dep.module("dvui");
        // @import("dvui").linkBackend(dvui_mod, your_backend_module);
        _ = addDvuiModule(.{ .b = b, .target = target, .optimize = optimize }, "dvui", true);
    }

    // Deprecated modules
    if (back_to_build == null or back_to_build == .sdl) {
        // The sdl backend name is deprecated. This is here to provide a useful error during transition
        _ = b.addModule("dvui_sdl", .{ .root_source_file = b.path("src/backends/sdl_deprecated.zig") });
        // TODO: If more deprecation messages are needed, the source files could be generated at compile time with a runArtifact

        if (back_to_build == .sdl) {
            const deprecation_message = b.addFail("Backend 'sdl' is deprecated. Use either 'sdl2' or 'sdl3'");
            b.getInstallStep().dependOn(&deprecation_message.step);
            test_step.dependOn(&deprecation_message.step);
            check_step.dependOn(&deprecation_message.step);
        }
    }

    // Testing
    if (back_to_build == null or back_to_build == .testing) {
        const testing_mod = b.addModule("testing", .{
            .root_source_file = b.path("src/backends/testing.zig"),
            .target = target,
            .optimize = optimize,
        });
        const dvui_testing = addDvuiModule(dvui_opts, "dvui_testing", true);
        linkBackend(dvui_testing, testing_mod);
        addExample(dvui_opts, "testing-app", b.path("examples/app.zig"), dvui_testing);
    }

    // SDL2
    if (back_to_build == null or back_to_build == .sdl2) {
        const sdl_mod = b.addModule("sdl2", .{
            .root_source_file = b.path("src/backends/sdl.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = sdl_mod, .name = "sdl2-backend" })).step);

        var sdl_options = b.addOptions();

        if (b.systemIntegrationOption("sdl2", .{})) {
            // SDL2 from system
            sdl_options.addOption(std.SemanticVersion, "version", .{ .major = 2, .minor = 0, .patch = 0 });
            sdl_mod.linkSystemLibrary("SDL2", .{});
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

        const dvui_sdl = addDvuiModule(dvui_opts, "dvui_sdl2", true);
        linkBackend(dvui_sdl, sdl_mod);
        addExample(dvui_opts, "sdl2-standalone", b.path("examples/sdl-standalone.zig"), dvui_sdl);
        addExample(dvui_opts, "sdl2-ontop", b.path("examples/sdl-ontop.zig"), dvui_sdl);
        addExample(dvui_opts, "sdl2-app", b.path("examples/app.zig"), dvui_sdl);
    }

    // SDL3
    if (back_to_build == null or back_to_build == .sdl3) {
        const sdl_mod = b.addModule("sdl3", .{
            .root_source_file = b.path("src/backends/sdl.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = sdl_mod, .name = "sdl3-backend" })).step);

        var sdl_options = b.addOptions();

        if (b.systemIntegrationOption("sdl3", .{})) {
            // SDL3 from system
            sdl_options.addOption(std.SemanticVersion, "version", .{ .major = 3, .minor = 0, .patch = 0 });
            sdl_mod.linkSystemLibrary("SDL3", .{});
        } else {
            // SDL3 compiled from source
            sdl_options.addOption(std.SemanticVersion, "version", .{ .major = 3, .minor = 0, .patch = 0 });
            if (b.lazyDependency("sdl3", .{
                .target = target,
                .optimize = optimize,
            })) |sdl3| {
                sdl_mod.linkLibrary(sdl3.artifact("SDL3"));
            }
        }
        sdl_mod.addOptions("sdl_options", sdl_options);

        const dvui_sdl = addDvuiModule(dvui_opts, "dvui_sdl3", true);
        linkBackend(dvui_sdl, sdl_mod);
        addExample(dvui_opts, "sdl3-standalone", b.path("examples/sdl-standalone.zig"), dvui_sdl);
        addExample(dvui_opts, "sdl3-ontop", b.path("examples/sdl-ontop.zig"), dvui_sdl);
        addExample(dvui_opts, "sdl3-app", b.path("examples/app.zig"), dvui_sdl);
    }

    // Raylib
    if (back_to_build == null or back_to_build == .raylib) {
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
        test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = raylib_mod, .name = "raylib-backend" })).step);

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

        const dvui_raylib = addDvuiModule(dvui_opts, "dvui_raylib", false);
        linkBackend(dvui_raylib, raylib_mod);
        addExample(dvui_opts, "raylib-standalone", b.path("examples/raylib-standalone.zig"), dvui_raylib);
        addExample(dvui_opts, "raylib-ontop", b.path("examples/raylib-ontop.zig"), dvui_raylib);
        addExample(dvui_opts, "raylib-app", b.path("examples/app.zig"), dvui_raylib);
    }

    // Dx11
    if (back_to_build == null or back_to_build == .dx11) {
        if (target.result.os.tag == .windows) {
            const dx11_mod = b.addModule("dx11", .{
                .root_source_file = b.path("src/backends/dx11.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            });
            test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = dx11_mod, .name = "dx11-backend" })).step);

            if (b.lazyDependency("win32", .{})) |zigwin32| {
                dx11_mod.addImport("win32", zigwin32.module("win32"));
            }

            const dvui_dx11 = addDvuiModule(dvui_opts, "dvui_dx11", true);
            linkBackend(dvui_dx11, dx11_mod);
            addExample(dvui_opts, "dx11-standalone", b.path("examples/dx11-standalone.zig"), dvui_dx11);
            addExample(dvui_opts, "dx11-ontop", b.path("examples/dx11-ontop.zig"), dvui_dx11);
            addExample(dvui_opts, "dx11-app", b.path("examples/app.zig"), dvui_dx11);
        }
    }

    // Web
    if (back_to_build == null or back_to_build == .web) {
        const web_dvui_opts = DvuiModuleOptions{
            .b = b,
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .wasm32,
                .os_tag = .freestanding,
            }),
            .optimize = optimize,
            .check_step = check_step,
        };

        {
            // Build test for selected target, not wasm as the test runner doesn't work without stderr
            const web_test = b.createModule(.{
                .root_source_file = b.path("src/backends/web.zig"),
                .target = target,
                .optimize = optimize,
            });
            test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = web_test, .name = "web-backend" })).step);

            // var web_test_opts = dvui_opts;
            // web_test_opts.test_step = null; // we cannot run web tests, but we can do semantic checks
            const dvui_web_test = addDvuiModule(dvui_opts, "dvui_web_test", true);
            linkBackend(dvui_web_test, web_test);
        }

        const web_mod = b.addModule("web", .{
            .root_source_file = b.path("src/backends/web.zig"),
        });

        web_mod.export_symbol_names = &[_][]const u8{
            "dvui_init",
            "dvui_deinit",
            "dvui_update",
            "add_event",
            "arena_u8",
            "gpa_u8",
            "gpa_free",
            "new_font",
        };

        const dvui_web = addDvuiModule(web_dvui_opts, "dvui_web", true);
        linkBackend(dvui_web, web_mod);

        addWebExample(web_dvui_opts, "web-test", b.path("examples/web-test.zig"), dvui_web);
        addWebExample(web_dvui_opts, "web-app", b.path("examples/app.zig"), dvui_web);
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

fn addTests(b: *std.Build, test_step: *std.Build.Step, mod: *std.Build.Module, comptime name: []const u8) void {
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = mod, .name = "test-" ++ name })).step);
}

const DvuiModuleOptions = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    check_step: ?*std.Build.Step = null,
    test_step: ?*std.Build.Step = null,
};

fn addDvuiModule(
    opts: DvuiModuleOptions,
    comptime name: []const u8,
    add_stb_image: bool,
) *std.Build.Module {
    const b = opts.b;
    const target = opts.target;
    const optimize = opts.optimize;

    const dvui_mod = b.addModule(name, .{
        .root_source_file = b.path("src/dvui.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (opts.check_step) |step| step.dependOn(&b.addLibrary(.{ .root_module = dvui_mod, .name = name }).step);
    if (opts.test_step) |step| step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = dvui_mod, .name = name })).step);

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
    opts: DvuiModuleOptions,
    comptime name: []const u8,
    file: std.Build.LazyPath,
    dvui_mod: *std.Build.Module,
) void {
    const b = opts.b;

    const mod = b.createModule(.{
        .root_source_file = file,
        .target = opts.target,
        .optimize = opts.optimize,
    });
    mod.addImport("dvui", dvui_mod);

    const exe = b.addExecutable(.{ .name = name, .root_module = mod, .use_lld = false });
    if (opts.check_step) |step| step.dependOn(&exe.step);

    if (opts.target.result.os.tag == .windows) {
        exe.win32_manifest = b.path("./src/main.manifest");
        exe.subsystem = .Windows;
        // TODO: This may just be only used for directx
        if (b.lazyDependency("win32", .{})) |zigwin32| {
            mod.addImport("win32", zigwin32.module("win32"));
        }
    }

    const test_cmd = b.addRunArtifact(b.addTest(.{ .root_module = mod, .name = name }));
    const example_test_step = b.step("test-" ++ name, "Test " ++ name);
    example_test_step.dependOn(&test_cmd.step);
    if (opts.test_step) |step| step.dependOn(&test_cmd.step);

    const compile_step = b.step("compile-" ++ name, "Compile " ++ name);
    compile_step.dependOn(&b.addInstallArtifact(exe, .{}).step);
    b.getInstallStep().dependOn(compile_step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(compile_step);

    const run_step = b.step(name, "Run " ++ name);
    run_step.dependOn(&run_cmd.step);
}

fn addWebExample(
    opts: DvuiModuleOptions,
    comptime name: []const u8,
    file: std.Build.LazyPath,
    dvui_mod: *std.Build.Module,
) void {
    const b = opts.b;
    const web_test = b.addExecutable(.{
        .name = "web",
        .root_source_file = file,
        .target = opts.target,
        .optimize = opts.optimize,
        .link_libc = false,
        .strip = if (opts.optimize == .ReleaseFast or opts.optimize == .ReleaseSmall) true else false,
    });
    web_test.entry = .disabled;
    web_test.root_module.addImport("dvui", dvui_mod);

    // web does not run tests, only compile checks
    if (opts.check_step) |step| step.dependOn(&web_test.step);

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
