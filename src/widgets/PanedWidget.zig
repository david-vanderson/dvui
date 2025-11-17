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
const AccessKit = dvui.AccessKit;

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

    /// Logical pixels of space added on each side of the sash handle when
    /// split is not 0 or 1.
    handle_margin: f32 = 0,

    /// Used so that the split_ratio will be set dynamically so that the first side
    /// fits its children within the min/max split specified
    autofit_first: ?AutoFitOptions = null,

    /// Whether to call draw in deinit if not called before.
    draw_in_deinit: bool = true,
};

wd: WidgetData,
init_opts: InitOptions,

mouse_dist: f32 = 1000, // logical
handle_thick: f32, // logical
split_ratio: *f32,
/// SAFETY: Set in `install`
prevClip: Rect.Physical = undefined,
collapsed_state: bool,
collapsing: bool,
active_side: enum { none, first, second } = .none,
layout: dvui.BasicLayout = .{},
should_autofit: bool = false,
drawn: bool = false,

pub const AutoFitOptions = struct {
    /// The minimum split percentage [0-1] for the first side
    min_split: f32 = 0,
    /// The maximum split percentage [0-1] for the first side
    max_split: f32 = 1,
    /// The minimum size that the first pane requires
    min_size: f32 = 0,
};

pub fn init(src: std.builtin.SourceLocation, init_options: InitOptions, opts: Options) PanedWidget {
    const defaults = Options{ .name = "Paned", .role = .pane };
    const wd = WidgetData.init(src, .{}, defaults.override(opts));

    const rect = wd.contentRect();
    const our_size = switch (init_options.direction) {
        .horizontal => rect.w,
        .vertical => rect.h,
    };

    var self = PanedWidget{
        .wd = wd,
        .init_opts = init_options,
        .collapsing = dvui.dataGet(null, wd.id, "_collapsing", bool) orelse false,
        .collapsed_state = dvui.dataGet(null, wd.id, "_collapsed", bool) orelse (our_size < init_options.collapsed_size),
        .should_autofit = dvui.dataGet(null, wd.id, "_autofit_next_frame", bool) orelse dvui.firstFrame(wd.id),

        // might be changed in processEvents
        .handle_thick = init_options.handle_size,

        .split_ratio = if (init_options.split_ratio) |srp| srp else blk: {
            const default: f32 = if (our_size < init_options.collapsed_size) 1.0 else 0.5;
            break :blk dvui.dataGetPtrDefault(null, wd.id, "_split_ratio", f32, default);
        },
    };

    // autofit on the second frame, after we know the full widget size
    if (dvui.firstFrame(wd.id)) {
        dvui.dataSet(null, wd.id, "_autofit_next_frame", true);
    } else if (self.should_autofit) {
        dvui.dataRemove(null, wd.id, "_autofit_next_frame");
    }

    if (self.init_opts.autofit_first != null and self.should_autofit) {
        // Make the first side take the full space to begin with
        self.split_ratio.* = 1.0;
    }

    if (self.collapsing) {
        self.collapsed_state = false;
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

    return self;
}

pub fn install(self: *PanedWidget) void {
    self.data().register();

    self.data().borderAndBackground(.{});
    self.prevClip = dvui.clip(self.data().contentRectScale().r);

    dvui.parentSet(self.widget());
    if (self.data().a11y_node) |node| {
        node.addAction(.focus);
        node.addAction(.set_value);
        node.setMinNumericValue(0);
        node.setMinNumericValue(1);
        node.setNumericValue(self.split_ratio.*);
    }
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
    if (self.drawn) return;
    self.drawn = true;
    if (self.collapsed()) return;

    if (dvui.captured(self.data().id)) {
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
        if (self.mouse_dist > self.handle_thick / 2) return;
    }

    const rs = self.data().contentRectScale();
    var r = rs.r;
    const handle_gap = self.handleGap() * rs.s; // physical
    const thick = self.handle_thick * rs.s; // physical
    const margin = self.init_opts.handle_margin * rs.s; // physical
    switch (self.init_opts.direction) {
        .horizontal => {
            r.x += std.math.clamp(
                (r.w - handle_gap) * self.split_ratio.* + (handle_gap - thick) / 2,
                margin,
                r.w - thick - margin,
            );
            r.w = thick;
            const height = r.h * len_ratio;
            r.y += r.h / 2 - height / 2;
            r.h = height;
        },
        .vertical => {
            r.y += std.math.clamp(
                (r.h - handle_gap) * self.split_ratio.* + (handle_gap - thick) / 2,
                margin,
                r.h - thick - margin,
            );
            r.h = thick;
            const width = r.w * len_ratio;
            r.x += r.w / 2 - width / 2;
            r.w = width;
        },
    }
    r.fill(.all(thick), .{ .color = self.data().options.color(.text).opacity(0.5), .fade = 1.0 });
}

pub fn collapsed(self: *PanedWidget) bool {
    return self.collapsed_state;
}

pub fn showFirst(self: *PanedWidget) bool {
    const ret = self.split_ratio.* > 0;

    if (ret) {
        self.active_side = .first;
        self.layout = .{};
    } else self.active_side = .none;

    return ret;
}

pub fn showSecond(self: *PanedWidget) bool {
    if (self.should_autofit) {
        if (self.init_opts.autofit_first) |autofit| {
            self.split_ratio.* = self.getFirstFittedRatio(autofit);
        }
    }

    const ret = self.split_ratio.* < 1.0;

    if (ret) {
        self.active_side = .second;
        self.layout = .{};
    } else self.active_side = .none;

    return ret;
}

pub fn animateSplit(self: *PanedWidget, end_val: f32) void {
    dvui.animation(self.data().id, "_split_ratio", dvui.Animation{ .start_val = self.split_ratio.*, .end_val = end_val, .end_time = 250_000 });
}

pub fn widget(self: *PanedWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *PanedWidget) *WidgetData {
    return self.wd.validate();
}

/// Resets the autofit of the first pane
///
/// Must be called before `showFirst`
pub fn autoFit(self: *PanedWidget) void {
    self.should_autofit = true;
    if (self.init_opts.autofit_first) |autofit| {
        // ensure the first pane is expanded before performing layout
        self.split_ratio.* = @max(self.split_ratio.*, autofit.min_split, 0.001);
        self.collapsing = false;
        self.collapsed_state = false;
    }
}

/// Calculates the split ratio to fit the first pane to the size of its children.
///
/// Must be called after all the children on `showFirst` have been called
/// and before `showSecond` is called
pub fn getFirstFittedRatio(self: *PanedWidget, autofit: AutoFitOptions) f32 {
    const content_size = switch (self.init_opts.direction) {
        .horizontal => self.data().contentRect().w,
        .vertical => self.data().contentRect().h,
    };
    // use the maximum possible handle margin to ensure we show all the content
    const total_pane_size = content_size - self.handleSize() * 2;

    const size_of_first = @max(autofit.min_size, switch (self.init_opts.direction) {
        .horizontal => self.layout.min_size_children.w,
        .vertical => self.layout.min_size_children.h,
    });
    return std.math.clamp(
        size_of_first / @max(1, total_pane_size),
        autofit.min_split,
        autofit.max_split,
    );
}

pub fn handleSize(self: *const PanedWidget) f32 {
    return self.handle_thick / 2 + self.init_opts.handle_margin;
}

/// The full gap added between panes to accomodate the handle.
///
/// The handle itself may be drawn outside this gap when the split ratio is at or
/// near the start or end of the paned widget.
pub fn handleGap(self: *PanedWidget) f32 {
    const r = self.data().contentRect();
    const space = switch (self.init_opts.direction) {
        .horizontal => r.w,
        .vertical => r.h,
    };
    const split_point = space * self.split_ratio.*;

    // when the handle is at the start or end of paned, the gap shrinks to 0
    return 2 * @min(self.handleSize(), split_point, space - split_point);
}

pub fn rectFor(self: *PanedWidget, id: dvui.Id, min_size: Size, e: Options.Expand, g: Options.Gravity) dvui.Rect {
    const handle_gap = self.handleGap();
    var r = self.data().contentRect().justSize();
    switch (self.init_opts.direction) {
        .horizontal => r.w -= handle_gap,
        .vertical => r.h -= handle_gap,
    }

    switch (self.active_side) {
        .none => {
            dvui.log.err("{s}:{d}: Paned widget {x} cannot add child widget {x} outside a first/second side", .{ self.data().src.file, self.data().src.line, self.data().id, id });
            // Highlight the widget in red
            dvui.currentWindow().debug.widget_id = id;
            // Place within the entire content rect just so that the widget shows up on screen
            // (probably covered by the panes, but the red outline will show)
        },
        .first => if (self.collapsed()) {
            if (self.split_ratio.* == 0.0) {
                r.w = 0;
                r.h = 0;
            } else switch (self.init_opts.direction) {
                .horizontal => r.x -= (r.w - (r.w * self.split_ratio.*)),
                .vertical => r.y -= (r.h - (r.h * self.split_ratio.*)),
            }
        } else switch (self.init_opts.direction) {
            .horizontal => r.w = @max(0, r.w * self.split_ratio.*),
            .vertical => r.h = @max(0, r.h * self.split_ratio.*),
        },
        .second => if (self.collapsed()) {
            if (self.split_ratio.* == 1.0) {
                r.w = 0;
                r.h = 0;
            } else switch (self.init_opts.direction) {
                .horizontal => r.x = r.w * self.split_ratio.*,
                .vertical => r.y = r.h * self.split_ratio.*,
            }
        } else switch (self.init_opts.direction) {
            .horizontal => {
                const first = r.w * self.split_ratio.*;
                r.w = @max(0, r.w - first);
                r.x += first + handle_gap;
            },
            .vertical => {
                const first = r.h * self.split_ratio.*;
                r.h = @max(0, r.h - first);
                r.y += first + handle_gap;
            },
        },
    }

    return self.layout.rectFor(r, id, min_size, e, g);
}

pub fn screenRectScale(self: *PanedWidget, rect: Rect) RectScale {
    return self.data().contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *PanedWidget, s: dvui.Size) void {
    const ms = self.layout.minSizeForChild(s);
    self.data().minSizeMax(self.data().options.padSize(ms));
}

pub fn processEvent(self: *PanedWidget, e: *Event) void {
    if (e.evt == .mouse) {
        const rs = self.data().contentRectScale();
        const handle_size = self.handleSize() * rs.s; // physical
        const handle_gap = self.handleGap() * rs.s; // physical

        const cursor: enums.Cursor = switch (self.init_opts.direction) {
            .horizontal => .arrow_w_e,
            .vertical => .arrow_n_s,
        };

        self.mouse_dist = switch (self.init_opts.direction) {
            .horizontal => @abs(e.evt.mouse.p.x - std.math.clamp(
                rs.r.x + (rs.r.w - handle_gap) * self.split_ratio.* + handle_size,
                0,
                rs.r.x + rs.r.w - handle_size,
            )) / rs.s,
            .vertical => @abs(e.evt.mouse.p.y - std.math.clamp(
                rs.r.y + (rs.r.h - handle_gap) * self.split_ratio.* + handle_size,
                0,
                rs.r.y + rs.r.h - handle_size,
            )) / rs.s,
        };

        if (self.init_opts.handle_dynamic) |hd| {
            const mouse_dist_outside = @max(0, self.mouse_dist - hd.handle_size_max / 2);
            self.handle_thick = std.math.clamp(hd.handle_size_max - mouse_dist_outside / 2, self.init_opts.handle_size, hd.handle_size_max);
        }

        if (self.collapsed()) return;

        if (dvui.captured(self.data().id) or self.mouse_dist <= @max(self.handle_thick / 2, 2)) {
            if (e.evt.mouse.action == .press and e.evt.mouse.button.pointer()) {
                e.handle(@src(), self.data());
                // capture and start drag
                dvui.captureMouse(self.data(), e.num);
                dvui.dragPreStart(e.evt.mouse.p, .{ .cursor = cursor });
            } else if (e.evt.mouse.action == .release and e.evt.mouse.button.pointer()) {
                e.handle(@src(), self.data());
                // stop possible drag and capture
                dvui.captureMouse(null, e.num);
                dvui.dragEnd();
            } else if (e.evt.mouse.action == .motion and dvui.captured(self.data().id)) {
                e.handle(@src(), self.data());
                // move if dragging
                if (dvui.dragging(e.evt.mouse.p, null)) |dps| {
                    _ = dps;
                    switch (self.init_opts.direction) {
                        .horizontal => {
                            self.split_ratio.* = (e.evt.mouse.p.x - rs.r.x - handle_gap / 2) / (rs.r.w - handle_gap);
                        },
                        .vertical => {
                            self.split_ratio.* = (e.evt.mouse.p.y - rs.r.y - handle_gap / 2) / (rs.r.h - handle_gap);
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
    const should_free = self.data().was_allocated_on_widget_stack;
    defer if (should_free) dvui.widgetFree(self);
    defer self.* = undefined;
    if (self.init_opts.draw_in_deinit) self.draw();
    dvui.clipSet(self.prevClip);
    dvui.dataSet(null, self.data().id, "_collapsing", self.collapsing);
    dvui.dataSet(null, self.data().id, "_collapsed", self.collapsed_state);
    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();
    dvui.parentReset(self.data().id, self.data().parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
