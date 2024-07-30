const dvui = @import("../dvui.zig");

const Color = dvui.Color;
const Font = dvui.Font;
const Theme = dvui.Theme;
const Options = dvui.Options;
const Hack = Font.TTFBytesId.Hack;
const HackBd = Font.TTFBytesId.HackBd;

//Colors Derived from Dracula theme for Kitty
const border = Color{ .r = 0x62, .g = 0x72, .b = 0xa4, .a = 0xff }; // inactive_border_color
const fill = Color{ .r = 0x44, .g = 0x47, .b = 0x5a, .a = 0xff }; // selection_background
const text = Color{ .r = 0xf8, .g = 0xf8, .b = 0xf2, .a = 0xff }; // foreground
const border_hover = Color{ .r = 0xf8, .g = 0xf8, .b = 0xf2, .a = 0xff }; // active_border_color
const fill_hover = Color{ .r = 0x62, .g = 0x72, .b = 0xa4, .a = 0xff }; // inactive_tab_background
const text_hover = Color{ .r = 0xff, .g = 0xff, .b = 0xff, .a = 0xff }; // selection_foreground
const border_pressed = Color{ .r = 0x28, .g = 0x2a, .b = 0x36, .a = 0xff }; // active_tab_foreground
const accent = Color{ .r = 0xff, .g = 0x79, .b = 0xc6, .a = 0xff };
const fill_pressed = accent;
const text_accent = Color{ .r = 0x8b, .g = 0xe9, .b = 0xfd, .a = 0xff }; // url_color
const border_err = Color{ .r = 0xff, .g = 0x55, .b = 0x55, .a = 0xff }; // color1
const err = Color{ .r = 0xf8, .g = 0xf8, .b = 0xf2, .a = 0xff }; // color7
const background = Color{ .r = 0x28, .g = 0x2a, .b = 0x36, .a = 0xff }; // background

const size = 15;

pub var dracula = Theme{
    .name = "Dracula",
    .dark = true,

    .font_body = .{ .size = size, .name = "hack", .ttf_bytes_id = Hack },
    .font_heading = .{ .size = size, .name = "hack", .ttf_bytes_id = HackBd },
    .font_caption = .{ .size = size * 0.8, .name = "hack", .ttf_bytes_id = Hack },
    .font_caption_heading = .{ .size = size * 0.8, .name = "hack", .ttf_bytes_id = HackBd },
    .font_title = .{ .size = size * 2, .name = "hack", .ttf_bytes_id = Hack },
    .font_title_1 = .{ .size = size * 1.8, .name = "hack", .ttf_bytes_id = HackBd },
    .font_title_2 = .{ .size = size * 1.6, .name = "hack", .ttf_bytes_id = HackBd },
    .font_title_3 = .{ .size = size * 1.4, .name = "hack", .ttf_bytes_id = HackBd },
    .font_title_4 = .{ .size = size * 1.2, .name = "hack", .ttf_bytes_id = HackBd },

    .color_accent = accent,
    .color_err = err,
    .color_text = text,
    .color_text_press = text_accent,
    .color_fill = fill,
    .color_fill_window = background,
    .color_fill_control = fill,
    .color_fill_hover = fill_hover,
    .color_fill_press = accent,
    .color_border = border,

    .style_accent = Options{
        .color_accent = .{ .color = accent },
        .color_text = .{ .color = text_accent },
        .color_text_press = .{ .color = Color.white },
        .color_fill = .{ .color = fill },
        .color_fill_hover = .{ .color = fill_hover },
        .color_fill_press = .{ .color = fill_pressed },
        .color_border = .{ .color = border_pressed },
    },

    .style_err = Options{
        .color_accent = .{ .color = accent },
        .color_text = .{ .color = Color.white },
        .color_text_press = .{ .color = Color.white },
        .color_fill = .{ .color = err },
        .color_fill_hover = .{ .color = fill_hover },
        .color_fill_press = .{ .color = fill_pressed },
        .color_border = .{ .color = border_pressed },
    },
};

