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

const fonts: []const Font.Source = &.{
    .{
        .family = Font.array("Vera"),
        .bytes = @embedFile("../fonts/bitstream-vera/Vera.ttf"),
    },
    .{
        .family = Font.array("Vera"),
        .weight = .bold,
        .bytes = @embedFile("../fonts/bitstream-vera/VeraBd.ttf"),
    },
    .{
        .family = Font.array("Vera"),
        .style = .italic,
        .bytes = @embedFile("../fonts/bitstream-vera/VeraIt.ttf"),
    },
    .{
        .family = Font.array("Vera"),
        .weight = .bold,
        .style = .italic,
        .bytes = @embedFile("../fonts/bitstream-vera/VeraBI.ttf"),
    },
};

pub const light = light: {
    @setEvalBranchQuota(3123);
    break :light Theme{
        .name = "Adwaita Light",
        .dark = false,

        .embedded_fonts = fonts,

        .font = .find(.{ .family = "Vera" }),

        .focus = accent,

        .fill = Color.white,
        .fill_hover = (Color.HSLuv{ .s = 0, .l = 82 }).color(),
        .fill_press = (Color.HSLuv{ .s = 0, .l = 72 }).color(),
        .text = Color.black,
        .text_select = .{ .r = 0x91, .g = 0xbc, .b = 0xf0 },
        .border = (Color.HSLuv{ .s = 0, .l = 63 }).color(),

        .control = .{
            .fill = .{ .r = 0xe0, .g = 0xe0, .b = 0xe0 },
            .fill_hover = (Color.HSLuv{ .s = 0, .l = 82 }).color(),
            .fill_press = (Color.HSLuv{ .s = 0, .l = 72 }).color(),
        },

        .window = .{
            .fill = .{ .r = 0xf0, .g = 0xf0, .b = 0xf0 },
        },

        .highlight = .{
            .fill = light_accent_fill,
            .fill_hover = light_accent_fill_hover,
            .fill_press = light_accent_accent,
            .text = Color.white,
            .border = light_accent_border,
        },

        .err = .{
            .fill = light_err_fill,
            .fill_hover = light_err_fill_hover,
            .fill_press = light_err_accent,
            .text = Color.white,
            .border = light_err_border,
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

        .embedded_fonts = fonts,

        .font = .find(.{ .family = "Vera" }),

        .focus = accent,

        .fill = dark_fill,
        .fill_hover = dark_fill_hsl.lighten(21).color(),
        .fill_press = dark_fill_hsl.lighten(30).color(),
        .text = Color.white,
        .text_select = .{ .r = 0x32, .g = 0x60, .b = 0x98 },
        .border = dark_fill_hsl.lighten(39).color(),

        .control = .{
            .fill = .{ .r = 0x40, .g = 0x40, .b = 0x40 },
            .fill_hover = dark_fill_hsl.lighten(21).color(),
            .fill_press = dark_fill_hsl.lighten(30).color(),
        },

        .window = .{
            .fill = .{ .r = 0x2b, .g = 0x2b, .b = 0x2b },
        },

        .highlight = .{
            .fill = accent,
            .fill_hover = dark_accent_fill_hover,
            .fill_press = dark_accent_accent,
            .text = Color.white,
            .border = dark_accent_border,
        },

        .err = .{
            .fill = dark_err,
            .fill_hover = dark_err_fill_hover,
            .fill_press = dark_err_fill_press,
            .text = Color.white,
            .border = dark_err_border,
        },
    };
};
