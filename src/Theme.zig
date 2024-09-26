const dvui = @import("dvui.zig");
const std = @import("std");

const Color = dvui.Color;
const Font = dvui.Font;
const Options = dvui.Options;

/// List of theme pointers
pub const ptrs = [_]*dvui.Theme{
    &AdwaitaLight,
    &AdwaitaDark,
    &AdwaitaOpenDyslexicLight,
    &AdwaitaOpenDyslexicDark,
    &Jungle,
    &Dracula,
    &Flow,
    &Gruvbox,
};

//builtin themes
pub var AdwaitaLight = @import("themes/Adwaita.zig").light;
pub var AdwaitaDark = @import("themes/Adwaita.zig").dark;
pub var AdwaitaOpenDyslexicLight = @import("themes/AdwaitaOpenDyslexic.zig").light;
pub var AdwaitaOpenDyslexicDark = @import("themes/AdwaitaOpenDyslexic.zig").dark;
pub var Jungle = @import("themes/Jungle.zig").jungle;
pub var Dracula = @import("themes/Dracula.zig").dracula;
pub var Flow = @import("themes/Flow.zig").flow;
pub var Gruvbox = @import("themes/Gruvbox.zig").gruvbox;

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
style_accent: Options,

// used for a button to perform dangerous actions
style_err: Options,

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

pub const QuickTheme = struct {
    name: []const u8 = "Default",

    // fonts
    font_size: f32 = 14,
    font_name_body: []const u8 = "Vera",
    font_name_heading: []const u8 = "Vera",
    font_name_caption: []const u8 = "Vera",
    font_name_title: []const u8 = "VeraBd",

    // used for focus
    color_focus: []const u8 = "#aa2244",

    // text/foreground color
    color_text: []const u8 = "#111111",

    // text/foreground color when widget is pressed
    color_text_press: []const u8 = "#112233",

    // background color for displaying lots of text
    color_fill_text: []const u8 = "#ddedde",

    // background color for containers that have other widgets inside
    color_fill_container: []const u8 = "#dddddd",

    // background color for controls like buttons
    color_fill_control: []const u8 = "#ddeede",

    color_fill_hover: []const u8 = "#ddeede",
    color_fill_press: []const u8 = "#223344",

    color_border: []const u8 = "#220110",

    pub fn fromString(
        allocator: std.mem.Allocator,
        string: []const u8,
    ) !std.json.Parsed(QuickTheme) {
        return try std.json.parseFromSlice(
            QuickTheme,
            allocator,
            string,
            .{ .allocate = .alloc_always },
        );
    }

    pub fn toTheme(self: @This(), allocator: std.mem.Allocator) !Theme {
        const color_accent = try Color.fromHex(self.color_focus);
        const color_err = try Color.fromHex("#ffaaaa");
        const color_text = try Color.fromHex(self.color_text);
        const color_text_press = try Color.fromHex(self.color_text_press);
        const color_fill = try Color.fromHex(self.color_fill_text);
        const color_fill_window = try Color.fromHex(self.color_fill_container);
        const color_fill_control = try Color.fromHex(self.color_fill_control);
        const color_fill_hover = try Color.fromHex(self.color_fill_hover);
        const color_fill_press = try Color.fromHex(self.color_fill_press);
        const color_border = try Color.fromHex(self.color_border);

        return Theme{
            .name = try allocator.dupeZ(u8, self.name),
            .dark = true,
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
            .font_body = .{ .size = self.font_size, .name = self.font_name_body },
            .font_heading = .{ .size = self.font_size, .name = self.font_name_heading },
            .font_caption = .{ .size = self.font_size * 0.7, .name = self.font_name_caption },
            .font_caption_heading = .{ .size = self.font_size * 0.7, .name = self.font_name_caption },
            .font_title = .{ .size = self.font_size * 2, .name = self.font_name_title },
            .font_title_1 = .{ .size = self.font_size * 1.8, .name = self.font_name_title },
            .font_title_2 = .{ .size = self.font_size * 1.6, .name = self.font_name_title },
            .font_title_3 = .{ .size = self.font_size * 1.4, .name = self.font_name_title },
            .font_title_4 = .{ .size = self.font_size * 1.2, .name = self.font_name_title },
            .style_accent = .{
                .color_accent = .{ .color = Color.alphaAdd(color_accent, color_accent) },
                .color_text = .{ .color = Color.alphaAdd(color_accent, color_text) },
                .color_text_press = .{ .color = Color.alphaAdd(color_accent, color_text_press) },
                .color_fill = .{ .color = Color.alphaAdd(color_accent, color_fill) },
                .color_fill_hover = .{ .color = Color.alphaAdd(color_accent, color_fill_hover) },
                .color_fill_press = .{ .color = Color.alphaAdd(color_accent, color_fill_press) },
                .color_border = .{ .color = Color.alphaAdd(color_accent, color_border) },
            },
            .style_err = .{
                .color_accent = .{ .color = Color.alphaAdd(color_accent, color_accent) },
                .color_text = .{ .color = Color.alphaAdd(color_err, color_text) },
                .color_text_press = .{ .color = Color.alphaAdd(color_err, color_text_press) },
                .color_fill = .{ .color = Color.alphaAdd(color_err, color_fill) },
                .color_fill_hover = .{ .color = Color.alphaAdd(color_err, color_fill_hover) },
                .color_fill_press = .{ .color = Color.alphaAdd(color_err, color_fill_press) },
                .color_border = .{ .color = Color.alphaAdd(color_err, color_border) },
            },
        };
    }
};
