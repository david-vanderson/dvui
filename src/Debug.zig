open: bool = false,
options_editor_open: bool = false,
options_override_list_open: bool = false,
show_frame_times: bool = false,

/// 0 means no widget is selected
widget_id: dvui.Id = .zero,
target: DebugTarget = .none,

/// All functions using the parent are invalid
target_wd: ?dvui.WidgetData = null,

/// Uses `gpa` allocator
///
/// The name slice is also duplicated by the `gpa` allocator
under_mouse_stack: std.ArrayList(struct { id: dvui.Id, name: []const u8 }) = .empty,

/// Uses `gpa` allocator
options_override: std.AutoHashMapUnmanaged(dvui.Id, struct { Options, std.builtin.SourceLocation }) = .empty,

toggle_mutex: Io.Mutex = .init,
log_refresh: bool = false,
log_events: bool = false,

/// A panic will be called from within the targeted widget
widget_panic: bool = false,

/// when true, left mouse button works like a finger
touch_simulate_events: bool = false,
touch_simulate_down: bool = false,

/// Multi-frame capture for `dumpFrame`/`dumpFrames`/`dumpDiff` (machine-readable
/// widget-tree JSON). Off unless armed via `captureFrame` (one frame) or
/// `captureFrames` (a consecutive range). Captured frames accumulate (newest
/// kept, oldest dropped past `capture_max`) so discrete snapshots can be diffed.
/// All `gpa`-owned and persist past the frame, so they can be dumped after
/// `Window.end`. See `captureFrame`, `captureFrames`, `clearCaptures`.
frames: std.ArrayList(CapturedFrame) = .empty,
/// Upcoming frames still to capture (a continuous range, or one armed frame).
capture_remaining: u32 = 0,
/// True only while the in-progress frame is being captured, i.e. between
/// `reset` and `Window.endRendering`.
capturing: bool = false,
/// Cap on retained captured frames; the oldest are dropped beyond this.
capture_max: u32 = 32,
/// Monotonic capture counter, used as each `CapturedFrame.index`.
capture_seq: u64 = 0,

const Debug = @This();

pub const DebugTarget = enum {
    none,
    focused,
    mouse_until_esc,
    mouse_until_click,
    mouse_quitting,

    pub fn mouse(self: DebugTarget) bool {
        return self == .mouse_until_click or self == .mouse_until_esc or self == .mouse_quitting;
    }
};

/// One captured frame: the widget tree recorded between a `Window.begin` and its
/// `Window.endRendering`, in registration (pre-order) order.
pub const CapturedFrame = struct {
    /// Monotonic capture sequence number (`Debug.capture_seq` when recorded).
    index: u64,
    /// `Window.frame_time_ns` of the captured frame.
    time_ns: i128,
    /// Uses `gpa`; widget names are duplicated into it.
    widgets: std.ArrayList(CapturedWidget) = .empty,
};

/// One widget's resolved state, recorded for `dumpFrame`. The rects are physical
/// (screen) pixels. `name` is `gpa`-duplicated; `src_*` point at static strings.
pub const CapturedWidget = struct {
    id: dvui.Id,
    /// Equals `id` for the window root (emitted as null parent in the dump).
    parent_id: dvui.Id,
    name: ?[]const u8,
    src_file: []const u8,
    src_fn: []const u8,
    src_line: u32,
    rect_border: Rect.Physical,
    rect_content: Rect.Physical,
    rect_background: Rect.Physical,
    expand: Options.Expand,
    gravity: Options.Gravity,
    /// Subwindow (floating window / popup) this widget belongs to.
    subwindow_id: dvui.Id,
    background: bool,
    style: dvui.Theme.Style.Name,
    /// Resolved colors (option value or theme fallback), as actually drawn.
    color_fill: dvui.Color,
    color_text: dvui.Color,
    color_border: dvui.Color,
    /// Resolved font (option value or theme body font).
    font: dvui.Font,
    focused: bool,
    active: bool,
    visible: bool,
};

/// Output shape for `dumpFrame`. `nested` rebuilds the parent/child tree (DOM
/// like); `flat` emits a flat array where each node carries its `parent_id`.
pub const DumpShape = enum { nested, flat };

pub const DumpOptions = struct {
    shape: DumpShape = .nested,
};

/// Which two captured frames `dumpDiff` compares (positions in `frames`,
/// 0-based, oldest first). Defaults compare the two most recent.
pub const DiffOptions = struct {
    from: ?usize = null,
    to: ?usize = null,
};

pub fn reset(self: *Debug, gpa: std.mem.Allocator) void {
    if (self.target.mouse()) {
        for (self.under_mouse_stack.items) |item| {
            gpa.free(item.name);
        }
        self.under_mouse_stack.clearRetainingCapacity();
    }
    self.target_wd = null;

    // If frames are still queued to capture, start one now: push a fresh frame
    // and record into it until `Window.endRendering` clears `capturing`.
    if (self.capture_remaining > 0) {
        self.capture_remaining -= 1;
        self.startFrameCapture(gpa);
    } else {
        self.capturing = false;
    }
}

pub fn deinit(self: *Debug, gpa: std.mem.Allocator) void {
    for (self.under_mouse_stack.items) |item| {
        gpa.free(item.name);
    }
    self.under_mouse_stack.clearAndFree(gpa);
    self.options_override.deinit(gpa);
    self.clearCaptures(gpa);
    self.frames.clearAndFree(gpa);

    // This is global, and deinit is usually called during Window.deinit.  But
    // in a testing environment, multiple whole Window init/deinit cycles
    // happen in the same process.  So prevent access-after-free.
    self.under_mouse_stack = .empty;
    self.options_override = .empty;
    self.frames = .empty;
    self.capture_remaining = 0;
    self.capturing = false;
}

/// Arm a machine-readable capture of the next frame's widget tree, read back
/// with `dumpFrame`/`dumpFrames`/`dumpDiff`. Opt-in: nothing is captured until
/// armed, so it costs nothing when off. Repeated calls on different frames
/// accumulate discrete snapshots that can be diffed. The capture covers the
/// build phase only (not the debug inspector or dialogs rendered afterwards).
///
/// Typical headless use: `dvui.debug.captureFrame()`, run one frame, then
/// `dvui.debug.dumpFrame(writer, .{})`.
pub fn captureFrame(self: *Debug) void {
    self.captureFrames(1);
}

/// Arm capture of the next `n` consecutive frames (a continuous range), in
/// addition to any frames still queued.
pub fn captureFrames(self: *Debug, n: u32) void {
    self.capture_remaining +|= n;
}

/// Drop all captured frames.
pub fn clearCaptures(self: *Debug, gpa: std.mem.Allocator) void {
    for (self.frames.items) |*f| freeFrame(gpa, f);
    self.frames.clearRetainingCapacity();
}

/// Number of captured frames currently retained.
pub fn capturedFrameCount(self: *const Debug) usize {
    return self.frames.items.len;
}

/// The most recently captured frame, or null if none. Valid until the next
/// capture or `clearCaptures`.
pub fn lastCapture(self: *const Debug) ?*const CapturedFrame {
    if (self.frames.items.len == 0) return null;
    return &self.frames.items[self.frames.items.len - 1];
}

/// Begin capturing into a fresh frame immediately, mid-frame, to profile a
/// sub-tree: only widgets registered until `captureScopeEnd` are recorded
/// (unlike `captureFrame`, which records a whole frame). Used by `dvui.Profiler`
/// to capture just the profiled target's widget tree. Must be paired with
/// `captureScopeEnd` before `Window.endRendering`.
pub fn captureScopeBegin(self: *Debug, gpa: std.mem.Allocator) void {
    self.startFrameCapture(gpa);
}

/// End a `captureScopeBegin` capture.
pub fn captureScopeEnd(self: *Debug) void {
    self.capturing = false;
}

fn freeFrame(gpa: std.mem.Allocator, frame: *CapturedFrame) void {
    for (frame.widgets.items) |w| if (w.name) |name| gpa.free(name);
    frame.widgets.deinit(gpa);
}

/// Begin recording a new frame (called from `reset`). Enforces `capture_max` by
/// dropping the oldest frames, then appends an empty frame and sets `capturing`.
fn startFrameCapture(self: *Debug, gpa: std.mem.Allocator) void {
    const max = @max(self.capture_max, 1);
    while (self.frames.items.len + 1 > max) {
        var oldest = self.frames.orderedRemove(0);
        freeFrame(gpa, &oldest);
    }
    self.capture_seq += 1;
    self.frames.append(gpa, .{
        .index = self.capture_seq,
        .time_ns = dvui.currentWindow().frame_time_ns,
    }) catch |err| {
        self.capture_remaining = 0;
        self.capturing = false;
        dvui.logError(@src(), err, "Debug.startFrameCapture could not append frame", .{});
        return;
    };
    self.capturing = true;
}

/// Record one widget into the in-progress frame. Called from
/// `WidgetData.register` while `capturing`. Best-effort: a failed allocation
/// drops the widget rather than the frame.
pub fn captureWidget(self: *Debug, gpa: std.mem.Allocator, wd: *const dvui.WidgetData) void {
    if (self.frames.items.len == 0) return;
    const frame = &self.frames.items[self.frames.items.len - 1];
    const name: ?[]const u8 = if (wd.options.name) |n| (gpa.dupe(u8, n) catch null) else null;
    frame.widgets.append(gpa, .{
        .id = wd.id,
        .parent_id = wd.parent.data().id,
        .name = name,
        .src_file = wd.src.file,
        .src_fn = wd.src.fn_name,
        .src_line = wd.src.line,
        .rect_border = wd.borderRectScale().r,
        .rect_content = wd.contentRectScale().r,
        .rect_background = wd.backgroundRectScale().r,
        .expand = wd.options.expandGet(),
        .gravity = wd.options.gravityGet(),
        .subwindow_id = dvui.subwindowCurrentId(),
        .background = wd.options.backgroundGet(),
        .style = wd.options.styleGet(),
        .color_fill = wd.options.color(.fill),
        .color_text = wd.options.color(.text),
        .color_border = wd.options.color(.border),
        .font = wd.options.fontGet(),
        .focused = wd.id == dvui.focusedWidgetId(),
        .active = dvui.captured(wd.id),
        .visible = wd.visible(),
    }) catch |err| {
        if (name) |n| gpa.free(n);
        dvui.logError(@src(), err, "Debug.captureWidget could not append", .{});
    };
}

