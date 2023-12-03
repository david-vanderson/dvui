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
    .margin = Rect.all(4),
    .corner_radius = Rect.all(5),
    .border = Rect.all(1),
    .padding = Rect.all(4),
    .background = true,
    // min_size_content is calculated in init()
};

pub const InitOptions = struct {
    text: []u8,
    break_lines: bool = false,
    scroll_vertical: ?bool = null, // default is value of multiline
    scroll_vertical_bar: ?ScrollInfo.ScrollBarMode = null, // default .auto
    scroll_horizontal: ?bool = null, // default true
    scroll_horizontal_bar: ?ScrollInfo.ScrollBarMode = null, // default .auto if multiline, .hide if not

    // must be a single utf8 character
    password_char: ?[]const u8 = null,
    multiline: bool = false,
};

wd: WidgetData = undefined,
prevClip: Rect = undefined,
scroll: ScrollAreaWidget = undefined,
scrollClip: Rect = undefined,
textLayout: TextLayoutWidget = undefined,
textClip: Rect = undefined,
padding: Rect = undefined,

init_opts: InitOptions = undefined,
len: usize = undefined,
scroll_to_cursor: bool = false,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) TextEntryWidget {
    var self = TextEntryWidget{};
    self.init_opts = init_opts;

    const msize = opts.fontGet().textSize("M") catch unreachable;
    var options = defaults.override(.{ .min_size_content = .{ .w = msize.w * 14, .h = msize.h } }).override(opts);

    // padding is interpreted as the padding for the TextLayoutWidget, but
    // we also need to add it to content size because TextLayoutWidget is
    // inside the scroll area
    self.padding = options.paddingGet();
    options.padding = null;
    options.min_size_content.?.w += self.padding.x + self.padding.w;
    options.min_size_content.?.h += self.padding.y + self.padding.h;

    self.wd = WidgetData.init(src, .{}, options);

    self.len = std.mem.indexOfScalar(u8, self.init_opts.text, 0) orelse self.init_opts.text.len;
    self.len = dvui.findUtf8Start(self.init_opts.text[0..self.len], self.len);
    return self;
}

pub fn install(self: *TextEntryWidget) !void {
    try self.wd.register();

    if (self.wd.visible()) {
        try dvui.tabIndexSet(self.wd.id, self.wd.options.tab_index);
    }

    dvui.parentSet(self.widget());

    try self.wd.borderAndBackground(.{});

    self.prevClip = dvui.clipGet();

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

    self.textLayout = TextLayoutWidget.init(@src(), .{ .break_lines = self.init_opts.break_lines }, self.wd.options.strip().override(.{ .expand = .both, .padding = self.padding, .min_size_content = .{} }));
    try self.textLayout.install(self.wd.id == dvui.focusedWidgetId());
    self.textClip = dvui.clipGet();

    // don't call textLayout.processEvents here, we forward events inside our own processEvents

    // textLayout is maintaining the selection for us, but if the text
    // changed, we need to update the selection to be valid before we
    // process any events
    var sel = self.textLayout.selection;
    sel.start = dvui.findUtf8Start(self.init_opts.text[0..self.len], sel.start);
    sel.cursor = dvui.findUtf8Start(self.init_opts.text[0..self.len], sel.cursor);
    sel.end = dvui.findUtf8Start(self.init_opts.text[0..self.len], sel.end);

    // textLayout clips to its content, but we need to get events out to our border
    dvui.clipSet(self.prevClip);
}

pub fn matchEvent(self: *TextEntryWidget, e: *Event) bool {
    // textLayout could be passively listening to events in matchEvent, so
    // don't short circuit
    const match1 = dvui.eventMatch(e, .{ .id = self.wd.id, .r = self.wd.borderRectScale().r });
    const match2 = self.textLayout.matchEvent(e);
    return match1 or match2;
}

pub fn processEvents(self: *TextEntryWidget) void {
    var evts = dvui.events();
    for (evts) |*e| {
        if (!self.matchEvent(e))
            continue;

        self.processEvent(e, false);
    }
}

