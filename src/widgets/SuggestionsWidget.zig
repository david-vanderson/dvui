const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const SuggestionsWidget = @This();

pub var defaults: Options = .{
    .corner_radius = Rect.all(5),
    .padding = Rect.all(6),
    .name = "Suggestions",
};

wd: WidgetData = undefined,
child_rect_union: ?Rect = null,

options: Options = undefined,
text_entry: *dvui.TextEntryWidget = undefined,
closed: bool = false,
drop: ?dvui.FloatingMenuWidget = null,
drop_first_frame: bool = false,
drop_mi: ?dvui.MenuItemWidget = null,
drop_mi_index: usize = 0,
drop_first_mi_id: ?u32 = null,

pub fn init(src: std.builtin.SourceLocation, text_entry: *dvui.TextEntryWidget, opts: Options) SuggestionsWidget {
    var self = SuggestionsWidget{};
    if (text_entry.init_opts.break_lines or text_entry.init_opts.multiline) {
        dvui.log.err("SuggestionsWidget does not support multiline TextEntryWidgets, initialized at [{s}:{d}:{d}]", .{ src.file, src.line, src.column });
    }

    const id = dvui.parentGet().extendId(src, opts.idExtra());
    const rect = dvui.dataGet(null, id, "_rect", Rect);
    const parent_defaults = Options{ .name = "Virtual Parent", .rect = rect orelse .{} };
    self.wd = WidgetData.init(src, .{}, parent_defaults.override(opts));
    self.text_entry = text_entry;
    self.options = defaults.override(opts);
    self.closed = dvui.dataGet(null, self.wd.id, "_closed", bool) orelse false;
    return self;
}

pub fn install(self: *SuggestionsWidget) !void {
    dvui.parentSet(self.widget());
    try self.wd.register();
}

pub fn dropped(self: *SuggestionsWidget) !bool {
    if (self.closed) {
        return false;
    }
    if (self.drop != null) {
        // protect against calling this multiple times
        return true;
    }

    const entry_rect = self.text_entry.data().contentRectScale();
    const start = entry_rect.rectToRectScale(entry_rect.r.justSize()).r.offset(.{ .y = entry_rect.r.h + self.options.marginGet().y });
    self.drop = dvui.FloatingMenuWidget.init(@src(), start, self.options.override(.{
        .min_size_content = .{
            .w = entry_rect.r
                .inset(self.options.paddingGet())
                .inset(self.options.borderGet())
                .inset(self.options.marginGet()).w,
        },
    }));
    var drop = &self.drop.?;
    self.drop_first_frame = dvui.firstFrame(drop.wd.id);

    const cw = dvui.currentWindow();
    if (cw.focused_subwindowId != drop.wd.id and dvui.focusedWidgetId() != self.text_entry.wd.id) {
        // Hide the suggestions when the textfield and suggestions window doesn't have focus
        self.drop = null;
        return false;
    }

    try drop.install();
    if (self.drop_first_frame) {
        // don't take focus away from text_entry when showing the suggestions
        dvui.focusWidget(self.text_entry.wd.id, null, null);
    } else {
        const sw = cw.subwindowCurrent();
        if (cw.focused_subwindowId != sw.id) {
            // reset focus of suggestions to always start at the first item
            sw.focused_widgetId = null;
        } else if (sw.focused_widgetId == null or sw.focused_widgetId == drop.menu.wd.id) {
            // Focus text_entry if we have no suggestion focused
            dvui.focusWidget(self.text_entry.wd.id, null, null);
        }
    }

    // without this, if you trigger the dropdown with the keyboard and then
    // move the mouse, the entries are highlighted but not focused
    drop.menu.submenus_activated = true;

    if (self.drop != null) {
        return true;
    }

    return false;
}

pub fn addSuggestionLabel(self: *SuggestionsWidget, label_text: []const u8) !bool {
    var mi = try self.addSuggestion();
    defer mi.deinit();

    var opts = self.options.strip();
    if (mi.show_active) {
        opts = opts.override(dvui.themeGet().style_accent);
    }

    try dvui.labelNoFmt(@src(), label_text, opts);

    if (mi.activeRect()) |_| {
        return true;
    }

    return false;
}

