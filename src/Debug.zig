open: bool = false,
/// 0 means no widget is selected
widget_id: dvui.WidgetId = .zero,
target: DebugTarget = .none,

/// All functions using the parent are invalid
target_wd: ?dvui.WidgetData = null,

/// Uses `gpa` allocator
///
/// The name slice is also duplicated by the `gpa` allocator
under_mouse_stack: std.ArrayListUnmanaged(struct { id: dvui.WidgetId, name: []const u8 }) = .empty,

toggle_mutex: std.Thread.Mutex = .{},
log_refresh: bool = false,
log_events: bool = false,

/// A panic will be called from within the targeted widget
widget_panic: bool = false,

/// when true, left mouse button works like a finger
touch_simulate_events: bool = false,
touch_simulate_down: bool = false,

const Debug = @This();

pub const DebugTarget = enum {
    none,
    focused,
    mouse_until_esc,
    mouse_until_click,
    quitting,

    pub fn mouse(self: DebugTarget) bool {
        return self == .mouse_until_click or self == .mouse_until_esc;
    }
};

pub fn reset(self: *Debug, gpa: std.mem.Allocator) void {
    if (self.target.mouse()) {
        for (self.under_mouse_stack.items) |item| {
            gpa.free(item.name);
        }
        self.under_mouse_stack.clearRetainingCapacity();
    }
    self.target_wd = null;
}

pub fn deinit(self: *Debug, gpa: std.mem.Allocator) void {
    for (self.under_mouse_stack.items) |item| {
        gpa.free(item.name);
    }
    self.under_mouse_stack.clearAndFree(gpa);
}

/// Returns the previous value
///
/// called from any thread
pub fn logEvents(self: *Debug, val: ?bool) bool {
    self.toggle_mutex.lock();
    defer self.toggle_mutex.unlock();

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
    self.toggle_mutex.lock();
    defer self.toggle_mutex.unlock();

    const previous = self.log_refresh;
    if (val) |v| {
        self.log_refresh = v;
    }

    return previous;
}

/// Returns early if `Debug.open` is `false`
pub fn show(self: *Debug) void {
    if (!self.open) return;

    if (self.target == .quitting) {
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
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.labelNoFmt(@src(), "Hex id of widget to highlight:", .{}, .{ .gravity_y = 0.5 });

        var buf = [_]u8{0} ** 20;
        if (self.widget_id != .zero) {
            _ = std.fmt.bufPrint(&buf, "{x}", .{self.widget_id}) catch unreachable;
        }
        var te = dvui.textEntry(@src(), .{
            .text = .{ .buffer = &buf },
        }, .{});
        te.deinit();

        self.widget_id = @enumFromInt(std.fmt.parseInt(u64, std.mem.sliceTo(&buf, 0), 16) catch 0);
    }

    var tl = dvui.TextLayoutWidget.init(@src(), .{}, .{ .expand = .horizontal, .min_size_content = .{ .h = 250 } });
    tl.install(.{});

    self.widget_panic = false;

    var color: ?dvui.Options.ColorOrName = null;
    if (self.widget_id == .zero) {
        // blend text and control colors
        color = .{ .color = dvui.Color.average(dvui.themeGet().color_text, dvui.themeGet().color_fill_control) };
    }
    if (dvui.button(@src(), "Panic", .{}, .{ .gravity_x = 1.0, .margin = dvui.Rect.all(8), .color_text = color })) {
        if (self.widget_id != .zero) {
            self.widget_panic = true;
        } else {
            dvui.dialog(@src(), .{}, .{ .title = "Disabled", .message = "Need valid widget Id to panic" });
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
            \\{x} {s}
            \\
            \\{}
            \\min {}
            \\{}
            \\scale {d}
            \\padding {}
            \\border {}
            \\margin {}
            \\
            \\{s}:{d}
            \\id_extra {?d}
        , .{
            wd.id,
            wd.options.name orelse "???",
            rs.r,
            wd.min_size,
            wd.options.expandGet(),
            rs.s,
            wd.options.paddingGet().scale(rs.s, dvui.Rect.Physical),
            wd.options.borderGet().scale(rs.s, dvui.Rect.Physical),
            wd.options.marginGet().scale(rs.s, dvui.Rect.Physical),
            wd.src.file,
            wd.src.line,
            wd.options.id_extra,
        }, .{});
    }
    tl.deinit();

    if (dvui.button(@src(), if (debug_target == .mouse_until_click) "Stop (Or Left Click)" else "Debug Under Mouse (until click)", .{}, .{})) {
        debug_target = .mouse_until_click;
    }

    if (dvui.button(@src(), if (debug_target == .mouse_until_esc) "Stop (Or Press Esc)" else "Debug Under Mouse (until esc)", .{}, .{})) {
        debug_target = .mouse_until_esc;
    }

    if (dvui.button(@src(), if (debug_target == .focused) "Stop Debugging Focus" else "Debug Focus", .{}, .{})) {
        debug_target = if (debug_target == .focused) .none else .focused;
    }

    var log_refresh = self.logRefresh(null);
    if (dvui.checkbox(@src(), &log_refresh, "Refresh Logging", .{})) {
        _ = self.logRefresh(log_refresh);
    }

    var log_events = self.logEvents(null);
    if (dvui.checkbox(@src(), &log_events, "Event Logging", .{})) {
        _ = self.logEvents(log_events);
    }
    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .background = false, .min_size_content = .height(200) });
    defer scroll.deinit();

    for (self.under_mouse_stack.items, 0..) |item, i| {
        var hbox = dvui.box(@src(), .horizontal, .{ .id_extra = i });
        defer hbox.deinit();

        if (dvui.buttonIcon(@src(), "find", dvui.entypo.magnifying_glass, .{}, .{}, .{})) {
            self.widget_id = item.id;
        }

        dvui.label(@src(), "{x} {s}", .{ item.id, item.name }, .{ .gravity_y = 0.5 });
    }
}

const std = @import("std");
const dvui = @import("dvui.zig");
