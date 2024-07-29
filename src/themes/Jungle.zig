const dvui = @import("../dvui.zig");

const Color = dvui.Color;
const Font = dvui.Font;
const Theme = dvui.Theme;
const Options = dvui.Options;
const bitstream_vera = dvui.bitstream_vera;

//const accent = Color{ .r = 0x35, .g = 0x84, .b = 0xe4 };
const accent_hsl = Color.HSLuv.fromColor(accent);
const err = Color{ .r = 0xe0, .g = 0x1b, .b = 0x24 };
const err_hsl = Color.HSLuv.fromColor(err);

const dark_fill = Color{ .r = 0x1e, .g = 0x1e, .b = 0x1e };
const dark_fill_hsl = Color.HSLuv.fromColor(dark_fill);
const dark_err = Color{ .r = 0xc0, .g = 0x1c, .b = 0x28 };
const dark_err_hsl = Color.HSLuv.fromColor(dark_err);

const dark_accent_accent = accent_hsl.lighten(12).color();
const dark_accent_fill_hover = accent_hsl.lighten(9).color();
const dark_accent_border = accent_hsl.lighten(17).color();

const dark_err_accent = dark_err_hsl.lighten(14).color();
const dark_err_fill_hover = err_hsl.lighten(9).color();
const dark_err_fill_press = err_hsl.lighten(16).color();
const dark_err_border = err_hsl.lighten(20).color();

const border = Color{ .r = 0x60, .g = 0x82, .b = 0x7d, .a = 0xff }; // DEFAULT_BORDER_COLOR_NORMAL
const fill = Color{ .r = 0x2c, .g = 0x33, .b = 0x34, .a = 0xff }; // DEFAULT_BASE_COLOR_NORMAL
//Color{ .r = 0x82, .g = 0xa2, .b = 0x9f, .a = 0xff },    // DEFAULT_TEXT_COLOR_NORMAL
const border_hover = Color{ .r = 0x5f, .g = 0x9a, .b = 0xa8, .a = 0xff }; // DEFAULT_BORDER_COLOR_FOCUSED
const fill_hover = Color{ .r = 0x33, .g = 0x4e, .b = 0x57, .a = 0xff }; // DEFAULT_BASE_COLOR_FOCUSED
//Color{ .r = 0x6a, .g = 0xa9, .b = 0xb8, .a = 0xff },    // DEFAULT_TEXT_COLOR_FOCUSED
//Color{ .r = 0xa9, .g = 0xcb, .b = 0x8d, .a = 0xff },    // DEFAULT_BORDER_COLOR_PRESSED
const accent = Color{ .r = 0x3b, .g = 0x63, .b = 0x57, .a = 0xff }; // DEFAULT_BASE_COLOR_PRESSED
const text_accent = Color{ .r = 0x97, .g = 0xaf, .b = 0x81, .a = 0xff }; // DEFAULT_TEXT_COLOR_PRESSED
//Color{ .r = 0x5b, .g = 0x64, .b = 0x62, .a = 0xff },    // DEFAULT_BORDER_COLOR_DISABLED
//Color{ .r = 0x2c, .g = 0x33, .b = 0x34, .a = 0xff },    // DEFAULT_BASE_COLOR_DISABLED
//Color{ .r = 0x66, .g = 0x6b, .b = 0x69, .a = 0xff },    // DEFAULT_TEXT_COLOR_DISABLED
//Color{ .r = 0x63, .g = 0x84, .b = 0x65, .a = 0xff },    // DEFAULT_LINE_COLOR
const background = Color{ .r = 0x2b, .g = 0x3a, .b = 0x3a, .a = 0xff }; // DEFAULT_BACKGROUND_COLOR
//Color{ .r = 0x00, .g = 0x00, .b = 0x00, .a = 0x12 },    // DEFAULT_TEXT_LINE_SPACING

