const dvui = @import("../dvui.zig");

const Color = dvui.Color;
const Font = dvui.Font;
const Theme = dvui.Theme;
const Options = dvui.Options;
const pixel_intv = dvui.pixel_intv;

//638465

//Colors Derived from raygui jungle theme
const border = Color{ .r = 0x60, .g = 0x82, .b = 0x7d, .a = 0xff }; // DEFAULT_BORDER_COLOR_NORMAL
const fill = Color{ .r = 0x2c, .g = 0x33, .b = 0x34, .a = 0xff }; // DEFAULT_BASE_COLOR_NORMAL
const text = Color{ .r = 0x82, .g = 0xa2, .b = 0x9f, .a = 0xff }; // DEFAULT_TEXT_COLOR_NORMAL
const border_hover = border_pressed; //Color{ .r = 0x5f, .g = 0x9a, .b = 0xa8, .a = 0xff }; // DEFAULT_BORDER_COLOR_FOCUSED
const fill_hover = Color{ .r = 0x33, .g = 0x4e, .b = 0x57, .a = 0xff }; // DEFAULT_BASE_COLOR_FOCUSED
const text_hover = Color{ .r = 0x6a, .g = 0xa9, .b = 0xb8, .a = 0xff }; // DEFAULT_TEXT_COLOR_FOCUSED
const border_pressed = Color{ .r = 0xa9, .g = 0xcb, .b = 0x8d, .a = 0xff }; // DEFAULT_BORDER_COLOR_PRESSED
const accent = Color{ .r = 0x3b, .g = 0x63, .b = 0x57, .a = 0xff }; // DEFAULT_BASE_COLOR_PRESSED
const fill_pressed = accent;
const text_accent = Color{ .r = 0x97, .g = 0xaf, .b = 0x81, .a = 0xff }; // DEFAULT_TEXT_COLOR_PRESSED
const border_err = Color{ .r = 0x5b, .g = 0x64, .b = 0x62, .a = 0xff }; // DEFAULT_BORDER_COLOR_DISABLED
const err = Color{ .r = 0x66, .g = 0x6b, .b = 0x69, .a = 0xff }; // DEFAULT_TEXT_COLOR_DISABLED
const background = Color{ .r = 0x2b, .g = 0x3a, .b = 0x3a, .a = 0xff }; // DEFAULT_BACKGROUND_COLOR

const size = 13;

pub var jungle = Theme{
    .name = "Jungle",
    .dark = true,

    .font_body = .{ .size = size, .name = "pixel_intv", .ttf_bytes = pixel_intv },
    .font_heading = .{ .size = size, .name = "pixel_intv", .ttf_bytes = pixel_intv },
    .font_caption = .{ .size = size, .name = "pixel_intv", .ttf_bytes = pixel_intv },
    .font_caption_heading = .{ .size = size, .name = "pixel_intv", .ttf_bytes = pixel_intv },
    .font_title = .{ .size = size * 2, .name = "pixel_intv", .ttf_bytes = pixel_intv },
    .font_title_1 = .{ .size = size * 1.8, .name = "pixel_intv", .ttf_bytes = pixel_intv },
    .font_title_2 = .{ .size = size * 1.6, .name = "pixel_intv", .ttf_bytes = pixel_intv },
    .font_title_3 = .{ .size = size * 1.4, .name = "pixel_intv", .ttf_bytes = pixel_intv },
    .font_title_4 = .{ .size = size * 1.2, .name = "pixel_intv", .ttf_bytes = pixel_intv },

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