pub fn draw(self: *TextEntryWidget) !void {
    const focused = (self.wd.id == dvui.focusedWidgetId());

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
        var utf8it = (try std.unicode.Utf8View.init(self.init_opts.text[0..self.len])).iterator();
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
        var password_str: []u8 = try dvui.currentWindow().arena.alloc(u8, count * pc.len);
        for (0..count) |i| {
            for (0..pc.len) |pci| {
                password_str[i * pc.len + pci] = pc[pci];
            }
        }
        try self.textLayout.addText(password_str, self.wd.options.strip());
    } else {
        try self.textLayout.addText(self.init_opts.text[0..self.len], self.wd.options.strip());
    }

    try self.textLayout.addTextDone(self.wd.options.strip());
    try self.textLayout.touchEditing(.{ .r = dvui.clipGet(), .s = self.wd.rectScale().s });

    if (self.init_opts.password_char) |pc| {
        // reset selection
        var count: usize = 0;
        var bytes: usize = 0;
        var sel = self.textLayout.selection;
        var sstart: ?usize = null;
        var scursor: ?usize = null;
        var send: ?usize = null;
        var utf8it = (try std.unicode.Utf8View.init(self.init_opts.text[0..self.len])).iterator();
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
        try self.drawCursor();

        dvui.clipSet(self.prevClip);
        try self.wd.focusBorder();
    }
}

pub fn drawCursor(self: *TextEntryWidget) !void {
    if (self.textLayout.cursor_rect) |cr| {
        // the cursor can be slightly outside the textLayout clip
        dvui.clipSet(self.scrollClip);

        var crect = cr.add(.{ .x = -1 });
        crect.w = 2;
        try dvui.pathAddRect(self.textLayout.screenRectScale(crect).r, Rect.all(0));
        try dvui.pathFillConvex(self.wd.options.color(.accent));

        if (self.scroll_to_cursor) {
            var scrollto = Event{
                .evt = .{
                    .scroll_to = .{
                        .screen_rect = self.textLayout.screenRectScale(crect.outset(self.padding)).r,
                        // cursor might just have transitioned to a new line, so scroll area has not expanded yet
                        .over_scroll = true,
                    },
                },
            };
            self.scroll.scroll.processEvent(&scrollto, true);
        }
    }
}

pub fn widget(self: *TextEntryWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *TextEntryWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *TextEntryWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    return dvui.placeIn(self.wd.contentRect().justSize(), dvui.minSize(id, min_size), e, g);
}

pub fn screenRectScale(self: *TextEntryWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToScreen(rect);
}

pub fn minSizeForChild(self: *TextEntryWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.padSize(s));
}

pub fn textTyped(self: *TextEntryWidget, new: []const u8) void {
    var sel = self.textLayout.selectionGet(self.len);
    if (!sel.empty()) {
        // delete selection
        std.mem.copy(u8, self.init_opts.text[sel.start..], self.init_opts.text[sel.end..self.len]);
        self.len -= (sel.end - sel.start);
        sel.end = sel.start;
        sel.cursor = sel.start;
    }

    var new_len = @min(new.len, self.init_opts.text.len - self.len);

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
    if (sel.cursor + new_len < self.init_opts.text.len) {
        std.mem.copyBackwards(u8, self.init_opts.text[sel.cursor + new_len ..], self.init_opts.text[sel.cursor..self.len]);
    }

    // update our len and maintain 0 termination if possible
    self.len += new_len;
    if (self.len < self.init_opts.text.len) {
        self.init_opts.text[self.len] = 0;
    }

    // insert
    std.mem.copy(u8, self.init_opts.text[sel.cursor..], new[0..new_len]);
    sel.cursor += new_len;
    sel.end = sel.cursor;
    sel.start = sel.cursor;

    // we might have dropped to a new line, so make sure the cursor is visible
    self.scroll_to_cursor = true;
}

