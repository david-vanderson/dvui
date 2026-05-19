const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Point = dvui.Point;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const ContextWidget = @This();

pub const InitOptions = struct {
    /// physical rect where right-click triggers the context menu
    rect: Rect.Physical,
};

const HoldState = struct {
    pending: bool = false,
    press_ns: i128 = 0,
    press_p: Point.Physical = .{},
    button: dvui.enums.Button = .none,
    event_num: u16 = 0,
};

wd: WidgetData,
init_options: InitOptions,

prev_menu_root: ?dvui.MenuWidget.Root = null,
winId: dvui.Id,
focused: bool = false,
activePt: Point.Natural = .{},
hold: HoldState = .{},
/// Short touch release in the rect (hold duration not reached, menu not opened).
tap_occurred: bool = false,

/// It's expected to call this when `self` is `undefined`
pub fn init(self: *ContextWidget, src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) void {
    const defaults = Options{ .name = "Context" };
    self.* = .{
        .wd = WidgetData.init(src, .{}, defaults.override(opts).override(.{ .rect = dvui.parentGet().data().contentRectScale().rectFromPhysical(init_opts.rect) })),
        .init_options = init_opts,
        .winId = dvui.subwindowCurrentId(),
    };
    if (dvui.focusedWidgetIdInCurrentSubwindow()) |fid| {
        if (fid == self.wd.id) {
            self.focused = true;
        }
    }

    if (dvui.dataGet(null, self.data().id, "_activePt", Point.Natural)) |a| {
        self.activePt = a;
    }
    if (dvui.dataGet(null, self.data().id, "_hold", HoldState)) |h| {
        self.hold = h;
    }

    dvui.parentSet(self.widget());
    self.prev_menu_root = dvui.MenuWidget.Root.set(.{ .ptr = self, .close = menu_root_close });
    self.data().register();
    self.data().borderAndBackground(.{});
}

pub fn activePoint(self: *ContextWidget) ?Point.Natural {
    if (self.focused) {
        return self.activePt;
    }

    return null;
}

/// True when the user completed a short touch tap in the rect this frame (not a hold-to-menu).
pub fn tapOccurred(self: *const ContextWidget) bool {
    return self.tap_occurred;
}

pub fn close(self: *ContextWidget) void {
    self.focused = false;
    self.hold = .{};
    dvui.focusWidget(null, self.winId, null);
}

/// Used as a close callback for menus closing
fn menu_root_close(ptr: *anyopaque, _: dvui.MenuWidget.CloseReason) void {
    const self: *ContextWidget = @ptrCast(@alignCast(ptr));
    self.close();
}

pub fn widget(self: *ContextWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *ContextWidget) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *ContextWidget, id: dvui.Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    dvui.log.debug("{s}:{d} ContextWidget should not have normal child widgets, only menu stuff", .{ self.data().src.file, self.data().src.line });
    return dvui.placeIn(self.data().contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *ContextWidget, rect: Rect) RectScale {
    return self.data().contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *ContextWidget, s: Size) void {
    self.data().minSizeMax(self.data().options.padSize(s));
}

fn openMenuAt(self: *ContextWidget, physical_pt: Point.Physical, event_num: u16) void {
    dvui.focusWidget(self.data().id, null, event_num);
    self.focused = true;

    self.activePt = physical_pt.toNatural();
    self.activePt.x += 1;

    dvui.dragStart(physical_pt, .{ .name = "_mi_mouse_down" });
    dvui.refresh(null, @src(), self.data().id);
}

fn openMenuFromHold(self: *ContextWidget) void {
    self.hold.pending = false;
    self.openMenuAt(self.hold.press_p, self.hold.event_num);
}

fn beginTouchHold(self: *ContextWidget, me: Event.Mouse, event_num: u16) void {
    self.hold = .{
        .pending = true,
        .press_ns = dvui.currentWindow().frame_time_ns,
        .press_p = me.p,
        .button = me.button,
        .event_num = event_num,
    };
}

fn cancelHold(self: *ContextWidget) void {
    self.hold.pending = false;
}

/// Touch down: capture immediately so underlying buttons do not treat this as a click yet.
fn beginTouchPress(self: *ContextWidget, me: Event.Mouse, e: *Event) void {
    e.handle(@src(), self.data());
    dvui.captureMouse(self.data(), e.num);
    dvui.dragPreStart(me.p, .{});
    self.beginTouchHold(me, e.num);
}

/// Touch up: short release becomes `tapOccurred`; hold that already opened the menu does not.
fn endTouchPress(self: *ContextWidget, _: Event.Mouse, e: *Event) void {
    if (!dvui.captured(self.data().id)) return;

    e.handle(@src(), self.data());

    if (!self.focused and self.hold.pending) {
        self.tap_occurred = true;
    }

    self.cancelHold();
    dvui.captureMouse(null, e.num);
    dvui.dragEnd();
}

fn updateHold(self: *ContextWidget) void {
    if (!self.hold.pending or self.focused) return;

    if (!dvui.captured(self.data().id)) return;

    const cw = dvui.currentWindow();
    if (cw.frame_time_ns - self.hold.press_ns >= cw.hold_menu_duration_ns) {
        self.openMenuFromHold();
    }
}

pub fn processEvents(self: *ContextWidget) void {
    // Touch presses in our rect: capture here first so widgets underneath wait for release.
    if (!self.focused) {
        for (dvui.events()) |*e| {
            if (e.handled or e.evt != .mouse) continue;
            const me = e.evt.mouse;
            if (me.action == .press and me.button.touch() and self.init_options.rect.contains(me.p)) {
                self.beginTouchPress(me, e);
            }
        }
    }

    const evts = dvui.events();
    for (evts) |*e| {
        if (!dvui.eventMatchSimple(e, self.data()))
            continue;

        self.processEvent(e);
    }
    self.updateHold();
}

pub fn processEvent(self: *ContextWidget, e: *Event) void {
    switch (e.evt) {
        .mouse => |me| {
            if (me.action == .focus and me.button == .right) {
                // eat any right button focus events so they don't get
                // caught by the containing window cleanup and cause us
                // to lose the focus we are about to get from the right
                // press below
                e.handle(@src(), self.data());
            } else if (me.action == .press and me.button == .right) {
                self.cancelHold();
                e.handle(@src(), self.data());
                self.openMenuAt(me.p, e.num);
            } else if (me.action == .release and me.button.touch()) {
                self.endTouchPress(me, e);
            } else if (me.action == .motion and me.button.touch() and self.hold.pending and dvui.captured(self.data().id)) {
                if (!self.init_options.rect.contains(me.p)) {
                    self.cancelHold();
                    dvui.captureMouse(null, e.num);
                    dvui.dragEnd();
                }
            }
        },
        else => {},
    }
}

pub fn deinit(self: *ContextWidget) void {
    defer if (dvui.widgetIsAllocated(self)) dvui.widgetFree(self);
    defer self.* = undefined;
    if (self.focused) {
        dvui.dataSet(null, self.data().id, "_activePt", self.activePt);
    }
    if (self.hold.pending) {
        dvui.dataSet(null, self.data().id, "_hold", self.hold);
    } else {
        dvui.dataRemove(null, self.data().id, "_hold");
    }

    // we are always given a rect, so we don't do normal layout, don't do these
    //self.data().minSizeSetAndRefresh();
    //self.data().minSizeReportToParent();

    _ = dvui.MenuWidget.Root.set(self.prev_menu_root);
    dvui.parentReset(self.data().id, self.data().parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
