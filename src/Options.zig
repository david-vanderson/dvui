const std = @import("std");
const dvui = @import("dvui.zig");

const Color = dvui.Color;
const Font = dvui.Font;
const Rect = dvui.Rect;
const Corner = dvui.Corner;
const CornerRect = dvui.CornerRect;
const Size = dvui.Size;
const Theme = dvui.Theme;
const Ninepatch = dvui.Ninepatch;

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

/// Specify focus order within the current TabIndexGroup.
/// * lower numbers first
/// * null means highest possible
/// * same tab_index go in processed order
/// * 0 disables (cannot focus via keyboard navigation)
tab_index: ?u16 = null,

// Used to override the style/theme. `color_fill*`/`color_text*`/`color_border`
// can each be a flat color or a gradient (see `ColorOrGradient`).
color_fill: ?ColorOrGradient = null,
color_fill_hover: ?ColorOrGradient = null,
color_fill_press: ?ColorOrGradient = null,
color_text: ?ColorOrGradient = null,
color_text_hover: ?ColorOrGradient = null,
color_text_press: ?ColorOrGradient = null,
color_border: ?ColorOrGradient = null,

ninepatch_fill: ?*const Ninepatch = null,
ninepatch_hover: ?*const Ninepatch = null,
ninepatch_press: ?*const Ninepatch = null,

// If a color above is null, source it from this style (if null, .content) in the theme.
style: ?Theme.Style.Name = null,

// If not null, source colors from here instead of the global theme.
theme: ?*const Theme = null,

// Use specified font
font: ?Font = null,

// only used for icons/images, rotates around center, radians clockwise
rotation: ?f32 = null,

// For the rest of these fields, if null, each widget uses its defaults

// x left, y top, w right, h bottom
margin: ?Rect = null,
border: ?Rect = null,
padding: ?Rect = null,

corners: ?CornerRect = null,

/// Widget min size will be at least this, unless max_size_content is smaller.
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

/// Render a box shadow in `WidgetData.borderAndBackground`.
box_shadow: ?BoxShadow = null,

const ColorOrGradient = dvui.ColorOrGradient;

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

    /// Size of "M" characters in current theme body font.
    pub fn sizeM(wide: f32, tall: f32) MaxSize {
        return .size(dvui.Font.theme(.body).sizeM(wide, tall));
    }

    pub fn cast(anysize: anytype) MaxSize {
        return .{ .w = anysize.w, .h = anysize.h };
    }
};

pub const BoxShadow = struct {
    /// Color of shadow
    color: Color = .black,

    // if null uses Options.corners
    corners: ?CornerRect = null,

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

/// Get a color (or gradient) from this Options or fallback to theme colors.
/// Hover/press auto-adjustment (see `Theme.adjustColorForState`) only
/// applies when the fallback source is a flat color -- gradients don't get
/// an automatic hover/press adjustment.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn color(self: *const Options, ask: ColorAsk) ColorOrGradient {
    return switch (ask) {
        .border => self.color_border,
        .fill => self.color_fill,
        .fill_hover => self.color_fill_hover orelse if (self.color_fill) |cog| adjustColorOrGradientForState(self, cog, ask) else null,
        .fill_press => self.color_fill_press orelse if (self.color_fill) |cog| adjustColorOrGradientForState(self, cog, ask) else null,
        .text => self.color_text,
        .text_hover => self.color_text_hover orelse if (self.color_text) |cog| adjustColorOrGradientForState(self, cog, ask) else null,
        .text_press => self.color_text_press orelse if (self.color_text) |cog| adjustColorOrGradientForState(self, cog, ask) else null,
    } orelse ColorOrGradient{ .color = self.themeGet().color(self.styleGet(), ask) };
}

fn adjustColorOrGradientForState(self: *const Options, cog: ColorOrGradient, ask: ColorAsk) ColorOrGradient {
    return switch (cog) {
        .color => |c| .{ .color = self.themeGet().adjustColorForState(c, ask) },
        .gradient => cog,
    };
}

/// Kinds of Ninepatch you can ask Options for.
pub const NinepatchAsk = enum {
    fill,
    hover,
    press,
};

pub fn ninepatch(self: *const Options, ask: NinepatchAsk) ?*const Ninepatch {
    const np_opt = switch (ask) {
        .fill => self.ninepatch_fill,
        .hover => self.ninepatch_hover orelse self.ninepatch_fill,
        .press => self.ninepatch_press orelse self.ninepatch_fill,
    };
    if (np_opt) |np| return np;

    return self.themeGet().ninepatch(self.styleGet(), ask);
}

pub fn fontGet(self: *const Options) Font {
    return self.font orelse self.themeGet().font_body;
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

pub fn cornersGet(self: *const Options) CornerRect {
    return self.corners orelse CornerRect{};
}

/// Combines min_size_content and max_size_content, adds margin/border/padding.
pub fn min_sizeGet(self: *const Options) Size {
    return self.padSize(self.min_size_contentGet().min(self.max_size_contentGet()));
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

/// Keeps only the fonts and colors. Intended for stuff like buttons passing
/// down options to internal widgets.
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

        .font = self.font,
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
// - corners
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
        .corners = CornerRect{},
        .background = false,
        .ninepatch_fill = &Ninepatch.none,
        .ninepatch_hover = &Ninepatch.none,
        .ninepatch_press = &Ninepatch.none,

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

        .rotation = self.rotation,
    };
}

pub fn override(self: *const Options, over: Options) Options {
    var ret = self.*;

    inline for (@typeInfo(Options).@"struct".field_names) |f_name| {
        if (@field(over, f_name)) |fval| {
            @field(ret, f_name) = fval;
        }
    }

    return ret;
}

