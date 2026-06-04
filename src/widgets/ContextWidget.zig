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
    /// Seconds the touch has been held, accumulated via `dvui.secondsSinceLastFrame`.
    held: f32 = 0,
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

    dvui.refresh(null, @src(), self.data().id);
}

fn updateHold(self: *ContextWidget) void {
    if (!self.hold.pending or self.focused) return;

    // waiting to see if we will timeout, need to run frames in the rare case
    // the finger is not moving at all (can reproduce using a mouse with
    // "Simulate Touch")
    dvui.timer(self.data().id, 100_000);

    self.hold.held += dvui.secondsSinceLastFrame();

    const cw = dvui.currentWindow();
    const hold_menu_duration_s = @as(f32, @floatFromInt(cw.hold_menu_duration_ns)) / std.time.ns_per_s;
    if (self.hold.held >= hold_menu_duration_s) {
        self.hold.pending = false;

        // prevent any button or other thing the finger might be on top of from firing on touch up
        dvui.captureMouse(null, 0);

        self.openMenuAt(self.hold.press_p, self.hold.event_num);
    }
}

pub fn processEvents(self: *ContextWidget) void {
    // Touch presses in our rect: capture here first so widgets underneath wait for release.
    if (!self.focused) {
        for (dvui.events()) |*e| {
            if (e.handled or e.evt != .mouse) continue;
            const me = e.evt.mouse;
            if (me.action == .press and me.button.touch() and self.init_options.rect.contains(me.p)) {
                // touch down inside our rect
                self.hold = .{
                    .pending = true,
                    .held = 0,
                    .press_p = me.p,
                    .button = me.button,
                    .event_num = e.num,
                };
            } else if (self.hold.pending and me.action == .release and me.button.touch()) {
                // touch up anywhere
                self.hold.pending = false;
            } else if (self.hold.pending and me.action == .motion and me.button.touch()) {
                const dp = me.p.diff(self.hold.press_p);
                const dps = dp.scale(1 / dvui.windowNaturalScale(), Point.Natural);
                if (@abs(dps.x) > dvui.Dragging.threshold or @abs(dps.y) > dvui.Dragging.threshold) {
                    self.hold.pending = false;
                }
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
                e.handle(@src(), self.data());
                self.openMenuAt(me.p, e.num);
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
