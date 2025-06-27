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

const enums = dvui.enums;

const PanedWidget = @This();

pub const InitOptions = struct {
    /// How to split the two panes (.horizontal first pane on left).
    direction: enums.Direction,

    /// If smaller (logical size) in direction, only show one pane.
    collapsed_size: f32,

    /// Use to save/control the split externally.
    split_ratio: ?*f32 = null,

    /// When uncollapsing, the split ratio will be set to this value.
    uncollapse_ratio: ?f32 = null,

    /// Thickness (logical) of sash handle.  If handle_dynamic is not null,
    /// this is min handle size.
    handle_size: f32 = 4,

    handle_dynamic: ?struct {
        /// Handle thickness is between handle_size (min) and handle_size_max
        /// (max) based on how close the mouse is.
        handle_size_max: f32 = 10,

        /// Show and dynamically adjust size of sash handle when mouse is
        /// closer than this (logical).
        distance_max: f32 = 20,
    } = null,
};

wd: WidgetData = undefined,
init_opts: InitOptions = undefined,

mouse_dist: f32 = 1000, // logical
handle_thick: f32 = undefined, // logical
split_ratio: *f32 = undefined,
prevClip: Rect.Physical = .{},
collapsed_state: bool = false,
collapsing: bool = false,
first_side: bool = true,

pub fn init(src: std.builtin.SourceLocation, init_options: InitOptions, opts: Options) PanedWidget {
    var self = PanedWidget{};
    const defaults = Options{ .name = "Paned" };
    self.wd = WidgetData.init(src, .{}, defaults.override(opts));
    self.init_opts = init_options;

    const rect = self.wd.contentRect();
    const our_size = switch (self.init_opts.direction) {
        .horizontal => rect.w,
        .vertical => rect.h,
    };

    self.collapsing = dvui.dataGet(null, self.wd.id, "_collapsing", bool) orelse false;

    self.collapsed_state = dvui.dataGet(null, self.wd.id, "_collapsed", bool) orelse (our_size < self.init_opts.collapsed_size);
    if (self.collapsing) {
        self.collapsed_state = false;
    }

    if (self.init_opts.split_ratio) |srp| {
        self.split_ratio = srp;
    } else {
        const default: f32 = if (our_size < self.init_opts.collapsed_size) 1.0 else 0.5;
        self.split_ratio = dvui.dataGetPtrDefault(null, self.wd.id, "_split_ratio", f32, default);
    }

    if (!self.collapsing and !self.collapsed_state and our_size < self.init_opts.collapsed_size) {
        // collapsing
        self.collapsing = true;
        if (self.split_ratio.* >= 0.5) {
            self.animateSplit(1.0);
        } else {
            self.animateSplit(0.0);
        }
    }

    if ((self.collapsing or self.collapsed_state) and our_size >= self.init_opts.collapsed_size) {
        // expanding
        self.collapsing = false;
        self.collapsed_state = false;
        if (self.init_opts.uncollapse_ratio) |ratio| {
            self.animateSplit(ratio);
        } else if (self.split_ratio.* > 0.5) {
            self.animateSplit(0.5);
        } else {
            // we were on the second widget, this will
            // "remember" we were on it
            self.animateSplit(0.4999);
        }
    }

    if (dvui.animationGet(self.wd.id, "_split_ratio")) |a| {
        self.split_ratio.* = a.value();

        if (self.collapsing and a.done()) {
            self.collapsing = false;
            self.collapsed_state = true;
        }
    }

    // might be changed in processEvents
    self.handle_thick = self.init_opts.handle_size;

    return self;
}

pub fn install(self: *PanedWidget) void {
    self.wd.register();

    self.wd.borderAndBackground(.{});
    self.prevClip = dvui.clip(self.wd.contentRectScale().r);

    dvui.parentSet(self.widget());
}

pub fn matchEvent(self: *PanedWidget, e: *Event) bool {
    return dvui.eventMatchSimple(e, self.data());
}

pub fn processEvents(self: *PanedWidget) void {
    const evts = dvui.events();
    for (evts) |*e| {
        if (!self.matchEvent(e))
            continue;

        self.processEvent(e);
    }
}

pub fn draw(self: *PanedWidget) void {
    if (self.collapsed()) return;

    if (dvui.captured(self.wd.id)) {
        // we are dragging it, draw it fully
        self.mouse_dist = 0;
    }

    var len_ratio: f32 = 1.0 / 5.0;

    if (self.init_opts.handle_dynamic) |hd| {
        if (self.mouse_dist > self.handle_thick + hd.distance_max) {
            return;
        } else {
            len_ratio *= 1.0 - std.math.clamp((self.mouse_dist - self.handle_thick) / hd.distance_max, 0.0, 1.0);
        }
    } else {
        if (self.mouse_dist > self.handle_thick + 3) return;
    }

    const rs = self.wd.contentRectScale();
    var r = rs.r;
    const thick = self.handle_thick * rs.s; // physical
    switch (self.init_opts.direction) {
        .horizontal => {
            r.x += r.w * self.split_ratio.* - thick / 2;
            r.w = thick;
            const height = r.h * len_ratio;
            r.y += r.h / 2 - height / 2;
            r.h = height;
        },
        .vertical => {
            r.y += r.h * self.split_ratio.* - thick / 2;
            r.h = thick;
            const width = r.w * len_ratio;
            r.x += r.w / 2 - width / 2;
            r.w = width;
        },
    }
    r.fill(.all(thick), .{ .color = self.wd.options.color(.text).opacity(0.5) });
}

pub fn collapsed(self: *PanedWidget) bool {
    return self.collapsed_state;
}

