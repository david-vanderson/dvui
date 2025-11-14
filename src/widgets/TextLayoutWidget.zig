const builtin = @import("builtin");
const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Point = dvui.Point;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;
const FloatingWidget = dvui.FloatingWidget;

const TextLayoutWidget = @This();

/// When break_lines is true, you can't get both a min width and min height,
/// since the width will affect the height.  In this case, min width will be as
/// if break_lines was false, and min_height will be the height needed at the
/// current width.
///
/// In many cases on our first frame we have a width of zero, which would make
/// min height very large, so instead we assume we will get our min width (or
/// 500 if our min width is zero).
pub var defaults: Options = .{
    .name = "TextLayout",
    .role = .label, // TODO: Use labels until can support .text_run
    .padding = Rect.all(6),
    .background = true,
    .style = .content,
};

pub const InitOptions = struct {
    selection: ?*Selection = null,

    /// If true, break text on space to fit (or any character if width is < 10 Ms)
    break_lines: bool = true,

    /// If true, assume text (and text height) is the same as we saw last frame
    /// and only process what is needed for visibility (and copy).
    cache_layout: bool = false,

    // Whether to enter touch editing mode on a touch-release (no drag) if we
    // were not focused before the touch.
    touch_edit_just_focused: bool = true,

    // If non null, overrides `Window.kerning` setting.
    kerning: ?bool = null,
};

pub const Selection = struct {
    const Affinity = enum {
        before,
        after,
    };

    cursor: usize = 0,
    start: usize = 0,
    end: usize = 0,

    // if the characters on either side of cursor are split across lines:
    // - before means cursor is logically at the end of the first char
    // - after means the cursor is logically at the beginning of the second char
    affinity: Affinity = .after,

    pub fn empty(self: *Selection) bool {
        return self.start == self.end;
    }

    pub fn selectAll(self: *Selection) void {
        self.start = 0;
        self.cursor = 0;
        self.end = std.math.maxInt(usize);
    }

    pub fn moveCursor(self: *Selection, idx: usize, select: bool) void {
        //std.debug.print("moveCursor {d} {}\n", .{ idx, select });
        self.affinity = .after;
        if (select) {
            if (self.cursor == self.start) {
                // move the start
                self.cursor = idx;
                self.start = idx;
            } else {
                // move the end
                self.cursor = idx;
                self.end = idx;
            }
        } else {
            // removing any selection
            self.cursor = idx;
            self.start = idx;
            self.end = idx;
        }

        self.order();
    }

    pub fn order(self: *Selection) void {
        if (self.end < self.start) {
            const tmp = self.start;
            self.start = self.end;
            self.end = tmp;
        }
    }
};

/// This is used for word selection - 2 clicks and ctrl+left/right - everything
/// here is not a word, and everything else is.
pub const word_breaks = " \n!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~";

wd: WidgetData,
corners: [4]?Rect = [_]?Rect{null} ** 4,
corners_min_size: [4]?Size = [_]?Size{null} ** 4,
corners_last_seen: ?u8 = null,
insert_pt: Point = Point{},
current_line_height: f32 = 0.0,
prevClip: Rect.Physical = .{},
kerning: ?bool,
break_lines: bool,
current_line_width: f32 = 0.0, // width of lines if break_lines was false
touch_edit_just_focused: bool,

cursor_pt: ?Point = null,
cursor_event: ?dvui.Event.EventTypes = null,
click_pt: ?Point = null,
click_event: ?dvui.Event.EventTypes = null,
click_num: u8 = 0,

bytes_seen: usize = 0,
first_byte_in_line: usize = 0,
selection_in: ?*Selection = null,
/// SAFETY: Set in `install`, might point to `selection_store`
selection: *Selection = undefined,
selection_store: Selection = .{},

/// For simplicity we only handle a single kind of selection change per frame
sel_move: union(enum) {
    none: void,

    // mouse down to move cursor and dragging to select
    mouse: struct {
        down_pt: ?Point = null, // point we got the mouse down (frame 1)
        byte: ?usize = null, // byte index of pt (find on frame 1, keep while captured)
        drag_pt: ?Point = null, // point of current mouse drag
    },

    // second click or touch selects word at pointer
    // third click selects line at pointer
    expand_pt: struct {
        pt: ?Point = null,
        bytes: [2]usize = .{ 0, 0 }, // start and end of original selection while dragging
        select: bool = true, // false - move cursor, true - change selection
        dragging: bool = false,
        done: bool = false, // finished our work this frame?
        which: enum {
            word,
            line,
            home,
            end,
        },
        last: [2]usize = .{ 0, 0 }, // index of last 2 space/newline we've seen
    },

    // moving left/right by characters
    char_left_right: struct {
        count: i8 = 0,
        select: bool = true, // false - move cursor, true - change selection
        buf: [20]u8 = [1]u8{0} ** 20, // only used when count < 0
    },

    // moving cursor up/down
    // - this can be pipelined, so we might get more count on the same frame 2
    // we are adjusting for the previous count
    cursor_updown: struct {
        count: i8 = 0, // positive is down (get this on frame 1, set pt once we see the cursor)
        pt: ?Point = null, // get this on frame 2
        select: bool = true, // false - move cursor, true - change selection
    },

    // moving left/right by words
    word_left_right: struct {
        count: i8 = 0,
        select: bool = true, // false - move cursor, true - change selection
        scratch_kind: enum {
            punc, // space, newline, or ascii puncutation
            word,
        } = .punc,
        // indexes of the last starts of words (only used when count < 0)
        word_start_idx: [5]usize = .{ 0, 0, 0, 0, 0 },
    },
} = .none,

sel_start_r: Rect = .{},
sel_start_r_new: ?Rect = null,
sel_end_r: Rect = .{},
sel_end_r_new: ?Rect = null,
sel_pts: [2]?Point = [2]?Point{ null, null },

cursor_seen: bool = false,
/// SAFETY: Set in `textAddEx`
cursor_rect: Rect = undefined,
scroll_to_cursor: bool = false,
scroll_to_cursor_next_frame: bool = false,

add_text_done: bool = false,

copy_sel: ?Selection = null,
copy_slice: ?[]u8 = null,

// when this is true and we have focus, show the floating widget with select all, copy, etc.
touch_editing: bool = false,
te_first: bool = true,
te_show_draggables: bool = true,
te_show_context_menu: bool = true,
te_focus_on_touchdown: bool = false,
focus_at_start: bool = false,
/// SAFETY: Set in `touchEditing`
te_floating: FloatingWidget = undefined,

cache_layout: bool = false,
cache_layout_bytes: ?bytesNeededReturn = null,
cache_layout_bytes_seen: usize = 0,
byte_height_ready: ?ByteHeight = null,
byte_heights: []ByteHeight = undefined, // from last frame
byte_heights_new: std.ArrayList(ByteHeight) = .empty, // creating this frame
byte_height_after_idx: ?usize = null,
byte_height_edit_idx: ?usize = null,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) TextLayoutWidget {
    const options = defaults.override(opts);
    var self = TextLayoutWidget{
        .wd = WidgetData.init(src, .{}, options),
        .selection_in = init_opts.selection,
        .break_lines = init_opts.break_lines,
        .cache_layout = init_opts.cache_layout,
        .kerning = init_opts.kerning,
        .touch_edit_just_focused = init_opts.touch_edit_just_focused,
    };
    if (dvui.dataGet(null, self.wd.id, "_touch_editing", bool)) |val| self.touch_editing = val;
    if (dvui.dataGet(null, self.wd.id, "_te_first", bool)) |val| self.te_first = val;
    if (dvui.dataGet(null, self.wd.id, "_te_show_draggables", bool)) |val| self.te_show_draggables = val;
    if (dvui.dataGet(null, self.wd.id, "_te_show_context_menu", bool)) |val| self.te_show_context_menu = val;
    if (dvui.dataGet(null, self.wd.id, "_te_focus_on_touchdown", bool)) |val| self.te_focus_on_touchdown = val;
    if (dvui.dataGet(null, self.wd.id, "_sel_start_r", Rect)) |val| self.sel_start_r = val;
    if (dvui.dataGet(null, self.wd.id, "_sel_end_r", Rect)) |val| self.sel_end_r = val;
    if (dvui.dataGet(null, self.wd.id, "_click_num", u8)) |val| self.click_num = val;
    if (dvui.dataGetSlice(null, self.wd.id, "_byte_heights", []ByteHeight)) |bh| {
        self.byte_heights = bh;
    } else {
        self.byte_heights = &[0]ByteHeight{};
    }

    if (dvui.dataGet(null, self.wd.id, "_scroll_to_cursor", bool) orelse false) {
        dvui.dataRemove(null, self.wd.id, "_scroll_to_cursor");
        self.scroll_to_cursor = true;
    }

    const scale_old = dvui.dataGetPtrDefault(null, self.wd.id, "_scale", f32, dvui.parentGet().screenRectScale(Rect{}).s);
    const scale_new = dvui.parentGet().screenRectScale(Rect{}).s;
    if (self.cache_layout and scale_old.* != scale_new) {
        dvui.log.debug("TextLayoutWidget forcing cache_layout false due to scale change", .{});
        self.cache_layout = false;
    }
    scale_old.* = scale_new;

    const break_lines_old = dvui.dataGetPtrDefault(null, self.wd.id, "_break_lines", bool, self.break_lines);
    if (self.cache_layout and break_lines_old.* != self.break_lines) {
        dvui.log.debug("TextLayoutWidget forcing cache_layout false due to break_lines change", .{});
        self.cache_layout = false;
    }
    break_lines_old.* = self.break_lines;

    const width_old = dvui.dataGetPtrDefault(null, self.wd.id, "_width", f32, self.data().rect.w);
    if (self.cache_layout and self.break_lines and width_old.* != self.data().rect.w) {
        dvui.log.debug("TextLayoutWidget forcing cache_layout false due to width change while break_lines", .{});
        self.cache_layout = false;
    }
    width_old.* = self.data().rect.w;

    return self;
}

