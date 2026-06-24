//! Headless CLI that renders one dvui frame with the (windowless) testing
//! backend and prints a machine-readable JSON dump of the resolved widget tree
//! to stdout. Intended for LLM-assisted UI analysis, CI golden snapshots, and
//! Turian Studio's "inspect frame" panel.
//!
//! Build/run: `zig build frame-dump` (nested JSON, default)
//!            `zig build frame-dump -- --flat`
//!
//! See `dvui.Debug.captureFrame` / `dvui.Debug.dumpFrame`.

const std = @import("std");
const dvui = @import("dvui");
const Backend = @import("testing-backend");

/// The UI whose frame we dump. A small but non-trivial tree (boxes, labels,
/// buttons) so the output exercises nesting, rects, styles, and fonts.
fn frame() !dvui.App.Result {
    var vbox = dvui.box(@src(), .{ .dir = .vertical }, .{
        .expand = .both,
        .background = true,
        .style = .window,
        .name = "root",
    });
    defer vbox.deinit();

    dvui.label(@src(), "Guinevere frame dump", .{}, .{ .name = "title" });

    {
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .name = "buttons" });
        defer row.deinit();
        _ = dvui.button(@src(), "OK", .{}, .{ .name = "ok" });
        _ = dvui.button(@src(), "Cancel", .{}, .{ .name = "cancel" });
    }

    dvui.label(@src(), "status: ready", .{}, .{ .name = "status" });

    return .ok;
}

/// One begin/frame/end cycle, the minimal headless equivalent of an app loop.
fn runFrame(win: *dvui.Window) !void {
    try win.begin(win.backend.nanoTime());
    _ = try frame();
    _ = try win.end(.{});
}

pub fn main(init: std.process.Init) !void {
    // --flat / --nested selects the dump shape (nested is the default).
    var shape: dvui.Debug.DumpShape = .nested;
    var it = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer it.deinit();
    _ = it.next(); // exe name
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--flat")) {
            shape = .flat;
        } else if (std.mem.eql(u8, arg, "--nested")) {
            shape = .nested;
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

    // Run a few frames so layout and fonts settle, then capture one. Because we
    // drive begin/frame/end in the natural order, `captureFrame` arms at the
    // next `begin` and that single frame is captured in full (see `dumpFrame`).
    for (0..4) |_| try runFrame(&win);
    dvui.debug.captureFrame();
    try runFrame(&win);

    var out_buf: [64 * 1024]u8 = undefined;
    var fw = std.Io.File.stdout().writer(init.io, &out_buf);
    try dvui.debug.dumpFrame(&fw.interface, .{ .shape = shape });
    try fw.interface.writeByte('\n');
    try fw.flush();
}
