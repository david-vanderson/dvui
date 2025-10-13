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

/// Defaults is for the embedded box widget
pub var defaults: Options = .{
    .name = "Window",
    .role = .window,
    .corner_radius = Rect.all(5),
    .margin = Rect.all(2),
    .border = Rect.all(1),
    .background = true,
    .style = .window,
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

/// SAFETY: Set by `install`
prev_rendering: bool = undefined,
wd: WidgetData,
init_options: InitOptions,
/// options is for our embedded BoxWidget
options: Options,
/// SAFETY: Set by `install`
prev_windowInfo: dvui.subwindowCurrentSetReturn = undefined,
/// SAFETY: Set by `install`
prev_last_focus: dvui.Id = undefined,
/// SAFETY: Set by `install`
layout: BoxWidget = undefined,
/// SAFETY: Set by `install`
prevClip: Rect.Physical = undefined,
auto_pos: bool = false,
auto_size: bool = false,
auto_size_refresh_prev_value: ?u8 = null,
drag_part: ?DragPart = null,
/// SAFETY: Set by `install`
drag_area: Rect.Physical = undefined,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) FloatingWindowWidget {
    const options = defaults.override(opts);
    var box_options = options;
    box_options.role = null;
    box_options.label = null;
    box_options.id_extra = null;
    box_options.rect = null; // if the user passes in a rect, don't pass it to the BoxWidget

    var self = FloatingWindowWidget{
        // options is really for our embedded BoxWidget, so save them for the
        // end of install()
        .options = box_options,

        // the floating window itself doesn't have any styling, it comes from
        // the embedded BoxWidget
        .wd = WidgetData.init(src, .{ .subwindow = true }, .{
            .id_extra = opts.id_extra,
            // passing options.rect will stop WidgetData.init from calling rectFor
            // which is important because we are outside normal layout
            .rect = .{},
            .role = options.role,
            .label = options.label,
        }),
        .init_options = init_opts,
    };

    self.options.rect = null; // if the user passes in a rect, don't pass it to the BoxWidget

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
            if (self.data().rect.w == 0 and self.wd.rect.h == 0) {
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

            const centering: Rect.Natural = self.init_options.center_on orelse dvui.currentWindow().subwindows.current_rect;
            self.wd.rect.x = centering.x + (centering.w - self.wd.rect.w) / 2;
            self.wd.rect.y = centering.y + (centering.h - self.wd.rect.h) / 2;

            if (dvui.snapToPixels()) {
                const s = dvui.windowNaturalScale();
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
                    for (cw.subwindows.stack.items[1..]) |subw| {
                        if (subw.id != self.wd.id and subw.rect.topLeft().equals(self.data().rect.topLeft())) {
                            self.wd.rect.x += 24;
                            self.wd.rect.y += 24;
                            nudge = true;
                        }
                    }
                }
            }

            //std.debug.print("autopos to {}\n", .{self.data().rect});
        }

        // always make sure we are on the screen
        var screen = dvui.windowRect();
        // okay if we are off the left or right but still see some
        const offleft = self.wd.rect.w - 48;
        screen.x -= offleft;
        screen.w += offleft + offleft;
        // okay if we are off the bottom but still see the top
        screen.h += self.wd.rect.h - 24;
        self.wd.rect = .cast(dvui.placeOnScreen(screen, .{}, .none, .cast(self.data().rect)));
    }

    return self;
}

