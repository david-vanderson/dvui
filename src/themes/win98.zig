const dvui = @import("../dvui.zig");

const Color = dvui.Color;
const Font = dvui.Font;
const Theme = dvui.Theme;
const Options = dvui.Options;

pub const light = light: {
    @setEvalBranchQuota(3123);
    break :light Theme{
        .name = "Windows 98",
        .dark = false,

        .font_body = .{ .size = 16, .id = .Vera },
        .font_heading = .{ .size = 16, .id = .VeraBd },
        .font_caption = .{ .size = 13, .id = .Vera, .line_height_factor = 1.1 },
        .font_caption_heading = .{ .size = 13, .id = .VeraBd, .line_height_factor = 1.1 },
        .font_title = .{ .size = 28, .id = .Vera },
        .font_title_1 = .{ .size = 24, .id = .VeraBd },
        .font_title_2 = .{ .size = 22, .id = .VeraBd },
        .font_title_3 = .{ .size = 20, .id = .VeraBd },
        .font_title_4 = .{ .size = 18, .id = .VeraBd },

        .focus = .gray,

        .fill = .white,
        .text = Color.black,
        .border = .fromHex("0a0a0a"),

        .control = .{
            .ninepatch_fill = dvui.Examples.ninepatch.outset,
            .ninepatch_press = dvui.Examples.ninepatch.inset,
            .fill = .white,
        },
    };
};
