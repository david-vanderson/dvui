//! Maps to an OS window, and save all the state needed between frames.
//!
//! Usually this is created at app startup and `deinit` called on app shutdown.
//!
//! `dvui.currentWindow` returns this when between `begin`/`end`.

pub const Window = @This();
const Self = Window;

// Would it make sense to have a separate scope for the window ?
pub const log = std.log.scoped(.dvui);

backend: dvui.Backend,
previous_window: ?*Window = null,

/// list of subwindows including base, later windows are on top of earlier
/// windows
subwindows: std.ArrayList(Subwindow),

/// id of the subwindow widgets are being added to
subwindow_currentId: u32 = 0,

/// natural rect of the last subwindow, dialogs use this
/// to center themselves
subwindow_currentRect: Rect.Natural = .{},

/// id of the subwindow that has focus
focused_subwindowId: u32 = 0,

last_focused_id_this_frame: u32 = 0,

/// natural rect telling the backend where our text input box is:
/// * when non-null, we want an on screen keyboard if needed (phones)
/// * when showing the IME input window, position it near this
text_input_rect: ?Rect.Natural = null,

snap_to_pixels: bool = true,
alpha: f32 = 1.0,

events: std.ArrayListUnmanaged(Event) = .{},
event_num: u16 = 0,
/// mouse_pt tracks the last position we got a mouse event for
/// 1) used to add position info to mouse wheel events
/// 2) used to highlight the widget under the mouse (`dvui.Event.Mouse.Action` .position event)
/// 3) used to change the cursor (`dvui.Event.Mouse.Action` .position event)
// Start off screen so nothing is highlighted on the first frame
mouse_pt: Point.Physical = .{ .x = -1, .y = -1 },
mouse_pt_prev: Point.Physical = .{ .x = -1, .y = -1 },
inject_motion_event: bool = false,

drag_state: enum {
    none,
    prestart,
    dragging,
} = .none,
drag_pt: Point.Physical = .{},
drag_offset: Point.Physical = .{},
drag_name: []const u8 = "",

frame_time_ns: i128 = 0,
loop_wait_target: ?i128 = null,
loop_wait_target_event: bool = false,
loop_target_slop: i32 = 1000, // 1ms frame overhead seems a good place to start
loop_target_slop_frames: i32 = 0,
frame_times: [30]u32 = [_]u32{0} ** 30,

secs_since_last_frame: f32 = 0,
extra_frames_needed: u8 = 0,
clipRect: dvui.Rect.Physical = .{},

theme: Theme = undefined,

min_sizes: std.AutoHashMap(u32, SavedSize),
tags: std.StringHashMap(SavedTagData),
data_mutex: std.Thread.Mutex,
datas: std.AutoHashMap(u32, SavedData),
datas_trash: std.ArrayList(SavedData) = undefined,
animations: std.AutoHashMap(u32, Animation),
tab_index_prev: std.ArrayList(dvui.TabIndex),
tab_index: std.ArrayList(dvui.TabIndex),
font_cache: std.AutoHashMap(u32, dvui.FontCacheEntry),
font_bytes: std.StringHashMap(dvui.FontBytesEntry),
texture_cache: std.AutoHashMap(u32, dvui.TextureCacheEntry),
dialog_mutex: std.Thread.Mutex,
dialogs: std.ArrayList(Dialog),
toasts: std.ArrayList(Toast),
keybinds: std.StringHashMap(dvui.enums.Keybind),
themes: std.StringArrayHashMap(Theme),

cursor_requested: ?dvui.enums.Cursor = null,
cursor_dragging: ?dvui.enums.Cursor = null,

wd: WidgetData = undefined,
rect_pixels: dvui.Rect.Physical = .{},
natural_scale: f32 = 1.0,
/// can set separately but gets folded into natural_scale
content_scale: f32 = 1.0,
next_widget_ypos: f32 = 0,

capture: ?dvui.CaptureMouse = null,
captured_last_frame: bool = false,

gpa: std.mem.Allocator,
_arena: std.heap.ArenaAllocator,
texture_trash: std.ArrayList(dvui.Texture) = undefined,
render_target: dvui.RenderTarget = .{ .texture = null, .offset = .{} },
end_rendering_done: bool = false,

debug_window_show: bool = false,
/// 0 means no widget is selected
debug_widget_id: u32 = 0,
debug_widget_panic: bool = false,
debug_info_name_rect: []const u8 = "",
debug_info_src_id_extra: []const u8 = "",
debug_under_focus: bool = false,
debug_under_mouse: bool = false,
debug_under_mouse_esc_needed: bool = false,
debug_under_mouse_quitting: bool = false,
debug_under_mouse_info: []u8 = "",

debug_refresh_mutex: std.Thread.Mutex,
debug_refresh: bool = false,

/// when true, left mouse button works like a finger
debug_touch_simulate_events: bool = false,
debug_touch_simulate_down: bool = false,

pub const Subwindow = struct {
    id: u32 = 0,
    rect: Rect = Rect{},
    rect_pixels: dvui.Rect.Physical = .{},
    focused_widgetId: ?u32 = null,
    render_cmds: std.ArrayList(dvui.RenderCommand),
    render_cmds_after: std.ArrayList(dvui.RenderCommand),
    used: bool = true,
    modal: bool = false,
    stay_above_parent_window: ?u32 = null,
};

const SavedSize = struct {
    size: Size,
    used: bool = true,
};

const SavedTagData = struct {
    data: dvui.TagData,
    used: bool = true,
};

const SavedData = struct {
    used: bool = true,
    alignment: u8,
    data: []u8,

    type_str: if (builtin.mode == .Debug) []const u8 else void = undefined,
    copy_slice: if (builtin.mode == .Debug) bool else void = undefined,

    pub fn free(self: *const SavedData, allocator: std.mem.Allocator) void {
        if (self.data.len != 0) {
            allocator.rawFree(
                self.data,
                std.mem.Alignment.fromByteUnits(self.alignment),
                @returnAddress(),
            );
        }
    }
};

pub const InitOptions = struct {
    id_extra: usize = 0,
    arena: ?std.heap.ArenaAllocator = null,
    theme: ?*Theme = null,
    keybinds: ?enum {
        none,
        windows,
        mac,
    } = null,
};

