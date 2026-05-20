const dvui = @import("dvui.zig");

// Actually doing this made me realize that `Style`
// might not be the best name for it.
// Perhaps `FontOptions` or something among those lines?
const FontStyle = @This();

size: f32 = 10,
// This might nto be the correct dvui builtin to use
// The idea is for `scale` to be able to scale `x` and `y` individually using `size` as a base
scale: ?dvui.Point = null,
fill: dvui.Color = .white,
outline: ?Outline = null,
shadow: ?Shadow = null,
spacing: f32 = 0,
style: Style = .normal,
weight: Weight = .normal,
width: Width = .normal,
line_height_factor: f32 = 1.2,
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
};

pub const Weight = enum(u10) {
    thin = 100,
    extra_light = 200,
    light = 300,
    normal = 400,
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
            0...399 => .normal,
            .normal...699 => .bold,
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
        return switch (self) {
            0...149 => .thin,
            150...249 => .extra_light,
            250...349 => .light,
            350...449 => .normal,
            450...549 => .medium,
            550...649 => .semi_bold,
            650...749 => .bold,
            750...849 => .extra_bold,
            850...949 => .black,
            else => .extra_black,
        };
    }
};

pub const Width = enum(f32) {
    ultra_condensed = 0.5,
    extra_condensed = 0.625,
    condensed = 0.75,
    semi_condensed = 0.875,
    normal = 1,
    semi_expanded = 1.125,
    expanded = 1.25,
    extra_expanded = 1.5,
    ultra_expanded = 2,
    _,

    /// Supported range is usually [0.5, 2]
    pub fn from(width: f32) Weight {
        // This is probably unsafe...
        return @bitCast(width);
    }

    /// Normalizes the enum into a known variant
    // The values here are very much arbitrary
    pub fn normalize(self: Weight) Weight {
        return if (self < 0.6)
            .ultra_condensed
        else if (self < 0.72)
            .extra_condensed
        else if (self < 0.83)
            .condensed
        else if (self < 1.1)
            .normal
        else if (self < 1.225)
            .semi_expanded
        else if (self < 1.4)
            .expanded
        else if (self < 1.8)
            .extra_expanded
        else
            .ultra_expanded;
    }
};

// This needs a better name
pub const Options = struct {
    size: ?Size = null,
    fill: ?Color = null,
    style: ?Style = null,
    weight: ?Weight = null,
    width: ?Width = null,
    line_height_factor: ?Size = null,
    decorations: ?[]Decoration = null,
    synthesis: ?Synthesis = null,
    kerning: ?Kerning = null,

    pub const Size = union(enum) {
        value: f32,
        larger: f32,
    };

    pub const Color = union(enum) {
        value: dvui.Color,
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
            .value => |val| ret.fill = val,
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
            .larger => |val| ret.line_height_factor += val,
        }
    }

    // What would be the best way to merge decorations?
    // Maybe they should be changed to a different api?

    if (over.decorations) |_| {}

    if (over.synthesis) |synthesis| {
        ret.synthesis = synthesis;
    }

    if (over.kerning) |kerning| {
        ret.kerning = kerning;
    }

    return ret;
}
