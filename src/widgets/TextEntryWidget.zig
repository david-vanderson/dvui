const builtin = @import("builtin");
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
const TextLayoutWidget = dvui.TextLayoutWidget;

const TextEntryWidget = @This();

pub var defaults: Options = .{
    .name = "TextEntry",
    .role = .text_input, // can change to multiline in init
    .margin = Rect.all(4),
    .corner_radius = Rect.all(5),
    .border = Rect.all(1),
    .padding = Rect.all(6),
    .background = true,
    .style = .content,
    // min_size_content/max_size_content is calculated in init()
};

const realloc_bin_size = 100;

pub const InitOptions = struct {
    pub const TextOption = union(enum) {
        /// Use this slice of bytes, cannot add more.
        buffer: []u8,

        /// Use and grow with realloc and shrink with resize as needed.
        buffer_dynamic: struct {
            backing: *[]u8,
            allocator: std.mem.Allocator,
            limit: usize = 10_000,
        },

        /// Use internal buffer up to limit.
        /// - use getText() to get contents.
        internal: struct {
            limit: usize = 10_000,
        },
    };

    text: TextOption = .{ .internal = .{} },
    /// Faded text shown when the textEntry is empty
    placeholder: ?[]const u8 = null,

    /// If true, assume text (and text height) is the same (excepting edits we
    /// do internally) as we saw last frame and only process what is needed for
    /// visibility (and copy).
    cache_layout: bool = false,

    break_lines: bool = false,
    kerning: ?bool = null,
    scroll_vertical: ?bool = null, // default is value of multiline
    scroll_vertical_bar: ?ScrollInfo.ScrollBarMode = null, // default .auto
    scroll_horizontal: ?bool = null, // default true
    scroll_horizontal_bar: ?ScrollInfo.ScrollBarMode = null, // default .auto if multiline, .hide if not

    // must be a single utf8 character
    password_char: ?[]const u8 = null,
    multiline: bool = false,
};

wd: WidgetData,
/// SAFETY: Set in `install`
prevClip: Rect.Physical = undefined,
/// SAFETY: Set in `install`
scroll: ScrollAreaWidget = undefined,
scroll_init_opts: ScrollAreaWidget.InitOpts,
/// SAFETY: Set in `install`
scrollClip: Rect.Physical = undefined,
/// SAFETY: Set in `install`
textLayout: TextLayoutWidget = undefined,
/// SAFETY: Set in `install`
textClip: Rect.Physical = undefined,
padding: Rect,

init_opts: InitOptions,
text: []u8,
len: usize,
enter_pressed: bool = false, // not valid if multiline
text_changed: bool = false,

// see textChanged()
text_changed_start: usize = std.math.maxInt(usize),
text_changed_end: usize = 0, // index of bytes before edits (so matches previous frame)
text_changed_added: i64 = 0, // bytes added

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) TextEntryWidget {
    var scroll_init_opts = ScrollAreaWidget.InitOpts{
        .vertical = if (init_opts.scroll_vertical orelse init_opts.multiline) .auto else .none,
        .vertical_bar = init_opts.scroll_vertical_bar orelse .auto,
        .horizontal = if (init_opts.scroll_horizontal orelse true) .auto else .none,
        .horizontal_bar = init_opts.scroll_horizontal_bar orelse (if (init_opts.multiline) .auto else .hide),
    };

    var options = defaults.themeOverride().min_sizeM(14, 1);

    if (init_opts.password_char != null) {
        options.role = .password_input;
    } else if (init_opts.multiline) {
        options.role = .multiline_text_input;
    }

    options = options.override(opts);

    if (options.max_size_content == null) {
        // max size not given, so default to the same as min size for direction
        // we can scroll in
        const ms = options.min_size_contentGet();
        const maxw = if (scroll_init_opts.horizontal == .auto) ms.w else dvui.max_float_safe;
        const maxh = if (scroll_init_opts.vertical == .auto) ms.h else dvui.max_float_safe;
        options = options.override(.{ .max_size_content = .{ .w = maxw, .h = maxh } });
    }

    // padding is interpreted as the padding for the TextLayoutWidget, but
    // we also need to add it to content size because TextLayoutWidget is
    // inside the scroll area
    const padding = options.paddingGet();
    options.padding = null;
    options.min_size_content.?.w += padding.x + padding.w;
    options.min_size_content.?.h += padding.y + padding.h;
    options.max_size_content.?.w += padding.x + padding.w;
    options.max_size_content.?.h += padding.y + padding.h;

    const wd = WidgetData.init(src, .{}, options);
    scroll_init_opts.focus_id = wd.id;

    const text = switch (init_opts.text) {
        .buffer => |b| b,
        .buffer_dynamic => |b| b.backing.*,
        .internal => dvui.dataGetSliceDefault(null, wd.id, "_buffer", []u8, &.{}),
    };
    const len_byte = std.mem.indexOfScalar(u8, text, 0) orelse text.len;
    const len_utf8_boundary = dvui.findUtf8Start(text[0..len_byte], len_byte);

    return .{
        .wd = wd,
        .scroll_init_opts = scroll_init_opts,
        .padding = padding,
        .init_opts = init_opts,
        .text = text,
        .len = len_utf8_boundary,
    };
}

