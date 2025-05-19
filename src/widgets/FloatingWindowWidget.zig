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
    .margin = Rect.all(2),
    .border = Rect.all(1),
    .background = true,
    .color_fill = .{ .name = .fill_window },
};

pub const InitOptions = struct {
    modal: bool = false,
    rect: ?*Rect = null,
    center_on: ?Rect.Natural = null,
    open_flag: ?*bool = null,
    process_events_in_deinit: bool = true,
    stay_above_parent_window: bool = false,
    window_avoid: enum {
        none,

        // nudge away from previously focused subwindow, might land on another
        nudge_once,

        // nudge away from all subwindows
        nudge,
    } = .nudge_once,
};

const DragPart = enum {
    middle,
    top,
    bottom,
    left,
    right,
    top_left,
    bottom_right,
    top_right,
    bottom_left,

    pub fn cursor(self: DragPart) dvui.enums.Cursor {
        return switch (self) {
            .middle => .arrow_all,

            .top_left => .arrow_nw_se,
            .bottom_right => .arrow_nw_se,

            .bottom_left => .arrow_ne_sw,
            .top_right => .arrow_ne_sw,

            .bottom => .arrow_n_s,
            .top => .arrow_n_s,

            .left => .arrow_w_e,
            .right => .arrow_w_e,
        };
    }
};

