const dvui = @import("dvui.zig");

const Point = dvui.Point;
const Rect = dvui.Rect;

const RectScale = @This();

r: Rect.Physical = .{},
s: f32 = 1.0,

pub fn rectToRectScale(rs: *const RectScale, r: Rect) RectScale {
    return .{ .r = r.scale(rs.s, Rect.Physical).offset(rs.r), .s = rs.s };
}

pub fn rectToScreen(rs: *const RectScale, r: Rect) Rect.Physical {
    return r.scale(rs.s, Rect.Physical).offset(rs.r);
}

pub fn rectFromScreen(rs: *const RectScale, r: Rect.Physical) Rect {
    return r.offsetNeg(rs.r).scale(1 / rs.s, Rect);
}

pub fn pointToScreen(rs: *const RectScale, p: Point) Point.Physical {
    return p.scale(rs.s, Point.Physical).plus(rs.r.topLeft());
}

pub fn pointFromScreen(rs: *const RectScale, p: Point.Physical) Point {
    return p.diff(rs.r.topLeft()).scale(1 / rs.s, Point);
}

test {
    @import("std").testing.refAllDecls(@This());
}