pub fn init(
    src: std.builtin.SourceLocation,
    gpa: std.mem.Allocator,
    backend_ctx: dvui.Backend,
    init_opts: InitOptions,
) !Self {
    const hashval = dvui.hashSrc(null, src, init_opts.id_extra);

    var self = Self{
        .gpa = gpa,
        ._arena = init_opts.arena orelse std.heap.ArenaAllocator.init(gpa),
        .subwindows = std.ArrayList(Subwindow).init(gpa),
        .min_sizes = std.AutoHashMap(u32, SavedSize).init(gpa),
        .tags = std.StringHashMap(SavedTagData).init(gpa),
        .data_mutex = std.Thread.Mutex{},
        .datas = std.AutoHashMap(u32, SavedData).init(gpa),
        .animations = std.AutoHashMap(u32, Animation).init(gpa),
        .tab_index_prev = std.ArrayList(dvui.TabIndex).init(gpa),
        .tab_index = std.ArrayList(dvui.TabIndex).init(gpa),
        .font_cache = std.AutoHashMap(u32, dvui.FontCacheEntry).init(gpa),
        .texture_cache = std.AutoHashMap(u32, dvui.TextureCacheEntry).init(gpa),
        .dialog_mutex = std.Thread.Mutex{},
        .dialogs = std.ArrayList(Dialog).init(gpa),
        .toasts = std.ArrayList(Toast).init(gpa),
        .keybinds = std.StringHashMap(dvui.enums.Keybind).init(gpa),
        .debug_refresh_mutex = std.Thread.Mutex{},
        .wd = WidgetData{ .src = src, .id = hashval, .init_options = .{ .subwindow = true }, .options = .{ .name = "Window" } },
        .backend = backend_ctx,
        .font_bytes = try dvui.Font.initTTFBytesDatabase(gpa),
        .themes = std.StringArrayHashMap(Theme).init(gpa),
    };

    try self.themes.putNoClobber("Adwaita Light", @import("themes/Adwaita.zig").light);
    try self.themes.putNoClobber("Adwaita Dark", @import("themes/Adwaita.zig").dark);

    inline for (@typeInfo(Theme.QuickTheme.builtin).@"struct".decls) |decl| {
        const quick_theme = Theme.QuickTheme.fromString(self.arena(), @field(Theme.QuickTheme.builtin, decl.name)) catch {
            @panic("Failure loading builtin theme. This is a problem with DVUI.");
        };
        defer quick_theme.deinit();
        const theme = try quick_theme.value.toTheme(self.gpa);
        try self.themes.putNoClobber(theme.name, theme);
    }

    // Sort themes alphabetically
    const Context = struct {
        hashmap: *std.StringArrayHashMap(Theme),
        pub fn lessThan(ctx: @This(), lhs: usize, rhs: usize) bool {
            return std.ascii.orderIgnoreCase(ctx.hashmap.values()[lhs].name, ctx.hashmap.values()[rhs].name) == .lt;
        }
    };
    self.themes.sort(Context{ .hashmap = &self.themes });
    if (init_opts.theme) |t| {
        self.theme = t.*;
    } else {
        self.theme = self.themes.get("Adwaita Light").?;
    }

    try self.initEvents();

    const kb = init_opts.keybinds orelse blk: {
        if (builtin.os.tag.isDarwin()) {
            break :blk .mac;
        } else {
            break :blk .windows;
        }
    };

    if (kb == .windows or kb == .mac) {
        try self.keybinds.putNoClobber("activate", .{ .key = .enter, .also = "activate_1" });
        try self.keybinds.putNoClobber("activate_1", .{ .key = .space });

        try self.keybinds.putNoClobber("next_widget", .{ .key = .tab, .shift = false });
        try self.keybinds.putNoClobber("prev_widget", .{ .key = .tab, .shift = true });
    }

    switch (kb) {
        .none => {},
        .windows => {
            // zig fmt: off
                try self.keybinds.putNoClobber("cut",        .{ .key = .x, .control = true });
                try self.keybinds.putNoClobber("copy",       .{ .key = .c, .control = true });
                try self.keybinds.putNoClobber("paste",      .{ .key = .v, .control = true });
                try self.keybinds.putNoClobber("select_all", .{ .key = .a, .control = true });

                try self.keybinds.putNoClobber("ctrl/cmd",   .{ .key = .left_control, .also = "ctrl/cmd_1" });
                try self.keybinds.putNoClobber("ctrl/cmd_1", .{ .key = .right_control });

                try self.keybinds.putNoClobber("text_start",        .{ .key = .home, .shift = false, .control = true });
                try self.keybinds.putNoClobber("text_end",          .{ .key = .end,  .shift = false, .control = true });
                try self.keybinds.putNoClobber("text_start_select", .{ .key = .home, .shift = true,  .control = true });
                try self.keybinds.putNoClobber("text_end_select",   .{ .key = .end,  .shift = true,  .control = true });

                try self.keybinds.putNoClobber("line_start",        .{ .key = .home, .shift = false, .control = false });
                try self.keybinds.putNoClobber("line_end",          .{ .key = .end,  .shift = false, .control = false });
                try self.keybinds.putNoClobber("line_start_select", .{ .key = .home, .shift = true,  .control = false });
                try self.keybinds.putNoClobber("line_end_select",   .{ .key = .end,  .shift = true,  .control = false });

                try self.keybinds.putNoClobber("word_left",         .{ .key = .left,  .shift = false, .control = true });
                try self.keybinds.putNoClobber("word_right",        .{ .key = .right, .shift = false, .control = true });
                try self.keybinds.putNoClobber("word_left_select",  .{ .key = .left,  .shift = true,  .control = true });
                try self.keybinds.putNoClobber("word_right_select", .{ .key = .right, .shift = true,  .control = true });

                try self.keybinds.putNoClobber("char_left",         .{ .key = .left,  .shift = false, .control = false });
                try self.keybinds.putNoClobber("char_right",        .{ .key = .right, .shift = false, .control = false });
                try self.keybinds.putNoClobber("char_left_select",  .{ .key = .left,  .shift = true,  .control = false });
                try self.keybinds.putNoClobber("char_right_select", .{ .key = .right, .shift = true,  .control = false });

                try self.keybinds.putNoClobber("char_up",          .{ .key = .up,   .shift = false });
                try self.keybinds.putNoClobber("char_down",        .{ .key = .down, .shift = false });
                try self.keybinds.putNoClobber("char_up_select",   .{ .key = .up,   .shift = true });
                try self.keybinds.putNoClobber("char_down_select", .{ .key = .down, .shift = true });

                try self.keybinds.putNoClobber("delete_prev_word", .{ .key = .backspace, .control = true });
                try self.keybinds.putNoClobber("delete_next_word", .{ .key = .delete,    .control = true });
                // zig fmt: on
        },
        .mac => {
            // zig fmt: off
                try self.keybinds.putNoClobber("cut",        .{ .key = .x, .command = true });
                try self.keybinds.putNoClobber("copy",       .{ .key = .c, .command = true });
                try self.keybinds.putNoClobber("paste",      .{ .key = .v, .command = true });
                try self.keybinds.putNoClobber("select_all", .{ .key = .a, .command = true });

                try self.keybinds.putNoClobber("ctrl/cmd",   .{ .key = .left_command, .also = "ctrl/cmd_1" });
                try self.keybinds.putNoClobber("ctrl/cmd_1", .{ .key = .right_command });

                try self.keybinds.putNoClobber("text_start",        .{ .key = .up,   .shift = false, .command = true });
                try self.keybinds.putNoClobber("text_end",          .{ .key = .down, .shift = false, .command = true });
                try self.keybinds.putNoClobber("text_start_select", .{ .key = .up,   .shift = true,  .command = true });
                try self.keybinds.putNoClobber("text_end_select",   .{ .key = .down, .shift = true,  .command = true });

                try self.keybinds.putNoClobber("line_start",        .{ .key = .left,  .shift = false, .command = true });
                try self.keybinds.putNoClobber("line_end",          .{ .key = .right, .shift = false, .command = true });
                try self.keybinds.putNoClobber("line_start_select", .{ .key = .left,  .shift = true,  .command = true });
                try self.keybinds.putNoClobber("line_end_select",   .{ .key = .right, .shift = true,  .command = true });

                try self.keybinds.putNoClobber("word_left",         .{ .key = .left,  .shift = false, .alt = true });
                try self.keybinds.putNoClobber("word_right",        .{ .key = .right, .shift = false, .alt = true });
                try self.keybinds.putNoClobber("word_left_select",  .{ .key = .left,  .shift = true,  .alt = true });
                try self.keybinds.putNoClobber("word_right_select", .{ .key = .right, .shift = true,  .alt = true });

                try self.keybinds.putNoClobber("char_left",         .{ .key = .left,  .shift = false, .alt = false });
                try self.keybinds.putNoClobber("char_right",        .{ .key = .right, .shift = false, .alt = false });
                try self.keybinds.putNoClobber("char_left_select",  .{ .key = .left,  .shift = true,  .alt = false });
                try self.keybinds.putNoClobber("char_right_select", .{ .key = .right, .shift = true,  .alt = false });

                try self.keybinds.putNoClobber("char_up",          .{ .key = .up,   .shift = false, .command = false });
                try self.keybinds.putNoClobber("char_down",        .{ .key = .down, .shift = false, .command = false });
                try self.keybinds.putNoClobber("char_up_select",   .{ .key = .up,   .shift = true,  .command = false });
                try self.keybinds.putNoClobber("char_down_select", .{ .key = .down, .shift = true,  .command = false });

                try self.keybinds.putNoClobber("delete_prev_word", .{ .key = .backspace, .alt = true });
                try self.keybinds.putNoClobber("delete_next_word", .{ .key = .delete,    .alt = true });
                // zig fmt: on
        },
    }

    const winSize = self.backend.windowSize();
    const pxSize = self.backend.pixelSize();
    self.content_scale = self.backend.contentScale();

    // Even on hidpi screens I see slight flattening of the sides of glyphs
    // when snap_to_pixels is false, so we are going to default on for now.
    //const total_scale = self.content_scale * pxSize.w / winSize.w;
    //if (total_scale >= 2.0) {
    //    self.snap_to_pixels = false;
    //}

    log.info("window logical {} pixels {} natural scale {d} initial content scale {d} snap_to_pixels {}\n", .{ winSize, pxSize, pxSize.w / winSize.w, self.content_scale, self.snap_to_pixels });

    errdefer self.deinit();

    self.focused_subwindowId = self.wd.id;
    self.frame_time_ns = 1;

    if (dvui.useFreeType) {
        dvui.FontCacheEntry.intToError(c.FT_Init_FreeType(&dvui.ft2lib)) catch |err| {
            dvui.log.err("freetype error {!} trying to init freetype library\n", .{err});
            return error.freetypeError;
        };
    }

    return self;
}