/// Emit the most recent captured frame as JSON: `{"widgets":[...]}`. `nested`
/// (default) rebuilds the tree with `children` arrays; `flat` emits a flat array
/// where each node carries `parent_id`. Safe with no capture (empty array).
pub fn dumpFrame(self: *const Debug, writer: *std.Io.Writer, opts: DumpOptions) std.Io.Writer.Error!void {
    const empty: []const CapturedWidget = &.{};
    const nodes = if (self.frames.items.len > 0) self.frames.items[self.frames.items.len - 1].widgets.items else empty;
    try writer.writeByte('{');
    try dumpWidgetList(writer, nodes, opts);
    try writer.writeByte('}');
}

/// Emit every captured frame as JSON:
/// `{"frames":[{"index":..,"time_ns":..,"widgets":[...]}, ...]}`.
pub fn dumpFrames(self: *const Debug, writer: *std.Io.Writer, opts: DumpOptions) std.Io.Writer.Error!void {
    try writer.writeAll("{\"frames\":[");
    for (self.frames.items, 0..) |*f, i| {
        if (i != 0) try writer.writeByte(',');
        try writer.print("{{\"index\":{d},\"time_ns\":{d},", .{ f.index, f.time_ns });
        try dumpWidgetList(writer, f.widgets.items, opts);
        try writer.writeByte('}');
    }
    try writer.writeAll("]}");
}

/// Emit the difference between two captured frames, matched by widget `id`:
/// widgets `added` (in `to`, not `from`), `removed` (in `from`, not `to`), and
/// `changed` (in both, with per-field `{from,to}`). `{"diff":null}` if fewer
/// than two frames are captured. See `DiffOptions`.
pub fn dumpDiff(self: *const Debug, writer: *std.Io.Writer, opts: DiffOptions) std.Io.Writer.Error!void {
    const n = self.frames.items.len;
    if (n < 2) {
        try writer.writeAll("{\"diff\":null}");
        return;
    }
    const to_i = @min(opts.to orelse n - 1, n - 1);
    const from_i = @min(opts.from orelse (to_i -| 1), n - 1);
    const a = &self.frames.items[from_i];
    const b = &self.frames.items[to_i];
    try writer.print("{{\"diff\":{{\"from\":{{\"index\":{d},\"time_ns\":{d}}},\"to\":{{\"index\":{d},\"time_ns\":{d}}}", .{ a.index, a.time_ns, b.index, b.time_ns });

    // added: present in `to`, absent from `from`.
    try writer.writeAll(",\"added\":[");
    var first = true;
    for (b.widgets.items) |*w| {
        if (findById(a.widgets.items, w.id) != null) continue;
        if (!first) try writer.writeByte(',');
        first = false;
        try writer.writeByte('{');
        try dumpFields(writer, w);
        try writer.writeByte('}');
    }

    // removed: present in `from`, absent from `to`.
    try writer.writeAll("],\"removed\":[");
    first = true;
    for (a.widgets.items) |*w| {
        if (findById(b.widgets.items, w.id) != null) continue;
        if (!first) try writer.writeByte(',');
        first = false;
        try writer.writeByte('{');
        try dumpFields(writer, w);
        try writer.writeByte('}');
    }

    // changed: present in both, some dumped field differs.
    try writer.writeAll("],\"changed\":[");
    first = true;
    for (b.widgets.items) |*wb| {
        const wa = findById(a.widgets.items, wb.id) orelse continue;
        if (!widgetChanged(wa, wb)) continue;
        if (!first) try writer.writeByte(',');
        first = false;
        try writer.writeAll("{\"id\":");
        try dumpValue(writer, wb.id);
        try dumpLabeled(writer, "name", wb.name);
        try writer.writeAll(",\"changes\":{");
        try dumpWidgetChanges(writer, wa, wb);
        try writer.writeAll("}}");
    }
    try writer.writeAll("]}}");
}

fn findById(nodes: []const CapturedWidget, id: dvui.Id) ?*const CapturedWidget {
    for (nodes) |*n| if (n.id == id) return n;
    return null;
}

/// Emit `"widgets":[...]` in the requested shape (no surrounding object braces).
fn dumpWidgetList(writer: *std.Io.Writer, nodes: []const CapturedWidget, opts: DumpOptions) std.Io.Writer.Error!void {
    try writer.writeAll("\"widgets\":[");
    switch (opts.shape) {
        .flat => for (nodes, 0..) |*n, i| {
            if (i != 0) try writer.writeByte(',');
            try writer.writeByte('{');
            try dumpFields(writer, n);
            try writer.writeByte('}');
        },
        .nested => {
            var first = true;
            for (nodes, 0..) |*n, i| {
                // Roots: the self-parented window root, or any node whose parent
                // wasn't captured (e.g. capture started mid-tree).
                if (n.parent_id != n.id and findById(nodes, n.parent_id) != null) continue;
                if (!first) try writer.writeByte(',');
                first = false;
                try dumpNested(writer, nodes, i);
            }
        },
    }
    try writer.writeByte(']');
}

fn dumpNested(writer: *std.Io.Writer, nodes: []const CapturedWidget, i: usize) std.Io.Writer.Error!void {
    const n = &nodes[i];
    try writer.writeByte('{');
    try dumpFields(writer, n);
    try writer.writeAll(",\"children\":[");
    var first = true;
    for (nodes, 0..) |*c, j| {
        if (j == i or c.parent_id != n.id) continue;
        if (!first) try writer.writeByte(',');
        first = false;
        try dumpNested(writer, nodes, j);
    }
    try writer.writeAll("]}");
}

/// Emit a node's fields (no surrounding braces, no `children`), shared by the
/// flat/nested shapes and the diff `added`/`removed` lists.
fn dumpFields(writer: *std.Io.Writer, n: *const CapturedWidget) std.Io.Writer.Error!void {
    try writer.writeAll("\"id\":");
    try dumpValue(writer, n.id);
    try writer.writeAll(",\"parent_id\":");
    if (n.parent_id == n.id) try writer.writeAll("null") else try dumpValue(writer, n.parent_id);
    try dumpLabeled(writer, "name", n.name);
    try writer.writeAll(",\"src\":{\"file\":");
    try dumpString(writer, n.src_file);
    try writer.writeAll(",\"fn\":");
    try dumpString(writer, n.src_fn);
    try writer.print(",\"line\":{d}}}", .{n.src_line});
    try dumpLabeled(writer, "rect_border", n.rect_border);
    try dumpLabeled(writer, "rect_content", n.rect_content);
    try dumpLabeled(writer, "rect_background", n.rect_background);
    try dumpLabeled(writer, "expand", n.expand);
    try dumpLabeled(writer, "gravity", n.gravity);
    try dumpLabeled(writer, "background", n.background);
    try dumpLabeled(writer, "style", n.style);
    try writer.writeAll(",\"colors\":{\"fill\":");
    try dumpValue(writer, n.color_fill);
    try writer.writeAll(",\"text\":");
    try dumpValue(writer, n.color_text);
    try writer.writeAll(",\"border\":");
    try dumpValue(writer, n.color_border);
    try writer.writeByte('}');
    try dumpLabeled(writer, "font", n.font);
    try dumpLabeled(writer, "subwindow_id", n.subwindow_id);
    try dumpLabeled(writer, "focused", n.focused);
    try dumpLabeled(writer, "active", n.active);
    try dumpLabeled(writer, "visible", n.visible);
}

/// Whether any dumped field differs between two captures of the same widget.
fn widgetChanged(a: *const CapturedWidget, b: *const CapturedWidget) bool {
    return a.parent_id != b.parent_id or
        !optStrEql(a.name, b.name) or
        !std.meta.eql(a.rect_border, b.rect_border) or
        !std.meta.eql(a.rect_content, b.rect_content) or
        !std.meta.eql(a.rect_background, b.rect_background) or
        a.expand != b.expand or
        !std.meta.eql(a.gravity, b.gravity) or
        a.subwindow_id != b.subwindow_id or
        a.background != b.background or
        a.style != b.style or
        !std.meta.eql(a.color_fill, b.color_fill) or
        !std.meta.eql(a.color_text, b.color_text) or
        !std.meta.eql(a.color_border, b.color_border) or
        !std.meta.eql(a.font, b.font) or
        a.focused != b.focused or
        a.active != b.active or
        a.visible != b.visible;
}

/// Emit the differing fields as `"<field>":{"from":..,"to":..}`, comma-separated.
fn dumpWidgetChanges(writer: *std.Io.Writer, a: *const CapturedWidget, b: *const CapturedWidget) std.Io.Writer.Error!void {
    var first = true;
    try diffField(writer, &first, "parent_id", a.parent_id, b.parent_id);
    if (!optStrEql(a.name, b.name)) try diffEmit(writer, &first, "name", a.name, b.name);
    try diffField(writer, &first, "rect_border", a.rect_border, b.rect_border);
    try diffField(writer, &first, "rect_content", a.rect_content, b.rect_content);
    try diffField(writer, &first, "rect_background", a.rect_background, b.rect_background);
    try diffField(writer, &first, "expand", a.expand, b.expand);
    try diffField(writer, &first, "gravity", a.gravity, b.gravity);
    try diffField(writer, &first, "subwindow_id", a.subwindow_id, b.subwindow_id);
    try diffField(writer, &first, "background", a.background, b.background);
    try diffField(writer, &first, "style", a.style, b.style);
    try diffField(writer, &first, "color_fill", a.color_fill, b.color_fill);
    try diffField(writer, &first, "color_text", a.color_text, b.color_text);
    try diffField(writer, &first, "color_border", a.color_border, b.color_border);
    try diffField(writer, &first, "font", a.font, b.font);
    try diffField(writer, &first, "focused", a.focused, b.focused);
    try diffField(writer, &first, "active", a.active, b.active);
    try diffField(writer, &first, "visible", a.visible, b.visible);
}

