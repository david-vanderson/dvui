const std = @import("std");
const dvui = @import("dvui.zig");

const Color = dvui.Color;
const Font = dvui.Font;
const Rect = dvui.Rect;
const Size = dvui.Size;
const Theme = dvui.Theme;
const Ninepatch = dvui.Ninepatch.Source;

const Options = @This();

/// Mixed into widget id. Use when @src() is not unique (like in a loop).
id_extra: ?usize = null,

/// String for programmatically interacting with widgets, like in tests.
tag: ?[]const u8 = null,

/// Name for debugging, says what kind of widget ("Button" or "Text Entry").
name: ?[]const u8 = null,

/// Accessibility role (.BUTTON or .TEXT_INPUT), says what kind of widget.
role: ?dvui.AccessKit.Role = null,

/// Accessibility label, either another widget or text.
label: ?LabelOpts = null,

/// Pass a pointer to get a copy of the widget's `data` when `register` was
/// called.  Useful for getting id/rect info out of a higher-level function.
data_out: ?*dvui.WidgetData = null,

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

// Used to override the style/theme.
color_fill: ?Color = null,
color_fill_hover: ?Color = null,
color_fill_press: ?Color = null,
color_text: ?Color = null,
color_text_hover: ?Color = null,
color_text_press: ?Color = null,
color_border: ?Color = null,

ninepatch_fill: ?Ninepatch = null,
ninepatch_hover: ?Ninepatch = null,
ninepatch_press: ?Ninepatch = null,

// If a color above is null, source it from this style (if null, .content) in the theme.
style: ?Theme.Style.Name = null,

// If not null, source colors from here instead of the global theme.
theme: ?*const Theme = null,

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

pub const LabelOpts = union(enum) {
    /// Use the label from a different widget.  This is preferred if there is a
    /// visible widget that labels this one.
    by_id: dvui.Id,

    /// Use this label for a different widget.
    for_id: dvui.Id,

    /// Use the previous or next label widget to label this widget.
    label_widget: enum { prev, next },

    /// Use this text as the label.  Prefer using .by if possible - .text is
    /// for cases where there is no visible label (like an icon or image).
    text: []const u8,
};

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

    pub fn all(v: f32) MaxSize {
        return .{ .w = v, .h = v };
    }
};

pub const BoxShadow = struct {
    /// Color of shadow
    color: Color = .black,

    // x topleft, y topright, w botright, h botleft
    // if null uses Options.corner_radius
    corner_radius: ?Rect = null,

    /// Shrink the shadow on all sides (before fade)
    shrink: f32 = 0,

    /// Offset down/right
    offset: dvui.Point = .{ .x = 1, .y = 1 },

    /// Extend the size of the transition to transparent at the edges
    fade: f32 = 2,

    /// Additional alpha multiply factor
    alpha: f32 = 0.5,
};

/// All the colors you can ask Options for
pub const ColorAsk = enum {
    text,
    text_hover,
    text_press,
    fill,
    fill_hover,
    fill_press,
    border,
};

/// Get a color from this Options or fallback to theme colors.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn color(self: *const Options, ask: ColorAsk) Color {
    return switch (ask) {
        .border => self.color_border,
        .fill => self.color_fill,
        .fill_hover => self.color_fill_hover orelse if (self.color_fill) |col| self.themeGet().adjustColorForState(col, ask) else null,
        .fill_press => self.color_fill_press orelse if (self.color_fill) |col| self.themeGet().adjustColorForState(col, ask) else null,
        .text => self.color_text,
        .text_hover => self.color_text_hover orelse self.color_text,
        .text_press => self.color_text_press orelse self.color_text,
    } orelse self.themeGet().color(self.styleGet(), ask);
}

/// All the colors you can ask Options for
pub const NinepatchAsk = enum {
    ninepatch_fill,
    ninepatch_hover,
    ninepatch_press,
};

pub fn ninepatch(self: *const Options, ask: NinepatchAsk) ?dvui.Ninepatch.Source {
    return switch (ask) {
        .ninepatch_fill => self.ninepatch_fill,
        .ninepatch_hover => self.ninepatch_hover orelse self.ninepatch_fill,
        .ninepatch_press => self.ninepatch_press orelse self.ninepatch_fill,
    } orelse self.themeGet().ninepatch(self.styleGet(), ask);
}