pub fn install(self: *TextEntryWidget) void {
    self.data().register();

    dvui.tabIndexSet(self.data().id, self.data().options.tab_index);

    dvui.parentSet(self.widget());

    self.data().borderAndBackground(.{});

    self.prevClip = dvui.clip(self.data().borderRectScale().r);
    const borderClip = dvui.clipGet();

    // We do this dance with last_focused_id_this_frame so scroll will process
    // key events we skip (like page up/down). Normally it would not (text
    // entry is not a child of scroll). So with this we make scroll think that
    // text entry ran as a child.
    const focused = (self.data().id == dvui.lastFocusedIdInFrame());
    if (focused) dvui.currentWindow().last_focused_id_this_frame = .zero;

    self.scroll = ScrollAreaWidget.init(@src(), self.scroll_init_opts, self.data().options.strip().override(.{ .role = .none, .expand = .both }));

    // scrollbars process mouse events here
    self.scroll.install();

    if (focused) dvui.currentWindow().last_focused_id_this_frame = self.data().id;

    self.scrollClip = dvui.clipGet();

    self.textLayout = TextLayoutWidget.init(@src(), .{ .break_lines = self.init_opts.break_lines, .kerning = self.init_opts.kerning, .touch_edit_just_focused = false, .cache_layout = self.init_opts.cache_layout }, self.data().options.strip().override(.{ .role = .none, .expand = .both, .padding = self.padding }));

    // if textLayout forced cache_layout to false, we need to honor that
    self.init_opts.cache_layout = self.textLayout.cache_layout;

    self.textLayout.install(.{ .focused = self.data().id == dvui.focusedWidgetId(), .show_touch_draggables = (self.len > 0) });
    self.textClip = dvui.clipGet();

    if (self.len == 0) {
        if (self.init_opts.placeholder) |placeholder| {
            self.textLayout.addText(placeholder, .{ .color_text = self.textLayout.data().options.color(.text).opacity(0.65) });
        }
    }

    if (self.textLayout.touchEditing()) |floating_widget| {
        defer floating_widget.deinit();

        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{
            .corner_radius = dvui.ButtonWidget.defaults.themeOverride().corner_radiusGet(),
            .background = true,
            .border = dvui.Rect.all(1),
        });
        defer hbox.deinit();

        if (dvui.buttonIcon(@src(), "paste", dvui.entypo.clipboard, .{}, .{}, .{
            .min_size_content = .{ .h = 20 },
            .margin = Rect.all(2),
        })) {
            self.paste();
        }

        if (dvui.buttonIcon(@src(), "select all", dvui.entypo.swap, .{}, .{}, .{
            .min_size_content = .{ .h = 20 },
            .margin = Rect.all(2),
        })) {
            self.textLayout.selection.selectAll();
        }

        if (dvui.buttonIcon(@src(), "cut", dvui.entypo.scissors, .{}, .{}, .{
            .min_size_content = .{ .h = 20 },
            .margin = Rect.all(2),
        })) {
            self.cut();
        }

        if (dvui.buttonIcon(@src(), "copy", dvui.entypo.copy, .{}, .{}, .{
            .min_size_content = .{ .h = 20 },
            .margin = Rect.all(2),
        })) {
            self.textLayout.copy();
        }
    }

    // don't call textLayout.processEvents here, we forward events inside our own processEvents

    // textLayout is maintaining the selection for us, but if the text
    // changed, we need to update the selection to be valid before we
    // process any events
    var sel = self.textLayout.selection;
    sel.start = dvui.findUtf8Start(self.text[0..self.len], sel.start);
    sel.cursor = dvui.findUtf8Start(self.text[0..self.len], sel.cursor);
    sel.end = dvui.findUtf8Start(self.text[0..self.len], sel.end);

    // textLayout clips to its content, but we need to get events out to our border
    dvui.clipSet(borderClip);
    if (self.data().accesskit_node()) |ak_node| {
        dvui.AccessKit.nodeAddAction(ak_node, dvui.AccessKit.Action.focus);
        dvui.AccessKit.nodeAddAction(ak_node, dvui.AccessKit.Action.set_value);
        if (self.data().options.role != .password_input) {
            const str = dvui.currentWindow().arena().dupeZ(u8, self.text) catch "";
            defer dvui.currentWindow().arena().free(str);
            // TODO: We don't want to always push large amounts of text each frame. So we either need to look at pushing
            // only chunks of text, ot only pushing when the text has actually changed since last frame.
            dvui.AccessKit.nodeSetValue(ak_node, str);
        }
    }
}

pub fn matchEvent(self: *TextEntryWidget, e: *Event) bool {
    // textLayout could be passively listening to events in matchEvent, so
    // don't short circuit
    const match1 = dvui.eventMatchSimple(e, self.data());
    const match2 = self.scroll.scroll.?.matchEvent(e);
    const match3 = self.textLayout.matchEvent(e);
    return match1 or match2 or match3;
}

pub fn processEvents(self: *TextEntryWidget) void {
    const evts = dvui.events();
    for (evts) |*e| {
        if (!self.matchEvent(e))
            continue;

        self.processEvent(e);
    }
}

