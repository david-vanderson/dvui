const std = @import("std");
const dvui = @import("dvui.zig");

const Rect = dvui.Rect;
const Size = dvui.Size;

const Font = @This();

size: f32,
line_height_factor: f32 = 1.2,
id: FontId,

// default bytes if font id is not found in database
pub const default_ttf_bytes = TTFBytes.Vera;
// NOTE: This font name should match the name in the font data base
pub const default_font_id = FontId.Vera;

pub fn hash(font: Font) u64 {
    var h = dvui.fnv.init();
    const bytes = if (dvui.currentWindow().font_bytes.get(font.id)) |fbe| fbe.ttf_bytes else Font.default_ttf_bytes;
    h.update(std.mem.asBytes(&bytes.ptr));
    h.update(std.mem.asBytes(&font.size));
    return h.final();
}

pub fn switchFont(self: Font, id: FontId) Font {
    return Font{ .size = self.size, .line_height_factor = self.line_height_factor, .id = id };
}

pub fn resize(self: Font, s: f32) Font {
    return Font{ .size = s, .line_height_factor = self.line_height_factor, .id = self.id };
}

pub fn lineHeightFactor(self: Font, factor: f32) Font {
    return Font{ .size = self.size, .line_height_factor = factor, .id = self.id };
}

pub fn textHeight(self: Font) f32 {
    return self.sizeM(1, 1).h;
}

pub fn lineHeight(self: Font) f32 {
    return self.textHeight() * self.line_height_factor;
}

pub fn sizeM(self: Font, wide: f32, tall: f32) Size {
    const msize: Size = self.textSize("M");
    return .{ .w = msize.w * wide, .h = msize.h * tall };
}

