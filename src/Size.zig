const std = @import("std");
const dvui = @import("dvui.zig");

pub const Size = SizeType(.none);

pub fn SizeType(comptime units: dvui.enums.Units) type {
    return struct {
        const Self = @This();

        w: f32 = 0,
        h: f32 = 0,

        pub const zero: Self = .{ .w = 0, .h = 0 };

        pub fn width(w: f32) Self {
            return .{ .w = w };
        }

        pub fn height(h: f32) Self {
            return .{ .h = h };
        }

        /// Size of "M" characters in current theme body font.
        pub fn sizeM(wide: f32, tall: f32) Self {
            return dvui.Font.theme(.body).sizeM(wide, tall);
        }

        /// Natural pixels is the unit for subwindows. It differs from
        /// physical pixels on hidpi screens or with content scaling.
        pub const Natural = if (units == .none) SizeType(.natural) else @compileError("tried to nest Size.Natural");

        /// Physical pixels is the units for rendering and dvui events.
        /// Regardless of dpi or content scaling, physical pixels always
        /// matches the output screen.
        pub const Physical = if (units == .none) SizeType(.physical) else @compileError("tried to nest Size.Physical");

        pub const RectType = switch (units) {
            .none => dvui.Rect,
            .natural => dvui.Rect.Natural,
            .physical => dvui.Rect.Physical,
        };

        pub fn cast(size: anytype) Self {
            return .{ .w = size.w, .h = size.h };
        }

        pub fn all(v: f32) Self {
            return .{ .w = v, .h = v };
        }

        pub fn ceil(self: *const Self) Self {
            return .{ .w = @ceil(self.w), .h = @ceil(self.h) };
        }

        pub fn pad(s: *const Self, padding: RectType) Self {
            return .{ .w = s.w + padding.x + padding.w, .h = s.h + padding.y + padding.h };
        }

        pub fn padNeg(s: *const Self, padding: RectType) Self {
            return .{ .w = @max(0, s.w - padding.x - padding.w), .h = @max(0, s.h - padding.y - padding.h) };
        }

        pub fn max(a: Self, b: Self) Self {
            return .{ .w = @max(a.w, b.w), .h = @max(a.h, b.h) };
        }

        pub fn min(a: Self, b: Self) Self {
            return .{ .w = @min(a.w, b.w), .h = @min(a.h, b.h) };
        }

        /// Pass the scale and the type of Size it now represents.
        pub fn scale(self: *const Self, s: f32, sizeType: type) sizeType {
            return sizeType{ .w = self.w * s, .h = self.h * s };
        }

        pub fn format(self: *const Self, writer: *std.Io.Writer) !void {
            const type_name = switch (units) {
                .none => "Size",
                .natural => "Size.Natural",
                .physical => "Size.Physical",
            };
            try writer.print("{s}{{ {d} {d} }}", .{ type_name, self.w, self.h });
        }
    };
}

test {
    @import("std").testing.refAllDecls(@This());
}
