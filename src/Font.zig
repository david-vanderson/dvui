const std = @import("std");
const dvui = @import("dvui.zig");

const Rect = dvui.Rect;
const Size = dvui.Size;

const Font = @This();

//size: f32,
line_height_factor: f32 = 1.0,
name: []const u8,
scale: f32 = 1.0,

//pub fn resize(self: *const Font, s: f32) Font {
//return Font{ .size = s, .line_height_factor = self.line_height_factor, .name = self.name };
//}

pub fn lineHeightFactor(self: *const Font, factor: f32) Font {
    return Font{ .scale = self.scale, .line_height_factor = factor, .name = self.name };
}

pub const Data = struct {
    bytes: []const u8,
    base_size: f32 = 16,
};

// default bytes if font id is not found in database
pub var default_font_data: Data = TTFBytes.Vera;

/// Gets font ttf bytes and default size for font
pub fn getData(self: Font) *Font.Data {
    if (dvui.currentWindow().font_database.getPtr(self.name)) |font_data| {
        return font_data;
    } else {
        return &default_font_data;
    }
}

pub fn getBytes(self: Font) []const u8 {
    return self.getData().bytes;
}

pub fn getSize(self: Font) f32 {
    return @floor(self.getData().base_size * self.scale);
}

//handles multiple lines
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
pub fn textSizeEx(
    self: *const Font,
    text: []const u8,
    max_width: ?f32,
    end_idx: ?*usize,
    end_metric: EndMetric,
) !Size {
    // ask for a font that matches the natural display pixels so we get a more
    // accurate size
    const font_data = self.getData();

    const screen_scale = dvui.parentGet().screenRectScale(Rect{}).s;
    const ask_size = self.getSize() * screen_scale;
    //const sized_font = self.resize(ask_size);

    // might give us a slightly smaller font
    const fce = try dvui.fontCacheGet(font_data.bytes, ask_size);

    // this must be synced with dvui.renderText()
    const target_fraction = if (dvui.currentWindow().snap_to_pixels)
        1.0 / screen_scale
    else
        self.getSize() / fce.height;

    var max_width_sized: ?f32 = null;
    if (max_width) |mwidth| {
        // convert max_width into font units
        max_width_sized = mwidth / target_fraction;
    }

    var s = try fce.textSizeRaw(self.name, text, max_width_sized, end_idx, end_metric);
    s.h *= self.line_height_factor;

    // do this check after calling textSizeRaw so that end_idx is set
    if (ask_size == 0.0) return Size{};

    // convert size back from font units
    return s.scale(target_fraction);
}
//
pub fn lineHeight(self: *const Font) !f32 {
    const s = try self.textSizeEx(" ", null, null, .before);
    return s.h;
}

// functionality for accessing builtin fonts
pub const TTFBytes = struct {
    pub const Aleo = Data{
        .bytes = @embedFile("fonts/Aleo/static/Aleo-Regular.ttf"),
        .base_size = 16,
    };
    pub const AleoBd = Data{
        .bytes = @embedFile("fonts/Aleo/static/Aleo-Bold.ttf"),
        .base_size = 16,
    };
    pub const Vera = Data{
        .bytes = @embedFile("fonts/bitstream-vera/Vera.ttf"),
        .base_size = 16,
    };
    pub const VeraBI = Data{
        .bytes = @embedFile("fonts/bitstream-vera/VeraBI.ttf"),
        .base_size = 16,
    };
    pub const VeraBd = Data{
        .bytes = @embedFile("fonts/bitstream-vera/VeraBd.ttf"),
        .base_size = 16,
    };
    pub const VeraIt = Data{
        .bytes = @embedFile("fonts/bitstream-vera/VeraIt.ttf"),
        .base_size = 16,
    };
    pub const VeraMoBI = Data{
        .bytes = @embedFile("fonts/bitstream-vera/VeraMoBI.ttf"),
        .base_size = 16,
    };
    pub const VeraMoBd = Data{
        .bytes = @embedFile("fonts/bitstream-vera/VeraMoBd.ttf"),
        .base_size = 16,
    };
    pub const VeraMoIt = Data{
        .bytes = @embedFile("fonts/bitstream-vera/VeraMoIt.ttf"),
        .base_size = 16,
    };
    pub const VeraMono = Data{
        .bytes = @embedFile("fonts/bitstream-vera/VeraMono.ttf"),
        .base_size = 16,
    };
    pub const VeraSe = Data{
        .bytes = @embedFile("fonts/bitstream-vera/VeraSe.ttf"),
        .base_size = 16,
    };
    pub const VeraSeBd = Data{
        .bytes = @embedFile("fonts/bitstream-vera/VeraSeBd.ttf"),
        .base_size = 16,
    };
    pub const Pixelify = Data{
        .bytes = @embedFile("fonts/Pixelify_Sans/static/PixelifySans-Regular.ttf"),
        .base_size = 16,
    };
    pub const PixelifyBd = Data{
        .bytes = @embedFile("fonts/Pixelify_Sans/static/PixelifySans-Bold.ttf"),
        .base_size = 16,
    };
    pub const PixelifyMe = Data{
        .bytes = @embedFile("fonts/Pixelify_Sans/static/PixelifySans-Medium.ttf"),
        .base_size = 16,
    };
    pub const PixelifySeBd = Data{
        .bytes = @embedFile("fonts/Pixelify_Sans/static/PixelifySans-SemiBold.ttf"),
        .base_size = 16,
    };
    pub const Hack = Data{
        .bytes = @embedFile("fonts/hack/Hack-Regular.ttf"),
        .base_size = 16,
    };
    pub const HackBd = Data{
        .bytes = @embedFile("fonts/hack/Hack-Bold.ttf"),
        .base_size = 16,
    };
    pub const HackIt = Data{
        .bytes = @embedFile("fonts/hack/Hack-Italic.ttf"),
        .base_size = 16,
    };
    pub const HackBdIt = Data{
        .bytes = @embedFile("fonts/hack/Hack-BoldItalic.ttf"),
        .base_size = 16,
    };
    pub const OpenDyslexic = Data{
        .bytes = @embedFile("fonts/OpenDyslexic/compiled/OpenDyslexic-Regular.otf"),
        .base_size = 16,
    };
    pub const OpenDyslexicBd = Data{
        .bytes = @embedFile("fonts/OpenDyslexic/compiled/OpenDyslexic-Bold.otf"),
        .base_size = 16,
    };
    pub const OpenDyslexicIt = Data{
        .bytes = @embedFile("fonts/OpenDyslexic/compiled/OpenDyslexic-Italic.otf"),
        .base_size = 16,
    };
    pub const OpenDyslexicBdIt = Data{
        .bytes = @embedFile("fonts/OpenDyslexic/compiled/OpenDyslexic-Bold-Italic.otf"),
        .base_size = 16,
    };
};

pub fn initTTFBytesDatabase(allocator: std.mem.Allocator) !std.StringHashMap(Data) {
    var result = std.StringHashMap(Data).init(allocator);
    inline for (@typeInfo(TTFBytes).Struct.decls) |decl| {
        try result.put(decl.name, .{
            .bytes = @field(TTFBytes, decl.name).bytes,
            .base_size = @field(TTFBytes, decl.name).base_size,
        });
    }
    return result;
}