//==RAW COLORS==
//
//Color{ .r = 0xf8, .g = 0xf8, .b = 0xf2, .a = 0xff },    // foreground
//Color{ .r = 0x28, .g = 0x2a, .b = 0x36, .a = 0xff },    // background
//Color{ .r = 0xff, .g = 0xff, .b = 0xff, .a = 0xff },    // selection_foreground
//Color{ .r = 0x44, .g = 0x47, .b = 0x5a, .a = 0xff },    // selection_background
//Color{ .r = 0x8b, .g = 0xe9, .b = 0xfd, .a = 0xff },    // url_color
//
//// black
//Color{ .r = 0x21, .g = 0x22, .b = 0x2c, .a = 0xff },    // color0
//Color{ .r = 0x62, .g = 0x72, .b = 0xa4, .a = 0xff },    // color8
//
//// red
//Color{ .r = 0xff, .g = 0x55, .b = 0x55, .a = 0xff },    // color1
//Color{ .r = 0xff, .g = 0x6e, .b = 0x6e, .a = 0xff },    // color9
//
//// green
//Color{ .r = 0x50, .g = 0xfa, .b = 0x7b, .a = 0xff },    // color2
//Color{ .r = 0x69, .g = 0xff, .b = 0x94, .a = 0xff },    // color10
//
//// yellow
//Color{ .r = 0xf1, .g = 0xfa, .b = 0x8c, .a = 0xff },    // color3
//Color{ .r = 0xff, .g = 0xff, .b = 0xa5, .a = 0xff },    // color11
//
//// blue
//Color{ .r = 0xbd, .g = 0x93, .b = 0xf9, .a = 0xff },    // color4
//Color{ .r = 0xd6, .g = 0xac, .b = 0xff, .a = 0xff },    // color12
//
//// magenta
//Color{ .r = 0xff, .g = 0x79, .b = 0xc6, .a = 0xff },    // color5
//Color{ .r = 0xff, .g = 0x92, .b = 0xdf, .a = 0xff },    // color13
//
//// cyan
//Color{ .r = 0x8b, .g = 0xe9, .b = 0xfd, .a = 0xff },    // color6
//Color{ .r = 0xa4, .g = 0xff, .b = 0xff, .a = 0xff },    // color14
//
//// white
//Color{ .r = 0xf8, .g = 0xf8, .b = 0xf2, .a = 0xff },    // color7
//Color{ .r = 0xff, .g = 0xff, .b = 0xff, .a = 0xff },    // color15
//
//// Cursor colors
//Color{ .r = 0xf8, .g = 0xf8, .b = 0xf2, .a = 0xff },    // cursor
//Color{ .r = 0x28, .g = 0x2a, .b = 0x36, .a = 0xff },    // cursor_text_color (same as background)
//
//// Tab bar colors
//Color{ .r = 0x28, .g = 0x2a, .b = 0x36, .a = 0xff },    // active_tab_foreground
//Color{ .r = 0xf8, .g = 0xf8, .b = 0xf2, .a = 0xff },    // active_tab_background
//Color{ .r = 0x28, .g = 0x2a, .b = 0x36, .a = 0xff },    // inactive_tab_foreground
//Color{ .r = 0x62, .g = 0x72, .b = 0xa4, .a = 0xff },    // inactive_tab_background
//
//// Marks
//Color{ .r = 0x28, .g = 0x2a, .b = 0x36, .a = 0xff },    // mark1_foreground
//Color{ .r = 0xff, .g = 0x55, .b = 0x55, .a = 0xff },    // mark1_background
//
//// Splits/Windows
//Color{ .r = 0xf8, .g = 0xf8, .b = 0xf2, .a = 0xff },    // active_border_color
//Color{ .r = 0x62, .g = 0x72, .b = 0xa4, .a = 0xff },    // inactive_border_color