pub fn deinit(self: *Self) void {
    for (self.datas_trash.items) |sd| {
        sd.free(self.gpa);
    }
    self.datas_trash.deinit();

    for (self.texture_trash.items) |tex| {
        self.backend.textureDestroy(tex);
    }
    self.texture_trash.deinit();

    {
        var it = self.datas.iterator();
        while (it.next()) |item| item.value_ptr.free(self.gpa);
        self.datas.deinit();
    }

    if (self.debug_under_mouse_info.len > 0) {
        self.gpa.free(self.debug_under_mouse_info);
        self.debug_under_mouse_info = "";
    }

    self.subwindows.deinit();
    self.min_sizes.deinit();
    self.tags.deinit();
    self.animations.deinit();
    self.tab_index_prev.deinit();
    self.tab_index.deinit();

    {
        var it = self.font_cache.iterator();
        while (it.next()) |item| {
            item.value_ptr.glyph_info.deinit();
            item.value_ptr.deinit(self);
        }
        self.font_cache.deinit();
    }

    {
        var it = self.texture_cache.iterator();
        while (it.next()) |item| {
            self.backend.textureDestroy(item.value_ptr.texture);
        }
        self.texture_cache.deinit();
    }

    self.dialogs.deinit();
    self.toasts.deinit();
    self.keybinds.deinit();
    self._arena.deinit();

    {
        var it = self.font_bytes.valueIterator();
        while (it.next()) |fbe| {
            if (fbe.allocator) |a| {
                a.free(fbe.ttf_bytes);
            }
        }
    }
    self.font_bytes.deinit();

    {
        for (self.themes.values()) |*theme| {
            theme.deinit(self.gpa);
        }
    }
    self.themes.deinit();
}

pub fn arena(self: *Self) std.mem.Allocator {
    return self._arena.allocator();
}

/// called from any thread
pub fn debugRefresh(self: *Self, val: ?bool) bool {
    self.debug_refresh_mutex.lock();
    defer self.debug_refresh_mutex.unlock();

    const previous = self.debug_refresh;
    if (val) |v| {
        self.debug_refresh = v;
    }

    return previous;
}

/// called from gui thread
pub fn refreshWindow(self: *Self, src: std.builtin.SourceLocation, id: ?u32) void {
    if (self.debugRefresh(null)) {
        log.debug("{s}:{d} refresh {?x}", .{ src.file, src.line, id });
    }
    self.extra_frames_needed = 1;
}

/// called from any thread
pub fn refreshBackend(self: *Self, src: std.builtin.SourceLocation, id: ?u32) void {
    if (self.debugRefresh(null)) {
        log.debug("{s}:{d} refreshBackend {?x}", .{ src.file, src.line, id });
    }
    self.backend.refresh();
}

pub fn focusSubwindowInternal(self: *Self, subwindow_id: ?u32, event_num: ?u16) void {
    const winId = subwindow_id orelse self.subwindow_currentId;
    if (self.focused_subwindowId != winId) {
        self.focused_subwindowId = winId;
        self.refreshWindow(@src(), null);
        if (event_num) |en| {
            for (self.subwindows.items) |*sw| {
                if (self.focused_subwindowId == sw.id) {
                    self.focusRemainingEventsInternal(en, sw.id, sw.focused_widgetId);
                    break;
                }
            }
        }
    }
}

pub fn focusRemainingEventsInternal(self: *Self, event_num: u16, focusWindowId: u32, focusWidgetId: ?u32) void {
    var evts = self.events.items;
    var k: usize = 0;
    while (k < evts.len) : (k += 1) {
        var e: *Event = &evts[k];
        if (e.num > event_num and e.focus_windowId != null) {
            e.focus_windowId = focusWindowId;
            e.focus_widgetId = focusWidgetId;
        }
    }
}

/// Add a keyboard event (key up/down/repeat) to the dvui event list.
///
/// This can be called outside begin/end.  You should add all the events
/// for a frame either before begin() or just after begin() and before
/// calling normal dvui widgets.  end() clears the event list.
pub fn addEventKey(self: *Self, event: Event.Key) !bool {
    if (self.debug_under_mouse and self.debug_under_mouse_esc_needed and event.action == .down and event.code == .escape) {
        // an escape will stop the debug stuff from following the mouse,
        // but need to stop it at the end of the frame when we've gotten
        // the info
        self.debug_under_mouse_quitting = true;
        return true;
    }

    self.positionMouseEventRemove();

    self.event_num += 1;
    try self.events.append(self.arena(), Event{
        .num = self.event_num,
        .evt = .{ .key = event },
        .focus_windowId = self.focused_subwindowId,
        .focus_widgetId = if (self.subwindows.items.len == 0) null else self.subwindowFocused().focused_widgetId,
    });

    const ret = (self.wd.id != self.focused_subwindowId);
    try self.positionMouseEventAdd();
    return ret;
}

/// Add an event that represents text being typed.  This is distinct from
/// key up/down because the text could come from an IME (Input Method
/// Editor).
///
/// This can be called outside begin/end.  You should add all the events
/// for a frame either before begin() or just after begin() and before
/// calling normal dvui widgets.  end() clears the event list.
pub fn addEventText(self: *Self, text: []const u8) !bool {
    return try self.addEventTextEx(text, false);
}

pub fn addEventTextEx(self: *Self, text: []const u8, selected: bool) !bool {
    self.positionMouseEventRemove();

    self.event_num += 1;
    try self.events.append(self.arena(), Event{
        .num = self.event_num,
        .evt = .{ .text = .{ .txt = try self._arena.allocator().dupe(u8, text), .selected = selected } },
        .focus_windowId = self.focused_subwindowId,
        .focus_widgetId = if (self.subwindows.items.len == 0) null else self.subwindowFocused().focused_widgetId,
    });

    const ret = (self.wd.id != self.focused_subwindowId);
    try self.positionMouseEventAdd();
    return ret;
}

/// Add a mouse motion event.  This is only for a mouse - for touch motion
/// use addEventTouchMotion().
///
/// This can be called outside begin/end.  You should add all the events
/// for a frame either before begin() or just after begin() and before
/// calling normal dvui widgets.  end() clears the event list.
pub fn addEventMouseMotion(self: *Self, pt: Point.Natural) !bool {
    self.positionMouseEventRemove();

    const newpt = pt.scale(self.natural_scale / self.content_scale, Point.Physical);
    //log.debug("mouse motion {d} {d} -> {d} {d}", .{ x, y, newpt.x, newpt.y });
    const dp = newpt.diff(self.mouse_pt);
    self.mouse_pt = newpt;
    const winId = self.windowFor(self.mouse_pt);

    // maybe could do focus follows mouse here
    // - generate a .focus event here instead of just doing focusWindow(winId, null);
    // - how to make it optional?

    self.event_num += 1;
    try self.events.append(self.arena(), Event{ .num = self.event_num, .evt = .{
        .mouse = .{
            .action = .{ .motion = dp },
            .button = if (self.debug_touch_simulate_events and self.debug_touch_simulate_down) .touch0 else .none,
            .p = self.mouse_pt,
            .floating_win = winId,
        },
    } });

    const ret = (self.wd.id != winId);
    try self.positionMouseEventAdd();
    return ret;
}

/// Add a mouse button event (like left button down/up).
///
/// This can be called outside begin/end.  You should add all the events
/// for a frame either before begin() or just after begin() and before
/// calling normal dvui widgets.  end() clears the event list.
pub fn addEventMouseButton(self: *Self, b: dvui.enums.Button, action: Event.Mouse.Action) !bool {
    return addEventPointer(self, b, action, null);
}

