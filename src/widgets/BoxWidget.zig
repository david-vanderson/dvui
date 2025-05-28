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
    single_child: bool,
};

wd: WidgetData = undefined,
dir: enums.Direction = undefined,
equal_space: bool = undefined,
max_thick: f32 = 0,
data_prev: ?Data = null,
min_space_taken: f32 = 0,
total_weight: f32 = 0,
children_seen: u8 = 0,
child_rect: Rect = Rect{},
extra_pixels: f32 = 0,
ratio_extra: f32 = 0,

pub fn init(src: std.builtin.SourceLocation, dir: enums.Direction, equal_space: bool, opts: Options) BoxWidget {
    var self = BoxWidget{};
    const defaults = Options{ .name = "Box" };
    self.wd = WidgetData.init(src, .{}, defaults.override(opts));
    self.dir = dir;
    self.equal_space = equal_space;
    self.data_prev = dvui.dataGet(null, self.wd.id, "_data", Data);
    return self;
}

pub fn install(self: *BoxWidget) !void {
    try self.wd.register();

    // our rect for children has to start at 0,0
    self.child_rect = self.wd.contentRect().justSize();

    if (self.data_prev) |dp| {
        if (self.dir == .horizontal) {
            if (self.equal_space) {
                self.extra_pixels = self.child_rect.w;
            } else {
                self.extra_pixels = @max(0, self.child_rect.w - dp.min_space_taken);
            }
        } else {
            if (self.equal_space) {
                self.extra_pixels = self.child_rect.h;
            } else {
                self.extra_pixels = @max(0, self.child_rect.h - dp.min_space_taken);
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
    self.children_seen +|= 1;

    if (self.data_prev != null and self.data_prev.?.single_child) {
        // we expect a single child this frame, so allow gravity positioning
        const ret = dvui.placeIn(self.child_rect, min_size, e, g);

        // in case we get another child, we'll give them zero size
        switch (self.dir) {
            .vertical => {
                self.child_rect.y += self.child_rect.h;
                self.child_rect.h = 0;
            },
            .horizontal => {
                self.child_rect.x += self.child_rect.w;
                self.child_rect.w = 0;
            },
        }

        return ret;
    }

    var current_weight: f32 = 0.0;
    if (self.equal_space or (self.dir == .horizontal and e.isHorizontal()) or (self.dir == .vertical and e.isVertical())) {
        current_weight = 1.0;
    }
    self.total_weight += current_weight;

    var pixels_per_w: f32 = 0;
    if (self.data_prev) |dp| {
        if (dp.total_weight > 0) {
            pixels_per_w = self.extra_pixels / dp.total_weight;
        }
    }

    var rect = self.child_rect;

    var ms = min_size;
    self.ratio_extra = 0;
    if (e == .ratio and ms.w != 0 and ms.h != 0) {
        switch (self.dir) {
            .horizontal => {
                const ratio = ms.w / ms.h;
                ms.h = rect.h;
                ms.w = rect.h * ratio;
                self.ratio_extra = ms.w - min_size.w;
            },
            .vertical => {
                const ratio = ms.h / ms.w;
                ms.h = rect.w * ratio;
                ms.w = rect.w;
                self.ratio_extra = ms.h - min_size.h;
            },
        }
    }

    rect.w = @min(rect.w, ms.w);
    rect.h = @min(rect.h, ms.h);

    if (self.dir == .horizontal) {
        rect.h = self.child_rect.h;
        if (self.equal_space) {
            rect.w = pixels_per_w * current_weight;
        } else {
            rect.w += pixels_per_w * current_weight;
        }

        if (g.x <= 0.5) {
            self.child_rect.w = @max(0, self.child_rect.w - rect.w);
            self.child_rect.x += rect.w;
        } else {
            rect.x += @max(0, self.child_rect.w - rect.w);
            self.child_rect.w = @max(0, self.child_rect.w - rect.w);
        }
    } else if (self.dir == .vertical) {
        rect.w = self.child_rect.w;
        if (self.equal_space) {
            rect.h = pixels_per_w * current_weight;
        } else {
            rect.h += pixels_per_w * current_weight;
        }

        if (g.y <= 0.5) {
            self.child_rect.h = @max(0, self.child_rect.h - rect.h);
            self.child_rect.y += rect.h;
        } else {
            rect.y += @max(0, self.child_rect.h - rect.h);
            self.child_rect.h = @max(0, self.child_rect.h - rect.h);
        }
    }

    return dvui.placeIn(rect, ms, e, g);
}

pub fn screenRectScale(self: *BoxWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *BoxWidget, s: Size) void {
    if (self.data_prev != null and self.data_prev.?.single_child) {
        if (self.children_seen == 1) {
            self.wd.minSizeMax(self.wd.options.padSize(s));
        }

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
    if (self.data_prev != null and self.data_prev.?.single_child) {
        // if we had a single child, nothing needed
    } else {
        var ms: Size = undefined;
        if (self.dir == .horizontal) {
            if (self.equal_space) {
                ms.w = self.min_space_taken * self.total_weight;
            } else {
                ms.w = self.min_space_taken;
            }
            ms.h = self.max_thick;
            if (self.total_weight > 0 and self.child_rect.w > 0.001) {
                // we have expanded children, but didn't use all the space, so something has changed
                // equal_space could mean we don't exactly use all the space (due to floating point)
                dvui.refresh(null, @src(), self.wd.id);
            }
        } else {
            if (self.equal_space) {
                ms.h = self.min_space_taken * self.total_weight;
            } else {
                ms.h = self.min_space_taken;
            }
            ms.w = self.max_thick;
            if (self.total_weight > 0 and self.child_rect.h > 0.001) {
                // we have expanded children, but didn't use all the space, so something has changed
                // equal_space could mean we don't exactly use all the space (due to floating point)
                dvui.refresh(null, @src(), self.wd.id);
            }
        }
        self.wd.minSizeMax(self.wd.options.padSize(ms));
    }

    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();

    dvui.dataSet(null, self.wd.id, "_data", Data{ .total_weight = self.total_weight, .min_space_taken = self.min_space_taken, .single_child = self.children_seen <= 1 });

    dvui.parentReset(self.wd.id, self.wd.parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
