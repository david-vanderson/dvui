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
}

pub fn matchEvent(self: *ButtonWidget, e: *Event) bool {
    return dvui.eventMatchSimple(e, self.data());
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

pub const Helpers = struct {
    pub fn button(src: std.builtin.SourceLocation, label_str: []const u8, init_opts: ButtonWidget.InitOptions, opts: Options) bool {
        // initialize widget and get rectangle from parent
        var bw = ButtonWidget.init(src, init_opts, opts);

        // make ourselves the new parent
        bw.install();

        // process events (mouse and keyboard)
        bw.processEvents();

        // draw background/border
        bw.drawBackground();

        // use pressed text color if desired
        const click = bw.clicked();

        // this child widget:
        // - has bw as parent
        // - gets a rectangle from bw
        // - draws itself
        // - reports its min size to bw
        dvui.labelNoFmt(@src(), label_str, .{ .align_x = 0.5, .align_y = 0.5 }, opts.strip().override(bw.style()).override(.{ .gravity_x = 0.5, .gravity_y = 0.5 }));

        // draw focus
        bw.drawFocus();

        // restore previous parent
        // send our min size to parent
        bw.deinit();

        return click;
    }

    pub fn buttonIcon(src: std.builtin.SourceLocation, name: []const u8, tvg_bytes: []const u8, init_opts: ButtonWidget.InitOptions, icon_opts: dvui.IconRenderOptions, opts: Options) bool {
        const button_icon_defaults = Options{ .padding = Rect.all(4) };
        var bw = ButtonWidget.init(src, init_opts, button_icon_defaults.override(opts));
        bw.install();
        bw.processEvents();
        bw.drawBackground();

        // When someone passes min_size_content to buttonIcon, they want the icon
        // to be that size, so we pass it through.
        dvui.icon(
            @src(),
            name,
            tvg_bytes,
            icon_opts,
            opts.strip().override(bw.style()).override(.{ .gravity_x = 0.5, .gravity_y = 0.5, .min_size_content = opts.min_size_content, .expand = .ratio, .color_text = opts.color_text }),
        );

        const click = bw.clicked();
        bw.drawFocus();
        bw.deinit();
        return click;
    }

    pub fn buttonLabelAndIcon(src: std.builtin.SourceLocation, label_str: []const u8, tvg_bytes: []const u8, init_opts: ButtonWidget.InitOptions, opts: Options) bool {
        // initialize widget and get rectangle from parent
        var bw = ButtonWidget.init(src, init_opts, opts);

        // make ourselves the new parent
        bw.install();

        // process events (mouse and keyboard)
        bw.processEvents();
        const options = opts.strip().override(bw.style()).override(.{ .gravity_y = 0.5 });

        // draw background/border
        bw.drawBackground();
        {
            var outer_hbox = dvui.box(src, .{ .dir = .horizontal }, .{ .expand = .horizontal });
            defer outer_hbox.deinit();
            dvui.icon(@src(), label_str, tvg_bytes, .{}, options.strip().override(.{ .gravity_x = 1.0, .color_text = opts.color_text }));
            dvui.labelEx(@src(), "{s}", .{label_str}, .{ .align_x = 0.5 }, options.strip().override(.{ .expand = .both }));
        }

        const click = bw.clicked();

        bw.drawFocus();

        bw.deinit();
        return click;
    }
};

test {
    @import("std").testing.refAllDecls(@This());
}
