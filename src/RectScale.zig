const dvui = @import("dvui.zig");

const Point = dvui.Point;
const Rect = dvui.Rect;

const RectScale = @This();

r: Rect.Physical = .{},
s: f32 = 1.0,

pub fn rectToRectScale(rs: *const RectScale, r: Rect) RectScale {
    return .{ .r = .fromRect(r.scale(rs.s).offset(rs.r.toRect())), .s = rs.s };
}

pub fn rectToScreen(rs: *const RectScale, r: Rect) Rect.Physical {
    return .fromRect(r.scale(rs.s).offset(rs.r.toRect()));
}

pub fn rectFromScreen(rs: *const RectScale, r: Rect.Physical) Rect {
    return r.toRect().offsetNeg(rs.r.toRect()).scale(1 / rs.s);
}

pub fn pointToScreen(rs: *const RectScale, p: Point) Point.Physical {
    return .fromPoint(p.scale(rs.s).plus(rs.r.topLeft().toPoint()));
}

pub fn pointFromScreen(rs: *const RectScale, p: Point.Physical) Point {
    return p.diff(rs.r.topLeft()).toPoint().scale(1 / rs.s);
}

test {
    @import("std").testing.refAllDecls(@This());
}
