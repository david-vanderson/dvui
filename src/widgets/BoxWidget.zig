const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const enums = dvui.enums;

const BoxWidget = @This();

pub const InitOptions = struct {
    /// Direction the box packs children in.
    dir: enums.Direction,

    /// Whether to give equal space to all packed children.
    equal_space: bool = false,

    /// Override box's count from last frame.  Use when you are changing
    /// children's .expand in the box direction at some breakpoint.
    num_packed_expanded: ?u32 = null,
};

const Data = struct {
    packed_children: f32,
    total_weight: f32,
    min_space_taken: f32,
};

wd: WidgetData,
init_opts: InitOptions,
max_space: f32 = 0, // equal_space max min size of child in direction
max_thick: f32 = 0, // max min size of child against direction
data_prev: ?Data,
min_space_taken: f32 = 0,
packed_children: f32 = 0,
total_weight: f32 = 0,
child_rect: Rect = Rect{},
child_positioned: bool = false,
ratio_extra: f32 = 0,
ran_off: bool = false,
pixels_per_w: f32 = 0,

pub fn init(src: std.builtin.SourceLocation, init_options: InitOptions, opts: Options) BoxWidget {
    const defaults = Options{ .name = "Box" };
    const wd = WidgetData.init(src, .{}, defaults.override(opts));
    return .{
        .wd = wd,
        .init_opts = init_options,
        .data_prev = dvui.dataGet(null, wd.id, "_data", Data),
    };
}

pub fn install(self: *BoxWidget) void {
    self.data().register();

    // our rect for children has to start at 0,0
    self.child_rect = self.data().contentRect().justSize();

    if (self.data_prev) |dp| {
        if (self.init_opts.equal_space) {
            if (dp.packed_children > 0) {
                switch (self.init_opts.dir) {
                    .horizontal => self.pixels_per_w = self.child_rect.w / dp.packed_children,
                    .vertical => self.pixels_per_w = self.child_rect.h / dp.packed_children,
                }
            }
        } else {
            var packed_weight = dp.total_weight;
            if (self.init_opts.num_packed_expanded) |num| {
                packed_weight = @floatFromInt(num);
            }

            if (packed_weight > 0) {
                switch (self.init_opts.dir) {
                    .horizontal => self.pixels_per_w = @max(0, self.child_rect.w - dp.min_space_taken) / packed_weight,
                    .vertical => self.pixels_per_w = @max(0, self.child_rect.h - dp.min_space_taken) / packed_weight,
                }
            }
        }
    }

    dvui.parentSet(self.widget());
}

pub fn drawBackground(self: *BoxWidget) void {
    self.data().borderAndBackground(.{});
}

pub fn matchEvent(self: *BoxWidget, e: *Event) bool {
    return dvui.eventMatchSimple(e, self.data());
}

pub fn widget(self: *BoxWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *BoxWidget) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *BoxWidget, id: dvui.WidgetId, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;

    self.child_positioned = switch (self.init_opts.dir) {
        .horizontal => g.x > 0 and g.x < 1.0,
        .vertical => g.y > 0 and g.y < 1.0,
    };

    if (self.child_positioned) {
        // don't pack this, we treat this like overlay - put it where they asked
        return dvui.placeIn(self.data().contentRect().justSize(), min_size, e, g);
    }

    self.packed_children += 1;
    var current_weight: f32 = 0.0;
    if ((self.init_opts.dir == .horizontal and e.isHorizontal()) or (self.init_opts.dir == .vertical and e.isVertical())) {
        current_weight = 1.0;
    }
    self.total_weight += current_weight;

    const available = self.child_rect;

    // adjust min size for expand ratio, which is forced
    var ms = min_size;
    self.ratio_extra = 0;
    if (e == .ratio and ms.w != 0 and ms.h != 0) {
        switch (self.init_opts.dir) {
            .horizontal => {
                const ratio = ms.w / ms.h;
                ms.h = available.h;
                ms.w = available.h * ratio;
                self.ratio_extra = ms.w - min_size.w;
            },
            .vertical => {
                const ratio = ms.h / ms.w;
                ms.h = available.w * ratio;
                ms.w = available.w;
                self.ratio_extra = ms.h - min_size.h;
            },
        }
    }

    // min size after ratio
    const child_min_size = ms;

    const ret: Rect = if (self.init_opts.equal_space) blk: {
        // position child inside the space we allocate for it
        switch (self.init_opts.dir) {
            .horizontal => {
                ms.w = self.pixels_per_w;
                ms.h = available.h;
                const avail = dvui.placeIn(available, ms, .none, g);
                self.removeSpace(avail, g);
                break :blk dvui.placeIn(avail, child_min_size, e, g);
            },
            .vertical => {
                ms.h = self.pixels_per_w;
                ms.w = available.w;
                const avail = dvui.placeIn(available, ms, .none, g);
                self.removeSpace(avail, g);
                break :blk dvui.placeIn(avail, child_min_size, e, g);
            },
        }
    } else blk: {
        //  adjust min size for normal expand (since you only get prorated extra space)
        // - keep the expand in the non box direction
        var ee: Options.Expand = .none;
        switch (self.init_opts.dir) {
            .horizontal => {
                ms.w += self.pixels_per_w * current_weight;
                if (e.isVertical()) ee = .vertical;
            },
            .vertical => {
                ms.h += self.pixels_per_w * current_weight;
                if (e.isHorizontal()) ee = .horizontal;
            },
        }

        const ret = dvui.placeIn(available, ms, ee, g);
        self.removeSpace(ret, g);
        break :blk ret;
    };

    switch (self.init_opts.dir) {
        .horizontal => if (ret.w + 0.001 < child_min_size.w) {
            self.ran_off = true;
        },
        .vertical => if (ret.h + 0.001 < child_min_size.h) {
            self.ran_off = true;
        },
    }

    return ret;
}

