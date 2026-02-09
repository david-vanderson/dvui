const dvui = @import("../dvui.zig");

pub const fonts: []const dvui.Font.Source = &.{
    .{
        .family = dvui.Font.array("Aleo"),
        .bytes = @embedFile("../fonts/Aleo/static/Aleo-Regular.ttf"),
    },
    .{
        .family = dvui.Font.array("Aleo"),
        .weight = .bold,
        .bytes = @embedFile("../fonts/Aleo/static/Aleo-Bold.ttf"),
    },
    .{
        .family = dvui.Font.array("Aleo"),
        .style = .italic,
        .bytes = @embedFile("../fonts/Aleo/static/Aleo-Italic.ttf"),
    },
    .{
        .family = dvui.Font.array("Aleo"),
        .weight = .bold,
        .style = .italic,
        .bytes = @embedFile("../fonts/Aleo/static/Aleo-BoldItalic.ttf"),
    },
};

const fill: dvui.Color = .fromHex("#7c6f64");
const fill_press: dvui.Color = .fromHex("#fe8019");
const text: dvui.Color = .fromHex("#ebdbb2");
const border: dvui.Color = .fromHex("#83a598");

pub const theme: dvui.Theme = blk: {
    @setEvalBranchQuota(2000);
    break :blk .{
        .name = "Gruvbox",
        .dark = true,

        .embedded_fonts = fonts,

        .font_body = .find(.{ .family = "Aleo" }),
        .font_heading = .find(.{ .family = "Aleo", .weight = .bold }),
        .font_title = .find(.{ .family = "Aleo", .size = dvui.Font.DefaultSize + 2 }),
        .font_mono = .find(.{ .family = "None" }),

        .focus = .fromHex("#fe8019"),
        .fill = fill,
        .fill_press = fill_press,
        .text = text,
        .border = border,

        .control = .{
            .fill = .fromHex("#7c6f64"),
            .fill_hover = .fromHex("#83a598"),
            .fill_press = .fromHex("#fe8019"),
            .text_press = .fromHex("#1d2021"),
        },
        .window = .{
            .fill = .fromHex("#665c54"),
        },
        .highlight = .{
            .fill = .fromHex("#bd773e"),
            .fill_press = .fromHex("#fe8019"),
            .text = .fromHex("#f4ad65"),
            .text_press = .fromHex("#1d2021"),
        },

        .err = .{
            .fill = .average(.red, fill),
            .fill_press = .average(.red, fill_press),
            .text = .average(.red, text),
            .border = .average(.red, border),
        },
    };
};

