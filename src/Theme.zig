const dvui = @import("dvui.zig");
const std = @import("std");

const Color = dvui.Color;
const Font = dvui.Font;
const Options = dvui.Options;

const Theme = @This();

/// enum used in Options to pick a ColorStyle from Theme
pub const Style = enum {
    content,
    window,
    control,
    highlight,
    err,
};

name: []const u8,

/// widgets can use this if they need to adjust colors
dark: bool,

/// used for focus highlighting
focus: Color,

/// colors for content like textLayout
/// * these are what Style .content use
/// * fill/text usually have the highest contrast
/// * accent used for textLayout selection
/// * also fallbacks for null Colors in ColorStyles
fill: Color,
fill_hover: ?Color = null,
fill_press: ?Color = null,
text: Color,
text_hover: ?Color = null,
text_press: ?Color = null,
border: Color,
accent: Color,

/// colors for normal controls like buttons
control: ColorStyle,

/// colors for windows/boxes that contain controls
window: ColorStyle,

/// colors for highlighting:
/// * menu/dropdown items
/// * checkboxes
/// * radio buttons
highlight: ColorStyle,

/// colors for buttons to perform dangerous actions
err: ColorStyle,

font_body: Font,
font_heading: Font,
font_caption: Font,
font_caption_heading: Font,
font_title: Font,
font_title_1: Font,
font_title_2: Font,
font_title_3: Font,
font_title_4: Font,

/// if true, all strings in `Theme` will be freed in `deinit`
allocated_strings: bool = false,

/// Colors for controls (like buttons), if null fall back to theme colors and
/// automatically adjust fill for hover/press.
pub const ColorStyle = struct {
    fill: ?Color = null,
    fill_hover: ?Color = null,
    fill_press: ?Color = null,
    text: ?Color = null,
    text_hover: ?Color = null,
    text_press: ?Color = null,
    border: ?Color = null,
    accent: ?Color = null,
};

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
pub fn color(self: *const Theme, style: Style, ask: Options.ColorAsk) Color {
    const cs: ColorStyle = switch (style) {
        .content => return sw: switch (ask) {
            .accent => self.accent,
            .border => self.border,
            .fill => self.adjustColorForState(self.fill, ask),
            .fill_hover => self.fill_hover orelse continue :sw .fill,
            .fill_press => self.fill_press orelse continue :sw .fill,
            .text => self.adjustColorForState(self.text, ask),
            .text_hover => self.text_hover orelse continue :sw .text,
            .text_press => self.text_press orelse continue :sw .text,
        },
        .control => self.control,
        .window => self.window,
        .highlight => self.highlight,
        .err => self.err,
    };

    return sw: switch (ask) {
        .accent => cs.accent orelse self.color(.content, ask),
        .border => cs.border orelse self.color(.content, ask),
        .fill => if (cs.fill) |col| self.adjustColorForState(col, ask) else self.color(.content, ask),
        .fill_hover => cs.fill_hover orelse continue :sw .fill,
        .fill_press => cs.fill_press orelse continue :sw .fill,
        .text => if (cs.text) |col| self.adjustColorForState(col, ask) else self.color(.content, ask),
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

    var dd = dvui.DropdownWidget.init(
        src,
        .{ .selected_index = theme_choice, .label = current_theme_name },
        options,
    );
    dd.install();

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
    //pub const gruvbox = QuickTheme.builtin.gruvbox.toTheme(null) catch unreachable;
    //pub const jungle = QuickTheme.builtin.jungle.toTheme(null) catch unreachable;
    //pub const opendyslexic = QuickTheme.builtin.opendyslexic.toTheme(null) catch unreachable;
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
        pub const dracula: QuickTheme = @import("themes/dracula.zon");
        pub const gruvbox: QuickTheme = @import("themes/gruvbox.zon");
        pub const jungle: QuickTheme = @import("themes/jungle.zon");
        pub const opendyslexic: QuickTheme = @import("themes/opendyslexic.zon");
    };

    name: []const u8,

    // fonts
    font_size: f32 = 14,
    font_name_body: []const u8,
    font_name_heading: []const u8,
    font_name_caption: []const u8,
    font_name_title: []const u8,

    // Will fallback to the `accent` color if not defined
    focus: ?[]const u8 = null,

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
    accent: []const u8,

    control: QuickColorStyle,
    window: QuickColorStyle,
    /// If this is null, highlight will be created by averaging the accent color and all the content colors
    highlight: ?QuickColorStyle = null,
    /// If this is null, highlight will be created by averaging `err_base` and all the content colors
    err: ?QuickColorStyle = null,

    const err_base = Color.fromHex("#ffaaaa");

    pub const QuickColorStyle = struct {
        fill: ?[]const u8 = null,
        fill_hover: ?[]const u8 = null,
        fill_press: ?[]const u8 = null,
        text: ?[]const u8 = null,
        text_hover: ?[]const u8 = null,
        text_press: ?[]const u8 = null,
        border: ?[]const u8 = null,
        accent: ?[]const u8 = null,
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
        const accent: Color = try .tryFromHex(self.accent);

        return Theme{
            .name = if (gpa) |alloc| try alloc.dupe(u8, self.name) else self.name,
            .dark = text.brightness() > fill.brightness(),

            .focus = if (self.focus) |hex| try Color.tryFromHex(hex) else accent,

            .text = text,
            .text_hover = text_hover,
            .text_press = text_press,
            .fill = fill,
            .fill_hover = fill_hover,
            .fill_press = fill_press,
            .border = border,
            .accent = accent,

            .control = try parseStyle(self.control),
            .window = try parseStyle(self.window),
            .highlight = if (self.highlight) |s| try parseStyle(s) else .{
                .text = .average(accent, text),
                .text_hover = if (text_hover) |col| .average(accent, col) else null,
                .text_press = if (text_press) |col| .average(accent, col) else null,
                .fill = .average(accent, fill),
                .fill_hover = if (fill_hover) |col| .average(accent, col) else null,
                .fill_press = if (fill_press) |col| .average(accent, col) else null,
                .border = .average(accent, border),
            },
            .err = if (self.err) |s| try parseStyle(s) else .{
                .text = .average(err_base, text),
                .text_hover = if (text_hover) |col| .average(err_base, col) else null,
                .text_press = if (text_press) |col| .average(err_base, col) else null,
                .fill = .average(err_base, fill),
                .fill_hover = if (fill_hover) |col| .average(err_base, col) else null,
                .fill_press = if (fill_press) |col| .average(err_base, col) else null,
                .border = .average(err_base, border),
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

    fn parseStyle(style: QuickColorStyle) Color.FromHexError!ColorStyle {
        return .{
            .fill = if (style.fill) |hex| try .tryFromHex(hex) else null,
            .fill_hover = if (style.fill_hover) |hex| try .tryFromHex(hex) else null,
            .fill_press = if (style.fill_press) |hex| try .tryFromHex(hex) else null,
            .text = if (style.text) |hex| try .tryFromHex(hex) else null,
            .text_hover = if (style.text_hover) |hex| try .tryFromHex(hex) else null,
            .text_press = if (style.text_press) |hex| try .tryFromHex(hex) else null,
            .border = if (style.border) |hex| try .tryFromHex(hex) else null,
            .accent = if (style.accent) |hex| try .tryFromHex(hex) else null,
        };
    }
};

test {
    @import("std").testing.refAllDecls(@This());
}
