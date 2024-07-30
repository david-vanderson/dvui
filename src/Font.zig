const std = @import("std");
const dvui = @import("dvui.zig");

const Rect = dvui.Rect;
const Size = dvui.Size;

const Font = @This();

size: f32,
line_height_factor: f32 = 1.0,
name: []const u8,
ttf_bytes_id: TTFBytesId,
//ttf_bytes: []const u8,

pub fn resize(self: *const Font, s: f32) Font {
    return Font{ .size = s, .line_height_factor = self.line_height_factor, .name = self.name, .ttf_bytes_id = self.ttf_bytes_id };
}

pub fn lineHeightFactor(self: *const Font, factor: f32) Font {
    return Font{ .size = self.size, .line_height_factor = factor, .name = self.name, .ttf_bytes_id = self.ttf_bytes_id };
}

// handles multiple lines
pub fn textSize(self: *const Font, text: []const u8) !Size {
    if (text.len == 0) {
        // just want the line height
        return .{ .w = 0, .h = try self.lineHeight() };
    }

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
    const ask_size = self.size * ss;
    const sized_font = self.resize(ask_size);

    // might give us a slightly smaller font
    const fce = try dvui.fontCacheGet(sized_font);

    // this must be synced with dvui.renderText()
    const target_fraction = if (dvui.currentWindow().snap_to_pixels) 1.0 / ss else self.size / fce.height;

    // convert max_width into font units
    const max_width_sized = (max_width orelse 1000000.0) / target_fraction;

    var s = try fce.textSizeRaw(self.name, text, max_width_sized, end_idx, end_metric);
    s.h *= self.line_height_factor;

    // do this check after calling textSizeRaw so that end_idx is set
    if (ss == 0) return Size{};

    // convert size back from font units
    return s.scale(target_fraction);
}

pub fn lineHeight(self: *const Font) !f32 {
    const s = try self.textSizeEx(" ", null, null, .before);
    return s.h;
}

// functionality for accessing builtin fonts
pub const bitstream_vera = @import("fonts/bitstream_vera.zig");
pub const pixelify_sans = @import("fonts/pixelify-sans.zig");
pub const hack = @import("fonts/hack.zig");

pub const FontBytes = struct {
    pub const Vera = bitstream_vera.Vera;
    pub const VeraBd = bitstream_vera.VeraBd;
    pub const VeraBI = bitstream_vera.VeraBI;
    pub const VeraMoBi = bitstream_vera.VeraMoBI;
    pub const VeraMono = bitstream_vera.VeraMono;
    pub const Pixelify = pixelify_sans.PixelifySans;
    pub const PixelifyBd = pixelify_sans.PixelifySansBd;
    pub const PixelifyMe = pixelify_sans.PixelifySansMe;
    pub const PixelifySeBd = pixelify_sans.PixelifySansSeBd;
    pub const Hack = hack.Hack;
    pub const HackBd = hack.HackBd;
    pub const HackIt = hack.HackIt;
    pub const HackBdIt = hack.HackBdIt;
};

pub const TTFBytesId = std.meta.DeclEnum(FontBytes);

pub fn getFontBytes(ttf_bytes_id: TTFBytesId) []const u8 {
    inline for (@typeInfo(FontBytes).Struct.decls, 0..) |decl, i| {
        if (@intFromEnum(ttf_bytes_id) == i) {
            return @field(FontBytes, decl.name);
        }
    }
    unreachable;
}
