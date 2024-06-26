const std = @import("std");
const Pkg = std.Build.Pkg;
const Compile = std.Build.Step.Compile;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dvui_mod = b.addModule("dvui", .{
        .root_source_file = b.path("src/dvui.zig"),
    });

    dvui_mod.addCSourceFiles(.{ .files = &.{
        "src/stb/stb_image_impl.c",
        "src/stb/stb_truetype_impl.c",
    } });

    dvui_mod.addIncludePath(b.path("src/stb"));

    const freetype_dep = b.lazyDependency("freetype", .{
        .target = target,
        .optimize = optimize,
    });

    if (freetype_dep) |fd| {
        dvui_mod.linkLibrary(fd.artifact("freetype"));
    }

    const sdl_mod = b.addModule("SDLBackend", .{
        .root_source_file = b.path("src/backends/SDLBackend.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sdl_mod.addImport("dvui", dvui_mod);
    linkSDL(b, sdl_mod, target, optimize);

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
            .root_source_file = b.path(ex ++ ".zig"),
            .target = target,
            .optimize = optimize,
        });

        exe.root_module.addImport("dvui", dvui_mod);
        exe.root_module.addImport("SDLBackend", sdl_mod);
        linkSDL(b, &exe.root_module, target, optimize);

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
            .root_source_file = b.path("sdl-test.zig"),
            .target = target,
            .optimize = optimize,
        });

        exe.root_module.addImport("dvui", dvui_mod);
        exe.root_module.addImport("SDLBackend", sdl_mod);

        const exe_install = b.addInstallArtifact(exe, .{});

        const compile_step = b.step("compile-sdl-test", "Compile the SDL test");
        compile_step.dependOn(&exe_install.step);
        b.getInstallStep().dependOn(compile_step);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(compile_step);

        const run_step = b.step("sdl-test", "Run the SDL test");
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
            .root_source_file = b.path("web-test.zig"),
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

        const install_step = b.addInstallArtifact(wasm, .{
            .dest_dir = .{ .override = .{ .custom = "bin" } },
        });

        cacheBusterStep = std.Build.Step.init(.{
            .id = .custom,
            .name = "cache-buster",
            .owner = b,
            .makeFn = cacheBuster,
            .first_ret_addr = @returnAddress(),
        });
        cacheBusterStep.dependOn(&install_step.step);

        const compile_step = b.step("web-test", "Compile the Web test");
        compile_step.dependOn(&cacheBusterStep);

        compile_step.dependOn(&b.addInstallFileWithDir(b.path("src/backends/index.html"), .prefix, "bin/index.html").step);
        compile_step.dependOn(&b.addInstallFileWithDir(b.path("src/backends/WebBackend.js"), .prefix, "bin/WebBackend.js").step);

        b.getInstallStep().dependOn(compile_step);
    }

    // color conversion test
    //{
    //    const exe = b.addExecutable(.{
    //        .name = "test_color",
    //        .root_source_file = .{ .path = "src/test_color.zig" },
    //        .target = target,
    //        .optimize = optimize,
    //    });

    //    const c_lib = b.addStaticLibrary(.{
    //        .name = "hsluv",
    //        .target = target,
    //        .optimize = optimize,
    //    });
    //    c_lib.addCSourceFile(.{ .file = .{ .path = "src/hsluv.c" }, .flags = &.{} });
    //    c_lib.linkLibC();
    //    exe.linkLibrary(c_lib);

    //    exe.addIncludePath(.{ .path = "src" });
    //    exe.linkLibC();
    //    b.installArtifact(exe);

    //    const run_exe = b.addRunArtifact(exe);

    //    const run_step = b.step("test_color", "Run test_color");
    //    run_step.dependOn(&run_exe.step);
    //}
}

var cacheBusterStep: std.Build.Step = undefined;

fn cacheBuster(step: *std.Build.Step, _: std.Progress.Node) !void {
    _ = step;
    std.debug.print("cacheBuster\n", .{});

    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arena = arena_allocator.allocator();
    defer arena_allocator.deinit();

    const path = "zig-out/bin/index.html";
    const needle = "TIMESTAMP";
    var file = try std.fs.cwd().openFile(path, .{});
    var contents = try file.reader().readAllAlloc(arena, 100 * 1024 * 1024);
    const index = std.mem.indexOf(u8, contents, needle);
    file.close();

    if (index) |idx| {
        var newfile = try std.fs.cwd().createFile(path, .{});
        defer newfile.close();
        try newfile.writer().writeAll(contents[0..idx]);
        try newfile.writer().print("{d}", .{std.time.nanoTimestamp()});
        try newfile.writer().writeAll(contents[idx + needle.len ..]);
    }
}

fn linkSDL(b: *std.Build, mod: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    if (target.result.cpu.arch == .wasm32) {
        // nothing
    } else if (target.result.os.tag == .windows) {
        const sdl_dep = b.lazyDependency("sdl", .{
            .target = target,
            .optimize = optimize,
        });

        if (sdl_dep) |sd| {
            mod.linkLibrary(sd.artifact("SDL2"));
        }

        mod.linkSystemLibrary("setupapi", .{});
        mod.linkSystemLibrary("winmm", .{});
        mod.linkSystemLibrary("gdi32", .{});
        mod.linkSystemLibrary("imm32", .{});
        mod.linkSystemLibrary("version", .{});
        mod.linkSystemLibrary("oleaut32", .{});
        mod.linkSystemLibrary("ole32", .{});
    } else {
        if (target.result.os.tag.isDarwin()) {
            mod.linkSystemLibrary("z", .{});
            mod.linkSystemLibrary("bz2", .{});
            mod.linkSystemLibrary("iconv", .{});
            mod.linkFramework("AppKit", .{});
            mod.linkFramework("AudioToolbox", .{});
            mod.linkFramework("Carbon", .{});
            mod.linkFramework("Cocoa", .{});
            mod.linkFramework("CoreAudio", .{});
            mod.linkFramework("CoreFoundation", .{});
            mod.linkFramework("CoreGraphics", .{});
            mod.linkFramework("CoreHaptics", .{});
            mod.linkFramework("CoreVideo", .{});
            mod.linkFramework("ForceFeedback", .{});
            mod.linkFramework("GameController", .{});
            mod.linkFramework("IOKit", .{});
            mod.linkFramework("Metal", .{});
        }

        mod.linkSystemLibrary("SDL2", .{});
        //mod.addIncludePath(.{.path = "/Users/dvanderson/SDL2-2.24.1/include"});
        //mod.addObjectFile(.{.path = "/Users/dvanderson/SDL2-2.24.1/build/.libs/libSDL2.a"});
    }
}
