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
const ScrollAreaWidget = dvui.ScrollAreaWidget;
const TextEntryWidget = dvui.TextEntryWidget;

pub fn InitOptions(comptime T: type) type {
    return struct {
        min: ?T,
        max: ?T,
    };
}

pub fn NumberEntryWidget(comptime T: type) type {
    return struct {
        wd: WidgetData = undefined,
        buffer: [64]u8 = .{0} ** 64,
        text_box: *dvui.TextEntryWidget = undefined,
        T: T,
        init_opts: InitOptions(T),

        pub fn drawBackground(self: *@This()) !void {
            try self.wd.borderAndBackground(.{});
        }

        pub fn widget(self: *@This()) Widget {
            return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
        }

        pub fn data(self: *@This()) *WidgetData {
            return &self.wd;
        }

        pub fn rectFor(self: *@This(), id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
            return dvui.placeIn(self.wd.contentRect().justSize(), dvui.minSize(id, min_size), e, g);
        }

        pub fn screenRectScale(self: *@This(), rect: Rect) RectScale {
            return self.wd.contentRectScale().rectToRectScale(rect);
        }

        pub fn minSizeForChild(self: *@This(), s: Size) void {
            self.wd.minSizeMax(self.wd.padSize(s));
        }

        pub fn processEvent(self: *@This(), e: *Event, bubbling: bool) void {
            _ = bubbling;
            if (e.bubbleable()) {
                self.wd.parent.processEvent(e, true);
            }
        }

pub fn install(self: *TextEntryWidget) !void {
    try self.wd.register();

    if (self.wd.visible()) {
        try dvui.tabIndexSet(self.wd.id, self.wd.options.tab_index);
    }

    dvui.parentSet(self.widget());

    try self.wd.borderAndBackground(.{});

    self.prevClip = dvui.clip(self.wd.borderRectScale().r);
    const borderClip = dvui.clipGet();

    self.scroll = ScrollAreaWidget.init(@src(), .{
        .vertical = if (self.init_opts.scroll_vertical orelse self.init_opts.multiline) .auto else .none,
        .vertical_bar = self.init_opts.scroll_vertical_bar orelse .auto,
        .horizontal = if (self.init_opts.scroll_horizontal orelse true) .auto else .none,
        .horizontal_bar = self.init_opts.scroll_horizontal_bar orelse (if (self.init_opts.multiline) .auto else .hide),
        .focus_id = self.wd.id,
    }, self.wd.options.strip().override(.{ .expand = .both }));
    // scrollbars process mouse events here
    try self.scroll.install();

    self.scrollClip = dvui.clipGet();

    self.textLayout = TextLayoutWidget.init(@src(), .{ .break_lines = self.init_opts.break_lines, .touch_edit_just_focused = false }, self.wd.options.strip().override(.{ .expand = .both, .padding = self.padding, .min_size_content = .{} }));
    try self.textLayout.install(.{ .focused = self.wd.id == dvui.focusedWidgetId(), .show_touch_draggables = (self.len > 0) });
    self.textClip = dvui.clipGet();

    if (try self.textLayout.touchEditing()) |floating_widget| {
        defer floating_widget.deinit();

        var hbox = try dvui.box(@src(), .horizontal, .{
            .corner_radius = dvui.ButtonWidget.defaults.corner_radiusGet(),
            .background = true,
            .border = dvui.Rect.all(1),
        });
        defer hbox.deinit();

        if (try dvui.buttonIcon(@src(), "paste", dvui.entypo.clipboard, .{}, .{ .min_size_content = .{ .h = 20 }, .margin = Rect.all(2) })) {
            self.paste();
        }

        if (try dvui.buttonIcon(@src(), "select all", dvui.entypo.swap, .{}, .{ .min_size_content = .{ .h = 20 }, .margin = Rect.all(2) })) {
            self.textLayout.selection.selectAll();
        }

        if (try dvui.buttonIcon(@src(), "cut", dvui.entypo.scissors, .{}, .{ .min_size_content = .{ .h = 20 }, .margin = Rect.all(2) })) {
            self.cut();
        }

        if (try dvui.buttonIcon(@src(), "copy", dvui.entypo.copy, .{}, .{ .min_size_content = .{ .h = 20 }, .margin = Rect.all(2) })) {
            self.textLayout.copy();
        }
    }

    // don't call textLayout.processEvents here, we forward events inside our own processEvents

    // textLayout is maintaining the selection for us, but if the text
    // changed, we need to update the selection to be valid before we
    // process any events
    var sel = self.textLayout.selection;
    sel.start = dvui.findUtf8Start(self.init_opts.text[0..self.len], sel.start);
    sel.cursor = dvui.findUtf8Start(self.init_opts.text[0..self.len], sel.cursor);
    sel.end = dvui.findUtf8Start(self.init_opts.text[0..self.len], sel.end);

    // textLayout clips to its content, but we need to get events out to our border
    dvui.clipSet(borderClip);
}

    };
}

pub fn init(src: std.builtin.SourceLocation, comptime T: type, init_opts: InitOptions, options: Options) !NumberEntryWidget(T) {
    var self = NumberEntryWidget{ .init_opts = init_opts, .T = T };
    self.wd = WidgetData.init(src, .{}, options);

    const text_init_opts: TextEntryWidget.InitOptions = .{};

    self.text_box = TextEntryWidget.init(src, text_init_opts, options);

    return self;
}