// Designed to run after event processing and before drawing
pub fn filterOut(self: *TextEntryWidget, filter: []const u8) void {
    if (filter.len == 0) {
        return;
    }

    var i: usize = 0;
    var j: usize = 0;
    const n = self.len;
    while (i < n) {
        if (std.mem.startsWith(u8, self.init_opts.text[i..], filter)) {
            self.len -= filter.len;
            var sel = self.textLayout.selection;
            if (sel.start > i) sel.start -= filter.len;
            if (sel.cursor > i) sel.cursor -= filter.len;
            if (sel.end > i) sel.end -= filter.len;

            i += filter.len;
        } else {
            self.init_opts.text[j] = self.init_opts.text[i];
            i += 1;
            j += 1;
        }
    }

    if (j < self.init_opts.text.len)
        self.init_opts.text[j] = 0;
}

pub fn processEvent(self: *TextEntryWidget, e: *Event, bubbling: bool) void {
    switch (e.evt) {
        .key => |ke| {
            switch (ke.code) {
                .backspace => {
                    if (ke.action == .down or ke.action == .repeat) {
                        e.handled = true;
                        var sel = self.textLayout.selectionGet(self.len);
                        if (!sel.empty()) {
                            // just delete selection
                            std.mem.copy(u8, self.init_opts.text[sel.start..], self.init_opts.text[sel.end..self.len]);
                            self.len -= (sel.end - sel.start);
                            self.init_opts.text[self.len] = 0;
                            sel.end = sel.start;
                            sel.cursor = sel.start;
                            self.scroll_to_cursor = true;
                        } else if (sel.cursor > 0) {
                            // delete character just before cursor
                            //
                            // A utf8 char might consist of more than one byte.
                            // Find the beginning of the last byte by iterating over
                            // the string backwards. The first byte of a utf8 char
                            // does not have the pattern 10xxxxxx.
                            var i: usize = 1;
                            while (self.init_opts.text[sel.cursor - i] & 0xc0 == 0x80) : (i += 1) {}
                            std.mem.copy(u8, self.init_opts.text[sel.cursor - i ..], self.init_opts.text[sel.cursor..self.len]);
                            self.len -= i;
                            self.init_opts.text[self.len] = 0;
                            sel.cursor -= i;
                            sel.start = sel.cursor;
                            sel.end = sel.cursor;
                            self.scroll_to_cursor = true;
                        }
                    }
                },
                .delete => {
                    if (ke.action == .down or ke.action == .repeat) {
                        e.handled = true;
                        var sel = self.textLayout.selectionGet(self.len);
                        if (!sel.empty()) {
                            // just delete selection
                            std.mem.copy(u8, self.init_opts.text[sel.start..], self.init_opts.text[sel.end..self.len]);
                            self.len -= (sel.end - sel.start);
                            self.init_opts.text[self.len] = 0;
                            sel.end = sel.start;
                            sel.cursor = sel.start;
                            self.scroll_to_cursor = true;
                        } else if (sel.cursor < self.len) {
                            // delete the character just after the cursor
                            //
                            // A utf8 char might consist of more than one byte.
                            const i = std.unicode.utf8ByteSequenceLength(self.init_opts.text[sel.cursor]) catch 1;
                            std.mem.copy(u8, self.init_opts.text[sel.cursor..], self.init_opts.text[sel.cursor + i .. self.len]);
                            self.len -= i;
                            self.init_opts.text[self.len] = 0;
                        }
                    }
                },
                .enter => {
                    if (self.init_opts.multiline and ke.action == .down or ke.action == .repeat) {
                        e.handled = true;
                        self.textTyped("\n");
                    }
                },
                .tab => {
                    if (ke.action == .down) {
                        e.handled = true;
                        if (ke.mod.shift()) {
                            dvui.tabIndexPrev(e.num);
                        } else {
                            dvui.tabIndexNext(e.num);
                        }
                    }
                },
                .v => {
                    if (ke.action == .down and ke.mod.controlCommand()) {
                        // paste
                        e.handled = true;
                        const clip_text = dvui.clipboardText();
                        defer dvui.backendFree(clip_text.ptr);
                        if (self.init_opts.multiline) {
                            self.textTyped(clip_text);
                        } else {
                            var i: usize = 0;
                            while (i < clip_text.len) {
                                if (std.mem.indexOfScalar(u8, clip_text[i..], '\n')) |idx| {
                                    self.textTyped(clip_text[i..][0..idx]);
                                    i += idx + 1;
                                } else {
                                    self.textTyped(clip_text[i..]);
                                    break;
                                }
                            }
                        }
                    }
                },
                .x => {
                    if (ke.action == .down and ke.mod.controlCommand()) {
                        // cut
                        e.handled = true;
                        var sel = self.textLayout.selectionGet(self.len);
                        if (!sel.empty()) {
                            // copy selection to clipboard
                            dvui.clipboardTextSet(self.init_opts.text[sel.start..sel.end]) catch |err| {
                                dvui.log.err("clipboardTextSet error {!}\n", .{err});
                            };

                            // delete selection
                            std.mem.copy(u8, self.init_opts.text[sel.start..], self.init_opts.text[sel.end..self.len]);
                            self.len -= (sel.end - sel.start);
                            self.init_opts.text[self.len] = 0;
                            sel.end = sel.start;
                            sel.cursor = sel.start;
                            self.scroll_to_cursor = true;
                        }
                    }
                },
                .left, .right => |code| {
                    if ((ke.action == .down or ke.action == .repeat) and !ke.mod.shift()) {
                        e.handled = true;
                        var sel = self.textLayout.selectionGet(self.len);
                        if (code == .left) {
                            // If the cursor is at position 0 do nothing...
                            if (sel.cursor > 0) {
                                // ... otherwise, "jump over" the utf8 char to the
                                // left of the cursor.
                                var i: usize = 1;
                                while (sel.cursor -| i > 0 and self.init_opts.text[sel.cursor -| i] & 0xc0 == 0x80) : (i += 1) {}
                                sel.cursor -|= i;
                            }
                        } else {
                            if (sel.cursor < self.len) {
                                // Get the number of bytes of the current code point and
                                // "jump" to the next code point to the right of the cursor.
                                sel.cursor += std.unicode.utf8ByteSequenceLength(self.init_opts.text[sel.cursor]) catch 1;
                                sel.cursor = @min(sel.cursor, self.len);
                            }
                        }

                        sel.start = sel.cursor;
                        sel.end = sel.cursor;
                        self.scroll_to_cursor = true;
                    }
                },
                .up, .down => |code| {
                    if ((ke.action == .down or ke.action == .repeat) and !ke.mod.shift()) {
                        e.handled = true;
                        self.textLayout.cursor_updown += if (code == .down) 1 else -1;
                        self.textLayout.cursor_updown_drag = false;
                    }
                },
                else => {},
            }
        },
        .text => |te| {
            e.handled = true;
            var new = std.mem.sliceTo(te, 0);
            if (self.init_opts.multiline) {
                self.textTyped(new);
            } else {
                var i: usize = 0;
                while (i < new.len) {
                    if (std.mem.indexOfScalar(u8, new[i..], '\n')) |idx| {
                        self.textTyped(new[i..][0..idx]);
                        i += idx + 1;
                    } else {
                        self.textTyped(new[i..]);
                        break;
                    }
                }
            }
        },
        .mouse => |me| {
            if (me.action == .focus) {
                e.handled = true;
                dvui.focusWidget(self.wd.id, null, e.num);
            }
        },
        else => {},
    }

    if (!e.handled and !bubbling) {
        self.textLayout.processEvent(e, false);
    }

    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *TextEntryWidget) void {
    self.textLayout.deinit();
    self.scroll.deinit();

    dvui.clipSet(self.prevClip);
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    dvui.parentReset(self.wd.id, self.wd.parent);
}
