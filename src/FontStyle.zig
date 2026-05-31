const dvui = @import("dvui.zig");

const Rect = dvui.Rect;
const Size = dvui.Size;

// Actually doing this made me realize that `Style`
// might not be the best name for it.
// Perhaps `FontOptions` or something among those lines?
const FontStyle = @This();

// Ideally the user would be able to pass a list of font families so fallbacks can be provided
// For example, fonts like `Noto Sans` do not include emojis so the user
// needs to provide something like `Noto Color Emoji` as a fallback
// Currently dvui provides no way for fallbacks as far as im aware
// so i don't know how this should look like.
font_family: []const u8,
size: f32 = 10,
// This might not be the correct dvui builtin to use
// The idea is for `scale` to be able to scale `x` and `y` individually using `size` as a base
scale: ?dvui.Point = null,
fill: dvui.Color = .white,
hover: ?dvui.Color = null,
press: ?dvui.Color = null,
select: dvui.Color = .{ .r = 0x32, .g = 0x60, .b = 0x98 },
outline: ?Outline = null,
shadow: ?Shadow = null,
spacing: f32 = 0,
style: Style = .normal,
weight: Weight = .regular,
width: Width = .normal,
/// This overrides the font's default line height
line_height_factor: ?f32 = null,
decorations: []Decoration = &.{},
// Synthesis should probably be a list as well...
// You might want to allow style and caps synthesis for example
synthesis: Synthesis = .auto,
kerning: Kerning = .auto,

pub const Shadow = struct {
    color: dvui.Color = .black,

    /// Shrink the shadow on all sides (before fade)
    shrink: f32 = 0,

    /// Offset down/right
    offset: dvui.Point = .{ .x = 1, .y = 1 },

    /// Extend the size of the transition to transparent at the edges
    fade: f32 = 2,

    /// Additional alpha multiply factor
    alpha: f32 = 0.5,
};

pub const Outline = struct {
    color: dvui.Color,
    thickness: f32,
};

pub const Decoration = union(enum) {
    underline: Definition,
    overline: Definition,
    /// Also known as `strike_through`
    line_through: Definition,
    /// `err` is a unique version of a wavy underline
    /// thus the style property doesn't actually do anything.
    err: Definition,

    pub const Definition = struct {
        /// `null` means inherit text color
        color: ?dvui.Color = null,
        style: Decoration.Style = .solid,
        /// Percent of font size, will always be at least 1 logical pixel
        thickness: f32 = 0.1,
    };

    pub const Style = enum {
        solid,
        double,
        dotted,
        dashed,
        wavy,
    };
};

pub const Kerning = enum {
    auto,
    normal,
    none,
};

pub const Synthesis = enum {
    none,
    auto,
    weight,
    style,
    oblique_only,
    small_caps,
    /// synthesize the subscript and superscript "position" typefaces
    position,
};

pub const Style = union(enum) {
    normal: void,
    italic: void,
    /// An angle between -90 and 90
    /// If `0` is passed, the default (14) will be used
    oblique: i8,

    pub fn toString(self: Style) []const u8 {
        return switch (self) {
            // I have never seen a font with a distinct oblique face
            // usually oblique means a normal font with synthesized inclination
            .normal, .oblique => "",
            .italic => " Italic",
        };
    }
};