pub fn draw(self: *TextEntryWidget) void {
    const focused = (self.data().id == dvui.focusedWidgetId());

    if (focused) {
        dvui.wantTextInput(self.data().borderRectScale().r.toNatural());
    }

    // set clip back to what textLayout had, so we don't draw over the scrollbars
    dvui.clipSet(self.textClip);

    if (self.init_opts.password_char) |pc| {
        // adjust selection for obfuscation
        var count: usize = 0;
        var bytes: usize = 0;
        var sel = self.textLayout.selection;
        var sstart: ?usize = null;
        var scursor: ?usize = null;
        var send: ?usize = null;
        var utf8it = (std.unicode.Utf8View.initUnchecked(self.text[0..self.len])).iterator();
        while (utf8it.nextCodepoint()) |codepoint| {
            if (sstart == null and sel.start == bytes) sstart = count * pc.len;
            if (scursor == null and sel.cursor == bytes) scursor = count * pc.len;
            if (send == null and sel.end == bytes) send = count * pc.len;
            count += 1;
            bytes += std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
        } else {
            if (sstart == null and sel.start >= bytes) sstart = count * pc.len;
            if (scursor == null and sel.cursor >= bytes) scursor = count * pc.len;
            if (send == null and sel.end >= bytes) send = count * pc.len;
        }
        sel.start = sstart.?;
        sel.cursor = scursor.?;
        sel.end = send.?;
        const password_str: ?[]u8 = dvui.currentWindow().lifo().alloc(u8, count * pc.len) catch null;
        if (password_str) |pstr| {
            defer dvui.currentWindow().lifo().free(pstr);
            for (0..count) |i| {
                for (0..pc.len) |pci| {
                    pstr[i * pc.len + pci] = pc[pci];
                }
            }
            self.textLayout.addText(pstr, self.data().options.strip());
        } else {
            dvui.log.warn("Could not allocate password_str, falling back to one single password_str", .{});
            self.textLayout.addText(pc, self.data().options.strip());
        }
    } else {
        if (self.init_opts.cache_layout) {
            self.textLayout.cache_layout_bytes = self.textLayout.bytesNeeded(
                self.text_changed_start,
                self.text_changed_end,
                self.text_changed_added,
            );
        }
        self.textLayout.addText(self.text[0..self.len], self.data().options.strip());
    }

    self.textLayout.addTextDone(self.data().options.strip());

    if (self.init_opts.password_char) |pc| {
        // reset selection
        var count: usize = 0;
        var bytes: usize = 0;
        var sel = self.textLayout.selection;
        var sstart: ?usize = null;
        var scursor: ?usize = null;
        var send: ?usize = null;
        // NOTE: We assume that all text in the area it valid utf8, loop with exit early on invalid utf8
        var utf8it = (std.unicode.Utf8View.initUnchecked(self.text[0..self.len])).iterator();
        while (utf8it.nextCodepoint()) |codepoint| {
            if (sstart == null and sel.start == count * pc.len) sstart = bytes;
            if (scursor == null and sel.cursor == count * pc.len) scursor = bytes;
            if (send == null and sel.end == count * pc.len) send = bytes;
            count += 1;
            bytes += std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
        } else {
            if (sstart == null and sel.start >= count * pc.len) sstart = bytes;
            if (scursor == null and sel.cursor >= count * pc.len) scursor = bytes;
            if (send == null and sel.end >= count * pc.len) send = bytes;
        }
        sel.start = sstart.?;
        sel.cursor = scursor.?;
        sel.end = send.?;
    }

    if (focused) {
        self.drawCursor();
    }

    dvui.clipSet(self.prevClip);

    if (focused) {
        self.data().focusBorder();
    }
}

pub fn drawCursor(self: *TextEntryWidget) void {
    var sel = self.textLayout.selectionGet(self.len);
    if (sel.empty()) {
        // the cursor can be slightly outside the textLayout clip
        dvui.clipSet(self.scrollClip);

        var crect = self.textLayout.cursor_rect.plus(.{ .x = -1 });
        crect.w = 2;
        self.textLayout.screenRectScale(crect).r.fill(.{}, .{ .color = dvui.themeGet().focus, .fade = 1.0 });
    }
}

pub fn widget(self: *TextEntryWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *TextEntryWidget) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *TextEntryWidget, id: dvui.Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.data().contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *TextEntryWidget, rect: Rect) RectScale {
    return self.data().contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *TextEntryWidget, s: Size) void {
    self.data().minSizeMax(self.data().options.padSize(s));
}

pub fn textChangedRemoved(self: *TextEntryWidget, start: usize, end: usize) void {
    self.textChanged(start, end, @as(i64, @intCast(start)) - @as(i64, @intCast(end)));
}

// Inserting text is at a single point in the previous frame's indexing.
pub fn textChangedAdded(self: *TextEntryWidget, pos: usize, added: usize) void {
    self.textChanged(pos, pos, @intCast(added));
}

