const std = @import("std");

const Color = @import("Color.zig");
const Font = @import("Font.zig");

// this should be changed seldomly
pub const Facet = union(enum) {
    /// contains font size and font name
    font: Font,
    font_color: Color,
    fill: Color,
};

// list all used by the core widgets here
pub const common_context = struct {
    pub const body = "body";
    pub const heading = "heading";
    pub const caption = "caption";
    pub const title = "title";
};

/// context: a string like "body text"
pub fn style_me(a: std.mem.Allocator, widget: anytype, context: []const u8, comptime facet: std.meta.Tag(Facet)) !std.meta.TagPayload(Facet, facet) {
    _ = a;
    _ = widget;
    _ = context;
    @panic("unimplemented");
}
