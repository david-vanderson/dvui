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
    lock_visible: bool = false,
};

hbox: BoxWidget = undefined,
vbox: BoxWidget = undefined,
init_opts: InitOpts = undefined,
si: *ScrollInfo = undefined,
si_store: ScrollInfo = .{},
scroll: ScrollContainerWidget = undefined,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOpts, opts: Options) ScrollAreaWidget {
    var self = ScrollAreaWidget{};
    self.init_opts = init_opts;
    const options = defaults.override(opts);

    self.hbox = BoxWidget.init(src, .horizontal, false, options);

    return self;
}

pub fn install(self: *ScrollAreaWidget) !void {
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

    try self.hbox.install();
    try self.hbox.drawBackground();

    // the viewport is also set in ScrollContainer but we need it here in
    // case the scroll bar modes are auto
    const crect = self.hbox.wd.contentRect();
    self.si.viewport.w = crect.w;
    self.si.viewport.h = crect.h;

    const focus_target = self.init_opts.focus_id orelse dvui.dataGet(null, self.hbox.data().id, "_scroll_id", dvui.WidgetId);

    // due to floating point inaccuracies, give ourselves a tiny bit of extra wiggle room

    var do_vbar = false;
    var do_hbar = false;
    if (self.si.vertical != .none) {
        if (self.init_opts.vertical_bar == .show or (self.init_opts.vertical_bar == .auto and (self.si.virtual_size.h > (self.si.viewport.h + 0.001)))) {
            do_vbar = true;
            self.si.viewport.w -= ScrollBarWidget.defaults.min_sizeGet().w;
        }
    }

    if (self.si.horizontal != .none) {
        if (self.init_opts.horizontal_bar == .show or (self.init_opts.horizontal_bar == .auto and (self.si.virtual_size.w > (self.si.viewport.w + 0.001)))) {
            do_hbar = true;
            self.si.viewport.h -= ScrollBarWidget.defaults.min_sizeGet().h;
        }
    }

    // test for vbar again because hbar might have removed some of our room
    if (!do_vbar) {
        if (self.si.vertical != .none) {
            if (self.init_opts.vertical_bar == .show or (self.init_opts.vertical_bar == .auto and (self.si.virtual_size.h > (self.si.viewport.h + 0.001)))) {
                do_vbar = true;
                self.si.viewport.w -= ScrollBarWidget.defaults.min_sizeGet().w;
            }
        }
    }

    if (do_vbar) {
        // do the scrollbars first so that they still appear even if there's not enough space
        // - could instead do them in deinit
        var vbar = ScrollBarWidget.init(@src(), .{ .scroll_info = self.si, .focus_id = focus_target }, .{ .gravity_x = 1.0, .expand = .vertical });
        try vbar.install();
        vbar.deinit();
    }

    self.vbox = BoxWidget.init(@src(), .vertical, false, self.hbox.data().options.strip().override(.{ .expand = .both, .name = "ScrollAreaWidget vbox" }));
    try self.vbox.install();
    try self.vbox.drawBackground();

    if (do_hbar) {
        var hbar = ScrollBarWidget.init(@src(), .{ .direction = .horizontal, .scroll_info = self.si, .focus_id = focus_target }, .{ .expand = .horizontal, .gravity_y = 1.0 });
        try hbar.install();
        hbar.deinit();
    }

    const container_opts = self.hbox.data().options.strip().override(.{ .expand = .both });
    self.scroll = ScrollContainerWidget.init(@src(), self.si, container_opts);
    self.scroll.lock_visible = self.init_opts.lock_visible;

    try self.scroll.install();
    self.scroll.processEvents();
    self.scroll.processVelocity();
}

pub fn data(self: *ScrollAreaWidget) *WidgetData {
    return &self.hbox.wd;
}

pub fn deinit(self: *ScrollAreaWidget) void {
    dvui.dataSet(null, self.hbox.data().id, "_scroll_id", self.scroll.wd.id);
    self.scroll.deinit();

    self.vbox.deinit();

    dvui.dataSet(null, self.hbox.data().id, "_scroll_info", self.si.*);

    self.hbox.deinit();
}

test {
    @import("std").testing.refAllDecls(@This());
}
