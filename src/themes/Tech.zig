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

// Primary Colors
const cyan_full: dvui.Color = .fromHex("#7bdafc");
const cyan_75: dvui.Color = .lerp(.black, cyan_full, 0.75);
const cyan_50: dvui.Color = .lerp(.black, cyan_full, 0.5);
const cyan_25: dvui.Color = .lerp(.black, cyan_full, 0.25);
const cyan_12: dvui.Color = .lerp(.black, cyan_full, 0.125);
const cyan_light_25: dvui.Color = .lerp(cyan_full, .white, 0.25);

const green_full: dvui.Color = .fromHex("#24d815");
const green_75: dvui.Color = .lerp(.black, green_full, 0.75);
const green_50: dvui.Color = .lerp(.black, green_full, 0.5);
const green_25: dvui.Color = .lerp(.black, green_full, 0.25);
const green_12: dvui.Color = .lerp(.black, green_full, 0.125);

// Secondary Colors
const yellow_base: dvui.Color = .fromHex("#FFAE00");
const yellow_light_25: dvui.Color = .lerp(yellow_base, .white, 0.25);
const yellow_light_50: dvui.Color = .lerp(yellow_base, .white, 0.50);
const yellow_light_75: dvui.Color = .lerp(yellow_base, .white, 0.75);
const yellow_dark_25: dvui.Color = .lerp(.black, yellow_base, 0.75);

const purple_base: dvui.Color = .fromHex("#8715d8");
const purple_light_25: dvui.Color = .lerp(purple_base, .white, 0.25);
const purple_light_50: dvui.Color = .lerp(purple_base, .white, 0.50);
const purple_light_75: dvui.Color = .lerp(purple_base, .white, 0.75);
const purple_dark_25: dvui.Color = .lerp(.black, purple_base, 0.75);

// Error Colors
const red_full: dvui.Color = .fromHex("#FF4F3D");
const red_75: dvui.Color = .lerp(.black, red_full, 0.75);
const red_50: dvui.Color = .lerp(.black, red_full, 0.5);
const red_35: dvui.Color = .lerp(.black, red_full, 0.35);
const red_15: dvui.Color = .lerp(.black, red_full, 0.15);

const mag_full: dvui.Color = .fromHex("#f402fc");
const mag_75: dvui.Color = .lerp(.black, mag_full, 0.75);
const mag_50: dvui.Color = .lerp(.black, mag_full, 0.5);
const mag_35: dvui.Color = .lerp(.black, mag_full, 0.35);
const mag_15: dvui.Color = .lerp(.black, mag_full, 0.15);

pub const basic: dvui.Theme = blk: {
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

        .corner = .chamfer(10),

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

pub const retro: dvui.Theme = blk: {
    @setEvalBranchQuota(2000);
    break :blk .{
        .name = "Tech Retro",
        .dark = true,

        .embedded_fonts = fonts,

        .font_body = .find(.{ .family = "Interceptor", .size = 9 }),
        .font_heading = .find(.{ .family = "Interceptor", .weight = .bold, .size = 9 }),
        .font_title = .find(.{ .family = "Interceptor", .size = 11 }),
        .font_mono = .find(.{ .family = "None" }),

        .focus = .white,
        .fill = .black,
        .text = green_full,
        .border = green_full,

        .corner = .square,

        .control = .{
            .fill = green_25,
            .fill_hover = green_50,
            .fill_press = green_75,
            .text_press = .white,
            .border = green_full,
            .text = green_full,
        },
        .window = .{
            .fill = green_12,
        },
        .highlight = .{
            .fill = purple_dark_25,
            .fill_hover = purple_base,
            .fill_press = purple_light_25,
            .text = purple_light_75,
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

pub const eight_hundred: dvui.Theme = blk: {
    @setEvalBranchQuota(2000);
    break :blk .{
        .name = "Tech 800",
        .dark = true,

        .embedded_fonts = fonts,

        .font_body = .find(.{ .family = "Interceptor", .size = 9 }),
        .font_heading = .find(.{ .family = "Interceptor", .weight = .bold, .size = 9 }),
        .font_title = .find(.{ .family = "Interceptor", .size = 11 }),
        .font_mono = .find(.{ .family = "None" }),

        .focus = .white,
        .fill = .black,
        .text = .white,
        .border = red_full,

        .corner = .angular(16, 8),

        .control = .{
            .fill = red_35,
            .fill_hover = red_50,
            .fill_press = red_75,
            .text_press = .white,
            .border = red_full,
            .text = .white,
        },
        .window = .{
            .fill = red_15,
        },
        .highlight = .{
            .fill = cyan_75,
            .fill_hover = cyan_full,
            .fill_press = cyan_light_25,
            .text = .white,
            .text_press = .white,
        },

        .err = .{
            .fill = mag_35,
            .fill_hover = mag_50,
            .fill_press = mag_75,
            .text = mag_full,
            .text_press = .white,
            .border = mag_full,
        },
    };
};
