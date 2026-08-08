const std = @import("std");
const dvui = @import("dvui.zig");

const Point = dvui.Point;
const Rect = dvui.Rect;
const Size = dvui.Size;

const enums = dvui.enums;

/// Holds all the information about a scrolling context:
/// * how to scroll horizontally/vertically
/// * virtual size (size of scrollable content)
/// * viewport (where and how much of the content is being seen)
///
/// ScrollAreaWidget/ScrollContainerWidget use this internally, but you can
/// pass your own in.  Set `vertical` and `horizontal` if needed and let the
/// scroll area fill in the virtual_size and viewport.
///
/// Then you can call the various functions to do things like:
/// * scroll to top - `scrollToOffset(.vertical, 0)`
/// * scroll to bottom - `scrollToOffset(.vertical, std.math.floatMax(f32))`
/// * scroll to a widget - `scrollToOffset(.vertical, widget.data().rect.y)`
/// * check if close to top - `offset(.vertical) <= 100`
/// * check if close to bottom - `offsetFromMax(.vertical) <= 100`
///
/// Note that if the content changes (like adding new widgets), the virtual
/// size will be updated in ScrollArea/ScrollContainer.deinit(), so run that
/// before trying to scroll to show the new stuff.
const ScrollInfo = @This();

pub const ScrollMode = enum {
    /// no scrolling
    none,
    /// virtual size calculated from children
    auto,
    /// virtual size left as given
    given,
};

pub const ScrollBarMode = enum {
    /// no scrollbar
    hide,
    /// show scrollbar if viewport is smaller than virtual_size
    auto,
    /// overlay scrollbar on content if viewport is smaller than virtual_size
    auto_overlay,
    /// always show scrollbar
    show,

    pub fn autoAny(self: ScrollBarMode) bool {
        return self == .auto or self == .auto_overlay;
    }
};

vertical: ScrollMode = .auto,
horizontal: ScrollMode = .none,

/// Minimum size needed to show all contents without scrolling.
virtual_size: Size = Size{},

/// Position and size of the visible part of the content.
viewport: Rect = Rect{},
velocity: Point = Point{},

/// Maximum offset - at this offset the viewport shows the end of the content.
/// Note: touch scrolling can temporarily go slightly past this.
pub fn scrollMax(self: ScrollInfo, dir: enums.Direction) f32 {
    switch (dir) {
        .vertical => return @max(0.0, self.virtual_size.h - self.viewport.h),
        .horizontal => return @max(0.0, self.virtual_size.w - self.viewport.w),
    }
}

/// Fraction [0-1] of content the viewport is showing.
pub fn visibleFraction(self: ScrollInfo, dir: enums.Direction) f32 {
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

    const max_hard_scroll = self.scrollMax(dir);
    var length = @max(viewport_size, virtual_size);
    if (viewport_start < 0) {
        // temporarily adding the dead space we are showing
        length += -viewport_start;
    } else if (viewport_start > max_hard_scroll) {
        length += (viewport_start - max_hard_scroll);
    }

    return viewport_size / length; // <= 1
}

/// Viewport offset - how far it is scrolled.
pub fn offset(self: ScrollInfo, dir: enums.Direction) f32 {
    return switch (dir) {
        .vertical => self.viewport.y,
        .horizontal => self.viewport.x,
    };
}

/// Viewport max offset - how far you can still scroll.
pub fn offsetFromMax(self: ScrollInfo, dir: enums.Direction) f32 {
    return self.scrollMax(dir) - self.offset(dir);
}

/// Viewport offset as a fraction [0-1].
pub fn offsetFraction(self: ScrollInfo, dir: enums.Direction) f32 {
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

    const max_hard_scroll = self.scrollMax(dir);
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

/// Scroll viewport by `off` logical pixels.
///
/// ScrollContainer uses this to scroll by mouse wheel or direction keys.
pub fn scrollByOffset(self: *ScrollInfo, dir: enums.Direction, off: f32) void {
    self.scrollToOffset(dir, self.offset(dir) + off);
}

/// Scroll viewport to `off` logical pixels.
///
/// Primary way to affect scrolling for things like:
/// * scroll to top - `scrollToOffset(.vertical, 0)`
/// * scroll to bottom - `scrollToOffset(.vertical, std.math.floatMax(f32))`
/// * scroll to a widget - `scrollToOffset(.vertical, widget.data().rect.y)`
///
/// Note that if the content changes (like adding new widgets), the virtual
/// size will be updated in ScrollArea/ScrollContainer.deinit(), so run that
/// before trying to scroll to show the new stuff.
pub fn scrollToOffset(self: *ScrollInfo, dir: enums.Direction, off: f32) void {
    switch (dir) {
        .vertical => self.viewport.y = std.math.clamp(off, 0, self.scrollMax(dir)),
        .horizontal => self.viewport.x = std.math.clamp(off, 0, self.scrollMax(dir)),
    }
}

/// Scroll viewport to `fin` fraction of max scroll.
pub fn scrollToFraction(self: *ScrollInfo, dir: enums.Direction, fin: f32) void {
    const f = @max(0, @min(1, fin));
    switch (dir) {
        .vertical => self.viewport.y = f * self.scrollMax(dir),
        .horizontal => self.viewport.x = f * self.scrollMax(dir),
    }
}

/// Scroll viewport by one page (one viewport size).
/// up: true to scroll up or left, false to scroll down or right
pub fn scrollPage(self: *ScrollInfo, dir: enums.Direction, up: bool) void {
    var fi = self.visibleFraction(dir);
    // the last page is offset fraction 1.0, so there is
    // one less scroll position between 0 and 1.0
    fi = 1.0 / ((1.0 / fi) - 1);
    const f: f32 = if (up)
        self.offsetFraction(dir) - fi
    else
        self.offsetFraction(dir) + fi;

    self.scrollToFraction(dir, f);
}

/// Scroll viewport by one page up/left (one viewport size).
pub fn scrollPageUp(self: *ScrollInfo, dir: enums.Direction) void {
    self.scrollPage(dir, true);
}

/// Scroll viewport by one page down/right (one viewport size).
pub fn scrollPageDown(self: *ScrollInfo, dir: enums.Direction) void {
    self.scrollPage(dir, false);
}

test {
    @import("std").testing.refAllDecls(@This());
}