pub var jungle = Theme{
    .name = "Jungle",
    .dark = true,

    .font_body = .{ .size = 13, .name = "Vera", .ttf_bytes = bitstream_vera.Vera },
    .font_heading = .{ .size = 13, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_caption = .{ .size = 10, .name = "Vera", .ttf_bytes = bitstream_vera.Vera },
    .font_caption_heading = .{ .size = 10, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_title = .{ .size = 28, .name = "Vera", .ttf_bytes = bitstream_vera.Vera },
    .font_title_1 = .{ .size = 23, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_title_2 = .{ .size = 20, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_title_3 = .{ .size = 17, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_title_4 = .{ .size = 15, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },

    //Color{ .r = 0x60, .g = 0x82, .b = 0x7d, .a = 0xff },    // DEFAULT_BORDER_COLOR_NORMAL
    //Color{ .r = 0x2c, .g = 0x33, .b = 0x34, .a = 0xff },    // DEFAULT_BASE_COLOR_NORMAL
    //Color{ .r = 0x82, .g = 0xa2, .b = 0x9f, .a = 0xff },    // DEFAULT_TEXT_COLOR_NORMAL
    //Color{ .r = 0x5f, .g = 0x9a, .b = 0xa8, .a = 0xff },    // DEFAULT_BORDER_COLOR_FOCUSED
    //Color{ .r = 0x33, .g = 0x4e, .b = 0x57, .a = 0xff },    // DEFAULT_BASE_COLOR_FOCUSED
    //Color{ .r = 0x6a, .g = 0xa9, .b = 0xb8, .a = 0xff },    // DEFAULT_TEXT_COLOR_FOCUSED
    //Color{ .r = 0xa9, .g = 0xcb, .b = 0x8d, .a = 0xff },    // DEFAULT_BORDER_COLOR_PRESSED
    //Color{ .r = 0x3b, .g = 0x63, .b = 0x57, .a = 0xff },    // DEFAULT_BASE_COLOR_PRESSED
    //Color{ .r = 0x97, .g = 0xaf, .b = 0x81, .a = 0xff },    // DEFAULT_TEXT_COLOR_PRESSED
    //Color{ .r = 0x5b, .g = 0x64, .b = 0x62, .a = 0xff },    // DEFAULT_BORDER_COLOR_DISABLED
    //Color{ .r = 0x2c, .g = 0x33, .b = 0x34, .a = 0xff },    // DEFAULT_BASE_COLOR_DISABLED
    //Color{ .r = 0x66, .g = 0x6b, .b = 0x69, .a = 0xff },    // DEFAULT_TEXT_COLOR_DISABLED
    //Color{ .r = 0x00, .g = 0x00, .b = 0x00, .a = 0x0c },    // DEFAULT_TEXT_SIZE
    //Color{ .r = 0x00, .g = 0x00, .b = 0x00, .a = 0x00 },    // DEFAULT_TEXT_SPACING
    //Color{ .r = 0x63, .g = 0x84, .b = 0x65, .a = 0xff },    // DEFAULT_LINE_COLOR
    //Color{ .r = 0x2b, .g = 0x3a, .b = 0x3a, .a = 0xff },    // DEFAULT_BACKGROUND_COLOR
    //Color{ .r = 0x00, .g = 0x00, .b = 0x00, .a = 0x12 },    // DEFAULT_TEXT_LINE_SPACING

    .color_accent = accent,
    .color_err = dark_err,
    .color_text = Color{ .r = 0x82, .g = 0xa2, .b = 0x9f, .a = 0xff }, // DEFAULT_TEXT_COLOR_NORMAL
    .color_text_press = text_accent,
    .color_fill = fill,
    .color_fill_window = background,
    .color_fill_control = fill,
    .color_fill_hover = fill_hover,
    .color_fill_press = accent,
    .color_border = border,

    .style_accent = Options{
        .color_accent = .{ .color = Color{ .r = 0x60, .g = 0x82, .b = 0x7d, .a = 0xff } }, // DEFAULT_BORDER_COLOR_NORMAL
        .color_text = .{ .color = text_accent },
        .color_text_press = .{ .color = Color.white },
        .color_fill = .{ .color = Color{ .r = 0x60, .g = 0x82, .b = 0x7d, .a = 0xff } }, // DEFAULT_BORDER_COLOR_NORMAL
        .color_fill_hover = .{ .color = dark_accent_fill_hover },
        .color_fill_press = .{ .color = dark_accent_accent },
        .color_border = .{ .color = dark_accent_border },
    },

    .style_err = Options{
        .color_accent = .{ .color = Color{ .r = 0x60, .g = 0x82, .b = 0x7d, .a = 0xff } }, // DEFAULT_BORDER_COLOR_NORMAL
        .color_text = .{ .color = Color.white },
        .color_text_press = .{ .color = Color.white },
        .color_fill = .{ .color = dark_err },
        .color_fill_hover = .{ .color = dark_err_fill_hover },
        .color_fill_press = .{ .color = dark_err_fill_press },
        .color_border = .{ .color = dark_err_border },
    },
};
