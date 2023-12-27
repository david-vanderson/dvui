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
const BoxWidget = dvui.BoxWidget;

const FloatingWindowWidget = @This();

pub var defaults: Options = .{
    .name = "FloatingWindow",
    .corner_radius = Rect.all(5),
    .border = Rect.all(1),
    .background = true,
    .color_fill = .{ .name = .fill_window },
};

pub const InitOptions = struct {
    modal: bool = false,
    rect: ?*Rect = null,
    open_flag: ?*bool = null,
    process_events_in_deinit: bool = true,
    stay_above_parent_window: bool = false,
    window_avoid: enum {
        none,

        // if we would spawn at the same position as an existing window,
        // move us downright a bit
        nudge,
    } = .none,
};

wd: WidgetData = undefined,
init_options: InitOptions = undefined,
options: Options = undefined,
prev_windowId: u32 = 0,
layout: BoxWidget = undefined,
prevClip: Rect = Rect{},
auto_pos: bool = false,
auto_size: bool = false,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) FloatingWindowWidget {
    var self = FloatingWindowWidget{};

    // options is really for our embedded BoxWidget, so save them for the
    // end of install()
    self.options = defaults.override(opts);
    self.options.rect = null; // if the user passes in a rect, don't pass it to the BoxWidget

    // the floating window itself doesn't have any styling, it comes from
    // the embedded BoxWidget
    // passing options.rect will stop WidgetData.init from calling rectFor
    // which is important because we are outside normal layout
    self.wd = WidgetData.init(src, .{ .subwindow = true }, .{ .id_extra = opts.id_extra, .rect = .{}, .name = self.options.name });
    self.options.name = null; // so our layout Box isn't named FloatingWindow

    self.init_options = init_opts;

    var autopossize = true;
    if (self.init_options.rect) |ior| {
        // user is storing the rect for us across open/close
        self.wd.rect = ior.*;
    } else if (opts.rect) |r| {
        // we were given a rect, just use that
        self.wd.rect = r;
        autopossize = false;
    } else {
        // we store the rect (only while the window is open)
        self.wd.rect = dvui.dataGet(null, self.wd.id, "_rect", Rect) orelse Rect{};
    }

    if (autopossize) {
        if (dvui.dataGet(null, self.wd.id, "_auto_size", @TypeOf(self.auto_size))) |as| {
            self.auto_size = as;
        } else {
            self.auto_size = (self.wd.rect.w == 0 and self.wd.rect.h == 0);
        }

        if (dvui.dataGet(null, self.wd.id, "_auto_pos", @TypeOf(self.auto_pos))) |ap| {
            self.auto_pos = ap;
        } else {
            self.auto_pos = (self.wd.rect.x == 0 and self.wd.rect.y == 0);
        }
    }

    if (dvui.minSizeGet(self.wd.id)) |min_size| {
        if (self.auto_size) {
            // only size ourselves once by default
            self.auto_size = false;

            var ms = Size.max(min_size, self.options.min_sizeGet());
            self.wd.rect.w = ms.w;
            self.wd.rect.h = ms.h;

            //std.debug.print("autosize to {}\n", .{self.wd.rect});
        }

        var prev_focus = dvui.windowRect();
        if (dvui.dataGet(null, self.wd.id, "_prev_focus_rect", Rect)) |r| {
            dvui.dataRemove(null, self.wd.id, "_prev_focus_rect");
            prev_focus = r;

            // second frame for us, but since new windows grab the
            // previously focused window rect, any focused window needs to
            // have a non-zero size
            dvui.focusSubwindow(self.wd.id, null);
        }

        if (self.auto_pos) {
            // only position ourselves once by default
            self.auto_pos = false;

            // center on prev_focus
            self.wd.rect.x = prev_focus.x + (prev_focus.w - self.wd.rect.w) / 2;
            self.wd.rect.y = prev_focus.y + (prev_focus.h - self.wd.rect.h) / 2;

            if (dvui.snapToPixels()) {
                const s = self.wd.rectScale().s;
                self.wd.rect.x = @round(self.wd.rect.x * s) / s;
                self.wd.rect.y = @round(self.wd.rect.y * s) / s;
            }

            while (self.wd.rect.topLeft().equals(prev_focus.topLeft())) {
                // if we ended up directly on top, nudge downright a bit
                self.wd.rect.x += 24;
                self.wd.rect.y += 24;
            }

            const cw = dvui.currentWindow();

            // we might nudge onto another window, so have to keep checking until we don't
            var nudge = true;
            while (nudge) {
                nudge = false;
                // don't check against subwindows[0] - that's that main window
                for (cw.subwindows.items[1..]) |subw| {
                    if (subw.rect.topLeft().equals(self.wd.rect.topLeft())) {
                        self.wd.rect.x += 24;
                        self.wd.rect.y += 24;
                        nudge = true;
                    }
                }

                if (self.init_options.window_avoid == .nudge) {
                    continue;
                } else {
                    break;
                }
            }

            //std.debug.print("autopos to {}\n", .{self.wd.rect});
        }

        // always make sure we are on the screen
        var screen = dvui.windowRect();
        // okay if we are off the left or right but still see some
        const offleft = self.wd.rect.w - 48;
        screen.x -= offleft;
        screen.w += offleft + offleft;
        // okay if we are off the bottom but still see the top
        screen.h += self.wd.rect.h - 24;
        self.wd.rect = dvui.placeOnScreen(screen, .{}, self.wd.rect);
    }

    return self;
}

