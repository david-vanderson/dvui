const dvui = @import("../dvui.zig");

const Color = dvui.Color;
const Font = dvui.Font;
const Theme = dvui.Theme;
const bitstream_vera = dvui.bitstream_vera;

const accent = Color{ .r = 0x35, .g = 0x84, .b = 0xe4 };
const success = Color{ .r = 0x2e, .g = 0xc2, .b = 0x7e };
const err = Color{ .r = 0xe0, .g = 0x1b, .b = 0x24 };

pub var light = Theme{
    .name = "Adwaita",
    .dark = false,

    .font_body = Font{ .size = 11, .name = "Vera", .ttf_bytes = bitstream_vera.Vera },
    .font_heading = Font{ .size = 11, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_caption = Font{ .size = 9, .name = "Vera", .ttf_bytes = bitstream_vera.Vera },
    .font_caption_heading = Font{ .size = 9, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_title = Font{ .size = 24, .name = "Vera", .ttf_bytes = bitstream_vera.Vera },
    .font_title_1 = Font{ .size = 20, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_title_2 = Font{ .size = 17, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_title_3 = Font{ .size = 15, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_title_4 = Font{ .size = 13, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },

    .style_content = .{
        .accent = accent,
        .text = Color.black,
        .fill = Color.white,
        .border = Color.lerp(Color.white, 0.4, Color.black),
        .hover = Color.lerp(Color.white, 0.2, Color.black),
        .press = Color.lerp(Color.white, 0.3, Color.black),
        .press_text = Color.black,
    },

    .style_control = .{ .fill = Color{ .r = 0xe0, .g = 0xe0, .b = 0xe0 } },
    .style_window = .{ .fill = Color{ .r = 0xf0, .g = 0xf0, .b = 0xf0 } },

    .style_accent = .{
        .accent = accent.darken(0.3),
        .fill = accent,
        .text = Color.white,
        .border = Color.lerp(accent, 0.4, Color.black),
        .hover = Color.lerp(accent, 0.2, Color.black),
        .press = Color.lerp(accent, 0.3, Color.black),
        .press_text = Color.black,
    },
    .style_success = .{
        .accent = success.darken(0.3),
        .fill = success,
        .text = Color.white,
        .border = Color.lerp(success, 0.4, Color.black),
        .hover = Color.lerp(success, 0.2, Color.black),
        .press = Color.lerp(success, 0.3, Color.black),
        .press_text = Color.black,
    },
    .style_err = .{
        .accent = err.darken(0.3),
        .fill = err,
        .text = Color.white,
        .border = Color.lerp(err, 0.4, Color.black),
        .hover = Color.lerp(err, 0.2, Color.black),
        .press = Color.lerp(err, 0.3, Color.black),
        .press_text = Color.black,
    },
};

const dark_fill = Color{ .r = 0x1e, .g = 0x1e, .b = 0x1e };
const dark_success = Color{ .r = 0x26, .g = 0xa2, .b = 0x69 };
const dark_err = Color{ .r = 0xc0, .g = 0x1c, .b = 0x28 };

pub var dark = Theme{
    .name = "Adwaita Dark",
    .dark = true,

    .font_body = Font{ .size = 11, .name = "Vera", .ttf_bytes = bitstream_vera.Vera },
    .font_heading = Font{ .size = 11, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_caption = Font{ .size = 9, .name = "Vera", .ttf_bytes = bitstream_vera.Vera },
    .font_caption_heading = Font{ .size = 9, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_title = Font{ .size = 24, .name = "Vera", .ttf_bytes = bitstream_vera.Vera },
    .font_title_1 = Font{ .size = 20, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_title_2 = Font{ .size = 17, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_title_3 = Font{ .size = 15, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },
    .font_title_4 = Font{ .size = 13, .name = "VeraBd", .ttf_bytes = bitstream_vera.VeraBd },

    .style_content = .{
        .accent = accent,
        .text = Color.white,
        .fill = dark_fill,
        .border = Color.lerp(dark_fill, 0.4, Color.white),
        .hover = Color.lerp(dark_fill, 0.2, Color.white),
        .press = Color.lerp(dark_fill, 0.3, Color.white),
        .press_text = Color.white,
    },

    .style_control = .{ .fill = Color{ .r = 0x40, .g = 0x40, .b = 0x40 } },
    .style_window = .{ .fill = Color{ .r = 0x2b, .g = 0x2b, .b = 0x2b } },

    .style_accent = .{
        .accent = accent.lighten(0.3),
        .fill = accent,
        .text = Color.white,
        .border = Color.lerp(accent, 0.4, Color.white),
        .hover = Color.lerp(accent, 0.2, Color.white),
        .press = Color.lerp(accent, 0.3, Color.white),
        .press_text = Color.white,
    },
    .style_success = .{
        .accent = dark_success.lighten(0.3),
        .fill = dark_success,
        .text = Color.white,
        .border = Color.lerp(success, 0.4, Color.white),
        .hover = Color.lerp(success, 0.2, Color.white),
        .press = Color.lerp(success, 0.3, Color.white),
        .press_text = Color.white,
    },
    .style_err = .{
        .accent = dark_err.lighten(0.3),
        .fill = dark_err,
        .text = Color.white,
        .border = Color.lerp(err, 0.4, Color.white),
        .hover = Color.lerp(err, 0.2, Color.white),
        .press = Color.lerp(err, 0.3, Color.white),
        .press_text = Color.white,
    },
};
