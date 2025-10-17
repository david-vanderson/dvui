//! A collection of layout helper functions for placing widgets

/// Helper to layout widgets stacked vertically or horizontally.
///
/// If there is a widget expanded in that direction, it takes up the remaining
/// space and it is an error to have any widget after.
///
/// Widgets with .gravity_y (.gravity_x) not zero might overlap other widgets.
pub const BasicLayout = struct {
    dir: Direction = .vertical,
    pos: f32 = 0,
    seen_expanded: bool = false,
    min_size_children: Size = .{},

    pub fn rectFor(self: *BasicLayout, contentRect: Rect, id: Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
        if (self.seen_expanded) {
            // A single vertically expanded child can take the rest of the
            // space, but it should be the last (usually only) child.
            //
            // Here we have a child after an expanded one, so it will get no space.
            //
            // If you want that to work, wrap the children in a vertical box.
            const cw = dvui.currentWindow();
            cw.debug.widget_id = id;
            dvui.log.debug("{s}:{d} rectFor() got child {x} after expanded child", .{ @src().file, @src().line, id });
            var iter = cw.current_parent.data().iterator();
            while (iter.next()) |wd| {
                dvui.log.debug("  {s}:{d} {s} {x}", .{
                    wd.src.file,
                    wd.src.line,
                    wd.options.name orelse "???",
                    wd.id,
                });
            }
        }

        var r = contentRect;

        switch (self.dir) {
            .vertical => {
                if (e.isVertical()) {
                    self.seen_expanded = true;
                }
                r.y += self.pos;
                r.h = @max(0, r.h - self.pos);
            },
            .horizontal => {
                if (e.isHorizontal()) {
                    self.seen_expanded = true;
                }
                r.x += self.pos;
                r.w = @max(0, r.w - self.pos);
            },
        }

        const ret = dvui.placeIn(r, min_size, e, g);

        switch (self.dir) {
            .vertical => self.pos += ret.h,
            .horizontal => self.pos += ret.w,
        }

        return ret;
    }

    pub fn minSizeForChild(self: *BasicLayout, s: Size) Size {
        switch (self.dir) {
            .vertical => {
                // add heights
                self.min_size_children.h += s.h;

                // max of widths
                self.min_size_children.w = @max(self.min_size_children.w, s.w);
            },
            .horizontal => {
                // add widths
                self.min_size_children.w += s.w;

                // max of heights
                self.min_size_children.h = @max(self.min_size_children.h, s.h);
            },
        }

        return self.min_size_children;
    }
};

/// Help left-align widgets by adding horizontal spacers.
///
/// Only valid between `Window.begin`and `Window.end`.
pub const Alignment = struct {
    id: Id,
    scale: f32,
    max: ?f32,
    next: f32,

    pub fn init(src: std.builtin.SourceLocation, id_extra: usize) Alignment {
        const parent = dvui.parentGet();
        const id = parent.extendId(src, id_extra);
        return .{
            .id = id,
            .scale = parent.data().rectScale().s,
            .max = dvui.dataGet(null, id, "_max_align", f32),
            .next = -1_000_000,
        };
    }

    /// Add spacer with margin.x so they all end at the same edge.
    pub fn spacer(self: *Alignment, src: std.builtin.SourceLocation, id_extra: usize) void {
        const uniqueId = dvui.parentGet().extendId(src, id_extra);
        var wd = dvui.spacer(src, .{ .margin = self.margin(uniqueId), .id_extra = id_extra });
        self.record(uniqueId, &wd);
    }

    /// Get the margin needed to align this id's left edge.
    pub fn margin(self: *Alignment, id: Id) Rect {
        if (self.max) |m| {
            if (dvui.dataGet(null, id, "_align", f32)) |a| {
                return .{ .x = @max(0, (m - a) / self.scale) };
            }
        }

        return .{};
    }

    /// Record where this widget ended up so we can align it next frame.
    pub fn record(self: *Alignment, id: Id, wd: *WidgetData) void {
        const x = wd.rectScale().r.x;
        dvui.dataSet(null, id, "_align", x);
        self.next = @max(self.next, x);
    }

    pub fn deinit(self: *Alignment) void {
        defer self.* = undefined;
        dvui.dataSet(null, self.id, "_max_align", self.next);
        if (self.max) |m| {
            if (self.next != m) {
                // something changed
                dvui.refresh(null, @src(), self.id);
            }
        }
    }
};

