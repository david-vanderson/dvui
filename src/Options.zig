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

    pub fn horizontal(self: Expand) bool {
        return (self == .horizontal or self == .both);
    }

    pub fn vertical(self: Expand) bool {
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

// used to adjust widget id when @src() is not enough (like in a loop)
id_extra: ?usize = null,

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
color_fill: ?Color = null,
color_border: ?Color = null,
color_hover: ?Color = null,
color_press: ?Color = null,

// use to override font_style
font: ?Font = null,

// only used for icons/images, rotates around center, only rotates drawing, radians counterclockwise
rotation: ?f32 = null,

// For the rest of these fields, if null, each widget uses its defaults

// x left, y top, w right, h bottom
margin: ?Rect = null,
border: ?Rect = null,
padding: ?Rect = null,

// x topleft, y topright, w botright, h botleft
corner_radius: ?Rect = null,

// padding/border/margin will be added to this
min_size_content: ?Size = null,

// whether to fill the background
background: ?bool = null,

// use to pick a font from the theme
font_style: ?FontStyle = null,

// use to pick a color from the theme
color_style: ?Theme.ColorStyle = null,

pub const ColorKind = enum {
    accent,
    text,
    fill,
    border,
    hover,
    press,
};

pub fn color(self: *const Options, kind: ColorKind) Color {
    var ret: ?Color = switch (kind) {
        .accent => self.color_accent,
        .text => self.color_text,
        .fill => self.color_fill,
        .border => self.color_border,
        .hover => self.color_hover,
        .press => self.color_press,
    };

    // if we have a custom color, return it
    if (ret) |r| {
        return r.transparent(dvui.themeGet().alpha);
    }

    // find the colors in our style
    const cs: Theme.StyleColors = switch (self.color_style orelse .content) {
        .content => dvui.themeGet().style_content,
        .accent => dvui.themeGet().style_accent,
        .window => dvui.themeGet().style_window,
        .control => dvui.themeGet().style_control,
        .success => dvui.themeGet().style_success,
        .err => dvui.themeGet().style_err,
    };

    // return color from style or default
    switch (kind) {
        .accent => ret = cs.accent orelse dvui.themeGet().style_content.accent orelse unreachable,
        .text => ret = cs.text orelse dvui.themeGet().style_content.text orelse unreachable,
        .fill => ret = cs.fill orelse dvui.themeGet().style_content.fill orelse unreachable,
        .border => ret = cs.border orelse dvui.themeGet().style_content.border orelse unreachable,
        .hover => ret = cs.hover orelse dvui.themeGet().style_content.hover orelse unreachable,
        .press => ret = cs.press orelse dvui.themeGet().style_content.press orelse unreachable,
    }

    return (ret orelse unreachable).transparent(dvui.themeGet().alpha);
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
    return self.min_size_contentGet().pad(self.paddingGet()).pad(self.borderGet()).pad(self.marginGet());
}

pub fn min_size_contentGet(self: *const Options) Size {
    return self.min_size_content orelse Size{};
}

pub fn rotationGet(self: *const Options) f32 {
    return self.rotation orelse 0.0;
}

// Used in compound widgets to strip out the styling that should only apply
// to the outermost container widget.  For example, with a button
// (container with label) the container uses:
// - rect
// - min_size_content
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
        .name = null,
        .rect = null,
        .min_size_content = null,
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
        .color_fill = self.color_fill,
        .color_border = self.color_border,
        .color_hover = self.color_hover,
        .color_press = self.color_press,
        .font = self.font,
        .color_style = self.color_style,
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

    inline for (@typeInfo(Options).Struct.fields) |f| {
        if (@field(over, f.name)) |fval| {
            @field(ret, f.name) = fval;
        }
    }

    return ret;
}

//pub fn format(self: *const Options, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
//    try std.fmt.format(writer, "Options{{ .background = {?}, .color_style = {?} }}", .{ self.background, self.color_style });
//}
