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

    const ask_size = @ceil(self.size * ss);
    const max_width_sized = (max_width orelse 1000000.0) * ss;
    const sized_font = self.resize(ask_size);
    const s = try sized_font.textSizeRaw(text, max_width_sized, end_idx, end_metric);

    // do this check after calling textSizeRaw so that end_idx is set
    if (ss == 0) return Size{};

    const target_fraction = self.size / ask_size;
    //std.debug.print("textSize size {d} for \"{s}\" {d} {}\n", .{ self.size, text, target_fraction, s.scale(target_fraction) });
    return s.scale(target_fraction);
}

// doesn't scale the font or max_width, always stops at newlines
pub fn textSizeRaw(self: *const Font, text: []const u8, max_width: ?f32, end_idx: ?*usize, end_metric: EndMetric) !Size {
    const fce = try dvui.fontCacheGet(self.*);

    const mwidth = max_width orelse 1000000.0;

    var x: f32 = 0;
    var minx: f32 = 0;
    var maxx: f32 = 0;
    var miny: f32 = 0;
    var maxy: f32 = fce.height;
    var tw: f32 = 0;
    var th: f32 = fce.height;

    var ei: usize = 0;
    var nearest_break: bool = false;

    var utf8 = (try std.unicode.Utf8View.init(text)).iterator();
    while (utf8.nextCodepoint()) |codepoint| {
        const gi = try fce.glyphInfoGet(@as(u32, @intCast(codepoint)), self.name);

        minx = @min(minx, x + gi.minx);
        maxx = @max(maxx, x + gi.maxx);
        maxx = @max(maxx, x + gi.advance);

        miny = @min(miny, gi.miny);
        maxy = @max(maxy, gi.maxy);

        // TODO: kerning

        if (codepoint == '\n') {
            // newlines always terminate, and don't use any space
            ei += std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
            break;
        }

        if ((maxx - minx) > mwidth) {
            switch (end_metric) {
                .before => break, // went too far
                .nearest => {
                    if ((maxx - minx) - mwidth >= mwidth - tw) {
                        break; // current one is closest
                    } else {
                        // get the next glyph and then break
                        nearest_break = true;
                    }
                },
            }
        }

        // record that we processed this codepoint
        ei += std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;

        // update space taken by glyph
        tw = maxx - minx;
        th = maxy - miny;
        x += gi.advance;

        if (nearest_break) break;
    }

    // TODO: xstart and ystart

    if (end_idx) |endout| {
        endout.* = ei;
    }

    //std.debug.print("textSizeRaw size {d} for \"{s}\" {d}x{d} {d}\n", .{ self.size, text, tw, th, ei });
    return Size{ .w = tw, .h = th };
}

pub fn lineHeight(self: *const Font) !f32 {
    // do the same sized thing as textSizeEx so they will cache the same font
    const ss = dvui.parentGet().screenRectScale(Rect{}).s;
    if (ss == 0) return 0;

    const ask_size = @ceil(self.size * ss);
    const target_fraction = self.size / ask_size;
    const sized_font = self.resize(ask_size);

    const fce = try dvui.fontCacheGet(sized_font);
    const face_height = fce.height;
    return face_height * target_fraction * self.line_height_factor;
}
