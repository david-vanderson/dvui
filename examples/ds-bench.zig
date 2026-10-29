//! Headless benchmark for the `dvui.profiling` recording overhead.
//!
//! The point is a *counter* comparison, not a time measurement: run it twice
//! under `perf stat -e instructions` (or callgrind, or `cachegrind`) with
//! recording off and on, and the difference in retired instructions is what
//! recording costs. Wall clock is not consulted anywhere here; the loop is a
//! fixed frame count so both runs execute the same widget code.
//!
//! Build/run:
//!   zig build ds-bench -Dbackend=testing -Doptimize=ReleaseFast
//!   perf stat -e instructions,cycles ./zig-out/bin/ds-bench
//!   DVUI_PROFILE_RECORD=1 perf stat -e instructions,cycles ./zig-out/bin/ds-bench
//!
//! The final line on stdout is the map activity the run produced, so the two
//! runs can be checked to have done the same work.

const std = @import("std");
const dvui = @import("dvui");
const Backend = @import("testing-backend");

const frames_default: usize = 300;

fn frame() !dvui.App.Result {
    // The demo window is the heaviest map user in the tree: tags, per-widget
    // data, min sizes and animations all run per frame.
    dvui.Examples.show_demo_window = true;
    dvui.Examples.demo(.lite);
    return .ok;
}

pub fn main(init: std.process.Init) !void {
    var frames = frames_default;
    var kerning = true;
    var it = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer it.deinit();
    _ = it.next(); // exe name
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--no-kerning")) {
            kerning = false;
        } else if (std.mem.eql(u8, arg, "--frames")) {
            const n = it.next() orelse return error.MissingFramesArgument;
            frames = try std.fmt.parseInt(usize, n, 10);
        }
    }

    if (init.environ_map.get("DVUI_PROFILE_RECORD")) |rec| {
        dvui.profiling.recording = !std.mem.eql(u8, rec, "0");
    }
    dvui.io = init.io;

    var backend: Backend = .init(.{
        .allocator = init.gpa,
        .size = .{ .w = 1000, .h = 700 },
        .size_pixels = .{ .w = 2000, .h = 1400 },
    });
    defer backend.deinit();

    var win = try dvui.Window.init(@src(), init.gpa, backend.backend(), .{
        .color_scheme = .light,
        .keybinds = .windows,
    });
    defer win.deinit();
    win.kerning = kerning;

    var t: i128 = 0;
    for (0..frames) |_| {
        t += 16 * std.time.ns_per_ms;
        try win.begin(t);
        _ = try frame();
        _ = try win.end(.{});
    }

    const reads = dvui.ContextLayer.read_stats;
    const totals = dvui.profiling.totals();
    var out_buf: [256]u8 = undefined;
    var fw = std.Io.File.stdout().writer(init.io, &out_buf);
    try fw.interface.print("recording={} freetype={} kerning={} maps={d} live={d} puts={d} gets={d} dead={d} rescans={d}\n", .{
        dvui.profiling.recording,
        dvui.useFreeType,
        win.kerning,
        totals.maps,
        totals.live,
        totals.puts,
        totals.gets,
        totals.dead,
        totals.rescans,
    });
    try fw.interface.print("context reads: getters={d} colors={d} fonts={d} sizes={d} overrides={d} copies={d}\n", .{
        reads.getters, reads.colors, reads.fonts, reads.sizes, reads.overrides, reads.copies,
    });
    try fw.flush();
}