pub fn install(self: *TextLayoutWidget, opts: struct { focused: ?bool = null, show_touch_draggables: bool = true }) void {
    self.focus_at_start = opts.focused orelse (self.data().id == dvui.focusedWidgetId());

    self.data().register();
    dvui.parentSet(self.widget());

    if (self.selection_in) |sel| {
        self.selection = sel;
    } else {
        if (dvui.dataGet(null, self.data().id, "_selection", Selection)) |s| {
            self.selection_store = s;
        }
        self.selection = &self.selection_store;
    }

    if (dvui.captured(self.data().id)) {
        if (dvui.dataGet(null, self.data().id, "_sel_move_mouse_byte", usize)) |p| {
            self.sel_move = .{ .mouse = .{ .byte = p } };
        }

        if (dvui.dataGet(null, self.data().id, "_sel_move_expand_pt_which", @TypeOf(self.sel_move.expand_pt.which))) |w| {
            if (dvui.dataGet(null, self.data().id, "_sel_move_expand_pt_bytes", [2]usize)) |bytes| {
                // set done to true, only matters if we are dragging which sets it back to false
                self.sel_move = .{ .expand_pt = .{ .which = w, .bytes = bytes, .done = true } };
            }
        }
    }

    if (dvui.dataGet(null, self.data().id, "_sel_move_cursor_updown_pt", Point)) |p| {
        self.sel_move = .{ .cursor_updown = .{ .pt = p } };
        dvui.dataRemove(null, self.data().id, "_sel_move_cursor_updown_pt");
        if (dvui.dataGet(null, self.data().id, "_sel_move_cursor_updown_select", bool)) |cud| {
            self.sel_move.cursor_updown.select = cud;
            dvui.dataRemove(null, self.data().id, "_sel_move_cursor_updown_select");
        }
    }

    const control_opts: Options = .{};

    const rs = self.data().contentRectScale();

    self.data().borderAndBackground(.{});

    // clip to background rect for possible corner widgets, addTextEx clips to content rect
    self.prevClip = dvui.clip(self.data().backgroundRectScale().r);

    if (opts.show_touch_draggables and self.touch_editing and self.te_show_draggables and self.focus_at_start and self.data().visible()) {
        const size = 36;
        {

            // calculate visible before FloatingWidget changes clip

            // We only draw if visible (to prevent drawing way outside the
            // textLayout), but we always process the floating window so that
            // we maintain capture.  That way you can drag a draggable off the
            // textLayout (so it's not visible), which causes a scroll, but
            // when the draggable shows back up you are still dragging it.

            // sel_start_r might be just off the right-hand edge, so widen it
            var cursor = self.sel_start_r;
            cursor.x -= 1;
            cursor.w += 1;
            const visible = !dvui.clipGet().intersect(rs.rectToPhysical(cursor)).empty();

            var rect = self.sel_start_r;
            rect.y += rect.h; // move to below the line
            const srs = self.screenRectScale(rect);
            rect = dvui.windowRectScale().rectFromPhysical(srs.r);
            rect.x -= size;
            rect.w = size;
            rect.h = size;

            var fc = dvui.FloatingWidget.init(@src(), .{}, .{ .rect = rect });
            fc.install();

            var offset: Point.Physical = dvui.dataGet(null, fc.data().id, "_offset", Point.Physical) orelse .{};

            const fcrs = fc.data().rectScale();
            const evts = dvui.events();
            for (evts) |*e| {
                if (!dvui.eventMatch(e, .{ .id = fc.data().id, .r = fcrs.r }))
                    continue;

                if (e.evt == .mouse) {
                    const me = e.evt.mouse;
                    if (me.action == .press and me.button.touch()) {
                        dvui.captureMouse(fc.data(), e.num);
                        self.te_show_context_menu = false;
                        offset = fcrs.r.topRight().diff(me.p);

                        // give an extra offset of half the cursor height
                        offset.y -= self.sel_start_r.h * 0.5 * rs.s;
                    } else if (me.action == .release and me.button.touch()) {
                        dvui.captureMouse(null, e.num);
                        dvui.dragEnd();
                    } else if (me.action == .motion and dvui.captured(fc.data().id)) {
                        const corner = me.p.plus(offset);
                        self.sel_pts[0] = self.data().contentRectScale().pointFromPhysical(corner);
                        self.sel_pts[1] = self.sel_end_r.topLeft().plus(.{ .y = self.sel_end_r.h / 2 });

                        self.sel_pts[0].?.y = @min(self.sel_pts[0].?.y, self.sel_pts[1].?.y);

                        dvui.scrollDrag(.{
                            .mouse_pt = e.evt.mouse.p,
                            .screen_rect = self.data().rectScale().r,
                        });
                    }
                }
            }

            if (visible) {
                var path: dvui.Path.Builder = .init(dvui.currentWindow().lifo());
                defer path.deinit();

                path.addPoint(.{ .x = fcrs.r.x + fcrs.r.w, .y = fcrs.r.y });
                path.addArc(.{ .x = fcrs.r.x + fcrs.r.w / 2, .y = fcrs.r.y + fcrs.r.h / 2 }, fcrs.r.w / 2, std.math.pi, 0, true);

                path.build().fillConvex(.{ .color = control_opts.color(.fill) });
                path.build().stroke(.{ .thickness = 1.0 * fcrs.s, .color = self.data().options.color(.border), .closed = true });
            }

            dvui.dataSet(null, fc.data().id, "_offset", offset);
            fc.deinit();
        }

        {
            // calculate visible before FloatingWidget changes clip

            // sel_end_r might be just off the right-hand edge, so widen it
            var cursor = self.sel_end_r;
            cursor.x -= 1;
            cursor.w += 1;
            const visible = !dvui.clipGet().intersect(rs.rectToPhysical(cursor)).empty();

            var rect = self.sel_end_r;
            rect.y += rect.h; // move to below the line
            const srs = self.screenRectScale(rect);
            rect = dvui.windowRectScale().rectFromPhysical(srs.r);
            rect.w = size;
            rect.h = size;

            var fc = dvui.FloatingWidget.init(@src(), .{}, .{ .rect = rect });
            fc.install();

            var offset: Point.Physical = dvui.dataGet(null, fc.data().id, "_offset", Point.Physical) orelse .{};

            const fcrs = fc.data().rectScale();
            const evts = dvui.events();
            for (evts) |*e| {
                if (!dvui.eventMatch(e, .{ .id = fc.data().id, .r = fcrs.r }))
                    continue;

                if (e.evt == .mouse) {
                    const me = e.evt.mouse;
                    if (me.action == .press and me.button.touch()) {
                        dvui.captureMouse(fc.data(), e.num);
                        self.te_show_context_menu = false;
                        offset = fcrs.r.topLeft().diff(me.p);

                        // give an extra offset of half the cursor height
                        offset.y -= self.sel_start_r.h * 0.5 * rs.s;
                    } else if (me.action == .release and me.button.touch()) {
                        dvui.captureMouse(null, e.num);
                        dvui.dragEnd();
                    } else if (me.action == .motion and dvui.captured(fc.data().id)) {
                        const corner = me.p.plus(offset);
                        self.sel_pts[0] = self.sel_start_r.topLeft().plus(.{ .y = self.sel_start_r.h / 2 });
                        self.sel_pts[1] = self.data().contentRectScale().pointFromPhysical(corner);

                        self.sel_pts[1].?.y = @max(self.sel_pts[0].?.y, self.sel_pts[1].?.y);

                        dvui.scrollDrag(.{
                            .mouse_pt = e.evt.mouse.p,
                            .screen_rect = self.data().rectScale().r,
                        });
                    }
                }
            }

            if (visible) {
                var path: dvui.Path.Builder = .init(dvui.currentWindow().lifo());
                defer path.deinit();

                path.addPoint(.{ .x = fcrs.r.x, .y = fcrs.r.y });
                path.addArc(.{ .x = fcrs.r.x + fcrs.r.w / 2, .y = fcrs.r.y + fcrs.r.h / 2 }, fcrs.r.w / 2, std.math.pi, 0, true);

                path.build().fillConvex(.{ .color = control_opts.color(.fill) });
                path.build().stroke(.{ .thickness = 1.0 * fcrs.s, .color = self.data().options.color(.border), .closed = true });
            }

            dvui.dataSet(null, fc.data().id, "_offset", offset);
            fc.deinit();
        }
    }
    if (self.data().accesskit_node()) |ak_node| {
        dvui.AccessKit.nodeSetReadOnly(ak_node);
    }
}

pub fn format(self: *TextLayoutWidget, comptime fmt: []const u8, args: anytype, opts: Options) void {
    comptime if (!std.unicode.utf8ValidateSlice(fmt)) @compileError("Format strings must be valid utf-8");
    const cw = dvui.currentWindow();
    const l = std.fmt.allocPrint(cw.lifo(), fmt, args) catch |err| blk: {
        dvui.logError(@src(), err, "Failed to print", .{});
        break :blk fmt;
    };
    defer if (l.ptr != fmt.ptr) cw.lifo().free(l);
    self.addText(l, opts);
}

pub fn addText(self: *TextLayoutWidget, text: []const u8, opts: Options) void {
    _ = self.addTextEx(text, .none, opts);
}

pub fn addTextClick(self: *TextLayoutWidget, text: []const u8, opts: Options) ?dvui.Event.EventTypes {
    return self.addTextEx(text, .click, opts);
}

pub const AddLinkOptions = struct {
    /// url navigated to when clicked
    url: []const u8,

    /// text shown to user - if null, uses url
    text: ?[]const u8 = null,
};

pub fn addLink(self: *TextLayoutWidget, init_opts: AddLinkOptions, opts: Options) void {
    const defs: Options = .{ .color_text = dvui.themeGet().focus };
    if (self.addTextClick(init_opts.text orelse init_opts.url, defs.override(opts))) |click_event| {
        const new_window = (click_event == .mouse and (click_event.mouse.button == .middle or click_event.mouse.mod.matchBind("ctrl/cmd")));
        _ = dvui.openURL(.{ .url = init_opts.url, .new_window = new_window });
    }
}

pub fn addTextHover(self: *TextLayoutWidget, text: []const u8, opts: Options) ?dvui.Event.EventTypes {
    return self.addTextEx(text, .hover, opts);
}

pub fn addTextTooltip(self: *TextLayoutWidget, src: std.builtin.SourceLocation, text: []const u8, tooltip: []const u8, opts: Options) void {
    var tt: dvui.FloatingTooltipWidget = .init(src, .{
        .active_rect = .{},
        .position = .sticky,
    }, .{ .id_extra = opts.idExtra() });

    if (self.addTextHover(text, opts)) |_| {
        tt.init_options.active_rect = dvui.windowRectPixels();
    }

    if (tt.shown()) {
        var tl = dvui.textLayout(@src(), .{}, .{ .background = false });
        tl.addText(tooltip, .{});
        tl.deinit();
    }

    tt.deinit();
}

