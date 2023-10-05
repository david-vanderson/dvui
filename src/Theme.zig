const dvui = @import("dvui.zig");

const Color = dvui.Color;
const Font = dvui.Font;

pub const ColorStyle = enum {
    content, // default
    accent,
    control,
    window,
    success,
    err,
};

pub const StyleColors = struct {
    // used to show focus
    accent: ?Color = null,

    text: ?Color = null,

    // background color contrasting the most with the text color, used when
    // displaying lots of text
    fill: ?Color = null,

    border: ?Color = null,
    hover: ?Color = null,
    press: ?Color = null,
};

name: []const u8,
dark: bool,

alpha: f32 = 1.0,

// Options.color_style selects between these

// content is default and must have all fields non-null
style_content: StyleColors,

// any null fields in these will use .content fields
style_accent: StyleColors,
style_control: StyleColors,
style_window: StyleColors,
style_success: StyleColors,
style_err: StyleColors,

font_body: Font,
font_heading: Font,
font_caption: Font,
font_caption_heading: Font,
font_title: Font,
font_title_1: Font,
font_title_2: Font,
font_title_3: Font,
font_title_4: Font,
