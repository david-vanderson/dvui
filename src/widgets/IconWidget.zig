const std = @import("std");
const dvui = @import("../dvui.zig");

const Options = dvui.Options;
const Size = dvui.Size;
const WidgetData = dvui.WidgetData;

const IconWidget = @This();

wd: WidgetData,
name: []const u8,
tvg_bytes: []const u8,
icon_opts: dvui.IconRenderOptions,

pub fn init(src: std.builtin.SourceLocation, name: []const u8, tvg_bytes: []const u8, icon_opts: dvui.IconRenderOptions, opts: Options) IconWidget {
    var size = Size{};
    if (opts.min_size_content) |msc| {
        // user gave us a min size, use it
        size = msc;
        size.w = @max(size.w, dvui.iconWidth(name, tvg_bytes, size.h) catch size.w);
    } else {
        // user didn't give us one, make it the height of text
        const h = opts.fontGet().textHeight();
        size = Size{ .w = dvui.iconWidth(name, tvg_bytes, h) catch h, .h = h };
    }

    const defaults = Options{ .name = "Icon" };

    return .{
        .wd = WidgetData.init(src, .{}, defaults.override(opts).override(.{ .min_size_content = size })),
        .name = name,
        .tvg_bytes = tvg_bytes,
        .icon_opts = icon_opts,
    };
}

pub fn install(self: *IconWidget) void {
    self.wd.register();
    self.wd.borderAndBackground(.{});
}

pub fn data(self: *IconWidget) *WidgetData {
    return self.wd.validate();
}

pub fn matchEvent(self: *IconWidget, e: *dvui.Event) bool {
    return dvui.eventMatchSimple(e, &self.wd);
}

pub fn draw(self: *IconWidget) void {
    const rs = self.wd.parent.screenRectScale(self.wd.contentRect());
    var texOpts: dvui.RenderTextureOptions = .{ .rotation = self.wd.options.rotationGet() };

    const white: ?dvui.Color = .white;
    const as_bytes = std.mem.asBytes;
    if (std.mem.eql(u8, as_bytes(&self.icon_opts.fill_color), as_bytes(&white)) and
        std.mem.eql(u8, as_bytes(&self.icon_opts.stroke_color), as_bytes(&white)))
    {
        // user is rasterizing icon with defaults (white), so always use
        // colormod (so icons default to text color)
        texOpts.colormod = self.wd.options.color(.text);
    } else if (self.wd.options.color_text) |ct| {
        // user is customizing icon rasterization, only colormod if they passed
        // a text color
        texOpts.colormod = ct.resolve();
    }

    dvui.renderIcon(
        self.name,
        self.tvg_bytes,
        rs,
        texOpts,
        self.icon_opts,
    ) catch |err| {
        dvui.logError(@src(), err, "Could not render icon", .{});
    };
}

pub fn deinit(self: *IconWidget) void {
    defer dvui.widgetFree(self);
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    self.* = undefined;
}

test {
    @import("std").testing.refAllDecls(@This());
}
