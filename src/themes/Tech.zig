const dvui = @import("../dvui.zig");

const Color = dvui.Color;
const Font = dvui.Font;
const Theme = dvui.Theme;
const Options = dvui.Options;

const fonts: []const Font.Source = &.{
    .{
        .family = Font.array("Interceptor"),
        .bytes = @embedFile("../fonts/PS_Interceptor/Interceptor.otf"),
    },
    .{
        .family = Font.array("Interceptor"),
        .weight = .bold,
        .bytes = @embedFile("../fonts/PS_Interceptor/Interceptor Bold.otf"),
    },
    .{
        .family = Font.array("Interceptor"),
        .style = .italic,
        .bytes = @embedFile("../fonts/PS_Interceptor/Interceptor Italic.otf"),
    },
    .{
        .family = Font.array("Interceptor"),
        .weight = .bold,
        .style = .italic,
        .bytes = @embedFile("../fonts/PS_Interceptor/Interceptor Bold Italic.otf"),
    },
};

const cyan_full: dvui.Color = .fromHex("#72FDFF");
const cyan_75: dvui.Color = .lerp(.black, cyan_full, 0.75);
const cyan_50: dvui.Color = .lerp(.black, cyan_full, 0.5);
const cyan_25: dvui.Color = .lerp(.black, cyan_full, 0.25);
const cyan_12: dvui.Color = .lerp(.black, cyan_full, 0.125);

const red_full: dvui.Color = .fromHex("#FF4F3D");
const red_75: dvui.Color = .lerp(.black, red_full, 0.75);
const red_50: dvui.Color = .lerp(.black, red_full, 0.5);
const red_35: dvui.Color = .lerp(.black, red_full, 0.35);

const yellow_base: dvui.Color = .fromHex("#FFAE00");
const yellow_light_25: dvui.Color = .lerp(yellow_base, .white, 0.25);
const yellow_light_50: dvui.Color = .lerp(yellow_base, .white, 0.50);
const yellow_light_75: dvui.Color = .lerp(yellow_base, .white, 0.75);
const yellow_dark_25: dvui.Color = .lerp(.black, yellow_base, 0.75);

pub const theme: dvui.Theme = blk: {
    @setEvalBranchQuota(2000);
    break :blk .{
        .name = "Tech Classic",
        .dark = true,

        .embedded_fonts = fonts,

        .font_body = .find(.{ .family = "Interceptor", .size = 9 }),
        .font_heading = .find(.{ .family = "Interceptor", .weight = .bold, .size = 9 }),
        .font_title = .find(.{ .family = "Interceptor", .size = 11 }),
        .font_mono = .find(.{ .family = "None" }),

        .focus = .white,
        .fill = .black,
        .text = cyan_full,
        .border = cyan_full,

        .default_corner = .cut45(10),

        .control = .{
            .fill = cyan_25,
            .fill_hover = cyan_50,
            .fill_press = cyan_75,
            .text_press = .white,
            .border = cyan_full,
            .text = cyan_full,
        },
        .window = .{
            .fill = cyan_12,
        },
        .highlight = .{
            .fill = yellow_dark_25,
            .fill_hover = yellow_base,
            .fill_press = yellow_light_25,
            .text = yellow_light_75,
            .text_press = .white,
        },

        .err = .{
            .fill = red_35,
            .fill_hover = red_50,
            .fill_press = red_75,
            .text = red_full,
            .text_press = .white,
            .border = red_full,
        },
    };
};