/// Emit a `from`/`to` field if `a` and `b` differ (compared with `std.meta.eql`,
/// so not for slices — see the `name` special case in `dumpWidgetChanges`).
fn diffField(writer: *std.Io.Writer, first: *bool, comptime label: []const u8, a: anytype, b: @TypeOf(a)) std.Io.Writer.Error!void {
    if (std.meta.eql(a, b)) return;
    try diffEmit(writer, first, label, a, b);
}

fn diffEmit(writer: *std.Io.Writer, first: *bool, comptime label: []const u8, a: anytype, b: @TypeOf(a)) std.Io.Writer.Error!void {
    if (!first.*) try writer.writeByte(',');
    first.* = false;
    try writer.writeAll("\"" ++ label ++ "\":{\"from\":");
    try dumpValue(writer, a);
    try writer.writeAll(",\"to\":");
    try dumpValue(writer, b);
    try writer.writeByte('}');
}

fn optStrEql(a: ?[]const u8, b: ?[]const u8) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;
    return std.mem.eql(u8, a.?, b.?);
}

fn dumpLabeled(writer: *std.Io.Writer, comptime label: []const u8, v: anytype) std.Io.Writer.Error!void {
    try writer.writeAll(",\"" ++ label ++ "\":");
    try dumpValue(writer, v);
}

/// Emit a single JSON value for one of the captured field types. Used by both
/// the node dump and the diff, so they stay in sync.
fn dumpValue(writer: *std.Io.Writer, v: anytype) std.Io.Writer.Error!void {
    const T = @TypeOf(v);
    if (T == Rect.Physical) {
        try writer.print("{{\"x\":{d},\"y\":{d},\"w\":{d},\"h\":{d}}}", .{ v.x, v.y, v.w, v.h });
    } else if (T == dvui.Color) {
        try writer.print("\"#{x:0>2}{x:0>2}{x:0>2}{x:0>2}\"", .{ v.r, v.g, v.b, v.a });
    } else if (T == dvui.Font) {
        try writer.writeAll("{\"family\":");
        try dumpString(writer, dvui.Font.string(&v.family));
        try writer.print(",\"size\":{d},\"weight\":\"{s}\",\"style\":\"{s}\"}}", .{ v.size, @tagName(v.weight), @tagName(v.style) });
    } else if (T == Options.Gravity) {
        try writer.print("{{\"x\":{d},\"y\":{d}}}", .{ v.x, v.y });
    } else if (T == dvui.Id) {
        try writer.print("\"0x{x}\"", .{v.asU64()});
    } else if (T == bool) {
        try writer.print("{}", .{v});
    } else if (T == ?[]const u8) {
        if (v) |s| try dumpString(writer, s) else try writer.writeAll("null");
    } else switch (@typeInfo(T)) {
        .@"enum" => try writer.print("\"{s}\"", .{@tagName(v)}),
        else => @compileError("dumpValue: unsupported type " ++ @typeName(T)),
    }
}

fn dumpString(writer: *std.Io.Writer, s: []const u8) std.Io.Writer.Error!void {
    try writer.writeByte('"');
    for (s) |ch| switch (ch) {
        '"' => try writer.writeAll("\\\""),
        '\\' => try writer.writeAll("\\\\"),
        '\n' => try writer.writeAll("\\n"),
        '\r' => try writer.writeAll("\\r"),
        '\t' => try writer.writeAll("\\t"),
        else => if (ch < 0x20) try writer.print("\\u{x:0>4}", .{ch}) else try writer.writeByte(ch),
    };
    try writer.writeByte('"');
}

pub fn errorOutline(rect: Rect.Physical) void {
    const clipr = dvui.clipGet();
    defer dvui.clipSet(clipr);

    // clip to whole window so we always see the outline
    dvui.clipSet(dvui.windowRectPixels());

    // intersect our rect with the clip - we only want to outline
    // the visible part
    var outline_rect = rect.intersect(clipr);

    // make sure something is visible
    outline_rect.w = @max(outline_rect.w, 1);
    outline_rect.h = @max(outline_rect.h, 1);

    if (dvui.currentWindow().snap_to_pixels) {
        outline_rect.x = @ceil(outline_rect.x) - 0.5;
        outline_rect.y = @ceil(outline_rect.y) - 0.5;
    }

    outline_rect.stroke(.{}, .{ .thickness = 1 * dvui.windowNaturalScale(), .color = .red, .after = true });
}

/// Returns the previous value
///
/// called from any thread
pub fn logEvents(self: *Debug, val: ?bool) bool {
    const io = dvui.io;
    self.toggle_mutex.lockUncancelable(io);
    defer self.toggle_mutex.unlock(io);

    const previous = self.log_events;
    if (val) |v| {
        self.log_events = v;
    }

    return previous;
}

/// Returns the previous value
///
/// called from any thread
pub fn logRefresh(self: *Debug, val: ?bool) bool {
    const io = dvui.io;
    self.toggle_mutex.lockUncancelable(io);
    defer self.toggle_mutex.unlock(io);

    const previous = self.log_refresh;
    if (val) |v| {
        self.log_refresh = v;
    }

    return previous;
}

