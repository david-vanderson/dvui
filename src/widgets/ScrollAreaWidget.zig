const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const ScrollInfo = dvui.ScrollInfo;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;
const BoxWidget = dvui.BoxWidget;
const ScrollBarWidget = dvui.ScrollBarWidget;
const ScrollContainerWidget = dvui.ScrollContainerWidget;

const ScrollAreaWidget = @This();

pub var defaults: Options = .{
    .name = "ScrollAreaWidget",
    .role = .scroll_view,
    .background = true,
    // generally the top of a scroll area is against something flat (like
    // window header), and the bottom is against something curved (bottom
    // of a window)
    .corner_radius = Rect{ .x = 0, .y = 0, .w = 5, .h = 5 },
    .style = .window,
};

pub const InitOpts = struct {
    // TODO: Make scroll info and vertical/horizontal mutually exclusive with a union
    scroll_info: ?*ScrollInfo = null,
    vertical: ?ScrollInfo.ScrollMode = null, // .auto is default
    vertical_bar: ScrollInfo.ScrollBarMode = .auto,
    horizontal: ?ScrollInfo.ScrollMode = null, // .none is default
    horizontal_bar: ScrollInfo.ScrollBarMode = .auto,
    focus_id: ?dvui.Id = null, // clicking on a scrollbar will focus this id, or the scroll container if null
    frame_viewport: ?dvui.Point = null,
    lock_visible: bool = false,
    process_events_after: bool = true,
    container: bool = true,

    was_allocated_on_widget_stack: bool = false,
};

hbox: BoxWidget,
vbar: ?ScrollBarWidget = null,
vbar_grab: ?ScrollBarWidget.Grab = null,
vbox: BoxWidget = undefined,
hbar: ?ScrollBarWidget = null,
hbar_grab: ?ScrollBarWidget.Grab = null,
init_opts: InitOpts,
si: *ScrollInfo = undefined,
scroll: ?ScrollContainerWidget = null,