pub fn install(self: *FloatingWindowWidget) !void {
    if (dvui.firstFrame(self.wd.id)) {
        // write back before we hide ourselves for the first frame
        dvui.dataSet(null, self.wd.id, "_rect", self.wd.rect);
        if (self.init_options.rect) |ior| {
            // send rect back to user
            ior.* = self.wd.rect;
        }

        // there might be multiple new windows, so we aren't going to
        // switch focus until the second frame, which gives all the new
        // windows a chance to grab the previously focused rect

        const cw = dvui.currentWindow();
        dvui.dataSet(null, self.wd.id, "_prev_focus_rect", cw.subwindowFocused().rect);

        // need a second frame to fit contents
        dvui.refresh(null, @src(), self.wd.id);

        // hide our first frame so the user doesn't see an empty window or
        // jump when we autopos/autosize - do this in install() because
        // animation stuff might be messing with out rect after init()
        self.wd.rect.w = 0;
        self.wd.rect.h = 0;
    }

    dvui.parentSet(self.widget());
    self.prev_windowId = dvui.subwindowCurrentSet(self.wd.id);

    // reset clip to whole OS window
    // - if modal fade everything below us
    // - gives us all mouse events
    self.prevClip = dvui.clipGet();
    dvui.clipSet(dvui.windowRectPixels());
}

pub fn drawBackground(self: *FloatingWindowWidget) !void {
    const rs = self.wd.rectScale();
    try dvui.subwindowAdd(self.wd.id, self.wd.rect, rs.r, self.init_options.modal, if (self.init_options.stay_above_parent_window) self.prev_windowId else null);
    dvui.captureMouseMaintain(self.wd.id);
    try self.wd.register();

    if (self.init_options.modal) {
        // paint over everything below
        try dvui.pathAddRect(dvui.windowRectPixels(), Rect.all(0));
        var col = self.options.color(.text);
        col.a = if (dvui.themeGet().dark) 60 else 80;
        try dvui.pathFillConvex(col);
    }

    // clip to just our window
    dvui.clipSet(rs.r);

    // we are using BoxWidget to do border/background but floating windows
    // don't have margin, so turn that off
    self.layout = BoxWidget.init(@src(), .vertical, false, self.options.override(.{ .margin = .{}, .expand = .both }));
    try self.layout.install();
    try self.layout.drawBackground();
}

pub fn processEventsBefore(self: *FloatingWindowWidget) void {
    const rs = self.wd.rectScale();
    var evts = dvui.events();
    for (evts) |*e| {
        if (!dvui.eventMatch(e, .{ .id = self.wd.id, .r = rs.r }))
            continue;

        if (e.evt == .mouse) {
            const me = e.evt.mouse;
            var corner: bool = false;
            const corner_size: f32 = if (me.button.touch()) 30 else 15;
            if (me.p.x > rs.r.x + rs.r.w - corner_size * rs.s and
                me.p.y > rs.r.y + rs.r.h - corner_size * rs.s)
            {
                // we are over the bottom-right resize corner
                corner = true;
            }

            if (me.action == .focus) {
                // focus but let the focus event propagate to widgets
                dvui.focusSubwindow(self.wd.id, e.num);
            }

            if (dvui.captured(self.wd.id) or corner) {
                if (me.action == .press and me.button.pointer()) {
                    // capture and start drag
                    dvui.captureMouse(self.wd.id);
                    dvui.dragStart(me.p, .arrow_all, Point.diff(rs.r.bottomRight(), me.p));
                    e.handled = true;
                } else if (me.action == .release and me.button.pointer()) {
                    dvui.captureMouse(null); // stop drag and capture
                    e.handled = true;
                } else if (me.action == .motion and dvui.captured(self.wd.id)) {
                    // move if dragging
                    if (dvui.dragging(me.p)) |dps| {
                        if (dvui.cursorGetDragging() == .crosshair) {
                            const dp = dps.scale(1 / rs.s);
                            self.wd.rect.x += dp.x;
                            self.wd.rect.y += dp.y;
                        } else if (dvui.cursorGetDragging() == .arrow_all) {
                            const p = me.p.plus(dvui.dragOffset()).scale(1 / rs.s);
                            self.wd.rect.w = @max(40, p.x - self.wd.rect.x);
                            self.wd.rect.h = @max(10, p.y - self.wd.rect.y);
                        }
                        // don't need refresh() because we're before drawing
                        e.handled = true;
                    }
                } else if (me.action == .position) {
                    if (corner) {
                        dvui.cursorSet(.arrow_all);
                        e.handled = true;
                    }
                }
            }
        }
    }
}

