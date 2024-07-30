const dvui = @import("../dvui.zig");

const Color = dvui.Color;
const Font = dvui.Font;
const Theme = dvui.Theme;
const Options = dvui.Options;
const Vera = Font.TTFBytesId.Vera;
const VeraBd = Font.TTFBytesId.VeraBd;

//Colors inspired by the flow neovim theme
const accent = Color{ .r = 0xff, .g = 0x33, .b = 0x99, .a = 0xff }; // colors.fluo.pink
const err = Color{ .r = 0xf2, .g = 0xf2, .b = 0xf2, .a = 0xff }; // colors.white
const text = Color{ .r = 0xf2, .g = 0xf2, .b = 0xf2, .a = 0xff }; // colors.white
const text_press = Color{ .r = 0x0d, .g = 0x0d, .b = 0x0d, .a = 0xff }; // colors.black
const fill = Color{ .r = 0x0d, .g = 0x13, .b = 0x2f, .a = 0xff }; // colors.grey[1]
const fill_window = fill; // Color{ .r = 0x9f, .g = 0xa7, .b = 0xc7, .a = 0xff }; // colors.grey[7]
const fill_control = Color{ .r = 0x51, .g = 0x5b, .b = 0x7f, .a = 0xff }; // colors.grey[4]
const fill_hover = Color{ .r = 0x62, .g = 0x72, .b = 0xa4, .a = 0xff }; // colors.bg_border
const fill_press = accent;
const border = Color{ .r = 0x9f, .g = 0xa7, .b = 0xc7, .a = 0xff }; // colors.grey[7]
const size = 15;

pub const flow = Theme{
    .name = "Flow",
    .dark = true,

    .font_body = .{ .size = 13, .name = "Vera", .ttf_bytes_id = Vera },
    .font_heading = .{ .size = 13, .name = "VeraBd", .ttf_bytes_id = VeraBd },
    .font_caption = .{ .size = 10, .name = "Vera", .ttf_bytes_id = Vera },
    .font_caption_heading = .{ .size = 10, .name = "VeraBd", .ttf_bytes_id = VeraBd },
    .font_title = .{ .size = 28, .name = "Vera", .ttf_bytes_id = Vera },
    .font_title_1 = .{ .size = 23, .name = "VeraBd", .ttf_bytes_id = VeraBd },
    .font_title_2 = .{ .size = 20, .name = "VeraBd", .ttf_bytes_id = VeraBd },
    .font_title_3 = .{ .size = 17, .name = "VeraBd", .ttf_bytes_id = VeraBd },
    .font_title_4 = .{ .size = 15, .name = "VeraBd", .ttf_bytes_id = VeraBd },

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
        .color_accent = .{ .color = Color.merge(accent, accent) },
        .color_text = .{ .color = Color.merge(accent, text) },
        .color_text_press = .{ .color = Color.merge(accent, text_press) },
        .color_fill = .{ .color = Color.merge(accent, fill) },
        .color_fill_hover = .{ .color = Color.merge(accent, fill_hover) },
        .color_fill_press = .{ .color = Color.merge(accent, fill_press) },
        .color_border = .{ .color = Color.merge(accent, border) },
    },

    .style_err = Options{
        .color_accent = .{ .color = Color.merge(err, accent) },
        .color_text = .{ .color = Color.merge(err, text) },
        .color_text_press = .{ .color = Color.merge(err, text_press) },
        .color_fill = .{ .color = Color.merge(err, fill) },
        .color_fill_hover = .{ .color = Color.merge(err, fill_hover) },
        .color_fill_press = .{ .color = Color.merge(err, fill_press) },
        .color_border = .{ .color = Color.merge(err, border) },
    },
};
