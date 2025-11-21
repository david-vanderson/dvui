//! Generally inspired by Windows 98, but specifically inspired by the [98.css]
//! library.
//!
//! [98.css]: https://jdan.github.io/98.css/
const dvui = @import("../dvui.zig");

const Color = dvui.Color;
const Font = dvui.Font;
const Theme = dvui.Theme;
const Options = dvui.Options;

//Color constants taken from [98.css] and [Programming Windows].
//[98.css]: https://github.com/jdan/98.css/blob/main/style.css
//[Programming Windows]: https://secure.corradoroberto.it/doc/WinAPI/ch09c.htm

const text_color: Color = .fromHex("222222");
const surface: Color = .fromHex("c0c0c0");

const button_highlight = Color.fromHex("ffffff");
const button_face = Color.fromHex("dfdfdf");
const button_shadow = Color.fromHex("808080");

const window_frame = Color.fromHex("0a0a0a");

const dialog_blue = Color.fromHex("000080");
const dialog_blue_light = Color.fromHex("1084d0");
const dialog_gray = Color.fromHex("808080");
const dialog_gray_light = Color.fromHex("b5b5b5");

const link_blue = Color.fromHex("0000ff");

pub const light = light: {
    @setEvalBranchQuota(3123);
    break :light Theme{
        .name = "Windows 98",
        .dark = false,

        .font_body = .{ .size = 16, .id = .Aleo },
        .font_heading = .{ .size = 16, .id = .AleoBd },
        .font_caption = .{ .size = 13, .id = .Aleo, .line_height_factor = 1.1 },
        .font_caption_heading = .{ .size = 13, .id = .AleoBd, .line_height_factor = 1.1 },
        .font_title = .{ .size = 28, .id = .Aleo },
        .font_title_1 = .{ .size = 24, .id = .AleoBd },
        .font_title_2 = .{ .size = 22, .id = .AleoBd },
        .font_title_3 = .{ .size = 20, .id = .AleoBd },
        .font_title_4 = .{ .size = 18, .id = .AleoBd },

        .text_select = dialog_blue_light,
        .focus = dialog_blue_light,

        .fill = surface,
        .text = text_color,
        .border = .white,

        .control = .{
            .ninepatch_fill = dvui.Ninepatch.builtins.outset,
            .ninepatch_press = dvui.Ninepatch.builtins.inset,
            .fill = .white,
            .fill_hover = .white,
            .fill_press = .white,
        },
        .window = .{
            .ninepatch_fill = dvui.Ninepatch.builtins.outset,
            .ninepatch_press = dvui.Ninepatch.builtins.inset,
            .fill = .white,
            .fill_hover = .white,
            .fill_press = .white,
        },
    };
};
