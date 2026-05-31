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

const fill: dvui.Color = .fromHex("#282a36");
const text: dvui.Color = .fromHex("#f8f8f2");
const border: dvui.Color = .fromHex("#6272a4");

pub const theme: dvui.Theme = blk: {
    @setEvalBranchQuota(2000);
    break :blk .{
        .name = "Dracula",
        .dark = true,

        .embedded_fonts = fonts,

        .body_style = .{
            .font_family = "Pixelify Sans",
            .fill = text,
        },

        .heading_style = .{
            .font_family = "Pixelify Sans",
            .weight = .bold,
            .fill = text,
        },

        .title_style = .{
            .font_family = "Pixelify Sans",
            .size = 12,
            .fill = text,
        },

        .mono_style = .{
            .font_family = "None",
            .fill = text,
        },

        .focus = .fromHex("#ff79c6"),
        .fill = fill,
        .border = border,

        .control = .{
            .fill = .fromHex("#44475a"),
            .fill_hover = .fromHex("#6272a4"),
            .fill_press = .fromHex("#ff79c6"),
            .text_press = .fromHex("#21222c"),
        },
        .window = .{
            .fill = .fromHex("#282a36"),
        },
        .highlight = .{
            .fill = .fromHex("#93517e"),
            .text = .fromHex("#fbb8dc"),
        },

        .err = .{
            .fill = .average(.red, fill),
            .text = .average(.red, text),
            .border = .average(.red, border),
        },
    };
};
