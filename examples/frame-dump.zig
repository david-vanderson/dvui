//! Headless CLI that renders dvui frames with the (windowless) testing backend
//! and prints a machine-readable JSON dump of the resolved widget tree to
//! stdout. Intended for LLM-assisted UI analysis, CI golden snapshots, and
//! Turian Studio's "inspect frame" panel.
//!
//! Build/run:
//!   zig build frame-dump                 one frame, nested JSON (default)
//!   zig build frame-dump -- --flat       one frame, flat JSON
//!   zig build frame-dump -- --frames 3   three consecutive frames
//!   zig build frame-dump -- --diff       diff of two consecutive frames
//!
//! See `dvui.Debug.captureFrame` / `captureFrames` / `dumpFrame` / `dumpFrames`
//! / `dumpDiff`.

const std = @import("std");
const dvui = @import("dvui");
const Backend = @import("testing-backend");

/// Frame counter so the demo UI changes slightly each frame (an extra label and
/// a flipped background on even ticks), making `--diff` show real differences.
var tick: u32 = 0;

/// The UI whose frames we dump. A small but non-trivial tree (boxes, labels,
/// buttons) so the output exercises nesting, rects, styles, fonts, and changes.
fn frame() !dvui.App.Result {
    var vbox = dvui.box(@src(), .{ .dir = .vertical }, .{
        .expand = .both,
        .background = true,
        .style = .window,
        .name = "root",
    });
    defer vbox.deinit();

    dvui.label(@src(), "Guinevere frame dump (tick {d})", .{tick}, .{ .name = "title" });

    {
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{
            .name = "buttons",
            .background = (tick % 2 == 0),
        });
        defer row.deinit();
        _ = dvui.button(@src(), "OK", .{}, .{ .name = "ok" });
        _ = dvui.button(@src(), "Cancel", .{}, .{ .name = "cancel" });
    }

    if (tick % 2 == 0) {
        dvui.label(@src(), "extra row", .{}, .{ .name = "extra" });
    }

    dvui.label(@src(), "status: ready", .{}, .{ .name = "status" });

    return .ok;
}

/// One begin/frame/end cycle, the minimal headless equivalent of an app loop.
fn runFrame(win: *dvui.Window) !void {
    try win.begin(win.backend.nanoTime());
    _ = try frame();
    _ = try win.end(.{});
    tick += 1;
}

const Mode = union(enum) { single, frames: u32, diff };

pub fn main(init: std.process.Init) !void {
    var shape: dvui.Debug.DumpShape = .nested;
    var mode: Mode = .single;

    var it = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer it.deinit();
    _ = it.next(); // exe name
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--flat")) {
            shape = .flat;
        } else if (std.mem.eql(u8, arg, "--nested")) {
            shape = .nested;
        } else if (std.mem.eql(u8, arg, "--diff")) {
            mode = .diff;
        } else if (std.mem.eql(u8, arg, "--frames")) {
            const n = it.next() orelse return error.MissingFramesArgument;
            mode = .{ .frames = try std.fmt.parseInt(u32, n, 10) };
        }
    }

    // Headless dvui window via the testing backend (no OS window, no rendering).
    dvui.io = init.io;
    var backend: Backend = .init(.{
        .allocator = init.gpa,
        .size = .{ .w = 800, .h = 600 },
        .size_pixels = .{ .w = 1600, .h = 1200 },
    });
    defer backend.deinit();

    var win = try dvui.Window.init(@src(), init.gpa, backend.backend(), .{
        .color_scheme = .light,
        .keybinds = .windows,
    });
    defer win.deinit();

    // Run a few frames so layout and fonts settle. Because we drive
    // begin/frame/end in the natural order, an armed capture records exactly the
    // requested number of subsequent frames in full.
    for (0..4) |_| try runFrame(&win);

    var out_buf: [64 * 1024]u8 = undefined;
    var fw = std.Io.File.stdout().writer(init.io, &out_buf);
    const out = &fw.interface;

    switch (mode) {
        .single => {
            dvui.debug.captureFrame();
            try runFrame(&win);
            try dvui.debug.dumpFrame(out, .{ .shape = shape });
        },
        .frames => |n| {
            dvui.debug.captureFrames(n);
            for (0..n) |_| try runFrame(&win);
            try dvui.debug.dumpFrames(out, .{ .shape = shape });
        },
        .diff => {
            dvui.debug.captureFrames(2);
            try runFrame(&win);
            try runFrame(&win);
            try dvui.debug.dumpDiff(out, .{});
        },
    }
    try out.writeByte('\n');
    try fw.flush();
}
