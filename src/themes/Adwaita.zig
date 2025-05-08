const dvui = @import("../dvui.zig");

const Color = dvui.Color;
const Font = dvui.Font;
const Theme = dvui.Theme;
const Options = dvui.Options;

const accent = Color{ .r = 0x35, .g = 0x84, .b = 0xe4 };
const accent_hsl = Color.HSLuv.fromColor(accent);
const err = Color{ .r = 0xe0, .g = 0x1b, .b = 0x24 };
const err_hsl = Color.HSLuv.fromColor(err);

// need to have these as separate variables because inlining them below trips
// zig's comptime eval quota
const light_accent_accent = accent_hsl.lighten(-16).color();
const light_accent_fill = accent_hsl.color();
const light_accent_fill_hover = accent_hsl.lighten(-11).color();
const light_accent_border = accent_hsl.lighten(-22).color();

const light_err_accent = err_hsl.lighten(-15).color();
const light_err_fill = err_hsl.color();
const light_err_fill_hover = err_hsl.lighten(-10).color();
const light_err_border = err_hsl.lighten(-20).color();

pub const light = light: {
    @setEvalBranchQuota(3123);
    break :light Theme{
        .name = "Adwaita Light",
        .dark = false,

        .font_body = .{ .size = 16, .name = "Vera" },
        .font_heading = .{ .size = 16, .name = "VeraBd" },
        .font_caption = .{ .size = 13, .name = "Vera", .line_height_factor = 1.1 },
        .font_caption_heading = .{ .size = 13, .name = "VeraBd", .line_height_factor = 1.1 },
        .font_title = .{ .size = 28, .name = "Vera" },
        .font_title_1 = .{ .size = 24, .name = "VeraBd" },
        .font_title_2 = .{ .size = 22, .name = "VeraBd" },
        .font_title_3 = .{ .size = 20, .name = "VeraBd" },
        .font_title_4 = .{ .size = 18, .name = "VeraBd" },

        .color_accent = accent_hsl.color(),
        .color_err = err_hsl.color(),
        .color_text = Color.black,
        .color_text_press = Color.black,
        .color_fill = Color.white,
        .color_fill_window = .{ .r = 0xf0, .g = 0xf0, .b = 0xf0 },
        .color_fill_control = .{ .r = 0xe0, .g = 0xe0, .b = 0xe0 },
        .color_fill_hover = (Color.HSLuv{ .s = 0, .l = 82 }).color(),
        .color_fill_press = (Color.HSLuv{ .s = 0, .l = 72 }).color(),
        .color_border = (Color.HSLuv{ .s = 0, .l = 63 }).color(),

        .style_accent = Options{
            .color_accent = light_accent_accent,
            .color_text = Color.white,
            .color_text_press = Color.white,
            .color_fill = light_accent_fill,
            .color_fill_hover = light_accent_fill_hover,
            .color_fill_press = light_accent_accent,
            .color_border = light_accent_border,
        },

        .style_err = Options{
            .color_accent = light_err_accent,
            .color_text = Color.white,
            .color_text_press = Color.white,
            .color_fill = light_err_fill,
            .color_fill_hover = light_err_fill_hover,
            .color_fill_press = light_err_accent,
            .color_border = light_err_border,
        },
    };
};

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

pub const dark = dark: {
    @setEvalBranchQuota(3023);
    break :dark Theme{
        .name = "Adwaita Dark",
        .dark = true,

        .font_body = .{ .size = 16, .name = "Vera" },
        .font_heading = .{ .size = 16, .name = "VeraBd" },
        .font_caption = .{ .size = 13, .name = "Vera", .line_height_factor = 1.1 },
        .font_caption_heading = .{ .size = 13, .name = "VeraBd", .line_height_factor = 1.1 },
        .font_title = .{ .size = 28, .name = "Vera" },
        .font_title_1 = .{ .size = 24, .name = "VeraBd" },
        .font_title_2 = .{ .size = 22, .name = "VeraBd" },
        .font_title_3 = .{ .size = 20, .name = "VeraBd" },
        .font_title_4 = .{ .size = 18, .name = "VeraBd" },

        .color_accent = accent_hsl.color(),
        .color_err = dark_err,
        .color_text = Color.white,
        .color_text_press = Color.white,
        .color_fill = dark_fill,
        .color_fill_window = .{ .r = 0x2b, .g = 0x2b, .b = 0x2b },
        .color_fill_control = .{ .r = 0x40, .g = 0x40, .b = 0x40 },
        .color_fill_hover = dark_fill_hsl.lighten(21).color(),
        .color_fill_press = dark_fill_hsl.lighten(30).color(),
        .color_border = dark_fill_hsl.lighten(39).color(),

        .style_accent = Options{
            .color_accent = dark_accent_accent,
            .color_text = Color.white,
            .color_text_press = Color.white,
            .color_fill = accent,
            .color_fill_hover = dark_accent_fill_hover,
            .color_fill_press = dark_accent_accent,
            .color_border = dark_accent_border,
        },

        .style_err = Options{
            .color_accent = dark_err_accent,
            .color_text = Color.white,
            .color_text_press = Color.white,
            .color_fill = dark_err,
            .color_fill_hover = dark_err_fill_hover,
            .color_fill_press = dark_err_fill_press,
            .color_border = dark_err_border,
        },
    };
};
