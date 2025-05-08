const std = @import("std");
const dvui = @import("../dvui.zig");

const Color = dvui.Color;
const Event = dvui.Event;
const Options = dvui.Options;
const ColorsFromTheme = Options.ColorsFromTheme;
const Point = dvui.Point;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const ButtonWidget = @This();

pub var defaults: Options = Options{};
pub const defaults_Def = .{
    .name = "Button",
    .color_fill = ColorsFromTheme.fill_control,
    .margin = Rect.all(4),
    .corner_radius = Rect.all(5),
    .padding = Rect.all(6),
    .background = true,
};

pub const InitOptions = struct {
    draw_focus: bool = true,
};

wd: WidgetData = undefined,
init_options: InitOptions = undefined,
hover: bool = false,
focus: bool = false,
click: bool = false,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) ButtonWidget {
    var self = ButtonWidget{};
    self.init_options = init_opts;
    self.wd = WidgetData.init(src, .{}, Options.fromAny(defaults_Def).override(defaults).override(opts));
    return self;
}

pub fn install(self: *ButtonWidget) !void {
    try self.wd.register();
    dvui.parentSet(self.widget());

    if (self.wd.visible()) {
        try dvui.tabIndexSet(self.wd.id, self.wd.options.tab_index);
    }
}

pub fn matchEvent(self: *ButtonWidget, e: *Event) bool {
    return dvui.eventMatchSimple(e, self.data());
}

pub fn processEvents(self: *ButtonWidget) void {
    const evts = dvui.events();
    for (evts) |*e| {
        if (!self.matchEvent(e))
            continue;

        self.processEvent(e, false);
    }
}

pub fn drawBackground(self: *ButtonWidget) !void {
    var fill_color: ?Color = null;
    if (dvui.captured(self.wd.id)) {
        fill_color = self.wd.options.color(.fill_press);
    } else if (self.hover) {
        fill_color = self.wd.options.color(.fill_hover);
    }

    try self.wd.borderAndBackground(.{ .fill_color = fill_color });
}

pub fn drawFocus(self: *ButtonWidget) !void {
    if (self.init_options.draw_focus and self.focused()) {
        try self.wd.focusBorder();
    }
}

pub fn focused(self: *ButtonWidget) bool {
    return self.wd.id == dvui.focusedWidgetId();
}

pub fn hovered(self: *ButtonWidget) bool {
    return self.hover;
}

pub fn pressed(self: *ButtonWidget) bool {
    return dvui.captured(self.wd.id);
}

pub fn clicked(self: *ButtonWidget) bool {
    return self.click;
}

pub fn widget(self: *ButtonWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *ButtonWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *ButtonWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *ButtonWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *ButtonWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
}

pub fn processEvent(self: *ButtonWidget, e: *Event, bubbling: bool) void {
    _ = bubbling;
    switch (e.evt) {
        .mouse => |me| {
            if (me.action == .focus) {
                e.handled = true;
                dvui.focusWidgetSelf(self.wd.id, e.num);
            } else if (me.action == .press and me.button.pointer()) {
                e.handled = true;
                dvui.captureMouse(self.data());

                // drag prestart is just for touch events
                dvui.dragPreStart(me.p, .{});
            } else if (me.action == .release and me.button.pointer()) {
                if (dvui.captured(self.wd.id)) {
                    e.handled = true;
                    dvui.captureMouse(null);
                    dvui.dragEnd();
                    if (self.data().borderRectScale().r.contains(me.p)) {
                        self.click = true;
                        dvui.refresh(null, @src(), self.wd.id);
                    }
                }
            } else if (me.action == .motion and me.button.touch()) {
                if (dvui.captured(self.wd.id)) {
                    if (dvui.dragging(me.p)) |_| {
                        // if we overcame the drag threshold, then that
                        // means the person probably didn't want to touch
                        // this button, maybe they were trying to scroll
                        dvui.captureMouse(null);
                        dvui.dragEnd();
                    }
                }
            } else if (me.action == .position) {
                dvui.cursorSet(.arrow);
                self.hover = true;
            }
        },
        .key => |ke| {
            if (ke.action == .down and ke.matchBind("activate")) {
                e.handled = true;
                self.click = true;
                dvui.refresh(null, @src(), self.wd.id);
            }
        },
        else => {},
    }

    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *ButtonWidget) void {
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    dvui.parentReset(self.wd.id, self.wd.parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