// handles multiple lines
pub fn textSize(self: Font, text: []const u8) Size {
    if (text.len == 0) {
        // just want the normal text height
        return .{ .w = 0, .h = self.textHeight() };
    }

    var ret = Size{};

    var line_height_adj: f32 = undefined;
    var end: usize = 0;
    while (end < text.len) {
        if (end > 0) {
            ret.h += line_height_adj;
        }

        var end_idx: usize = undefined;
        const s = self.textSizeEx(text[end..], .{ .end_idx = &end_idx, .end_metric = .before });
        line_height_adj = s.h * (self.line_height_factor - 1.0);
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

pub const TextSizeOptions = struct {
    max_width: ?f32 = null,
    end_idx: ?*usize = null,
    end_metric: EndMetric = .before,
    kerning: ?bool = null,
    kern_in: ?[]u32 = null,
    kern_out: ?[]u32 = null,
};

/// textSizeEx always stops at a newline, use textSize to get multiline sizes
pub fn textSizeEx(self: Font, text: []const u8, opts: TextSizeOptions) Size {
    // ask for a font that matches the natural display pixels so we get a more
    // accurate size

    const ss = dvui.parentGet().screenRectScale(Rect{}).s;
    const ask_size = self.size * ss;
    const sized_font = self.resize(ask_size);

    // might give us a slightly smaller font
    const fce = dvui.fontCacheGet(sized_font) catch return .{ .w = 10, .h = 10 };

    // this must be synced with dvui.renderText()
    const target_fraction = if (dvui.currentWindow().snap_to_pixels) 1.0 / ss else self.size / fce.height;

    var options = opts;
    if (opts.max_width) |mwidth| {
        // convert max_width into font units
        options.max_width = mwidth / target_fraction;
    }

    var s = fce.textSizeRaw(text, options) catch return .{ .w = 10, .h = 10 };

    // do this check after calling textSizeRaw so that end_idx is set
    if (ask_size == 0.0) return Size{};

    // convert size back from font units
    return s.scale(target_fraction, Size);
}

pub const FontId = enum(u64) {
    // The following predefined names for TTFBytes (verified at comptime)
    // These give a more useful debug output for the builtin font
    InvalidFontFile = dvui.fnv.hash("InvalidFontFile"),
    Aleo = dvui.fnv.hash("Aleo"),
    AleoBd = dvui.fnv.hash("AleoBd"),
    Vera = dvui.fnv.hash("Vera"),
    VeraBI = dvui.fnv.hash("VeraBI"),
    VeraBd = dvui.fnv.hash("VeraBd"),
    VeraIt = dvui.fnv.hash("VeraIt"),
    VeraMoBI = dvui.fnv.hash("VeraMoBI"),
    VeraMoBd = dvui.fnv.hash("VeraMoBd"),
    VeraMoIt = dvui.fnv.hash("VeraMoIt"),
    VeraMono = dvui.fnv.hash("VeraMono"),
    VeraSe = dvui.fnv.hash("VeraSe"),
    VeraSeBd = dvui.fnv.hash("VeraSeBd"),
    Pixelify = dvui.fnv.hash("Pixelify"),
    PixelifyBd = dvui.fnv.hash("PixelifyBd"),
    PixelifyMe = dvui.fnv.hash("PixelifyMe"),
    PixelifySeBd = dvui.fnv.hash("PixelifySeBd"),
    Hack = dvui.fnv.hash("Hack"),
    HackBd = dvui.fnv.hash("HackBd"),
    HackIt = dvui.fnv.hash("HackIt"),
    HackBdIt = dvui.fnv.hash("HackBdIt"),
    OpenDyslexic = dvui.fnv.hash("OpenDyslexic"),
    OpenDyslexicBd = dvui.fnv.hash("OpenDyslexicBd"),
    OpenDyslexicIt = dvui.fnv.hash("OpenDyslexicIt"),
    OpenDyslexicBdIt = dvui.fnv.hash("OpenDyslexicBdIt"),
    // Not included in TTFBytes but should still be named
    Noto = dvui.fnv.hash("Noto"),
    _,

    pub fn fromName(name: []const u8) FontId {
        return @enumFromInt(dvui.fnv.hash(name));
    }

    pub fn format(self: *const FontId, writer: *std.Io.Writer) !void {
        const named_ids = std.meta.tags(FontId);
        for (named_ids) |named| {
            if (named == self.*) {
                try writer.writeAll(@tagName(named));
            }
        } else {
            try writer.print("Id 0x{x}", .{@intFromEnum(self.*)});
        }
    }

    // Ensure that all builtin fonts have a named variant
    comptime {
        const EnumKV = struct { []const u8, FontId };
        const fields = @typeInfo(FontId).@"enum".fields;
        var kvs_array: [fields.len]EnumKV = undefined;
        for (fields, 0..) |enumField, i| {
            kvs_array[i] = .{ enumField.name, @field(FontId, enumField.name) };
        }
        const map = std.StaticStringMap(FontId).initComptime(kvs_array);
        for (@typeInfo(TTFBytes).@"struct".decls) |decl| {
            std.debug.assert(map.get(decl.name) == FontId.fromName(decl.name));
        }
    }
};

// functionality for accessing builtin fonts
pub const TTFBytes = struct {
    pub const InvalidFontFile = "This is a very invalid font file";
    pub const Aleo = @embedFile("fonts/Aleo/static/Aleo-Regular.ttf");
    pub const AleoBd = @embedFile("fonts/Aleo/static/Aleo-Bold.ttf");
    pub const Vera = @embedFile("fonts/bitstream-vera/Vera.ttf");
    //pub const VeraBI = @embedFile("fonts/bitstream-vera/VeraBI.ttf");
    pub const VeraBd = @embedFile("fonts/bitstream-vera/VeraBd.ttf");
    //pub const VeraIt = @embedFile("fonts/bitstream-vera/VeraIt.ttf");
    //pub const VeraMoBI = @embedFile("fonts/bitstream-vera/VeraMoBI.ttf");
    //pub const VeraMoBd = @embedFile("fonts/bitstream-vera/VeraMoBd.ttf");
    //pub const VeraMoIt = @embedFile("fonts/bitstream-vera/VeraMoIt.ttf");
    pub const VeraMono = @embedFile("fonts/bitstream-vera/VeraMono.ttf");
    //pub const VeraSe = @embedFile("fonts/bitstream-vera/VeraSe.ttf");
    //pub const VeraSeBd = @embedFile("fonts/bitstream-vera/VeraSeBd.ttf");
    pub const Pixelify = @embedFile("fonts/Pixelify_Sans/static/PixelifySans-Regular.ttf");
    //pub const PixelifyBd = @embedFile("fonts/Pixelify_Sans/static/PixelifySans-Bold.ttf");
    //pub const PixelifyMe = @embedFile("fonts/Pixelify_Sans/static/PixelifySans-Medium.ttf");
    //pub const PixelifySeBd = @embedFile("fonts/Pixelify_Sans/static/PixelifySans-SemiBold.ttf");
    //pub const Hack = @embedFile("fonts/hack/Hack-Regular.ttf");
    //pub const HackBd = @embedFile("fonts/hack/Hack-Bold.ttf");
    //pub const HackIt = @embedFile("fonts/hack/Hack-Italic.ttf");
    //pub const HackBdIt = @embedFile("fonts/hack/Hack-BoldItalic.ttf");
    pub const OpenDyslexic = @embedFile("fonts/OpenDyslexic/compiled/OpenDyslexic-Regular.otf");
    pub const OpenDyslexicBd = @embedFile("fonts/OpenDyslexic/compiled/OpenDyslexic-Bold.otf");
    //pub const OpenDyslexicIt = @embedFile("fonts/OpenDyslexic/compiled/OpenDyslexic-Italic.otf");
    //pub const OpenDyslexicBdIt = @embedFile("fonts/OpenDyslexic/compiled/OpenDyslexic-Bold-Italic.otf");
};

pub fn initTTFBytesDatabase(allocator: std.mem.Allocator) std.mem.Allocator.Error!@FieldType(dvui.Window, "font_bytes") {
    var result: @FieldType(dvui.Window, "font_bytes") = .empty;
    inline for (@typeInfo(TTFBytes).@"struct".decls) |decl| {
        try result.putNoClobber(allocator, .fromName(decl.name), dvui.FontBytesEntry{
            .ttf_bytes = @field(TTFBytes, decl.name),
            .name = decl.name,
            .allocator = null,
        });
    }

    if (!dvui.wasm) {
        try result.putNoClobber(allocator, .Noto, dvui.FontBytesEntry{
            .ttf_bytes = @embedFile("fonts/NotoSansKR-Regular.ttf"),
            .name = @tagName(FontId.Noto),
            .allocator = null,
        });
    }

    return result;
}

test {
    @import("std").testing.refAllDecls(@This());
}
