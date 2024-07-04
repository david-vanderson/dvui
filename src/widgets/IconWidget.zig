const std = @import("std");
const dvui = @import("../dvui.zig");

const Options = dvui.Options;
const Size = dvui.Size;
const WidgetData = dvui.WidgetData;

const IconWidget = @This();

wd: WidgetData = undefined,
name: []const u8 = undefined,
tvg_bytes: []const u8 = undefined,

pub fn init(src: std.builtin.SourceLocation, name: []const u8, tvg_bytes: []const u8, opts: Options) !IconWidget {
    var self = IconWidget{};
    const options = (Options{ .name = "Icon" }).override(opts);
    self.name = name;
    self.tvg_bytes = tvg_bytes;

    var size = Size{};
    if (options.min_size_content) |msc| {
        // user gave us a min size, use it
        size = msc;
        size.w = @max(size.w, dvui.iconWidth(name, tvg_bytes, size.h) catch size.w);
    } else {
        // user didn't give us one, make it the height of text
        const h = options.fontGet().lineHeight() catch 10;
        size = Size{ .w = dvui.iconWidth(name, tvg_bytes, h) catch h, .h = h };
    }

    self.wd = WidgetData.init(src, .{}, options.override(.{ .min_size_content = size }));

    return self;
}

pub fn install(self: *IconWidget) !void {
    try self.wd.register();
    try self.wd.borderAndBackground(.{});
}

pub fn matchEvent(self: *IconWidget, e: *dvui.Event) bool {
    return dvui.eventMatch(e, .{ .id = self.wd.id, .r = self.wd.borderRectScale().r });
}

pub fn draw(self: *IconWidget) !void {
    const rect = dvui.placeIn(self.wd.contentRect(), self.wd.options.min_size_contentGet(), .none, self.wd.options.gravityGet());
    const rs = self.wd.parent.screenRectScale(rect);
    try dvui.renderIcon(self.name, self.tvg_bytes, rs, self.wd.options.rotationGet(), self.wd.options.color(.text));
}

pub fn deinit(self: *IconWidget) void {
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
}
