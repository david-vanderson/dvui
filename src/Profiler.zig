//! A browser-DevTools-style profiler for a dvui GUI: a perf chart, a navigable
//! widget tree, and an inspector. The controlling app owns the window and the
//! frame loop and hands the *target* app's GUI to `Profiler.run` as a plain
//! function; the profiler invokes it inside an instrumented viewport so it can
//! time it and capture its widget tree (via `Debug.captureScopeBegin/End`)
//! without the target ever touching the window.
//!
//! Persist one `Profiler` across frames (the app owns a `var prof: Profiler`)
//! and call `prof.run(@src(), targetFn)` once per dvui frame.
//!
//! This is the basis for Turian's in-engine GUI profiler; it consumes the same
//! data as `Window.renderStats` (#1), `Window.frameTiming` (#3), and
//! `Debug.dumpFrame` (#2).

const std = @import("std");
const dvui = @import("dvui.zig");

const Profiler = @This();
const CapturedWidget = dvui.Debug.CapturedWidget;

pub const history_len = 240;

pub const Sample = struct {
    /// Wall-clock CPU time of the target's GUI calls (target-only, excludes the
    /// devtools UI and rendering).
    target_build_ns: u64 = 0,
    draw_calls: u32 = 0,
    triangles: u32 = 0,
};

/// Ring buffer of recent per-frame samples; `head` is the next write slot.
history: [history_len]Sample = @splat(.{}),
head: usize = 0,
count: usize = 0,
/// Most recent target build time, for the readout.
last_build_ns: u64 = 0,

/// Render one profiler frame: run `target` in an instrumented viewport on the
/// left, the devtools panels on the right. Call once per dvui frame.
pub fn run(self: *Profiler, src: std.builtin.SourceLocation, target: *const fn () void) void {
    var outer = dvui.box(src, .{ .dir = .horizontal }, .{ .expand = .both, .name = "profiler" });
    defer outer.deinit();

    // --- target viewport (left): time + capture only the target's tree ---
    {
        var viewport = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both, .name = "target_viewport" });
        defer viewport.deinit();

        const cw = dvui.currentWindow();
        const t0 = cw.backend.nanoTime();
        dvui.debug.captureScopeBegin(cw.gpa);
        target();
        dvui.debug.captureScopeEnd();
        self.record(@intCast(@max(0, cw.backend.nanoTime() - t0)));
    }

    // --- devtools sidebar (right) ---
    {
        var sidebar = dvui.box(@src(), .{ .dir = .vertical }, .{
            .expand = .vertical,
            .min_size_content = .{ .w = 340, .h = 0 },
            .background = true,
            .style = .window,
            .name = "devtools",
        });
        defer sidebar.deinit();

        self.chartPanel();
        self.statsPanel();
        self.treePanel();
        self.inspectorPanel();
    }
}

fn record(self: *Profiler, build_ns: u64) void {
    const rs = dvui.currentWindow().renderStats();
    self.history[self.head] = .{ .target_build_ns = build_ns, .draw_calls = rs.draw_calls, .triangles = rs.triangles };
    self.head = (self.head + 1) % history_len;
    if (self.count < history_len) self.count += 1;
    self.last_build_ns = build_ns;
}

fn chartPanel(self: *Profiler) void {
    var box = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .horizontal, .name = "chart" });
    defer box.deinit();

    dvui.label(@src(), "target build time (ms)", .{}, .{ .font = dvui.Font.theme(.heading) });

    const arena = dvui.currentWindow().arena();
    const xs = arena.alloc(f64, history_len) catch return;
    const ys = arena.alloc(f64, history_len) catch return;
    defer arena.free(xs);
    defer arena.free(ys);
    for (0..history_len) |i| {
        // oldest (at head) first, newest last
        const idx = (self.head + i) % history_len;
        xs[i] = @floatFromInt(i);
        ys[i] = ms(self.history[idx].target_build_ns);
    }
    var yaxis: dvui.PlotWidget.Axis = .{ .name = "ms", .min = 0 };
    dvui.plotXY(@src(), .{ .xs = xs, .ys = ys, .plot_opts = .{ .y_axis = &yaxis } }, .{
        .expand = .horizontal,
        .min_size_content = .{ .w = 0, .h = 80 },
        .padding = .{ .y = 6, .h = 6 },
    });
}

fn statsPanel(self: *Profiler) void {
    const cw = dvui.currentWindow();
    const rs = cw.renderStats();
    const ft = cw.frameTiming();
    dvui.label(@src(), "target build : {d:.3} ms", .{ms(self.last_build_ns)}, .{});
    dvui.label(@src(), "frame total  : {d:.3} ms", .{ms(ft.total_ns)}, .{});
    dvui.label(@src(), "  build {d:.3}  render {d:.3}", .{ ms(ft.build_ns), ms(ft.render_ns) }, .{});
    dvui.label(@src(), "draw calls {d}  tris {d}", .{ rs.draw_calls, rs.triangles }, .{});
}