// Only needed when cache_layout is true.  We are maintaining an interval of
// bytes from last frame plus a total number added (might be negative) in that
// interval.  This is sent to textLayout so it will process at least this
// interval (plus whatever is visible).
pub fn textChanged(self: *TextEntryWidget, start: usize, end: usize, added: i64) void {
    self.text_changed = true;
    if (end > self.text_changed_start) {
        // end is in current bytes, so we update it to previous frame's indexing
        var end_old: usize = undefined;
        if (self.text_changed_added >= 0) {
            end_old = end - @as(usize, @intCast(self.text_changed_added));
        } else {
            end_old = end + @as(usize, @intCast(-self.text_changed_added));
        }
        // This assumes that the current update happens after (in bytes) all
        // previous updates.  This is not exact, but will always give an
        // interval that includes all the updates.
        self.text_changed_end = @max(self.text_changed_end, end_old);
    } else {
        // before previous updates then indexing is the same
        self.text_changed_end = @max(self.text_changed_end, end);
    }

    // if we are before the previous updates then the indexing is the same
    self.text_changed_start = @min(self.text_changed_start, start);
    self.text_changed_added += added;

    //std.debug.print("textChanged {d} {d} {d}\n", .{ self.text_changed_start, self.text_changed_end, self.text_changed_added });
}

pub fn textSet(self: *TextEntryWidget, text: []const u8, selected: bool) void {
    self.textLayout.selection.selectAll();
    self.textTyped(text, selected);
}

pub fn textTyped(self: *TextEntryWidget, new: []const u8, selected: bool) void {
    // strip out carriage returns, which we get from copy/paste on windows
    if (std.mem.indexOfScalar(u8, new, '\r')) |idx| {
        self.textTyped(new[0..idx], selected);
        self.textTyped(new[idx + 1 ..], selected);
        return;
    }

    var sel = self.textLayout.selectionGet(self.len);
    if (!sel.empty()) {
        // delete selection
        self.textChangedRemoved(sel.start, sel.end);
        std.mem.copyForwards(u8, self.text[sel.start..], self.text[sel.end..self.len]);
        self.len -= (sel.end - sel.start);
        sel.end = sel.start;
        sel.cursor = sel.start;
    }

    const space_left = self.text.len - self.len;
    if (space_left < new.len) {
        var new_size = realloc_bin_size * (@divTrunc(self.len + new.len, realloc_bin_size) + 1);
        switch (self.init_opts.text) {
            .buffer => {},
            .buffer_dynamic => |b| {
                new_size = @min(new_size, b.limit);
                b.backing.* = b.allocator.realloc(self.text, new_size) catch |err| blk: {
                    dvui.logError(@src(), err, "{x} TextEntryWidget.textTyped failed to realloc backing (current size {d}, new size {d})", .{ self.data().id, self.text.len, new_size });
                    break :blk b.backing.*;
                };
                self.text = b.backing.*;
            },
            .internal => |i| {
                new_size = @min(new_size, i.limit);
                // If we are the same size then there is no work to do
                // This is important because same sized data allocations will be reused
                if (new_size != self.text.len) {
                    // NOTE: Using prev_text is safe because data is trashed and stays valid until the end of the frame
                    const prev_text = self.text;
                    dvui.dataSetSliceCopies(null, self.data().id, "_buffer", &[_]u8{0}, new_size);
                    self.text = dvui.dataGetSlice(null, self.data().id, "_buffer", []u8).?;
                    const min_len = @min(prev_text.len, self.text.len);
                    if (self.text.ptr != prev_text.ptr) {
                        @memcpy(self.text[0..min_len], prev_text[0..min_len]);
                    }
                }
            },
        }
    }
    var new_len = @min(new.len, self.text.len - self.len);

    // find start of last utf8 char
    var last: usize = new_len -| 1;
    while (last < new_len and new[last] & 0xc0 == 0x80) {
        last -|= 1;
    }

    // if the last utf8 char can't fit, don't include it
    if (last < new_len) {
        const utf8_size = std.unicode.utf8ByteSequenceLength(new[last]) catch 0;
        if (utf8_size != (new_len - last)) {
            new_len = last;
        }
    }

    // make room if we can
    if (new_len > 0 and sel.cursor + new_len < self.text.len) {
        std.mem.copyBackwards(u8, self.text[sel.cursor + new_len ..], self.text[sel.cursor..self.len]);
    }

    if (new_len > 0) {
        self.textChangedAdded(sel.cursor, new_len);
    }

    // update our len and maintain 0 termination if possible
    self.len += new_len;
    self.addNullTerminator();

    // insert
    std.mem.copyForwards(u8, self.text[sel.cursor..], new[0..new_len]);
    if (selected) {
        sel.start = sel.cursor;
        sel.cursor += new_len;
        sel.end = sel.cursor;
    } else {
        sel.cursor += new_len;
        sel.end = sel.cursor;
        sel.start = sel.cursor;
    }
    if (std.mem.indexOfScalar(u8, new[0..new_len], '\n') != null) {
        sel.affinity = .after;
    }

    // we might have dropped to a new line, so make sure the cursor is visible
    self.textLayout.scroll_to_cursor_next_frame = true;
    dvui.refresh(null, @src(), self.data().id);
}

/// Remove all characters that not present in filter_chars.
/// Designed to run after event processing and before drawing.
pub fn filterIn(self: *TextEntryWidget, filter_chars: []const u8) void {
    if (filter_chars.len == 0) {
        return;
    }

    var i: usize = 0;
    var j: usize = 0;
    const n = self.len;
    while (i < n) {
        if (std.mem.indexOfScalar(u8, filter_chars, self.text[i]) == null) {
            self.len -= 1;
            var sel = self.textLayout.selection;
            if (sel.start > i) sel.start -= 1;
            if (sel.cursor > i) sel.cursor -= 1;
            if (sel.end > i) sel.end -= 1;
            self.text_changed = true;

            i += 1;
        } else {
            self.text[j] = self.text[i];
            i += 1;
            j += 1;
        }
    }

    if (j < self.text.len)
        self.text[j] = 0;
}

