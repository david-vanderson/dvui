const std = @import("std");
const dvui = @import("dvui.zig");

const Color = dvui.Color;
const Font = dvui.Font;
const Rect = dvui.Rect;
const Size = dvui.Size;
const Theme = dvui.Theme;

const Options = @This();

/// Mixed into widget id. Use when @src() is not unique (like in a loop).
id_extra: ?usize = null,

/// String for programmatically interacting with widgets, like in tests.
tag: ?[]const u8 = null,

/// Use to name the kind of widget for debugging.
name: ?[]const u8 = null,

/// Debugging flag to isolate debug commands/output to a specific widget.
debug: ?bool = null,

/// Specific placement within parent.  Null is normal, meaning parent picks a
/// rect for the child widget.
///
/// If non-null, child widget is choosing its own place, meaning its not being
/// placed normally.  w and h will still be expanded if expand is set. Example
/// is the demo Scroll Canvas, where user code chooses widget placement.
///
/// If non-null, should not call rectFor or minSizeForChild.
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
color_accent: ?ColorOrName = null,
color_text: ?ColorOrName = null,
color_text_press: ?ColorOrName = null,
color_fill: ?ColorOrName = null,
color_fill_hover: ?ColorOrName = null,
color_fill_press: ?ColorOrName = null,
color_border: ?ColorOrName = null,

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

/// Render a box shadow in `WidgetData.borderAndBackground`.
box_shadow: ?BoxShadow = null,

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

    pub fn fromDirection(dir: dvui.enums.Direction) Expand {
        return switch (dir) {
            .horizontal => .horizontal,
            .vertical => .vertical,
        };
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

pub const BoxShadow = struct {
    /// Color of shadow
    color: ColorOrName = .fromColor(.black),

    // x topleft, y topright, w botright, h botleft
    // if null uses Options.corner_radius
    corner_radius: ?Rect = null,

    /// Shrink the shadow on all sides (before blur)
    shrink: f32 = 0,

    /// Offset down/right
    offset: dvui.Point = .{ .x = 1, .y = 1 },

    /// Extend the size of the transition to transparent at the edges
    blur: f32 = 2,

    /// Additional alpha multiply factor
    alpha: f32 = 0.5,

    pub fn colorGet(self: *const BoxShadow) Color {
        const col = switch (self.color) {
            .color => |col| col,
            .name => |from_theme| Color.fromTheme(from_theme),
        };

        return col.opacity(dvui.themeGet().alpha);
    }
};

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

// Either specify the color directly or name a color from the Theme
pub const ColorOrName = union(enum) {
    color: Color,
    name: ColorsFromTheme,

    pub const accent = ColorOrName{ .name = .accent };
    pub const err = ColorOrName{ .name = .err };
    pub const text = ColorOrName{ .name = .text };
    pub const text_press = ColorOrName{ .name = .text_press };
    pub const fill = ColorOrName{ .name = .fill };
    pub const fill_window = ColorOrName{ .name = .fill_window };
    pub const fill_control = ColorOrName{ .name = .fill_control };
    pub const fill_hover = ColorOrName{ .name = .fill_hover };
    pub const fill_press = ColorOrName{ .name = .fill_press };
    pub const border = ColorOrName{ .name = .border };

    pub fn fromColor(col: Color) @This() {
        return .{ .color = col };
    }
    pub fn fromHex(hex_color: []const u8) @This() {
        return fromColor(Color.fromHex(hex_color));
    }
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

pub fn color(self: *const Options, ask: ColorAsk) Color {
    const color_or_name: ColorOrName = switch (ask) {
        .accent => self.color_accent orelse .{ .name = .accent },
        .text => self.color_text orelse .{ .name = .text },
        .text_press => self.color_text_press orelse .{ .name = .text_press },
        .fill => self.color_fill orelse .{ .name = .fill },
        .fill_hover => self.color_fill_hover orelse .{ .name = .fill_hover },
        .fill_press => self.color_fill_press orelse .{ .name = .fill_press },
        .border => self.color_border orelse .{ .name = .border },
    };

    const col = switch (color_or_name) {
        // if we have a custom color, use it
        .color => |col| col,
        .name => |from_theme| Color.fromTheme(from_theme),
    };

    return col.opacity(dvui.themeGet().alpha);
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
        .box_shadow = null,

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

pub fn min_sizeM(self: *const Options, wide: f32, tall: f32) Options {
    return self.override(.{ .min_size_content = self.fontGet().sizeM(wide, tall) });
}

pub fn sizeM(wide: f32, tall: f32) Size {
    return (Options{}).fontGet().sizeM(wide, tall);
}

pub fn padSize(self: *const Options, s: Size) Size {
    return s.pad(self.paddingGet()).pad(self.borderGet()).pad(self.marginGet());
}

/// Hashes all the values of the options
///
/// Only useful to check exact equality between two `Options`
pub fn hash(self: *const Options) u64 {
    const asBytes = std.mem.asBytes;
    var hasher = dvui.fnv.init();

    hasher.update(asBytes(&self.min_size_contentGet()));
    hasher.update(asBytes(&self.max_size_contentGet()));
    if (self.rect) |rect| hasher.update(asBytes(&rect));

    hasher.update(asBytes(&self.borderGet()));
    hasher.update(asBytes(&self.marginGet()));
    hasher.update(asBytes(&self.paddingGet()));

    hasher.update(asBytes(&self.corner_radiusGet()));
    hasher.update(asBytes(&self.gravityGet()));
    hasher.update(asBytes(&self.expandGet()));
    hasher.update(asBytes(&self.rotationGet()));
    hasher.update(asBytes(&self.background));

    hasher.update(asBytes(&self.color_accent));
    hasher.update(asBytes(&self.color_text));
    hasher.update(asBytes(&self.color_text_press));
    hasher.update(asBytes(&self.color_fill));
    hasher.update(asBytes(&self.color_fill_hover));
    hasher.update(asBytes(&self.color_fill_press));
    hasher.update(asBytes(&self.color_border));

    hasher.update(asBytes(&self.font_style));
    const font = self.fontGet();
    hasher.update(font.name);
    hasher.update(asBytes(&font.line_height_factor));
    hasher.update(asBytes(&font.size));

    hasher.update(asBytes(&self.tab_index));
    hasher.update(asBytes(&self.id_extra));
    if (self.tag) |tag| hasher.update(tag);
    if (self.name) |name| hasher.update(name);

    return hasher.final();
}

//pub fn format(self: *const Options, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
//    try std.fmt.format(writer, "Options{{ .background = {?}, .color_style = {?} }}", .{ self.background, self.color_style });
//}

test {
    @import("std").testing.refAllDecls(@This());
}
