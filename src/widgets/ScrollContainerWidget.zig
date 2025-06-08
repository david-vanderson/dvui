const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Point = dvui.Point;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const ScrollInfo = dvui.ScrollInfo;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const ScrollContainerWidget = @This();

pub var defaults: Options = .{
    .name = "ScrollContainer",
    // most of the time ScrollContainer is used inside ScrollArea which
    // overrides these
    .background = true,
    .min_size_content = .{ .w = 5, .h = 5 },
};

wd: WidgetData = undefined,

si: *ScrollInfo = undefined,

// si.viewport.x/y might be updated in the middle of a frame, this prevents
// those visual artifacts
frame_viewport: Point = Point{},

prevClip: Rect.Physical = .{},

nextVirtualSize: Size = Size{},
seen_expanded_child: bool = false,

lock_visible: bool = false,
first_visible_id: dvui.WidgetId = .zero,
first_visible_offset: Point = Point{}, // offset of top left of first visible widget from viewport

inject_capture_id: ?dvui.WidgetId = null,
seen_scroll_drag: bool = false,

finger_down: bool = false,

pub fn init(src: std.builtin.SourceLocation, io_scroll_info: *ScrollInfo, opts: Options) ScrollContainerWidget {
    var self = ScrollContainerWidget{};
    const options = defaults.override(opts);

    self.wd = WidgetData.init(src, .{}, options);

    self.si = io_scroll_info;
    self.finger_down = dvui.dataGet(null, self.wd.id, "_finger_down", bool) orelse false;

    const crect = self.wd.contentRect();
    self.si.viewport.w = crect.w;
    self.si.viewport.h = crect.h;

    return self;
}

pub fn install(self: *ScrollContainerWidget) !void {
    self.wd.register();

    // user code might have changed our rect
    const crect = self.wd.contentRect();
    self.si.viewport.w = crect.w;
    self.si.viewport.h = crect.h;

    switch (self.si.horizontal) {
        .none => self.si.virtual_size.w = crect.w,
        .auto => {},
        .given => {},
    }
    switch (self.si.vertical) {
        .none => self.si.virtual_size.h = crect.h,
        .auto => {},
        .given => {},
    }

    try self.wd.borderAndBackground(.{});

    self.prevClip = dvui.clip(self.wd.contentRectScale().r);

    self.frame_viewport = self.si.viewport.topLeft();
    if (self.lock_visible) {
        // we don't want to see anything until we find first_visible_id
        self.first_visible_id = dvui.dataGet(null, self.wd.id, "_fv_id", dvui.WidgetId) orelse .zero;
        self.first_visible_offset = dvui.dataGet(null, self.wd.id, "_fv_offset", Point) orelse .{};
        self.frame_viewport = .{ .x = -10000, .y = -10000 };
    }

    dvui.parentSet(self.widget());
}

pub fn matchEvent(self: *ScrollContainerWidget, e: *Event) bool {
    // track finger press/release even if it doesn't happen in our rect
    if (e.evt == .mouse and e.evt.mouse.action == .press and e.evt.mouse.button.touch()) {
        self.finger_down = true;
    } else if (e.evt == .mouse and e.evt.mouse.action == .release and e.evt.mouse.button.touch()) {
        self.finger_down = false;
    }

    return dvui.eventMatchSimple(e, self.data());
}

pub fn processEvents(self: *ScrollContainerWidget) void {
    const evts = dvui.events();
    for (evts) |*e| {
        if (!self.matchEvent(e))
            continue;

        self.processEvent(e, false);
    }

    // might have changed from events
    self.frame_viewport = self.si.viewport.topLeft();
    if (self.lock_visible) {
        self.frame_viewport = .{ .x = -10000, .y = -10000 };
    }
}

