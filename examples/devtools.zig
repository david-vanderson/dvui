//! Proof-of-concept Guinevere DevTools: a browser-style profiler that *owns* the
//! window and frame loop and runs a target app's GUI under instrumentation. The
//! target (here, the dvui examples) never touches the window — the devtools call
//! its GUI function inside `dvui.Profiler.run`, which times it, captures its
//! widget tree, and shows a perf chart + tree navigator + inspector.
//!
//! This is the basis for Turian's in-engine GUI profiler.
//!
//! Run: `zig build devtools`

const std = @import("std");
const dvui = @import("dvui");
const SDLBackend = @import("sdl3gpu-backend");

/// Persisted across frames: the profiler's history ring and selection.
var prof: dvui.Profiler = .{};

/// The profiled target: the dvui examples. Swap this for any `fn () void` of
/// GUI calls (e.g. a Turian scene's GUI) to profile it instead.
fn target() void {
    dvui.Examples.demo(.lite);
}

pub fn main(init: std.process.Init) !void {
    var backend = try SDLBackend.initWindow(.{
        .io = init.io,
        .allocator = init.gpa,
        .size = .{ .w = 1280.0, .h = 800.0 },
        .min_size = .{ .w = 640.0, .h = 480.0 },
        .vsync = true,
        .title = "Guinevere DevTools",
    });
    defer backend.deinit();

    var window_open = true;
    var win = try dvui.Window.init(@src(), init.gpa, backend.backend(), .{ .open_flag = &window_open });
    defer win.deinit();

    dvui.Examples.show_demo_window = true;

    var interrupted = false;
    while (window_open) {
        const nstime = win.beginWait(interrupted);
        try win.begin(nstime);
        _ = try backend.addAllEvents(&win);

        // The devtools own the frame; the target's GUI runs inside the profiler.
        prof.run(@src(), target);

        const end_micros = try win.end(.{});
        const wait_micros = win.waitTime(end_micros);
        interrupted = try backend.waitEventTimeout(wait_micros);
    }
}
