const dvui = @import("../dvui.zig");

const fonts: []const dvui.Font.Source = &.{
    .{
        .family = dvui.Font.array("OpenDyslexic"),
        .bytes = @embedFile("../fonts/OpenDyslexic/compiled/OpenDyslexic-Regular.otf"),
    },
    .{
        .family = dvui.Font.array("OpenDyslexic"),
        .weight = .bold,
        .bytes = @embedFile("../fonts/OpenDyslexic/compiled/OpenDyslexic-Bold.otf"),
    },
    .{
        .family = dvui.Font.array("OpenDyslexic"),
        .style = .italic,
        .bytes = @embedFile("../fonts/OpenDyslexic/compiled/OpenDyslexic-Italic.otf"),
    },
    .{
        .family = dvui.Font.array("OpenDyslexic"),
        .weight = .bold,
        .style = .italic,
        .bytes = @embedFile("../fonts/OpenDyslexic/compiled/OpenDyslexic-Bold-Italic.otf"),
    },
};

const fill: dvui.Color = .fromHex("#ffffff");
const text: dvui.Color = .fromHex("#000000");
const border: dvui.Color = .fromHex("#a1a1a1");

pub const theme: dvui.Theme = blk: {
    @setEvalBranchQuota(2000);
    break :blk .{
        .name = "Open Dyslexic",
        .dark = false,

        .embedded_fonts = fonts,

        .font_body = .find(.{ .family = "OpenDyslexic", .size = 18 }),
        .font_heading = .find(.{ .family = "OpenDyslexic", .size = 18, .weight = .bold }),
        .font_title = .find(.{ .family = "OpenDyslexic", .size = 22 }),
        .font_mono = .find(.{ .family = "None", .size = 18 }),

        .focus = .fromHex("#3584e4"),
        .fill = fill,
        .text = text,
        .border = border,

        .control = .{
            .fill = .fromHex("#e0e0e0"),
            .fill_hover = .fromHex("#d1d1d1"),
            .fill_press = .fromHex("#b8b8b8"),
        },
        .window = .{
            .fill = .fromHex("#f0f0f0"),
        },
        .highlight = .{
            .fill = .fromHex("#9ac1f1"),
            .text = .fromHex("#1a4272"),
        },

        .err = .{
            .fill = .average(.red, fill),
            .text = .average(.red, text),
            .border = .average(.red, border),
        },
    };
};