// Helper to addTextEx
// - returns byte position if p is before or within r
fn findPoint(self: *TextLayoutWidget, p: Point, r: Rect, bytes_seen: usize, txt: []const u8, options: Options) ?struct { byte: usize, affinity: Selection.Affinity = .after } {
    if (p.y < r.y or (p.y < (r.y + r.h) and p.x < r.x)) {
        // found it - p is before this rect
        return .{ .byte = bytes_seen };
    }

    if (p.y < (r.y + r.h) and p.x < (r.x + r.w)) {
        // found it - p is in this rect
        const how_far = p.x - r.x;
        var pt_end: usize = undefined;
        _ = options.fontGet().textSizeEx(txt, .{ .kerning = self.kerning, .max_width = how_far, .end_idx = &pt_end, .end_metric = .nearest });
        return .{ .byte = bytes_seen + pt_end, .affinity = if (pt_end == txt.len) .before else .after };
    }

    var newline = false;
    if (txt.len > 0 and (txt[txt.len - 1] == '\n')) {
        newline = true;
    }

    if (newline and p.y < (r.y + r.h)) {
        // found it - p is after this rect on same horizontal line
        return .{ .byte = bytes_seen + txt.len - 1 };
    }

    return null;
}

// Called for each piece of text before searching for the cursor.
// Place for selection movement to track points and move the cursor if needed,
// also to track any state they need before the cursor (like word select).
fn selMovePre(self: *TextLayoutWidget, txt: []const u8, end: usize, text_rect: Rect, options: Options) void {
    const text_line = txt[0..end];
    switch (self.sel_move) {
        .none => {},
        .mouse => |*m| {
            if (m.down_pt) |p| {
                if (self.findPoint(p, text_rect, self.bytes_seen, text_line, options)) |ba| {
                    m.byte = ba.byte;
                    self.selection.moveCursor(ba.byte, false);
                    self.selection.affinity = ba.affinity;
                    m.down_pt = null;
                } else {
                    // haven't found it yet, keep cursor at end to not trigger cursor_seen
                    self.selection.moveCursor(self.bytes_seen + end, false);
                }
            } else if (m.drag_pt) |p| {
                if (self.findPoint(p, text_rect, self.bytes_seen, text_line, options)) |ba| {
                    self.selection.cursor = ba.byte;
                    self.selection.start = @min(m.byte.?, ba.byte);
                    self.selection.end = @max(m.byte.?, ba.byte);
                    self.selection.affinity = ba.affinity;
                    m.drag_pt = null;
                } else {
                    // haven't found it yet, keep cursor at end to not trigger cursor_seen
                    self.selection.cursor = self.bytes_seen + end;
                    self.selection.start = @min(m.byte.?, self.selection.cursor);
                    self.selection.end = @max(m.byte.?, self.selection.cursor);
                    self.selection.affinity = .after;
                }
            }
        },
        .expand_pt => |*ep| {
            if (ep.pt) |p| {
                if (self.findPoint(p, text_rect, self.bytes_seen, text_line, options)) |ba| {
                    self.selection.moveCursor(ba.byte, false);
                    self.selection.affinity = ba.affinity;
                    ep.pt = null;
                } else {
                    // haven't found it yet, keep cursor at end to not trigger cursor_seen
                    self.selection.moveCursor(self.bytes_seen + end, false);
                }

                if (ep.dragging) {
                    self.selection.start = @min(self.selection.start, ep.bytes[0]);
                    self.selection.end = @max(self.selection.end, ep.bytes[1]);
                }
            }
        },
        .char_left_right => {},
        .cursor_updown => |*cud| {
            if (cud.pt) |p| {
                if (self.findPoint(p, text_rect, self.bytes_seen, text_line, options)) |ba| {
                    self.selection.moveCursor(ba.byte, cud.select);
                    self.selection.affinity = ba.affinity;
                    cud.pt = null;
                } else {
                    // haven't found it yet, keep cursor at end to not trigger cursor_seen
                    self.selection.moveCursor(self.bytes_seen + end, cud.select);
                }
            }
        },
        .word_left_right => {},
    }
}

// Called when we transition to a new line without seeing a newline char.
// Place for selection movement that is tracking a point to say that the cursor
// should be at the end of the previous line.
fn lineBreak(self: *TextLayoutWidget) void {
    switch (self.sel_move) {
        .none => {},
        .mouse => |*m| {
            if (m.down_pt) |p| {
                if (p.y < self.insert_pt.y) {
                    // point was right of previous line, no newline
                    m.byte = self.bytes_seen;
                    self.selection.affinity = .before;
                    m.down_pt = null;

                    self.cursorSeen();
                }
            } else if (m.drag_pt) |p| {
                if (p.y < self.insert_pt.y) {
                    // point was right of previous line, no newline
                    self.selection.cursor = self.bytes_seen;
                    self.selection.start = @min(m.byte.?, self.selection.cursor);
                    self.selection.end = @max(m.byte.?, self.selection.cursor);
                    self.selection.affinity = .before;
                    m.drag_pt = null;

                    self.cursorSeen();
                }
            }
        },
        .expand_pt => |*ep| {
            if (ep.pt) |p| {
                if (p.y < self.insert_pt.y) {
                    // point was right of previous line, no newline
                    if (ep.last[0] == self.bytes_seen) {
                        // we are at the end of a line and the ending character
                        // was a space, so ignore it
                        ep.last[0] = ep.last[1];
                        self.selection.moveCursor(self.bytes_seen -| 1, false);
                    } else {
                        self.selection.moveCursor(self.bytes_seen, false);
                        self.selection.affinity = .before;
                    }
                    ep.pt = null;

                    self.cursorSeen();
                }
            }

            // if we are doing something like move to end of line, we'll
            // already have moved the cursor to the end of the text and now we
            // find a line break
            if (!ep.done and self.cursor_seen) {
                if (!ep.select) {
                    self.selection.moveCursor(self.selection.cursor, false);
                }

                self.selection.affinity = .before;

                if (!ep.dragging) {
                    ep.bytes[1] = self.selection.end;
                }

                ep.done = true;
            }
        },
        .cursor_updown => |*cud| {
            if (cud.pt) |p| {
                if (p.y < self.insert_pt.y) {
                    // point was right of previous line, no newline
                    self.selection.moveCursor(self.bytes_seen, cud.select);
                    self.selection.affinity = .before;
                    cud.pt = null;

                    self.cursorSeen();
                }
            }
        },
        .char_left_right => {},
        .word_left_right => {},
    }
}

// Called for each text processed (maybe empty), text will not straddle cursor.
// Place for selection movement (like word select) to adjust around cursor.
fn selMoveText(self: *TextLayoutWidget, txt: []const u8, start_idx: usize) void {
    if (txt.len == 0) {
        return;
    }

    switch (self.sel_move) {
        .none => {},
        .mouse => {},
        .expand_pt => |*ep| {
            if (!ep.done) {
                const search = if (ep.which == .word) word_breaks else "\n";
                if (!self.cursor_seen) {
                    // maintain index of last punc we saw
                    if (std.mem.lastIndexOfAny(u8, txt, search)) |space| {
                        ep.last[1] = ep.last[0];
                        ep.last[0] = start_idx + space + 1;
                        if (std.mem.lastIndexOfAny(u8, txt[0..space], search)) |space2| {
                            ep.last[1] = start_idx + space2 + 1;
                        }
                    }
                } else {
                    // searching for next punc
                    if (std.mem.indexOfAny(u8, txt, search)) |space| {
                        // found within our current text
                        self.selection.moveCursor(start_idx + space, ep.select);
                        ep.done = true;
                    } else {
                        // push the cursor to the end, we might see it in lineBreak
                        self.selection.moveCursor(start_idx + txt.len, ep.select);
                    }

                    if (ep.which == .end) {
                        self.scroll_to_cursor_next_frame = true;
                    }

                    if (!ep.dragging) {
                        ep.bytes[1] = self.selection.end;
                    }

                    if (ep.dragging) {
                        self.selection.start = @min(self.selection.start, ep.bytes[0]);
                        self.selection.end = @max(self.selection.end, ep.bytes[1]);
                    }
                }
            }
        },
        .char_left_right => |*clr| {
            if (!self.cursor_seen and clr.count < 0) {
                // save a small lookback buffer

                for (clr.buf, 0..) |_, i| {
                    if (i + txt.len >= clr.buf.len) {
                        clr.buf[i] = txt[txt.len + i - clr.buf.len];
                    } else {
                        clr.buf[i] = clr.buf[i + txt.len];
                    }
                }
            }

            while (self.cursor_seen and clr.count > 0) {
                var cur = self.selection.cursor;

                if (cur == self.first_byte_in_line and self.selection.affinity == .before and !clr.select) {
                    self.selection.affinity = .after;
                } else if (cur < start_idx + txt.len) {
                    const newline = txt[cur - start_idx] == '\n';

                    // move cursor one utf8 char right
                    cur += std.unicode.utf8ByteSequenceLength(txt[cur - start_idx]) catch 1;

                    self.selection.moveCursor(cur, clr.select);
                    if (cur == start_idx + txt.len and !newline) {
                        self.selection.affinity = .before;
                    }
                } else {
                    // nothing we can do on this iteration
                    break;
                }

                clr.count -= 1;

                self.scroll_to_cursor_next_frame = true;
                dvui.refresh(null, @src(), self.data().id);
            }
        },
        .cursor_updown => {},
        .word_left_right => |*wlr| {
            if (wlr.count < 0) {
                // maintain our list of previous starts of words, looking backwards
                var idx = txt.len -| 1;
                var last_kind: enum { punc, word } = if (std.mem.indexOfAnyPos(u8, txt, idx, word_breaks) != null) .punc else .word;

                var word_start_count: usize = 0;

                loop: while (word_start_count < wlr.word_start_idx.len) {
                    switch (last_kind) {
                        .punc => {
                            if (std.mem.lastIndexOfNone(u8, txt[0..idx], word_breaks)) |word_end| {
                                last_kind = .word;
                                idx = word_end;
                            } else {
                                // all punc
                                break :loop;
                            }
                        },
                        .word => {
                            var new_word_start: ?usize = null;
                            if (std.mem.lastIndexOfAny(u8, txt[0..idx], word_breaks)) |punc| {
                                last_kind = .punc;
                                idx = punc;
                                new_word_start = idx + 1;
                            } else {
                                // all word
                                idx = 0;
                                if (wlr.scratch_kind == .punc) {
                                    // last char from previous iteration was punc and we started with word
                                    new_word_start = idx;
                                }
                            }

                            if (new_word_start) |ws| {
                                var i = wlr.word_start_idx.len - 1;
                                while (i > word_start_count) : (i -= 1) {
                                    wlr.word_start_idx[i] = wlr.word_start_idx[i - 1];
                                }
                                wlr.word_start_idx[word_start_count] = start_idx + ws;
                                word_start_count += 1;
                            }

                            if (idx == 0) {
                                break :loop;
                            }
                        },
                    }
                }

                // record last character kind for next iteration
                if (std.mem.indexOfAnyPos(u8, txt, txt.len -| 1, word_breaks) != null) {
                    wlr.scratch_kind = .punc;
                } else {
                    wlr.scratch_kind = .word;
                }
            }

            while (self.cursor_seen and wlr.count > 0) {
                // do this first, so if we break out of the loop but never see
                // more text we still scroll to cursor
                self.scroll_to_cursor_next_frame = true;
                dvui.refresh(null, @src(), self.data().id);

                switch (wlr.scratch_kind) {
                    .punc => {
                        // skipping over punc
                        if (std.mem.indexOfNonePos(u8, txt, self.selection.cursor -| start_idx, word_breaks)) |non_blank| {
                            self.selection.moveCursor(start_idx + non_blank, wlr.select);
                            wlr.scratch_kind = .word; // now want to skip over word chars
                        } else {
                            // rest was punc
                            self.selection.moveCursor(start_idx + txt.len, wlr.select);
                            break;
                        }
                    },
                    .word => {
                        // skipping over word chars
                        if (std.mem.indexOfAnyPos(u8, txt, self.selection.cursor -| start_idx, word_breaks)) |punc| {
                            self.selection.moveCursor(start_idx + punc, wlr.select);
                            // done with this one
                            wlr.scratch_kind = .punc; // now want to skip over punc
                            wlr.count -= 1;
                        } else {
                            // rest was word
                            self.selection.moveCursor(start_idx + txt.len, wlr.select);
                            break;
                        }
                    },
                }
            }
        },
    }
}