pub fn processVelocity(self: *ScrollContainerWidget) void {
    // velocity is only for touch currently

    // damp the current velocity
    // exponential decay: v *= damping^secs_since
    // tweak the damping so we brake harder as the velocity slows down
    if (!self.finger_down) {
        {
            const damping = 0.0001 + @min(1.0, @abs(self.si.velocity.x) / 50.0) * (0.7 - 0.0001);
            self.si.velocity.x *= @exp(@log(damping) * dvui.secondsSinceLastFrame());
            if (@abs(self.si.velocity.x) > 1) {
                //std.debug.print("vel x {d}\n", .{self.si.velocity.x});
                self.si.viewport.x += self.si.velocity.x * 50 * dvui.secondsSinceLastFrame();
                dvui.refresh(null, @src(), self.wd.id);
            } else {
                self.si.velocity.x = 0;
            }
        }

        {
            const damping = 0.0001 + @min(1.0, @abs(self.si.velocity.y) / 50.0) * (0.7 - 0.0001);
            self.si.velocity.y *= @exp(@log(damping) * dvui.secondsSinceLastFrame());
            if (@abs(self.si.velocity.y) > 1) {
                //std.debug.print("vel y {d}\n", .{self.si.velocity.y});
                self.si.viewport.y += self.si.velocity.y * 50 * dvui.secondsSinceLastFrame();
                dvui.refresh(null, @src(), self.wd.id);
            } else {
                self.si.velocity.y = 0;
            }
        }
    }

    // bounce back if we went too far
    {
        const max_scroll = self.si.scrollMax(.horizontal);
        if (self.si.viewport.x < 0) {
            self.si.velocity.x = 0;
            self.si.viewport.x = @min(0, @max(-20, self.si.viewport.x + 250 * dvui.secondsSinceLastFrame()));
            if (self.si.viewport.x < 0) {
                dvui.refresh(null, @src(), self.wd.id);
            }
        } else if (self.si.viewport.x > max_scroll) {
            self.si.velocity.x = 0;
            self.si.viewport.x = @max(max_scroll, @min(max_scroll + 20, self.si.viewport.x - 250 * dvui.secondsSinceLastFrame()));
            if (self.si.viewport.x > max_scroll) {
                dvui.refresh(null, @src(), self.wd.id);
            }
        }
    }

    {
        const max_scroll = self.si.scrollMax(.vertical);

        if (self.si.viewport.y < 0) {
            self.si.velocity.y = 0;
            self.si.viewport.y = @min(0, @max(-20, self.si.viewport.y + 250 * dvui.secondsSinceLastFrame()));
            if (self.si.viewport.y < 0) {
                dvui.refresh(null, @src(), self.wd.id);
            }
        } else if (self.si.viewport.y > max_scroll) {
            self.si.velocity.y = 0;
            self.si.viewport.y = @max(max_scroll, @min(max_scroll + 20, self.si.viewport.y - 250 * dvui.secondsSinceLastFrame()));
            if (self.si.viewport.y > max_scroll) {
                dvui.refresh(null, @src(), self.wd.id);
            }
        }
    }

    // might have changed
    self.frame_viewport = self.si.viewport.topLeft();
    if (self.lock_visible) {
        self.frame_viewport = .{ .x = -10000, .y = -10000 };
    }
}

pub fn widget(self: *ScrollContainerWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *ScrollContainerWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *ScrollContainerWidget, id: dvui.WidgetId, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    // todo: do horizontal properly
    if (self.seen_expanded_child) {
        // Having one expanded child makes sense - could be taking the rest of
        // the given space or filling the visible space (if bigger than the min
        // virtual size).  But that should be the last (usually only) child
        // that asks for space.
        //
        // We saw an expanded child and gave it the rest of the space, and now
        // another child has asked for space, which shouldn't happen.  Visually
        // the new child might not appear at all or appear on top of the
        // expanded child.
        //
        // If you are reading this, make sure that children of scrollArea() are
        // not expanded in the scrollArea's layout direction, or that only the
        // last child is.
        dvui.currentWindow().debug_widget_id = id;
        dvui.log.debug("{s}:{d} ScrollContainerWidget.rectFor() got child {x} after expanded child", .{ @src().file, @src().line, id });
    } else if (e.isVertical()) {
        self.seen_expanded_child = true;
    }

    const y = self.nextVirtualSize.h;

    const h = switch (self.si.vertical) {
        // no scrolling, you only get the visible space
        .none => self.si.viewport.h - y,

        // you get the space you need or more if there is extra visible space
        // and you are expanded
        .auto => @max(self.si.viewport.h - y, min_size.h),

        // you get the given space
        .given => self.si.virtual_size.h - y,
    };

    // todo: do horizontal properly
    const maxw = @max(self.si.virtual_size.w, self.si.viewport.w);

    const rect = Rect{ .x = 0, .y = y, .w = maxw, .h = h };
    const ret = dvui.placeIn(rect, min_size, e, g);

    if (self.lock_visible and self.first_visible_id == id) {
        self.frame_viewport.x = 0; // todo
        self.frame_viewport.y = y + self.first_visible_offset.y;
        self.si.viewport.x = self.frame_viewport.x;
        self.si.viewport.y = self.frame_viewport.y;
    }

    if (ret.y <= self.frame_viewport.y and self.frame_viewport.y < (ret.y + ret.h)) {
        self.first_visible_id = id;
        self.first_visible_offset = Point.diff(self.frame_viewport, ret.topLeft());
    }

    return ret;
}