pub fn showFirst(self: *PanedWidget) bool {
    const ret = self.split_ratio.* > 0;

    // If we don't show the first side, then record that for rectFor
    if (!ret) self.first_side = false;

    return ret;
}

pub fn showSecond(self: *PanedWidget) bool {
    return self.split_ratio.* < 1.0;
}

pub fn animateSplit(self: *PanedWidget, end_val: f32) void {
    dvui.animation(self.wd.id, "_split_ratio", dvui.Animation{ .start_val = self.split_ratio.*, .end_val = end_val, .end_time = 250_000 });
}

pub fn widget(self: *PanedWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *PanedWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *PanedWidget, id: dvui.WidgetId, min_size: Size, e: Options.Expand, g: Options.Gravity) dvui.Rect {
    _ = id;
    var r = self.wd.contentRect().justSize();
    if (self.first_side) {
        self.first_side = false;
        if (self.collapsed()) {
            if (self.split_ratio.* == 0.0) {
                r.w = 0;
                r.h = 0;
            } else {
                switch (self.init_opts.direction) {
                    .horizontal => r.x -= (r.w - (r.w * self.split_ratio.*)),
                    .vertical => r.y -= (r.h - (r.h * self.split_ratio.*)),
                }
            }
        } else {
            switch (self.init_opts.direction) {
                .horizontal => r.w = @max(0, r.w * self.split_ratio.* - self.handle_thick / 2),
                .vertical => r.h = @max(0, r.h * self.split_ratio.* - self.handle_thick / 2),
            }
        }
        return dvui.placeIn(r, min_size, e, g);
    } else {
        if (self.collapsed()) {
            if (self.split_ratio.* == 1.0) {
                r.w = 0;
                r.h = 0;
            } else {
                switch (self.init_opts.direction) {
                    .horizontal => {
                        r.x = r.w * self.split_ratio.*;
                    },
                    .vertical => {
                        r.y = r.h * self.split_ratio.*;
                    },
                }
            }
        } else {
            switch (self.init_opts.direction) {
                .horizontal => {
                    const first = @max(0, r.w * self.split_ratio.* - self.handle_thick / 2);
                    r.w = @max(0, r.w - first - self.handle_thick);
                    r.x += first + self.handle_thick;
                },
                .vertical => {
                    const first = @max(0, r.h * self.split_ratio.* - self.handle_thick / 2);
                    r.h = @max(0, r.h - first - self.handle_thick);
                    r.y += first + self.handle_thick;
                },
            }
        }
        return dvui.placeIn(r, min_size, e, g);
    }
}

pub fn screenRectScale(self: *PanedWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *PanedWidget, s: dvui.Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
}

pub fn processEvent(self: *PanedWidget, e: *Event) void {
    if (e.evt == .mouse) {
        const rs = self.wd.contentRectScale();
        const cursor: enums.Cursor = switch (self.init_opts.direction) {
            .horizontal => .arrow_w_e,
            .vertical => .arrow_n_s,
        };

        self.mouse_dist = switch (self.init_opts.direction) {
            .horizontal => @abs(e.evt.mouse.p.x - (rs.r.x + rs.r.w * self.split_ratio.*)) / rs.s,
            .vertical => @abs(e.evt.mouse.p.y - (rs.r.y + rs.r.h * self.split_ratio.*)) / rs.s,
        };

        if (self.init_opts.handle_dynamic) |hd| {
            const mouse_dist_outside = @max(0, self.mouse_dist - hd.handle_size_max / 2);
            self.handle_thick = std.math.clamp(hd.handle_size_max - mouse_dist_outside / 2, self.init_opts.handle_size, hd.handle_size_max);
        }

        if (dvui.captured(self.wd.id) or self.mouse_dist <= @max(self.handle_thick / 2, 2)) {
            if (e.evt.mouse.action == .press and e.evt.mouse.button.pointer()) {
                e.handle(@src(), self.data());
                // capture and start drag
                dvui.captureMouse(self.data());
                dvui.dragPreStart(e.evt.mouse.p, .{ .cursor = cursor });
            } else if (e.evt.mouse.action == .release and e.evt.mouse.button.pointer()) {
                e.handle(@src(), self.data());
                // stop possible drag and capture
                dvui.captureMouse(null);
                dvui.dragEnd();
            } else if (e.evt.mouse.action == .motion and dvui.captured(self.wd.id)) {
                e.handle(@src(), self.data());
                // move if dragging
                if (dvui.dragging(e.evt.mouse.p)) |dps| {
                    _ = dps;
                    switch (self.init_opts.direction) {
                        .horizontal => {
                            self.split_ratio.* = (e.evt.mouse.p.x - rs.r.x) / rs.r.w;
                        },
                        .vertical => {
                            self.split_ratio.* = (e.evt.mouse.p.y - rs.r.y) / rs.r.h;
                        },
                    }

                    self.split_ratio.* = @max(0.0, @min(1.0, self.split_ratio.*));
                }
            } else if (e.evt.mouse.action == .position) {
                dvui.cursorSet(cursor);
            }
        }
    }
}

pub fn deinit(self: *PanedWidget) void {
    defer dvui.widgetFree(self);
    dvui.clipSet(self.prevClip);
    dvui.dataSet(null, self.wd.id, "_collapsing", self.collapsing);
    dvui.dataSet(null, self.wd.id, "_collapsed", self.collapsed_state);
    dvui.dataSet(null, self.wd.id, "_split_ratio", self.split_ratio.*);
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    dvui.parentReset(self.wd.id, self.wd.parent);
    self.* = undefined;
}

test {
    @import("std").testing.refAllDecls(@This());
}