/// Returns early if `Debug.open` is `false`
pub fn show(self: *Debug) void {
    if (self.show_frame_times) {
        self.showFrameTimes();
    }

    if (!self.open) return;

    if (self.target == .mouse_quitting) {
        self.target = .none;
    }

    // disable so the widgets we are about to use to display this data
    // don't modify the data, otherwise our iterator will get corrupted and
    // even if you search for a widget here, the data won't be available
    var debug_target = self.target;
    self.target = .none;
    defer self.target = debug_target;

    var float = dvui.floatingWindow(@src(), .{ .open_flag = &self.open }, .{ .min_size_content = .{ .w = 300, .h = 600 } });
    defer float.deinit();

    float.dragAreaSet(dvui.windowHeader("DVUI Debug", "", &self.open));

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        var log_refresh = self.logRefresh(null);
        if (dvui.checkbox(@src(), &log_refresh, "Refresh Logging", .{ .gravity_y = 0.5 })) {
            _ = self.logRefresh(log_refresh);
        }

        var custom_label: ?[]const u8 = null;
        var max_fps: f32 = 60;
        if (dvui.currentWindow().max_fps) |mfps| {
            max_fps = mfps;
        } else {
            custom_label = "max fps: unlimited";
        }

        if (dvui.sliderEntry(@src(), "max fps: {d:0.0}", .{ .value = &max_fps, .min = 1, .max = 60, .interval = 1, .label = custom_label }, .{ .min_size_content = .width(200), .gravity_y = 0.5 })) {
            if (max_fps >= 60) {
                dvui.currentWindow().max_fps = null;
            } else {
                dvui.currentWindow().max_fps = max_fps;
            }
        }

        if (dvui.button(@src(), "Frame Times", .{}, .{})) {
            self.show_frame_times = !self.show_frame_times;
        }
    }

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        var log_events = self.logEvents(null);
        if (dvui.checkbox(@src(), &log_events, "Event Logging", .{})) {
            _ = self.logEvents(log_events);
        }

        var wd: dvui.WidgetData = undefined;
        _ = dvui.checkbox(@src(), &dvui.debug.touch_simulate_events, "Simulate Touch", .{ .data_out = &wd });

        dvui.tooltip(@src(), .{ .active_rect = wd.borderRectScale().r, .position = .vertical }, "mouse drag will scroll\ntext layout/entry have draggables and menu", .{}, .{});

        _ = dvui.checkbox(@src(), &dvui.reduce_motion, "Reduce Motion", .{ .data_out = &wd });

        dvui.tooltip(@src(), .{ .active_rect = wd.borderRectScale().r, .position = .vertical }, "animations expire in one frame\ntimers not affected", .{}, .{});
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .all(4) });

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        dvui.labelNoFmt(@src(), "Widget Id:", .{}, .{ .gravity_y = 0.5 });

        var buf: [20]u8 = @splat(0);
        if (self.widget_id != .zero) {
            _ = std.fmt.bufPrint(&buf, "{x}", .{self.widget_id}) catch unreachable;
        }
        var te = dvui.textEntry(@src(), .{
            .text = .{ .buffer = &buf },
        }, .{});
        te.deinit();

        self.widget_id = @enumFromInt(std.fmt.parseInt(u64, std.mem.sliceTo(&buf, 0), 16) catch 0);

        var temp = (debug_target == .focused);
        if (dvui.checkbox(@src(), &temp, "Follow Focus", .{ .gravity_y = 0.5 })) {
            debug_target = if (debug_target == .focused) .none else .focused;
        }
    }

    var tl: dvui.TextLayoutWidget = undefined;
    tl.init(@src(), .{}, .{ .expand = .horizontal });

    {
        var corner_box = dvui.box(@src(), .{}, .{ .gravity_x = 1, .margin = .all(8) });
        defer corner_box.deinit();

        var color: ?dvui.Color = null;
        if (self.widget_id == .zero) {
            // blend text and control colors
            const opts: Options = .{};
            color = .average(opts.color(.text), opts.color(.fill));
        }

        if (dvui.button(@src(), "Edit Options", .{}, .{ .gravity_x = 1, .color_text = color })) {
            if (self.widget_id != .zero) {
                self.options_editor_open = true;
            } else {
                dvui.dialog(@src(), .{}, .{ .title = "Disabled", .message = "Need valid widget Id to edit options" });
            }
        }

        self.widget_panic = false;
        if (dvui.button(@src(), "Panic", .{}, .{ .gravity_x = 1, .color_text = color })) {
            if (self.widget_id != .zero) {
                self.widget_panic = true;
            } else {
                dvui.dialog(@src(), .{}, .{ .title = "Disabled", .message = "Need valid widget Id to panic" });
            }
        }
    }

    if (tl.touchEditing()) |floating_widget| {
        defer floating_widget.deinit();
        tl.touchEditingMenu();
    }
    tl.processEvents();

    if (self.target_wd) |wd| {
        const rs = wd.rectScale();
        tl.format(
            \\{s}
            \\role {?t}
            \\{s}:{d}
            \\min {f}
            \\expand {any}
            \\gravity x {d:0>.2} y {d:0>.2}
            \\margin {f}
            \\border {f}
            \\padding {f}
            \\rs.s {d}
            \\rs.r {f}
        , .{
            wd.options.name orelse "???",
            wd.options.role,
            wd.src.file,
            wd.src.line,
            wd.min_size,
            wd.options.expandGet(),
            wd.options.gravityGet().x,
            wd.options.gravityGet().y,
            wd.options.marginGet(),
            wd.options.borderGet(),
            wd.options.paddingGet(),
            rs.s,
            rs.r,
        }, .{});
    }
    tl.deinit();

    if (self.target_wd) |wd| {
        if (self.options_editor_open) {
            var options, _ = self.options_override.get(wd.id) orelse .{ wd.options, undefined };

            var editor_float = dvui.floatingWindow(@src(), .{
                .open_flag = &self.options_editor_open,
                .stay_above_parent_window = true,
            }, .{});
            defer editor_float.deinit();

            const title = std.fmt.allocPrint(dvui.currentWindow().lifo(), "{x} {s} (+{d})", .{
                wd.id,
                wd.options.name orelse "???",
                wd.options.idExtra(),
            }) catch wd.options.name orelse "???";
            defer dvui.currentWindow().lifo().free(title);

            editor_float.dragAreaSet(dvui.windowHeader(title, "", &self.options_editor_open));

            if (optionsEditor(&options, &wd)) {
                self.options_override.put(dvui.currentWindow().gpa, wd.id, .{ options, wd.src }) catch |err| {
                    dvui.logError(@src(), err, "Could not add the override options for {x} {s}", .{ wd.id, wd.options.name orelse "???" });
                };
            }
        }
    } else {
        self.options_editor_open = false;
    }

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        defer hbox.deinit();

        dvui.label(@src(), "Mouse {any}", .{dvui.mouseType()}, .{ .gravity_x = 1.0 });

        if (dvui.button(@src(), if (debug_target == .mouse_until_click) "Stop (Or Left Click)" else "Debug Under Mouse (until click)", .{}, .{})) {
            debug_target = if (debug_target == .mouse_until_click) .none else .mouse_until_click;
        }
    }

    if (dvui.button(@src(), if (debug_target == .mouse_until_esc) "Stop (Or Press Esc)" else "Debug Under Mouse (until esc)", .{}, .{})) {
        debug_target = if (debug_target == .mouse_until_esc) .none else .mouse_until_esc;
    }

    if (dvui.button(@src(), "Show all option overrides", .{}, .{})) {
        self.options_override_list_open = true;
    }

    if (self.options_override_list_open) {
        var list_float = dvui.floatingWindow(@src(), .{
            .open_flag = &self.options_override_list_open,
            .stay_above_parent_window = true,
        }, .{ .min_size_content = .{ .w = 300, .h = 200 } });
        defer list_float.deinit();

        list_float.dragAreaSet(dvui.windowHeader("Options overrides", "", &self.options_override_list_open));

        var scroll = dvui.scrollArea(@src(), .{}, .{ .min_size_content = .{ .h = 200 }, .expand = .both });
        defer scroll.deinit();

        var menu = dvui.menu(@src(), .vertical, .{ .expand = .horizontal });
        defer menu.deinit();

        var it = self.options_override.iterator();
        var remove_override_id: ?dvui.Id = null;
        while (it.next()) |entry| {
            const id = entry.key_ptr.*;
            const options, const src = entry.value_ptr.*;

            const row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .id_extra = id.asUsize() });
            defer row.deinit();

            var reset_wd: dvui.WidgetData = undefined;
            if (dvui.buttonIcon(@src(), "Reset Option Override", dvui.entypo.back, .{}, .{}, .{
                .gravity_y = 0.5,
                .data_out = &reset_wd,
            })) {
                remove_override_id = id;
            }
            dvui.tooltip(@src(), .{
                .active_rect = reset_wd.borderRectScale().r,
                .position = .vertical,
            }, "Remove the override", .{}, .{});

            var copy_wd: dvui.WidgetData = undefined;
            if (dvui.buttonIcon(@src(), "Copy Option Override", dvui.entypo.copy, .{}, .{}, .{
                .gravity_y = 0.5,
                .data_out = &copy_wd,
            })) {
                copyOptionsToClipboard(id, options);
            }
            dvui.tooltip(@src(), .{
                .active_rect = copy_wd.borderRectScale().r,
                .position = .vertical,
            }, "Copy Options struct to clipboard", .{}, .{});

            {
                var button: dvui.ButtonWidget = undefined;
                button.init(@src(), .{}, .{ .expand = .horizontal });
                defer button.deinit();
                button.processEvents();
                button.drawBackground();

                if (button.clicked()) self.widget_id = id;

                const opts: Options = .{};
                const stack = dvui.box(@src(), .{}, .{
                    .expand = .both,
                    .color_fill = if (button.pressed()) opts.color(.fill_press) else null,
                });
                defer stack.deinit();

                dvui.label(@src(), "{x} {s} (+{d})", .{ id, options.name orelse "???", options.idExtra() }, .{ .padding = .all(1) });
                dvui.label(@src(), "{s}:{d}", .{ src.file, src.line }, .{ .font = dvui.themeGet().font_body.larger(-3), .padding = .all(1) });
            }
        }
        if (remove_override_id) |id| {
            _ = self.options_override.remove(id);
        }
    }

    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .background = false, .min_size_content = .height(200) });
    defer scroll.deinit();

    for (self.under_mouse_stack.items, 0..) |item, i| {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .id_extra = i });
        defer hbox.deinit();

        if (dvui.buttonIcon(@src(), "find", dvui.entypo.magnifying_glass, .{}, .{}, .{})) {
            self.widget_id = item.id;
        }

        dvui.label(@src(), "{x} {s}", .{ item.id, item.name }, .{ .gravity_y = 0.5 });
    }
}

fn showFrameTimes(self: *Debug) void {
    var float = dvui.floatingWindow(@src(), .{ .open_flag = &self.show_frame_times }, .{ .min_size_content = .width(600) });
    defer float.deinit();

    float.dragAreaSet(dvui.windowHeader("Frame Times", "", &self.show_frame_times));

    {
        var b = dvui.box(@src(), .{}, .{ .expand = .horizontal, .gravity_y = 1.0 });
        defer b.deinit();

        var tl = dvui.textLayout(@src(), .{}, .{ .expand = .both });
        defer tl.deinit();

        tl.addText("Shows time (ms) between Window.begin/end for last 400 frames.", .{});
    }

    const uniqueId = dvui.parentGet().extendId(@src(), 0);

    var data = dvui.dataGetSlice(null, uniqueId, "data", []f64) orelse blk: {
        dvui.dataSetSliceCopies(null, uniqueId, "data", &[1]f64{0}, 400);
        break :blk dvui.dataGetSlice(null, uniqueId, "data", []f64) orelse unreachable;
    };

    const cw = dvui.currentWindow();
    const so_far_nanos = @max(cw.frame_time_ns, cw.backend.nanoTime()) - cw.frame_time_ns;
    const so_far_micros: u32 = @intCast(@divFloor(so_far_nanos, 1000));
    const new_data: f64 = @as(f64, so_far_micros) / 1000.0;

    for (0..data.len - 1) |i| {
        data[i] = data[i + 1];
    }
    data[data.len - 1] = new_data;

    var xs = dvui.currentWindow().arena().alloc(f64, data.len) catch @panic("OOM");
    defer dvui.currentWindow().arena().free(xs);

    for (0..data.len) |i| {
        xs[i] = @floatFromInt(i);
    }

    var yaxis: dvui.PlotWidget.Axis = .{
        .name = "ms",
        .min = 0,
        .max = 50,
    };

    dvui.plotXY(@src(), .{ .xs = xs, .ys = data, .plot_opts = .{ .y_axis = &yaxis } }, .{ .expand = .both, .min_size_content = .height(50), .padding = .{ .y = 10, .h = 10 } });
}

const OptionsEditorTab = enum { layout, style, info };

