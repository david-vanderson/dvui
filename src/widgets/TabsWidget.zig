pub const TabsWidget = @This();

init_options: InitOptions,
scroll: ScrollAreaWidget,
/// SAFETY: Set in `install`
box: BoxWidget = undefined,
tab_index: usize = 0,
/// SAFETY: Set in `addTab`
tab_button: ButtonWidget = undefined,

pub var defaults: Options = .{
    .background = false,
    .corner_radius = Rect{},
    .name = "Tabs",
};

pub const InitOptions = struct {
    dir: dvui.enums.Direction = .horizontal,
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

    const margin: Rect = switch (self.init_options.dir) {
        .horizontal => .{ .y = 2 },
        .vertical => .{ .x = 2 },
    };
    self.box = BoxWidget.init(@src(), .{ .dir = self.init_options.dir }, .{ .margin = margin });
    self.box.install();

    var r = self.scroll.data().contentRectScale().r;
    switch (self.init_options.dir) {
        .horizontal => {
            if (dvui.currentWindow().snap_to_pixels) {
                r.x += 0.5;
                r.w -= 1.0;
                r.y = @floor(r.y) - 0.5;
            }
            dvui.Path.stroke(.{ .points = &.{ r.bottomLeft(), r.bottomRight() } }, .{ .thickness = 1, .color = dvui.themeGet().color_border });
        },
        .vertical => {
            if (dvui.currentWindow().snap_to_pixels) {
                r.y += 0.5;
                r.h -= 1.0;
                r.x = @floor(r.x) - 0.5;
            }
            dvui.Path.stroke(.{ .points = &.{ r.topRight(), r.bottomRight() } }, .{ .thickness = 1, .color = dvui.themeGet().color_border });
        },
    }
}

pub fn addTabLabel(self: *TabsWidget, selected: bool, text: []const u8) bool {
    var tab = self.addTab(selected, .{});
    defer tab.deinit();

    var label_opts = tab.data().options.strip();
    if (dvui.captured(tab.data().id)) {
        label_opts.color_text = .{ .name = .text_press };
    }

    dvui.labelNoFmt(@src(), text, .{}, label_opts);

    return tab.clicked();
}

pub fn addTab(self: *TabsWidget, selected: bool, opts: Options) *ButtonWidget {
    var tab_defaults: Options = switch (self.init_options.dir) {
        .horizontal => .{ .id_extra = self.tab_index, .background = true, .corner_radius = .{ .x = 5, .y = 5 }, .margin = .{ .x = 2, .w = 2 } },
        .vertical => .{ .id_extra = self.tab_index, .background = true, .corner_radius = .{ .x = 5, .h = 5 }, .margin = .{ .y = 2, .h = 2 } },
    };

    self.tab_index += 1;

    if (selected) {
        tab_defaults.font_style = .heading;
        tab_defaults.color_fill = .{ .name = .fill_window };
        tab_defaults.border = switch (self.init_options.dir) {
            .horizontal => .{ .x = 1, .y = 1, .w = 1 },
            .vertical => .{ .x = 1, .y = 1, .h = 1 },
        };
    } else {
        tab_defaults.color_fill = .{ .name = .fill_control };
        switch (self.init_options.dir) {
            .horizontal => tab_defaults.margin.?.h = 1,
            .vertical => tab_defaults.margin.?.w = 1,
        }
    }

    switch (self.init_options.dir) {
        .horizontal => tab_defaults.gravity_y = 1.0,
        .vertical => tab_defaults.gravity_x = 1.0,
    }

    const options = tab_defaults.override(opts);

    self.tab_button = ButtonWidget.init(@src(), .{}, options);
    self.tab_button.install();
    self.tab_button.processEvents();
    self.tab_button.drawBackground();

    if (self.tab_button.focused() and self.tab_button.data().visible()) {
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

                path.build().stroke(.{ .thickness = 2 * rs.s, .color = dvui.themeGet().color_accent, .after = true });
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

                path.build().stroke(.{ .thickness = 2 * rs.s, .color = dvui.themeGet().color_accent, .after = true });
            },
        }
    }

    return &self.tab_button;
}

pub fn deinit(self: *TabsWidget) void {
    defer dvui.widgetFree(self);
    self.box.deinit();
    self.scroll.deinit();
    self.* = undefined;
}

const Options = dvui.Options;
const Rect = dvui.Rect;
const Point = dvui.Point;

const BoxWidget = dvui.BoxWidget;
const ButtonWidget = dvui.ButtonWidget;
const ScrollAreaWidget = dvui.ScrollAreaWidget;

const std = @import("std");
const math = std.math;
const dvui = @import("../dvui.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
