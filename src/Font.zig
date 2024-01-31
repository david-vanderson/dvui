const std = @import("std");
const dvui = @import("dvui.zig");

const Rect = dvui.Rect;
const Size = dvui.Size;

const Font = @This();

size: f32,
line_height_factor: f32 = 1.0,
name: []const u8,
ttf_bytes: []const u8,

pub fn resize(self: *const Font, s: f32) Font {
    return Font{ .size = s, .line_height_factor = self.line_height_factor, .name = self.name, .ttf_bytes = self.ttf_bytes };
}

pub fn lineHeightFactor(self: *const Font, factor: f32) Font {
    return Font{ .size = self.size, .line_height_factor = factor, .name = self.name, .ttf_bytes = self.ttf_bytes };
}

// handles multiple lines
pub fn textSize(self: *const Font, text: []const u8) !Size {
    var ret = Size{};

    var end: usize = 0;
    while (end < text.len) {
        var end_idx: usize = undefined;
        const s = try self.textSizeEx(text[end..], null, &end_idx, .before);
        ret.h += s.h;
        ret.w = @max(ret.w, s.w);

        end += end_idx;
    }

    return ret;
}

pub const EndMetric = enum {
    before, // end_idx stops before text goes past max_width
    nearest, // end_idx stops at start of character closest to max_width
};

/// textSizeEx always stops at a newline, use textSize to get multiline sizes
pub fn textSizeEx(self: *const Font, text: []const u8, max_width: ?f32, end_idx: ?*usize, end_metric: EndMetric) !Size {
    // ask for a font that matches the natural display pixels so we get a more
    // accurate size

    const ss = dvui.parentGet().screenRectScale(Rect{}).s;
    const max_width_sized = (max_width orelse 1000000.0) * ss;

    const ask_size = self.size * ss;
    const sized_font = self.resize(ask_size);
    const fce = try dvui.fontCacheGet(sized_font);
    const s = try fce.textSizeRaw(self.name, text, max_width_sized, end_idx, end_metric);

    // do this check after calling textSizeRaw so that end_idx is set
    if (ss == 0) return Size{};

    const target_fraction = self.size / fce.height;
    //std.debug.print("textSize size {d} for \"{s}\" {d} {}\n", .{ self.size, text, target_fraction, s.scale(target_fraction) });
    return s.scale(target_fraction);
}

pub fn lineHeight(self: *const Font) !f32 {
    // do the same sized thing as textSizeEx so they will cache the same font
    const ss = dvui.parentGet().screenRectScale(Rect{}).s;
    if (ss == 0) return 0;

    return self.size * self.line_height_factor;
}