fn cursorSeen(self: *TextLayoutWidget) void {
    self.cursor_seen = true;
    const cr = self.cursor_rect;

    switch (self.sel_move) {
        .none => {},
        .mouse => {},
        .expand_pt => |*ep| {
            if (!ep.done) {
                switch (ep.which) {
                    .word => {
                        self.selection.start = @max(ep.last[0], self.first_byte_in_line);
                        self.selection.cursor = self.selection.end; // put cursor at end so later expansion works
                    },
                    .line => {
                        self.selection.start = self.first_byte_in_line;
                        self.selection.cursor = self.selection.end; // put cursor at end so later expansion works
                    },
                    .home => {
                        self.selection.moveCursor(self.first_byte_in_line, ep.select);
                        ep.done = true;
                        self.scroll_to_cursor_next_frame = true;
                    },
                    .end => {
                        self.scroll_to_cursor_next_frame = true;
                    },
                }

                if (!ep.dragging) {
                    ep.bytes[0] = self.selection.start;
                    ep.bytes[1] = self.selection.end;
                }

                if (ep.dragging) {
                    self.selection.start = @min(self.selection.start, ep.bytes[0]);
                    self.selection.end = @max(self.selection.end, ep.bytes[1]);
                }

                dvui.refresh(null, @src(), self.data().id);
            }
        },
        .char_left_right => |*clr| {
            if (clr.count < 0) {
                const oldcur = self.selection.cursor;
                var cur = self.selection.cursor;
                while (clr.count < 0 and cur > 0 and (oldcur - cur + 1) <= clr.buf.len) {
                    if (cur == self.first_byte_in_line and self.selection.affinity == .after and !clr.select) {
                        if (clr.buf[clr.buf.len + cur - oldcur - 1] == '\n') {
                            cur -= 1;
                            self.selection.moveCursor(cur, clr.select);
                        } else {
                            self.selection.affinity = .before;
                        }
                    } else {
                        // move cursor one utf8 char left
                        cur -|= 1;
                        while (cur > 0 and oldcur - cur <= clr.buf.len and clr.buf[clr.buf.len + cur - oldcur] & 0xc0 == 0x80) {
                            // in the middle of a multibyte char
                            cur -|= 1;
                        }

                        var bail = false;
                        while ((oldcur - cur) > clr.buf.len or (cur <= oldcur and clr.buf[clr.buf.len + cur - oldcur] & 0xc0 == 0x80)) {
                            // couldn't get to a good place, so reverse
                            cur += 1;
                            bail = true;
                        }

                        if (bail) break;

                        self.selection.moveCursor(cur, clr.select);
                    }

                    clr.count += 1;
                }

                clr.count = 0;

                self.scroll_to_cursor_next_frame = true;
                dvui.refresh(null, @src(), self.data().id);
            }
        },
        .cursor_updown => |*cud| {
            if (cud.count != 0) {
                // If we had cursor_updown.pt from last frame, we don't get
                // cursor_seen until we've moved the cursor to that point
                const cr_new = cr.plus(.{ .y = @as(f32, @floatFromInt(cud.count)) * cr.h });
                const updown_pt = cr_new.topLeft().plus(.{ .y = cr_new.h / 2 });
                cud.count = 0;

                // forward the pixel position we want the cursor to be in to
                // the next frame
                dvui.dataSet(null, self.data().id, "_sel_move_cursor_updown_pt", updown_pt);
                dvui.dataSet(null, self.data().id, "_sel_move_cursor_updown_select", cud.select);
                dvui.refresh(null, @src(), self.data().id);

                // even though we scrolled to where we thought the cursor would
                // be, we might have moved up from a long line to a short one
                // and need to scroll horizontally
                self.scroll_to_cursor_next_frame = true;
            }
        },
        .word_left_right => |*wlr| {
            if (wlr.count < 0) {
                const idx2 = @min(-wlr.count - 1, wlr.word_start_idx.len - 1);
                self.selection.moveCursor(wlr.word_start_idx[@intCast(idx2)], wlr.select);
                wlr.count = 0;

                self.scroll_to_cursor_next_frame = true;
                dvui.refresh(null, @src(), self.data().id);
            }
        },
    }

    if (self.scroll_to_cursor) {
        dvui.scrollTo(.{
            .screen_rect = self.screenRectScale(cr.outset(self.data().options.paddingGet())).r,
            // cursor might just have transitioned to a new line, so scroll area has not expanded yet
            .over_scroll = true,
        });
    }
}

pub const ByteHeight = struct {
    pub const dist: f32 = 200.0; // record byte/height every this many logical pixels

    /// byte just after a newline (or after the last byte)
    byte: usize,

    /// height from top of text layout content rect
    height: f32,
};

const bytesNeededReturn = struct { start: usize, end: usize };

pub fn bytesNeeded(self: *TextLayoutWidget, edit_start: usize, edit_end: usize, edit_added: i64) ?bytesNeededReturn {
    if (self.byte_heights.len == 0) return null;

    // intersect our content rect with the clipping rect
    const clip_logical = self.data().contentRectScale().rectFromPhysical(dvui.clipGet());
    const vr = self.data().contentRect().intersect(clip_logical);

    var start_byte: usize = 0;
    var end_byte: usize = self.byte_heights[self.byte_heights.len - 1].byte;

    const Context = struct { height: f32, byte: usize };
    var context: Context = .{ .height = vr.y, .byte = edit_start };
    var sel_end: usize = edit_end;
    var end_height = vr.y + vr.h;

    if (self.copy_sel) |sel| {
        context.byte = @min(context.byte, sel.start);
        sel_end = @max(sel_end, sel.end);
    }

    var include_cursor = self.scroll_to_cursor;

    // if we are moving the cursor, need to process the text around where we are moving it
    switch (self.sel_move) {
        .none => {},
        .mouse => {}, // all in visible region
        .expand_pt => |*ep| {
            switch (ep.which) {
                .word, .line => {}, // all in visible region
                .home, .end => include_cursor = true,
            }
        },
        .char_left_right => include_cursor = true,
        .cursor_updown => |*cud| {
            if (cud.pt) |p| {
                // found cursor last frame, need to include p this frame
                context.height = @min(context.height, p.y);
                end_height = @max(end_height, p.y);
            } else {
                // we are looking for the cursor to move from
                include_cursor = true;
            }
        },
        .word_left_right => include_cursor = true,
    }

    if (include_cursor) {
        context.byte = @min(context.byte, self.selection.cursor);
        sel_end = @max(sel_end, self.selection.cursor);
    }

    // binary search for the start
    const predicateFn = struct {
        fn predicateFn(ctx: Context, item: ByteHeight) bool {
            return item.height <= ctx.height and item.byte < ctx.byte;
        }
    }.predicateFn;

    var first_past_height = std.sort.partitionPoint(ByteHeight, self.byte_heights, context, predicateFn);
    if (first_past_height == self.byte_heights.len) {
        // can't start at the final
        first_past_height -|= 1;
    }

    if (first_past_height > 0) {
        // starting not at the top
        const startBH = self.byte_heights[first_past_height - 1];
        start_byte = startBH.byte;

        self.insert_pt.y = startBH.height;
        self.bytes_seen = start_byte;

        if (!include_cursor and (self.selection.cursor < self.bytes_seen)) {
            std.debug.assert(self.cursor_seen == false);
            self.cursor_rect = Rect{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = 1, .h = 10 };
            self.cursorSeen();
        }

        switch (self.sel_move) {
            .word_left_right => |*wlr| {
                if (wlr.count < 0) {
                    // update default so that if someone does tons of word left in
                    // the same frame (so they move to before we started processing
                    // text, they will only go back to this index (instead of 0)
                    for (&wlr.word_start_idx) |*i| {
                        i.* = start_byte;
                    }
                }
            },
            else => {},
        }

        //std.debug.print("setting min height to {d}\n", .{self.insert_pt.y});

        // set min height just to make sure it happens
        const start_size = self.data().options.padSize(.{ .h = self.insert_pt.y });
        self.data().min_size.h = @max(self.data().min_size.h, start_size.h);

        // copy all the ByteHeights we skipped
        self.byte_heights_new.appendSlice(dvui.currentWindow().arena(), self.byte_heights[0..first_past_height]) catch {};
    }

    // linear scan for the end (but not the final)
    for (self.byte_heights[first_past_height .. self.byte_heights.len - 1], first_past_height..) |bh, i| {
        if (bh.height >= end_height and bh.byte > sel_end) {
            //std.debug.print("found end {d} {d} bh height {d} vr {d} {d} {d}\n", .{ i, self.byte_heights.len, bh.height, vr.y, vr.h, vr.y + vr.h });
            end_byte = bh.byte;

            self.byte_height_after_idx = i;
            break;
        }
    }

    // assume min width stays the same
    self.data().min_size.w = (dvui.minSizeGet(self.data().id) orelse Size.all(0)).w;

    // adjust end_byte for any edits
    if (edit_added >= 0) {
        end_byte += @intCast(edit_added);
    } else {
        end_byte -= @intCast(-edit_added);
    }

    //std.debug.print("bytesNeeded end {d} {d} {d}\n", .{ start_byte, end_byte, edit_added });

    return .{ .start = start_byte, .end = end_byte };
}