/// Remove all instances of the string needle.
/// Designed to run after event processing and before drawing.
pub fn filterOut(self: *TextEntryWidget, needle: []const u8) void {
    if (needle.len == 0) {
        return;
    }

    var i: usize = 0;
    var j: usize = 0;
    const n = self.len;
    while (i < n) {
        if (std.mem.startsWith(u8, self.text[i..], needle)) {
            self.len -= needle.len;
            var sel = self.textLayout.selection;
            if (sel.start > i) sel.start -= needle.len;
            if (sel.cursor > i) sel.cursor -= needle.len;
            if (sel.end > i) sel.end -= needle.len;
            self.text_changed = true;

            i += needle.len;
        } else {
            self.text[j] = self.text[i];
            i += 1;
            j += 1;
        }
    }

    if (j < self.text.len)
        self.text[j] = 0;
}

/// Sets the null terminator at index self.len if there is space in the backing slice
pub fn addNullTerminator(self: *TextEntryWidget) void {
    if (self.len < self.text.len) {
        self.text[self.len] = 0;
    }
}

pub fn processEvent(self: *TextEntryWidget, e: *Event) void {
    // scroll gets first crack, because it is logically outside the text area
    self.scroll.scroll.?.processEvent(e);
    if (e.handled) return;

    switch (e.evt) {
        .key => |ke| blk: {
            if (ke.action == .down and ke.matchBind("next_widget")) {
                e.handle(@src(), self.data());
                dvui.tabIndexNext(e.num);
                break :blk;
            }

            if (ke.action == .down and ke.matchBind("prev_widget")) {
                e.handle(@src(), self.data());
                dvui.tabIndexPrev(e.num);
                break :blk;
            }

            if (ke.action == .down and ke.matchBind("paste")) {
                e.handle(@src(), self.data());
                self.paste();
                break :blk;
            }

            if (ke.action == .down and ke.matchBind("cut")) {
                e.handle(@src(), self.data());
                self.cut();
                break :blk;
            }

            if (ke.action == .down and ke.matchBind("text_start")) {
                e.handle(@src(), self.data());
                self.textLayout.selection.moveCursor(0, false);
                self.textLayout.scroll_to_cursor = true;
                break :blk;
            }

            if (ke.action == .down and ke.matchBind("text_end")) {
                e.handle(@src(), self.data());
                self.textLayout.selection.moveCursor(std.math.maxInt(usize), false);
                self.textLayout.scroll_to_cursor = true;
                break :blk;
            }

            if (ke.action == .down and ke.matchBind("line_start")) {
                e.handle(@src(), self.data());
                if (self.textLayout.sel_move == .none) {
                    self.textLayout.sel_move = .{ .expand_pt = .{ .select = false, .which = .home } };
                }
                break :blk;
            }

            if (ke.action == .down and ke.matchBind("line_end")) {
                e.handle(@src(), self.data());
                if (self.textLayout.sel_move == .none) {
                    self.textLayout.sel_move = .{ .expand_pt = .{ .select = false, .which = .end } };
                }
                break :blk;
            }

            if ((ke.action == .down or ke.action == .repeat) and ke.matchBind("word_left")) {
                e.handle(@src(), self.data());
                if (!self.textLayout.selection.empty()) {
                    self.textLayout.selection.moveCursor(self.textLayout.selection.start, false);
                } else {
                    if (self.textLayout.sel_move == .none) {
                        self.textLayout.sel_move = .{ .word_left_right = .{ .select = false } };
                    }
                    if (self.textLayout.sel_move == .word_left_right) {
                        self.textLayout.sel_move.word_left_right.count -= 1;
                    }
                }
                break :blk;
            }

            if ((ke.action == .down or ke.action == .repeat) and ke.matchBind("word_right")) {
                e.handle(@src(), self.data());
                if (!self.textLayout.selection.empty()) {
                    self.textLayout.selection.moveCursor(self.textLayout.selection.end, false);
                    self.textLayout.selection.affinity = .before;
                } else {
                    if (self.textLayout.sel_move == .none) {
                        self.textLayout.sel_move = .{ .word_left_right = .{ .select = false } };
                    }
                    if (self.textLayout.sel_move == .word_left_right) {
                        self.textLayout.sel_move.word_left_right.count += 1;
                    }
                }
                break :blk;
            }

            if ((ke.action == .down or ke.action == .repeat) and ke.matchBind("char_left")) {
                e.handle(@src(), self.data());
                if (!self.textLayout.selection.empty()) {
                    self.textLayout.selection.moveCursor(self.textLayout.selection.start, false);
                } else {
                    if (self.textLayout.sel_move == .none) {
                        self.textLayout.sel_move = .{ .char_left_right = .{ .select = false } };
                    }
                    if (self.textLayout.sel_move == .char_left_right) {
                        self.textLayout.sel_move.char_left_right.count -= 1;
                    }
                }
                break :blk;
            }

            if ((ke.action == .down or ke.action == .repeat) and ke.matchBind("char_right")) {
                e.handle(@src(), self.data());
                if (!self.textLayout.selection.empty()) {
                    self.textLayout.selection.moveCursor(self.textLayout.selection.end, false);
                    self.textLayout.selection.affinity = .before;
                } else {
                    if (self.textLayout.sel_move == .none) {
                        self.textLayout.sel_move = .{ .char_left_right = .{ .select = false } };
                    }
                    if (self.textLayout.sel_move == .char_left_right) {
                        self.textLayout.sel_move.char_left_right.count += 1;
                    }
                }
                break :blk;
            }

            if ((ke.action == .down or ke.action == .repeat) and ke.matchBind("char_up")) {
                e.handle(@src(), self.data());
                if (self.textLayout.sel_move == .none) {
                    self.textLayout.sel_move = .{ .cursor_updown = .{ .select = false } };
                }
                if (self.textLayout.sel_move == .cursor_updown) {
                    self.textLayout.sel_move.cursor_updown.count -= 1;
                }
                break :blk;
            }

            if ((ke.action == .down or ke.action == .repeat) and ke.matchBind("char_down")) {
                e.handle(@src(), self.data());
                if (self.textLayout.sel_move == .none) {
                    self.textLayout.sel_move = .{ .cursor_updown = .{ .select = false } };
                }
                if (self.textLayout.sel_move == .cursor_updown) {
                    self.textLayout.sel_move.cursor_updown.count += 1;
                }
                break :blk;
            }

            switch (ke.code) {
                .backspace => {
                    if (ke.action == .down or ke.action == .repeat) {
                        e.handle(@src(), self.data());
                        var sel = self.textLayout.selectionGet(self.len);
                        if (!sel.empty()) {
                            // just delete selection
                            self.textChangedRemoved(sel.start, sel.end);
                            std.mem.copyForwards(u8, self.text[sel.start..], self.text[sel.end..self.len]);
                            self.len -= (sel.end - sel.start);
                            self.addNullTerminator();
                            sel.end = sel.start;
                            sel.cursor = sel.start;
                            self.textLayout.scroll_to_cursor = true;
                        } else if (ke.matchBind("delete_prev_word")) {
                            // delete word before cursor

                            const oldcur = sel.cursor;
                            // find end of last word
                            if (sel.cursor > 0 and std.mem.indexOfAny(u8, self.text[sel.cursor - 1 ..][0..1], " \n") != null) {
                                sel.cursor = std.mem.lastIndexOfNone(u8, self.text[0..sel.cursor], " \n") orelse 0;
                            }

                            // find start of word
                            if (std.mem.lastIndexOfAny(u8, self.text[0..sel.cursor], " \n")) |last_space| {
                                sel.cursor = last_space + 1;
                            } else {
                                sel.cursor = 0;
                            }

                            // delete from sel.cursor to oldcur
                            if (sel.cursor != oldcur) self.textChangedRemoved(sel.cursor, oldcur);
                            std.mem.copyForwards(u8, self.text[sel.cursor..], self.text[oldcur..self.len]);
                            self.len -= (oldcur - sel.cursor);
                            self.addNullTerminator();
                            sel.end = sel.cursor;
                            sel.start = sel.cursor;
                            self.textLayout.scroll_to_cursor = true;
                        } else if (sel.cursor > 0) {
                            // delete character just before cursor
                            //
                            // A utf8 char might consist of more than one byte.
                            // Find the beginning of the last byte by iterating over
                            // the string backwards. The first byte of a utf8 char
                            // does not have the pattern 10xxxxxx.
                            var i: usize = 1;
                            while (sel.cursor - i > 0 and self.text[sel.cursor - i] & 0xc0 == 0x80) : (i += 1) {}
                            self.textChangedRemoved(sel.cursor - i, sel.cursor);
                            std.mem.copyForwards(u8, self.text[sel.cursor - i ..], self.text[sel.cursor..self.len]);
                            self.len -= i;
                            self.addNullTerminator();
                            sel.cursor -= i;
                            sel.start = sel.cursor;
                            sel.end = sel.cursor;
                            self.textLayout.scroll_to_cursor = true;
                        }
                    }
                },
                .delete => {
                    if (ke.action == .down or ke.action == .repeat) {
                        e.handle(@src(), self.data());
                        var sel = self.textLayout.selectionGet(self.len);
                        if (!sel.empty()) {
                            // just delete selection
                            self.textChangedRemoved(sel.start, sel.end);
                            std.mem.copyForwards(u8, self.text[sel.start..], self.text[sel.end..self.len]);
                            self.len -= (sel.end - sel.start);
                            self.addNullTerminator();
                            sel.end = sel.start;
                            sel.cursor = sel.start;
                            self.textLayout.scroll_to_cursor = true;
                        } else if (ke.matchBind("delete_next_word")) {
                            // delete word after cursor

                            const oldcur = sel.cursor;
                            // find start of next word
                            if (sel.cursor < self.len and std.mem.indexOfAny(u8, self.text[sel.cursor..][0..1], " \n") != null) {
                                sel.cursor = std.mem.indexOfNonePos(u8, self.text, sel.cursor, " \n") orelse self.len;
                            }

                            // find end of word
                            if (std.mem.indexOfAny(u8, self.text[sel.cursor..self.len], " \n")) |last_space| {
                                sel.cursor = sel.cursor + last_space;
                            } else {
                                sel.cursor = self.len;
                            }

                            // delete from oldcur to sel.cursor
                            if (sel.cursor != oldcur) self.textChangedRemoved(oldcur, sel.cursor);
                            std.mem.copyForwards(u8, self.text[oldcur..], self.text[sel.cursor..self.len]);
                            self.len -= (sel.cursor - oldcur);
                            self.addNullTerminator();
                            sel.cursor = oldcur;
                            sel.end = sel.cursor;
                            sel.start = sel.cursor;
                            self.textLayout.scroll_to_cursor = true;
                        } else if (sel.cursor < self.len) {
                            // delete the character just after the cursor
                            //
                            // A utf8 char might consist of more than one byte.
                            const ii = std.unicode.utf8ByteSequenceLength(self.text[sel.cursor]) catch 1;
                            const i = @min(ii, self.len - sel.cursor);

                            self.textChangedRemoved(sel.cursor, sel.cursor + i);
                            std.mem.copyForwards(u8, self.text[sel.cursor..], self.text[sel.cursor + i .. self.len]);
                            self.len -= i;
                            self.addNullTerminator();
                            self.textLayout.scroll_to_cursor = true;
                        }
                    }
                },
                .enter => {
                    if (ke.action == .down or ke.action == .repeat) {
                        e.handle(@src(), self.data());
                        if (self.init_opts.multiline) {
                            self.textTyped("\n", false);
                        } else {
                            self.enter_pressed = true;
                            dvui.refresh(null, @src(), self.data().id);
                        }
                    }
                },
                else => {},
            }
        },
        .text => |te| {
            e.handle(@src(), self.data());
            var new = std.mem.sliceTo(te.txt, 0);
            if (te.replace) {
                self.textLayout.selection.selectAll();
            }
            if (self.init_opts.multiline) {
                self.textTyped(new, te.selected);
            } else {
                var i: usize = 0;
                while (i < new.len) {
                    if (std.mem.indexOfScalar(u8, new[i..], '\n')) |idx| {
                        self.textTyped(new[i..][0..idx], te.selected);
                        i += idx + 1;
                    } else {
                        self.textTyped(new[i..], te.selected);
                        break;
                    }
                }
            }
        },
        .mouse => |me| {
            if (me.action == .focus) {
                e.handle(@src(), self.data());
                dvui.focusWidget(self.data().id, null, e.num);
            }
        },
        else => {},
    }

    if (!e.handled) {
        self.textLayout.processEvent(e);

        if (!e.handled and e.evt == .key) {
            switch (e.evt.key.code) {
                .page_up, .page_down => {}, // handled by scroll container
                else => {
                    // Mark all remaining key events as handled. This allows
                    // checking a keybind (like "d") after the textEntry, but
                    // where textEntry will get it first.
                    e.handle(@src(), self.data());
                },
            }
        }
    }
}

