const dvui = @import("dvui.zig");
const std = @import("std");

const Color = dvui.Color;
const Font = dvui.Font;
const Options = dvui.Options;

const Theme = @This();

/// Colors for controls (like buttons), if null fall back to theme colors and
/// automatically adjust fill for hover/press.
pub const Style = struct {
    /// enum used in Options to pick a Style from Theme
    pub const Name = enum {
        content,
        window,
        control,
        highlight,
        err,
        app1,
        app2,
        app3,
    };

    fill: ?Color = null,
    fill_hover: ?Color = null,
    fill_press: ?Color = null,
    ninepatch_fill: ?dvui.Ninepatch = null,
    ninepatch_hover: ?dvui.Ninepatch = null,
    ninepatch_press: ?dvui.Ninepatch = null,
    text: ?Color = null,
    text_hover: ?Color = null,
    text_press: ?Color = null,
    border: ?Color = null,
};

name: []const u8,

/// widgets can use this if they need to adjust colors
dark: bool,

/// used for focus highlighting
focus: Color,

/// color used to show selected text.  textLayout composites this color partially opaque under selected text.
text_select: ?Color = null,

/// fill for .content Style, fallback for any Style without fill.  Example is background of textLayout and textEntry.
fill: Color,

/// fill when hovered for .content Style.  Example is hovering checkbox.  If null, dvui creates one by adjusting fill (see `adjustColorForState`.
fill_hover: ?Color = null,

/// fill when pressed for .content Style.  Example is pressing checkbox.  If null, dvui creates one by adjusting fill (see `adjustColorForState`.
fill_press: ?Color = null,

/// ninepatch for .content Style, fallback for any Style without fill.
ninepatch_fill: ?dvui.Ninepatch = null,

/// ninepatch when hovered for .content Style, fallback for any Style without fill.
ninepatch_hover: ?dvui.Ninepatch = null,

/// ninepatch when pressed for .content Style, fallback for any Style without fill.
ninepatch_press: ?dvui.Ninepatch = null,

/// text color for .content Style, fallback for any Style without text.  Example is text in a textLayout or textEntry.  Also used as general foreground color like a checkmark or icon color.
text: Color,

/// text when hovered for .content Style.  Currently unused in dvui widgets.  If null, uses text.
text_hover: ?Color = null,

/// text when pressed for .content Style.  Currently unused in dvui widgets (but text_press in .control Style is).  If null, uses text.
text_press: ?Color = null,

/// border for .content Style, fallback for any Style without border.
border: Color,

/// colors for normal controls like buttons
control: Style = .{},

/// colors for windows/boxes that contain controls like scrollArea and floatingWindow
window: Style = .{},

/// colors for highlighting:
/// * menu/dropdown items
/// * checkboxes
/// * radio buttons
highlight: Style = .{},

/// colors for buttons to perform dangerous actions
err: Style = .{},

/// Reserved for application use.  dvui only uses these in examples.
app1: Style = .{},
app2: Style = .{},
app3: Style = .{},

/// Font for body text.
/// Use `Font.withSize`, `Font.withWeight`, etc. for variation.
/// Suggestions:
/// - headings: bold, same size
/// - captions: size 2-3 smaller, smaller line height factor like 1.1
font_body: Font,

/// Usually a bold version of font_body.
/// dvui uses this by default for:
/// * subwindow titles
/// * active tab name
/// * grid headers
/// * expanders
font_heading: Font,

/// Usually a larger version of font_body.
/// dvui uses this by default for:
/// * plot titles
font_title: Font,

/// Font for monospaced body text.  dvui only uses this in examples.
font_mono: Font,

/// Caps widget default corner_radius.  Can be overridden at widget call sites.
max_default_corner_radius: ?f32 = null,

/// if true, all strings in `Theme` will be freed in `deinit`
allocated_strings: bool = false,

/// Font sources here will be loaded on demand by dvui when this theme is used.
embedded_fonts: []const Font.Source = &.{},

pub fn deinit(self: *Theme, gpa: std.mem.Allocator) void {
    if (self.allocated_strings) {
        gpa.free(self.name);
    }
    self.* = undefined;
}

pub fn fontSizeAdd(self: *Theme, delta: f32) Theme {
    var ret = self.*;
    ret.font_body = ret.font_body.withSize(ret.font_body.size + delta);
    ret.font_heading = ret.font_heading.withSize(ret.font_heading.size + delta);
    ret.font_title = ret.font_title.withSize(ret.font_title.size + delta);
    ret.font_mono = ret.font_mono.withSize(ret.font_mono.size + delta);

    return ret;
}

