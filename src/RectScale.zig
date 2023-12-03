const dvui = @import("dvui.zig");

const Point = dvui.Point;
const Rect = dvui.Rect;

const RectScale = @This();

r: Rect = Rect{},
s: f32 = 0.0,

pub fn rectToRectScale(rs: *const RectScale, r: Rect) RectScale {
    return .{ .r = r.scale(rs.s).offset(rs.r), .s = rs.s };
}

pub fn rectToScreen(rs: *const RectScale, r: Rect) Rect {
    return r.scale(rs.s).offset(rs.r);
}

pub fn rectFromScreen(rs: *const RectScale, r: Rect) Rect {
    return r.offsetNeg(rs.r).scale(1 / rs.s);
}

pub fn pointToScreen(rs: *const RectScale, p: Point) Point {
    return p.scale(rs.s).plus(rs.r.topleft());
}

pub fn pointFromScreen(rs: *const RectScale, p: Point) Point {
    return Point.diff(p, rs.r.topleft()).scale(1 / rs.s);
}