pub const Weight = enum(u10) {
    thin = 100,
    extra_light = 200,
    light = 300,
    regular = 400,
    medium = 500,
    semi_bold = 600,
    bold = 700,
    extra_bold = 800,
    black = 900,
    extra_black = 950,
    _,

    /// Supported range: [1,1000]
    pub fn from(weight: u10) Weight {
        return @enumFromInt(weight);
    }

    pub fn bolder(self: Weight) Weight {
        return switch (self) {
            0...399 => .regular,
            .regular...699 => .bold,
            else => .black,
        };
    }

    pub fn lighter(self: Weight) Weight {
        return switch (self) {
            .extra_bold...1000 => .bold,
            .semi_bold...799 => .normal,
            else => .thin,
        };
    }

    /// Normalizes the enum into a known variant
    pub fn normalize(self: Weight) Weight {
        return switch (@intFromEnum(self)) {
            0...149 => .thin,
            150...249 => .extra_light,
            250...349 => .light,
            350...449 => .regular,
            450...549 => .medium,
            550...649 => .semi_bold,
            650...749 => .bold,
            750...849 => .extra_bold,
            850...949 => .black,
            else => .extra_black,
        };
    }

    pub fn toString(self: Weight) []const u8 {
        return switch (self.normalize()) {
            .thin => " Thin",
            .extra_light => " ExtraLight",
            .light => " Light",
            // Should we suffix it with `Regular`?
            // After all we are looking for a specific font inside a family
            .regular => "",
            .medium => " Medium",
            .semi_bold => " SemiBold",
            .bold => " Bold",
            .extra_bold => " ExtraBold",
            .black => " Black",
            .extra_black => " ExtraBlack",
            else => unreachable,
        };
    }
};

pub const Width = enum(u32) {
    ultra_condensed = 500,
    extra_condensed = 625,
    condensed = 750,
    semi_condensed = 875,
    normal = 1000,
    semi_expanded = 1125,
    expanded = 1250,
    extra_expanded = 1500,
    ultra_expanded = 2000,
    _,

    /// Supported range is usually [0.5, 2]
    pub fn from(width: f32) Weight {
        return @enumFromInt(@as(u32, @intFromFloat(width * 1000)));
    }

    pub fn toFloat(self: Width) f32 {
        return @as(f32, @floatFromInt(@intFromEnum(self))) / 1000;
    }

    /// Normalizes the enum into a known variant
    // The values here are very much arbitrary
    pub fn normalize(self: Weight) Weight {
        return switch (self) {
            0...524 => .ultra_condensed,
            525...724 => .extra_condensed,
            725...849 => .condensed,
            850...949 => .semi_condensed,
            950...1099 => .normal,
            1100...1180 => .semi_expanded,
            1178...1399 => .expanded,
            1400...1849 => .extra_expanded,
            else => .ultra_expanded,
        };
    }
};

// This needs a better name
pub const Options = struct {
    size: ?Apply = null,
    fill: ?Color = null,
    style: ?Style = null,
    weight: ?Weight = null,
    width: ?Width = null,
    line_height_factor: ?Apply = null,
    // decorations: ?[]Decoration = null,
    synthesis: ?Synthesis = null,
    kerning: ?Kerning = null,

    pub const Apply = union(enum) {
        value: f32,
        larger: f32,
    };

    pub const Color = union(enum) {
        value: ?dvui.Color,
        darker: void,
        lighter: void,
    };
};

// This has a bit of manual work but it aids in providing some custom apis
// that do not affect internals, only user facing code.
pub fn override(self: *const FontStyle, over: Options) FontStyle {
    var ret = self.*;

    if (over.size) |size| {
        switch (size) {
            .value => |val| ret.size = val,
            .larger => |val| ret.size += val,
        }
    }

    if (over.fill) |fill| {
        switch (fill) {
            .value => |val| {
                if (val) |color| ret.fill = color;
            },
            .darker => @panic("TODO"),
            .lighter => @panic("TODO"),
        }
    }

    if (over.style) |style| {
        ret.style = style;
    }

    if (over.weight) |weight| {
        ret.weight = weight;
    }

    if (over.width) |width| {
        ret.width = width;
    }

    if (over.line_height_factor) |line_height_factor| {
        switch (line_height_factor) {
            .value => |val| ret.line_height_factor = val,
            .larger => |val| {
                if (ret.line_height_factor != null)
                    ret.line_height_factor.? += val
                else
                    ret.line_height_factor = val;
            },
        }
    }

    // What would be the best way to merge decorations?
    // Maybe they should be changed to a different api?

    // if (over.decorations) |_| {}

    if (over.synthesis) |synthesis| {
        ret.synthesis = synthesis;
    }

    if (over.kerning) |kerning| {
        ret.kerning = kerning;
    }

    return ret;
}

