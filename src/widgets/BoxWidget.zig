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
    total_weight_prev: ?f32 = null,
    min_space_taken_prev: ?f32 = null,
};

wd: WidgetData = undefined,
dir: enums.Direction = undefined,
equal_space: bool = undefined,
max_thick: f32 = 0,
data_prev: Data = Data{},
min_space_taken: f32 = 0,
total_weight: f32 = 0,
childRect: Rect = Rect{}, //TODO rename this to child_rect for naming consistency
extra_pixels: f32 = 0,
ratio_extra: f32 = 0,

// FIXME : Does this take space when ztracy is disabled ?
tracy_ctx: dvui.ztracy.ZoneCtx = undefined,
// If it does, I could do :
// tracy_ctx: if (dvui.ztracy.enabled) dvui.ztracy.ZoneCtx else void = undefined,
// but then I need to wrap assignement and End() call below as well
// Or come up with some more comptime stuff up-front

pub fn init(src: std.builtin.SourceLocation, dir: enums.Direction, equal_space: bool, opts: Options) BoxWidget {
    const ctx = dvui.ztracy.ZoneAllocN(src, "BoxWidget");

    var self = BoxWidget{};
    self.tracy_ctx = ctx;

    const defaults = Options{ .name = "Box" };
    self.wd = WidgetData.init(src, .{}, defaults.override(opts));
    self.dir = dir;
    self.equal_space = equal_space;
    if (dvui.dataGet(null, self.wd.id, "_data", Data)) |d| {
        self.data_prev = d;
    }
    return self;
}

pub fn install(self: *BoxWidget) !void {
    try self.wd.register();

    // our rect for children has to start at 0,0
    self.childRect = self.wd.contentRect().justSize();

    if (self.data_prev.min_space_taken_prev) |taken_prev| {
        if (self.dir == .horizontal) {
            if (self.equal_space) {
                self.extra_pixels = self.childRect.w;
            } else {
                self.extra_pixels = @max(0, self.childRect.w - taken_prev);
            }
        } else {
            if (self.equal_space) {
                self.extra_pixels = self.childRect.h;
            } else {
                self.extra_pixels = @max(0, self.childRect.h - taken_prev);
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

pub fn rectFor(self: *BoxWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    var current_weight: f32 = 0.0;
    if (self.equal_space or (self.dir == .horizontal and e.isHorizontal()) or (self.dir == .vertical and e.isVertical())) {
        current_weight = 1.0;
    }
    self.total_weight += current_weight;

    var pixels_per_w: f32 = 0;
    if (self.data_prev.total_weight_prev) |w| {
        if (w > 0) {
            pixels_per_w = self.extra_pixels / w;
        }
    }

    var rect = self.childRect;

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
        rect.h = self.childRect.h;
        if (self.equal_space) {
            rect.w = pixels_per_w * current_weight;
        } else {
            rect.w += pixels_per_w * current_weight;
        }

        if (g.x <= 0.5) {
            self.childRect.w = @max(0, self.childRect.w - rect.w);
            self.childRect.x += rect.w;
        } else {
            rect.x += @max(0, self.childRect.w - rect.w);
            self.childRect.w = @max(0, self.childRect.w - rect.w);
        }
    } else if (self.dir == .vertical) {
        rect.w = self.childRect.w;
        if (self.equal_space) {
            rect.h = pixels_per_w * current_weight;
        } else {
            rect.h += pixels_per_w * current_weight;
        }

        if (g.y <= 0.5) {
            self.childRect.h = @max(0, self.childRect.h - rect.h);
            self.childRect.y += rect.h;
        } else {
            rect.y += @max(0, self.childRect.h - rect.h);
            self.childRect.h = @max(0, self.childRect.h - rect.h);
        }
    }

    return dvui.placeIn(rect, ms, e, g);
}

pub fn screenRectScale(self: *BoxWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *BoxWidget, s: Size) void {
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
    if (self.dir == .horizontal) {
        if (self.equal_space) {
            ms.w = self.min_space_taken * self.total_weight;
        } else {
            ms.w = self.min_space_taken;
        }
        ms.h = self.max_thick;
        if (self.total_weight > 0 and self.childRect.w > 0.001) {
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
        if (self.total_weight > 0 and self.childRect.h > 0.001) {
            // we have expanded children, but didn't use all the space, so something has changed
            // equal_space could mean we don't exactly use all the space (due to floating point)
            dvui.refresh(null, @src(), self.wd.id);
        }
    }

    self.wd.minSizeMax(self.wd.options.padSize(ms));
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();

    dvui.dataSet(null, self.wd.id, "_data", Data{ .total_weight_prev = self.total_weight, .min_space_taken_prev = self.min_space_taken });

    dvui.parentReset(self.wd.id, self.wd.parent);

    self.tracy_ctx.End();
}
