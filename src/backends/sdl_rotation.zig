//! Output rotation for the SDL backend. Free of SDL so it can be tested alone.

const std = @import("std");

/// Clockwise rotation applied to the rendered frame when it is presented.
/// A plain enum, so apps can keep it in a settings struct saved with
/// `std.zon` or `std.json`, or as text with `degrees` and `fromDegrees`.
pub const Rotation = enum(u16) {
    none = 0,
    cw90 = 90,
    cw180 = 180,
    cw270 = 270,

    pub fn swapsAxes(self: Rotation) bool {
        return self == .cw90 or self == .cw270;
    }

    pub fn degrees(self: Rotation) u16 {
        return @backingInt(self);
    }

    /// The rotation after another 90 degrees clockwise.
    pub fn turned(self: Rotation) Rotation {
        return switch (self) {
            .none => .cw90,
            .cw90 => .cw180,
            .cw180 => .cw270,
            .cw270 => .none,
        };
    }

    pub fn fromDegrees(text: []const u8) ?Rotation {
        const value = std.fmt.parseInt(u16, std.mem.trim(u8, text, " \t\r\n"), 10) catch return null;
        return switch (value) {
            0 => .none,
            90 => .cw90,
            180 => .cw180,
            270 => .cw270,
            else => null,
        };
    }

    /// Takes the DRM panel orientation names and returns the rotation the
    /// kernel applies to its own framebuffer for that panel.
    pub fn fromPanelOrientation(name: []const u8) ?Rotation {
        if (std.mem.eql(u8, name, "normal")) return .none;
        if (std.mem.eql(u8, name, "upside_down")) return .cw180;
        if (std.mem.eql(u8, name, "right_side_up")) return .cw90;
        if (std.mem.eql(u8, name, "left_side_up")) return .cw270;
        return null;
    }

    /// Maps a point of the unrotated `w` x `h` area to the rotated frame.
    pub fn mapPoint(self: Rotation, x: f32, y: f32, w: f32, h: f32) [2]f32 {
        return switch (self) {
            .none => .{ x, y },
            .cw90 => .{ y, w - x },
            .cw180 => .{ w - x, h - y },
            .cw270 => .{ h - y, x },
        };
    }

    pub fn mapDelta(self: Rotation, dx: f32, dy: f32) [2]f32 {
        return switch (self) {
            .none => .{ dx, dy },
            .cw90 => .{ dy, -dx },
            .cw180 => .{ -dx, -dy },
            .cw270 => .{ -dy, dx },
        };
    }
};

/// Finds the `panel_orientation=` entry of a `video=` option in a kernel command line.
pub fn rotationFromCmdline(cmdline: []const u8) ?Rotation {
    const key = "panel_orientation=";
    const start = (std.mem.find(u8, cmdline, key) orelse return null) + key.len;
    var end = start;
    while (end < cmdline.len and cmdline[end] != ',' and !std.ascii.isWhitespace(cmdline[end])) end += 1;
    return Rotation.fromPanelOrientation(cmdline[start..end]);
}

test "turning four times returns to the start" {
    var rotation: Rotation = .cw270;
    try std.testing.expectEqual(Rotation.none, rotation.turned());
    for (0..4) |_| rotation = rotation.turned();
    try std.testing.expectEqual(Rotation.cw270, rotation);
    try std.testing.expectEqual(@as(u16, 180), Rotation.cw180.degrees());
}

test "points map from the panel into the rotated frame" {
    // A 1200x1920 portrait panel presenting a 1920x1200 frame.
    const w = 1200;
    const h = 1920;
    try std.testing.expectEqual([2]f32{ 0, 0 }, Rotation.cw90.mapPoint(1200, 0, w, h));
    try std.testing.expectEqual([2]f32{ 1920, 0 }, Rotation.cw90.mapPoint(1200, 1920, w, h));
    try std.testing.expectEqual([2]f32{ 0, 1200 }, Rotation.cw90.mapPoint(0, 0, w, h));
    try std.testing.expectEqual([2]f32{ 0, 0 }, Rotation.cw270.mapPoint(0, 1920, w, h));
    try std.testing.expectEqual([2]f32{ 1920, 1200 }, Rotation.cw270.mapPoint(1200, 0, w, h));
    try std.testing.expectEqual([2]f32{ 1200, 1920 }, Rotation.cw180.mapPoint(0, 0, w, h));
    try std.testing.expectEqual([2]f32{ 5, 7 }, Rotation.none.mapPoint(5, 7, w, h));
}

test "normalized points and deltas follow the same rotation" {
    try std.testing.expectEqual([2]f32{ 0.25, 0.75 }, Rotation.cw90.mapPoint(0.25, 0.25, 1, 1));
    try std.testing.expectEqual([2]f32{ 0.75, 0.25 }, Rotation.cw270.mapPoint(0.25, 0.25, 1, 1));
    try std.testing.expectEqual([2]f32{ 2, -1 }, Rotation.cw90.mapDelta(1, 2));
    try std.testing.expectEqual([2]f32{ -2, 1 }, Rotation.cw270.mapDelta(1, 2));
    try std.testing.expectEqual([2]f32{ -1, -2 }, Rotation.cw180.mapDelta(1, 2));
}

test "rotation is parsed from degrees and the kernel command line" {
    try std.testing.expectEqual(Rotation.cw90, Rotation.fromDegrees("90\n").?);
    try std.testing.expect(Rotation.fromDegrees("45") == null);
    try std.testing.expect(Rotation.fromDegrees("up") == null);

    const cmdline = "root=/dev/mmcblk0p2 quiet video=DSI-2:1200x1920,panel_orientation=right_side_up\n";
    try std.testing.expectEqual(Rotation.cw90, rotationFromCmdline(cmdline).?);
    try std.testing.expectEqual(Rotation.cw270, rotationFromCmdline("video=DSI-2:panel_orientation=left_side_up rw").?);
    try std.testing.expectEqual(Rotation.none, rotationFromCmdline("video=x,panel_orientation=normal").?);
    try std.testing.expect(rotationFromCmdline("quiet root=/dev/sda1") == null);
    try std.testing.expect(rotationFromCmdline("video=x,panel_orientation=sideways") == null);
}