pub fn min_sizeM(self: *const Options, wide: f32, tall: f32) Options {
    return self.override(.{ .min_size_content = self.fontGet().sizeM(wide, tall) });
}

pub fn max_sizeM(self: *const Options, wide: f32, tall: f32) Options {
    return self.override(.{ .max_size_content = .size(self.fontGet().sizeM(wide, tall)) });
}

pub fn padSize(self: *const Options, s: Size) Size {
    return s.pad(self.paddingGet()).pad(self.borderGet()).pad(self.marginGet());
}

/// Everything in these options that changes what the widget renders, in a form
/// that can be serialized.
///
/// A named type, not an inline literal: a literal whose field holds a constant
/// becomes a comptime field, and s2s rejects those.
///
/// `Options` itself cannot be serialized: `data_out` points at a `WidgetData`
/// and `theme` at a whole `Theme`, and s2s walks pointers by content — one
/// would recurse into widget data, the other push embedded font files through
/// the hasher.  So a pointer is replaced by what it stands for: the font by its
/// parameters, a ninepatch by the identity of its image.
pub const HashView = struct {
    min_size_content: Size,
    max_size_content: Size,
    rect: ?Rect,
    border: Rect,
    margin: Rect,
    padding: Rect,
    corners: CornerRect,
    gravity: Gravity,
    expand: Expand,
    rotation: f32,
    background: bool,
    style: Theme.Style.Name,
    font: Font.HashView,
    color_fill: ?ColorOrGradient,
    color_fill_hover: ?ColorOrGradient,
    color_fill_press: ?ColorOrGradient,
    color_text: ?ColorOrGradient,
    color_text_hover: ?ColorOrGradient,
    color_text_press: ?ColorOrGradient,
    color_border: ?ColorOrGradient,
    ninepatch_fill: ?u64,
    ninepatch_hover: ?u64,
    ninepatch_press: ?u64,
    tab_index: ?u16,
    id_extra: usize,
    tag: ?[]const u8,
    name: ?[]const u8,
    role: ?dvui.AccessKit.Role,
    label: ?LabelOpts,
    box_shadow: ?BoxShadow,
};

/// The resolved option values, ready to be serialized.
///
/// Uses the resolved getters (`min_size_contentGet` and friends), so options
/// that render the same way hash the same way whether a field was left null or
/// set to its default.
pub fn hashView(self: *const Options) HashView {
    return .{
        .min_size_content = self.min_size_contentGet(),
        .max_size_content = self.max_size_contentGet(),
        .rect = self.rect,
        .border = self.borderGet(),
        .margin = self.marginGet(),
        .padding = self.paddingGet(),
        .corners = self.cornersGet(),
        .gravity = self.gravityGet(),
        .expand = self.expandGet(),
        .rotation = self.rotationGet(),
        .background = self.backgroundGet(),
        .style = self.styleGet(),
        .font = Font.HashView.of(self.fontGet()),
        .color_fill = self.color_fill,
        .color_fill_hover = self.color_fill_hover,
        .color_fill_press = self.color_fill_press,
        .color_text = self.color_text,
        .color_text_hover = self.color_text_hover,
        .color_text_press = self.color_text_press,
        .color_border = self.color_border,
        .ninepatch_fill = if (self.ninepatch_fill) |np| np.contentHash() else null,
        .ninepatch_hover = if (self.ninepatch_hover) |np| np.contentHash() else null,
        .ninepatch_press = if (self.ninepatch_press) |np| np.contentHash() else null,
        .tab_index = self.tab_index,
        .id_extra = self.idExtra(),
        .tag = self.tag,
        .name = self.name,
        .role = self.role,
        .label = self.label,
        .box_shadow = self.box_shadow,
    };
}

/// Feed everything in these options that changes what the widget renders into
/// `hasher`.
///
/// Only used by the snapshot digest (`dvui.testing.widget_hasher`).
pub fn hashInto(self: *const Options, hasher: *dvui.hash.Hasher) void {
    dvui.hash.serialize(hasher, self.hashView());

    // The theme a widget renders against is part of its appearance, even when
    // it is inherited from the current window instead of overridden here.
    self.themeGet().hashInto(hasher);
}

//pub fn format(self: *const Options, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
//    try std.fmt.format(writer, "Options{{ .background = {?}, .color_style = {?} }}", .{ self.background, self.color_style });
//}

test {
    @import("std").testing.refAllDecls(@This());
}

test "Options.hashInto sees the theme" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const opts: Options = .{};

    // Every field of the view has to hash to the same value twice.  A view that
    // keeps a slice into a temporary (as a font take by value hands out) hashes
    // stack garbage here instead.
    const base = opts.hashView();
    inline for (@typeInfo(Options.HashView).@"struct".field_names) |fname| {
        try std.testing.expectEqual(
            dvui.hash.hashOf(@field(base, fname)),
            dvui.hash.hashOf(@field(base, fname)),
        );
    }

    // Same options, same window: the whole digest must not drift on its own.
    var first = dvui.hash.Hasher.init(0);
    opts.hashInto(&first);
    var second = dvui.hash.Hasher.init(0);
    opts.hashInto(&second);
    const first_final = first.final();
    try std.testing.expectEqual(first_final, second.final());

    // A different theme is a different appearance, so the digest has to move
    // even though the options are untouched.  The theme used to be left out of
    // the digest entirely.
    var theme = dvui.themeGet();
    theme.fill = dvui.Color.red;
    dvui.themeSet(theme);

    var themed = dvui.hash.Hasher.init(0);
    opts.hashInto(&themed);
    try std.testing.expect(first_final != themed.final());
}
