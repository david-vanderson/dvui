const dvui = @import("../dvui.zig");

const fonts: []const dvui.Font.Source = &.{
    .{
        .family = dvui.Font.array("Pixelify Sans"),
        .bytes = @embedFile("../fonts/Pixelify_Sans/static/PixelifySans-Regular.ttf"),
    },
    .{
        .family = dvui.Font.array("Pixelify Sans"),
        .weight = .bold,
        .bytes = @embedFile("../fonts/Pixelify_Sans/static/PixelifySans-Bold.ttf"),
    },
};

const fill: dvui.Color = .fromHex("#2c3332");
const text: dvui.Color = .fromHex("#82a29f");
const border: dvui.Color = .fromHex("#60827d");

pub const theme: dvui.Theme = blk: {
    @setEvalBranchQuota(2000);
    break :blk .{
        .name = "Jungle",
        .dark = true,

        .embedded_fonts = fonts,

        .font_body = .find(.{ .family = "Pixelify Sans" }),
        .font_heading = .find(.{ .family = "Pixelify Sans", .weight = .bold }),
        .font_title = .find(.{ .family = "Pixelify Sans", .size = dvui.Font.DefaultSize + 2 }),
        .font_mono = .find(.{ .family = "None" }),

        .focus = .fromHex("#638465"),
        .fill = fill,
        .text = text,
        .border = border,

        .control = .{
            .fill = .fromHex("#2c3334"),
            .fill_hover = .fromHex("#334e57"),
            .fill_press = .fromHex("#3b6357"),
            .text_press = .fromHex("#97af81"),
        },
        .window = .{
            .fill = .fromHex("#2b3a3a"),
        },
        .highlight = .{
            .fill = .fromHex("#475b4b"),
            .fill_hover = .fromHex("#4b695e"),
            .fill_press = .fromHex("#4f735e"),
            .text = .fromHex("#729382"),
            .text_press = .fromHex("#7d9973"),
        },

        .err = .{
            .fill = .average(.red, fill),
            .text = .average(.red, text),
            .border = .average(.red, border),
        },
    };
};

