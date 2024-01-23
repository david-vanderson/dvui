const dvui = @import("../dvui.zig");

const Color = dvui.Color;
const Font = dvui.Font;
const Theme = dvui.Theme;
const Options = dvui.Options;
const bitstream_vera = dvui.bitstream_vera;

const accent = Color{ .r = 0x35, .g = 0x84, .b = 0xe4 };
const err = Color{ .r = 0xe0, .g = 0x1b, .b = 0x24 };

pub var light = Theme{
    .name = "Adwaita",
    .dark = false,

    .font_body = .{ .size = 11, .name = "Vera", .ttf_bytes = bitstream_vera.Vera },
    .font_heading = .{ .size = 11, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_caption = .{ .size = 9, .name = "Vera", .ttf_bytes = bitstream_vera.Vera },
    .font_caption_heading = .{ .size = 9, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_title = .{ .size = 24, .name = "Vera", .ttf_bytes = bitstream_vera.Vera },
    .font_title_1 = .{ .size = 20, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_title_2 = .{ .size = 17, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_title_3 = .{ .size = 15, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_title_4 = .{ .size = 13, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },

    .color_accent = accent,
    .color_err = err,
    .color_text = Color.black,
    .color_text_press = Color.black,
    .color_fill = Color.white,
    .color_fill_window = .{ .r = 0xf0, .g = 0xf0, .b = 0xf0 },
    .color_fill_control = .{ .r = 0xe0, .g = 0xe0, .b = 0xe0 },
    .color_fill_hover = Color.lerp(Color.white, 0.2, Color.black),
    .color_fill_press = Color.lerp(Color.white, 0.3, Color.black),
    .color_border = Color.lerp(Color.white, 0.4, Color.black),

    .style_accent = Options{
        .color_accent = .{ .color = accent.lerp(0.3, Color.black) },
        .color_text = .{ .color = Color.white },
        .color_text_press = .{ .color = Color.white },
        .color_fill = .{ .color = accent },
        .color_fill_hover = .{ .color = Color.lerp(accent, 0.2, Color.black) },
        .color_fill_press = .{ .color = Color.lerp(accent, 0.3, Color.black) },
        .color_border = .{ .color = Color.lerp(accent, 0.4, Color.black) },
    },

    .style_err = Options{
        .color_accent = .{ .color = err.lerp(0.3, Color.black) },
        .color_text = .{ .color = Color.white },
        .color_text_press = .{ .color = Color.white },
        .color_fill = .{ .color = err },
        .color_fill_hover = .{ .color = Color.lerp(err, 0.2, Color.black) },
        .color_fill_press = .{ .color = Color.lerp(err, 0.3, Color.black) },
        .color_border = .{ .color = Color.lerp(err, 0.4, Color.black) },
    },
};

const dark_fill = Color{ .r = 0x1e, .g = 0x1e, .b = 0x1e };
const dark_err = Color{ .r = 0xc0, .g = 0x1c, .b = 0x28 };

pub var dark = Theme{
    .name = "Adwaita Dark",
    .dark = true,

    .font_body = .{ .size = 11, .name = "Vera", .ttf_bytes = bitstream_vera.Vera },
    .font_heading = .{ .size = 11, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_caption = .{ .size = 9, .name = "Vera", .ttf_bytes = bitstream_vera.Vera },
    .font_caption_heading = .{ .size = 9, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_title = .{ .size = 24, .name = "Vera", .ttf_bytes = bitstream_vera.Vera },
    .font_title_1 = .{ .size = 20, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_title_2 = .{ .size = 17, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_title_3 = .{ .size = 15, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_title_4 = .{ .size = 13, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },

    .color_accent = accent,
    .color_err = dark_err,
    .color_text = Color.white,
    .color_text_press = Color.white,
    .color_fill = dark_fill,
    .color_fill_window = .{ .r = 0x2b, .g = 0x2b, .b = 0x2b },
    .color_fill_control = .{ .r = 0x40, .g = 0x40, .b = 0x40 },
    .color_fill_hover = Color.lerp(dark_fill, 0.2, Color.white),
    .color_fill_press = Color.lerp(dark_fill, 0.3, Color.white),
    .color_border = Color.lerp(dark_fill, 0.4, Color.white),

    .style_accent = Options{
        .color_accent = .{ .color = accent.lerp(0.3, Color.white) },
        .color_text = .{ .color = Color.white },
        .color_text_press = .{ .color = Color.white },
        .color_fill = .{ .color = accent },
        .color_fill_hover = .{ .color = Color.lerp(accent, 0.2, Color.white) },
        .color_fill_press = .{ .color = Color.lerp(accent, 0.3, Color.white) },
        .color_border = .{ .color = Color.lerp(accent, 0.4, Color.white) },
    },

    .style_err = Options{
        .color_accent = .{ .color = dark_err.lerp(0.3, Color.white) },
        .color_text = .{ .color = Color.white },
        .color_text_press = .{ .color = Color.white },
        .color_fill = .{ .color = dark_err },
        .color_fill_hover = .{ .color = Color.lerp(err, 0.2, Color.white) },
        .color_fill_press = .{ .color = Color.lerp(err, 0.3, Color.white) },
        .color_border = .{ .color = Color.lerp(err, 0.4, Color.white) },
    },
};