pub fn paste(self: *TextEntryWidget) void {
    const clip_text = dvui.clipboardText();

    if (self.init_opts.multiline) {
        self.textTyped(clip_text, false);
    } else {
        var i: usize = 0;
        while (i < clip_text.len) {
            if (std.mem.indexOfScalar(u8, clip_text[i..], '\n')) |idx| {
                self.textTyped(clip_text[i..][0..idx], false);
                i += idx + 1;
            } else {
                self.textTyped(clip_text[i..], false);
                break;
            }
        }
    }
}

pub fn cut(self: *TextEntryWidget) void {
    var sel = self.textLayout.selectionGet(self.len);
    if (!sel.empty()) {
        // copy selection to clipboard
        dvui.clipboardTextSet(self.text[sel.start..sel.end]);

        // delete selection
        self.textChangedRemoved(sel.start, sel.end);
        std.mem.copyForwards(u8, self.text[sel.start..], self.text[sel.end..self.len]);
        self.len -= (sel.end - sel.start);
        self.addNullTerminator();
        sel.end = sel.start;
        sel.cursor = sel.start;
        self.textLayout.scroll_to_cursor = true;
    }
}

pub fn getText(self: *const TextEntryWidget) []u8 {
    return self.text[0..self.len];
}

pub fn deinit(self: *TextEntryWidget) void {
    const should_free = self.data().was_allocated_on_widget_stack;
    defer if (should_free) dvui.widgetFree(self);
    defer self.* = undefined;
    const needed_binds = @divTrunc(self.len, realloc_bin_size) + 1;
    const current_bins = @divTrunc(self.text.len, realloc_bin_size);
    // dvui.log.debug("TextEntry {x} needs {d} bins, has {d}", .{ self.data().id, needed_binds, current_bins });
    if (self.len == 0 or needed_binds < current_bins) {
        // we want to shrink the allocation
        const new_len = if (self.len == 0) 0 else realloc_bin_size * needed_binds;
        switch (self.init_opts.text) {
            .buffer => {},
            .buffer_dynamic => |b| {
                if (b.allocator.resize(self.text, new_len)) {
                    b.backing.*.len = new_len;
                    self.text.len = new_len;
                } else {
                    dvui.logError(@src(), std.mem.Allocator.Error.OutOfMemory, "{x} TextEntryWidget.textTyped failed to realloc backing (current size {d}, new size {d})", .{ self.data().id, self.text.len, new_len });
                }
            },
            .internal => {
                // NOTE: Using prev_text is safe because data is trashed and stays valid until the end of the frame
                const prev_text = self.text;
                dvui.dataSetSliceCopies(null, self.data().id, "_buffer", &[_]u8{0}, new_len);
                self.text = dvui.dataGetSlice(null, self.data().id, "_buffer", []u8).?;
                const min_len = @min(prev_text.len, self.text.len);
                @memcpy(self.text[0..min_len], prev_text[0..min_len]);
            },
        }
    }

    self.textLayout.deinit();
    self.scroll.deinit();

    dvui.clipSet(self.prevClip);
    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();
    dvui.parentReset(self.data().id, self.data().parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "text internal" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const Local = struct {
        var text: []const u8 = "";

        // Set a limit that is not a multiple of the bin size
        const limit = realloc_bin_size * 5 / 2;

        fn frame() !dvui.App.Result {
            var entry = TextEntryWidget.init(@src(), .{
                .text = .{ .internal = .{ .limit = limit } },
            }, .{ .tag = "entry" });
            entry.install();
            defer entry.deinit();

            entry.processEvents();
            entry.draw();
            text = entry.getText();
            return .ok;
        }
    };

    try dvui.testing.settle(Local.frame);
    try dvui.testing.pressKey(.tab, .none);
    try dvui.testing.settle(Local.frame);
    try dvui.testing.expectFocused("entry");

    const text = "This is some short sample text!";
    // text length should not be a multiple of the limit or bin size
    try std.testing.expect(Local.limit % text.len != 0);
    try std.testing.expect(realloc_bin_size % text.len != 0);

    try dvui.testing.writeText(text);
    try dvui.testing.settle(Local.frame);
    try std.testing.expectEqualStrings(text, Local.text);

    for (0..@divFloor(Local.limit, text.len)) |_| {
        // Fill the internal buffer
        try dvui.testing.writeText(text);
    }
    try dvui.testing.settle(Local.frame);

    const full_text_buffer = (text ** (@divFloor(Local.limit, text.len) + 1))[0..Local.limit];
    try std.testing.expectEqualStrings(full_text_buffer, Local.text);
}

test "text dynamic buffer" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const Local = struct {
        var text: []const u8 = "";

        // Set a limit that is not a multiple of the bin size
        const limit = realloc_bin_size * 5 / 2;

        var buffer: [limit]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        var backing: []u8 = &.{};

        fn frame() !dvui.App.Result {
            var entry = TextEntryWidget.init(@src(), .{
                .text = .{ .buffer_dynamic = .{
                    .backing = &backing,
                    .allocator = fba.allocator(),
                    .limit = limit,
                } },
            }, .{ .tag = "entry" });
            entry.install();
            defer entry.deinit();

            entry.processEvents();
            entry.draw();
            text = entry.getText();
            return .ok;
        }
    };

    try dvui.testing.settle(Local.frame);
    try dvui.testing.pressKey(.tab, .none);
    try dvui.testing.settle(Local.frame);
    try dvui.testing.expectFocused("entry");

    const text = "This is some short sample text!";
    // limit should not be a multiple of the text length
    try std.testing.expect(Local.limit % text.len != 0);
    try std.testing.expect(realloc_bin_size % text.len != 0);

    try dvui.testing.writeText(text);
    try dvui.testing.settle(Local.frame);
    try std.testing.expectEqualStrings(text, Local.text);

    for (0..@divFloor(Local.limit, text.len)) |_| {
        // Fill the internal buffer
        // This verifies that any OOM error is handled by writing past the buffer size
        try dvui.testing.writeText(text);
    }
    try dvui.testing.settle(Local.frame);

    const full_text_buffer = (text ** (@divFloor(Local.limit, text.len) + 1))[0..Local.limit];
    try std.testing.expectEqualStrings(full_text_buffer, Local.text);
}

