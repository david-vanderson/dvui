//! ## Note on ARIA Roles
//!
//! The `TabsWidget` is a `tablist`,
//! containing a list of elements with the role `tab`.
//! The content shown when you select a tab should have the role `tabpanel`.
//!
//! - [Tabs Pattern - ARIA Authoring Practices Guide](https://www.w3.org/WAI/ARIA/apg/patterns/tabs/)
pub const TabsWidget = @This();

init_options: InitOptions,
scroll: ScrollAreaWidget,
/// SAFETY: Set in `install`
group: dvui.FocusGroupWidget = undefined,
/// SAFETY: Set in `install`
box: BoxWidget = undefined,
tab_index: usize = 0,
/// SAFETY: Set in `addTab`
tab_button: ButtonWidget = undefined,

pub var defaults: Options = .{
    .name = "Tabs",
    // https://www.w3.org/TR/wai-aria/#tablist
    .role = .tab_list,
};

pub const InitOptions = struct {
    dir: dvui.enums.Direction = .horizontal,
    draw_focus: bool = true,
    was_allocated_on_widget_stack: bool = false,
};

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) TabsWidget {
    const scroll_opts: ScrollAreaWidget.InitOpts = switch (init_opts.dir) {
        .horizontal => .{ .vertical = .none, .horizontal = .auto, .horizontal_bar = .hide },
        .vertical => .{ .vertical = .auto, .vertical_bar = .hide },
    };
    return .{
        .init_options = init_opts,
        .scroll = ScrollAreaWidget.init(src, scroll_opts, defaults.override(opts)),
    };
}

pub fn install(self: *TabsWidget) void {
    self.scroll.install();

    self.group = dvui.FocusGroupWidget.init(@src(), .{ .nav_key_dir = self.init_options.dir }, .{});
    self.group.install();

    const margin: Rect = switch (self.init_options.dir) {
        .horizontal => .{ .y = 2 },
        .vertical => .{ .x = 2 },
    };
    self.box = BoxWidget.init(@src(), .{ .dir = self.init_options.dir }, .{ .margin = margin, .expand = .both });
    self.box.install();

    var r = self.scroll.data().contentRectScale().r;
    switch (self.init_options.dir) {
        .horizontal => {
            if (dvui.currentWindow().snap_to_pixels) {
                r.x += 0.5;
                r.w -= 1.0;
                r.y = @floor(r.y) - 0.5;
            }
            dvui.Path.stroke(.{ .points = &.{ r.bottomLeft(), r.bottomRight() } }, .{ .thickness = 1, .color = self.scroll.data().options.color(.border) });
        },
        .vertical => {
            if (dvui.currentWindow().snap_to_pixels) {
                r.y += 0.5;
                r.h -= 1.0;
                r.x = @floor(r.x) - 0.5;
            }
            dvui.Path.stroke(.{ .points = &.{ r.topRight(), r.bottomRight() } }, .{ .thickness = 1, .color = self.scroll.data().options.color(.border) });
        },
    }
}

pub fn addTabLabel(self: *TabsWidget, selected: bool, text: []const u8) bool {
    var tab = self.addTab(selected, .{});
    defer tab.deinit();

    var label_opts = tab.data().options.strip();
    if (dvui.captured(tab.data().id)) {
        label_opts.color_text = label_opts.color(.text_press);
    }

    dvui.labelNoFmt(@src(), text, .{}, label_opts);

    return tab.clicked();
}

pub fn addTab(self: *TabsWidget, selected: bool, opts: Options) *ButtonWidget {
    // https://www.w3.org/TR/wai-aria/#tab
    var tab_defaults: Options = switch (self.init_options.dir) {
        .horizontal => .{ .id_extra = self.tab_index, .background = true, .corner_radius = .{ .x = 5, .y = 5 }, .margin = .{ .x = 2, .w = 2 }, .role = .tab, .label = .{ .label_widget = .next } },
        .vertical => .{ .id_extra = self.tab_index, .background = true, .corner_radius = .{ .x = 5, .h = 5 }, .margin = .{ .y = 2, .h = 2 }, .role = .tab, .label = .{ .label_widget = .next } },
    };

    self.tab_index += 1;

    if (selected) {
        tab_defaults.style = .window;
        tab_defaults.font_style = .heading;
        tab_defaults.border = switch (self.init_options.dir) {
            .horizontal => .{ .x = 1, .y = 1, .w = 1 },
            .vertical => .{ .x = 1, .y = 1, .h = 1 },
        };
    } else {
        switch (self.init_options.dir) {
            .horizontal => tab_defaults.margin.?.h = 1,
            .vertical => tab_defaults.margin.?.w = 1,
        }
    }

    switch (self.init_options.dir) {
        .horizontal => tab_defaults.gravity_y = 1.0,
        .vertical => tab_defaults.gravity_x = 1.0,
    }

    const options = tab_defaults.themeOverride().override(opts);

    self.tab_button = ButtonWidget.init(@src(), .{}, options);
    self.tab_button.install();
    self.tab_button.processEvents();
    self.tab_button.drawBackground();

    if (self.tab_button.focused() and self.tab_button.data().visible() and self.init_options.draw_focus) {
        const rs = self.tab_button.data().borderRectScale();
        const r = rs.r;
        const cr = self.tab_button.data().options.corner_radiusGet();

        switch (self.init_options.dir) {
            .horizontal => {
                var path: dvui.Path.Builder = .init(dvui.currentWindow().lifo());
                defer path.deinit();

                path.addPoint(r.bottomRight());

                const tr = Point.Physical{ .x = r.x + r.w - cr.y, .y = r.y + cr.y };
                path.addArc(tr, cr.y, math.pi * 2.0, math.pi * 1.5, false);

                const tl = Point.Physical{ .x = r.x + cr.x, .y = r.y + cr.x };
                path.addArc(tl, cr.x, math.pi * 1.5, math.pi, false);

                path.addPoint(r.bottomLeft());

                path.build().stroke(.{ .thickness = 2 * rs.s, .color = dvui.themeGet().focus, .after = true });
            },
            .vertical => {
                var path: dvui.Path.Builder = .init(dvui.currentWindow().lifo());
                defer path.deinit();

                path.addPoint(r.topRight());

                const tl = Point.Physical{ .x = r.x + cr.x, .y = r.y + cr.x };
                path.addArc(tl, cr.x, math.pi * 1.5, math.pi, false);

                const bl = Point.Physical{ .x = r.x + cr.h, .y = r.y + r.h - cr.h };
                path.addArc(bl, cr.h, math.pi, math.pi * 0.5, false);

                path.addPoint(r.bottomRight());

                path.build().stroke(.{ .thickness = 2 * rs.s, .color = dvui.themeGet().focus, .after = true });
            },
        }
    }
    if (self.tab_button.data().accesskit_node()) |ak_node| {
        AccessKit.nodeSetSelected(ak_node, selected);
    }

    return &self.tab_button;
}

pub fn deinit(self: *TabsWidget) void {
    const should_free = self.init_options.was_allocated_on_widget_stack;
    defer if (should_free) dvui.widgetFree(self);
    defer self.* = undefined;
    self.box.deinit();
    self.group.deinit();
    self.scroll.deinit();
}

const Options = dvui.Options;
const Rect = dvui.Rect;
const Point = dvui.Point;

const BoxWidget = dvui.BoxWidget;
const ButtonWidget = dvui.ButtonWidget;
const ScrollAreaWidget = dvui.ScrollAreaWidget;
const AccessKit = dvui.AccessKit;

const std = @import("std");
const math = std.math;
const dvui = @import("../dvui.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
