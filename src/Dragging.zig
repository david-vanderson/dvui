fingers: [dvui.enums.Button.FINGERS]Finger = @splat(.{}),
/// Use this cursor from when a drag starts to when it ends.
cursor: ?dvui.enums.Cursor = null,

const Dragging = @This();

pub var threshold: f32 = 3;

// drag info for each finger
pub const Finger = struct {
    state: State = .none,
    button: dvui.enums.Button = .none, // used to differentiate mouse buttons
    pt: Point.Physical = .{},
    /// Offset of point of interest from the mouse.  Useful during a drag to
    /// locate where to move the point of interest.
    offset: Point.Physical = .{},
    /// Size of the item being dragged.  offset plus this makes a screen rect
    /// saying where the dragged item is relative to the mouse.
    size: Size.Physical = .{},
    /// Used for cross-widget dragging.  See `matchName`.
    name: ?[]const u8 = null,
};

pub const State = enum {
    none,
    prestart,
    dragging,
};

/// Optional features you might want when doing a mouse/touch drag.
pub const StartOptions = struct {
    /// Use this cursor from when a drag starts to when it ends.
    cursor: ?dvui.enums.Cursor = null,

    /// Offset of point of interest from the mouse.  Useful during a drag to
    /// locate where to move the point of interest.
    offset: Point.Physical = .{},

    /// Size of the item being dragged.  offset plus this makes a screen rect
    /// saying where the dragged item is relative to the mouse.
    size: Size.Physical = .{},

    /// Used for cross-widget dragging.  See `matchName`.
    name: ?[]const u8 = null,
};

/// Prepare for a possible mouse drag.  This will detect a drag, and also a
/// normal click (mouse down and up without a drag).
///
/// * `dragging` will return a Point once mouse motion has moved at least
/// threshold (default 3) natural pixels away from `p`.
///
/// * if cursor is non-null and a drag starts, use that cursor while dragging
///
/// * offset given here can be retrieved later with `offset` - example is
/// dragging bottom right corner of floating window.  The drag can start
/// anywhere in the hit area (passing the offset to the true corner), then
/// during the drag, the `offset` is added to the current mouse location to
/// recover where to move the true corner.
///
/// See `start` to immediately start a drag.
pub fn preStart(self: *Dragging, button: dvui.enums.Button, p: Point.Physical, options: StartOptions) void {
    const f = button.finger();
    self.fingers[f].state = .prestart;
    self.fingers[f].button = button;
    self.fingers[f].pt = p;
    self.fingers[f].offset = options.offset;
    self.fingers[f].size = options.size;
    self.fingers[f].name = options.name;
    self.cursor = options.cursor;
}

/// Start a mouse drag from p.  Use when only dragging is possible (normal
/// click would do nothing), otherwise use `preStart`.
///
/// * if cursor is non-null, use that cursor while dragging
///
/// * offset given here can be retrieved later with `offset` - example is
/// dragging bottom right corner of floating window.  The drag can start
/// anywhere in the hit area (passing the offset to the true corner), then
/// during the drag, the `offset` is added to the current mouse location to
/// recover where to move the true corner.
pub fn start(self: *Dragging, button: dvui.enums.Button, p: Point.Physical, options: StartOptions) void {
    const f = button.finger();
    self.fingers[f].state = .dragging;
    self.fingers[f].button = button;
    self.fingers[f].pt = p;
    self.fingers[f].offset = options.offset;
    self.fingers[f].size = options.size;
    self.fingers[f].name = options.name;
    self.cursor = options.cursor;
}

/// Get offset previously given to `preStart` or `start`.
pub fn getOffset(self: *Dragging, button: dvui.enums.Button) Point.Physical {
    return self.fingers[button.finger()].offset;
}

/// Get rect from mouse position using offset and size previously given to
/// `preStart` or `start`.
pub fn getRect(self: *Dragging, button: dvui.enums.Button) dvui.Rect.Physical {
    const f = self.fingers[button.finger()];
    const topleft = f.pt.plus(f.offset);
    return dvui.Rect.Physical.fromPoint(topleft).toSize(f.size);
}

pub const GetOptions = struct {
    /// If a name is given, `get` returns null immediately if it doesn't match
    /// the name given to `preStart` or `start`.  This is useful for widgets
    /// that need multiple different kinds of drags.
    name: ?[]const u8 = null,

    /// Used to scale the `preStart` dragging to natural pixels on the screen.
    /// This ensures that the amount of movement needed to start the drag is
    /// consistent at different screen DPIs or OS scalings.
    ///
    /// Should be the value of `Window.natural_scale`
    // TODO: This isn't the nicest api and there should probably be a nicer and
    //       more consistent way to access the `Window` instance for this
    window_natural_scale: f32,
};

/// If a mouse drag is happening, return the pixel difference to p from the
/// previous dragging call or the drag starting location (from `preStart`
/// or `start`).  Otherwise return null, meaning a drag hasn't started yet.
///
/// If name is given, returns null immediately if it doesn't match the name /
/// given to `preStart` or `start`.  This is useful for widgets that need
/// multiple different kinds of drags.
pub fn get(self: *Dragging, button: dvui.enums.Button, p: Point.Physical, opts: GetOptions) ?Point.Physical {
    const f = button.finger();
    if (opts.name) |name| {
        if (!std.mem.eql(u8, name, self.fingers[f].name orelse "")) return null;
    }

    switch (self.fingers[f].state) {
        .none => return null,
        .dragging => {
            const dp = p.diff(self.fingers[f].pt);
            self.fingers[f].pt = p;
            return dp;
        },
        .prestart => {
            const dp = p.diff(self.fingers[f].pt);
            const dps = dp.scale(1 / opts.window_natural_scale, Point.Natural);
            if (@abs(dps.x) > threshold or @abs(dps.y) > threshold) {
                self.fingers[f].pt = p;
                self.fingers[f].state = .dragging;
                return dp;
            } else {
                return null;
            }
        },
    }
}

/// True if any finger is `dragging` and `start` (or `preStart`) was given name.
///
/// Use to know when a cross-widget drag is in progress.
pub fn matchName(self: *Dragging, name: ?[]const u8) bool {
    if (name) |n| {
        for (self.fingers) |f| {
            if (f.state == .dragging and f.name != null and std.mem.eql(u8, n, f.name.?)) return true;
        }
    }

    return false;
}

/// Stop any mouse drag.
pub fn end(self: *Dragging, button: dvui.enums.Button) void {
    const f = button.finger();
    self.fingers[f].state = .none;
    self.fingers[f].name = null;
}

pub fn slot(self: *Dragging, button: dvui.enums.Button) *Finger {
    return &self.fingers[button.finger()];
}

const std = @import("std");
const dvui = @import("dvui.zig");

const Point = dvui.Point;
const Size = dvui.Size;
