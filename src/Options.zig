const std = @import("std");
const dvui = @import("dvui.zig");

const Color = dvui.Color;
const Font = dvui.Font;
const Rect = dvui.Rect;
const Size = dvui.Size;
const Theme = dvui.Theme;

const Options = @This();

pub const Expand = enum {
    none,
    horizontal,
    vertical,
    both,

    /// Expand while keeping aspect ratio.
    ratio,

    pub fn isHorizontal(self: Expand) bool {
        return (self == .horizontal or self == .both);
    }

    pub fn isVertical(self: Expand) bool {
        return (self == .vertical or self == .both);
    }
};

pub const Gravity = struct {
    // wraps Options.gravity_x and Options.gravity_y
    x: f32,
    y: f32,
};

pub const FontStyle = enum {
    body,
    heading,
    caption,
    caption_heading,
    title,
    title_1,
    title_2,
    title_3,
    title_4,
};

pub const MaxSize = struct {
    w: f32,
    h: f32,

    pub const zero: MaxSize = .{ .w = 0, .h = 0 };

    pub fn width(w: f32) MaxSize {
        return .{ .w = w, .h = dvui.max_float_safe };
    }

    pub fn height(h: f32) MaxSize {
        return .{ .w = dvui.max_float_safe, .h = h };
    }

    pub fn size(s: Size) MaxSize {
        return .{ .w = s.w, .h = s.h };
    }
};

// used to adjust widget id when @src() is not enough (like in a loop)
id_extra: ?usize = null,

// used to id widgets to programmatically interact with them
tag: ?[]const u8 = null,

// used in debugging to give widgets a name, especially in compound widgets
name: ?[]const u8 = null,
debug: ?bool = null,

// null is normal, meaning parent picks a rect for the child widget.  If
// non-null, child widget is choosing its own place, meaning its not being
// placed normally.  w and h will still be expanded if expand is set.
// Example is ScrollArea, where user code chooses widget placement. If
// non-null, should not call rectFor or minSizeForChild.
rect: ?Rect = null,

// default is .none
expand: ?Expand = null,

// [0, 1] default is 0 (left)
gravity_x: ?f32 = null,

// [0, 1] default is 0 (top)
gravity_y: ?f32 = null,

// used to override the tab order, lower numbers first, null means highest
// possible number, same tab_index goes in install() order, 0 disables
tab_index: ?u16 = null,

// used to override widget and theme defaults
color_accent: ?Color = null,
color_text: ?Color = null,
color_text_press: ?Color = null,
color_fill: ?Color = null,
color_fill_hover: ?Color = null,
color_fill_press: ?Color = null,
color_border: ?Color = null,

// use to override font_style
font: ?Font = null,

// only used for icons/images, rotates around center, radians clockwise
rotation: ?f32 = null,

// For the rest of these fields, if null, each widget uses its defaults

// x left, y top, w right, h bottom
margin: ?Rect = null,
border: ?Rect = null,
padding: ?Rect = null,

// x topleft, y topright, w botright, h botleft
corner_radius: ?Rect = null,

/// Widget min size will be at least this much.
///
/// padding/border/margin will be added to this.
min_size_content: ?Size = null,

/// Widget min size can't exceed this, even if min_size_content is larger.
///
/// Use when a child textLayout or scrollArea is making the parent too big.
///
/// padding/border/margin will be added to this.
max_size_content: ?MaxSize = null,

// whether to fill the background
background: ?bool = null,

// use to pick a font from the theme
font_style: ?FontStyle = null,

// All the colors you can get from a Theme
pub const ColorsFromTheme = enum {
    accent,
    err,
    text,
    text_press,
    fill,
    fill_window,
    fill_control,
    fill_hover,
    fill_press,
    border,
};

// All the colors you can ask Options for
pub const ColorAsk = enum {
    accent,
    text,
    text_press,
    fill,
    fill_hover,
    fill_press,
    border,
};
pub fn colorFromTheme(theme_color: ColorsFromTheme) Color {
    return switch (theme_color) {
        .accent => dvui.themeGet().color_accent,
        .text => dvui.themeGet().color_text,
        .text_press => dvui.themeGet().color_text_press,
        .fill => dvui.themeGet().color_fill,
        .fill_hover => dvui.themeGet().color_fill_hover,
        .fill_press => dvui.themeGet().color_fill_press,
        .border => dvui.themeGet().color_border,
        .err => dvui.themeGet().color_err,
        .fill_window => dvui.themeGet().color_fill_window,
        .fill_control => dvui.themeGet().color_fill_control,
    };
}
pub fn color(self: *const Options, ask: ColorAsk) Color {
    const col = switch (ask) {
        .accent => self.color_accent orelse dvui.themeGet().color_accent,
        .text => self.color_text orelse dvui.themeGet().color_text,
        .text_press => self.color_text_press orelse dvui.themeGet().color_text_press,
        .fill => self.color_fill orelse dvui.themeGet().color_fill,
        .fill_hover => self.color_fill_hover orelse dvui.themeGet().color_fill_hover,
        .fill_press => self.color_fill_press orelse dvui.themeGet().color_fill_press,
        .border => self.color_border orelse dvui.themeGet().color_border,
    };
    return col.transparent(dvui.themeGet().alpha);
}

