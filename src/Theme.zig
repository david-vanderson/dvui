const dvui = @import("dvui.zig");
const std = @import("std");

const Color = dvui.Color;
const Font = dvui.Font;
const Options = dvui.Options;

const Theme = @This();

name: []const u8,

// widgets can use this if they need to adjust colors
dark: bool,

alpha: f32 = 1.0,

// used for focus
color_accent: Color,

color_err: Color,

// text/foreground color
color_text: Color,

// text/foreground color when widget is pressed
color_text_press: Color,

// background color for displaying lots of text
color_fill: Color,

// background color for containers that have other widgets inside
color_fill_window: Color,

// background color for controls like buttons
color_fill_control: Color,

color_fill_hover: Color,
color_fill_press: Color,

color_border: Color,

font_body: Font,
font_heading: Font,
font_caption: Font,
font_caption_heading: Font,
font_title: Font,
font_title_1: Font,
font_title_2: Font,
font_title_3: Font,
font_title_4: Font,

// used for highlighting menu/dropdown items
style_accent: ColorStyles,

// used for a button to perform dangerous actions
style_err: ColorStyles,

// if true, need to free the strings in deinit()
allocated_strings: bool = false,

pub const ColorStyles = struct {
    color_accent: ?Options.ColorOrName = null,
    color_text: ?Options.ColorOrName = null,
    color_text_press: ?Options.ColorOrName = null,
    color_fill: ?Options.ColorOrName = null,
    color_fill_hover: ?Options.ColorOrName = null,
    color_fill_press: ?Options.ColorOrName = null,
    color_border: ?Options.ColorOrName = null,

    pub fn asOptions(self: ColorStyles) Options {
        return .{
            .color_accent = self.color_accent,
            .color_text = self.color_text,
            .color_text_press = self.color_text_press,
            .color_fill = self.color_fill,
            .color_fill_hover = self.color_fill_hover,
            .color_fill_press = self.color_fill_press,
            .color_border = self.color_border,
        };
    }
};