pub fn install(self: *FloatingWindowWidget) void {
    self.data().register();
    self.prev_rendering = dvui.renderingSet(false);

    if (dvui.firstFrame(self.data().id)) {
        dvui.focusSubwindow(self.data().id, null);

        // write back before we hide ourselves for the first frame
        dvui.dataSet(null, self.data().id, "_rect", self.data().rect);
        if (self.init_options.rect) |ior| {
            // send rect back to user
            ior.* = self.data().rect;
        }

        // need a second frame to fit contents
        dvui.refresh(null, @src(), self.data().id);

        // hide our first frame so the user doesn't see an empty window or
        // jump when we autopos/autosize - do this in install() because
        // animation stuff might be messing with out rect after init()
        self.data().rect.w = 0;
        self.data().rect.h = 0;
    }

    if (dvui.captured(self.data().id)) {
        if (dvui.dataGet(null, self.data().id, "_drag_part", DragPart)) |dp| {
            self.drag_part = dp;
        }
    }

    self.drag_area = self.data().rectScale().r;

    dvui.parentSet(self.widget());
    self.prev_windowInfo = dvui.subwindowCurrentSet(self.data().id, .cast(self.data().rect));
    // prevents parents from processing key events if focus is inside the floating window
    self.prev_last_focus = dvui.lastFocusedIdInFrame();

    // reset clip to whole OS window
    // - if modal fade everything below us
    // - gives us all mouse events
    self.prevClip = dvui.clipGet();
    dvui.clipSet(dvui.windowRectPixels());

    if (self.data().accesskit_node()) |ak_node| {
        if (self.init_options.modal)
            dvui.AccessKit.nodeSetModal(ak_node)
        else
            dvui.AccessKit.nodeClearModal(ak_node);
    }
}

pub fn drawBackground(self: *FloatingWindowWidget) void {
    const rs = self.data().rectScale();
    dvui.subwindowAdd(self.data().id, self.data().rect, rs.r, self.init_options.modal, if (self.init_options.stay_above_parent_window) self.prev_windowInfo.id else null, true);
    dvui.captureMouseMaintain(.{ .id = self.data().id, .rect = rs.r, .subwindow_id = self.data().id });

    if (self.init_options.modal and !dvui.firstFrame(self.data().id)) {
        // paint over everything below
        var col = self.options.color(.text);
        col.a = if (dvui.themeGet().dark) 60 else 80;
        dvui.windowRectPixels().fill(.{}, .{ .color = col });
    }

    // we are using BoxWidget to do border/background
    self.layout = BoxWidget.init(@src(), .{ .dir = .vertical }, self.options.override(.{ .expand = .both }));
    self.layout.install();
    self.layout.drawBackground();

    // clip to just our window (layout has the margin)
    _ = dvui.clip(self.layout.data().borderRectScale().r);
}

fn dragPart(me: Event.Mouse, rs: RectScale) DragPart {
    const corner_size: f32 = rs.s * @as(f32, if (me.button.touch()) 30 else 15);
    const top = (me.p.y < rs.r.y + corner_size);
    const bottom = (me.p.y > rs.r.y + rs.r.h - corner_size);
    const left = (me.p.x < rs.r.x + corner_size);
    const right = (me.p.x > rs.r.x + rs.r.w - corner_size);

    if (bottom and right) return .bottom_right;

    if (top and left) return .top_left;

    if (bottom and left) return .bottom_left;

    if (top and right) return .top_right;

    const side_size: f32 = rs.s * @as(f32, if (me.button.touch()) 16 else 4);

    if (me.p.y > rs.r.y + rs.r.h - side_size) return .bottom;

    if (me.p.y < rs.r.y + side_size) return .top;

    if (me.p.x < rs.r.x + side_size) return .left;

    if (me.p.x > rs.r.x + rs.r.w - side_size) return .right;

    return .middle;
}

