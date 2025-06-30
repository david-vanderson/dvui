const std = @import("std");
const dvui = @import("../dvui.zig");

const Color = dvui.Color;
const Event = dvui.Event;
const Options = dvui.Options;
const Point = dvui.Point;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const ButtonWidget = @This();

pub var defaults: Options = .{
    .name = "Button",
    .color_fill = .{ .name = .fill_control },
    .margin = Rect.all(4),
    .corner_radius = Rect.all(5),
    .padding = Rect.all(6),
    .background = true,
};

pub const InitOptions = struct {
    draw_focus: bool = true,
};

wd: WidgetData,
init_options: InitOptions,
hover: bool = false,
focus: bool = false,
click: bool = false,

pub fn init(src: std.builtin.SourceLocation, init_options: InitOptions, opts: Options) ButtonWidget {
    return .{
        .wd = .init(src, .{}, defaults.override(opts)),
        .init_options = init_options,
    };
}

pub fn install(self: *ButtonWidget) void {
    self.data().register();
    dvui.parentSet(self.widget());

    dvui.tabIndexSet(self.data().id, self.data().options.tab_index);
}

pub fn matchEvent(self: *ButtonWidget, e: *Event) bool {
    return dvui.eventMatchSimple(e, self.data());
}

pub fn processEvents(self: *ButtonWidget) void {
    self.click = dvui.clicked(self.data(), .{ .hovered = &self.hover });
}

pub fn drawBackground(self: *ButtonWidget) void {
    var fill_color: ?Color = null;
    if (dvui.captured(self.data().id)) {
        fill_color = self.data().options.color(.fill_press);
    } else if (self.hover) {
        fill_color = self.data().options.color(.fill_hover);
    }

    self.data().borderAndBackground(.{ .fill_color = fill_color });
}

pub fn drawFocus(self: *ButtonWidget) void {
    if (self.init_options.draw_focus and self.focused()) {
        self.data().focusBorder();
    }
}

pub fn focused(self: *ButtonWidget) bool {
    return self.data().id == dvui.focusedWidgetId();
}

pub fn hovered(self: *ButtonWidget) bool {
    return self.hover;
}

pub fn pressed(self: *ButtonWidget) bool {
    return dvui.captured(self.data().id);
}

pub fn clicked(self: *ButtonWidget) bool {
    return self.click;
}

pub fn widget(self: *ButtonWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *ButtonWidget) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *ButtonWidget, id: dvui.WidgetId, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.data().contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *ButtonWidget, rect: Rect) RectScale {
    return self.data().contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *ButtonWidget, s: Size) void {
    self.data().minSizeMax(self.data().options.padSize(s));
}

pub fn deinit(self: *ButtonWidget) void {
    defer dvui.widgetFree(self);
    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();
    dvui.parentReset(self.data().id, self.data().parent);
    self.* = undefined;
}

test {
    @import("std").testing.refAllDecls(@This());
}
