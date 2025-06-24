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
    .background = true,
    // generally the top of a scroll area is against something flat (like
    // window header), and the bottom is against something curved (bottom
    // of a window)
    .corner_radius = Rect{ .x = 0, .y = 0, .w = 5, .h = 5 },
};

pub const InitOpts = struct {
    scroll_info: ?*ScrollInfo = null,
    vertical: ?ScrollInfo.ScrollMode = null, // .auto is default
    vertical_bar: ScrollInfo.ScrollBarMode = .auto,
    horizontal: ?ScrollInfo.ScrollMode = null, // .none is default
    horizontal_bar: ScrollInfo.ScrollBarMode = .auto,
    focus_id: ?dvui.WidgetId = null, // clicking on a scrollbar will focus this id, or the scroll container if null
    frame_viewport: ?dvui.Point = null,
    lock_visible: bool = false,
    process_events_after: bool = true,
};

hbox: BoxWidget = undefined,
vbar: ?ScrollBarWidget = null,
vbar_grab: ?ScrollBarWidget.Grab = null,
vbox: BoxWidget = undefined,
hbar: ?ScrollBarWidget = null,
hbar_grab: ?ScrollBarWidget.Grab = null,
init_opts: InitOpts = undefined,
si: *ScrollInfo = undefined,
si_store: ScrollInfo = .{},
scroll: ?ScrollContainerWidget = null,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOpts, opts: Options) ScrollAreaWidget {
    var self = ScrollAreaWidget{};
    self.init_opts = init_opts;
    const options = defaults.override(opts);

    self.hbox = BoxWidget.init(src, .{ .dir = .horizontal }, options);

    return self;
}

pub fn install(self: *ScrollAreaWidget) void {
    self.installScrollBars();

    const container_opts = self.hbox.data().options.strip().override(.{ .expand = .both });
    self.scroll = ScrollContainerWidget.init(@src(), self.si, .{ .lock_visible = self.init_opts.lock_visible, .frame_viewport = self.init_opts.frame_viewport, .process_events_after = self.init_opts.process_events_after }, container_opts);

    self.scroll.?.install();
    self.scroll.?.processEvents();
    self.scroll.?.processVelocity();
}

pub fn installScrollBars(self: *ScrollAreaWidget) void {
    if (self.init_opts.scroll_info) |si| {
        self.si = si;
        if (self.init_opts.vertical != null) {
            dvui.log.debug("ScrollAreaWidget {x} init_opts.vertical .{s} overridden by init_opts.scroll_info.vertical .{s}\n", .{ self.hbox.wd.id, @tagName(self.init_opts.vertical.?), @tagName(si.vertical) });
        }
        if (self.init_opts.horizontal != null) {
            dvui.log.debug("ScrollAreaWidget {x} init_opts.horizontal .{s} overridden by init_opts.scroll_info.horizontal .{s}\n", .{ self.hbox.wd.id, @tagName(self.init_opts.horizontal.?), @tagName(si.horizontal) });
        }
    } else if (dvui.dataGet(null, self.hbox.data().id, "_scroll_info", ScrollInfo)) |si| {
        self.si_store = si;
        self.si = &self.si_store; // can't take pointer to self in init, so we do it in install

        // outside code might have changed what direction we scroll in
        self.si.vertical = self.init_opts.vertical orelse .auto;
        self.si.horizontal = self.init_opts.horizontal orelse .none;
    } else {
        self.si = &self.si_store; // can't take pointer to self in init, so we do it in install
        self.si.vertical = self.init_opts.vertical orelse .auto;
        self.si.horizontal = self.init_opts.horizontal orelse .none;
    }

    self.hbox.install();
    self.hbox.drawBackground();

    const focus_target = self.init_opts.focus_id orelse dvui.dataGet(null, self.hbox.data().id, "_scroll_id", dvui.WidgetId);

    // due to floating point inaccuracies, give ourselves a tiny bit of extra wiggle room

    var do_vbar = false;
    var do_hbar = false;
    if (self.si.vertical != .none) {
        if (self.init_opts.vertical_bar == .show or (self.init_opts.vertical_bar.autoAny() and (self.si.virtual_size.h > (self.si.viewport.h + 0.001)))) {
            do_vbar = true;
        }
    }

    if (self.si.horizontal != .none) {
        if (self.init_opts.horizontal_bar == .show or (self.init_opts.horizontal_bar.autoAny() and (self.si.virtual_size.w > (self.si.viewport.w + 0.001)))) {
            do_hbar = true;
        }
    }

    // test for vbar again because hbar might have removed some of our room
    if (!do_vbar) {
        if (self.si.vertical != .none) {
            if (self.init_opts.vertical_bar == .show or (self.init_opts.vertical_bar.autoAny() and (self.si.virtual_size.h > (self.si.viewport.h + 0.001)))) {
                do_vbar = true;
            }
        }
    }

    if (do_vbar) {
        // do the scrollbars first so that they still appear even if there's not enough space
        const overlay = self.init_opts.vertical_bar == .auto_overlay;
        self.vbar = ScrollBarWidget.init(@src(), .{
            .scroll_info = self.si,
            .focus_id = focus_target,
        }, .{ .gravity_x = if (overlay) 0.999 else 1.0, .expand = .vertical });
        self.vbar.?.install();
        if (overlay) {
            self.vbar_grab = self.vbar.?.grab();
        } else {
            self.vbar.?.grab().draw();
        }
        self.vbar.?.deinit();
    }

    self.vbox = BoxWidget.init(@src(), .{ .dir = .vertical }, self.hbox.data().options.strip().override(.{ .expand = .both, .name = "ScrollAreaWidget vbox" }));
    self.vbox.install();
    self.vbox.drawBackground();

    if (do_hbar) {
        const overlay = self.init_opts.horizontal_bar == .auto_overlay;
        self.hbar = ScrollBarWidget.init(@src(), .{ .direction = .horizontal, .scroll_info = self.si, .focus_id = focus_target }, .{ .expand = .horizontal, .gravity_y = if (overlay) 0.999 else 1.0 });
        self.hbar.?.install();
        if (overlay) {
            self.hbar_grab = self.hbar.?.grab();
        } else {
            self.hbar.?.grab().draw();
        }
        self.hbar.?.deinit();
    }
}

pub fn data(self: *ScrollAreaWidget) *WidgetData {
    return &self.hbox.wd;
}

pub fn deinit(self: *ScrollAreaWidget) void {
    defer dvui.widgetFree(self);

    if (self.scroll) |*s| {
        dvui.dataSet(null, self.hbox.data().id, "_scroll_id", s.data().id);
        s.deinit();
    }

    if (self.hbar_grab) |hb| hb.draw();

    self.vbox.deinit();

    if (self.vbar_grab) |vb| vb.draw();

    dvui.dataSet(null, self.hbox.data().id, "_scroll_info", self.si.*);

    self.hbox.deinit();
    self.* = undefined;
}

test {
    @import("std").testing.refAllDecls(@This());
}