pub fn fontGet(self: *const Options) Font {
    if (self.font) |ff| {
        return ff;
    }

    return switch (self.font_style orelse .body) {
        .body => dvui.themeGet().font_body,
        .heading => dvui.themeGet().font_heading,
        .caption => dvui.themeGet().font_caption,
        .caption_heading => dvui.themeGet().font_caption_heading,
        .title => dvui.themeGet().font_title,
        .title_1 => dvui.themeGet().font_title_1,
        .title_2 => dvui.themeGet().font_title_2,
        .title_3 => dvui.themeGet().font_title_3,
        .title_4 => dvui.themeGet().font_title_4,
    };
}

pub fn idExtra(self: *const Options) usize {
    return self.id_extra orelse 0;
}

pub fn debugGet(self: *const Options) bool {
    return self.debug orelse false;
}

pub fn expandGet(self: *const Options) Expand {
    return self.expand orelse .none;
}

pub fn gravityGet(self: *const Options) Gravity {
    return .{ .x = self.gravity_x orelse 0.0, .y = self.gravity_y orelse 0.0 };
}

pub fn marginGet(self: *const Options) Rect {
    return self.margin orelse Rect{};
}

pub fn borderGet(self: *const Options) Rect {
    return self.border orelse Rect{};
}

pub fn backgroundGet(self: *const Options) bool {
    return self.background orelse false;
}

pub fn paddingGet(self: *const Options) Rect {
    return self.padding orelse Rect{};
}

pub fn corner_radiusGet(self: *const Options) Rect {
    return self.corner_radius orelse Rect{};
}

pub fn min_sizeGet(self: *const Options) Size {
    return self.padSize(self.min_size_contentGet());
}

pub fn min_size_contentGet(self: *const Options) Size {
    return self.min_size_content orelse Size{};
}

pub fn max_sizeGet(self: *const Options) Size {
    return self.padSize(self.max_size_contentGet());
}

pub fn max_size_contentGet(self: *const Options) Size {
    if (self.max_size_content) |msc| {
        return .{ .w = msc.w, .h = msc.h };
    } else {
        return Size.all(dvui.max_float_safe);
    }
}

pub fn rotationGet(self: *const Options) f32 {
    return self.rotation orelse 0.0;
}

// Used in compound widgets to strip out the styling that should only apply
// to the outermost container widget.  For example, with a button
// (container with label) the container uses:
// - rect
// - min_size_content
// - max_size_content
// - margin
// - border
// - background
// - padding
// - corner_radius
// - expand
// - gravity
// while the label uses:
// - fonts
// - colors
pub fn strip(self: *const Options) Options {
    return Options{
        // reset to defaults of internal widgets
        .id_extra = null,
        .tag = null,
        .name = null,
        .rect = null,
        .min_size_content = null,
        .max_size_content = null,
        .expand = null,
        .gravity_x = null,
        .gravity_y = null,

        // ignore defaults of internal widgets
        .tab_index = null,
        .margin = Rect{},
        .border = Rect{},
        .padding = Rect{},
        .corner_radius = Rect{},
        .background = false,

        // keep the rest
        .color_accent = self.color_accent,
        .color_text = self.color_text,
        .color_text_press = self.color_text_press,
        .color_fill = self.color_fill,
        .color_fill_hover = self.color_fill_hover,
        .color_fill_press = self.color_fill_press,
        .color_border = self.color_border,

        .font = self.font,
        .font_style = self.font_style,

        .rotation = self.rotation,
        .debug = self.debug,
    };
}

pub fn wrapOuter(self: *const Options) Options {
    var ret = self.*;
    ret.tab_index = null;
    ret.border = Rect{};
    ret.padding = Rect{};
    ret.background = false;
    return ret;
}

pub fn wrapInner(self: *const Options) Options {
    return self.strip().override(.{
        .tab_index = self.tab_index,
        .border = self.border,
        .padding = self.padding,
        .corner_radius = self.corner_radius,
        .background = self.background,
        .expand = .both,
    });
}

pub fn override(self: *const Options, over: Options) Options {
    var ret = self.*;
    inline for (@typeInfo(Options).@"struct".fields) |f| {
        if (@field(over, f.name)) |fval| {
            @field(ret, f.name) = fval;
        }
    }
    return ret;
}

pub fn fromAny(comptime opt_tuple: anytype) Options {
    const m = struct {
        fn has_field(T: type, comptime field_name: []const u8) bool {
            comptime {
                for (@typeInfo(T).@"struct".fields) |f| {
                    if (std.mem.eql(u8, f.name, field_name)) return true;
                }
                return false;
            }
        }
    };
    var ret = Options{};
    inline for (@typeInfo(Options).@"struct".fields) |f| {
        if (comptime m.has_field(@TypeOf(opt_tuple), f.name)) {
            const def = comptime @field(opt_tuple, f.name);
            if (comptime @TypeOf(def) == ColorsFromTheme) {
                const col = colorFromTheme(def);
                @field(ret, f.name) = col;
            } else {
                @field(ret, f.name) = def;
            }
        }
    }
    return ret;
}

pub fn min_sizeM(self: *const Options, wide: f32, tall: f32) Options {
    return self.override(.{ .min_size_content = self.fontGet().sizeM(wide, tall) });
}

pub fn sizeM(wide: f32, tall: f32) Size {
    return (Options{}).fontGet().sizeM(wide, tall);
}

pub fn padSize(self: *const Options, s: Size) Size {
    return s.pad(self.paddingGet()).pad(self.borderGet()).pad(self.marginGet());
}

//pub fn format(self: *const Options, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
//    try std.fmt.format(writer, "Options{{ .background = {?}, .color_style = {?} }}", .{ self.background, self.color_style });
//}

test {
    @import("std").testing.refAllDecls(@This());
}