// TODO: Fetch the font and get the line height
pub fn getLineHeightFactor(self: FontStyle) f32 {
    return self.line_height_factor orelse 1;
}

pub fn getFont(self: FontStyle) dvui.Font {
    return .{
        .family = dvui.Font.array(self.font_family),
        .weight = self.weight,
        .style = self.style,
    };
}

pub fn textHeight(self: FontStyle) f32 {
    return self.sizeM(1, 1).h;
}

pub fn lineHeight(self: FontStyle) f32 {
    return self.textHeight() * self.getLineHeightFactor();
}

pub fn sizeM(self: FontStyle, wide: f32, tall: f32) Size {
    const m_size: Size = self.textSize("M");
    return .{ .w = m_size.w * wide, .h = m_size.h * tall };
}

/// handles multiple lines
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn textSize(self: FontStyle, text: []const u8) Size {
    if (text.len == 0) {
        // just want the normal text height
        return .{ .w = 0, .h = self.textHeight() };
    }

    const line_height_factor = self.getLineHeightFactor();

    var ret = Size{};

    var line_height_adj: f32 = 0.0;
    var end: usize = 0;
    while (end < text.len) {
        if (end > 0) {
            ret.h += line_height_adj;
        }

        var end_idx: usize = undefined;
        var s = self.textSizeEx(text[end..], .{ .end_idx = &end_idx, .end_metric = .before });
        if (line_height_factor >= 1.0) {
            line_height_adj = s.h * (line_height_factor - 1.0);
        } else {
            s.h *= line_height_factor;
        }
        ret.h += s.h;
        ret.w = @max(ret.w, s.w);

        end += end_idx;
    }

    return ret;
}

pub const TextSizeOptions = struct {
    max_width: ?f32 = null,
    end_idx: ?*usize = null,
    end_metric: EndMetric = .before,
    kerning: ?bool = null,
    kern_in: ?[]u32 = null,
    kern_out: ?[]u32 = null,
    ascent_out: ?*f32 = null,

    pub const EndMetric = enum {
        before, // end_idx stops before text goes past max_width
        nearest, // end_idx stops at start of character closest to max_width
    };
};

/// textSizeEx always stops at a newline, use textSize to get multiline sizes
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn textSizeEx(self: FontStyle, text: []const u8, opts: TextSizeOptions) Size {
    // ask for a font that matches the natural display pixels so we get a more
    // accurate size
    const ss = dvui.parentGet().screenRectScale(Rect{}).s;
    const ask_size = self.size * ss;
    const sized_style = self.override(.{ .size = .{ .value = ask_size } });

    const cw = dvui.currentWindow();

    if (opts.ascent_out) |ao| ao.* = 10;

    // might give us a slightly smaller font
    const fce = dvui.fontCacheGet(sized_style) catch return .{ .w = 10, .h = 10 };

    // this must be synced with dvui.renderText()
    const target_fraction = if (cw.snap_to_pixels) 1.0 / ss else self.size / fce.em_height;

    var options = opts;
    if (opts.max_width) |mwidth| {
        // convert max_width into font units
        options.max_width = mwidth / target_fraction;
    }
    options.kerning = opts.kerning orelse cw.kerning;

    var s = fce.textSizeRaw(cw.gpa, text, options) catch return .{ .w = 10, .h = 10 };
    const line_height_factor = self.getLineHeightFactor();

    // do this check after calling textSizeRaw so that end_idx is set
    if (ask_size == 0.0) {
        if (opts.ascent_out) |ao| ao.* = 0;
        return Size{};
    }

    if (opts.ascent_out) |ao| {
        ao.* = fce.ascent;
        if (line_height_factor < 1.0) {
            ao.* = @round(ao.* * line_height_factor);
        }
        ao.* *= target_fraction;
    }

    // convert size back from font units
    return s.scale(target_fraction, Size);
}