fn dragAdjust(self: *FloatingWindowWidget, p: Point.Natural, dp: Point.Natural, drag_part: DragPart) void {
    switch (drag_part) {
        .middle => {
            self.data().rect.x += dp.x;
            self.data().rect.y += dp.y;
        },
        .bottom_right => {
            self.data().rect.w = @max(40, p.x - self.data().rect.x);
            self.data().rect.h = @max(10, p.y - self.data().rect.y);
        },
        .top_left => {
            const anchor = self.data().rect.bottomRight();
            const new_w = @max(40, self.data().rect.w - (p.x - self.data().rect.x));
            const new_h = @max(10, self.data().rect.h - (p.y - self.data().rect.y));
            self.data().rect.x = anchor.x - new_w;
            self.data().rect.w = new_w;
            self.data().rect.y = anchor.y - new_h;
            self.data().rect.h = new_h;
        },
        .bottom_left => {
            const anchor = self.data().rect.topRight();
            const new_w = @max(40, self.data().rect.w - (p.x - self.data().rect.x));
            self.data().rect.x = anchor.x - new_w;
            self.data().rect.w = new_w;
            self.data().rect.h = @max(10, p.y - self.data().rect.y);
        },
        .top_right => {
            const anchor = self.data().rect.bottomLeft();
            self.data().rect.w = @max(40, p.x - self.data().rect.x);
            const new_h = @max(10, self.data().rect.h - (p.y - self.data().rect.y));
            self.data().rect.y = anchor.y - new_h;
            self.data().rect.h = new_h;
        },
        .bottom => {
            self.data().rect.h = @max(10, p.y - self.data().rect.y);
        },
        .top => {
            const anchor = self.data().rect.bottomLeft();
            const new_h = @max(10, self.data().rect.h - (p.y - self.data().rect.y));
            self.data().rect.y = anchor.y - new_h;
            self.data().rect.h = new_h;
        },
        .left => {
            const anchor = self.data().rect.topRight();
            const new_w = @max(40, self.data().rect.w - (p.x - self.data().rect.x));
            self.data().rect.x = anchor.x - new_w;
            self.data().rect.w = new_w;
        },
        .right => {
            self.data().rect.w = @max(40, p.x - self.data().rect.x);
        },
    }
}

pub fn processEventsBefore(self: *FloatingWindowWidget) void {
    const rs = self.data().rectScale();
    const evts = dvui.events();
    for (evts) |*e| {
        if (!dvui.eventMatch(e, .{ .id = self.data().id, .r = rs.r }))
            continue;

        if (e.evt == .mouse) {
            const me = e.evt.mouse;

            if (me.action == .focus) {
                // focus but let the focus event propagate to widgets
                dvui.focusSubwindow(self.data().id, e.num);
                continue;
            }

            // If we are already dragging, do it here so it happens before drawing
            if (dvui.captured(self.data().id)) {
                if (me.action == .motion) {
                    if (dvui.dragging(me.p, null)) |dps| {
                        const p = me.p.plus(dvui.dragOffset()).toNatural();
                        self.dragAdjust(p, dps.toNatural(), self.drag_part.?);
                        // don't need refresh() because we're before drawing
                        // but we changed the rect, so need to upate WidgetData's rect_scale
                        self.wd.rect_scale = self.wd.rectScaleFromParent();
                        e.handle(@src(), self.data());
                        continue;
                    }
                }

                if (me.action == .release and me.button.pointer()) {
                    dvui.captureMouse(null, e.num); // stop drag and capture
                    dvui.dragEnd();
                    e.handle(@src(), self.data());
                    continue;
                }
            }

            if (dragPart(me, rs) == .bottom_right) {
                if (me.action == .press and me.button.pointer()) {
                    // capture and start drag
                    dvui.captureMouse(self.data(), e.num);
                    self.drag_part = .bottom_right;
                    dvui.dragStart(me.p, .{ .cursor = .arrow_nw_se, .offset = .diff(rs.r.bottomRight(), me.p) });
                    e.handle(@src(), self.data());
                    continue;
                }
                if (me.action == .position) {
                    e.handle(@src(), self.data()); // don't want any widgets under this to see a hover
                    dvui.cursorSet(.arrow_nw_se);
                    continue;
                }
            }
        }
    }
}

/// Set the phyiscal pixel rect (inside FloatingWidowWidget) where a click-drag
/// will move the FloatingWindowWidget.
///
/// Usually set by return from `windowHeader`.
pub fn dragAreaSet(self: *FloatingWindowWidget, rect: Rect.Physical) void {
    self.drag_area = rect;
}