pub fn addSuggestion(self: *SuggestionsWidget) !*dvui.MenuItemWidget {
    self.drop_mi = dvui.MenuItemWidget.init(@src(), .{}, .{ .id_extra = self.drop_mi_index, .expand = .horizontal });
    try self.drop_mi.?.install();
    self.drop_mi.?.processEvents();
    try self.drop_mi.?.drawBackground(.{});

    if (self.drop_mi_index == 0) {
        self.drop_first_mi_id = self.drop_mi.?.wd.id;
    }
    self.drop_mi_index += 1;

    return &self.drop_mi.?;
}

pub fn close(self: *SuggestionsWidget) void {
    self.closed = true;
    dvui.dataSet(null, self.wd.id, "_closed", self.closed);
}

pub fn open(self: *SuggestionsWidget) void {
    self.closed = false;
    dvui.dataSet(null, self.wd.id, "_closed", self.closed);
}

pub fn chooseText(self: *SuggestionsWidget, text: []const u8) void {
    if (text.len == 0) {
        self.text_entry.len = 0;
        self.text_entry.addNullTerminator();
        return;
    }
    // Set the TextEntryWidgets text data assuming an internal buffer
    dvui.dataSetSlice(null, self.text_entry.wd.id, "_buffer", text);
    self.text_entry.text = dvui.dataGetSlice(null, self.text_entry.wd.id, "_buffer", []u8).?;
    self.text_entry.len = text.len;
    const sel = self.text_entry.textLayout.selectionGet(text.len);
    sel.cursor = text.len;
    dvui.focusWidget(self.text_entry.wd.id, null, null);
}

pub fn widget(self: *SuggestionsWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *SuggestionsWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *SuggestionsWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    const ret = self.wd.parent.rectFor(id, min_size, e, g);
    if (self.child_rect_union) |u| {
        self.child_rect_union = u.unionWith(ret);
    } else {
        self.child_rect_union = ret;
    }
    return ret;
}

pub fn screenRectScale(self: *SuggestionsWidget, rect: Rect) RectScale {
    return self.wd.parent.screenRectScale(rect);
}

pub fn minSizeForChild(self: *SuggestionsWidget, s: Size) void {
    self.wd.parent.minSizeForChild(s);
}

pub fn processEvent(self: *SuggestionsWidget, e: *Event, bubbling: bool) void {
    if (e.evt == .close_popup) {
        e.handled = true;
        self.close();
        dvui.focusWidget(self.text_entry.wd.id, null, e.num);
    }
    if (e.evt == .key and self.text_entry.matchEvent(e)) {
        if ((e.evt.key.action == .down or e.evt.key.action == .repeat) and e.evt.key.matchBind("char_down")) {
            e.handled = true;
            self.open();
            if (self.drop_first_mi_id != null) {
                dvui.focusWidget(self.drop_first_mi_id, null, null);
            } else {
                // The window may not be shown currently, needs one more frame
                dvui.dataSet(null, self.wd.id, "_start_focused", true);
                dvui.refresh(null, @src(), self.wd.id);
            }
        }
        if (e.evt.key.action == .down and e.evt.key.code == .escape) {
            e.handled = true;
            self.close();
            dvui.refresh(null, @src(), self.wd.id);
        }
    }
    if (bubbling and e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *SuggestionsWidget) void {
    const start_focused = dvui.dataGet(null, self.wd.id, "_start_focused", bool) orelse false;
    if (start_focused and self.drop != null) {
        dvui.dataRemove(null, self.wd.id, "_start_focused");
        if (self.drop_first_mi_id) |first_mi_id| {
            // If there is a menu item, focus it
            dvui.focusWidget(first_mi_id, null, null);
        }
    }
    const evts = dvui.events();
    for (evts) |*e| {
        self.processEvent(e, false);
    }

    if (self.drop != null) {
        self.drop.?.deinit();
        self.drop = null;
    }

    if (self.child_rect_union) |u| {
        dvui.dataSet(null, self.wd.id, "_rect", u);
    }
    dvui.parentReset(self.wd.id, self.wd.parent);
}
