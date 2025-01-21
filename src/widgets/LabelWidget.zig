const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Rect = dvui.Rect;
const Size = dvui.Size;
const WidgetData = dvui.WidgetData;

const LabelWidget = @This();

pub var defaults: Options = .{
    .name = "Label",
    .padding = Rect.all(6),
};

wd: WidgetData = undefined,
label_str: []const u8 = undefined,

pub fn init(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype, opts: Options) !LabelWidget {
    const l = try std.fmt.allocPrint(dvui.currentWindow().arena(), fmt, args);
    return try LabelWidget.initNoFmt(src, l, opts);
}

pub fn initNoFmt(src: std.builtin.SourceLocation, label_str: []const u8, opts: Options) !LabelWidget {
    var self = LabelWidget{};
    const options = defaults.override(opts);
    self.label_str = label_str;

    var size = try options.fontGet().textSize(self.label_str);
    size = Size.max(size, options.min_size_contentGet());

    self.wd = WidgetData.init(src, .{}, options.override(.{ .min_size_content = size }));

    return self;
}

pub fn data(self: *LabelWidget) *WidgetData {
    return &self.wd;
}

pub fn install(self: *LabelWidget) !void {
    try self.wd.register();
    try self.wd.borderAndBackground(.{});
}

pub fn draw(self: *LabelWidget) !void {
    const rect = dvui.placeIn(self.wd.contentRect(), self.wd.options.min_size_contentGet(), .none, self.wd.options.gravityGet());
    var rs = self.wd.parent.screenRectScale(rect);
    const oldclip = dvui.clip(rs.r);
    var iter = std.mem.splitScalar(u8, self.label_str, '\n');
    var line_height_adj: f32 = undefined;
    var first: bool = true;
    while (iter.next()) |line| {
        if (first) {
            line_height_adj = self.wd.options.fontGet().textHeight() * (self.wd.options.fontGet().line_height_factor - 1.0);
            first = false;
        } else {
            rs.r.y += rs.s * line_height_adj;
        }

        const tsize = try self.wd.options.fontGet().textSize(line);
        const lineRect = dvui.placeIn(self.wd.contentRect(), tsize, .none, self.wd.options.gravityGet());
        const liners = self.wd.parent.screenRectScale(lineRect);

        rs.r.x = liners.r.x;
        try dvui.renderText(.{
            .font = self.wd.options.fontGet(),
            .text = line,
            .rs = rs,
            .color = self.wd.options.color(.text),
            .debug = self.wd.options.debugGet(),
        });
        rs.r.y += rs.s * tsize.h;
    }
    dvui.clipSet(oldclip);
}

pub fn matchEvent(self: *LabelWidget, e: *Event) bool {
    return dvui.eventMatchSimple(e, self.data());
}

pub fn processEvents(self: *LabelWidget) void {
    const evts = dvui.events();
    for (evts) |*e| {
        if (!self.matchEvent(e))
            continue;

        self.processEvent(e, false);
    }
}

pub fn processEvent(self: *LabelWidget, e: *Event, bubbling: bool) void {
    _ = bubbling;

    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *LabelWidget) void {
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
}
