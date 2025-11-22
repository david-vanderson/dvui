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

/// reserved for application use
app1: Style = .{},
app2: Style = .{},
app3: Style = .{},

font_body: Font,
font_heading: Font,
font_caption: Font,
font_caption_heading: Font,
font_title: Font,
font_title_1: Font,
font_title_2: Font,
font_title_3: Font,
font_title_4: Font,

/// Caps widget default corner_radius.  Can be overridden at widget call sites.
max_default_corner_radius: ?f32 = null,

/// if true, all strings in `Theme` will be freed in `deinit`
allocated_strings: bool = false,

pub fn deinit(self: *Theme, gpa: std.mem.Allocator) void {
    if (self.allocated_strings) {
        gpa.free(self.name);
    }
    self.* = undefined;
}

pub fn fontSizeAdd(self: *Theme, delta: f32) Theme {
    var ret = self.*;
    ret.font_body.size += delta;
    ret.font_heading.size += delta;
    ret.font_caption.size += delta;
    ret.font_caption_heading.size += delta;
    ret.font_title.size += delta;
    ret.font_title_1.size += delta;
    ret.font_title_2.size += delta;
    ret.font_title_3.size += delta;
    ret.font_title_4.size += delta;

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
    pub const dracula = QuickTheme.builtin.dracula.toTheme(null) catch unreachable;
    pub const gruvbox = QuickTheme.builtin.gruvbox.toTheme(null) catch unreachable;
    pub const jungle = QuickTheme.builtin.jungle.toTheme(null) catch unreachable;
    pub const opendyslexic = QuickTheme.builtin.opendyslexic.toTheme(null) catch unreachable;

    test {
        // Ensures all builting themes are valid
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

pub const QuickTheme = struct {
    pub const builtin = struct {
        pub const adwaita_light: QuickTheme = @import("themes/adwaita_light.zon");
        pub const adwaita_dark: QuickTheme = @import("themes/adwaita_dark.zon");
        pub const dracula: QuickTheme = @import("themes/dracula.zon");
        pub const gruvbox: QuickTheme = @import("themes/gruvbox.zon");
        pub const jungle: QuickTheme = @import("themes/jungle.zon");
        pub const opendyslexic: QuickTheme = @import("themes/opendyslexic.zon");

        test {
            // Ensures all the .zon files are valid `QuickTheme` types
            std.testing.refAllDecls(@This());
        }
    };

    name: []const u8,

    // fonts
    font_size: f32 = 14,
    font_name_body: []const u8,
    font_name_heading: []const u8,
    font_name_caption: []const u8,
    font_name_title: []const u8,

    focus: []const u8,

    // text/foreground color
    text: []const u8,
    text_hover: ?[]const u8 = null,
    // text/foreground color when widget is pressed
    text_press: ?[]const u8 = null,

    // background color
    fill: []const u8,
    fill_hover: ?[]const u8 = null,
    // fill/background color when widget is pressed
    fill_press: ?[]const u8 = null,

    border: []const u8,

    control: QuickColorStyle,
    window: QuickColorStyle,
    highlight: QuickColorStyle,
    /// If this is null, highlight will be created by averaging `red` and all the content colors
    err: ?QuickColorStyle = null,

    pub const QuickColorStyle = struct {
        fill: ?[]const u8 = null,
        fill_hover: ?[]const u8 = null,
        fill_press: ?[]const u8 = null,
        text: ?[]const u8 = null,
        text_hover: ?[]const u8 = null,
        text_press: ?[]const u8 = null,
        border: ?[]const u8 = null,
    };

    /// Parses a json object with the fields of `QuickTheme`,
    /// allocating copies of all the string data
    pub fn fromString(
        arena: std.mem.Allocator,
        string: []const u8,
    ) !std.json.Parsed(QuickTheme) {
        return try std.json.parseFromSlice(
            QuickTheme,
            arena,
            string,
            .{ .allocate = .alloc_always },
        );
    }

    /// If an allocator is provided, all name slices will be duplicated
    /// by that allocator and freed in `Theme.deinit`. Else the names
    /// will be used directly which is good for embedded/static slices.
    pub fn toTheme(self: @This(), gpa: ?std.mem.Allocator) (std.mem.Allocator.Error || Color.FromHexError)!Theme {
        @setEvalBranchQuota(5000); // Needs to handle worst case of all optionals being non-null
        const text: Color = try .tryFromHex(self.text);
        const text_hover: ?Color = if (self.text_hover) |hex| try .tryFromHex(hex) else null;
        const text_press: ?Color = if (self.text_press) |hex| try .tryFromHex(hex) else null;
        const fill: Color = try .tryFromHex(self.fill);
        const fill_hover: ?Color = if (self.fill_hover) |hex| try .tryFromHex(hex) else null;
        const fill_press: ?Color = if (self.fill_press) |hex| try .tryFromHex(hex) else null;
        const border: Color = try .tryFromHex(self.border);
        const focus: Color = try .tryFromHex(self.focus);

        return Theme{
            .name = if (gpa) |alloc| try alloc.dupe(u8, self.name) else self.name,
            .dark = text.brightness() > fill.brightness(),

            .focus = focus,

            .text = text,
            .text_hover = text_hover,
            .text_press = text_press,
            .fill = fill,
            .fill_hover = fill_hover,
            .fill_press = fill_press,
            .border = border,

            .control = try parseStyle(self.control),
            .window = try parseStyle(self.window),
            .highlight = try parseStyle(self.highlight),
            .err = if (self.err) |s| try parseStyle(s) else .{
                .text = .average(.red, text),
                .text_hover = if (text_hover) |col| .average(.red, col) else null,
                .text_press = if (text_press) |col| .average(.red, col) else null,
                .fill = .average(.red, fill),
                .fill_hover = if (fill_hover) |col| .average(.red, col) else null,
                .fill_press = if (fill_press) |col| .average(.red, col) else null,
                .border = .average(.red, border),
            },

            .font_body = .{
                .size = @round(self.font_size),
                .id = .fromName(self.font_name_body),
            },
            .font_heading = .{
                .size = @round(self.font_size),
                .id = .fromName(self.font_name_heading),
            },
            .font_caption = .{
                .size = @round(self.font_size * 0.77),
                .id = .fromName(self.font_name_caption),
            },
            .font_caption_heading = .{
                .size = @round(self.font_size * 0.77),
                .id = .fromName(self.font_name_caption),
            },
            .font_title = .{
                .size = @round(self.font_size * 2.15),
                .id = .fromName(self.font_name_title),
            },
            .font_title_1 = .{
                .size = @round(self.font_size * 1.77),
                .id = .fromName(self.font_name_title),
            },
            .font_title_2 = .{
                .size = @round(self.font_size * 1.54),
                .id = .fromName(self.font_name_title),
            },
            .font_title_3 = .{
                .size = @round(self.font_size * 1.3),
                .id = .fromName(self.font_name_title),
            },
            .font_title_4 = .{
                .size = @round(self.font_size * 1.15),
                .id = .fromName(self.font_name_title),
            },

            .allocated_strings = gpa != null,
        };
    }

    fn parseStyle(style: QuickColorStyle) Color.FromHexError!Style {
        return .{
            .fill = if (style.fill) |hex| try .tryFromHex(hex) else null,
            .fill_hover = if (style.fill_hover) |hex| try .tryFromHex(hex) else null,
            .fill_press = if (style.fill_press) |hex| try .tryFromHex(hex) else null,
            .text = if (style.text) |hex| try .tryFromHex(hex) else null,
            .text_hover = if (style.text_hover) |hex| try .tryFromHex(hex) else null,
            .text_press = if (style.text_press) |hex| try .tryFromHex(hex) else null,
            .border = if (style.border) |hex| try .tryFromHex(hex) else null,
        };
    }
};

test {
    @import("std").testing.refAllDecls(@This());
}