/// It's expected to call this when `self` is `undefined`
pub fn init(self: *ScrollAreaWidget, src: std.builtin.SourceLocation, init_opts: InitOpts, opts: Options) void {
    self.* = .{
        .init_opts = init_opts,
        .hbox = undefined, // set below
    };

    self.hbox.init(src, .{ .dir = .horizontal }, defaults.themeOverride(opts.theme).override(opts));

    if (self.init_opts.scroll_info) |si| {
        self.si = si;
        if (self.init_opts.vertical != null) {
            dvui.log.debug("ScrollAreaWidget {x} init_opts.vertical .{s} overridden by init_opts.scroll_info.vertical .{s}\n", .{ self.hbox.data().id, @tagName(self.init_opts.vertical.?), @tagName(si.vertical) });
        }
        if (self.init_opts.horizontal != null) {
            dvui.log.debug("ScrollAreaWidget {x} init_opts.horizontal .{s} overridden by init_opts.scroll_info.horizontal .{s}\n", .{ self.hbox.data().id, @tagName(self.init_opts.horizontal.?), @tagName(si.horizontal) });
        }
    } else {
        self.si = dvui.dataGetPtrDefault(null, self.hbox.data().id, "_scroll_info", ScrollInfo, .{});

        // outside code might have changed what direction we scroll in
        self.si.vertical = self.init_opts.vertical orelse .auto;
        self.si.horizontal = self.init_opts.horizontal orelse .none;
    }

    self.hbox.drawBackground();

    const focus_target = self.init_opts.focus_id orelse dvui.dataGet(null, self.hbox.data().id, "_scroll_id", dvui.Id);

    const crect = self.hbox.data().contentRect();

    // First assume ScrollContainer gets all our space.
    self.si.viewport.w = crect.w;
    self.si.viewport.h = crect.h;

    // Now adjust if we got insets from last frame.
    if (dvui.dataGet(null, self.hbox.data().id, "_linsets", dvui.Size)) |inset| {
        self.si.viewport.w -= inset.w;
        self.si.viewport.h -= inset.h;
    } else if (!dvui.firstFrame(self.hbox.data().id)) {
        dvui.log.debug("ScrollAreaWidget {x} missing insets from last frame\n", .{self.hbox.data().id});
    }

    // due to floating point inaccuracies, give ourselves a tiny bit of extra wiggle room

    var do_vbar = false;
    var do_hbar = false;
    if (self.si.vertical != .none) {
        if (self.init_opts.vertical_bar == .show or (self.init_opts.vertical_bar.autoAny() and (self.si.virtual_size.h > (self.si.viewport.h + 0.001)))) {
            do_vbar = true;
            if (self.init_opts.vertical_bar != .auto_overlay) {
                self.si.viewport.w -= ScrollBarWidget.defaults.min_sizeGet().w;
            }
        }
    }

    if (self.si.horizontal != .none) {
        if (self.init_opts.horizontal_bar == .show or (self.init_opts.horizontal_bar.autoAny() and (self.si.virtual_size.w > (self.si.viewport.w + 0.001)))) {
            do_hbar = true;
            if (self.init_opts.horizontal_bar != .auto_overlay) {
                self.si.viewport.h -= ScrollBarWidget.defaults.min_sizeGet().h;
            }
        }
    }

    // test for vbar again because hbar might have removed some of our room
    if (!do_vbar and do_hbar and self.si.vertical != .none) {
        if (self.init_opts.vertical_bar.autoAny() and (self.si.virtual_size.h > (self.si.viewport.h + 0.001))) {
            do_vbar = true;
            if (self.init_opts.vertical_bar != .auto_overlay) {
                self.si.viewport.w -= ScrollBarWidget.defaults.min_sizeGet().w;
            }
        }
    }

    if (do_vbar) {
        // do the scrollbars first so that they still appear even if there's not enough space
        const overlay = self.init_opts.vertical_bar == .auto_overlay;
        self.vbar = @as(ScrollBarWidget, undefined); // Must be a non-null value for `.?` bellow
        self.vbar.?.init(
            @src(),
            .{ .scroll_info = self.si, .focus_id = focus_target },
            self.hbox.data().options.strip().override(.{ .gravity_x = if (overlay) 0.999 else 1.0, .expand = .vertical }),
        );
        if (overlay) {
            self.vbar_grab = self.vbar.?.grab();
        } else {
            self.vbar.?.grab().draw();
        }
        self.vbar.?.deinit();
    }

    self.vbox.init(@src(), .{ .dir = .vertical }, self.hbox.data().options.strip().override(.{ .expand = .both, .name = "ScrollAreaWidget vbox" }));
    self.vbox.drawBackground();

    if (do_hbar) {
        const overlay = self.init_opts.horizontal_bar == .auto_overlay;
        self.hbar = @as(ScrollBarWidget, undefined); // Must be a non-null value for `.?` bellow
        self.hbar.?.init(
            @src(),
            .{ .direction = .horizontal, .scroll_info = self.si, .focus_id = focus_target },
            self.hbox.data().options.strip().override(.{ .expand = .horizontal, .gravity_y = if (overlay) 0.999 else 1.0 }),
        );
        if (overlay) {
            self.hbar_grab = self.hbar.?.grab();
        } else {
            self.hbar.?.grab().draw();
        }
        self.hbar.?.deinit();
    }

    if (init_opts.container) {
        const container_opts = self.hbox.data().options.strip().override(.{ .expand = .both });
        self.scroll = @as(ScrollContainerWidget, undefined);
        self.scroll.?.init(@src(), self.si, .{ .scroll_area = self, .lock_visible = self.init_opts.lock_visible, .frame_viewport = self.init_opts.frame_viewport, .process_events_after = self.init_opts.process_events_after }, container_opts);

        self.scroll.?.processEvents();
        self.scroll.?.processVelocity();
    }
}

pub fn data(self: *ScrollAreaWidget) *WidgetData {
    return self.hbox.data();
}

pub fn setContainerRect(self: *ScrollAreaWidget, rect: dvui.Rect) void {
    // only storing the topleft inset, assuming only scrollbars on bottom/right
    dvui.dataSet(null, self.hbox.data().id, "_linsets", dvui.Size{ .w = rect.x, .h = rect.y });
}

pub fn deinit(self: *ScrollAreaWidget) void {
    const should_free = self.init_opts.was_allocated_on_widget_stack;
    defer if (should_free) dvui.widgetFree(self);
    defer self.* = undefined;

    if (self.scroll) |*s| {
        dvui.dataSet(null, self.hbox.data().id, "_scroll_id", s.data().id);
        s.deinit();
    }

    if (self.hbar_grab) |hb| hb.draw();

    self.vbox.deinit();

    if (self.vbar_grab) |vb| vb.draw();

    dvui.dataSet(null, self.hbox.data().id, "_scroll_info", self.si.*);

    self.hbox.deinit();
}

test {
    @import("std").testing.refAllDecls(@This());
}