pub fn deinit(self: *Theme, gpa: std.mem.Allocator) void {
    if (self.allocated_strings) {
        gpa.free(self.name);
        gpa.free(self.font_body.name);
        gpa.free(self.font_heading.name);
        gpa.free(self.font_caption.name);
        gpa.free(self.font_caption_heading.name);
        gpa.free(self.font_title.name);
        gpa.free(self.font_title_1.name);
        gpa.free(self.font_title_2.name);
        gpa.free(self.font_title_3.name);
        gpa.free(self.font_title_4.name);
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

/// Gets the accent style `Options`
pub fn accent(self: *const Theme) Options {
    return self.style_accent.asOptions();
}

/// Gets the error style `Options`
pub fn err(self: *const Theme) Options {
    return self.style_err.asOptions();
}

pub fn picker(src: std.builtin.SourceLocation, opts: Options) bool {
    var picked = false;

    const defaults: Options = .{
        .name = "Theme Picker",
        .min_size_content = .{ .w = 120 },
    };

    const options = defaults.override(opts);
    const cw = dvui.currentWindow();

    const theme_choice: usize = blk: {
        for (cw.themes.values(), 0..) |val, i| {
            if (std.mem.eql(u8, dvui.themeGet().name, val.name)) {
                break :blk i;
            }
        }
        break :blk 0;
    };

    var dd = dvui.DropdownWidget.init(
        src,
        .{ .selected_index = theme_choice, .label = dvui.themeGet().name },
        options,
    );
    dd.install();

    if (dd.dropped()) {
        for (cw.themes.values()) |*theme| {
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

    // used for focus
    color_focus: []const u8 = "#638465",

    // text/foreground color
    color_text: []const u8 = "#82a29f",

    // text/foreground color when widget is pressed
    color_text_press: []const u8 = "#971f81",

    // background color for displaying lots of text
    color_fill_text: []const u8 = "#2c3332",

    // background color for containers that have other widgets inside
    color_fill_container: []const u8 = "#2b3a3a",

    // background color for controls like buttons
    color_fill_control: []const u8 = "#2c3334",

    color_fill_hover: []const u8 = "#333e57",
    color_fill_press: []const u8 = "#3b6357",

    color_border: []const u8 = "#60827d",

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
        @setEvalBranchQuota(1500);
        const color_accent = try Color.tryFromHex(self.color_focus);
        const color_err = try Color.tryFromHex("#ffaaaa");
        const color_text = try Color.tryFromHex(self.color_text);
        const color_text_press = try Color.tryFromHex(self.color_text_press);
        const color_fill = try Color.tryFromHex(self.color_fill_text);
        const color_fill_window = try Color.tryFromHex(self.color_fill_container);
        const color_fill_control = try Color.tryFromHex(self.color_fill_control);
        const color_fill_hover = try Color.tryFromHex(self.color_fill_hover);
        const color_fill_press = try Color.tryFromHex(self.color_fill_press);
        const color_border = try Color.tryFromHex(self.color_border);

        return Theme{
            .name = if (gpa) |alloc| try alloc.dupe(u8, self.name) else self.name,
            .dark = color_text.brightness() > color_fill.brightness(),
            .alpha = 1.0,
            .color_accent = color_accent,
            .color_err = color_err,
            .color_text = color_text,
            .color_text_press = color_text_press,
            .color_fill = color_fill,
            .color_fill_window = color_fill_window,
            .color_fill_control = color_fill_control,
            .color_fill_hover = color_fill_hover,
            .color_fill_press = color_fill_press,
            .color_border = color_border,
            .font_body = .{
                .size = @round(self.font_size),
                .name = if (gpa) |alloc| try alloc.dupe(u8, self.font_name_body) else self.font_name_body,
            },
            .font_heading = .{
                .size = @round(self.font_size),
                .name = if (gpa) |alloc| try alloc.dupe(u8, self.font_name_heading) else self.font_name_heading,
            },
            .font_caption = .{
                .size = @round(self.font_size * 0.77),
                .name = if (gpa) |alloc| try alloc.dupe(u8, self.font_name_caption) else self.font_name_caption,
            },
            .font_caption_heading = .{
                .size = @round(self.font_size * 0.77),
                .name = if (gpa) |alloc| try alloc.dupe(u8, self.font_name_caption) else self.font_name_caption,
            },
            .font_title = .{
                .size = @round(self.font_size * 2.15),
                .name = if (gpa) |alloc| try alloc.dupe(u8, self.font_name_title) else self.font_name_title,
            },
            .font_title_1 = .{
                .size = @round(self.font_size * 1.77),
                .name = if (gpa) |alloc| try alloc.dupe(u8, self.font_name_title) else self.font_name_title,
            },
            .font_title_2 = .{
                .size = @round(self.font_size * 1.54),
                .name = if (gpa) |alloc| try alloc.dupe(u8, self.font_name_title) else self.font_name_title,
            },
            .font_title_3 = .{
                .size = @round(self.font_size * 1.3),
                .name = if (gpa) |alloc| try alloc.dupe(u8, self.font_name_title) else self.font_name_title,
            },
            .font_title_4 = .{
                .size = @round(self.font_size * 1.15),
                .name = if (gpa) |alloc| try alloc.dupe(u8, self.font_name_title) else self.font_name_title,
            },
            .style_accent = .{
                .color_accent = .{ .color = Color.average(color_accent, color_accent) },
                .color_text = .{ .color = Color.average(color_accent, color_text) },
                .color_text_press = .{ .color = Color.average(color_accent, color_text_press) },
                .color_fill = .{ .color = Color.average(color_accent, color_fill) },
                .color_fill_hover = .{ .color = Color.average(color_accent, color_fill_hover) },
                .color_fill_press = .{ .color = Color.average(color_accent, color_fill_press) },
                .color_border = .{ .color = Color.average(color_accent, color_border) },
            },
            .style_err = .{
                .color_accent = .{ .color = Color.average(color_accent, color_accent) },
                .color_text = .{ .color = Color.average(color_err, color_text) },
                .color_text_press = .{ .color = Color.average(color_err, color_text_press) },
                .color_fill = .{ .color = Color.average(color_err, color_fill) },
                .color_fill_hover = .{ .color = Color.average(color_err, color_fill_hover) },
                .color_fill_press = .{ .color = Color.average(color_err, color_fill_press) },
                .color_border = .{ .color = Color.average(color_err, color_border) },
            },
            .allocated_strings = gpa != null,
        };
    }
};

test {
    @import("std").testing.refAllDecls(@This());
}