/// Add a touch up/down event.  This is similar to addEventMouseButton but
/// also includes a normalized (0-1) touch point.
///
/// This can be called outside begin/end.  You should add all the events
/// for a frame either before begin() or just after begin() and before
/// calling normal dvui widgets.  end() clears the event list.
pub fn addEventPointer(self: *Self, b: dvui.enums.Button, action: Event.Mouse.Action, xynorm: ?Point) !bool {
    if (self.debug_under_mouse and !self.debug_under_mouse_esc_needed and action == .press and b.pointer()) {
        // a left click or touch will stop the debug stuff from following
        // the mouse, but need to stop it at the end of the frame when
        // we've gotten the info
        self.debug_under_mouse_quitting = true;
        return true;
    }

    var bb = b;
    if (self.debug_touch_simulate_events and bb == .left) {
        bb = .touch0;
        if (action == .press) {
            self.debug_touch_simulate_down = true;
        } else if (action == .release) {
            self.debug_touch_simulate_down = false;
        }
    }

    self.positionMouseEventRemove();

    if (xynorm) |xyn| {
        self.mouse_pt = (Point{ .x = xyn.x * self.wd.rect.w, .y = xyn.y * self.wd.rect.h }).scale(self.natural_scale, Point.Physical);
    }

    const winId = self.windowFor(self.mouse_pt);

    if (action == .press and bb.pointer()) {
        // normally the focus event is what focuses windows, but since the
        // base window is instantiated before events are added, it has to
        // do any event processing as the events come in, right now
        if (winId == self.wd.id) {
            // focus the window here so any more key events get routed
            // properly
            self.focusSubwindowInternal(self.wd.id, null);
        }

        // add focus event
        self.event_num += 1;
        try self.events.append(self.arena(), Event{ .num = self.event_num, .evt = .{
            .mouse = .{
                .action = .focus,
                .button = bb,
                .p = self.mouse_pt,
                .floating_win = winId,
            },
        } });
    }

    self.event_num += 1;
    try self.events.append(self.arena(), Event{ .num = self.event_num, .evt = .{
        .mouse = .{
            .action = action,
            .button = bb,
            .p = self.mouse_pt,
            .floating_win = winId,
        },
    } });

    const ret = (self.wd.id != winId);
    try self.positionMouseEventAdd();
    return ret;
}

/// Add a mouse wheel event.  Positive ticks means scrolling up / scrolling left.
///
/// This can be called outside begin/end.  You should add all the events
/// for a frame either before begin() or just after begin() and before
/// calling normal dvui widgets.  end() clears the event list.
pub fn addEventMouseWheel(self: *Self, ticks: f32, dir: dvui.enums.Direction) !bool {
    self.positionMouseEventRemove();

    const winId = self.windowFor(self.mouse_pt);

    //std.debug.print("mouse wheel {d}\n", .{ticks});

    self.event_num += 1;
    try self.events.append(self.arena(), Event{ .num = self.event_num, .evt = .{
        .mouse = .{
            .action = if (dir == .vertical) .{ .wheel_y = ticks } else .{ .wheel_x = ticks },
            .button = .none,
            .p = self.mouse_pt,
            .floating_win = winId,
        },
    } });

    const ret = (self.wd.id != winId);
    try self.positionMouseEventAdd();
    return ret;
}

/// Add an event that represents a finger moving while touching the screen.
///
/// This can be called outside begin/end.  You should add all the events
/// for a frame either before begin() or just after begin() and before
/// calling normal dvui widgets.  end() clears the event list.
pub fn addEventTouchMotion(self: *Self, finger: dvui.enums.Button, xnorm: f32, ynorm: f32, dxnorm: f32, dynorm: f32) !bool {
    self.positionMouseEventRemove();

    const newpt = (Point{ .x = xnorm * self.wd.rect.w, .y = ynorm * self.wd.rect.h }).scale(self.natural_scale, Point.Physical);
    //std.debug.print("touch motion {} {d} {d}\n", .{ finger, newpt.x, newpt.y });
    self.mouse_pt = newpt;

    const dp = (Point{ .x = dxnorm * self.wd.rect.w, .y = dynorm * self.wd.rect.h }).scale(self.natural_scale, Point.Physical);

    const winId = self.windowFor(self.mouse_pt);

    self.event_num += 1;
    try self.events.append(self.arena(), Event{ .num = self.event_num, .evt = .{
        .mouse = .{
            .action = .{ .motion = dp },
            .button = finger,
            .p = self.mouse_pt,
            .floating_win = winId,
        },
    } });

    const ret = (self.wd.id != winId);
    try self.positionMouseEventAdd();
    return ret;
}

pub fn FPS(self: *const Self) f32 {
    const diff = self.frame_times[0];
    if (diff == 0) {
        return 0;
    }

    const avg = @as(f32, @floatFromInt(diff)) / @as(f32, @floatFromInt(self.frame_times.len - 1));
    const fps = 1_000_000.0 / avg;
    return fps;
}

/// Coordinates with `Window.waitTime` to run frames only when needed.
///
/// Typically called right before `Window.begin`.
///
/// See usage in the example folder for the backend of you choice.
pub fn beginWait(self: *Self, has_event: bool) i128 {
    var new_time = @max(self.frame_time_ns, self.backend.nanoTime());

    if (self.loop_wait_target) |target| {
        if (self.loop_wait_target_event and has_event) {
            // interrupted by event, so don't adjust slop for target
            //std.debug.print("beginWait interrupted by event\n", .{});
            return new_time;
        }

        //std.debug.print("beginWait adjusting slop\n", .{});
        // we were trying to sleep for a specific amount of time, adjust slop to
        // compensate if we didn't hit our target
        if (new_time > target) {
            // woke up later than expected
            self.loop_target_slop_frames = math.clamp(self.loop_target_slop_frames * 2, 1, 1000);
            self.loop_target_slop += self.loop_target_slop_frames;
        } else if (new_time < target) {
            // woke up sooner than expected
            self.loop_target_slop_frames = math.clamp(self.loop_target_slop_frames * 2, -1000, -1);
            self.loop_target_slop += self.loop_target_slop_frames;

            const max_behind = std.time.ns_per_ms;
            if (new_time > target - max_behind) {
                // we are early (but not too early), so spin a bit to try and hit target
                //var i: usize = 0;
                //var first_time = new_time;
                while (new_time < target) {
                    //i += 1;
                    self.backend.sleep(0);
                    new_time = @max(self.frame_time_ns, self.backend.nanoTime());
                }

                //if (i > 0) {
                //  std.debug.print("    begin {d} spun {d} {d}us\n", .{self.loop_target_slop, i, @divFloor(new_time - first_time, 1000)});
                //}
            }
        }

        // make sure this never gets too crazy -1ms to 100ms
        self.loop_target_slop = math.clamp(self.loop_target_slop, -1_000, 100_000);
    }

    //std.debug.print("beginWait {d:6} {d}\n", .{ self.loop_target_slop, self.loop_target_slop_frames });
    return new_time;
}