fn treePanel(_: *Profiler) void {
    dvui.label(@src(), "widget tree", .{}, .{ .font = dvui.Font.theme(.heading) });

    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .min_size_content = .{ .w = 0, .h = 180 } });
    defer scroll.deinit();

    const cap = dvui.debug.lastCapture() orelse return;
    const nodes = cap.widgets.items;
    const arena = dvui.currentWindow().arena();

    for (nodes, 0..) |*node, i| {
        const depth = nodeDepth(nodes, node);
        const nm = node.name orelse "(widget)";
        const text = std.fmt.allocPrint(arena, "{s}  {s}:{d} {x}", .{ nm, std.fs.path.basename(node.src_file), node.src_line, node.id }) catch nm;
        const selected = node.id == dvui.debug.widget_id;
        if (dvui.button(@src(), text, .{}, .{
            .id_extra = i,
            .expand = .horizontal,
            .gravity_x = 0,
            .margin = .{ .x = @floatFromInt(depth * 14), .y = 1, .h = 1 },
            .style = if (selected) .highlight else .control,
        })) {
            dvui.debug.widget_id = if (selected) .zero else node.id;
        }
    }
}

fn inspectorPanel(_: *Profiler) void {
    if (dvui.debug.widget_id == .zero) return;
    const cap = dvui.debug.lastCapture() orelse return;
    const node = findById(cap.widgets.items, dvui.debug.widget_id) orelse return;

    var box = dvui.box(@src(), .{ .dir = .vertical }, .{
        .expand = .horizontal,
        .background = true,
        .style = .content,
        .name = "inspector",
    });
    defer box.deinit();

    dvui.label(@src(), "selected: {s}", .{node.name orelse "(widget)"}, .{ .font = dvui.Font.theme(.heading) });
    dvui.label(@src(), "src   {s}:{d}", .{ std.fs.path.basename(node.src_file), node.src_line }, .{});
    dvui.label(@src(), "rect  x{d:.0} y{d:.0}  {d:.0}x{d:.0}", .{ node.rect_border.x, node.rect_border.y, node.rect_border.w, node.rect_border.h }, .{});
    dvui.label(@src(), "expand {s}  style {s}", .{ @tagName(node.expand), @tagName(node.style) }, .{});
    dvui.label(@src(), "font  {s} {d:.0}", .{ dvui.Font.string(&node.font.family), node.font.size }, .{});
    dvui.label(@src(), "focused {} active {} visible {}", .{ node.focused, node.active, node.visible }, .{});
}

fn ms(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / 1_000_000.0;
}

fn findById(nodes: []const CapturedWidget, id: dvui.Id) ?*const CapturedWidget {
    for (nodes) |*n| if (n.id == id) return n;
    return null;
}

/// Depth of `node` within `nodes` by walking captured ancestors.
fn nodeDepth(nodes: []const CapturedWidget, node: *const CapturedWidget) usize {
    var depth: usize = 0;
    var cur = node;
    while (cur.parent_id != cur.id) {
        const parent = findById(nodes, cur.parent_id) orelse break;
        depth += 1;
        cur = parent;
    }
    return depth;
}

var test_prof: Profiler = .{};

fn testTarget() void {
    var b = dvui.box(@src(), .{}, .{ .name = "target_inner", .expand = .both });
    defer b.deinit();
    dvui.label(@src(), "hello", .{}, .{ .name = "target_label" });
}

fn testFrame() !dvui.App.Result {
    test_prof.run(@src(), testTarget);
    return .ok;
}

test "profiler runs target, records samples, captures only the target tree" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 900, .h = 600 } });
    defer t.deinit();
    test_prof = .{};

    for (0..5) |_| _ = try dvui.testing.step(testFrame);

    // Samples were recorded for the perf chart.
    try std.testing.expect(test_prof.count > 0);

    // The scoped capture holds the target's widgets but NOT the devtools UI:
    // this is the core "devtools instruments the target" guarantee.
    const cap = dvui.debug.lastCapture() orelse return error.NoCapture;
    var found_target = false;
    var found_devtools = false;
    for (cap.widgets.items) |*w| {
        const nm = w.name orelse continue;
        if (std.mem.eql(u8, nm, "target_inner")) found_target = true;
        if (std.mem.eql(u8, nm, "devtools") or std.mem.eql(u8, nm, "chart")) found_devtools = true;
    }
    try std.testing.expect(found_target);
    try std.testing.expect(!found_devtools);
}

test {
    @import("std").testing.refAllDecls(@This());
}