fn removeSpace(self: *BoxWidget, r: Rect, g: Options.Gravity) void {
    if (self.init_opts.dir == .horizontal) {
        if (g.x <= 0.5) {
            self.child_rect.w = @max(0, self.child_rect.w - r.w);
            self.child_rect.x += r.w;
        } else {
            self.child_rect.w = @max(0, self.child_rect.w - r.w);
        }
    } else if (self.init_opts.dir == .vertical) {
        if (g.y <= 0.5) {
            self.child_rect.h = @max(0, self.child_rect.h - r.h);
            self.child_rect.y += r.h;
        } else {
            self.child_rect.h = @max(0, self.child_rect.h - r.h);
        }
    }
}

pub fn screenRectScale(self: *BoxWidget, rect: Rect) RectScale {
    return self.data().contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *BoxWidget, s: Size) void {
    if (self.child_positioned) {
        self.data().minSizeMax(self.data().options.padSize(s));
        return;
    }

    if (self.init_opts.dir == .horizontal) {
        self.max_space = @max(self.max_space, s.w + self.ratio_extra);
        self.min_space_taken += s.w + self.ratio_extra;
        self.max_thick = @max(self.max_thick, s.h);
    } else {
        self.max_space = @max(self.max_space, s.h + self.ratio_extra);
        self.min_space_taken += s.h + self.ratio_extra;
        self.max_thick = @max(self.max_thick, s.w);
    }
}

pub fn deinit(self: *BoxWidget) void {
    defer dvui.widgetFree(self);
    const extra_space = (if (self.init_opts.dir == .horizontal) self.child_rect.w else self.child_rect.h) > 0.001;
    const ms: Size = if (self.init_opts.dir == .horizontal) .{
        .w = if (self.init_opts.equal_space)
            self.max_space * self.packed_children
        else
            self.min_space_taken,
        .h = self.max_thick,
    } else .{
        .h = if (self.init_opts.equal_space)
            self.max_space * self.packed_children
        else
            self.min_space_taken,
        .w = self.max_thick,
    };

    if ((self.init_opts.equal_space and self.packed_children > 0) or self.total_weight > 0) {
        if (extra_space) {
            // we have expanded children, but didn't use all the space:
            // - maybe lost a child
            // - maybe one is no longer expanded
            // - maybe one's min size shrunk (label changing text)
            // equal_space could mean we don't exactly use all the space (due to floating point)
            dvui.refresh(null, @src(), self.data().id);
        }

        if (!self.init_opts.equal_space and self.pixels_per_w > 0 and self.ran_off) {
            // we have expanded children, thought we had extra space, but ran
            // off the end:
            // - maybe one's min size got bigger (label changing text)
            dvui.refresh(null, @src(), self.data().id);
        }

        // if total_weight is 0, we are tight around all children, so our min
        // size will be sensitive to theirs and handle normal changes in
        // minSizeSetAndRefresh()
    }

    self.data().minSizeMax(self.data().options.padSize(ms));

    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();

    dvui.dataSet(null, self.data().id, "_data", Data{ .packed_children = self.packed_children, .total_weight = self.total_weight, .min_space_taken = self.min_space_taken });

    dvui.parentReset(self.data().id, self.data().parent);
    self.* = undefined;
}

test {
    @import("std").testing.refAllDecls(@This());
}