/// Takes output of `Window.end` and optionally a max fps.  Returns microseconds
/// the app should wait (with event interruption) before running the render loop again.
///
/// Pass return value to backend.waitEventTimeout().
/// Cooperates with `Window.beginWait` to estimate how much time is being spent
/// outside the render loop and account for that.
pub fn waitTime(self: *Self, end_micros: ?u32, maxFPS: ?f32) u32 {
    // end_micros is the naive value we want to be between last begin and next begin

    // minimum time to wait to hit max fps target
    var min_micros: u32 = 0;
    if (maxFPS) |mfps| {
        min_micros = @as(u32, @intFromFloat(1_000_000.0 / mfps));
    }

    //std.debug.print("  end {d:6} min {d:6}", .{end_micros, min_micros});

    // wait_micros is amount on top of min_micros we will conditionally wait
    var wait_micros = (end_micros orelse 0) -| min_micros;

    // assume that we won't target a specific time to sleep but if we do
    // calculate the targets before removing so_far and slop
    self.loop_wait_target = null;
    self.loop_wait_target_event = false;
    const target_min = min_micros;
    const target = min_micros + wait_micros;

    // how long it's taken from begin to here
    const so_far_nanos = @max(self.frame_time_ns, self.backend.nanoTime()) - self.frame_time_ns;
    var so_far_micros = @as(u32, @intCast(@divFloor(so_far_nanos, 1000)));
    //std.debug.print("  far {d:6}", .{so_far_micros});

    // take time from min_micros first
    const min_so_far = @min(so_far_micros, min_micros);
    so_far_micros -= min_so_far;
    min_micros -= min_so_far;

    // then take time from wait_micros
    const min_so_far2 = @min(so_far_micros, wait_micros);
    so_far_micros -= min_so_far2;
    wait_micros -= min_so_far2;

    var slop = self.loop_target_slop;

    // get slop we can take out of min_micros
    const min_us_slop = @min(slop, @as(i32, @intCast(min_micros)));
    slop -= min_us_slop;
    if (min_us_slop >= 0) {
        min_micros -= @as(u32, @intCast(min_us_slop));
    } else {
        min_micros += @as(u32, @intCast(-min_us_slop));
    }

    // remaining slop we can take out of wait_micros
    const wait_us_slop = @min(slop, @as(i32, @intCast(wait_micros)));
    slop -= wait_us_slop;
    if (wait_us_slop >= 0) {
        wait_micros -= @as(u32, @intCast(wait_us_slop));
    } else {
        wait_micros += @as(u32, @intCast(-wait_us_slop));
    }

    //std.debug.print("  min {d:6}", .{min_micros});
    if (min_micros > 0) {
        // wait unconditionally for fps target
        self.backend.sleep(min_micros * 1000);
        self.loop_wait_target = self.frame_time_ns + (@as(i128, @intCast(target_min)) * 1000);
    }

    if (end_micros == null) {
        // no target, wait indefinitely for next event
        self.loop_wait_target = null;
        //std.debug.print("  wait indef\n", .{});
        return std.math.maxInt(u32);
    } else if (wait_micros > 0) {
        // wait conditionally
        // since we have a timeout we will try to hit that target but set our
        // flag so that we don't adjust for the target if we wake up to an event
        self.loop_wait_target = self.frame_time_ns + (@as(i128, @intCast(target)) * 1000);
        self.loop_wait_target_event = true;
        //std.debug.print("  wait {d:6}\n", .{wait_micros});
        return wait_micros;
    } else {
        // trying to hit the target but ran out of time
        //std.debug.print("  wait none\n", .{});
        return 0;
        // if we had a wait target from min_micros leave it
    }
}

/// Make this window the current window.
///
/// All widgets for this window should be declared between this call and `Window.end`.
pub fn begin(
    self: *Self,
    time_ns: i128,
) !void {
    const larena = self._arena.allocator();

    var micros_since_last: u32 = 1;
    if (time_ns > self.frame_time_ns) {
        // enforce monotinicity
        var nanos_since_last = time_ns - self.frame_time_ns;

        // make sure the @intCast below doesn't panic
        const max_nanos_since_last: i128 = std.math.maxInt(u32) * std.time.ns_per_us;
        nanos_since_last = @min(nanos_since_last, max_nanos_since_last);

        micros_since_last = @as(u32, @intCast(@divFloor(nanos_since_last, std.time.ns_per_us)));
        micros_since_last = @max(1, micros_since_last);
        self.frame_time_ns = time_ns;
    }

    //std.debug.print(" frame_time_ns {d}\n", .{self.frame_time_ns});

    self.previous_window = dvui.current_window;
    dvui.current_window = self;

    if (self.previous_window) |pw| {
        if (pw == self) {
            log.err("Window.begin() window is already the current_window - ensure Window.end() is called for each Window.begin()\n", .{});
        }
    }

    self.end_rendering_done = false;
    self.cursor_requested = null;
    self.text_input_rect = null;
    self.last_focused_id_this_frame = 0;
    self.debug_info_name_rect = "";
    self.debug_info_src_id_extra = "";
    if (self.debug_under_mouse) {
        if (self.debug_under_mouse_info.len > 0) {
            self.gpa.free(self.debug_under_mouse_info);
        }
        self.debug_under_mouse_info = "";
    }

    self.datas_trash = std.ArrayList(SavedData).init(larena);
    self.texture_trash = std.ArrayList(dvui.Texture).init(larena);

    {
        var i: usize = 0;
        while (i < self.subwindows.items.len) {
            var sw = &self.subwindows.items[i];
            if (sw.used) {
                sw.used = false;
                i += 1;
            } else {
                _ = self.subwindows.orderedRemove(i);
            }
        }
    }

    for (self.frame_times, 0..) |_, i| {
        if (i == (self.frame_times.len - 1)) {
            self.frame_times[i] = 0;
        } else {
            self.frame_times[i] = self.frame_times[i + 1] +| micros_since_last;
        }
    }

    {
        var deadSizes = std.ArrayList(u32).init(larena);
        defer deadSizes.deinit();
        var it = self.min_sizes.iterator();
        while (it.next()) |kv| {
            if (kv.value_ptr.used) {
                kv.value_ptr.used = false;
            } else {
                try deadSizes.append(kv.key_ptr.*);
            }
        }

        for (deadSizes.items) |id| {
            _ = self.min_sizes.remove(id);
        }

        //std.debug.print("min_sizes {d}\n", .{self.min_sizes.count()});
    }

    {
        var deadTags = std.ArrayList([]const u8).init(larena);
        defer deadTags.deinit();
        var it = self.tags.iterator();
        while (it.next()) |kv| {
            if (kv.value_ptr.used) {
                kv.value_ptr.used = false;
            } else {
                try deadTags.append(kv.key_ptr.*);
            }
        }

        for (deadTags.items) |name| {
            _ = self.tags.remove(name);
        }

        //std.debug.print("tags {d}\n", .{self.tags.count()});
    }

    {
        self.data_mutex.lock();
        defer self.data_mutex.unlock();

        var deadDatas = std.ArrayList(u32).init(larena);
        defer deadDatas.deinit();
        var it = self.datas.iterator();
        while (it.next()) |kv| {
            if (kv.value_ptr.used) {
                kv.value_ptr.used = false;
            } else {
                try deadDatas.append(kv.key_ptr.*);
            }
        }

        for (deadDatas.items) |id| {
            var dd = self.datas.fetchRemove(id).?;
            dd.value.free(self.gpa);
        }

        //std.debug.print("datas {d}\n", .{self.datas.count()});
    }

    self.tab_index_prev.deinit();
    self.tab_index_prev = self.tab_index;
    self.tab_index = @TypeOf(self.tab_index).init(self.tab_index.allocator);

    self.rect_pixels = .fromSize(self.backend.pixelSize());
    dvui.clipSet(self.rect_pixels);

    self.wd.rect = Rect.Natural.fromSize(self.backend.windowSize()).scale(1.0 / self.content_scale, Rect);
    self.natural_scale = if (self.wd.rect.w == 0) 1.0 else self.rect_pixels.w / self.wd.rect.w;

    //dvui.log.debug("window size {d} x {d} renderer size {d} x {d} scale {d}", .{ self.wd.rect.w, self.wd.rect.h, self.rect_pixels.w, self.rect_pixels.h, self.natural_scale });

    try dvui.subwindowAdd(self.wd.id, self.wd.rect, self.rect_pixels, false, null);

    _ = dvui.subwindowCurrentSet(self.wd.id, .cast(self.wd.rect));

    self.extra_frames_needed -|= 1;
    self.secs_since_last_frame = @as(f32, @floatFromInt(micros_since_last)) / 1_000_000;

    {
        const micros: i32 = if (micros_since_last > math.maxInt(i32)) math.maxInt(i32) else @as(i32, @intCast(micros_since_last));
        var deadAnimations = std.ArrayList(u32).init(larena);
        defer deadAnimations.deinit();
        var it = self.animations.iterator();
        while (it.next()) |kv| {
            if (!kv.value_ptr.used or kv.value_ptr.end_time <= 0) {
                try deadAnimations.append(kv.key_ptr.*);
            } else {
                kv.value_ptr.used = false;
                kv.value_ptr.start_time -|= micros;
                kv.value_ptr.end_time -|= micros;
                if (kv.value_ptr.start_time <= 0 and kv.value_ptr.end_time > 0) {
                    dvui.refresh(null, @src(), null);
                }
            }
        }

        for (deadAnimations.items) |id| {
            _ = self.animations.remove(id);
        }
    }

    {
        var deadFonts = std.ArrayList(u32).init(larena);
        defer deadFonts.deinit();
        var it = self.font_cache.iterator();
        while (it.next()) |kv| {
            if (kv.value_ptr.used) {
                kv.value_ptr.used = false;
            } else {
                try deadFonts.append(kv.key_ptr.*);
            }
        }

        for (deadFonts.items) |id| {
            var tce = self.font_cache.fetchRemove(id).?;
            tce.value.glyph_info.deinit();
            tce.value.deinit(self);
        }

        //std.debug.print("font_cache {d}\n", .{self.font_cache.count()});
    }

    {
        var deadIcons = std.ArrayList(u32).init(larena);
        defer deadIcons.deinit();
        var it = self.texture_cache.iterator();
        while (it.next()) |kv| {
            if (kv.value_ptr.used) {
                kv.value_ptr.used = false;
            } else {
                try deadIcons.append(kv.key_ptr.*);
            }
        }

        for (deadIcons.items) |id| {
            const ice = self.texture_cache.fetchRemove(id).?;
            self.backend.textureDestroy(ice.value.texture);
        }

        //std.debug.print("texture_cache {d}\n", .{self.texture_cache.count()});
    }

    if (!self.captured_last_frame) {
        // widget that had capture went away
        self.capture = null;
    }
    self.captured_last_frame = false;

    self.wd.parent = self.widget();

    // Window's wd is kept frame to frame, so manually reset the cache.
    self.wd.rect_scale_cache = null;
    try self.wd.register();

    self.next_widget_ypos = self.wd.rect.y;

    self.backend.begin(larena);
}

