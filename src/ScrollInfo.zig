const dvui = @import("dvui.zig");

const Point = dvui.Point;
const Rect = dvui.Rect;
const Size = dvui.Size;

const enums = dvui.enums;

const ScrollInfo = @This();

pub const ScrollMode = enum {
    none, // no scrolling
    auto, // virtual size calculated from children
    given, // virtual size left as given
};

pub const ScrollBarMode = enum {
    hide, // no scrollbar
    auto, // show scrollbar if viewport is smaller than virtual_size
    show, // always show scrollbar
};

vertical: ScrollMode = .auto,
horizontal: ScrollMode = .none,
virtual_size: Size = Size{},
viewport: Rect = Rect{},
velocity: Point = Point{},

pub fn scroll_max(self: ScrollInfo, dir: enums.Direction) f32 {
    switch (dir) {
        .vertical => return @max(0.0, self.virtual_size.h - self.viewport.h),
        .horizontal => return @max(0.0, self.virtual_size.w - self.viewport.w),
    }
}

pub fn fraction_visible(self: ScrollInfo, dir: enums.Direction) f32 {
    const viewport_start = switch (dir) {
        .vertical => self.viewport.y,
        .horizontal => self.viewport.x,
    };
    const viewport_size = switch (dir) {
        .vertical => self.viewport.h,
        .horizontal => self.viewport.w,
    };
    const virtual_size = switch (dir) {
        .vertical => self.virtual_size.h,
        .horizontal => self.virtual_size.w,
    };

    if (viewport_size == 0) return 1.0;

    const max_hard_scroll = self.scroll_max(dir);
    var length = @max(viewport_size, virtual_size);
    if (viewport_start < 0) {
        // temporarily adding the dead space we are showing
        length += -viewport_start;
    } else if (viewport_start > max_hard_scroll) {
        length += (viewport_start - max_hard_scroll);
    }

    return viewport_size / length; // <= 1
}

pub fn scroll_fraction(self: ScrollInfo, dir: enums.Direction) f32 {
    const viewport_start = switch (dir) {
        .vertical => self.viewport.y,
        .horizontal => self.viewport.x,
    };
    const viewport_size = switch (dir) {
        .vertical => self.viewport.h,
        .horizontal => self.viewport.w,
    };
    const virtual_size = switch (dir) {
        .vertical => self.virtual_size.h,
        .horizontal => self.virtual_size.w,
    };

    if (viewport_size == 0) return 0;

    const max_hard_scroll = self.scroll_max(dir);
    var length = @max(viewport_size, virtual_size);
    if (viewport_start < 0) {
        // temporarily adding the dead space we are showing
        length += -viewport_start;
    } else if (viewport_start > max_hard_scroll) {
        length += (viewport_start - max_hard_scroll);
    }

    const max_scroll = @max(0, length - viewport_size);
    if (max_scroll == 0) return 0;

    return @max(0, @min(1.0, viewport_start / max_scroll));
}

pub fn scrollToFraction(self: *ScrollInfo, dir: enums.Direction, fin: f32) void {
    const f = @max(0, @min(1, fin));
    switch (dir) {
        .vertical => self.viewport.y = f * self.scroll_max(dir),
        .horizontal => self.viewport.x = f * self.scroll_max(dir),
    }
}