/// Get the resolved color for a style.  If null fallback to theme base.
///
/// If a color with a state (like `fill_hover`) is `null`, then the `fill` color
/// will be used and adjusted by `Theme.adjustColorForState`.
///
pub fn color(self: *const Theme, style_name: Style.Name, ask: Options.ColorAsk) Color {
    const cs: Style = switch (style_name) {
        .content => return sw: switch (ask) {
            .border => self.border,
            .fill => self.adjustColorForState(self.fill, ask),
            .fill_hover => self.fill_hover orelse continue :sw .fill,
            .fill_press => self.fill_press orelse continue :sw .fill,
            .text => self.text,
            .text_hover => self.text_hover orelse self.text,
            .text_press => self.text_press orelse self.text,
        },
        .control => self.control,
        .window => self.window,
        .highlight => self.highlight,
        .err => self.err,
        .app1 => self.app1,
        .app2 => self.app2,
        .app3 => self.app3,
    };

    return sw: switch (ask) {
        .border => cs.border orelse self.color(.content, ask),
        .fill => if (cs.fill) |col| self.adjustColorForState(col, ask) else self.color(.content, ask),
        .fill_hover => cs.fill_hover orelse continue :sw .fill,
        .fill_press => cs.fill_press orelse continue :sw .fill,
        .text => cs.text orelse self.color(.content, ask),
        .text_hover => cs.text_hover orelse continue :sw .text,
        .text_press => cs.text_press orelse continue :sw .text,
    };
}

/// Adjust col (sourced from .fill) for .fill_hover and .fill_press by
/// lightening/darkening (based on the `dark` field).
pub fn adjustColorForState(self: *const Theme, col: Color, ask: Options.ColorAsk) Color {
    return col.lighten(switch (ask) {
        .fill_hover => if (self.dark) 10 else -10,
        .fill_press => if (self.dark) 20 else -20,
        else => return col,
    });
}

pub fn ninepatch(self: *const Theme, style_name: Style.Name, ask: Options.NinepatchAsk) ?*const dvui.Ninepatch {
    const cs: *const Style = switch (style_name) {
        .content => switch (ask) {
            .fill => return if (self.ninepatch_fill) |*np| np else null,
            .hover => return if (self.ninepatch_hover) |*np| np else null,
            .press => return if (self.ninepatch_press) |*np| np else null,
        },
        .control => &self.control,
        .window => &self.window,
        .highlight => &self.highlight,
        .err => &self.err,
        .app1 => &self.app1,
        .app2 => &self.app2,
        .app3 => &self.app3,
    };

    switch (ask) {
        .fill => return if (cs.ninepatch_fill) |*np| np else null,
        .hover => return if (cs.ninepatch_hover) |*np| np else null,
        .press => return if (cs.ninepatch_press) |*np| np else null,
    }
}

/// To pick between the built in themes, pass `&Theme.builtins` as the `themes` argument
///
/// Sets the theme on the current `dvui.Window` upon selection
pub fn picker(src: std.builtin.SourceLocation, themes: []const Theme, opts: Options) bool {
    var picked = false;

    const defaults: Options = .{
        .name = "Theme Picker",
        .min_size_content = .{ .w = 120 },
    };

    const options = defaults.override(opts);
    const current_theme_name = dvui.themeGet().name;

    const theme_choice: ?usize = for (themes, 0..) |val, i| {
        if (std.mem.eql(u8, current_theme_name, val.name)) {
            break i;
        }
    } else null;

    var dd: dvui.DropdownWidget = undefined;
    dd.init(
        src,
        .{ .selected_index = theme_choice, .label = current_theme_name },
        options,
    );

    if (dd.dropped()) {
        for (themes) |theme| {
            if (dd.addChoiceLabel(theme.name)) {
                dvui.themeSet(theme);
                picked = true;
                break;
            }
        }
    }

    dd.deinit();

    return picked;
}

pub const builtin = struct {
    pub const adwaita_light = @import("themes/Adwaita.zig").light;
    pub const adwaita_dark = @import("themes/Adwaita.zig").dark;
    pub const dracula = @import("themes/Dracula.zig").theme;
    pub const gruvbox = @import("themes/Gruvbox.zig").theme;
    pub const jungle = @import("themes/Jungle.zig").theme;
    pub const opendyslexic = @import("themes/OpenDyslexic.zig").theme;
    pub const win98 = @import("themes/win98.zig").light;

    test {
        // Ensures all builtin themes are valid
        std.testing.refAllDecls(@This());
    }
};

/// A comptime array of all the builtin themes sorted alphabetically
pub const builtins = blk: {
    const S = struct {
        fn lessThan(context: void, lhs: Theme, rhs: Theme) bool {
            _ = context;
            return std.mem.lessThan(u8, lhs.name, rhs.name);
        }
    };
    const decls = @typeInfo(builtin).@"struct".decls;
    var array: [decls.len]Theme = undefined;
    for (decls, 0..) |decl, i| {
        array[i] = @field(builtin, decl.name);
    }
    std.mem.sort(Theme, &array, {}, S.lessThan);
    break :blk array;
};

test {
    @import("std").testing.refAllDecls(@This());
}