fn positionMouseEventAdd(self: *Self) !void {
    try self.events.append(self.arena(), .{ .evt = .{ .mouse = .{
        .action = .position,
        .button = .none,
        .p = self.mouse_pt,
        .floating_win = self.windowFor(self.mouse_pt),
    } } });
}

fn positionMouseEventRemove(self: *Self) void {
    if (self.events.pop()) |e| {
        if (e.evt != .mouse or e.evt.mouse.action != .position) {
            log.err("positionMouseEventRemove removed a non-mouse or non-position event\n", .{});
        }
    }
}

pub fn windowFor(self: *const Self, p: Point.Physical) u32 {
    var i = self.subwindows.items.len;
    while (i > 0) : (i -= 1) {
        const sw = &self.subwindows.items[i - 1];
        if (sw.modal or sw.rect_pixels.contains(p)) {
            return sw.id;
        }
    }

    return self.wd.id;
}

pub fn subwindowCurrent(self: *const Self) *Subwindow {
    var i = self.subwindows.items.len;
    while (i > 0) : (i -= 1) {
        const sw = &self.subwindows.items[i - 1];
        if (sw.id == self.subwindow_currentId) {
            return sw;
        }
    }

    log.warn("subwindowCurrent failed to find the current subwindow, returning base window\n", .{});
    return &self.subwindows.items[0];
}

pub fn subwindowFocused(self: *const Self) *Subwindow {
    var i = self.subwindows.items.len;
    while (i > 0) : (i -= 1) {
        const sw = &self.subwindows.items[i - 1];
        if (sw.id == self.focused_subwindowId) {
            return sw;
        }
    }

    log.warn("subwindowFocused failed to find the focused subwindow, returning base window\n", .{});
    return &self.subwindows.items[0];
}

/// Return the cursor the gui wants.  Client code should cache this if
/// switching the platform's cursor is expensive.
pub fn cursorRequested(self: *const Self) dvui.enums.Cursor {
    if (self.drag_state == .dragging and self.cursor_dragging != null) {
        return self.cursor_dragging.?;
    } else {
        return self.cursor_requested orelse .arrow;
    }
}

/// Return the cursor the gui wants or null if mouse is not in gui windows.
/// Client code should cache this if switching the platform's cursor is
/// expensive.
pub fn cursorRequestedFloating(self: *const Self) ?dvui.enums.Cursor {
    if (self.capture != null or self.windowFor(self.mouse_pt) != self.wd.id) {
        // gui owns the cursor if we have mouse capture or if the mouse is above
        // a floating window
        return self.cursorRequested();
    } else {
        // no capture, not above a floating window, so client owns the cursor
        return null;
    }
}

/// If a widget called wantTextInput this frame, return the rect of where the
/// text input is happening.
///
/// Apps and backends should use this to show an on screen keyboard and/or
/// position an IME window.
pub fn textInputRequested(self: *const Self) ?Rect.Natural {
    return self.text_input_rect;
}

pub fn renderCommands(self: *Self, queue: std.ArrayList(dvui.RenderCommand)) !void {
    const oldsnap = dvui.snapToPixels();
    defer _ = dvui.snapToPixelsSet(oldsnap);

    const oldclip = dvui.clipGet();
    defer dvui.clipSet(oldclip);

    const old_rendering = dvui.renderingSet(true);
    defer _ = dvui.renderingSet(old_rendering);

    for (queue.items) |*drc| {
        _ = dvui.snapToPixelsSet(drc.snap);
        dvui.clipSet(drc.clip);
        switch (drc.cmd) {
            .text => |t| {
                try dvui.renderText(t);
            },
            .debug_font_atlases => |t| {
                try dvui.debugRenderFontAtlases(t.rs, t.color);
            },
            .texture => |t| {
                try dvui.renderTexture(t.tex, t.rs, t.opts);
            },
            .pathFillConvex => |pf| {
                try dvui.pathFillConvex(pf.path, pf.color);
                self.arena().free(pf.path);
            },
            .pathStroke => |ps| {
                try dvui.pathStrokeRaw(ps.path, ps.thickness, ps.color, ps.closed, ps.endcap_style);
                self.arena().free(ps.path);
            },
            .triangles => |t| {
                try dvui.renderTriangles(t.tri, t.tex);
                // FIXME: free the triangles?
            },
        }
    }
}

/// data is copied into internal storage
pub fn dataSetAdvanced(self: *Self, id: u32, key: []const u8, data_in: anytype, comptime copy_slice: bool, num_copies: usize) void {
    const hash = dvui.hashIdKey(id, key);

    const dt = @typeInfo(@TypeOf(data_in));
    const dt_type_str = @typeName(@TypeOf(data_in));
    var bytes: []const u8 = undefined;
    if (copy_slice) {
        bytes = std.mem.sliceAsBytes(data_in);
        if (dt.pointer.sentinel() != null) {
            bytes.len += @sizeOf(dt.pointer.child);
        }
    } else {
        bytes = std.mem.asBytes(&data_in);
    }

    const alignment = comptime blk: {
        if (copy_slice) {
            break :blk dt.pointer.alignment;
        } else {
            break :blk @alignOf(@TypeOf(data_in));
        }
    };

    self.data_mutex.lock();
    defer self.data_mutex.unlock();

    var sd = SavedData{ .alignment = alignment, .data = self.gpa.allocWithOptions(u8, bytes.len * num_copies, alignment, null) catch |err| switch (err) {
        error.OutOfMemory => {
            log.err("dataSet got {!} for id {x} key {s}\n", .{ err, id, key });
            return;
        },
    } };

    for (0..num_copies) |i| {
        @memcpy(sd.data[i * bytes.len ..][0..bytes.len], bytes);
    }

    if (builtin.mode == .Debug) {
        sd.type_str = dt_type_str;
        sd.copy_slice = copy_slice;
    }

    const previous_kv = self.datas.fetchPut(hash, sd) catch |err| switch (err) {
        error.OutOfMemory => {
            log.err("dataSet got {!} for id {x} key {s}\n", .{ err, id, key });
            sd.free(self.gpa);
            return;
        },
    };

    if (previous_kv) |kv| {
        //std.debug.print("dataSet: already had data for id {x} key {s}, freeing previous data\n", .{ id, kv.key });
        self.datas_trash.append(kv.value) catch |err| {
            log.err("Previous data could not be added to the trash, got {!} for id {x} key {s}\n", .{ err, id, key });
            return;
        };
    }
}