pub fn fontGet(self: *const Options) Font {
    if (self.font) |ff| {
        return ff;
    }

    return switch (self.font_style orelse .body) {
        .body => self.themeGet().font_body,
        .heading => self.themeGet().font_heading,
        .caption => self.themeGet().font_caption,
        .caption_heading => self.themeGet().font_caption_heading,
        .title => self.themeGet().font_title,
        .title_1 => self.themeGet().font_title_1,
        .title_2 => self.themeGet().font_title_2,
        .title_3 => self.themeGet().font_title_3,
        .title_4 => self.themeGet().font_title_4,
    };
}

pub fn idExtra(self: *const Options) usize {
    return self.id_extra orelse 0;
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

pub fn styleGet(self: *const Options) Theme.Style.Name {
    return self.style orelse .content;
}

pub fn themeGet(self: *const Options) *const Theme {
    return self.theme orelse &dvui.currentWindow().theme;
}

/// Keeps only the fonts, colors and style
pub fn styleOnly(self: *const Options) Options {
    return .{
        .style = self.style,
        .theme = self.theme,

        .color_fill = self.color_fill,
        .color_fill_hover = self.color_fill_hover,
        .color_fill_press = self.color_fill_press,
        .color_text = self.color_text,
        .color_text_hover = self.color_text_hover,
        .color_text_press = self.color_text_press,
        .color_border = self.color_border,

        .ninepatch_fill = self.ninepatch_fill,
        .ninepatch_hover = self.ninepatch_hover,
        .ninepatch_press = self.ninepatch_press,

        .font = self.font,
        .font_style = self.font_style,
    };
}

// Used in compound widgets to strip out the styling that should only apply to
// the outermost container widget.  Also zero out
// margin/border/padding/background because those are usually for freestanding
// widgets.
//
// For example, with a button
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
// - and we don't want the normal label margin/padding
pub fn strip(self: *const Options) Options {
    return Options{
        // reset to defaults of internal widgets
        .id_extra = null,
        .tag = null,
        .name = null,
        .data_out = null,
        .rect = null,
        .min_size_content = null,
        .max_size_content = null,
        .expand = null,
        .gravity_x = null,
        .gravity_y = null,
        .tab_index = null,
        .box_shadow = null,
        .role = null,
        .label = null,

        // ignore defaults of internal widgets
        .margin = Rect{},
        .border = Rect{},
        .padding = Rect{},
        .corner_radius = Rect{},
        .background = false,

        // keep the rest
        .style = self.style,
        .theme = self.theme,
        .color_fill = self.color_fill,
        .color_fill_hover = self.color_fill_hover,
        .color_fill_press = self.color_fill_press,
        .color_text = self.color_text,
        .color_text_hover = self.color_text_hover,
        .color_text_press = self.color_text_press,
        .color_border = self.color_border,

        .font = self.font,
        .font_style = self.font_style,

        .rotation = self.rotation,
    };
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

pub fn themeOverride(self: *const Options) Options {
    var ret = self.*;
    if (ret.themeGet().max_default_corner_radius) |mdcr| {
        if (ret.corner_radius != null) {
            ret.corner_radius.?.x = @min(ret.corner_radius.?.x, mdcr);
            ret.corner_radius.?.y = @min(ret.corner_radius.?.y, mdcr);
            ret.corner_radius.?.w = @min(ret.corner_radius.?.w, mdcr);
            ret.corner_radius.?.h = @min(ret.corner_radius.?.h, mdcr);
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
    hasher.update(asBytes(&self.backgroundGet()));

    hasher.update(asBytes(&self.styleGet()));
    // FIXME: Should hash the theme fields here in a consistent way
    // hasher.update(asBytes(self.themeGet()));

    if (self.color_fill) |col| hasher.update(asBytes(&col));
    if (self.color_fill_hover) |col| hasher.update(asBytes(&col));
    if (self.color_fill_press) |col| hasher.update(asBytes(&col));
    if (self.color_text) |col| hasher.update(asBytes(&col));
    if (self.color_text_hover) |col| hasher.update(asBytes(&col));
    if (self.color_text_press) |col| hasher.update(asBytes(&col));
    if (self.color_border) |col| hasher.update(asBytes(&col));

    const fontStyle: FontStyle = self.font_style orelse .body;
    hasher.update(asBytes(&fontStyle));
    const font = self.fontGet();
    hasher.update(asBytes(&font.id));
    hasher.update(asBytes(&font.line_height_factor));
    hasher.update(asBytes(&font.size));

    if (self.tab_index) |ti| hasher.update(asBytes(&ti));
    hasher.update(asBytes(&self.idExtra()));
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