/// Returns true if the options was modified
pub fn optionsEditor(self: *Options, wd: *const dvui.WidgetData) bool {
    var changed = false;

    var vbox = dvui.box(@src(), .{}, .{ .name = "Editor Box", .expand = .both });
    defer vbox.deinit();

    const active_tab = dvui.dataGetPtrDefault(null, vbox.data().id, "Tab", OptionsEditorTab, .layout);
    {
        const tabs = dvui.tabs(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        defer tabs.deinit();

        var button_wd: dvui.WidgetData = undefined;
        if (dvui.buttonIcon(@src(), "Copy Options", dvui.entypo.copy, .{}, .{}, .{ .gravity_x = 1, .data_out = &button_wd })) {
            copyOptionsToClipboard(wd.id, self.*);
        }
        dvui.tooltip(@src(), .{
            .active_rect = button_wd.borderRectScale().r,
            .position = .vertical,
        }, "Copy Options struct to clipboard", .{}, .{});

        if (tabs.addTabLabel(active_tab.* == .layout, "Layout", .{})) {
            active_tab.* = .layout;
        }
        if (tabs.addTabLabel(active_tab.* == .style, "Style", .{})) {
            active_tab.* = .style;
        }
        if (tabs.addTabLabel(active_tab.* == .info, "Info", .{})) {
            active_tab.* = .info;
        }
    }

    switch (active_tab.*) {
        .layout => {
            if (layoutPage(self, vbox.data().id, wd)) changed = true;
        },
        .style => {
            if (stylePage(self, vbox.data().id)) changed = true;
        },
        .info => {
            // Note uses wd.options here instead of self, so it can pick up defaults from the widget, like .role etc.
            infoPage(wd.options);
        },
    }
    return changed;
}

fn copyOptionsToClipboard(id: dvui.Id, options: Options) void {
    dvui.toast(@src(), .{ .message = "Options copied to clipboard" });

    var aw = std.Io.Writer.Allocating.init(dvui.currentWindow().lifo());
    defer aw.deinit();
    aw.writer.print("{f}", .{asZigCode(options)}) catch |err| {
        dvui.logError(@src(), err, "Could not write Options struct for {x} {s}", .{ id, options.name orelse "???" });
    };
    dvui.clipboardTextSet(aw.written());
}

fn sliderRectOptional(src: std.builtin.SourceLocation, comptime label: []const u8, comptime fmt: []const u8, rect: *?Rect, comptime field: std.meta.FieldEnum(dvui.Rect), link_all: bool, default: dvui.Rect) bool {
    return sliderRectOptionalWithInitOpts(src, label, fmt, rect, field, link_all, default, null);
}

/// TODO: find a way to merge this function with the original sliderRectOptionalWithInitOpts function, OR find a way to also include the y and the corner type dropdown
fn sliderCornerOptional(src: std.builtin.SourceLocation, comptime label: []const u8, comptime fmt: []const u8, rect: *?CornerRect, comptime field: std.meta.FieldEnum(dvui.CornerRect), link_all: bool, default: CornerRect) bool {
    var changed: bool = false;
    var hbox = dvui.box(src, .{ .dir = .horizontal }, .{ .min_size_content = .{ .w = 160, .h = 80 }, .max_size_content = .width(160) });
    defer hbox.deinit();
    var value_set: bool = rect.* != null;

    if (dvui.checkbox(
        @src(),
        &value_set,
        if (value_set) "" else label,
        .{ .padding = .{ .x = 6, .y = 6, .h = 6, .w = 0 }, .gravity_y = 0.5 },
    )) {
        changed = true;
        rect.* = if (value_set) default else null;
    }
    if (value_set) {
        const slider_rx_init_opts: dvui.SliderEntryInitOptions = .{ .value = &@field(rect.*.?, @tagName(field)).rx, .min = 0.0, .max = 32.0, .interval = 1.0 };

        if (dvui.sliderEntry(
            @src(),
            label ++ ": " ++ fmt,
            slider_rx_init_opts,
            .{ .margin = .{ .x = 0, .y = 4, .w = 4, .h = 4 }, .gravity_y = 0.5 },
        )) {
            changed = true;
            if (link_all) {
                rect.* = .round(@field(rect.*.?, @tagName(field)).rx);
            }
        }
    }
    return changed;
}

fn sliderRectOptionalWithInitOpts(src: std.builtin.SourceLocation, comptime label: []const u8, comptime fmt: []const u8, rect: *?Rect, comptime field: std.meta.FieldEnum(dvui.Rect), link_all: bool, default: dvui.Rect, init_opts: ?dvui.SliderEntryInitOptions) bool {
    var changed: bool = false;
    var hbox = dvui.box(src, .{ .dir = .horizontal }, .{ .min_size_content = .{ .w = 160 }, .max_size_content = .width(160) });
    defer hbox.deinit();
    var value_set: bool = rect.* != null;

    if (dvui.checkbox(
        @src(),
        &value_set,
        if (value_set) "" else label,
        .{ .padding = .{ .x = 6, .y = 6, .h = 6, .w = 0 }, .gravity_y = 0.5 },
    )) {
        changed = true;
        if (value_set)
            rect.* = default
        else
            rect.* = null;
    }
    if (value_set) {
        const slider_init_opts: dvui.SliderEntryInitOptions = .{
            .value = &@field(rect.*.?, @tagName(field)),
            .min = if (init_opts) |opts| (opts.min orelse 0.0) else 0.0,
            .max = if (init_opts) |opts| (opts.max orelse 32.0) else 32.0,
            .interval = if (init_opts) |opts| (opts.interval orelse 1.0) else 1.0,
        };

        if (dvui.sliderEntry(
            @src(),
            label ++ ": " ++ fmt,
            slider_init_opts,
            .{ .margin = .{ .x = 0, .y = 4, .w = 4, .h = 4 }, .gravity_y = 0.5 },
        )) {
            changed = true;
            if (link_all) {
                rect.* = .all(@field(rect.*.?, @tagName(field)));
            }
        }
    }
    return changed;
}

fn layoutPage(self: *Options, id: dvui.Id, wd: *const dvui.WidgetData) bool {
    var changed = false;

    const link_margin = dvui.dataGetPtrDefault(null, id, "link_margin", bool, true);
    const link_border = dvui.dataGetPtrDefault(null, id, "link_border", bool, true);
    const link_padding = dvui.dataGetPtrDefault(null, id, "link_padding", bool, true);
    const link_radius = dvui.dataGetPtrDefault(null, id, "link_radius", bool, true);

    { // First bar

        {
            var row = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer row.deinit();

            dvui.labelNoFmt(@src(), "expand", .{}, .{ .gravity_y = 0.5 });
            _ = dvui.dropdownEnum(@src(), Options.Expand, .{ .choice_nullable = &self.expand }, .{ .placeholder = "null" }, .{
                .expand = .horizontal,
                .min_size_content = .{ .w = 110 },
                .gravity_y = 0.5,
            });
            _ = dvui.spacer(@src(), .{ .min_size_content = .{ .w = 15 } });
            dvui.labelNoFmt(@src(), "tab_index ", .{}, .{ .margin = .{ .y = 4 } });
            const result = dvui.textEntryNumber(@src(), u16, .{ .placeholder = "null" }, .{});
            switch (result.value) {
                .Valid => |valid| self.tab_index = valid,
                else => self.tab_index = null,
            }
        }
        var rot_rect: ?dvui.Rect = if (self.rotation) |rot| .{ .x = rot } else null;
        var dummy: f32 = 0;
        changed = sliderRectOptionalWithInitOpts(
            @src(),
            "rotation",
            "{d:0.2}",
            &rot_rect,
            .x,
            false,
            .all(wd.options.rotationGet()),
            .{
                .value = &dummy,
                .min = std.math.pi * -2,
                .max = std.math.pi * 2,
                .interval = @as(f32, 0.5 / std.math.pi),
            },
        ) or changed;

        if (rot_rect) |rr| {
            self.rotation = rr.x;
        } else {
            self.rotation = null;
        }
    }

    { // Min size
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer row.deinit();

        var has_min_size = self.min_size_content != null;
        if (dvui.checkbox(@src(), &has_min_size, "min_size_content", .{ .gravity_y = 0.5, .min_size_content = .{ .w = 90 } })) {
            if (self.min_size_content) |_| {
                self.min_size_content = null;
            } else {
                self.min_size_content = .all(100);
            }
            changed = true;
        }

        if (self.min_size_content) |*size| {
            if (dvui.sliderEntry(@src(), "width: {d:0.0}", .{ .value = &size.w, .min = 0, .max = 400.0, .interval = 1 }, .{ .gravity_y = 0.5 })) {
                changed = true;
            }
            if (dvui.sliderEntry(@src(), "height: {d:0.0}", .{ .value = &size.h, .min = 0, .max = 400.0, .interval = 1 }, .{ .gravity_y = 0.5 })) {
                changed = true;
            }
        }
    }

    { // Max size
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer row.deinit();

        var has_max_size = self.max_size_content != null;
        if (dvui.checkbox(@src(), &has_max_size, "max_size_content", .{ .gravity_y = 0.5, .min_size_content = .{ .w = 90 } })) {
            if (self.max_size_content) |_| {
                self.max_size_content = null;
            } else {
                self.max_size_content = .size(.all(400));
            }
            changed = true;
        }

        if (self.max_size_content) |*size| {
            if (dvui.sliderEntry(@src(), "width: {d:0.0}", .{ .value = &size.w, .min = 0, .max = 400.0, .interval = 1 }, .{})) {
                changed = true;
            }
            if (dvui.sliderEntry(@src(), "height: {d:0.0}", .{ .value = &size.h, .min = 0, .max = 400.0, .interval = 1 }, .{})) {
                changed = true;
            }
        }
    }

    { // Top Row
        var row = dvui.box(@src(), .{ .dir = .horizontal, .equal_space = true }, .{});
        defer row.deinit();
        { // Top Left
            var col = dvui.box(@src(), .{}, .{ .border = .all(1), .expand = .vertical });
            defer col.deinit();

            changed = sliderCornerOptional(@src(), "corner_radius", "{d}", &self.corners, .tl, link_radius.*, wd.options.cornersGet()) or changed;
        }
        { // Top Center
            var col = dvui.box(@src(), .{}, .{ .border = .all(1) });
            defer col.deinit();
            changed = sliderRectOptional(@src(), "margin", "{d:0.0}", &self.margin, .y, link_margin.*, wd.options.marginGet()) or changed;
            changed = sliderRectOptional(@src(), "border", "{d:0.0}", &self.border, .y, link_border.*, wd.options.borderGet()) or changed;
            changed = sliderRectOptional(@src(), "padding", "{d:0.0}", &self.padding, .y, link_padding.*, wd.options.paddingGet()) or changed;
        }
        { // Top Right
            var col = dvui.box(@src(), .{}, .{ .border = .all(1), .expand = .vertical });
            defer col.deinit();

            changed = sliderCornerOptional(@src(), "corner_radius", "{d}", &self.corners, .tr, link_radius.*, wd.options.cornersGet()) or changed;
        }
    }

    { // Middle Row
        var row = dvui.box(@src(), .{ .dir = .horizontal, .equal_space = true }, .{});
        defer row.deinit();
        { // Middle Left
            var col = dvui.box(@src(), .{}, .{ .border = .all(1) });
            defer col.deinit();
            changed = sliderRectOptional(@src(), "margin", "{d:0.0}", &self.margin, .x, link_margin.*, wd.options.marginGet()) or changed;
            changed = sliderRectOptional(@src(), "border", "{d:0.0}", &self.border, .x, link_border.*, wd.options.borderGet()) or changed;
            changed = sliderRectOptional(@src(), "padding", "{d:0.0}", &self.padding, .x, link_padding.*, wd.options.paddingGet()) or changed;
        }
        { // Middle Center
            var col = dvui.box(@src(), .{ .dir = .horizontal }, .{ .border = .all(1), .expand = .both });
            defer col.deinit();

            var gravity_set: bool = self.gravity_x != null or self.gravity_y != null;
            var gravity = self.gravityGet();
            gravity.y = 1 - gravity.y;

            if (gravity_set)
                if (dvui.slider(@src(), .{ .dir = .vertical, .fraction = &gravity.y }, .{ .expand = .vertical })) {
                    //                self.gravity_y.? = 1.0 - gravity_y.*;
                    changed = true;
                };

            var side = dvui.box(@src(), .{}, .{ .expand = .both });
            defer side.deinit();

            changed = dvui.checkbox(@src(), &gravity_set, "gravity", .{ .gravity_y = 0.5 }) or changed;

            if (gravity_set) {
                if (dvui.slider(@src(), .{ .fraction = &gravity.x }, .{ .expand = .horizontal, .gravity_y = 1 })) {
                    changed = true;
                }
                self.gravity_x = gravity.x;
                self.gravity_y = 1 - gravity.y;
            } else {
                self.gravity_x = null;
                self.gravity_y = null;
            }
        }
        { // Middle Right
            var col = dvui.box(@src(), .{}, .{ .border = .all(1) });
            defer col.deinit();
            changed = sliderRectOptional(@src(), "margin", "{d:0.0}", &self.margin, .w, link_margin.*, wd.options.marginGet()) or changed;
            changed = sliderRectOptional(@src(), "border", "{d:0.0}", &self.border, .w, link_border.*, wd.options.borderGet()) or changed;
            changed = sliderRectOptional(@src(), "padding", "{d:0.0}", &self.padding, .w, link_padding.*, wd.options.paddingGet()) or changed;
        }
    }

    { // Bottom Row
        var row = dvui.box(@src(), .{ .dir = .horizontal, .equal_space = true }, .{});
        defer row.deinit();
        { // Bottom Left
            var col = dvui.box(@src(), .{}, .{ .border = .all(1), .expand = .vertical });
            defer col.deinit();

            changed = sliderCornerOptional(@src(), "corner_radius", "{d}", &self.corners, .bl, link_radius.*, wd.options.cornersGet()) or changed;
        }
        { // Bottom Center
            var col = dvui.box(@src(), .{}, .{ .border = .all(1) });
            defer col.deinit();
            changed = sliderRectOptional(@src(), "margin", "{d:0.0}", &self.margin, .h, link_margin.*, wd.options.marginGet()) or changed;
            changed = sliderRectOptional(@src(), "border", "{d:0.0}", &self.border, .h, link_border.*, wd.options.borderGet()) or changed;
            changed = sliderRectOptional(@src(), "padding", "{d:0.0}", &self.padding, .h, link_padding.*, wd.options.paddingGet()) or changed;
        }
        { // Bottom Right
            var col = dvui.box(@src(), .{}, .{ .border = .all(1), .expand = .vertical });
            defer col.deinit();

            changed = sliderCornerOptional(@src(), "corner_radius", "{d}", &self.corners, .br, link_radius.*, wd.options.cornersGet()) or changed;
        }
    }

    {
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer row.deinit();

        dvui.labelNoFmt(@src(), "Link: ", .{}, .{});

        if (dvui.checkbox(@src(), link_margin, "margin", .{})) {
            if (self.margin) |*margin| {
                margin.* = .all(margin.x);
                changed = true;
            }
        }
        if (dvui.checkbox(@src(), link_border, "border", .{})) {
            if (self.border) |*border| {
                border.* = .all(border.x);
                changed = true;
            }
        }
        if (dvui.checkbox(@src(), link_padding, "padding", .{})) {
            if (self.padding) |*padding| {
                padding.* = .all(padding.x);
                changed = true;
            }
        }
        if (dvui.checkbox(@src(), link_radius, "corner_radius", .{})) {
            if (self.corners) |*radius| {
                radius.* = .all(radius.tl.rx);
                changed = true;
            }
        }
    }

    return changed;
}

fn stylePage(self: *Options, id: dvui.Id) bool {
    var changed = false;
    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
    defer scroll.deinit();
    {
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });

        var background = self.backgroundGet();
        if (dvui.checkbox(@src(), &background, "background", .{ .gravity_y = 0.5 })) {
            changed = true;
            self.background = if (background) background else null;
        }

        row.deinit();
        row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .margin = .{ .y = 5 } });
        defer row.deinit();

        const OptionsColors = enum { fill, fill_hover, fill_press, text, text_hover, text_press, border };
        const active_color = dvui.dataGetPtrDefault(null, id, "Color", OptionsColors, .fill);

        {
            const tabs = dvui.tabs(@src(), .{ .dir = .vertical }, .{ .expand = .vertical });
            defer tabs.deinit();

            const colors = comptime std.meta.tags(OptionsColors);
            inline for (colors, 0..) |color_ask, i| {
                const tab = tabs.addTab(active_color.* == color_ask, .{}, .{
                    .expand = .horizontal,
                    .padding = .all(2),
                    .id_extra = i,
                });
                defer tab.deinit();

                if (tab.clicked()) {
                    active_color.* = color_ask;
                }

                var label_opts = tab.data().options.strip();
                if (dvui.captured(tab.data().id)) {
                    label_opts.color_text = label_opts.color(.text_press);
                }

                const field = "color_" ++ @tagName(color_ask);
                const color = @field(self, field);

                const color_indicator = dvui.overlay(@src(), .{
                    .expand = .ratio,
                    .min_size_content = .all(10),
                    .corners = .all(100),
                    .border = .all(1),
                    .background = true,
                    .color_fill = color,
                });
                const color_width = color_indicator.data().rectScale().r.w;
                if (color == null) {
                    dvui.labelNoFmt(@src(), "?", .{}, .{ .expand = .ratio, .gravity_x = 0.5, .gravity_y = 0.5 });
                }
                color_indicator.deinit();
                dvui.labelNoFmt(@src(), @tagName(color_ask), .{}, .{ .margin = .{ .x = color_width } });
            }
        }

        {
            var vbox = dvui.box(@src(), .{}, .{});
            defer vbox.deinit();

            const field: *?dvui.Color, const default: dvui.Color = switch (active_color.*) {
                inline else => |c| .{
                    &@field(self, "color_" ++ @tagName(c)),
                    self.color(std.meta.stringToEnum(dvui.Options.ColorAsk, @tagName(c)) orelse unreachable),
                },
            };
            var hsv = dvui.Color.HSV.fromColor(field.* orelse default);
            if (dvui.colorPicker(@src(), .{ .hsv = &hsv, .dir = .horizontal }, .{})) {
                changed = true;
                field.* = hsv.toColor();
            }

            if (field.* != null and dvui.button(@src(), "Set to null", .{}, .{})) {
                changed = true;
                field.* = null;
            }
        }
    }
    _ = dvui.spacer(@src(), .{ .expand = .horizontal, .margin = Rect.all(6) });
    changed = fontChanger(self) or changed;
    _ = dvui.spacer(@src(), .{ .expand = .horizontal, .margin = Rect.all(6) });
    const box_shadow_orig = self.box_shadow;
    const label_str = if (self.box_shadow == null) "box_shadow not set" else "box_shadow";
    if (dvui.expander(@src(), label_str, .{ .default_expanded = self.box_shadow != null }, .{ .expand = .horizontal })) {
        var vbox = dvui.box(@src(), .{}, .{
            .expand = .horizontal,
            .border = .{ .x = 1 },
            .background = true,
            .margin = .{ .w = 12, .x = 12 },
            .padding = Rect.all(6),
        });
        defer vbox.deinit();
        var al: dvui.Alignment = .init(@src(), 0);
        defer al.deinit();
        const T = Options.BoxShadow;
        var box_shadow: Options.BoxShadow = self.box_shadow orelse .{};
        quickDisplayField(@src(), T, "color", &box_shadow.color, .default, &al);
        quickDisplayField(@src(), T, "offset", &box_shadow.offset, .default, &al);
        quickDisplayField(@src(), T, "fade", &box_shadow.fade, .default, &al);
        quickDisplayField(@src(), T, "alpha", &box_shadow.alpha, .default, &al);
        quickDisplayField(@src(), T, "shrink", &box_shadow.shrink, .default, &al);
        quickDisplayField(@src(), T, "corner_radius", &box_shadow.corners, .default, &al);
        self.box_shadow = box_shadow;
    } else {
        self.box_shadow = null;
    }
    if (box_shadow_orig == null and self.box_shadow != null or box_shadow_orig != null and self.box_shadow == null) {
        changed = true;
    } else if (box_shadow_orig != null and self.box_shadow != null) {
        changed = !std.mem.eql(u8, std.mem.asBytes(&self.box_shadow.?), std.mem.asBytes(&box_shadow_orig.?));
    }

    return changed;
}