/// returns the backing byte slice if we have one
pub fn dataGetInternal(self: *Self, id: u32, key: []const u8, comptime T: type, slice: bool) ?[]u8 {
    const hash = dvui.hashIdKey(id, key);

    self.data_mutex.lock();
    defer self.data_mutex.unlock();

    if (self.datas.getPtr(hash)) |sd| {
        if (builtin.mode == .Debug) {
            if (!std.mem.eql(u8, sd.type_str, @typeName(T)) or sd.copy_slice != slice) {
                std.debug.panic("dataGetInternal: stored type {s} (slice {}) doesn't match asked for type {s} (slice {})", .{ sd.type_str, sd.copy_slice, @typeName(T), slice });
            }
        }

        sd.used = true;
        return sd.data;
    } else {
        return null;
    }
}

pub fn dataRemove(self: *Self, id: u32, key: []const u8) void {
    const hash = dvui.hashIdKey(id, key);

    self.data_mutex.lock();
    defer self.data_mutex.unlock();

    if (self.datas.fetchRemove(hash)) |dd| {
        self.datas_trash.append(dd.value) catch |err| {
            log.err("Previous data could not be added to the trash, got {!} for id {x} key {s}\n", .{ err, id, key });
            return;
        };
    }
}

///  Add a dialog to be displayed on the GUI thread during `Window.end`.
///
///  See `dvui.dialogAdd` for higher level api.
///
///  Can be called from any thread. Returns a locked mutex that must be unlocked
///  by the caller.
///
///  If calling from a non-GUI thread, do any dataSet() calls before unlocking the
///  mutex to ensure that data is available before the dialog is displayed.
pub fn dialogAdd(self: *Self, id: u32, display: dvui.DialogDisplayFn) !*std.Thread.Mutex {
    self.dialog_mutex.lock();

    for (self.dialogs.items) |*d| {
        if (d.id == id) {
            d.display = display;
            break;
        }
    } else {
        try self.dialogs.append(Dialog{ .id = id, .display = display });
    }

    return &self.dialog_mutex;
}

/// Only called from gui thread.
pub fn dialogRemove(self: *Self, id: u32) void {
    self.dialog_mutex.lock();
    defer self.dialog_mutex.unlock();

    for (self.dialogs.items, 0..) |*d, i| {
        if (d.id == id) {
            _ = self.dialogs.orderedRemove(i);
            return;
        }
    }
}

fn dialogsShow(self: *Self) !void {
    var i: usize = 0;
    var dia: ?Dialog = null;
    while (true) {
        self.dialog_mutex.lock();
        if (i < self.dialogs.items.len and
            dia != null and
            dia.?.id == self.dialogs.items[i].id)
        {
            // we just did this one, move to the next
            i += 1;
        }

        if (i < self.dialogs.items.len) {
            dia = self.dialogs.items[i];
        } else {
            dia = null;
        }
        self.dialog_mutex.unlock();

        if (dia) |d| {
            try d.display(d.id);
        } else {
            break;
        }
    }
}

pub fn timer(self: *Self, id: u32, micros: i32) !void {
    // when start_time is in the future, we won't spam frames, so this will
    // cause a single frame and then expire
    const a = Animation{ .start_time = micros, .end_time = micros };
    const h = dvui.hashIdKey(id, "_timer");
    try self.animations.put(h, a);
}

pub fn timerRemove(self: *Self, id: u32) void {
    const h = dvui.hashIdKey(id, "_timer");
    _ = self.animations.remove(h);
}

/// Add a toast to be displayed on the GUI thread. Can be called from any
/// thread. Returns a locked mutex that must be unlocked by the caller.  If
/// calling from a non-GUI thread, do any `dvui.dataSet` calls before unlocking
/// the mutex to ensure that data is available before the dialog is
/// displayed.
pub fn toastAdd(self: *Self, id: u32, subwindow_id: ?u32, display: dvui.DialogDisplayFn, timeout: ?i32) !*std.Thread.Mutex {
    self.dialog_mutex.lock();

    for (self.toasts.items) |*t| {
        if (t.id == id) {
            t.display = display;
            t.subwindow_id = subwindow_id;
            break;
        }
    } else {
        try self.toasts.append(Toast{ .id = id, .subwindow_id = subwindow_id, .display = display });
    }

    if (timeout) |tt| {
        try self.timer(id, tt);
    } else {
        self.timerRemove(id);
    }

    return &self.dialog_mutex;
}

pub fn toastRemove(self: *Self, id: u32) void {
    self.dialog_mutex.lock();
    defer self.dialog_mutex.unlock();

    for (self.toasts.items, 0..) |*t, i| {
        if (t.id == id) {
            _ = self.toasts.orderedRemove(i);
            return;
        }
    }
}

/// show any toasts that didn't have a subwindow_id set
fn toastsShow(self: *Self) !void {
    var ti = dvui.toastsFor(null);
    if (ti) |*it| {
        var toast_win = dvui.FloatingWindowWidget.init(@src(), .{ .stay_above_parent_window = true, .process_events_in_deinit = false }, .{ .background = false, .border = .{} });
        defer toast_win.deinit();

        toast_win.data().rect = dvui.placeIn(self.wd.rect, toast_win.data().rect.size(), .none, .{ .x = 0.5, .y = 0.7 });
        toast_win.autoSize();
        try toast_win.install();
        try toast_win.drawBackground();

        var vbox = try dvui.box(@src(), .vertical, .{});
        defer vbox.deinit();

        while (it.next()) |t| {
            try t.display(t.id);
        }
    }
}

fn debugWindowShow(self: *Self) !void {
    if (self.debug_under_mouse_quitting) {
        self.debug_under_mouse = false;
        self.debug_under_mouse_esc_needed = false;
        self.debug_under_mouse_quitting = false;
    }

    // disable so the widgets we are about to use to display this data
    // don't modify the data, otherwise our iterator will get corrupted and
    // even if you search for a widget here, the data won't be available
    var dum = self.debug_under_mouse;
    self.debug_under_mouse = false;
    defer self.debug_under_mouse = dum;

    var duf = self.debug_under_focus;
    self.debug_under_focus = false;
    defer self.debug_under_focus = duf;

    var float = try dvui.floatingWindow(@src(), .{ .open_flag = &self.debug_window_show }, .{ .min_size_content = .{ .w = 300, .h = 600 } });
    defer float.deinit();

    try dvui.windowHeader("DVUI Debug", "", &self.debug_window_show);

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.labelNoFmt(@src(), "Hex id of widget to highlight:", .{ .gravity_y = 0.5 });

        var buf = [_]u8{0} ** 20;
        if (self.debug_widget_id != 0) {
            _ = try std.fmt.bufPrint(&buf, "{x}", .{self.debug_widget_id});
        }
        var te = try dvui.textEntry(@src(), .{
            .text = .{ .buffer = &buf },
        }, .{});
        te.deinit();

        self.debug_widget_id = std.fmt.parseInt(u32, std.mem.sliceTo(&buf, 0), 16) catch 0;
    }

    var tl = dvui.TextLayoutWidget.init(@src(), .{}, .{ .expand = .horizontal, .min_size_content = .{ .h = 80 } });
    try tl.install(.{});

    self.debug_widget_panic = false;

    var color: ?dvui.Options.ColorOrName = null;
    if (self.debug_widget_id == 0) {
        // blend text and control colors
        color = .{ .color = dvui.Color.average(dvui.themeGet().color_text, dvui.themeGet().color_fill_control) };
    }
    if (try dvui.button(@src(), "Panic", .{}, .{ .gravity_x = 1.0, .margin = dvui.Rect.all(8), .color_text = color })) {
        if (self.debug_widget_id != 0) {
            self.debug_widget_panic = true;
        } else {
            try dvui.dialog(@src(), .{}, .{ .title = "Disabled", .message = "Need valid widget Id to panic" });
        }
    }

    if (try tl.touchEditing()) |floating_widget| {
        defer floating_widget.deinit();
        try tl.touchEditingMenu();
    }
    tl.processEvents();

    try tl.addText(self.debug_info_name_rect, .{});
    try tl.addText("\n\n", .{});
    try tl.addText(self.debug_info_src_id_extra, .{});
    tl.deinit();

    if (try dvui.button(@src(), if (dum) "Stop (Or Left Click)" else "Debug Under Mouse (until click)", .{}, .{})) {
        dum = !dum;
    }

    if (try dvui.button(@src(), if (dum) "Stop (Or Press Esc)" else "Debug Under Mouse (until esc)", .{}, .{})) {
        dum = !dum;
        self.debug_under_mouse_esc_needed = dum;
    }

    if (try dvui.button(@src(), if (duf) "Stop Debugging Focus" else "Debug Focus", .{}, .{})) {
        duf = !duf;
    }

    const logit = self.debugRefresh(null);
    if (try dvui.button(@src(), if (logit) "Stop Refresh Logging" else "Start Refresh Logging", .{}, .{})) {
        _ = self.debugRefresh(!logit);
    }

    var scroll = try dvui.scrollArea(@src(), .{}, .{ .expand = .both, .background = false });
    defer scroll.deinit();

    var iter = std.mem.splitScalar(u8, self.debug_under_mouse_info, '\n');
    var i: usize = 0;
    while (iter.next()) |line| : (i += 1) {
        if (line.len > 0) {
            var hbox = try dvui.box(@src(), .horizontal, .{ .id_extra = i });
            defer hbox.deinit();

            if (try dvui.buttonIcon(@src(), "find", dvui.entypo.magnifying_glass, .{}, .{})) {
                self.debug_widget_id = std.fmt.parseInt(u32, std.mem.sliceTo(line, ' '), 16) catch 0;
            }

            try dvui.labelNoFmt(@src(), line, .{ .gravity_y = 0.5 });
        }
    }
}

