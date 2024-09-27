const std = @import("std");
const Pkg = std.Build.Pkg;
const Compile = std.Build.Step.Compile;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dvui_sdl = addDvuiModule(b, target, optimize, .sdl);
    const dvui_raylib = addDvuiModule(b, target, optimize, .raylib);

    addExample(b, target, optimize, "sdl-standalone", dvui_sdl);
    addExample(b, target, optimize, "sdl-ontop", dvui_sdl);
    addExample(b, target, optimize, "raylib-standalone", dvui_raylib);
    addExample(b, target, optimize, "raylib-ontop", dvui_raylib);

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
            "gpa_u8",
            "gpa_free",
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

const Backend = enum {
    raylib,
    sdl,
};

pub fn backendSystemPkg(backend: Backend) ?[]const u8 {
    return switch (backend) {
        .raylib => null,
        .sdl => "sdl2",
    };
}

const LazyDeps = struct {
    enabled: bool,
    need_was_disabled: bool = false,
    pub fn need(self: *LazyDeps, b: *std.Build, name: []const u8, args: anytype) ?*std.Build.Dependency {
        if (!self.enabled) {
            self.need_was_disabled = true;
            return null;
        }
        return b.lazyDependency(name, args);
    }
};

const DvuiModule = struct {
    backend: Backend,
    mod: union(enum) {
        disabled: void,
        enabled: *std.Build.Module,
    },
};

fn addDvuiModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    comptime backend: Backend,
) DvuiModule {
    var deps: LazyDeps = .{
        .enabled = b.option(bool, @tagName(backend), b.fmt(
            "Fetches lazy dependencies for the {s} backend",
            .{ @tagName(backend) },
        )) orelse false,
    };

    const system_integration: bool = blk: {
        if (backendSystemPkg(backend)) |name|
            break :blk b.systemIntegrationOption(name, .{});
        break :blk false;
    };

    const dvui_mod = b.addModule("dvui_" ++ @tagName(backend), .{
        .root_source_file = b.path("src/dvui.zig"),
        .target = target,
        .optimize = optimize,
    });

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
        },
    });
    backend_mod.addImport("dvui", dvui_mod);
    dvui_mod.addImport("backend", backend_mod);

    dvui_mod.addCSourceFiles(.{ .files = &.{
        "src/stb/stb_truetype_impl.c",
    } });
    switch (backend) {
        .raylib => {
            var raylib_linux_display: []const u8 = "Both";
            _ = std.process.getEnvVarOwned(b.allocator, "WAYLAND_DISPLAY") catch |err| switch (err) {
                error.EnvironmentVariableNotFound => raylib_linux_display = "X11",
                else => @panic("Unknown error checking for WAYLAND_DISPLAY environment variable"),
            };
            const maybe_ray = deps.need(b, "raylib", .{ .target = target, .optimize = optimize, .linux_display_backend = raylib_linux_display });
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
            if (b.systemIntegrationOption("sdl2", .{})) {
                backend_mod.linkSystemLibrary("SDL2", .{});
            } else {
                const sdl_dep = deps.need(b, "sdl", .{
                    .target = target,
                    .optimize = optimize,
                });
                if (sdl_dep) |sd| {
                    backend_mod.linkLibrary(sd.artifact("SDL2"));
                }
            }
        },
    }
    dvui_mod.addIncludePath(b.path("src/stb"));

    if (b.systemIntegrationOption("freetype", .{})) {
        dvui_mod.linkSystemLibrary("freetype", .{});
    } else {
        const freetype_dep = deps.need(b, "freetype", .{
            .target = target,
            .optimize = optimize,
        });
        if (freetype_dep) |fd| {
            dvui_mod.linkLibrary(fd.artifact("freetype"));
        }
    }

    if (deps.need_was_disabled)
        return .{ .backend = backend, .mod = .disabled };

    return .{ .backend = backend, .mod = .{ .enabled = dvui_mod } };
}

fn addExample(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    comptime name: []const u8,
    dvui: DvuiModule,
) void {
    const exe: struct {
        install: *std.Build.Step,
        run: *std.Build.Step,
    } = blk: {
        switch (dvui.mod) {
            .disabled => {
                const disabled = BackendDisabledStep.create(b, dvui.backend);
                break :blk .{
                    .install = &disabled.step,
                    .run = &disabled.step,
                };
            },
            .enabled => |mod| {
                const exe = b.addExecutable(.{
                    .name = name,
                    .root_source_file = b.path("examples/" ++ name ++ ".zig"),
                    .target = target,
                    .optimize = optimize,
                });
                exe.root_module.addImport("dvui", mod);
                const install = b.addInstallArtifact(exe, .{});
                const run = b.addRunArtifact(exe);
                run.step.dependOn(&install.step);
                break :blk .{
                    .install = &install.step,
                    .run = &run.step,
                };
            },
        }
    };

    const requires = if (backendSystemPkg(dvui.backend)) |system_pkg|
        b.fmt(" (requires -D{s} or --system {s})", .{@tagName(dvui.backend), system_pkg})
    else
        b.fmt(" (requires -D{s})", .{@tagName(dvui.backend)});

    const compile_step = b.step("compile-" ++ name, b.fmt("Compile {s}{s}", .{name, requires}));
    compile_step.dependOn(exe.install);
    b.getInstallStep().dependOn(compile_step);

    const run_step = b.step(name, b.fmt("Run {s}{s}", .{name, requires}));
    run_step.dependOn(exe.run);
}

const BackendDisabledStep = struct {
    step: std.Build.Step,
    backend: Backend,
    pub fn create(owner: *std.Build, backend: Backend) *BackendDisabledStep {
        const disabled = owner.allocator.create(BackendDisabledStep) catch @panic("OOM");
        disabled.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = owner.fmt("Assert {s} backend is disabled", .{@tagName(backend)}),
                .owner = owner,
                .makeFn = make,
            }),
            .backend = backend,
        };
        return disabled;
    }
    fn make(step: *std.Build.Step, prog_node: std.Progress.Node) !void {
        _ = prog_node;
        const disabled: *BackendDisabledStep = @fieldParentPtr("step", step);
        if (backendSystemPkg(disabled.backend)) |system_pkg| return step.fail(
            "the {s} backend requires either -D{0s} to fetch/build its lazy dependencies or --system {s} to use the system package",
            .{@tagName(disabled.backend), system_pkg},
        );
        return step.fail(
            "the {s} backend requires -D{0s} to fetch its lazy dependencies",
            .{@tagName(disabled.backend)},
        );
    }
};

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
//}