fn fontChanger(self: *Options) bool {
    var changed = false;

    const label_str = if (self.font == null) "font not set" else "font";
    if (dvui.expander(@src(), label_str, .{ .default_expanded = self.font != null }, .{ .expand = .horizontal })) {
        changed = self.font == null;
        var edited_font = self.fontGet();

        var vbox = dvui.box(@src(), .{}, .{
            .expand = .horizontal,
            .border = .{ .x = 1 },
            .background = true,
            .margin = .{ .w = 12, .x = 12 },
            .padding = Rect.all(6),
        });
        defer vbox.deinit();

        var current_font_index: ?usize = null;
        var current_font_name: []const u8 = "Unknown";
        for (dvui.currentWindow().fonts.database.items, 0..) |dbs, i| {
            if (std.mem.eql(u8, dbs.familyName(), edited_font.familyName())) {
                current_font_index = i;
                current_font_name = edited_font.familyName();
            }
        }

        var dd: dvui.DropdownWidget = undefined;
        dd.init(@src(), .{ .selected_index = current_font_index, .label = current_font_name }, .{});
        if (dd.dropped()) {
            for (dvui.currentWindow().fonts.database.items) |dbs| {
                const name = dbs.name(dvui.currentWindow().lifo());
                defer dvui.currentWindow().lifo().free(name);
                if (dd.addChoiceLabel(name)) {
                    edited_font = edited_font.withFamily(dbs.familyName()).withStyle(dbs.style).withWeight(dbs.weight);
                    changed = true;
                }
            }
        }
        dd.deinit();
        if (dvui.sliderEntry(@src(), "Size: {d:0}", .{ .min = 4, .max = 100, .interval = 1, .value = &edited_font.size }, .{})) {
            changed = true;
        }
        if (dvui.sliderEntry(@src(), "Line height: {d:0.1}", .{ .min = 0, .max = 10, .interval = 0.1, .value = &edited_font.line_height_factor }, .{})) {
            changed = true;
        }

        if (changed) {
            self.font = edited_font;
        }
    } else {
        self.font = null;
        changed = true;
    }

    return changed;
}

