const std = @import("std");
const dvui = @import("dvui.zig");

const Rect = dvui.Rect;

const Size = @This();

w: f32 = 0,
h: f32 = 0,

pub fn all(v: f32) Size {
    return Size{ .w = v, .h = v };
}

pub fn rect(self: *const Size) Rect {
    return Rect{ .x = 0, .y = 0, .w = self.w, .h = self.h };
}

pub fn ceil(self: *const Size) Size {
    return Size{ .w = @ceil(self.w), .h = @ceil(self.h) };
}

pub fn pad(s: *const Size, padding: Rect) Size {
    return Size{ .w = s.w + padding.x + padding.w, .h = s.h + padding.y + padding.h };
}

pub fn padNeg(s: *const Size, padding: Rect) Size {
    return Size{ .w = @max(0, s.w - padding.x - padding.w), .h = @max(0, s.h - padding.y - padding.h) };
}

pub fn max(a: Size, b: Size) Size {
    return Size{ .w = @max(a.w, b.w), .h = @max(a.h, b.h) };
}

pub fn min(a: Size, b: Size) Size {
    return Size{ .w = @min(a.w, b.w), .h = @min(a.h, b.h) };
}

pub fn scale(self: *const Size, s: f32) Size {
    return Size{ .w = self.w * s, .h = self.h * s };
}

pub fn format(self: *const Size, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try std.fmt.format(writer, "Size{{ {d} {d} }}", .{ self.w, self.h });
}

/// Natural pixels is the unit for subwindow sizing and placement.
pub const Natural = struct {
    w: f32 = 0,
    h: f32 = 0,

    pub inline fn toSize(self: Size.Natural) Size {
        return .{ .w = self.w, .h = self.h };
    }

    pub inline fn fromSize(p: Size) Size.Natural {
        return .{ .w = p.w, .h = p.h };
    }

    /// Only valid between `dvui.Window.begin`and `dvui.Window.end`.
    pub inline fn toPhysical(self: Size.Natural) Size.Physical {
        return .fromSize(self.toSize().scale(dvui.windowNaturalScale()));
    }

    pub fn format(self: *const Size.Natural, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "Size.Natural{{ {d} {d} }}", .{ self.w, self.h });
    }
};

/// Pixels is the unit for rendering and user input.
///
/// Physical pixels might be more on a hidpi screen or if the user has content scaling.
pub const Physical = struct {
    w: f32 = 0,
    h: f32 = 0,

    pub inline fn toSize(self: Size.Physical) Size {
        return .{ .w = self.w, .h = self.h };
    }

    pub inline fn fromSize(p: Size) Size.Physical {
        return .{ .w = p.w, .h = p.h };
    }

    /// Only valid between `dvui.Window.begin`and `dvui.Window.end`.
    pub inline fn toNatural(self: Size.Physical) Size.Natural {
        return .fromSize(self.toSize().scale(1 / dvui.windowNaturalScale()));
    }

    pub fn format(self: *const Size.Physical, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "Size.Physical{{ {d} {d} }}", .{ self.w, self.h });
    }
};

test {
    @import("std").testing.refAllDecls(@This());
}
