const std = @import("std");
const dvui = @import("dvui.zig");

const Point = dvui.Point;
const Size = dvui.Size;

const Rect = @This();

x: f32 = 0,
y: f32 = 0,
w: f32 = 0,
h: f32 = 0,

/// Stroke (outline) a rounded rect.
///
/// radius values:
/// - x is top-left corner
/// - y is top-right corner
/// - w is bottom-right corner
/// - h is bottom-left corner
///
/// Only valid between dvui.Window.begin() and end().
pub fn stroke(self: Rect, radius: Rect, thickness: f32, color: dvui.Color, opts: dvui.PathStrokeOptions) !void {
    var path: std.ArrayList(dvui.Point) = .init(dvui.currentWindow().arena());
    defer path.deinit();

    try dvui.pathAddRect(&path, self, radius);
    var options = opts;
    options.closed = true;
    try dvui.pathStroke(path.items, thickness, color, options);
}

/// Fill a rounded rect.
///
/// radius values:
/// - x is top-left corner
/// - y is top-right corner
/// - w is bottom-right corner
/// - h is bottom-left corner
///
/// Only valid between dvui.Window.begin() and end().
pub fn fill(self: Rect, radius: Rect, color: dvui.Color) !void {
    var path: std.ArrayList(dvui.Point) = .init(dvui.currentWindow().arena());
    defer path.deinit();

    try dvui.pathAddRect(&path, self, radius);
    try dvui.pathFillConvex(path.items, color);
}

pub fn equals(self: *const Rect, r: Rect) bool {
    return (self.x == r.x and self.y == r.y and self.w == r.w and self.h == r.h);
}

pub fn plus(self: *const Rect, r: Rect) Rect {
    return Rect{ .x = self.x + r.x, .y = self.y + r.y, .w = self.w + r.w, .h = self.h + r.h };
}

pub fn nonZero(self: *const Rect) bool {
    return (self.x != 0 or self.y != 0 or self.w != 0 or self.h != 0);
}

pub fn all(v: f32) Rect {
    return Rect{ .x = v, .y = v, .w = v, .h = v };
}

pub fn fromPoint(p: Point) Rect {
    return Rect{ .x = p.x, .y = p.y };
}

pub fn toPoint(self: *const Rect, p: Point) Rect {
    return Rect{ .x = self.x, .y = self.y, .w = p.x - self.x, .h = p.y - self.y };
}

pub fn toSize(self: *const Rect, s: Size) Rect {
    return Rect{ .x = self.x, .y = self.y, .w = s.w, .h = s.h };
}

pub fn justSize(self: *const Rect) Rect {
    return Rect{ .x = 0, .y = 0, .w = self.w, .h = self.h };
}

pub fn topLeft(self: *const Rect) Point {
    return Point{ .x = self.x, .y = self.y };
}

pub fn topRight(self: *const Rect) Point {
    return Point{ .x = self.x + self.w, .y = self.y };
}

pub fn bottomLeft(self: *const Rect) Point {
    return Point{ .x = self.x, .y = self.y + self.h };
}

pub fn bottomRight(self: *const Rect) Point {
    return Point{ .x = self.x + self.w, .y = self.y + self.h };
}

pub fn center(self: *const Rect) Point {
    return Point{ .x = self.x + self.w / 2, .y = self.y + self.h / 2 };
}

pub fn size(self: *const Rect) Size {
    return Size{ .w = self.w, .h = self.h };
}

pub fn contains(self: *const Rect, p: Point) bool {
    return (p.x >= self.x and p.x <= (self.x + self.w) and p.y >= self.y and p.y <= (self.y + self.h));
}

pub fn empty(self: *const Rect) bool {
    return (self.w == 0 or self.h == 0);
}

pub fn scale(self: *const Rect, s: f32) Rect {
    return Rect{ .x = self.x * s, .y = self.y * s, .w = self.w * s, .h = self.h * s };
}

pub fn offset(self: *const Rect, r: Rect) Rect {
    return Rect{ .x = self.x + r.x, .y = self.y + r.y, .w = self.w, .h = self.h };
}

pub fn offsetNeg(self: *const Rect, r: Rect) Rect {
    return Rect{ .x = self.x - r.x, .y = self.y - r.y, .w = self.w, .h = self.h };
}

pub fn offsetNegPoint(self: *const Rect, p: Point) Rect {
    return Rect{ .x = self.x - p.x, .y = self.y - p.y, .w = self.w, .h = self.h };
}

pub fn intersect(a: Rect, b: Rect) Rect {
    const ax2 = a.x + a.w;
    const ay2 = a.y + a.h;
    const bx2 = b.x + b.w;
    const by2 = b.y + b.h;
    const x = @max(a.x, b.x);
    const y = @max(a.y, b.y);
    const x2 = @min(ax2, bx2);
    const y2 = @min(ay2, by2);
    return Rect{ .x = x, .y = y, .w = @max(0, x2 - x), .h = @max(0, y2 - y) };
}

/// True if self would be modified when clipped by r.
pub fn clippedBy(self: *const Rect, r: Rect) bool {
    return self.x < r.x or self.y < r.y or
        (self.x + self.w > r.x + r.w) or
        (self.y + self.h > r.y + r.h);
}

pub fn unionWith(a: Rect, b: Rect) Rect {
    const ax2 = a.x + a.w;
    const ay2 = a.y + a.h;
    const bx2 = b.x + b.w;
    const by2 = b.y + b.h;
    const x = @min(a.x, b.x);
    const y = @min(a.y, b.y);
    const x2 = @max(ax2, bx2);
    const y2 = @max(ay2, by2);
    return Rect{ .x = x, .y = y, .w = @max(0, x2 - x), .h = @max(0, y2 - y) };
}

pub fn shrinkToSize(self: *const Rect, s: Size) Rect {
    return Rect{ .x = self.x, .y = self.y, .w = @min(self.w, s.w), .h = @min(self.h, s.h) };
}

pub fn inset(self: *const Rect, r: Rect) Rect {
    return Rect{ .x = self.x + r.x, .y = self.y + r.y, .w = @max(0, self.w - r.x - r.w), .h = @max(0, self.h - r.y - r.h) };
}

pub fn insetAll(self: *const Rect, p: f32) Rect {
    return self.inset(Rect.all(p));
}

pub fn outset(self: *const Rect, r: Rect) Rect {
    return Rect{ .x = self.x - r.x, .y = self.y - r.y, .w = self.w + r.x + r.w, .h = self.h + r.y + r.h };
}

pub fn outsetAll(self: *const Rect, p: f32) Rect {
    return self.outset(Rect.all(p));
}

pub fn format(self: *const Rect, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try std.fmt.format(writer, "Rect{{ {d} {d} {d} {d} }}", .{ self.x, self.y, self.w, self.h });
}
