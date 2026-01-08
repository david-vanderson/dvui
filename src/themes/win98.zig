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

pub const raised = dvui.Ninepatch{
    .source = .{ .imageFile = .{
        .bytes = @embedFile("raised.png"),
        .name = "raised.png",
        .interpolation = .nearest,
    } },
    .edge = .all(2),
};

pub const sunken = dvui.Ninepatch{
    .source = .{ .imageFile = .{
        .bytes = @embedFile("sunken.png"),
        .name = "sunken.png",
        .interpolation = .nearest,
    } },
    .edge = .all(2),
};

pub const fonts: []const Font.Source = &.{
    .{
        .family = Font.array("Aleo"),
        .bytes = Font.alignEmbedded(@embedFile("../fonts/Aleo/static/Aleo-Regular.ttf")),
    },
    .{
        .family = Font.array("Aleo"),
        .weight = .bold,
        .bytes = Font.alignEmbedded(@embedFile("../fonts/Aleo/static/Aleo-Bold.ttf")),
    },
    .{
        .family = Font.array("Aleo"),
        .style = .italic,
        .bytes = Font.alignEmbedded(@embedFile("../fonts/Aleo/static/Aleo-Italic.ttf")),
    },
    .{
        .family = Font.array("Aleo"),
        .weight = .bold,
        .style = .italic,
        .bytes = Font.alignEmbedded(@embedFile("../fonts/Aleo/static/Aleo-BoldItalic.ttf")),
    },
};

pub const light = light: {
    @setEvalBranchQuota(3123);
    break :light Theme{
        .name = "Windows 98",
        .dark = false,

        .embedded_fonts = fonts,

        .font_body = .find(.{ .family = "Aleo" }),
        .font_heading = .find(.{ .family = "Aleo", .weight = .bold }),
        .font_title = .find(.{ .family = "Aleo", .size = 20 }),
        .font_mono = .find(.{ .family = "None" }),

        .text_select = dialog_blue_light,
        .focus = dialog_blue_light,

        .fill = surface,
        .text = text_color,
        .border = .white,

        .max_default_corner_radius = 0.0,

        .control = .{
            .ninepatch_fill = raised,
            .ninepatch_press = sunken,
            .fill = surface,
            .fill_hover = surface,
            .fill_press = surface,
        },
        .window = .{
            .ninepatch_fill = raised,
            .ninepatch_press = sunken,
            .fill = .white,
            .fill_hover = .white,
            .fill_press = .white,
        },
    };
};