/// Controls how `placeOnScreen` will move start to avoid spawner.
pub const PlaceOnScreenAvoid = enum {
    /// Don't avoid spawner
    none,
    /// Move to right of spawner, or jump to left
    horizontal,
    /// Move to bottom of spawner, or jump to top
    vertical,
};

/// Adjust start rect based on screen and spawner (like a context menu).
///
/// When adding a floating widget or window, often we want to guarantee that it
/// is visible.  Additionally, if start is logically connected to a spawning
/// rect (like a context menu spawning a submenu), then jump to the opposite
/// side if needed.
pub fn placeOnScreen(screen: Rect.Natural, spawner: Rect.Natural, avoid: PlaceOnScreenAvoid, start: Rect.Natural) Rect.Natural {
    var r = start;

    // first move to avoid spawner
    if (!r.intersect(spawner).empty()) {
        switch (avoid) {
            .none => {},
            .horizontal => r.x = spawner.x + spawner.w,
            .vertical => r.y = spawner.y + spawner.h,
        }
    }

    // fix up if we ran off right side of screen
    switch (avoid) {
        .none, .vertical => {
            // if off right, move
            if ((r.x + r.w) > (screen.x + screen.w)) {
                r.x = (screen.x + screen.w) - r.w;
            }

            // if off left, move
            if (r.x < screen.x) {
                r.x = screen.x;
            }

            // if off right, shrink to fit (but not to zero)
            // - if we went to zero, then a window could get into a state where you can
            // no longer see it or interact with it (like if you resize the OS window
            // to zero size and back)
            if ((r.x + r.w) > (screen.x + screen.w)) {
                r.w = @max(24, (screen.x + screen.w) - r.x);
            }
        },
        .horizontal => {
            // if off right, is there more room on left
            if ((r.x + r.w) > (screen.x + screen.w)) {
                if ((spawner.x - screen.x) > (screen.x + screen.w - (spawner.x + spawner.w))) {
                    // more room on left, switch
                    r.x = spawner.x - r.w;

                    if (r.x < screen.x) {
                        // off left, shrink
                        r.x = screen.x;
                        r.w = spawner.x - screen.x;
                    }
                } else {
                    // more room on left, shrink
                    r.w = @max(24, (screen.x + screen.w) - r.x);
                }
            }
        },
    }

    // fix up if we ran off bottom of screen
    switch (avoid) {
        .none, .horizontal => {
            // if off bottom, first try moving
            if ((r.y + r.h) > (screen.y + screen.h)) {
                r.y = (screen.y + screen.h) - r.h;
            }

            // if off top, move
            if (r.y < screen.y) {
                r.y = screen.y;
            }

            // if still off bottom, shrink to fit (but not to zero)
            if ((r.y + r.h) > (screen.y + screen.h)) {
                r.h = @max(24, (screen.y + screen.h) - r.y);
            }
        },
        .vertical => {
            // if off bottom, is there more room on top?
            if ((r.y + r.h) > (screen.y + screen.h)) {
                if ((spawner.y - screen.y) > (screen.y + screen.h - (spawner.y + spawner.h))) {
                    // more room on top, switch
                    r.y = spawner.y - r.h;

                    if (r.y < screen.y) {
                        // off top, shrink
                        r.y = screen.y;
                        r.h = spawner.y - screen.y;
                    }
                } else {
                    // more room on bottom, shrink
                    r.h = @max(24, (screen.y + screen.h) - r.y);
                }
            }
        },
    }

    return r;
}

const std = @import("std");
const dvui = @import("dvui.zig");

const Direction = dvui.enums.Direction;
const WidgetData = dvui.WidgetData;
const Options = dvui.Options;
const Size = dvui.Size;
const Rect = dvui.Rect;
const Id = dvui.Id;

test {
    @import("std").testing.refAllDecls(@This());
}