pub const endOptions = struct {
    show_toasts: bool = true,
};

/// Normally this is called for you in `end`, but you can call it separately in
/// case you want to do something after everything has been rendered.
pub fn endRendering(self: *Self, opts: endOptions) !void {
    if (opts.show_toasts) {
        try self.toastsShow();
    }
    try self.dialogsShow();

    if (self.debug_window_show) {
        try self.debugWindowShow();
    }

    for (self.subwindows.items) |*sw| {
        try self.renderCommands(sw.render_cmds);
        sw.render_cmds.clearAndFree();

        try self.renderCommands(sw.render_cmds_after);
        sw.render_cmds_after.clearAndFree();
    }

    self.end_rendering_done = true;
}

/// End of this window gui's rendering.  Renders retained dialogs and all
/// deferred rendering (subwindows, focus highlights).  Returns micros we
/// want between last call to `begin` and next call to `begin` (or null
/// meaning wait for event).  If wanted, pass return value to `waitTime` to
/// get a useful time to wait between render loops.
pub fn end(self: *Self, opts: endOptions) !?u32 {
    if (!self.end_rendering_done) {
        try self.endRendering(opts);
    }

    // Call this before freeing data so backend can use data allocated during frame.
    self.backend.end();

    for (self.datas_trash.items) |sd| {
        sd.free(self.gpa);
    }
    self.datas_trash.clearAndFree();

    for (self.texture_trash.items) |tex| {
        self.backend.textureDestroy(tex);
    }
    self.texture_trash.clearAndFree();

    // events may have been tagged with a focus widget that never showed up, so
    // we wouldn't even get them bubbled
    const evts = dvui.events();
    for (evts) |*e| {
        if (self.drag_state == .dragging and e.evt == .mouse and e.evt.mouse.action == .release) {
            log.debug("clearing drag ({s}) for unhandled mouse release", .{self.drag_name});
            self.drag_state = .none;
            self.drag_name = "";
        }

        if (!dvui.eventMatch(e, .{ .id = self.wd.id, .r = self.rect_pixels, .cleanup = true }))
            continue;

        if (e.evt == .mouse) {
            if (e.evt.mouse.action == .focus) {
                // unhandled click, clear focus
                dvui.focusWidget(null, null, null);
            }
        } else if (e.evt == .key) {
            if (e.evt.key.action == .down and e.evt.key.matchBind("next_widget")) {
                e.handled = true;
                dvui.tabIndexNext(e.num);
            }

            if (e.evt.key.action == .down and e.evt.key.matchBind("prev_widget")) {
                e.handled = true;
                dvui.tabIndexPrev(e.num);
            }
        }
    }

    self.mouse_pt_prev = self.mouse_pt;

    if (!self.subwindowFocused().used) {
        // our focused subwindow didn't show this frame, focus the highest one that did
        var i = self.subwindows.items.len;
        while (i > 0) : (i -= 1) {
            const sw = self.subwindows.items[i - 1];
            if (sw.used) {
                //std.debug.print("focused subwindow lost, focusing {d}\n", .{i - 1});
                dvui.focusSubwindow(sw.id, null);
                break;
            }
        }

        dvui.refresh(null, @src(), null);
    }

    // Check that the final event was our synthetic mouse position event.
    // If one of the addEvent* functions forgot to add the synthetic mouse
    // event to the end this will print a debug message.
    self.positionMouseEventRemove();

    _ = self._arena.reset(.retain_capacity);

    try self.initEvents();

    if (self.inject_motion_event) {
        self.inject_motion_event = false;
        const pt = self.rectScale().pointFromScreen(self.mouse_pt);
        _ = try self.addEventMouseMotion(.cast(pt));
    }

    defer dvui.current_window = self.previous_window;

    // This is what refresh affects
    if (self.extra_frames_needed > 0) {
        return 0;
    }

    // If there are current animations, return 0 so we go as fast as we can.
    // If all animations are scheduled in the future, pick the soonest start.
    var ret: ?u32 = null;
    var it = self.animations.iterator();
    while (it.next()) |kv| {
        if (kv.value_ptr.used) {
            if (kv.value_ptr.start_time > 0) {
                const st = @as(u32, @intCast(kv.value_ptr.start_time));
                ret = @min(ret orelse st, st);
            } else if (kv.value_ptr.end_time > 0) {
                ret = 0;
                break;
            }
        }
    }

    return ret;
}

fn initEvents(self: *Self) !void {
    self.events = .{};
    self.event_num = 0;

    // We want a position mouse event to do mouse cursors.  It needs to be
    // final so if there was a drag end the cursor will still be set
    // correctly.  We don't know when the client gives us the last event,
    // so make our position event now, and addEvent* functions will remove
    // and re-add to keep it as the final event.
    try self.positionMouseEventAdd();
}

pub fn widget(self: *Self) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *Self) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *Self, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    var r = self.wd.rect;
    r.y = self.next_widget_ypos;
    r.h -= r.y;
    const ret = dvui.placeIn(r, min_size, e, g);
    self.next_widget_ypos += ret.h;
    return ret;
}

pub fn rectScale(self: *Self) RectScale {
    return .{ .r = self.rect_pixels, .s = self.natural_scale };
}

pub fn screenRectScale(self: *Self, r: Rect) RectScale {
    return self.rectScale().rectToRectScale(r);
}

pub fn minSizeForChild(self: *Self, s: Size) void {
    // os window doesn't size itself based on children
    _ = self;
    _ = s;
}

pub fn processEvent(self: *Self, e: *Event, bubbling: bool) void {
    // window does cleanup events, but not normal events
    switch (e.evt) {
        .close_popup => |cp| {
            e.handled = true;
            if (cp.intentional) {
                // when a popup is closed due to a menu item being chosen,
                // the window that spawned it (which had focus previously)
                // should become focused again
                dvui.focusSubwindow(self.wd.id, null);
            }
        },
        else => {},
    }

    // can't bubble past the base window
    _ = bubbling;
}

const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Point = dvui.Point;
const Event = dvui.Event;
const WidgetData = dvui.WidgetData;
const Widget = dvui.Widget;

const Animation = dvui.Animation;
const Theme = dvui.Theme;
const Dialog = dvui.Dialog;
const Toast = dvui.Toast;

const c = dvui.c;

const std = @import("std");
const math = std.math;
const builtin = @import("builtin");
const dvui = @import("dvui.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