fn quickDisplayField(comptime src: std.builtin.SourceLocation, ContainerT: type, comptime field_name: []const u8, field_value_ptr: anytype, field_option: dvui.struct_ui.FieldOptions, al: *dvui.Alignment) void {
    const rect_opts: dvui.struct_ui.StructOptions(dvui.Rect) = .init(.{
        .x = .{ .number = .{ .min = 0, .max = 30, .widget_type = .slider_entry } },
        .y = .{ .number = .{ .min = 0, .max = 30, .widget_type = .slider_entry } },
        .h = .{ .number = .{ .min = 0, .max = 30, .widget_type = .slider_entry } },
        .w = .{ .number = .{ .min = 0, .max = 30, .widget_type = .slider_entry } },
    }, .{});

    const size_opts: dvui.struct_ui.StructOptions(dvui.Size) = .init(.{
        .h = .{ .number = .{ .min = 0, .max = 30, .widget_type = .slider_entry } },
        .w = .{ .number = .{ .min = 0, .max = 30, .widget_type = .slider_entry } },
    }, .{});

    const point_opts: dvui.struct_ui.StructOptions(dvui.Point) = .init(.{
        .x = .{ .number = .{ .min = 0, .max = 30, .widget_type = .slider_entry } },
        .y = .{ .number = .{ .min = 0, .max = 30, .widget_type = .slider_entry } },
    }, .{});

    const color_opts: dvui.struct_ui.StructOptions(dvui.Color) = .init(.{
        .r = .{ .number = .{ .widget_type = .slider_entry, .min = 0, .max = 255 } },
        .g = .{ .number = .{ .widget_type = .slider_entry, .min = 0, .max = 255 } },
        .b = .{ .number = .{ .widget_type = .slider_entry, .min = 0, .max = 255 } },
        .a = .{ .number = .{ .widget_type = .slider_entry, .min = 0, .max = 255 } },
    }, .{});

    dvui.struct_ui.displayField(src, ContainerT, field_name, field_value_ptr, 10, field_option, .{
        rect_opts,
        color_opts,
        size_opts,
        point_opts,
    }, al);
}

fn infoPage(self: Options) void {
    var al: dvui.Alignment = .init(@src(), 0);
    defer al.deinit();
    var vbox = dvui.box(@src(), .{}, .{ .expand = .horizontal });
    defer vbox.deinit();
    {
        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
            defer hbox.deinit();
            dvui.labelNoFmt(@src(), "name: ", .{}, .{});
            al.spacer(@src(), 0);
            var tl = dvui.textLayout(@src(), .{}, .{ .background = false });
            if (self.name) |name| {
                tl.addText(name, .{});
            } else {
                tl.addText("null", .{});
            }
            tl.deinit();
        }
        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
            defer hbox.deinit();
            dvui.labelNoFmt(@src(), "role: ", .{}, .{});
            al.spacer(@src(), 0);
            var tl = dvui.textLayout(@src(), .{}, .{ .background = false });
            if (self.role) |role| {
                tl.addText(@tagName(role), .{});
            } else {
                tl.addText("null", .{});
            }
            tl.deinit();
        }
        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
            defer hbox.deinit();
            dvui.labelNoFmt(@src(), "tag: ", .{}, .{});
            al.spacer(@src(), 0);
            var tl = dvui.textLayout(@src(), .{}, .{ .background = false });
            if (self.tag) |tag| {
                tl.addText(tag, .{});
            } else {
                tl.addText("null", .{});
            }
            tl.deinit();
        }
        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
            defer hbox.deinit();
            dvui.labelNoFmt(@src(), "id_extra: ", .{}, .{});
            al.spacer(@src(), 0);
            var tl = dvui.textLayout(@src(), .{}, .{ .background = false });
            if (self.id_extra) |id_extra| {
                const str = std.fmt.allocPrint(dvui.currentWindow().arena(), "{d}", .{id_extra}) catch "";
                tl.addText(str, .{});
            } else {
                tl.addText("null", .{});
            }
            tl.deinit();
        }
        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
            defer hbox.deinit();
            dvui.labelNoFmt(@src(), "label: ", .{}, .{});
            al.spacer(@src(), 0);
            var tl = dvui.textLayout(@src(), .{}, .{ .background = false });
            if (self.label) |label| {
                const str = switch (label) {
                    .by_id => |id| std.fmt.allocPrint(dvui.currentWindow().arena(), "by_id = {x}", .{id}) catch "",
                    .for_id => |id| std.fmt.allocPrint(dvui.currentWindow().arena(), "for_id = {x}", .{id}) catch "",
                    .label_widget => |val| std.fmt.allocPrint(dvui.currentWindow().arena(), "label_widget = {t}", .{val}) catch "",
                    .text => |val| std.fmt.allocPrint(dvui.currentWindow().arena(), "text = \"{s}\"", .{val}) catch "",
                };
                tl.addText(str, .{});
            } else {
                tl.addText("null", .{});
            }
            tl.deinit();
        }
        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
            defer hbox.deinit();
            dvui.labelNoFmt(@src(), "rect: ", .{}, .{});
            al.spacer(@src(), 0);
            var tl = dvui.textLayout(@src(), .{}, .{ .background = false });
            if (self.rect) |rect| {
                const str = std.fmt.allocPrint(dvui.currentWindow().arena(), "x = {d}, y = {d}, h = {d}, w = {d}", .{ rect.x, rect.y, rect.h, rect.w }) catch "";
                tl.addText(str, .{});
            } else {
                tl.addText("null", .{});
            }
            tl.deinit();
        }
    }
}

/// Used to copy the code for any runtime type, used to copy
/// modified `Options`.s
pub fn ZigCodeFormatter(comptime T: type) type {
    return struct {
        value: T,
        pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            switch (@typeInfo(T)) {
                .optional => if (self.value) |v|
                    try writer.print("{f}", .{asZigCode(v)})
                else
                    try writer.writeAll("null"),
                .null => try writer.writeAll("null"),
                .@"enum" => try writer.print(".{t}", .{self.value}),
                .float, .int, .comptime_float, .comptime_int => try writer.print("{d}", .{self.value}),
                .bool => try writer.print("{s}", .{if (self.value) "true" else "false"}),
                .pointer => |ptr| {
                    switch (ptr.size) {
                        .one => switch (@typeInfo(ptr.child)) {
                            .array => try writer.print("{f}", .{asZigCode(self.value.*)}),
                            else => @compileError("Cannot write single item pointer"),
                        },
                        .c, .many, .slice => if (ptr.child == u8)
                            try writer.print("\"{s}\"", .{self.value})
                        else
                            @compileError("Cannot write non string many item pointer"),
                    }
                },
                .array => |array| if (array.child == u8) {
                    try writer.print("\"{s}\"", .{self.value});
                } else {
                    try writer.writeAll(".{ ");
                    for (self.value) |v| {
                        try writer.print("{f}", .{asZigCode(v)});
                        try writer.writeAll(", ");
                    }
                    try writer.writeAll("}");
                },
                .@"struct" => |struct_info| {
                    try writer.writeAll(".{ ");
                    inline for (struct_info.fields) |field| blk: {
                        const ti = @typeInfo(field.type);
                        // Ignore single item pointers
                        const ptr_info: ?std.builtin.Type.Pointer = switch (ti) {
                            .pointer => |ptr| ptr,
                            .optional => |opt| if (@typeInfo(opt.child) == .pointer)
                                @typeInfo(opt.child).pointer
                            else
                                null,
                            else => null,
                        };
                        if (ptr_info != null and ptr_info.?.size == .one and @typeInfo(ptr_info.?.child) != .array) {
                            continue;
                        }
                        if (field.defaultValue() != null and ti == .optional and @field(self.value, field.name) == null) {
                            break :blk;
                        }
                        try writer.print(".{s} = ", .{field.name});
                        try writer.print("{f}", .{asZigCode(@field(self.value, field.name))});
                        try writer.writeAll(", ");
                    }
                    try writer.writeAll("}");
                },
                .@"union" => switch (std.meta.activeTag(self.value)) {
                    inline else => |tag| if (@FieldType(T, @tagName(tag)) == void) {
                        try writer.print(".{s}", .{@tagName(tag)});
                    } else {
                        try writer.print(".{{ .{s} = ", .{@tagName(tag)});
                        try writer.print("{f}", .{asZigCode(@field(self.value, @tagName(tag)))});
                        try writer.writeAll(" }");
                    },
                },
                .void => {},
                else => @compileError("Unhandled field type: " ++ @typeName(T)),
            }
        }
    };
}

