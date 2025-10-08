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
    .margin = Rect.all(4),
    .corner_radius = Rect.all(5),
    .padding = Rect.all(6),
    .background = true,
    .style = .control,
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
    if (dvui.accesskit.nodeCreate(self.data(), .BUTTON, @src())) |ak_node| {
        dvui.AccessKit.nodeAddAction(ak_node, dvui.AccessKit.Action.FOCUS);
        dvui.AccessKit.nodeAddAction(ak_node, dvui.AccessKit.Action.CLICK);
    }
}

pub fn matchEvent(self: *ButtonWidget, e: *Event) bool {
    return dvui.eventMatch(e, .{ .id = self.data().id, .r = self.data().borderRectScale().r });
}

pub fn processEvents(self: *ButtonWidget) void {
    self.click = dvui.clicked(self.data(), .{ .hovered = &self.hover });
}

pub fn drawBackground(self: *ButtonWidget) void {
    self.data().borderAndBackground(.{ .fill_color = self.style().color_fill });
}

pub fn drawFocus(self: *ButtonWidget) void {
    if (self.init_options.draw_focus and self.focused()) {
        self.data().focusBorder();
    }
}

/// Returns an `Options` struct with color/style overrides for the hover and press state
pub fn style(self: *ButtonWidget) Options {
    var opts = self.data().options.styleOnly();
    if (dvui.captured(self.data().id)) {
        opts.color_fill = self.data().options.color(.fill_press);
        opts.color_text = self.data().options.color(.text_press);
    } else if (self.hover) {
        opts.color_fill = self.data().options.color(.fill_hover);
        opts.color_text = self.data().options.color(.text_hover);
    }
    return opts;
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

pub fn rectFor(self: *ButtonWidget, id: dvui.Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
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
    const should_free = self.data().was_allocated_on_widget_stack;
    defer if (should_free) dvui.widgetFree(self);
    defer self.* = undefined;
    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();
    dvui.parentReset(self.data().id, self.data().parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
