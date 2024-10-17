const std = @import("std");
const dvui = @import("../dvui.zig");

const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const FlexBoxWidget = @This();

pub const InitOptions = struct {};

wd: WidgetData = undefined,
init_options: InitOptions = undefined,
insert_pt: dvui.Point = .{},
row_size: Size = .{},
max_row_width: f32 = 0.0,
max_row_width_prev: f32 = 0.0,
width_nobreak: f32 = 0.0, // width if all children were on one row

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) FlexBoxWidget {
    var self = FlexBoxWidget{};
    const defaults = Options{ .name = "FlexBox" };
    self.wd = WidgetData.init(src, .{}, defaults.override(opts));
    self.init_options = init_opts;
    self.max_row_width_prev = dvui.dataGet(null, self.wd.id, "_mrw", f32) orelse 0.0;
    return self;
}

pub fn install(self: *FlexBoxWidget) !void {
    try self.wd.register();
    dvui.parentSet(self.widget());
}

pub fn drawBackground(self: *FlexBoxWidget) !void {
    try self.wd.borderAndBackground(.{});
}

pub fn widget(self: *FlexBoxWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *FlexBoxWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *FlexBoxWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    _ = e;
    _ = g;

    if (self.insert_pt.x > 0 and self.insert_pt.x + min_size.w > self.wd.contentRect().w) {
        // we ran off the end and didn't start at the left edge, break
        self.insert_pt.x = 0;
        self.insert_pt.y += self.row_size.h;
        self.row_size = .{ .w = 0, .h = min_size.h };
    } else {
        self.row_size.h = @max(self.row_size.h, min_size.h);
    }

    var ret = Rect.fromPoint(self.insert_pt).toSize(min_size);
    ret.x += (self.wd.contentRect().w - self.max_row_width_prev) / 2;

    self.insert_pt.x += min_size.w;

    return ret;
}

pub fn screenRectScale(self: *FlexBoxWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *FlexBoxWidget, s: Size) void {
    self.row_size.w += s.w;
    self.max_row_width = @max(self.max_row_width, self.row_size.w);
    self.width_nobreak += s.w;
    self.wd.min_size = self.wd.options.padSize(.{ .w = self.width_nobreak, .h = self.insert_pt.y + self.row_size.h });
}

pub fn processEvent(self: *FlexBoxWidget, e: *dvui.Event, bubbling: bool) void {
    _ = bubbling;
    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *FlexBoxWidget) void {
    dvui.dataSet(null, self.wd.id, "_mrw", self.max_row_width);
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    dvui.parentReset(self.wd.id, self.wd.parent);
}