pub fn screenRectScale(self: *ScrollContainerWidget, rect: Rect) RectScale {
    var r = rect;
    r.y -= self.frame_viewport.y;
    r.x -= self.frame_viewport.x;

    return self.wd.contentRectScale().rectToRectScale(r);
}

pub fn minSizeForChild(self: *ScrollContainerWidget, s: Size) void {
    self.nextVirtualSize.h += s.h;
    self.nextVirtualSize.w = @max(self.nextVirtualSize.w, s.w);
}

pub fn processEvent(self: *ScrollContainerWidget, e: *Event, bubbling: bool) void {
    switch (e.evt) {
        .mouse => |me| {
            if (me.action == .press and me.button.touch()) {
                // stop any current scrolling
                if (self.si.velocity.x != 0 or self.si.velocity.y != 0) {
                    // if we were scrolling, then eat the finger press so it
                    // doesn't do anything other than stop the scroll
                    e.handle(@src(), self.data());

                    self.si.velocity.x = 0;
                    self.si.velocity.y = 0;
                }
            }
        },
        .key => |ke| {
            if (bubbling or (self.wd.id == dvui.focusedWidgetId())) {
                if (ke.code == .up and (ke.action == .down or ke.action == .repeat)) {
                    e.handle(@src(), self.data());
                    if (self.si.vertical != .none) {
                        self.si.scrollByOffset(.vertical, -10);
                    }
                    dvui.refresh(null, @src(), self.wd.id);
                } else if (ke.code == .down and (ke.action == .down or ke.action == .repeat)) {
                    e.handle(@src(), self.data());
                    if (self.si.vertical != .none) {
                        self.si.scrollByOffset(.vertical, 10);
                    }
                    dvui.refresh(null, @src(), self.wd.id);
                } else if (ke.code == .left and (ke.action == .down or ke.action == .repeat)) {
                    e.handle(@src(), self.data());
                    if (self.si.horizontal != .none) {
                        self.si.scrollByOffset(.horizontal, -10);
                    }
                    dvui.refresh(null, @src(), self.wd.id);
                } else if (ke.code == .right and (ke.action == .down or ke.action == .repeat)) {
                    e.handle(@src(), self.data());
                    if (self.si.horizontal != .none) {
                        self.si.scrollByOffset(.horizontal, 10);
                    }
                    dvui.refresh(null, @src(), self.wd.id);
                } else if (ke.code == .page_up and (ke.action == .down or ke.action == .repeat)) {
                    e.handle(@src(), self.data());
                    self.si.scrollPageUp(.vertical);
                    dvui.refresh(null, @src(), self.wd.id);
                } else if (ke.code == .page_down and (ke.action == .down or ke.action == .repeat)) {
                    e.handle(@src(), self.data());
                    self.si.scrollPageDown(.vertical);
                    dvui.refresh(null, @src(), self.wd.id);
                }
            }
        },
        .scroll_drag => |sd| {
            e.handle(@src(), self.data());
            const rs = self.wd.contentRectScale();
            var scrolly: f32 = 0;
            if (sd.mouse_pt.y <= rs.r.y and // want to scroll up
                sd.screen_rect.y < rs.r.y and // scrolling would show more of child
                self.si.viewport.y > 0) // can scroll up
            {
                scrolly = if (!self.seen_scroll_drag) -200 * dvui.secondsSinceLastFrame() else -5;
            }

            if (sd.mouse_pt.y >= (rs.r.y + rs.r.h) and
                (sd.screen_rect.y + sd.screen_rect.h) > (rs.r.y + rs.r.h) and
                self.si.viewport.y < self.si.scrollMax(.vertical))
            {
                scrolly = if (!self.seen_scroll_drag) 200 * dvui.secondsSinceLastFrame() else 5;
            }

            var scrollx: f32 = 0;
            if (sd.mouse_pt.x <= rs.r.x and // want to scroll left
                sd.screen_rect.x < rs.r.x and // scrolling would show more of child
                self.si.viewport.x > 0) // can scroll left
            {
                scrollx = if (!self.seen_scroll_drag) -200 * dvui.secondsSinceLastFrame() else -5;
            }

            if (sd.mouse_pt.x >= (rs.r.x + rs.r.w) and
                (sd.screen_rect.x + sd.screen_rect.w) > (rs.r.x + rs.r.w) and
                self.si.viewport.x < self.si.scrollMax(.horizontal))
            {
                scrollx = if (!self.seen_scroll_drag) 200 * dvui.secondsSinceLastFrame() else 5;
            }

            if (scrolly != 0 or scrollx != 0) {
                if (scrolly != 0) {
                    self.si.scrollByOffset(.vertical, scrolly);
                }
                if (scrollx != 0) {
                    self.si.scrollByOffset(.horizontal, scrollx);
                }

                dvui.refresh(null, @src(), self.wd.id);

                // if we are scrolling, then we need a motion event next
                // frame so that the child widget can adjust selection
                self.inject_capture_id = sd.capture_id;
            }

            self.seen_scroll_drag = true;
        },
        .scroll_to => |st| {
            e.handle(@src(), self.data());
            const rs = self.wd.contentRectScale();

            if (self.si.vertical != .none) {
                const ypx = @max(0.0, rs.r.y - st.screen_rect.y);
                if (ypx > 0) {
                    self.si.viewport.y = self.si.viewport.y - (ypx / rs.s);
                    if (!st.over_scroll) {
                        self.si.scrollToOffset(.vertical, self.si.viewport.y);
                    }
                    dvui.refresh(null, @src(), self.wd.id);
                }

                const ypx2 = @max(0.0, (st.screen_rect.y + st.screen_rect.h) - (rs.r.y + rs.r.h));
                if (ypx2 > 0) {
                    self.si.viewport.y = self.si.viewport.y + (ypx2 / rs.s);
                    if (!st.over_scroll) {
                        self.si.scrollToOffset(.vertical, self.si.viewport.y);
                    }
                    dvui.refresh(null, @src(), self.wd.id);
                }
            }

            if (self.si.horizontal != .none) {
                const xpx = @max(0.0, rs.r.x - st.screen_rect.x);
                if (xpx > 0) {
                    self.si.viewport.x = self.si.viewport.x - (xpx / rs.s);
                    if (!st.over_scroll) {
                        self.si.scrollToOffset(.horizontal, self.si.viewport.x);
                    }
                    dvui.refresh(null, @src(), self.wd.id);
                }

                const xpx2 = @max(0.0, (st.screen_rect.x + st.screen_rect.w) - (rs.r.x + rs.r.w));
                if (xpx2 > 0) {
                    self.si.viewport.x = self.si.viewport.x + (xpx2 / rs.s);
                    if (!st.over_scroll) {
                        self.si.scrollToOffset(.horizontal, self.si.viewport.x);
                    }
                    dvui.refresh(null, @src(), self.wd.id);
                }
            }
        },
        .scroll_propagate => |sp| {
            self.processMotionScrollEvent(e, sp.motion);
        },
        else => {},
    }

    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn processMotionScrollEvent(self: *ScrollContainerWidget, e: *dvui.Event, motion: dvui.Point.Physical) void {
    e.handle(@src(), self.data());

    const rs = self.wd.borderRectScale();

    // Whether to propagate out to any containing scroll
    // containers. Propagate unless we did the whole scroll
    // in the main direction of movement.
    //
    // This helps prevent spurious propogation from a text
    // entry box where you are trying to scroll vertically
    // but the motion event has a small amount of
    // horizontal.
    var propagate: bool = true;

    if (self.si.vertical != .none) {
        self.si.viewport.y -= motion.y / rs.s;
        self.si.velocity.y = -motion.y / rs.s;
        dvui.refresh(null, @src(), self.wd.id);
        if (@abs(motion.y) > @abs(motion.x) and self.si.viewport.y >= 0 and self.si.viewport.y <= self.si.scrollMax(.vertical)) {
            propagate = false;
        }
    }
    if (self.si.horizontal != .none) {
        self.si.viewport.x -= motion.x / rs.s;
        self.si.velocity.x = -motion.x / rs.s;
        dvui.refresh(null, @src(), self.wd.id);
        if (@abs(motion.x) > @abs(motion.y) and self.si.viewport.x >= 0 and self.si.viewport.x <= self.si.scrollMax(.horizontal)) {
            propagate = false;
        }
    }

    if (propagate) {
        var scrollprop = Event{ .evt = .{ .scroll_propagate = .{ .motion = motion } } };
        self.wd.parent.processEvent(&scrollprop, true);
    }
}

pub fn processEventsAfter(self: *ScrollContainerWidget) void {
    const evts = dvui.events();
    for (evts) |*e| {
        if (!dvui.eventMatchSimple(e, self.data()))
            continue;

        switch (e.evt) {
            .mouse => |me| {
                if (me.action == .focus) {
                    e.handle(@src(), self.data());
                    // focus so that we can receive keyboard input
                    dvui.focusWidget(self.wd.id, null, e.num);
                } else if (me.action == .wheel_x) {
                    if (self.si.scrollMax(.horizontal) > 0) {
                        if ((me.action.wheel_x < 0 and self.si.viewport.x <= 0) or (me.action.wheel_x > 0 and self.si.viewport.x >= self.si.scrollMax(.horizontal))) {
                            // propagate the scroll event because we are already maxxed out
                        } else {
                            e.handle(@src(), self.data());
                            self.si.scrollByOffset(.horizontal, me.action.wheel_x);
                            dvui.refresh(null, @src(), self.wd.id);
                        }
                    }
                } else if (me.action == .wheel_y) {
                    // scroll vertically if we can, otherwise try horizontal
                    // use scrollMax instead of self.si.vertical != .none so
                    // that if we possibly could scroll vertically but there's
                    // not enough content to show the scrollbar, we'll try
                    // horizontal
                    if (self.si.scrollMax(.vertical) > 0) {
                        if ((me.action.wheel_y > 0 and self.si.viewport.y <= 0) or (me.action.wheel_y < 0 and self.si.viewport.y >= self.si.scrollMax(.vertical))) {
                            // try horizontal or propagate the scroll event because we are already maxxed out
                        } else {
                            e.handle(@src(), self.data());
                            self.si.scrollByOffset(.vertical, -me.action.wheel_y);
                            dvui.refresh(null, @src(), self.wd.id);
                        }
                    } else if (self.si.scrollMax(.horizontal) > 0) {
                        if ((me.action.wheel_y > 0 and self.si.viewport.x <= 0) or (me.action.wheel_y < 0 and self.si.viewport.x >= self.si.scrollMax(.horizontal))) {
                            // propagate the scroll event because we are already maxxed out
                        } else {
                            e.handle(@src(), self.data());
                            self.si.scrollByOffset(.horizontal, -me.action.wheel_y);
                            dvui.refresh(null, @src(), self.wd.id);
                        }
                    }
                } else if (me.action == .press and me.button.touch()) {
                    // don't let this event go through to floating window
                    // which would capture the mouse preventing scrolling
                    e.handle(@src(), self.data());
                    dvui.captureMouse(self.data());
                } else if (me.action == .release and dvui.captured(self.wd.id)) {
                    e.handle(@src(), self.data());
                    dvui.captureMouse(null);
                    dvui.dragEnd();
                } else if (me.action == .motion and me.button.touch()) {
                    // Need to capture here because it's common for the touch
                    // down to happen on top of a different widget.  Example is
                    // a touch down on a button, which captures.  Then when the
                    // drag starts the button gives up capture, so we get here,
                    // never having seen the touch down.
                    dvui.captureMouse(self.data());

                    self.processMotionScrollEvent(e, me.action.motion);
                }
            },
            else => {},
        }
    }
}

pub fn deinit(self: *ScrollContainerWidget) void {
    // defer dvui.widgetFree(self);
    self.processEventsAfter();

    dvui.dataSet(null, self.wd.id, "_fv_id", self.first_visible_id);
    dvui.dataSet(null, self.wd.id, "_fv_offset", self.first_visible_offset);
    dvui.dataSet(null, self.wd.id, "_finger_down", self.finger_down);

    if (self.inject_capture_id) |ci| {
        // Only do this if the widget that sent the scroll_drag event still has
        // mouse capture at this point.  Mouse could have moved, generated a
        // scroll_drag, then released - in that case we don't want to inject a
        // motion event next frame.
        if (dvui.captured(ci)) {
            // inject a mouse motion event into next frame
            dvui.currentWindow().inject_motion_event = true;
        }
    }

    dvui.clipSet(self.prevClip);

    const padded = self.wd.options.padSize(self.nextVirtualSize);
    switch (self.si.horizontal) {
        .none => self.wd.min_size.w = padded.w,
        .auto => {
            self.wd.min_size.w = padded.w;
            if (self.nextVirtualSize.w != self.si.virtual_size.w) {
                self.si.virtual_size.w = self.nextVirtualSize.w;
                dvui.refresh(null, @src(), self.wd.id);
            }
        },
        .given => {},
    }

    switch (self.si.vertical) {
        .none => self.wd.min_size.h = padded.h,
        .auto => {
            self.wd.min_size.h = padded.h;
            if (self.nextVirtualSize.h != self.si.virtual_size.h) {
                self.si.virtual_size.h = self.nextVirtualSize.h;
                dvui.refresh(null, @src(), self.wd.id);
            }
        },
        .given => {},
    }

    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    dvui.parentReset(self.wd.id, self.wd.parent);
    self.* = undefined;
}

test {
    @import("std").testing.refAllDecls(@This());
}
