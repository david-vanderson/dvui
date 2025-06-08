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

const Data = struct {
    total_weight: f32,
    min_space_taken: f32,
};

wd: WidgetData = undefined,
dir: enums.Direction = undefined,
equal_space: bool = undefined,
max_thick: f32 = 0,
data_prev: ?Data = undefined,
min_space_taken: f32 = 0,
total_weight: f32 = 0,
child_rect: Rect = Rect{},
child_positioned: bool = false,
ratio_extra: f32 = undefined,
ran_off: bool = undefined,
pixels_per_w: f32 = undefined,

pub fn init(src: std.builtin.SourceLocation, dir: enums.Direction, equal_space: bool, opts: Options) BoxWidget {
    var self = BoxWidget{};
    const defaults = Options{ .name = "Box" };
    self.wd = WidgetData.init(src, .{}, defaults.override(opts));
    self.dir = dir;
    self.equal_space = equal_space;
    self.data_prev = dvui.dataGet(null, self.wd.id, "_data", Data);
    self.ran_off = false;
    self.pixels_per_w = 0;
    return self;
}

pub fn install(self: *BoxWidget) !void {
    self.wd.register();

    // our rect for children has to start at 0,0
    self.child_rect = self.wd.contentRect().justSize();

    if (self.data_prev) |dp| {
        if (dp.total_weight > 0) {
            if (self.equal_space) {
                switch (self.dir) {
                    .horizontal => self.pixels_per_w = self.child_rect.w / dp.total_weight,
                    .vertical => self.pixels_per_w = self.child_rect.h / dp.total_weight,
                }
            } else switch (self.dir) {
                .horizontal => self.pixels_per_w = @max(0, self.child_rect.w - dp.min_space_taken) / dp.total_weight,
                .vertical => self.pixels_per_w = @max(0, self.child_rect.h - dp.min_space_taken) / dp.total_weight,
            }
        }
    }

    dvui.parentSet(self.widget());
}

pub fn drawBackground(self: *BoxWidget) !void {
    try self.wd.borderAndBackground(.{});
}

pub fn matchEvent(self: *BoxWidget, e: *Event) bool {
    return dvui.eventMatchSimple(e, self.data());
}

pub fn widget(self: *BoxWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *BoxWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *BoxWidget, id: dvui.WidgetId, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;

    self.child_positioned = switch (self.dir) {
        .horizontal => g.x > 0 and g.x < 1.0,
        .vertical => g.y > 0 and g.y < 1.0,
    };

    if (self.child_positioned) {
        // don't pack this, we treat this like overlay - put it where they asked
        return dvui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
    }

    var current_weight: f32 = 0.0;
    if (self.equal_space or (self.dir == .horizontal and e.isHorizontal()) or (self.dir == .vertical and e.isVertical())) {
        current_weight = 1.0;
    }
    self.total_weight += current_weight;

    const available = self.child_rect;

    // adjust min size for expand ratio, which is forced
    var ms = min_size;
    self.ratio_extra = 0;
    if (e == .ratio and ms.w != 0 and ms.h != 0) {
        switch (self.dir) {
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

    var ret: Rect = undefined;

    if (self.equal_space) {
        // position child inside the space we allocate for it
        switch (self.dir) {
            .horizontal => {
                ms.w = self.pixels_per_w * current_weight;
                ms.h = available.h;
                const avail = dvui.placeIn(available, ms, .none, g);
                self.removeSpace(avail, g);
                ret = dvui.placeIn(avail, child_min_size, e, g);
            },
            .vertical => {
                ms.h = self.pixels_per_w * current_weight;
                ms.w = available.w;
                const avail = dvui.placeIn(available, ms, .none, g);
                self.removeSpace(avail, g);
                ret = dvui.placeIn(avail, child_min_size, e, g);
            },
        }
    } else {
        // adjust min size for normal expand (since you only get prorated extra space)
        // - keep the expand in the non box direction
        var ee: Options.Expand = .none;
        switch (self.dir) {
            .horizontal => {
                ms.w += self.pixels_per_w * current_weight;
                if (e.isVertical()) ee = .vertical;
            },
            .vertical => {
                ms.h += self.pixels_per_w * current_weight;
                if (e.isHorizontal()) ee = .horizontal;
            },
        }

        ret = dvui.placeIn(available, ms, ee, g);
        self.removeSpace(ret, g);
    }

    switch (self.dir) {
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
    if (self.dir == .horizontal) {
        if (g.x <= 0.5) {
            self.child_rect.w = @max(0, self.child_rect.w - r.w);
            self.child_rect.x += r.w;
        } else {
            self.child_rect.w = @max(0, self.child_rect.w - r.w);
        }
    } else if (self.dir == .vertical) {
        if (g.y <= 0.5) {
            self.child_rect.h = @max(0, self.child_rect.h - r.h);
            self.child_rect.y += r.h;
        } else {
            self.child_rect.h = @max(0, self.child_rect.h - r.h);
        }
    }
}

pub fn screenRectScale(self: *BoxWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *BoxWidget, s: Size) void {
    if (self.child_positioned) {
        self.wd.minSizeMax(self.wd.options.padSize(s));
        return;
    }

    if (self.dir == .horizontal) {
        if (self.equal_space) {
            self.min_space_taken = @max(self.min_space_taken, s.w + self.ratio_extra);
        } else {
            self.min_space_taken += s.w + self.ratio_extra;
        }
        self.max_thick = @max(self.max_thick, s.h);
    } else {
        if (self.equal_space) {
            self.min_space_taken = @max(self.min_space_taken, s.h + self.ratio_extra);
        } else {
            self.min_space_taken += s.h + self.ratio_extra;
        }
        self.max_thick = @max(self.max_thick, s.w);
    }
}

pub fn processEvent(self: *BoxWidget, e: *Event, bubbling: bool) void {
    _ = bubbling;
    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *BoxWidget) void {
    var ms: Size = undefined;
    var extra_space = false;
    if (self.dir == .horizontal) {
        if (self.equal_space) {
            ms.w = self.min_space_taken * self.total_weight;
        } else {
            ms.w = self.min_space_taken;
        }
        ms.h = self.max_thick;
        extra_space = self.child_rect.w > 0.001;
    } else {
        if (self.equal_space) {
            ms.h = self.min_space_taken * self.total_weight;
        } else {
            ms.h = self.min_space_taken;
        }
        ms.w = self.max_thick;
        extra_space = self.child_rect.h > 0.001;
    }

    if (self.total_weight > 0) {
        if (extra_space) {
            // we have expanded children, but didn't use all the space:
            // - maybe lost a child
            // - maybe one is no longer expanded
            // - maybe one's min size shrunk (label changing text)
            // equal_space could mean we don't exactly use all the space (due to floating point)
            dvui.refresh(null, @src(), self.wd.id);
        }

        if (!self.equal_space and self.pixels_per_w > 0 and self.ran_off) {
            // we have expanded children, thought we had extra space, but ran
            // off the end:
            // - maybe one's min size got bigger (label changing text)
            dvui.refresh(null, @src(), self.wd.id);
        }

        // if total_weight is 0, we are tight around all children, so our min
        // size will be sensitive to theirs and handle normal changes in
        // minSizeSetAndRefresh()
    }

    self.wd.minSizeMax(self.wd.options.padSize(ms));

    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();

    dvui.dataSet(null, self.wd.id, "_data", Data{ .total_weight = self.total_weight, .min_space_taken = self.min_space_taken });

    dvui.parentReset(self.wd.id, self.wd.parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
