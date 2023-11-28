const dvui = @import("dvui.zig");

const Color = dvui.Color;
const Font = dvui.Font;
const Options = dvui.Options;

name: []const u8,

// widgets can use this if they need to adjust colors
dark: bool,

alpha: f32 = 1.0,

// used for focus
color_accent: Color,

color_err: Color,

// text/foreground color
color_text: Color,

// text/foreground color when widget is pressed
color_text_press: Color,

// background color for displaying lots of text
color_fill: Color,

// background color for containers that have other widgets inside
color_fill_window: Color,

// background color for controls like buttons
color_fill_control: Color,

color_fill_hover: Color,
color_fill_press: Color,

color_border: Color,

font_body: Font,
font_heading: Font,
font_caption: Font,
font_caption_heading: Font,
font_title: Font,
font_title_1: Font,
font_title_2: Font,
font_title_3: Font,
font_title_4: Font,

// used for highlighting menu/dropdown items
style_accent: Options,

// used for a button to perform dangerous actions
style_err: Options,