pub fn processEventsAfter(self: *FloatingWindowWidget) void {
    const rs = self.data().rectScale();
    // duplicate processEventsBefore because you could have a click down,
    // motion, and up in same frame and you wouldn't know you needed to do
    // anything until you got capture here
    //
    // bottom_right corner happens in processEventsBefore
    const evts = dvui.events();
    for (evts) |*e| {
        if (!dvui.eventMatch(e, .{ .id = self.data().id, .r = rs.r, .cleanup = true }))
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
                            const dp = dragPart(me, rs);
                            if (dp == .middle and !self.drag_area.contains(me.p)) {
                                continue;
                            }
                            e.handle(@src(), self.data());
                            // capture and start drag
                            dvui.captureMouse(self.data(), e.num);
                            self.drag_part = dp;
                            dvui.dragPreStart(e.evt.mouse.p, .{ .cursor = self.drag_part.?.cursor() });
                        }
                    },
                    .release => {
                        if (me.button.pointer() and dvui.captured(self.data().id)) {
                            e.handle(@src(), self.data());
                            dvui.captureMouse(null, e.num); // stop drag and capture
                            dvui.dragEnd();
                        }
                    },
                    .motion => {
                        if (dvui.captured(self.data().id)) {
                            // move if dragging
                            if (dvui.dragging(me.p, null)) |dps| {
                                const p = me.p.plus(dvui.dragOffset()).toNatural();
                                self.dragAdjust(p, dps.toNatural(), self.drag_part.?);

                                e.handle(@src(), self.data());
                                dvui.refresh(null, @src(), self.data().id);
                            }
                        }
                    },
                    .position => {
                        const dp = dragPart(me, rs);
                        if (dp == .middle and !self.drag_area.contains(me.p)) {
                            continue;
                        }
                        dvui.cursorSet(dp.cursor());
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

/// Request that the window resize to fit contents up to max_size.  This takes
/// effect next frame.
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
        dvui.log.warn("{s}:{d} FloatingWindowWidget.close() was called but it has no open_flag", .{ self.data().src.file, self.data().src.line });
    }
    dvui.refresh(null, @src(), self.data().id);
}

pub fn widget(self: *FloatingWindowWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *FloatingWindowWidget) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *FloatingWindowWidget, id: dvui.Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.data().contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *FloatingWindowWidget, rect: Rect) RectScale {
    return self.data().contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *FloatingWindowWidget, s: Size) void {
    self.data().minSizeMax(self.data().options.padSize(s));
}

pub fn deinit(self: *FloatingWindowWidget) void {
    const should_free = self.data().was_allocated_on_widget_stack;
    defer if (should_free) dvui.widgetFree(self);
    defer self.* = undefined;
    self.layout.deinit();

    if (self.auto_size_refresh_prev_value) |pv| {
        if (dvui.currentWindow().extra_frames_needed == 0) {
            self.auto_size = false;
        }
        dvui.currentWindow().extra_frames_needed = @max(dvui.currentWindow().extra_frames_needed, pv);
    }

    if (self.init_options.process_events_in_deinit) {
        dvui.clipSet(dvui.windowRectPixels());
        self.processEventsAfter();
    }

    if (!dvui.firstFrame(self.data().id)) {
        // if firstFrame, we already did this in install
        dvui.dataSet(null, self.data().id, "_rect", self.data().rect);
        if (self.init_options.rect) |ior| {
            // send rect back to user
            ior.* = self.data().rect;
        }
    }

    if (dvui.captured(self.data().id)) {
        dvui.dataSet(null, self.data().id, "_drag_part", self.drag_part.?);
    }

    dvui.dataSet(null, self.data().id, "_auto_pos", self.auto_pos);
    dvui.dataSet(null, self.data().id, "_auto_size", self.auto_size);
    self.data().minSizeSetAndRefresh();

    // outside normal layout, don't call minSizeForChild or self.data().minSizeReportToParent();

    dvui.parentReset(self.data().id, self.data().parent);
    dvui.currentWindow().last_focused_id_this_frame = self.prev_last_focus;
    _ = dvui.subwindowCurrentSet(self.prev_windowInfo.id, self.prev_windowInfo.rect);
    dvui.clipSet(self.prevClip);
    _ = dvui.renderingSet(self.prev_rendering);
}

test {
    @import("std").testing.refAllDecls(@This());
}