const AddTextExAction = enum {
    none,
    click,
    hover,
};

fn addTextEx(self: *TextLayoutWidget, text_in: []const u8, action: AddTextExAction, opts: Options) ?dvui.Event.EventTypes {
    var ret: ?dvui.Event.EventTypes = null;
    const cw = dvui.currentWindow();

    // clip to content rect for all text
    _ = dvui.clip(self.data().contentRectScale().r);

    var txt = dvui.toUtf8(cw.lifo(), text_in) catch |err| blk: {
        dvui.logError(@src(), err, "Failed to convert to utf8", .{});
        break :blk text_in;
    };
    defer if (txt.ptr != txt.ptr) cw.lifo().free(txt);

    if (self.cache_layout) {
        if (self.cache_layout_bytes == null) self.cache_layout_bytes = self.bytesNeeded(std.math.maxInt(usize), 0, 0);

        if (self.cache_layout_bytes) |clb| {
            const start = @min(txt.len, clb.start -| self.cache_layout_bytes_seen);
            const end = @min(txt.len, clb.end -| self.cache_layout_bytes_seen);
            self.cache_layout_bytes_seen += txt.len;

            //std.debug.print("{d} clb {d} .. {d} bytes {d} taking {d} .. {d}\n", .{ self.bytes_seen, clb.start, clb.end, self.cache_layout_bytes_seen, start, end });

            txt = txt[start..end];
            if (txt.len == 0) return null;
        } else {
            // bytesNeeded returned null, we can't do it this frame
            self.cache_layout = false;
        }
    }

    const options = self.data().options.override(opts);
    const msize = options.fontGet().sizeM(1, 1);
    const line_height = options.fontGet().lineHeight();
    self.current_line_height = @max(self.current_line_height, line_height);

    var container_width = self.data().contentRect().w;
    if (container_width == 0) {
        // if we are not being shown at all, probably this is the first
        // frame for us and we should calculate our min height assuming we
        // get at least our min width

        container_width = self.data().options.min_size_contentGet().w;
        if (container_width == 0) {
            // wasn't given a min width, assume something
            container_width = 500;
        }
    }

    text_loop: while (txt.len > 0) {
        if (self.byte_height_ready) |bhr| {
            //std.debug.print("byte_height_new append {d} {d}\n", .{ bhr.byte, bhr.height });
            self.byte_heights_new.append(cw.arena(), bhr) catch {};
            self.byte_height_ready = null;
        }

        var linestart: f32 = 0;

        // Often we measure text for a size, then try to render text into that
        // size.  Sometimes due to floating point this width will be very
        // slightly less than the width of the text that textSizeEx below sees,
        // causing a line break.  So give ourselves a tiny bit of extra room.
        var linewidth = container_width + 0.001;
        var width = linewidth - self.insert_pt.x;
        var width_after: f32 = 0;
        for (self.corners, 0..) |corner, i| {
            if (corner) |cor| {
                if (@max(cor.y, self.insert_pt.y) < @min(cor.y + cor.h, self.insert_pt.y + msize.h)) {
                    linewidth -= cor.w;
                    if (linestart == cor.x) {
                        // used below - if we moved over for a widget, we
                        // can drop to the next line expecting more room
                        // later
                        linestart = (cor.x + cor.w);
                    }

                    if (self.insert_pt.x <= (cor.x + cor.w)) {
                        width -= cor.w;
                        if (self.insert_pt.x >= cor.x) {
                            // widget on left side, skip over it
                            self.insert_pt.x = (cor.x + cor.w);
                        } else {
                            // widget on right side, need to add width to min_size below
                            width_after = self.corners_min_size[i].?.w;
                        }
                    }
                }
            }
        }

        var end: usize = undefined;

        var kern_buf: [10]u32 = @splat(0);

        // get slice of text that fits within width or ends with newline
        var s = options.fontGet().textSizeEx(txt, .{ .kerning = self.kerning, .max_width = if (self.break_lines) width else null, .end_idx = &end, .kern_out = &kern_buf });

        // ensure we always get at least 1 codepoint so we make progress
        if (end == 0) {
            end = std.unicode.utf8ByteSequenceLength(txt[0]) catch 1;
            s = options.fontGet().textSizeEx(txt[0..end], .{ .kerning = self.kerning });
        }

        const newline = (txt[end - 1] == '\n');

        //std.debug.print("{d} 1 txt to {d} \"{s}\"\n", .{ container_width, end, txt[0..end] });

        if (self.break_lines) blk: {

            // try to break on space if:
            // - slice ended due to width (not newline)
            // - linewidth is long enough (otherwise too narrow to break on space)
            if (end < txt.len and !newline and linewidth > (10 * msize.w)) {
                // now we are under the length limit but might be in the middle of a word
                // look one char further because we might be right at the end of a word
                const spaceIdx = std.mem.lastIndexOfLinear(u8, txt[0 .. end + 1], " ");
                if (spaceIdx) |si| {
                    end = si + 1;
                    s = options.fontGet().textSizeEx(txt[0..end], .{ .kerning = self.kerning, .kern_in = &kern_buf });
                    break :blk; // this part will fit
                }

                // couldn't break of space, fall through
            }

            // drop to next line without doing anything if:
            // - we are boxed in too much by corner widgets
            // - we aren't starting at the left edge
            // both mean dropping to next line will give us more space
            if (s.w > width and (linewidth < container_width or self.insert_pt.x > linestart)) {
                self.insert_pt.y += self.current_line_height;
                self.insert_pt.x = 0;
                self.current_line_height = line_height;

                self.lineBreak();

                self.first_byte_in_line = self.bytes_seen;

                continue :text_loop;
            }
        }

        // now we know the line of text we are about to render
        // see if selection needs to be updated

        // if the text changed our selection might be in the middle of utf8 chars, so fix it up
        while (self.selection.start >= self.bytes_seen and self.selection.start < self.bytes_seen + end and txt[self.selection.start - self.bytes_seen] & 0xc0 == 0x80) {
            self.selection.start += 1;
        }

        while (self.selection.cursor >= self.bytes_seen and self.selection.cursor < self.bytes_seen + end and txt[self.selection.cursor - self.bytes_seen] & 0xc0 == 0x80) {
            self.selection.cursor += 1;
        }

        while (self.selection.end >= self.bytes_seen and self.selection.end < self.bytes_seen + end and txt[self.selection.end - self.bytes_seen] & 0xc0 == 0x80) {
            self.selection.end += 1;
        }

        if (action != .none) {
            if (self.cursor_pt) |p| {
                const rs = Rect{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = s.w, .h = s.h };
                if (p.x > rs.x and p.x < (rs.x + rs.w) and p.y > rs.y and p.y < (rs.y + rs.h)) {
                    // point is in this text
                    if (action == .click) {
                        dvui.cursorSet(.hand);
                    } else if (action == .hover) {
                        ret = self.cursor_event;
                    }
                }
            }

            if (self.click_pt) |p| {
                const rs = Rect{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = s.w, .h = s.h };
                if (p.x > rs.x and p.x < (rs.x + rs.w) and p.y > rs.y and p.y < (rs.y + rs.h)) {
                    if (action == .click) {
                        ret = self.click_event;
                    }
                }
            }
        }

        // handle selection movement
        const text_rect = Rect{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = s.w, .h = s.h };
        self.selMovePre(txt, end, text_rect, options);

        if (self.sel_pts[0] != null or self.sel_pts[1] != null) {
            var sel_bytes = [2]?usize{ null, null };
            for (self.sel_pts, 0..) |maybe_pt, i| {
                if (maybe_pt) |p| {
                    const rs = Rect{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = s.w, .h = s.h };
                    if (p.y < rs.y or (p.y < (rs.y + rs.h) and p.x < rs.x)) {
                        // point is before this text
                        sel_bytes[i] = self.bytes_seen;
                        self.sel_pts[i] = null;
                    } else if (p.y < (rs.y + rs.h) and p.x < (rs.x + rs.w)) {
                        // point is in this text
                        const how_far = p.x - rs.x;
                        var pt_end: usize = undefined;
                        _ = options.fontGet().textSizeEx(txt, .{ .kerning = self.kerning, .max_width = how_far, .end_idx = &pt_end, .end_metric = .nearest });
                        sel_bytes[i] = self.bytes_seen + pt_end;
                        self.sel_pts[i] = null;
                    } else {
                        if (newline and p.y < (rs.y + rs.h)) {
                            // point is after this text on this same horizontal line
                            sel_bytes[i] = self.bytes_seen + end - 1;
                            self.sel_pts[i] = null;
                        } else {
                            // point is after this text, but we might not get anymore
                            sel_bytes[i] = self.bytes_seen + end;
                        }
                    }
                }
            }

            //std.debug.print("sel_bytes {?d} {?d}\n", .{ sel_bytes[0], sel_bytes[1] });

            // start off getting both, then maybe getting one
            if (sel_bytes[0] != null and sel_bytes[1] != null) {
                self.selection.cursor = @min(sel_bytes[0].?, sel_bytes[1].?);
                self.selection.start = @min(sel_bytes[0].?, sel_bytes[1].?);
                self.selection.end = @max(sel_bytes[0].?, sel_bytes[1].?);

                // changing touch selection, need to refresh to move draggables
                dvui.refresh(null, @src(), self.data().id);
            } else if (sel_bytes[0] != null or sel_bytes[1] != null) {
                self.selection.end = sel_bytes[0] orelse sel_bytes[1].?;
            }
        }

        // record screen position of selection for touch editing (use s for
        // height in case we are calling textSize with an empty slice)
        if (self.selection.start >= self.bytes_seen and self.selection.start <= self.bytes_seen + end) {
            const start_off = options.fontGet().textSize(txt[0..self.selection.start -| self.bytes_seen]);
            self.sel_start_r_new = .{ .x = self.insert_pt.x + start_off.w, .y = self.insert_pt.y, .w = 1, .h = s.h };
        }

        if (self.selection.end >= self.bytes_seen and self.selection.end <= self.bytes_seen + end) {
            const end_off = options.fontGet().textSize(txt[0..self.selection.end -| self.bytes_seen]);
            self.sel_end_r_new = .{ .x = self.insert_pt.x + end_off.w, .y = self.insert_pt.y, .w = 1, .h = s.h };
        }

        if (!self.cursor_seen and (self.selection.cursor < self.bytes_seen + end or (self.selection.cursor == self.bytes_seen + end and self.selection.affinity == .before))) {
            std.debug.assert(self.selection.cursor >= self.bytes_seen);
            const cursor_offset = self.selection.cursor - self.bytes_seen;
            const text_to_cursor = txt[0..cursor_offset];
            const size = options.fontGet().textSize(text_to_cursor);
            self.cursor_rect = Rect{ .x = self.insert_pt.x + size.w, .y = self.insert_pt.y, .w = 1, .h = s.h };

            self.selMoveText(text_to_cursor, self.bytes_seen);
            self.cursorSeen(); // might alter selection
            self.selMoveText(txt[cursor_offset..end], self.bytes_seen + cursor_offset);
        } else {
            self.selMoveText(txt[0..end], self.bytes_seen);
        }

        { // Scope here is for deallocating rtxt before handling copying to clipboard on the arena
            const rs = self.screenRectScale(Rect{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = s.w, .h = @min(s.h, self.data().contentRect().h - self.insert_pt.y) });
            //std.debug.print("renderText: {} {s}\n", .{ rs.r, txt[0..end] });
            var rtxt = if (newline) txt[0 .. end - 1] else txt[0..end];

            // If the newline is part of the selection, then render it as a
            // selected space.  This matches Chrome's behavior, although this is
            // not a universal - Firefox doesn't do this.
            if (newline and
                (self.selection.start -| self.bytes_seen -| rtxt.len) == 0 and
                (self.selection.end -| self.bytes_seen -| rtxt.len) > 0)
            {
                rtxt = std.mem.concat(cw.lifo(), u8, &.{ rtxt, " " }) catch txt;
            }
            defer if (txt.ptr != rtxt.ptr) cw.lifo().free(rtxt);

            dvui.renderText(.{
                .font = options.fontGet(),
                .text = rtxt,
                .rs = rs,
                .color = options.color(.text),
                // TODO: Should this take `options.background` into account?
                .background_color = options.color_fill,
                .sel_start = self.selection.start -| self.bytes_seen,
                .sel_end = self.selection.end -| self.bytes_seen,
                .sel_color = (dvui.themeGet().text_select orelse dvui.themeGet().color(.highlight, .fill)).opacity(0.75),
                .kerning = self.kerning,
                .kern_in = &kern_buf,
            }) catch |err| {
                dvui.logError(@src(), err, "Failed to render text: {s}", .{rtxt});
            };
        }

        // Even if we don't actually render (might be outside clipping region),
        // need to update insert_pt and minSize like we did because our parent
        // might size based on that (might be in a scroll area)
        self.insert_pt.x += s.w;
        self.current_line_width += s.w;
        const size = self.data().options.padSize(.{ .w = self.current_line_width, .h = self.insert_pt.y + s.h });
        self.data().min_size.w = @max(self.data().min_size.w, size.w + width_after);
        self.data().min_size.h = @max(self.data().min_size.h, size.h);

        if (self.copy_sel) |sel| {
            // we are copying to clipboard
            if (sel.start < self.bytes_seen + end) {
                // need to copy some
                const cstart = if (sel.start < self.bytes_seen) 0 else (sel.start - self.bytes_seen);
                const cend = if (sel.end < self.bytes_seen + end) (sel.end - self.bytes_seen) else end;

                // initialize or realloc
                if (self.copy_slice) |slice| {
                    const old_len = slice.len;
                    self.copy_slice = cw.arena().realloc(slice, slice.len + (cend - cstart)) catch slice;
                    if (self.copy_slice.?.len == old_len) {
                        dvui.log.debug("copy_slice realloc failed, copying will be incomplete", .{});
                    } else {
                        @memcpy(self.copy_slice.?[old_len..], txt[cstart..cend]);
                    }
                } else {
                    self.copy_slice = cw.arena().dupe(u8, txt[cstart..cend]) catch |err| blk: {
                        dvui.logError(@src(), err, "Could not allocate copy slice for text: {s}", .{txt[cstart..cend]});
                        break :blk null;
                    };
                }

                // push to clipboard if done
                if (sel.end <= self.bytes_seen + end) {
                    dvui.clipboardTextSet(self.copy_slice.?);
                    self.copy_sel = null;
                    cw.arena().free(self.copy_slice.?);
                    self.copy_slice = null;
                }
            }
        }

        // discard bytes we've dealt with
        txt = txt[end..];
        self.bytes_seen += end;

        if (!self.cursor_seen) {
            // until we see the cursor, record the last position it could be
            // in, could be moving to a new line next iteration
            self.cursor_rect = Rect{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = 1, .h = s.h };
        }

        // move insert_pt to next line if we have more text
        if (newline or txt.len > 0) {
            self.insert_pt.y += self.current_line_height;
            self.insert_pt.x = 0;
            self.current_line_height = line_height;

            if (newline) {
                const newline_size = self.data().options.padSize(.{ .w = self.current_line_width, .h = self.insert_pt.y + s.h });
                self.data().min_size.w = @max(self.data().min_size.w, newline_size.w);
                self.data().min_size.h = @max(self.data().min_size.h, newline_size.h);
                self.current_line_width = 0.0;

                var last_bh_height: f32 = 0;
                if (self.byte_heights_new.items.len > 0) {
                    last_bh_height = self.byte_heights_new.items[self.byte_heights_new.items.len - 1].height;
                }

                if (self.insert_pt.y > last_bh_height + ByteHeight.dist) {
                    self.byte_height_ready = .{ .byte = self.bytes_seen, .height = self.insert_pt.y };
                }
            } else if (txt.len > 0) {
                self.lineBreak();
            }

            self.first_byte_in_line = self.bytes_seen;
        }

        if (newline and (self.selection.start == self.bytes_seen)) {
            self.sel_start_r_new = .{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = 1, .h = s.h };
        }

        if (newline and (self.selection.end == self.bytes_seen)) {
            self.sel_end_r_new = .{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = 1, .h = s.h };
        }

        if (self.data().options.rect != null) {
            // we were given a rect, so don't need to calculate our min height,
            // so stop as soon as we run off the end of the clipping region
            // this helps for performance
            const nextrs = self.screenRectScale(Rect{ .x = self.insert_pt.x, .y = self.insert_pt.y });
            if (nextrs.r.y > (dvui.clipGet().y + dvui.clipGet().h)) {
                //std.debug.print("stopping after: {s}\n", .{rtxt});
                break :text_loop;
            }
        }
    }

    if (action == .click and (ret != null)) {
        // we can only click when not in touch editing, so that click must have
        // transitioned us into touch editing, but we don't want to transition
        // if the click happened on clickable text
        self.touch_editing = false;
    }

    // TODO: This only shows the currently visible text. What behavior do we actually want here?
    if (self.data().accesskit_node()) |ak_node| {
        const ak_value = dvui.AccessKit.nodeValue(ak_node);
        if (ak_value != 0) {
            defer dvui.AccessKit.stringFree(ak_value);
            const current_value = std.mem.span(ak_value);
            allocate_new: {
                var new_value = cw.arena().allocWithOptions(u8, current_value.len + txt.len, null, 0) catch break :allocate_new;
                @memcpy(new_value[0..current_value.len], current_value);
                @memcpy(new_value[current_value.len .. current_value.len + txt.len], txt);

                dvui.AccessKit.nodeSetValue(ak_node, new_value);
            }
        } else {
            const str = cw.arena().dupeZ(u8, txt) catch "";
            defer cw.arena().free(str);
            dvui.AccessKit.nodeSetValue(ak_node, str);
        }
    }

    return ret;
}