pub fn asZigCode(value: anytype) ZigCodeFormatter(@TypeOf(value)) {
    return .{ .value = value };
}

test asZigCode {
    var writeBuffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writeBuffer);

    try writer.print("{f}", .{asZigCode(@as(f32, 12.34))});
    try std.testing.expectEqualStrings("12.34", writer.buffered());
    _ = writer.consumeAll();
    try writer.print("{f}", .{asZigCode(@as(f32, 12))});
    try std.testing.expectEqualStrings("12", writer.buffered());
    _ = writer.consumeAll();
    try writer.print("{f}", .{asZigCode(@as(u8, 43))});
    try std.testing.expectEqualStrings("43", writer.buffered());
    _ = writer.consumeAll();
    try writer.print("{f}", .{asZigCode(@as(i32, -5423))});
    try std.testing.expectEqualStrings("-5423", writer.buffered());
    _ = writer.consumeAll();

    try writer.print("{f}", .{asZigCode(true)});
    try std.testing.expectEqualStrings("true", writer.buffered());
    _ = writer.consumeAll();
    try writer.print("{f}", .{asZigCode(false)});
    try std.testing.expectEqualStrings("false", writer.buffered());
    _ = writer.consumeAll();

    try writer.print("{f}", .{asZigCode(@as(?f32, null))});
    try std.testing.expectEqualStrings("null", writer.buffered());
    _ = writer.consumeAll();

    try writer.print("{f}", .{asZigCode(@as([]const u8, "testing"))});
    try std.testing.expectEqualStrings(
        \\"testing"
    , writer.buffered());
    _ = writer.consumeAll();
    try writer.print("{f}", .{asZigCode(@as(*const [7]u8, "testing"))});
    try std.testing.expectEqualStrings(
        \\"testing"
    , writer.buffered());
    _ = writer.consumeAll();

    try writer.print("{f}", .{asZigCode(@as([3]u32, .{ 12, 34, 56 }))});
    try std.testing.expectEqualStrings(
        \\.{ 12, 34, 56, }
    , writer.buffered());
    _ = writer.consumeAll();

    try writer.print("{f}", .{asZigCode(@as(enum { a, b }, .a))});
    try std.testing.expectEqualStrings(".a", writer.buffered());
    _ = writer.consumeAll();

    const A = struct {
        a: bool,
        b: u32 = 123,
        c: ?[]const u8 = null,
    };

    try writer.print("{f}", .{asZigCode(A{ .a = true })});
    try std.testing.expectEqualStrings(
        // Expect that `c` is not included as it defaults to `null`
        \\.{ .a = true, .b = 123, }
    , writer.buffered());
    _ = writer.consumeAll();
    try writer.print("{f}", .{asZigCode(A{ .a = false, .c = "testing text" })});
    try std.testing.expectEqualStrings(
        \\.{ .a = false, .b = 123, .c = "testing text", }
    , writer.buffered());
    _ = writer.consumeAll();

    const B = union(enum) {
        a: u32,
        b: struct { a: ?[]const u8 = null, b: f32 },
        c,
    };

    try writer.print("{f}", .{asZigCode(B{ .a = 123 })});
    try std.testing.expectEqualStrings(
        \\.{ .a = 123 }
    , writer.buffered());
    _ = writer.consumeAll();
    try writer.print("{f}", .{asZigCode(B{ .b = .{ .b = 0.001 } })});
    try std.testing.expectEqualStrings(
        \\.{ .b = .{ .b = 0.001, } }
    , writer.buffered());
    _ = writer.consumeAll();
    try writer.print("{f}", .{asZigCode(B.c)});
    try std.testing.expectEqualStrings(
        // the value type here is void, so it should use the shorthand
        \\.c
    , writer.buffered());
    _ = writer.consumeAll();
}

test "dumpFrame captures the widget tree as JSON" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .name = "outer", .style = .window });
            defer box.deinit();
            dvui.label(@src(), "hi", .{}, .{});
            return .ok;
        }
    }.frame;

    // Settle first, then capture a stable frame. `captureFrame` starts at the
    // next `Window.begin`; in a real begin/frame/end loop one frame suffices,
    // but `testing.step` runs `frame()` before its `begin`, so two steps are
    // needed here: the first arms capture at its trailing begin, the second
    // builds the captured widgets.
    try dvui.testing.settle(frame);
    dvui.debug.captureFrame();
    _ = try dvui.testing.step(frame);
    _ = try dvui.testing.step(frame);

    const buf = try std.testing.allocator.alloc(u8, 64 * 1024);
    defer std.testing.allocator.free(buf);

    // nested (default): a tree with `children` arrays, a self-parented root.
    var w = std.Io.Writer.fixed(buf);
    try dvui.debug.dumpFrame(&w, .{});
    const nested = w.buffered();
    try std.testing.expect(std.mem.startsWith(u8, nested, "{\"widgets\":["));
    try std.testing.expect(std.mem.indexOf(u8, nested, "\"children\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, nested, "\"parent_id\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, nested, "\"name\":\"outer\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, nested, "\"rect_border\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, nested, "Debug.zig") != null);
    // enriched fields: resolved style/colors/font.
    try std.testing.expect(std.mem.indexOf(u8, nested, "\"colors\":{\"fill\":\"#") != null);
    try std.testing.expect(std.mem.indexOf(u8, nested, "\"font\":{\"family\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, nested, "\"style\":\"window\"") != null);

    // flat: no `children`, every node carries `parent_id`.
    var w2 = std.Io.Writer.fixed(buf);
    try dvui.debug.dumpFrame(&w2, .{ .shape = .flat });
    const flat = w2.buffered();
    try std.testing.expect(std.mem.indexOf(u8, flat, "\"children\":") == null);
    try std.testing.expect(std.mem.indexOf(u8, flat, "\"parent_id\":") != null);
}

/// Frame counter for `diffFrame`, which renders slightly different content on
/// even vs odd ticks so consecutive captures differ.
var diff_test_tick: u32 = 0;

fn diffFrame() !dvui.App.Result {
    defer diff_test_tick += 1;
    var root = dvui.box(@src(), .{ .dir = .vertical }, .{
        .expand = .both,
        .name = "root",
        .background = (diff_test_tick % 2 == 0),
    });
    defer root.deinit();
    dvui.label(@src(), "hi", .{}, .{ .name = "title" });
    if (diff_test_tick % 2 == 0) {
        dvui.label(@src(), "extra", .{}, .{ .name = "extra" });
    }
    return .ok;
}

test "multi-frame capture, dumpFrames and dumpDiff" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    diff_test_tick = 0;
    try dvui.testing.settle(diffFrame);

    // Continuous range: arm two frames. `testing.step` runs frame() before its
    // begin, so 2 captured frames need 3 steps (the first only arms).
    dvui.debug.captureFrames(2);
    _ = try dvui.testing.step(diffFrame);
    _ = try dvui.testing.step(diffFrame);
    _ = try dvui.testing.step(diffFrame);
    try std.testing.expectEqual(@as(usize, 2), dvui.debug.capturedFrameCount());

    const buf = try std.testing.allocator.alloc(u8, 128 * 1024);
    defer std.testing.allocator.free(buf);

    // dumpFrames: both frames, each with an index/time_ns and a widget list.
    var w = std.Io.Writer.fixed(buf);
    try dvui.debug.dumpFrames(&w, .{});
    const frames_json = w.buffered();
    try std.testing.expect(std.mem.startsWith(u8, frames_json, "{\"frames\":["));
    try std.testing.expect(std.mem.indexOf(u8, frames_json, "\"index\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, frames_json, "\"time_ns\":") != null);

    // dumpDiff: the "extra" label is added/removed and "root" background flips,
    // across the two captured frames (one even tick, one odd).
    var w2 = std.Io.Writer.fixed(buf);
    try dvui.debug.dumpDiff(&w2, .{});
    const diff = w2.buffered();
    try std.testing.expect(std.mem.indexOf(u8, diff, "\"diff\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, diff, "\"added\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, diff, "\"removed\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, diff, "\"changed\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, diff, "extra") != null);
    try std.testing.expect(std.mem.indexOf(u8, diff, "\"background\":{\"from\":") != null);
}

const Options = dvui.Options;
const Rect = dvui.Rect;
const CornerRect = dvui.CornerRect;

const std = @import("std");
const Io = std.Io;
const dvui = @import("dvui.zig");