prev_rendering: bool = undefined,
wd: WidgetData = undefined,
init_options: InitOptions = undefined,
options: Options = undefined,
prev_windowInfo: dvui.subwindowCurrentSetReturn = undefined,
layout: BoxWidget = undefined,
prevClip: Rect.Physical = .{},
auto_pos: bool = false,
auto_size: bool = false,
auto_size_refresh_prev_value: ?u8 = null,
drag_part: ?DragPart = null,

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
    self.wd = WidgetData.init(src, .{ .subwindow = true }, .{ .id_extra = opts.id_extra, .rect = .{}, .name = self.options.name, .debug = self.options.debugGet() });
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
            if (self.wd.rect.w == 0 and self.wd.rect.h == 0) {
                self.autoSize();
            }
        }

        if (dvui.dataGet(null, self.wd.id, "_auto_pos", @TypeOf(self.auto_pos))) |ap| {
            self.auto_pos = ap;
        } else {
            self.auto_pos = (self.wd.rect.x == 0 and self.wd.rect.y == 0);
        }
    }

    if (dvui.minSizeGet(self.wd.id)) |min_size| {
        if (self.auto_size) {
            // Track if any of our children called refresh(), and in deinit we
            // will turn off auto_size if none of them did.
            self.auto_size_refresh_prev_value = dvui.currentWindow().extra_frames_needed;
            dvui.currentWindow().extra_frames_needed = 0;

            const ms = Size.min(Size.max(min_size, self.options.min_sizeGet()), .cast(dvui.windowRect().size()));
            self.wd.rect.w = ms.w;
            self.wd.rect.h = ms.h;
        }

        if (self.auto_pos) {
            // only position ourselves once by default
            self.auto_pos = false;

            const centering: Rect.Natural = self.init_options.center_on orelse dvui.currentWindow().subwindow_currentRect;
            self.wd.rect.x = centering.x + (centering.w - self.wd.rect.w) / 2;
            self.wd.rect.y = centering.y + (centering.h - self.wd.rect.h) / 2;

            if (dvui.snapToPixels()) {
                const s = self.wd.rectScale().s;
                self.wd.rect.x = @round(self.wd.rect.x * s) / s;
                self.wd.rect.y = @round(self.wd.rect.y * s) / s;
            }

            if (self.init_options.window_avoid != .none) {
                if (self.wd.rect.topLeft().equals(.cast(centering.topLeft()))) {
                    // if we ended up directly on top, nudge downright a bit
                    self.wd.rect.x += 24;
                    self.wd.rect.y += 24;
                }
            }

            if (self.init_options.window_avoid == .nudge) {
                const cw = dvui.currentWindow();

                // we might nudge onto another window, so have to keep checking until we don't
                var nudge = true;
                while (nudge) {
                    nudge = false;
                    // don't check against subwindows[0] - that's that main window
                    for (cw.subwindows.items[1..]) |subw| {
                        if (subw.id != self.wd.id and subw.rect.topLeft().equals(self.wd.rect.topLeft())) {
                            self.wd.rect.x += 24;
                            self.wd.rect.y += 24;
                            nudge = true;
                        }
                    }
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
        self.wd.rect = .cast(dvui.placeOnScreen(screen, .{}, .none, .cast(self.wd.rect)));
    }

    return self;
}

pub fn install(self: *FloatingWindowWidget) !void {
    self.prev_rendering = dvui.renderingSet(false);

    if (dvui.firstFrame(self.wd.id)) {
        dvui.focusSubwindow(self.wd.id, null);

        // write back before we hide ourselves for the first frame
        dvui.dataSet(null, self.wd.id, "_rect", self.wd.rect);
        if (self.init_options.rect) |ior| {
            // send rect back to user
            ior.* = self.wd.rect;
        }

        // need a second frame to fit contents
        dvui.refresh(null, @src(), self.wd.id);

        // hide our first frame so the user doesn't see an empty window or
        // jump when we autopos/autosize - do this in install() because
        // animation stuff might be messing with out rect after init()
        self.wd.rect.w = 0;
        self.wd.rect.h = 0;
    }

    if (dvui.captured(self.wd.id)) {
        if (dvui.dataGet(null, self.wd.id, "_drag_part", DragPart)) |dp| {
            self.drag_part = dp;
        }
    }

    dvui.parentSet(self.widget());
    self.prev_windowInfo = dvui.subwindowCurrentSet(self.wd.id, .cast(self.wd.rect));

    // reset clip to whole OS window
    // - if modal fade everything below us
    // - gives us all mouse events
    self.prevClip = dvui.clipGet();
    dvui.clipSet(dvui.windowRectPixels());
}

pub fn drawBackground(self: *FloatingWindowWidget) !void {
    const rs = self.wd.rectScale();
    try dvui.subwindowAdd(self.wd.id, self.wd.rect, rs.r, self.init_options.modal, if (self.init_options.stay_above_parent_window) self.prev_windowInfo.id else null);
    dvui.captureMouseMaintain(.{ .id = self.wd.id, .rect = rs.r, .subwindow_id = self.wd.id });
    try self.wd.register();

    if (self.init_options.modal) {
        // paint over everything below
        var col = self.options.color(.text);
        col.a = if (dvui.themeGet().dark) 60 else 80;
        try dvui.windowRectPixels().fill(.{ .color = col });
    }

    // we are using BoxWidget to do border/background
    self.layout = BoxWidget.init(@src(), .vertical, false, self.options.override(.{ .expand = .both }));
    try self.layout.install();
    try self.layout.drawBackground();

    // clip to just our window (layout has the margin)
    _ = dvui.clip(self.layout.data().borderRectScale().r);
}

fn dragPart(me: Event.Mouse, rs: RectScale) DragPart {
    const corner_size: f32 = if (me.button.touch()) 30 else 15;
    const top = (me.p.y < rs.r.y + corner_size * rs.s);
    const bottom = (me.p.y > rs.r.y + rs.r.h - corner_size * rs.s);
    const left = (me.p.x < rs.r.x + corner_size * rs.s);
    const right = (me.p.x > rs.r.x + rs.r.w - corner_size * rs.s);

    if (bottom and right) return .bottom_right;

    if (top and left) return .top_left;

    if (bottom and left) return .bottom_left;

    if (top and right) return .top_right;

    const side_size: f32 = if (me.button.touch()) 16 else 8;

    if (me.p.y > rs.r.y + rs.r.h - side_size * rs.s) return .bottom;

    if (me.p.y < rs.r.y + side_size * rs.s) return .top;

    if (me.p.x < rs.r.x + side_size * rs.s) return .left;

    if (me.p.x > rs.r.x + rs.r.w - side_size * rs.s) return .right;

    return .middle;
}

fn dragAdjust(self: *FloatingWindowWidget, p: Point.Natural, dp: Point.Natural, drag_part: DragPart) void {
    switch (drag_part) {
        .middle => {
            self.wd.rect.x += dp.x;
            self.wd.rect.y += dp.y;
        },
        .bottom_right => {
            self.wd.rect.w = @max(40, p.x - self.wd.rect.x);
            self.wd.rect.h = @max(10, p.y - self.wd.rect.y);
        },
        .top_left => {
            const anchor = self.wd.rect.bottomRight();
            const new_w = @max(40, self.wd.rect.w - (p.x - self.wd.rect.x));
            const new_h = @max(10, self.wd.rect.h - (p.y - self.wd.rect.y));
            self.wd.rect.x = anchor.x - new_w;
            self.wd.rect.w = new_w;
            self.wd.rect.y = anchor.y - new_h;
            self.wd.rect.h = new_h;
        },
        .bottom_left => {
            const anchor = self.wd.rect.topRight();
            const new_w = @max(40, self.wd.rect.w - (p.x - self.wd.rect.x));
            self.wd.rect.x = anchor.x - new_w;
            self.wd.rect.w = new_w;
            self.wd.rect.h = @max(10, p.y - self.wd.rect.y);
        },
        .top_right => {
            const anchor = self.wd.rect.bottomLeft();
            self.wd.rect.w = @max(40, p.x - self.wd.rect.x);
            const new_h = @max(10, self.wd.rect.h - (p.y - self.wd.rect.y));
            self.wd.rect.y = anchor.y - new_h;
            self.wd.rect.h = new_h;
        },
        .bottom => {
            self.wd.rect.h = @max(10, p.y - self.wd.rect.y);
        },
        .top => {
            const anchor = self.wd.rect.bottomLeft();
            const new_h = @max(10, self.wd.rect.h - (p.y - self.wd.rect.y));
            self.wd.rect.y = anchor.y - new_h;
            self.wd.rect.h = new_h;
        },
        .left => {
            const anchor = self.wd.rect.topRight();
            const new_w = @max(40, self.wd.rect.w - (p.x - self.wd.rect.x));
            self.wd.rect.x = anchor.x - new_w;
            self.wd.rect.w = new_w;
        },
        .right => {
            self.wd.rect.w = @max(40, p.x - self.wd.rect.x);
        },
    }
}

pub fn processEventsBefore(self: *FloatingWindowWidget) void {
    const rs = self.wd.rectScale();
    const evts = dvui.events();
    for (evts) |*e| {
        if (!dvui.eventMatch(e, .{ .id = self.wd.id, .r = rs.r }))
            continue;

        if (e.evt == .mouse) {
            const me = e.evt.mouse;

            if (me.action == .focus) {
                // focus but let the focus event propagate to widgets
                dvui.focusSubwindow(self.wd.id, e.num);
                continue;
            }

            // If we are already dragging, do it here so it happens before drawing
            if (me.action == .motion and dvui.captured(self.wd.id)) {
                if (dvui.dragging(me.p)) |dps| {
                    const p = me.p.plus(dvui.dragOffset()).toNatural();
                    self.dragAdjust(p, dps.toNatural(), self.drag_part.?);
                    // don't need refresh() because we're before drawing
                    e.handle(@src(), self.data());
                    continue;
                }
            }

            if (me.action == .release and me.button.pointer() and dvui.captured(self.wd.id)) {
                dvui.captureMouse(null); // stop drag and capture
                dvui.dragEnd();
                e.handle(@src(), self.data());
                continue;
            }

            if (me.action == .press and me.button.pointer()) {
                if (dragPart(me, rs) == .bottom_right) {
                    // capture and start drag
                    dvui.captureMouse(self.data());
                    self.drag_part = .bottom_right;
                    dvui.dragStart(me.p, .{ .cursor = .arrow_nw_se, .offset = .diff(rs.r.bottomRight(), me.p) });
                    e.handle(@src(), self.data());
                    continue;
                }
            }

            if (me.action == .position) {
                if (dragPart(me, rs) == .bottom_right) {
                    e.handle(@src(), self.data()); // don't want any widgets under this to see a hover
                    dvui.cursorSet(.arrow_nw_se);
                    continue;
                }
            }
        }
    }
}

pub fn processEventsAfter(self: *FloatingWindowWidget) void {
    const rs = self.wd.rectScale();
    // duplicate processEventsBefore because you could have a click down,
    // motion, and up in same frame and you wouldn't know you needed to do
    // anything until you got capture here
    //
    // bottom_right corner happens in processEventsBefore
    const evts = dvui.events();
    for (evts) |*e| {
        if (!dvui.eventMatch(e, .{ .id = self.wd.id, .r = rs.r, .cleanup = true }))
            continue;

        switch (e.evt) {
            .mouse => |me| {
                switch (me.action) {
                    .focus => {
                        e.handle(@src(), self.data());
                        // unhandled focus (clicked on nothing)
                        dvui.focusWidget(null, null, null);
                    },
                    .press => {
                        if (me.button.pointer()) {
                            e.handle(@src(), self.data());
                            // capture and start drag
                            dvui.captureMouse(self.data());
                            self.drag_part = dragPart(me, rs);
                            dvui.dragPreStart(e.evt.mouse.p, .{ .cursor = self.drag_part.?.cursor() });
                        }
                    },
                    .release => {
                        if (me.button.pointer() and dvui.captured(self.wd.id)) {
                            e.handle(@src(), self.data());
                            dvui.captureMouse(null); // stop drag and capture
                            dvui.dragEnd();
                        }
                    },
                    .motion => {
                        if (dvui.captured(self.wd.id)) {
                            // move if dragging
                            if (dvui.dragging(me.p)) |dps| {
                                const p = me.p.plus(dvui.dragOffset()).toNatural();
                                self.dragAdjust(p, dps.toNatural(), self.drag_part.?);

                                e.handle(@src(), self.data());
                                dvui.refresh(null, @src(), self.wd.id);
                            }
                        }
                    },
                    .position => {
                        dvui.cursorSet(dragPart(me, rs).cursor());
                    },
                    else => {},
                }
            },
            .key => |ke| {
                // catch any tabs that weren't handled by widgets
                if (ke.action == .down and ke.matchBind("next_widget")) {
                    e.handle(@src(), self.data());
                    dvui.tabIndexNext(e.num);
                }

                if (ke.action == .down and ke.matchBind("prev_widget")) {
                    e.handle(@src(), self.data());
                    dvui.tabIndexPrev(e.num);
                }
            },
            else => {},
        }
    }
}

/// Request that the window resize to fit contents up to max_size.
///
/// If max_size width/height is zero, use up to the screen size.
///
/// This might take 2 frames if there is a textLayout with break_lines.
pub fn autoSize(self: *FloatingWindowWidget) void {
    self.auto_size = true;
}

pub fn close(self: *FloatingWindowWidget) void {
    if (self.init_options.open_flag) |of| {
        of.* = false;
    } else {
        dvui.log.warn("{s}:{d} FloatingWindowWidget.close() was called but it has no open_flag", .{ self.wd.src.file, self.wd.src.line });
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
    _ = id;
    return dvui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *FloatingWindowWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *FloatingWindowWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
}

pub fn processEvent(self: *FloatingWindowWidget, e: *Event, bubbling: bool) void {
    // floating window doesn't process events normally
    switch (e.evt) {
        .close_popup => |cp| {
            e.handle(@src(), self.data());
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
    self.layout.deinit();

    if (self.auto_size_refresh_prev_value) |pv| {
        if (dvui.currentWindow().extra_frames_needed == 0) {
            self.auto_size = false;
        }
        dvui.currentWindow().extra_frames_needed = @max(dvui.currentWindow().extra_frames_needed, pv);
    }

    if (self.init_options.process_events_in_deinit) {
        self.processEventsAfter();
    }

    if (!dvui.firstFrame(self.wd.id)) {
        // if firstFrame, we already did this in install
        dvui.dataSet(null, self.wd.id, "_rect", self.wd.rect);
        if (self.init_options.rect) |ior| {
            // send rect back to user
            ior.* = self.wd.rect;
        }
    }

    if (dvui.captured(self.wd.id)) {
        dvui.dataSet(null, self.wd.id, "_drag_part", self.drag_part.?);
    }

    dvui.dataSet(null, self.wd.id, "_auto_pos", self.auto_pos);
    dvui.dataSet(null, self.wd.id, "_auto_size", self.auto_size);
    self.wd.minSizeSetAndRefresh();

    // outside normal layout, don't call minSizeForChild or self.wd.minSizeReportToParent();

    dvui.parentReset(self.wd.id, self.wd.parent);
    _ = dvui.subwindowCurrentSet(self.prev_windowInfo.id, self.prev_windowInfo.rect);
    dvui.clipSet(self.prevClip);
    _ = dvui.renderingSet(self.prev_rendering);
}

test {
    @import("std").testing.refAllDecls(@This());
}