pub fn addTextDone(self: *TextLayoutWidget, opts: Options) void {
    self.add_text_done = true;

    if (self.cache_layout and self.byte_heights.len > 0) {
        // sanity check
        std.debug.assert(self.cache_layout_bytes != null);

        var edit_height: f32 = undefined;
        if (self.byte_height_after_idx) |i| {
            // this is not the final one
            const bh = self.byte_heights[i];

            // we expected to end at bh.height without edits, this is the extra
            // height the edits gave (might be negative)
            edit_height = self.insert_pt.y - bh.height;
            const edit_bytes: i64 = @as(i64, @intCast(self.bytes_seen)) - @as(i64, @intCast(bh.byte));

            // these are the height and bytes we are skipping
            const extra_height = self.byte_heights[self.byte_heights.len - 1].height - bh.height;
            const extra_bytes = self.byte_heights[self.byte_heights.len - 1].byte - bh.byte;
            self.bytes_seen += extra_bytes;

            // set min height
            const end_size = self.data().options.padSize(.{ .h = self.insert_pt.y + extra_height });
            self.data().min_size.h = @max(self.data().min_size.h, end_size.h);

            // adjust for edits
            for (self.byte_heights[i..self.byte_heights.len]) |*bhh| {
                bhh.height += edit_height;
                if (edit_bytes >= 0) {
                    bhh.byte += @intCast(edit_bytes);
                } else {
                    bhh.byte -= @intCast(-edit_bytes);
                }
            }

            // copy all the ByteHeights we skipped, but not the final one
            self.byte_heights_new.appendSlice(dvui.currentWindow().arena(), self.byte_heights[i .. self.byte_heights.len - 1]) catch {};
        } else {
            // use the final one
            var bh = &self.byte_heights[self.byte_heights.len - 1];

            // we expected to end at bh.height without edits, this is the extra
            // height the edits gave (might be negative)
            const os = self.data().options;
            const contentMinSize = self.data().min_size.padNeg(os.paddingGet()).padNeg(os.borderGet()).padNeg(os.marginGet());
            edit_height = contentMinSize.h - bh.height;

            // adjust previous height for sanity check below
            bh.height += edit_height;
        }

        std.debug.assert(self.cache_layout_bytes_seen == self.bytes_seen);
        //std.debug.print("edit_height {d}\n", .{edit_height});

        // TODO: if edit_height is negative, we might not render some text for a frame - need to scan further in byte_heights until we find one that is not visible
    }

    const os = self.data().options;
    const contentMinSize = self.data().min_size.padNeg(os.paddingGet()).padNeg(os.borderGet()).padNeg(os.marginGet());
    self.byte_heights_new.append(dvui.currentWindow().arena(), .{ .byte = self.bytes_seen, .height = contentMinSize.h }) catch {};

    if (self.cache_layout) {
        // sanity check
        const old = self.byte_heights[self.byte_heights.len - 1].height;
        const new = self.byte_heights_new.items[self.byte_heights_new.items.len - 1].height;
        if (new < (old - 1.0) or new > (old + 1.0)) {
            dvui.logError(@src(), error.CacheLayoutError, "the height of the processed text changed by {d}, cache_layout should have been false this frame", .{new - old});
            self.byte_heights_new.clearAndFree(dvui.currentWindow().arena());
        }
    }
    //std.debug.print("final height: {d} at {d}\n", .{ contentMinSize.h, self.bytes_seen });

    //const crs = self.data().contentRectScale();
    //for (self.byte_heights_new.items) |bhn| {
    //    //std.debug.print("bh: {d} - {d}\n", .{ bhn.byte, bhn.height });
    //    const p: dvui.Path = .{ .points = &.{
    //        crs.pointToPhysical(.{ .x = 0, .y = bhn.height }),
    //        crs.pointToPhysical(.{ .x = 100, .y = bhn.height }),
    //    } };
    //    p.stroke(.{ .thickness = 1, .color = .red });
    //}

    self.selection.cursor = @min(self.selection.cursor, self.bytes_seen);
    self.selection.start = @min(self.selection.start, self.bytes_seen);
    self.selection.end = @min(self.selection.end, self.bytes_seen);

    const options = self.data().options.override(opts);
    const text_height = options.fontGet().textHeight();

    if (!self.cursor_seen) {
        self.cursor_rect = Rect{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = 1, .h = text_height };
        self.cursorSeen();
    }

    if (self.copy_sel) |_| {
        // we are copying to clipboard and never stopped
        dvui.clipboardTextSet(self.copy_slice orelse "");

        self.copy_sel = null;
        if (self.copy_slice) |cs| {
            dvui.currentWindow().arena().free(cs);
        }
        self.copy_slice = null;
    }

    // handle selection movement
    // - this logic must work even if addText() is never called
    switch (self.sel_move) {
        .none => {},
        .mouse => |*m| {
            if (m.down_pt) |_| {
                m.byte = self.bytes_seen;
                self.selection.moveCursor(self.bytes_seen, false);
                m.down_pt = null;
            }

            if (m.drag_pt) |_| {
                self.selection.cursor = self.bytes_seen;
                self.selection.start = @min(m.byte.?, self.bytes_seen);
                self.selection.end = @max(m.byte.?, self.bytes_seen);
                m.drag_pt = null;
            }
        },
        .expand_pt => |*ep| {
            if (!ep.done and !ep.select) {
                self.selection.moveCursor(self.selection.cursor, false);
            }
        },
        .char_left_right => {},
        .cursor_updown => |*cud| {
            if (cud.pt) |_| {
                self.selection.moveCursor(self.bytes_seen, cud.select);
                cud.pt = null;
            }
        },
        .word_left_right => {},
    }

    if (self.sel_start_r_new) |start_r| {
        if (!self.sel_start_r.equals(start_r)) {
            dvui.refresh(null, @src(), self.data().id);
        }
        self.sel_start_r = start_r;
    }

    if (self.selection.start > self.bytes_seen or self.bytes_seen == 0) {
        self.sel_start_r = .{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = 1, .h = text_height };
        if (self.selection.start > self.bytes_seen) {
            dvui.refresh(null, @src(), self.data().id);
        }
    }

    if (self.sel_end_r_new) |end_r| {
        if (!self.sel_end_r.equals(end_r)) {
            dvui.refresh(null, @src(), self.data().id);
        }
        self.sel_end_r = end_r;
    }

    if (self.selection.end > self.bytes_seen or self.bytes_seen == 0) {
        self.sel_end_r = .{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = 1, .h = text_height };
        if (self.selection.end > self.bytes_seen) {
            dvui.refresh(null, @src(), self.data().id);
        }
    }
}

