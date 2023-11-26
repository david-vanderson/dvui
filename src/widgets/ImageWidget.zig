const std = @import("std");
const dvui = @import("../dvui.zig");

const Options = dvui.Options;
const Size = dvui.Size;
const WidgetData = dvui.WidgetData;

const ImageWidget = @This();

wd: WidgetData = undefined,
name: []const u8 = undefined,
image_bytes: []const u8 = undefined,

pub fn init(src: std.builtin.SourceLocation, name: []const u8, image_bytes: []const u8, opts: Options) !ImageWidget {
    var self = ImageWidget{};
    const options = (Options{ .name = "Image" }).override(opts);
    self.name = name;
    self.image_bytes = image_bytes;

    var size = Size{};
    if (options.min_size_content) |msc| {
        // user gave us a min size, use it
        size = msc;
    } else {
        // user didn't give us one, use natural size
        size = dvui.imageSize(name, image_bytes) catch .{ .w = 10, .h = 10 };
    }

    self.wd = WidgetData.init(src, .{}, options.override(.{ .min_size_content = size }));

    return self;
}

pub fn install(self: *ImageWidget) !void {
    try self.wd.register();
    try self.wd.borderAndBackground(.{});
}

pub fn draw(self: *ImageWidget) !void {
    var rect = dvui.placeIn(self.wd.contentRect(), self.wd.options.min_size_contentGet(), .none, self.wd.options.gravityGet());
    var rs = self.wd.parent.screenRectScale(rect);
    try dvui.renderImage(self.name, self.image_bytes, rs, self.wd.options.rotationGet(), .{});
}

pub fn deinit(self: *ImageWidget) void {
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
}