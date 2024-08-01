const dvui = @import("../dvui.zig");

const Color = dvui.Color;
const Font = dvui.Font;
const Theme = dvui.Theme;
const Options = dvui.Options;

const accent = Color{ .r = 0x63, .g = 0x84, .b = 0x65, .a = 0xff };
const err = Color.white;
const text = Color{ .r = 0x82, .g = 0xa2, .b = 0x9f, .a = 0xff };
const text_press = Color{ .r = 0x97, .g = 0xaf, .b = 0x81, .a = 0xff };
const fill = Color{ .r = 0x2c, .g = 0x33, .b = 0x34, .a = 0xff }; //base color normal
const fill_window = Color{ .r = 0x2b, .g = 0x3a, .b = 0x3a, .a = 0xff }; //default bg color
const fill_control = Color{ .r = 0x2c, .g = 0x33, .b = 0x34, .a = 0xff }; // default_base_color_normal
const fill_hover = Color{ .r = 0x33, .g = 0x4e, .b = 0x57, .a = 0xff }; // default_base_color_focused
const fill_press = Color{ .r = 0x3b, .g = 0x63, .b = 0x57, .a = 0xff }; // DEFAULT_BASE_COLOR_PRESSED
const border = Color{ .r = 0x60, .g = 0x82, .b = 0x7d, .a = 0xff }; // default_border_color_normal

const size = 18;

pub const jungle = Theme{
    .name = "Jungle",
    .dark = true,

    .font_body = .{ .size = size, .name = "Pixelify" },
    .font_heading = .{ .size = size, .name = "Pixelify" },
    .font_caption = .{ .size = size, .name = "Pixelify" },
    .font_caption_heading = .{ .size = size, .name = "Pixelify" },
    .font_title = .{ .size = size * 2, .name = "Pixelify" },
    .font_title_1 = .{ .size = size * 1.8, .name = "Pixelify" },
    .font_title_2 = .{ .size = size * 1.6, .name = "Pixelify" },
    .font_title_3 = .{ .size = size * 1.4, .name = "Pixelify" },
    .font_title_4 = .{ .size = size * 1.2, .name = "Pixelify" },

    .color_accent = accent,
    .color_err = err,
    .color_text = text,
    .color_text_press = text_press,
    .color_fill = fill,
    .color_fill_window = fill_window,
    .color_fill_control = fill_control,
    .color_fill_hover = fill_hover,
    .color_fill_press = fill_press,
    .color_border = border,

    .style_accent = Options{
        .color_accent = .{ .color = Color.alphaAdd(accent, accent) },
        .color_text = .{ .color = Color.alphaAdd(accent, text) },
        .color_text_press = .{ .color = Color.alphaAdd(accent, text_press) },
        .color_fill = .{ .color = Color.alphaAdd(accent, fill) },
        .color_fill_hover = .{ .color = Color.alphaAdd(accent, fill_hover) },
        .color_fill_press = .{ .color = Color.alphaAdd(accent, fill_press) },
        .color_border = .{ .color = Color.alphaAdd(accent, border) },
    },

    .style_err = Options{
        .color_accent = .{ .color = Color.alphaAdd(err, accent) },
        .color_text = .{ .color = Color.alphaAdd(err, text) },
        .color_text_press = .{ .color = Color.alphaAdd(err, text_press) },
        .color_fill = .{ .color = Color.alphaAdd(err, fill) },
        .color_fill_hover = .{ .color = Color.alphaAdd(err, fill_hover) },
        .color_fill_press = .{ .color = Color.alphaAdd(err, fill_press) },
        .color_border = .{ .color = Color.alphaAdd(err, border) },
    },
};