pub fn touchEditing(self: *TextLayoutWidget) ?*FloatingWidget {
    if (self.touch_editing and self.te_show_context_menu and self.focus_at_start and self.data().visible()) {
        self.te_floating = dvui.FloatingWidget.init(@src(), .{}, .{});

        const r = dvui.windowRectScale().rectFromPhysical(dvui.clipGet());
        if (dvui.minSizeGet(self.te_floating.data().id)) |_| {
            const ms = dvui.minSize(self.te_floating.data().id, self.te_floating.data().options.min_sizeGet());
            self.te_floating.data().rect.w = ms.w;
            self.te_floating.data().rect.h = ms.h;

            self.te_floating.data().rect.x = r.x + r.w - self.te_floating.data().rect.w;
            self.te_floating.data().rect.y = r.y - self.te_floating.data().rect.h - self.data().options.paddingGet().y;

            self.te_floating.data().rect = .cast(dvui.placeOnScreen(dvui.windowRect(), .{ .x = self.te_floating.data().rect.x, .y = self.te_floating.data().rect.y }, .vertical, .cast(self.te_floating.data().rect)));
        } else {
            // need another frame to get our min size
            dvui.refresh(null, @src(), self.te_floating.data().id);
        }

        self.te_floating.install();
        return &self.te_floating;
    }

    return null;
}

pub fn touchEditingMenu(self: *TextLayoutWidget) void {
    var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{
        .corner_radius = dvui.ButtonWidget.defaults.themeOverride().corner_radiusGet(),
        .background = true,
        .border = dvui.Rect.all(1),
    });
    defer hbox.deinit();

    if (dvui.buttonIcon(
        @src(),
        "select all",
        dvui.entypo.swap,
        .{},
        .{},
        .{ .min_size_content = .{ .h = 20 }, .margin = Rect.all(2) },
    )) {
        self.selection.selectAll();
    }

    if (dvui.buttonIcon(
        @src(),
        "copy",
        dvui.entypo.copy,
        .{},
        .{},
        .{ .min_size_content = .{ .h = 20 }, .margin = Rect.all(2) },
    )) {
        self.copy();
    }
}

pub fn widget(self: *TextLayoutWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *TextLayoutWidget) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *TextLayoutWidget, id: dvui.Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;

    // For corner widgets, they might want to be closer to the border than the
    // text, so fit them without padding, but then need to adjust origin
    // because screenRectScale assumes we placed in the contentRect
    var ret = dvui.placeIn(self.data().backgroundRect().justSize(), min_size, e, g);
    ret.x -= self.data().options.paddingGet().x;
    ret.y -= self.data().options.paddingGet().y;

    const i: usize = if (g.y < 0.5) if (g.x < 0.5)
        0 // upleft
    else
        1 // upright
    else if (g.x < 0.5)
        2 // downleft
    else
        3; // downright

    self.corners[i] = ret;
    self.corners_last_seen = @intCast(i);
    return ret;
}

pub fn screenRectScale(self: *TextLayoutWidget, rect: Rect) RectScale {
    return self.data().contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *TextLayoutWidget, s: Size) void {
    if (self.corners_last_seen) |ls| {
        self.corners_min_size[ls] = s;
    }
    // we calculate our min size in deinit() after we have seen our text
}

// Using this function helps prevent accidentally using the selection when the
// end is way too large, because the way we do select all is to set end to
// maxInt(usize) and fix it up the next frame.
//
// Either the caller knows the max (like TextEntryWidget), or they can pass
// maxInt(usize) and be clued into what might happen.
pub fn selectionGet(self: *TextLayoutWidget, max: usize) *Selection {
    self.selection.start = @min(self.selection.start, max);
    self.selection.cursor = @min(self.selection.cursor, max);
    self.selection.end = @min(self.selection.end, max);
    return self.selection;
}

pub fn matchEvent(self: *TextLayoutWidget, e: *Event) bool {
    if (self.touch_editing and e.evt == .mouse and e.evt.mouse.action == .release and e.evt.mouse.button.touch()) {
        self.te_show_draggables = true;
        self.te_show_context_menu = true;
        dvui.refresh(null, @src(), self.data().id);
    }

    return dvui.eventMatchSimple(e, self.data());
}

pub fn processEvents(self: *TextLayoutWidget) void {
    const evts = dvui.events();
    for (evts) |*e| {
        if (!self.matchEvent(e))
            continue;

        self.processEvent(e);
    }
}