test "text buffer" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const Local = struct {
        var text: []const u8 = "";

        // Set a limit that is not a multiple of the bin size
        const limit = realloc_bin_size * 5 / 2;

        var buffer: [limit]u8 = undefined;

        fn frame() !dvui.App.Result {
            var entry = TextEntryWidget.init(@src(), .{
                .text = .{ .buffer = &buffer },
            }, .{ .tag = "entry" });
            entry.install();
            defer entry.deinit();

            entry.processEvents();
            entry.draw();
            text = entry.getText();
            return .ok;
        }
    };

    try dvui.testing.settle(Local.frame);
    try dvui.testing.pressKey(.tab, .none);
    try dvui.testing.settle(Local.frame);
    try dvui.testing.expectFocused("entry");

    const text = "This is some short sample text!";
    // limit should not be a multiple of the text length
    try std.testing.expect(Local.limit % text.len != 0);
    try std.testing.expect(realloc_bin_size % text.len != 0);

    try dvui.testing.writeText(text);
    try dvui.testing.settle(Local.frame);
    try std.testing.expectEqualStrings(text, Local.text);

    for (0..@divFloor(Local.limit, text.len)) |_| {
        // Fill the internal buffer
        // This verifies that any OOM error is handled by writing past the buffer size
        try dvui.testing.writeText(text);
    }
    try dvui.testing.settle(Local.frame);

    const full_text_buffer = (text ** (@divFloor(Local.limit, text.len) + 1))[0..Local.limit];
    try std.testing.expectEqualStrings(full_text_buffer, Local.text);
}