pub fn processEventsAfter(self: *FloatingWindowWidget) void {
    const rs = self.wd.rectScale();
    // duplicate processEventsBefore (minus corner stuff) because you could
    // have a click down, motion, and up in same frame and you wouldn't know
    // you needed to do anything until you got capture here
    var evts = dvui.events();
    for (evts) |*e| {
        if (!dvui.eventMatch(e, .{ .id = self.wd.id, .r = rs.r, .cleanup = true }))
            continue;

        switch (e.evt) {
            .mouse => |me| {
                switch (me.action) {
                    .focus => {
                        e.handled = true;
                        // unhandled focus (clicked on nothing)
                        dvui.focusWidget(null, null, null);
                    },
                    .press => {
                        if (me.button.pointer()) {
                            e.handled = true;
                            // capture and start drag
                            dvui.captureMouse(self.wd.id);
                            dvui.dragPreStart(e.evt.mouse.p, .crosshair, Point{});
                        }
                    },
                    .release => {
                        if (me.button.pointer()) {
                            e.handled = true;
                            dvui.captureMouse(null); // stop drag and capture
                        }
                    },
                    .motion => {
                        if (dvui.captured(self.wd.id)) {
                            e.handled = true;
                            // move if dragging
                            if (dvui.dragging(me.p)) |dps| {
                                if (dvui.cursorGetDragging() == .crosshair) {
                                    const dp = dps.scale(1 / rs.s);
                                    self.wd.rect.x += dp.x;
                                    self.wd.rect.y += dp.y;
                                }
                                dvui.refresh(null, @src(), self.wd.id);
                            }
                        }
                    },
                    else => {},
                }
            },
            .key => |ke| {
                // catch any tabs that weren't handled by widgets
                if (ke.code == .tab and ke.action == .down) {
                    e.handled = true;
                    if (ke.mod.shift()) {
                        dvui.tabIndexPrev(e.num);
                    } else {
                        dvui.tabIndexNext(e.num);
                    }
                }
            },
            else => {},
        }
    }
}

// Call this to indicate that you want the window to resize to fit
// contents.  The window's size next frame will fit the min size of the
// contents from this frame.
pub fn autoSize(self: *FloatingWindowWidget) void {
    self.auto_size = true;
}

pub fn close(self: *FloatingWindowWidget) void {
    if (self.init_options.open_flag) |of| {
        of.* = false;
    }
    dvui.refresh(null, @src(), self.wd.id);
}

pub fn widget(self: *FloatingWindowWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *FloatingWindowWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *FloatingWindowWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    return dvui.placeIn(self.wd.contentRect().justSize(), dvui.minSize(id, min_size), e, g);
}

pub fn screenRectScale(self: *FloatingWindowWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *FloatingWindowWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.padSize(s));
}

pub fn processEvent(self: *FloatingWindowWidget, e: *Event, bubbling: bool) void {
    // floating window doesn't process events normally
    switch (e.evt) {
        .close_popup => |cp| {
            e.handled = true;
            if (cp.intentional) {
                // when a popup is closed because the user chose to, the
                // window that spawned it (which had focus previously)
                // should become focused again
                dvui.focusSubwindow(self.wd.id, null);
            }
        },
        else => {},
    }

    // floating windows don't bubble any events
    _ = bubbling;
}

pub fn deinit(self: *FloatingWindowWidget) void {
    if (self.init_options.process_events_in_deinit) {
        self.processEventsAfter();
    }

    self.layout.deinit();

    if (!dvui.firstFrame(self.wd.id)) {
        // if firstFrame, we already did this in install
        dvui.dataSet(null, self.wd.id, "_rect", self.wd.rect);
        if (self.init_options.rect) |ior| {
            // send rect back to user
            ior.* = self.wd.rect;
        }
    }

    dvui.dataSet(null, self.wd.id, "_auto_pos", self.auto_pos);
    dvui.dataSet(null, self.wd.id, "_auto_size", self.auto_size);
    self.wd.minSizeSetAndRefresh();

    // outside normal layout, don't call minSizeForChild or self.wd.minSizeReportToParent();

    dvui.parentReset(self.wd.id, self.wd.parent);
    _ = dvui.subwindowCurrentSet(self.prev_windowId);
    dvui.clipSet(self.prevClip);
}