pub fn processEvent(self: *TextLayoutWidget, e: *Event) void {
    switch (e.evt) {
        .mouse => |me| {
            if (me.action == .focus) {
                e.handle(@src(), self.data());
                // focus so that we can receive keyboard input
                dvui.focusWidget(self.data().id, null, e.num);
            } else if (me.action == .press and (me.button.pointer() or me.button == .middle)) {
                e.handle(@src(), self.data());
                // capture and start drag
                dvui.captureMouse(self.data(), e.num);
                dvui.dragPreStart(me.p, .{ .cursor = .ibeam });

                if (me.button.touch()) {
                    self.te_focus_on_touchdown = self.focus_at_start;
                    if (self.touch_editing) {
                        self.te_show_context_menu = false;

                        // need to refresh draggables
                        dvui.refresh(null, @src(), self.data().id);
                    }
                } else if (me.button.pointer()) {
                    // a click always sets sel_move - has the highest priority
                    const p = self.data().contentRectScale().pointFromPhysical(me.p);
                    self.sel_move = .{ .mouse = .{ .down_pt = p } };
                    self.scroll_to_cursor = true;

                    if (self.click_num == 1) {
                        // select word we touched
                        self.sel_move = .{ .expand_pt = .{ .which = .word, .pt = p } };
                    } else if (self.click_num == 2) {
                        // select line we touched
                        self.sel_move = .{ .expand_pt = .{ .which = .line, .pt = p } };
                    }
                }
            } else if (me.action == .release and (me.button.pointer() or me.button == .middle)) {
                e.handle(@src(), self.data());

                if (dvui.captured(self.data().id)) {
                    if (!self.touch_editing and dvui.dragging(me.p, null) == null) {
                        // click without drag
                        self.click_pt = self.data().contentRectScale().pointFromPhysical(me.p);
                        self.click_event = e.evt;

                        if (me.button.pointer()) {
                            self.click_num += 1;
                            if (self.click_num == 4) {
                                self.click_num = 1;
                            }
                        }
                    }

                    if (me.button.touch()) {
                        // this was a touch-release without drag, which transitions
                        // us between touch editing
                        const p = self.data().contentRectScale().pointFromPhysical(me.p);

                        if (self.te_focus_on_touchdown) {
                            self.touch_editing = !self.touch_editing;
                            // move cursor to point
                            self.sel_move = .{ .mouse = .{ .down_pt = p } };
                            if (self.touch_editing) {
                                // select word we touched
                                self.sel_move = .{ .expand_pt = .{ .which = .word, .pt = p } };
                            }
                        } else {
                            if (self.touch_edit_just_focused) {
                                self.touch_editing = true;
                            }
                            if (self.te_first) {
                                // This is the very first time we are entering
                                // touch editing from not having focus, we want to
                                // position the cursor.
                                self.te_first = false;

                                // select word we touched
                                self.sel_move = .{ .expand_pt = .{ .which = .word, .pt = p } };
                            }
                        }
                        dvui.refresh(null, @src(), self.data().id);
                    }

                    dvui.captureMouse(null, e.num);
                    dvui.dragEnd();
                }
            } else if (me.action == .motion and dvui.captured(self.data().id)) {
                if (dvui.dragging(me.p, null)) |_| {
                    self.click_num = 0;
                    if (!me.button.touch()) {
                        e.handle(@src(), self.data());
                        if (self.sel_move == .mouse) {
                            self.sel_move.mouse.drag_pt = self.data().contentRectScale().pointFromPhysical(me.p);
                        } else if (self.sel_move == .expand_pt) {
                            self.sel_move.expand_pt.pt = self.data().contentRectScale().pointFromPhysical(me.p);
                            self.sel_move.expand_pt.done = false;
                            self.sel_move.expand_pt.dragging = true;
                        }
                        dvui.scrollDrag(.{
                            .mouse_pt = me.p,
                            .screen_rect = self.data().rectScale().r,
                        });
                    } else {
                        // user intended to scroll with a finger swipe
                        // release our capture including this event so a
                        // containing scroll container can get it
                        dvui.captureMouse(null, e.num - 1); // stop possible drag and capture
                        dvui.dragEnd();
                    }
                }
            } else if (me.action == .motion) {
                self.click_num = 0;
            } else if (me.action == .position) {
                self.cursor_pt = self.data().contentRectScale().pointFromPhysical(me.p);
                self.cursor_event = e.evt;
            }
        },
        .key => |ke| blk: {
            if (ke.action == .down and ke.matchBind("text_start_select")) {
                e.handle(@src(), self.data());
                self.selection.moveCursor(0, true);
                self.scroll_to_cursor = true;
                break :blk;
            }

            if (ke.action == .down and ke.matchBind("text_end_select")) {
                e.handle(@src(), self.data());
                self.selection.moveCursor(std.math.maxInt(usize), true);
                self.scroll_to_cursor = true;
                break :blk;
            }

            if (ke.action == .down and ke.matchBind("line_start_select")) {
                e.handle(@src(), self.data());
                if (self.sel_move == .none) {
                    self.sel_move = .{ .expand_pt = .{ .which = .home } };
                }
                break :blk;
            }

            if (ke.action == .down and ke.matchBind("line_end_select")) {
                e.handle(@src(), self.data());
                if (self.sel_move == .none) {
                    self.sel_move = .{ .expand_pt = .{ .which = .end } };
                }
                break :blk;
            }

            if ((ke.action == .down or ke.action == .repeat) and ke.matchBind("word_left_select")) {
                e.handle(@src(), self.data());
                if (self.sel_move == .none) {
                    self.sel_move = .{ .word_left_right = .{} };
                }
                if (self.sel_move == .word_left_right) {
                    self.sel_move.word_left_right.count -= 1;
                }
                break :blk;
            }

            if ((ke.action == .down or ke.action == .repeat) and ke.matchBind("word_right_select")) {
                e.handle(@src(), self.data());
                if (self.sel_move == .none) {
                    self.sel_move = .{ .word_left_right = .{} };
                }
                if (self.sel_move == .word_left_right) {
                    self.sel_move.word_left_right.count += 1;
                }
                break :blk;
            }

            if ((ke.action == .down or ke.action == .repeat) and ke.matchBind("char_left_select")) {
                e.handle(@src(), self.data());
                if (self.sel_move == .none) {
                    self.sel_move = .{ .char_left_right = .{} };
                }
                if (self.sel_move == .char_left_right) {
                    self.sel_move.char_left_right.count -= 1;
                }
                break :blk;
            }

            if ((ke.action == .down or ke.action == .repeat) and ke.matchBind("char_right_select")) {
                e.handle(@src(), self.data());
                if (self.sel_move == .none) {
                    self.sel_move = .{ .char_left_right = .{} };
                }
                if (self.sel_move == .char_left_right) {
                    self.sel_move.char_left_right.count += 1;
                }
                break :blk;
            }

            if ((ke.action == .down or ke.action == .repeat) and ke.matchBind("char_up_select")) {
                e.handle(@src(), self.data());
                if (self.sel_move == .none) {
                    self.sel_move = .{ .cursor_updown = .{} };
                }
                if (self.sel_move == .cursor_updown) {
                    self.sel_move.cursor_updown.count -= 1;
                }
                break :blk;
            }

            if ((ke.action == .down or ke.action == .repeat) and ke.matchBind("char_down_select")) {
                e.handle(@src(), self.data());
                if (self.sel_move == .none) {
                    self.sel_move = .{ .cursor_updown = .{} };
                }
                if (self.sel_move == .cursor_updown) {
                    self.sel_move.cursor_updown.count += 1;
                }
                break :blk;
            }

            if (ke.action == .down and ke.matchBind("copy")) {
                e.handle(@src(), self.data());
                self.copy();
                break :blk;
            }

            if (ke.action == .down and ke.matchBind("select_all")) {
                e.handle(@src(), self.data());
                self.selection.selectAll();
                break :blk;
            }
        },
        else => {},
    }
}

// must be called before addText()
pub fn copy(self: *TextLayoutWidget) void {
    self.copy_sel = self.selection.*;
}

pub fn deinit(self: *TextLayoutWidget) void {
    const should_free = self.data().was_allocated_on_widget_stack;
    defer if (should_free) dvui.widgetFree(self);
    defer self.* = undefined;
    if (!self.add_text_done) {
        self.addTextDone(.{});
    }

    // handle mouse cursor here after all addText because some might set the cursor
    const evts = dvui.events();
    for (evts) |*e| {
        if (!self.matchEvent(e))
            continue;

        if (e.evt == .mouse and e.evt.mouse.action == .position) {
            dvui.cursorSet(.ibeam);
        }
    }

    dvui.dataSet(null, self.data().id, "_touch_editing", self.touch_editing);
    dvui.dataSet(null, self.data().id, "_te_first", self.te_first);
    dvui.dataSet(null, self.data().id, "_te_show_draggables", self.te_show_draggables);
    dvui.dataSet(null, self.data().id, "_te_show_context_menu", self.te_show_context_menu);
    dvui.dataSet(null, self.data().id, "_te_focus_on_touchdown", self.te_focus_on_touchdown);
    dvui.dataSet(null, self.data().id, "_sel_start_r", self.sel_start_r);
    dvui.dataSet(null, self.data().id, "_sel_end_r", self.sel_end_r);
    dvui.dataSet(null, self.data().id, "_selection", self.selection.*);
    dvui.dataSetSlice(null, self.data().id, "_byte_heights", self.byte_heights_new.items);

    if (self.scroll_to_cursor_next_frame) {
        dvui.dataSet(null, self.data().id, "_scroll_to_cursor", true);
    }

    if (dvui.captured(self.data().id)) {
        if (self.sel_move == .mouse) {
            // once we figure out where the mousedown was, we need to save it
            // as long as we are dragging
            dvui.dataSet(null, self.data().id, "_sel_move_mouse_byte", self.sel_move.mouse.byte.?);
        } else if (self.sel_move == .expand_pt and (self.sel_move.expand_pt.which == .word or self.sel_move.expand_pt.which == .line)) {
            dvui.dataSet(null, self.data().id, "_sel_move_expand_pt_which", self.sel_move.expand_pt.which);
            dvui.dataSet(null, self.data().id, "_sel_move_expand_pt_bytes", self.sel_move.expand_pt.bytes);
        }
    }
    if (self.click_num == 0) {
        dvui.dataRemove(null, self.data().id, "_click_num");
    } else {
        dvui.dataSet(null, self.data().id, "_click_num", self.click_num);
    }
    dvui.clipSet(self.prevClip);

    // check if the widgets are taller than the text
    const left_height = (self.corners_min_size[0] orelse Size{}).h + (self.corners_min_size[2] orelse Size{}).h;
    const right_height = (self.corners_min_size[1] orelse Size{}).h + (self.corners_min_size[3] orelse Size{}).h;
    // adjust for corner widgets not being inside textLayout's padding
    const padded = self.data().options.padSize(.{ .h = @max(left_height, right_height) }).padNeg(self.data().options.paddingGet());
    self.data().min_size.h = @max(self.data().min_size.h, padded.h);

    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();
    dvui.parentReset(self.data().id, self.data().parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
