const std = @import("std");

const dvui = @import("dvui.zig");

const Rect = dvui.Rect;
const Size = dvui.Size;

// Actually doing this made me realize that `Style`
// might not be the best name for it.
// Perhaps `FontOptions` or something among those lines?
const FontStyle = @This();

families: []const []const u8,
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
decorations: Decorations,
// Synthesis should probably be a list as well...
// You might want to allow style and caps synthesis for example
synthesis: Synthesis = .auto,
kerning: Kerning = .auto,

pub const Decorations = struct {
    underline: ?Definition,
    overline: ?Definition,
    /// Also known as `strike_through`
    line_through: ?Definition,

    pub const Definition = struct {
        /// `null` means inherit text color
        color: ?dvui.Color = null,
        style: Decorations.Style = .solid,
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

pub fn withFamilies(self: FontStyle, families: []const []const u8) FontStyle {
    var r: FontStyle = self;
    r.families = families;
    return r;
}

pub fn withSize(self: FontStyle, size: f32) FontStyle {
    var r: FontStyle = self;
    r.size = size;
    return r;
}

pub fn larger(self: FontStyle, ds: f32) FontStyle {
    var r: FontStyle = self;
    r.size += ds;
    return r;
}

pub fn withScale(self: FontStyle, scale: ?dvui.Point) FontStyle {
    var r: FontStyle = self;
    r.scale = scale;
    return r;
}

pub fn withFill(self: FontStyle, fill: dvui.Color) FontStyle {
    var r: FontStyle = self;
    r.fill = fill;
    return r;
}

pub fn withHover(self: FontStyle, hover: ?dvui.Color) FontStyle {
    var r: FontStyle = self;
    r.hover = hover;
    return r;
}

pub fn withPress(self: FontStyle, press: ?dvui.Color) FontStyle {
    var r: FontStyle = self;
    r.press = press;
    return r;
}

pub fn withSelect(self: FontStyle, select: ?dvui.Color) FontStyle {
    var r: FontStyle = self;
    r.select = select;
    return r;
}

pub fn withOutline(self: FontStyle, outline: ?Outline) FontStyle {
    var r: FontStyle = self;
    r.outline = outline;
    return r;
}

pub fn withShadow(self: FontStyle, shadow: ?Shadow) FontStyle {
    var r: FontStyle = self;
    r.shadow = shadow;
    return r;
}

pub fn withSpacing(self: FontStyle, spacing: f32) FontStyle {
    var r: FontStyle = self;
    r.spacing = spacing;
    return r;
}

pub fn withStyle(self: FontStyle, style: Style) FontStyle {
    var r: FontStyle = self;
    r.style = style;
    return r;
}

pub fn withWeight(self: FontStyle, weight: Weight) FontStyle {
    var r: FontStyle = self;
    r.weight = weight;
    return r;
}

pub fn withWidth(self: FontStyle, width: Width) FontStyle {
    var r: FontStyle = self;
    r.width = width;
    return r;
}

pub fn withLineHeight(self: FontStyle, factor: f32) FontStyle {
    var r: FontStyle = self;
    r.line_height_factor = factor;
    return r;
}

pub fn withKerning(self: FontStyle, kerning: Kerning) FontStyle {
    var r: FontStyle = self;
    r.kerning = kerning;
    return r;
}

pub fn withSynthesis(self: FontStyle, synthesis: Synthesis) FontStyle {
    var r: FontStyle = self;
    r.synthesis = synthesis;
    return r;
}

pub fn withDecorations(self: FontStyle, decorations: Decorations) FontStyle {
    var r: FontStyle = self;
    r.decorations = decorations;
    return r;
}

pub fn withUnderline(self: FontStyle, underline: ?Decorations.Definition) FontStyle {
    var r: FontStyle = self;
    r.decorations.underline = underline;
    return r;
}

pub fn withOverline(self: FontStyle, overline: ?Decorations.Definition) FontStyle {
    var r: FontStyle = self;
    r.decorations.overline = overline;
    return r;
}

pub fn withLineThrough(self: FontStyle, line_through: ?Decorations.Definition) FontStyle {
    var r: FontStyle = self;
    r.decorations.line_through = line_through;
    return r;
}

// This needs a better name
// pub const Options = struct {
//     size: ?Apply = null,
//     fill: ?Color = null,
//     style: ?Style = null,
//     weight: ?Weight = null,
//     width: ?Width = null,
//     line_height_factor: ?Apply = null,
//     // decorations: ?[]Decoration = null,
//     synthesis: ?Synthesis = null,
//     kerning: ?Kerning = null,

//     pub const Apply = union(enum) {
//         value: f32,
//         larger: f32,
//     };

//     pub const Color = union(enum) {
//         value: ?dvui.Color,
//         darker: void,
//         lighter: void,
//     };
// };

// This has a bit of manual work but it aids in providing some custom apis
// that do not affect internals, only user facing code.
// pub fn override(self: FontStyle, over: Options) FontStyle {
//     var ret = self;

//     if (over.size) |size| {
//         switch (size) {
//             .value => |val| ret.size = val,
//             .larger => |val| ret.size += val,
//         }
//     }

//     if (over.fill) |fill| {
//         switch (fill) {
//             .value => |val| {
//                 if (val) |color| ret.fill = color;
//             },
//             .darker => @panic("TODO"),
//             .lighter => @panic("TODO"),
//         }
//     }

//     if (over.style) |style| {
//         ret.style = style;
//     }

//     if (over.weight) |weight| {
//         ret.weight = weight;
//     }

//     if (over.width) |width| {
//         ret.width = width;
//     }

//     if (over.line_height_factor) |line_height_factor| {
//         switch (line_height_factor) {
//             .value => |val| ret.line_height_factor = val,
//             .larger => |val| {
//                 if (ret.line_height_factor != null)
//                     ret.line_height_factor.? += val
//                 else
//                     ret.line_height_factor = val;
//             },
//         }
//     }

//     // What would be the best way to merge decorations?
//     // Maybe they should be changed to a different api?

//     // if (over.decorations) |_| {}

//     if (over.synthesis) |synthesis| {
//         ret.synthesis = synthesis;
//     }

//     if (over.kerning) |kerning| {
//         ret.kerning = kerning;
//     }

//     return ret;
// }

// TODO: Fetch the font and get the line height
pub fn getLineHeightFactor(self: FontStyle, family: []const u8) f32 {
    _ = self;
    _ = family;
    return 1.2;
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

pub const FontSource = struct {
    style: Style = .normal,
    weight: Weight = .regular,
    line_height_factor: f32 = 1.2,
};

pub const Database = struct {
    backing: std.HashMapUnmanaged(
        Key,
        Value,
        Context,
        std.hash_map.default_max_load_percentage,
    ) = .empty,

    pub const Key = u64;
    pub const Value = union(enum) {
        variable: Entry,
        // TODO: This is probably not the way...
        family: *Family,

        const Entry = struct {
            line_height_factor: f32,
            bytes: []const u8,
        };

        const Family = std.HashMapUnmanaged(
            Key,
            Entry,
            Context,
            std.hash_map.default_max_load_percentage,
        );
    };

    const Context = struct {
        pub fn hash(ctx: Context, key: Key) u64 {
            _ = ctx;
            return key;
        }

        pub fn eql(ctx: Context, a: Key, b: Key) bool {
            _ = ctx;
            return a == b;
        }
    };

    const LookupKey = packed struct(u64) {
        style: Style,
        weight: Weight,
        _: u22 = 0,
    };

    fn hashFamily(family: []const u8) u64 {
        return std.hash.XxHash3.hash(0, family);
    }

    pub fn insert(
        self: *Database,
        gpa: std.mem.Allocator,
        family: []const u8,
        info: FontSource,
        bytes: []const u8,
        variable: bool,
    ) !void {
        const hash = hashFamily(family);

        if (variable) return self.backing.put(gpa, hash, .{
            .variable = .{
                .line_height_factor = info.line_height_factor,
                .bytes = bytes,
            },
        });

        var family_map: *Value.Family = blk: {
            if (self.backing.get(hash)) |val| {
                if (val != .family)
                    return dvui.log.err("Failed to insert font: '{s} {t} {t}'", .{ family, info.weight, info.style });

                break :blk val.family;
            }

            const map = try gpa.create(Value.Family);
            map.* = .empty;
            break :blk map;
        };

        return family_map.put(
            gpa,
            @bitCast(LookupKey{ .style = info.style, .weight = info.weight }),
            .{ .line_height_factor = info.line_height_factor, .bytes = bytes },
        );
    }

    pub const GetReturnType = union(enum) {
        variable: Value.Entry,
        family: Value.Entry,
    };

    pub fn get(
        self: *Database,
        family: []const u8,
        lookup: LookupKey,
    ) ?GetReturnType {
        const hash = hashFamily(family);
        const entry = self.backing.get(hash) orelse return null;

        switch (entry) {
            .variable => |variable| return .{ .variable = variable },
            .family => |family_map| {
                const result = family_map.get(@bitCast(lookup)) orelse return null;
                return .{ .family = result };
            },
        }
    }
};

pub const Cache = struct {
    // TODO: `Font.Cache.Entry` stores `name` for whatever reason, so we need a new type that doesn't
    // this is all just poc
    backing: dvui.TrackingAutoHashMap(u64, dvui.Font.Cache.Entry, .get_and_put, void) = .empty,
    database: *Database = &.{},

    fn createCacheHash(family: []const u8, lookup: Database.LookupKey) u64 {
        var h = std.hash.XxHash3.init(0);
        h.update(family);
        h.update(std.mem.asBytes(&lookup));
        return h.final();
    }

    pub fn getOrCreate(
        self: *Cache,
        gpa: std.mem.Allocator,
        family: []const u8,
        lookup: Database.LookupKey,
    ) !*dvui.Font.Cache.Entry {
        const entry = try self.backing.getOrPut(gpa, family, lookup);
        if (entry.found_existing) return entry.value_ptr;

        // TODO: Global fallbacks need to be implemented differently from status quo
        const source = self.database.get(family, lookup) orelse return error.NoSource;

        // TODO: Entry needs to be heavily modified looking at this...
        entry.value_ptr.* = dvui.Font.CacheEntry.init(gpa, source.bytes, .{}) catch |err| {
            dvui.log.err("Font {s} init got {any}, using fallback", .{ family, err });
            self.backing.map.removeByPtr(entry.key_ptr);
            return error.NoSource;
        };
        return entry.value_ptr;
    }
};
