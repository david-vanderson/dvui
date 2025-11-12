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

subwindows: dvui.Subwindows = .{},

last_focused_id_this_frame: Id = .zero,
last_focused_id_in_subwindow: Id = .zero,
last_registered_id_this_frame: Id = .zero,
scroll_to_focused: bool = false,

/// natural rect telling the backend where our text input box is:
/// * when non-null, we want an on screen keyboard if needed (phones)
/// * when showing the IME input window, position it near this
text_input_rect: ?Rect.Natural = null,

snap_to_pixels: bool = true,
kerning: bool = true,
/// The alpha value for all rendering. All colors alpha values will be
/// multiplied by this value.
alpha: f32 = 1.0,

/// Uses `arena` allocator
events: std.ArrayListUnmanaged(Event) = .{},
event_num: u16 = 0,
/// mouse_pt tracks the last position we got a mouse event for
/// 1) used to add position info to mouse wheel events
/// 2) used to highlight the widget under the mouse (`dvui.Event.Mouse.Action` .position event)
/// 3) used to change the cursor (`dvui.Event.Mouse.Action` .position event)
// Start off screen so nothing is highlighted on the first frame
mouse_pt: Point.Physical = .{ .x = -1, .y = -1 },
mouse_pt_prev: Point.Physical = .{ .x = -1, .y = -1 },
/// Holds the current state of the modifiers from the most
/// recently added key event. Used for adding modifiers to
/// mouse events
modifiers: dvui.enums.Mod = .none,
inject_motion_event: bool = false,

dragging: dvui.Dragging = .{},

frame_time_ns: i128 = 0,
loop_wait_target: ?i128 = null,
loop_wait_target_can_interrupt: bool = false,
loop_target_slop: i32 = 1000, // 1ms frame overhead seems a good place to start
loop_target_slop_frames: i32 = 0,
frame_times: [10]u32 = @splat(0),

/// Debugging aid, only used in waitTime(), null means no max
max_fps: ?f32 = null,

secs_since_last_frame: f32 = 0,
extra_frames_needed: u8 = 0,
clipRect: dvui.Rect.Physical = .{},

/// The currently active theme where colors and fonts will be sourced.
/// This field is intended to be assigned to directly.
///
/// See `dvui.themeSet`
theme: Theme,

/// Used by `dvui.dialog` for button order of Ok and Cancel.
button_order: dvui.enums.DialogButtonOrder = .cancel_ok,

/// Uses `gpa` allocator
min_sizes: dvui.TrackingAutoHashMap(Id, Size, .put_only) = .empty,
/// Uses `gpa` allocator
tags: dvui.TrackingAutoHashMap([]const u8, dvui.TagData, .put_only) = .empty,
/// Uses `gpa` allocator
data_store: dvui.Data = .{},
/// Uses `gpa` allocator
animations: dvui.TrackingAutoHashMap(Id, Animation, .get_and_put) = .empty,
/// Uses `gpa` allocator
tab_index_prev: std.ArrayListUnmanaged(dvui.TabIndex) = .empty,
/// Uses `gpa` allocator
tab_index: std.ArrayListUnmanaged(dvui.TabIndex) = .empty,
/// Uses `gpa` allocator
fonts: dvui.Font.Cache = .{},
/// Uses `gpa` allocator
texture_cache: dvui.Texture.Cache = .{},
/// Uses `gpa` allocator
dialogs: dvui.Dialogs = .{},
/// Uses `gpa` allocator
///
/// A toast is a dialog that will be displayed is a special
/// positioned floating window at the end of the frame
toasts: dvui.Dialogs = .{},
/// Uses `gpa` allocator
keybinds: std.StringHashMapUnmanaged(dvui.enums.Keybind) = .empty,

cursor_requested: ?dvui.enums.Cursor = null,

wd: WidgetData,
current_parent: Widget,
rect_pixels: dvui.Rect.Physical = .{},
natural_scale: f32 = 1.0,
/// can set separately but gets folded into natural_scale
content_scale: f32 = 1.0,
layout: dvui.BasicLayout = .{},

capture: ?dvui.CaptureMouse = null,
captured_last_frame: bool = false,

gpa: std.mem.Allocator,
_arena: std.heap.ArenaAllocator,
_lifo_arena: std.heap.ArenaAllocator,
/// Used to allocate widgets with a fixed location
_widget_stack: std.heap.ArenaAllocator,
render_target: dvui.RenderTarget = .{ .texture = null, .offset = .{} },
end_rendering_done: bool = false,

debug: @import("Debug.zig") = .{},

accesskit: dvui.AccessKit,

pub const InitOptions = struct {
    id_extra: usize = 0,
    arena: ?std.heap.ArenaAllocator = null,
    theme: ?Theme = null,
    /// `null` indicated that the OS will choose it's preferred theme
    ///
    /// Does nothing if the `theme` option is populated
    color_scheme: ?dvui.enums.ColorScheme = null,
    keybinds: ?enum {
        none,
        windows,
        mac,
    } = null,

    button_order: ?dvui.enums.DialogButtonOrder = null,
};

pub fn init(
    src: std.builtin.SourceLocation,
    gpa: std.mem.Allocator,
    backend_ctx: dvui.Backend,
    init_opts: InitOptions,
) !Self {
    const hashval = dvui.Id.extendId(null, src, init_opts.id_extra);

    var self = Self{
        .gpa = gpa,
        ._arena = if (init_opts.arena) |a| a else .init(gpa),
        ._lifo_arena = .init(gpa),
        ._widget_stack = .init(gpa),
        .wd = WidgetData{
            .src = src,
            .id = hashval,
            .init_options = .{ .subwindow = true },
            .options = .{ .name = "Window", .role = .window },
            // Unused
            .min_size = .{},
            // Set in `begin`
            .rect = undefined,
            // Set in `begin`
            .parent = undefined,
        },
        // Set in `begin`
        .current_parent = undefined,
        .backend = backend_ctx,
        // TODO: Add some way to opt-out of including the builtin fonts in the built binary
        .fonts = try .initWithBuiltins(gpa),
        .theme = if (init_opts.theme) |t| t else switch (init_opts.color_scheme orelse backend_ctx.preferredColorScheme() orelse .light) {
            .light => Theme.builtin.adwaita_light,
            .dark => Theme.builtin.adwaita_dark,
        },
        .accesskit = .{},
    };

    try self.initEvents();

    self.button_order = init_opts.button_order orelse switch (builtin.os.tag) {
        .windows => .ok_cancel,
        else => .cancel_ok,
    };

    const kb = init_opts.keybinds orelse blk: {
        if (builtin.os.tag.isDarwin()) {
            break :blk .mac;
        } else {
            break :blk .windows;
        }
    };

    if (kb == .windows or kb == .mac) {
        try self.keybinds.putNoClobber(self.gpa, "activate", .{ .key = .enter, .also = "activate_1" });
        try self.keybinds.putNoClobber(self.gpa, "activate_1", .{ .key = .space });

        try self.keybinds.putNoClobber(self.gpa, "next_widget", .{ .key = .tab, .shift = false });
        try self.keybinds.putNoClobber(self.gpa, "prev_widget", .{ .key = .tab, .shift = true });
    }

    switch (kb) {
        .none => {},
        .windows => {
            // zig fmt: off
                try self.keybinds.putNoClobber(self.gpa, "cut",        .{ .key = .x, .control = true });
                try self.keybinds.putNoClobber(self.gpa, "copy",       .{ .key = .c, .control = true, .also = "copy_1" });
                try self.keybinds.putNoClobber(self.gpa, "copy_1",       .{ .key = .insert, .control = true, .shift = false, .alt = false, .command = false });
                try self.keybinds.putNoClobber(self.gpa, "paste",      .{ .key = .v, .control = true, .also = "paste_1" });
                try self.keybinds.putNoClobber(self.gpa, "paste_1",       .{ .key = .insert, .control = false, .shift = true, .alt = false, .command = false });
                try self.keybinds.putNoClobber(self.gpa, "select_all", .{ .key = .a, .control = true });

                // use with mod.matchBind
                try self.keybinds.putNoClobber(self.gpa, "ctrl/cmd",   .{ .control = true });

                try self.keybinds.putNoClobber(self.gpa, "text_start",        .{ .key = .home, .shift = false, .control = true });
                try self.keybinds.putNoClobber(self.gpa, "text_end",          .{ .key = .end,  .shift = false, .control = true });
                try self.keybinds.putNoClobber(self.gpa, "text_start_select", .{ .key = .home, .shift = true,  .control = true });
                try self.keybinds.putNoClobber(self.gpa, "text_end_select",   .{ .key = .end,  .shift = true,  .control = true });

                try self.keybinds.putNoClobber(self.gpa, "line_start",        .{ .key = .home, .shift = false, .control = false });
                try self.keybinds.putNoClobber(self.gpa, "line_end",          .{ .key = .end,  .shift = false, .control = false });
                try self.keybinds.putNoClobber(self.gpa, "line_start_select", .{ .key = .home, .shift = true,  .control = false });
                try self.keybinds.putNoClobber(self.gpa, "line_end_select",   .{ .key = .end,  .shift = true,  .control = false });

                try self.keybinds.putNoClobber(self.gpa, "word_left",         .{ .key = .left,  .shift = false, .control = true });
                try self.keybinds.putNoClobber(self.gpa, "word_right",        .{ .key = .right, .shift = false, .control = true });
                try self.keybinds.putNoClobber(self.gpa, "word_left_select",  .{ .key = .left,  .shift = true,  .control = true });
                try self.keybinds.putNoClobber(self.gpa, "word_right_select", .{ .key = .right, .shift = true,  .control = true });

                try self.keybinds.putNoClobber(self.gpa, "char_left",         .{ .key = .left,  .shift = false, .control = false });
                try self.keybinds.putNoClobber(self.gpa, "char_right",        .{ .key = .right, .shift = false, .control = false });
                try self.keybinds.putNoClobber(self.gpa, "char_left_select",  .{ .key = .left,  .shift = true,  .control = false });
                try self.keybinds.putNoClobber(self.gpa, "char_right_select", .{ .key = .right, .shift = true,  .control = false });

                try self.keybinds.putNoClobber(self.gpa, "char_up",          .{ .key = .up,   .shift = false });
                try self.keybinds.putNoClobber(self.gpa, "char_down",        .{ .key = .down, .shift = false });
                try self.keybinds.putNoClobber(self.gpa, "char_up_select",   .{ .key = .up,   .shift = true });
                try self.keybinds.putNoClobber(self.gpa, "char_down_select", .{ .key = .down, .shift = true });

                try self.keybinds.putNoClobber(self.gpa, "delete_prev_word", .{ .key = .backspace, .control = true });
                try self.keybinds.putNoClobber(self.gpa, "delete_next_word", .{ .key = .delete,    .control = true });
                // zig fmt: on
        },
        .mac => {
            // zig fmt: off
                try self.keybinds.putNoClobber(self.gpa, "cut",        .{ .key = .x, .command = true });
                try self.keybinds.putNoClobber(self.gpa, "copy",       .{ .key = .c, .command = true });
                try self.keybinds.putNoClobber(self.gpa, "paste",      .{ .key = .v, .command = true });
                try self.keybinds.putNoClobber(self.gpa, "select_all", .{ .key = .a, .command = true });

                // use with mod.matchBind
                try self.keybinds.putNoClobber(self.gpa, "ctrl/cmd",   .{ .command = true });

                try self.keybinds.putNoClobber(self.gpa, "text_start",        .{ .key = .up,   .shift = false, .command = true });
                try self.keybinds.putNoClobber(self.gpa, "text_end",          .{ .key = .down, .shift = false, .command = true });
                try self.keybinds.putNoClobber(self.gpa, "text_start_select", .{ .key = .up,   .shift = true,  .command = true });
                try self.keybinds.putNoClobber(self.gpa, "text_end_select",   .{ .key = .down, .shift = true,  .command = true });

                try self.keybinds.putNoClobber(self.gpa, "line_start",        .{ .key = .left,  .shift = false, .command = true });
                try self.keybinds.putNoClobber(self.gpa, "line_end",          .{ .key = .right, .shift = false, .command = true });
                try self.keybinds.putNoClobber(self.gpa, "line_start_select", .{ .key = .left,  .shift = true,  .command = true });
                try self.keybinds.putNoClobber(self.gpa, "line_end_select",   .{ .key = .right, .shift = true,  .command = true });

                try self.keybinds.putNoClobber(self.gpa, "word_left",         .{ .key = .left,  .shift = false, .alt = true });
                try self.keybinds.putNoClobber(self.gpa, "word_right",        .{ .key = .right, .shift = false, .alt = true });
                try self.keybinds.putNoClobber(self.gpa, "word_left_select",  .{ .key = .left,  .shift = true,  .alt = true });
                try self.keybinds.putNoClobber(self.gpa, "word_right_select", .{ .key = .right, .shift = true,  .alt = true });

                try self.keybinds.putNoClobber(self.gpa, "char_left",         .{ .key = .left,  .shift = false, .alt = false });
                try self.keybinds.putNoClobber(self.gpa, "char_right",        .{ .key = .right, .shift = false, .alt = false });
                try self.keybinds.putNoClobber(self.gpa, "char_left_select",  .{ .key = .left,  .shift = true,  .alt = false });
                try self.keybinds.putNoClobber(self.gpa, "char_right_select", .{ .key = .right, .shift = true,  .alt = false });

                try self.keybinds.putNoClobber(self.gpa, "char_up",          .{ .key = .up,   .shift = false, .command = false });
                try self.keybinds.putNoClobber(self.gpa, "char_down",        .{ .key = .down, .shift = false, .command = false });
                try self.keybinds.putNoClobber(self.gpa, "char_up_select",   .{ .key = .up,   .shift = true,  .command = false });
                try self.keybinds.putNoClobber(self.gpa, "char_down_select", .{ .key = .down, .shift = true,  .command = false });

                try self.keybinds.putNoClobber(self.gpa, "delete_prev_word", .{ .key = .backspace, .alt = true });
                try self.keybinds.putNoClobber(self.gpa, "delete_next_word", .{ .key = .delete,    .alt = true });
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

    log.info("window logical {f} pixels {f} natural scale {d} initial content scale {d} snap_to_pixels {any} accesskit {any}\n", .{ winSize, pxSize, pxSize.w / winSize.w, self.content_scale, self.snap_to_pixels, dvui.accesskit_enabled });

    errdefer self.deinit();

    self.subwindows.focused_id = self.data().id;
    self.frame_time_ns = 1;

    if (dvui.useFreeType) {
        dvui.Font.FreeType.intToError(c.FT_Init_FreeType(&dvui.ft2lib)) catch |err| {
            dvui.log.err("freetype error {any} trying to init freetype library\n", .{err});
            return error.freetypeError;
        };
    }

    return self;
}

pub fn deinit(self: *Self) void {
    if (dvui.accesskit_enabled) self.accesskit.deinit();

    self.data_store.deinit(self.gpa);

    self.texture_cache.deinit(self.gpa, self.backend);
    self.fonts.deinit(self.gpa, self.backend);

    self.debug.deinit(self.gpa);

    self.subwindows.deinit(self.gpa);
    self.min_sizes.deinit(self.gpa);

    {
        var it = self.tags.map.keyIterator();
        while (it.next()) |name| {
            //std.debug.print("tag free {s}\n", .{name.*});
            self.gpa.free(name.*);
        }
        self.tags.deinit(self.gpa);
    }

    self.animations.deinit(self.gpa);
    self.tab_index_prev.deinit(self.gpa);
    self.tab_index.deinit(self.gpa);

    self.dialogs.deinit(self.gpa);
    self.toasts.deinit(self.gpa);
    self.keybinds.deinit(self.gpa);
    self._arena.deinit();
    self._lifo_arena.deinit();
    self._widget_stack.deinit();
    dvui.struct_ui.deinit(self.gpa);
    self.* = undefined;
}

/// This allocator requires that the allocations are freed in a
/// LIFO (Last In First Out) order. The purpose is to reuse as
/// much memory as possible throughout a frame.
///
/// Can be very useful for quickly printing some text with
/// `std.fmt.allocPrint` or for temporary arrays.
///
/// ```zig
/// const msg = std.fmt.allocPrint(dvui.currentWindow().lifo(), "{d}", number);
/// defer dvui.currentWindow().lifo().free(msg);
/// // ... Render text in some widget here
/// ```
///
/// For allocations that should live for the entire frame, see
/// `Window.arena`
pub fn lifo(self: *Self) std.mem.Allocator {
    return self._lifo_arena.allocator();
}

/// A general allocator for using during a frame. All allocations
/// will be freed at the end of the frame.
///
/// If any dvui functions are called before freeing memory, it is
/// not guaranteed that the allocation can be freed.
///
/// For temporary allocations, see `Window.lifo`
pub fn arena(self: *Self) std.mem.Allocator {
    return self._arena.allocator();
}

/// called from gui thread
pub fn refreshWindow(self: *Self, src: std.builtin.SourceLocation, id: ?Id) void {
    if (self.debug.logRefresh(null)) {
        log.debug("{s}:{d} refresh {?x}", .{ src.file, src.line, id });
    }
    self.extra_frames_needed = 1;
}

/// called from any thread
pub fn refreshBackend(self: *Self, src: std.builtin.SourceLocation, id: ?Id) void {
    if (self.debug.logRefresh(null)) {
        log.debug("{s}:{d} refreshBackend {?x}", .{ src.file, src.line, id });
    }
    self.backend.refresh();
}

pub fn focusWidget(self: *Self, id: ?Id, subwindow_id: ?Id, event_num: ?u16) void {
    self.scroll_to_focused = false;
    const swid = subwindow_id orelse self.subwindows.current_id;
    if (self.subwindows.get(swid)) |sw| {
        if (sw.focused_widget_id == id) return;
        sw.focused_widget_id = id;
        if (event_num) |en| {
            self.focusEvents(en, sw.id, sw.focused_widget_id);
        }
        self.refreshWindow(@src(), null);

        if (id) |wid| {
            self.scroll_to_focused = true;

            if (self.last_registered_id_this_frame == wid) {
                self.last_focused_id_this_frame = wid;
                self.last_focused_id_in_subwindow = wid;
            } else {
                // walk parent chain
                var iter = self.current_parent.data().iterator();
                while (iter.next()) |wd| {
                    if (wd.id == wid) {
                        self.last_focused_id_this_frame = wid;
                        self.last_focused_id_in_subwindow = wid;
                        break;
                    }
                }
            }
        }
    }
}

pub fn focusSubwindow(self: *Self, subwindow_id: ?Id, event_num: ?u16) void {
    const winId = subwindow_id orelse self.subwindows.current_id;
    if (self.subwindows.focused_id == winId) return;

    self.subwindows.focused_id = winId;
    self.refreshWindow(@src(), null);
    if (event_num) |en| {
        if (self.subwindows.focused()) |sw| {
            self.focusEvents(en, sw.id, sw.focused_widget_id);
        }
    }
}

// Only for keyboard events
pub fn focusEvents(self: *Self, event_num: u16, windowId: ?Id, widgetId: ?Id) void {
    for (self.events.items) |*e| {
        if (e.num > event_num) {
            switch (e.evt) {
                .key, .text => {
                    e.target_windowId = windowId;
                    e.target_widgetId = widgetId;
                },
                .mouse => {},
                .window, .app => {},
            }
        }
    }
}

// Only for mouse/touch events
pub fn captureEvents(self: *Self, event_num: u16, widgetId: ?Id) void {
    for (self.events.items) |*e| {
        if (e.num > event_num) {
            switch (e.evt) {
                .key, .text => {},
                .mouse => |me| {
                    if (me.action != .wheel_x and me.action != .wheel_y) {
                        e.target_widgetId = widgetId;
                    }
                },
                .window, .app => {},
            }
        }
    }
}

/// Add a keyboard event (key up/down/repeat) to the dvui event list.
///
/// This can be called outside begin/end.  You should add all the events
/// for a frame either before begin() or just after begin() and before
/// calling normal dvui widgets.  end() clears the event list.
pub fn addEventKey(self: *Self, event: Event.Key) std.mem.Allocator.Error!bool {
    if (self.debug.target == .mouse_until_esc and event.action == .down and event.code == .escape) {
        // an escape will stop the debug stuff from following the mouse,
        // but need to stop it at the end of the frame when we've gotten
        // the info
        self.debug.target = .mouse_quitting;
        return true;
    }

    self.positionMouseEventRemove();

    self.modifiers = event.mod;

    self.event_num += 1;
    try self.events.append(self.arena(), Event{
        .num = self.event_num,
        .evt = .{ .key = event },
        .target_windowId = self.subwindows.focused_id,
        .target_widgetId = if (self.subwindows.focused()) |sw| sw.focused_widget_id else null,
    });

    const ret = (self.data().id != self.subwindows.focused_id);
    try self.positionMouseEventAdd();
    return ret;
}

pub const AddEventTextOptions = struct {
    text: []const u8,
    selected: bool = false,
    replace: bool = false,
    target_id: ?dvui.Id = null,
};

/// Add an event that represents text being typed.  This is distinct from
/// key up/down because the text could come from an IME (Input Method
/// Editor).
///
/// This can be called outside begin/end.  You should add all the events
/// for a frame either before begin() or just after begin() and before
/// calling normal dvui widgets.  end() clears the event list.
pub fn addEventText(self: *Self, opts: AddEventTextOptions) std.mem.Allocator.Error!bool {
    self.positionMouseEventRemove();

    self.event_num += 1;
    try self.events.append(self.arena(), Event{
        .num = self.event_num,
        .evt = .{
            .text = .{
                .txt = try self.arena().dupe(u8, opts.text),
                .selected = opts.selected,
                .replace = opts.replace,
            },
        },
        .target_windowId = self.subwindows.focused_id,
        .target_widgetId = opts.target_id orelse if (self.subwindows.focused()) |sw| sw.focused_widget_id else null,
    });

    const ret = (self.data().id != self.subwindows.focused_id);
    try self.positionMouseEventAdd();
    return ret;
}

pub const AddEventFocusOptions = struct {
    pt: Point.Physical,
    button: dvui.enums.Button = .none,
    target_id: ?dvui.Id = null,
};

/// Focus the widget under pt, without moving mouse_pt.
pub fn addEventFocus(self: *Self, opts: AddEventFocusOptions) std.mem.Allocator.Error!bool {
    self.positionMouseEventRemove();

    const target_id = opts.target_id orelse if (self.capture) |cap| cap.id else null;
    const winId = self.subwindows.windowFor(opts.pt);

    // normally the focus event is what focuses windows, but since the
    // base window is instantiated before events are added, it has to
    // do any event processing as the events come in, right now
    if (winId == self.data().id) {
        // focus the window here so any more key events get routed
        // properly
        self.focusSubwindow(self.data().id, null);
    }

    // add focus event
    self.event_num += 1;
    try self.events.append(self.arena(), Event{
        .num = self.event_num,
        .target_widgetId = target_id,
        .evt = .{
            .mouse = .{
                .action = .focus,
                .button = opts.button,
                .mod = self.modifiers,
                .p = opts.pt,
                .floating_win = winId,
            },
        },
    });

    try self.positionMouseEventAdd();
    return (self.data().id != winId);
}

pub const AddEventMouseMotionOptions = struct {
    pt: Point.Physical,
    target_id: ?dvui.Id = null,
};

/// Add a mouse motion event that the mouse is now at physical pixel pt.  This
/// is only for a mouse - for touch motion use addEventTouchMotion().
///
/// This can be called outside begin/end.  You should add all the events
/// for a frame either before begin() or just after begin() and before
/// calling normal dvui widgets.  end() clears the event list.
pub fn addEventMouseMotion(self: *Self, opts: AddEventMouseMotionOptions) std.mem.Allocator.Error!bool {
    self.positionMouseEventRemove();

    //log.debug("mouse motion {d} {d} -> {d} {d}", .{ x, y, newpt.x, newpt.y });
    const dp = opts.pt.diff(self.mouse_pt);
    self.mouse_pt = opts.pt;
    const winId = self.subwindows.windowFor(self.mouse_pt);

    // maybe could do focus follows mouse here
    // - generate a .focus event here instead of just doing focusWindow(winId, null);
    // - how to make it optional?

    const target_id = opts.target_id orelse if (self.capture) |cap| cap.id else null;

    self.event_num += 1;
    try self.events.append(self.arena(), Event{
        .num = self.event_num,
        .target_widgetId = target_id,
        .evt = .{
            .mouse = .{
                .action = .{ .motion = dp },
                .button = if (self.debug.touch_simulate_events and self.debug.touch_simulate_down) .touch0 else .none,
                .mod = self.modifiers,
                .p = self.mouse_pt,
                .floating_win = winId,
            },
        },
    });

    const ret = (self.data().id != winId);
    try self.positionMouseEventAdd();
    return ret;
}

/// Add a mouse button event (like left button down/up).
///
/// This can be called outside begin/end.  You should add all the events
/// for a frame either before begin() or just after begin() and before
/// calling normal dvui widgets.  end() clears the event list.
pub fn addEventMouseButton(self: *Self, b: dvui.enums.Button, action: Event.Mouse.Action) std.mem.Allocator.Error!bool {
    return addEventPointer(self, .{ .button = b, .action = action });
}

pub const AddEventPointerOptions = struct {
    button: dvui.enums.Button,
    action: Event.Mouse.Action,
    xynorm: ?Point = null,
    target_id: ?dvui.Id = null,
};

/// Add a touch up/down event.  This is similar to addEventMouseButton but
/// also includes a normalized (0-1) touch point.
///
/// This can be called outside begin/end.  You should add all the events
/// for a frame either before begin() or just after begin() and before
/// calling normal dvui widgets.  end() clears the event list.
pub fn addEventPointer(self: *Self, opts: AddEventPointerOptions) std.mem.Allocator.Error!bool {
    if (self.debug.target == .mouse_until_click and opts.action == .press and opts.button.pointer()) {
        // a left click or touch will stop the debug stuff from following
        // the mouse, but need to stop it at the end of the frame when
        // we've gotten the info
        self.debug.target = .mouse_quitting;
        return true;
    }

    var bb = opts.button;
    if (self.debug.touch_simulate_events and bb == .left) {
        bb = .touch0;
        if (opts.action == .press) {
            self.debug.touch_simulate_down = true;
        } else if (opts.action == .release) {
            self.debug.touch_simulate_down = false;
        }
    }

    if (opts.xynorm) |xyn| {
        self.mouse_pt = (Point{ .x = xyn.x * self.data().rect.w, .y = xyn.y * self.data().rect.h }).scale(self.natural_scale, Point.Physical);
    }

    const target_id = opts.target_id orelse if (self.capture) |cap| cap.id else null;
    const winId = self.subwindows.windowFor(self.mouse_pt);

    if (opts.action == .press and bb.pointer()) {
        _ = try self.addEventFocus(.{ .pt = self.mouse_pt, .button = bb });
    }

    self.positionMouseEventRemove();

    self.event_num += 1;
    try self.events.append(self.arena(), Event{
        .num = self.event_num,
        .target_widgetId = target_id,
        .evt = .{
            .mouse = .{
                .action = opts.action,
                .button = bb,
                .mod = self.modifiers,
                .p = self.mouse_pt,
                .floating_win = winId,
            },
        },
    });

    const ret = (self.data().id != winId);
    try self.positionMouseEventAdd();
    return ret;
}

/// Add a mouse wheel event.  Positive ticks means scrolling up / scrolling right.
///
/// If the shift key is being held, any vertical scroll will be transformed to
/// horizontal.
///
/// This can be called outside begin/end.  You should add all the events
/// for a frame either before begin() or just after begin() and before
/// calling normal dvui widgets.  end() clears the event list.
pub fn addEventMouseWheel(self: *Self, ticks: f32, dir: dvui.enums.Direction) std.mem.Allocator.Error!bool {
    self.positionMouseEventRemove();

    const winId = self.subwindows.windowFor(self.mouse_pt);

    //std.debug.print("mouse wheel {d}\n", .{ticks});

    self.event_num += 1;
    try self.events.append(self.arena(), Event{
        .num = self.event_num,
        .evt = .{
            .mouse = .{
                .action = if (dir == .vertical)
                    if (self.modifiers.shiftOnly())
                        // Invert ticks so scrolling up takes you left
                        // (matches behaviour of text editors and browsers)
                        .{ .wheel_x = -ticks }
                    else
                        .{ .wheel_y = ticks }
                else
                    .{ .wheel_x = ticks },
                .button = .none,
                .mod = self.modifiers,
                .p = self.mouse_pt,
                .floating_win = winId,
            },
        },
    });

    const ret = (self.data().id != winId);
    try self.positionMouseEventAdd();
    return ret;
}

/// Add an event that represents a finger moving while touching the screen.
///
/// This can be called outside begin/end.  You should add all the events
/// for a frame either before begin() or just after begin() and before
/// calling normal dvui widgets.  end() clears the event list.
pub fn addEventTouchMotion(self: *Self, finger: dvui.enums.Button, xnorm: f32, ynorm: f32, dxnorm: f32, dynorm: f32) std.mem.Allocator.Error!bool {
    self.positionMouseEventRemove();

    const newpt = (Point{ .x = xnorm * self.data().rect.w, .y = ynorm * self.data().rect.h }).scale(self.natural_scale, Point.Physical);
    //std.debug.print("touch motion {} {d} {d}\n", .{ finger, newpt.x, newpt.y });
    self.mouse_pt = newpt;

    const dp = (Point{ .x = dxnorm * self.data().rect.w, .y = dynorm * self.data().rect.h }).scale(self.natural_scale, Point.Physical);

    const winId = self.subwindows.windowFor(self.mouse_pt);

    const widget_id = if (self.capture) |cap| cap.id else null;

    self.event_num += 1;
    try self.events.append(self.arena(), Event{
        .num = self.event_num,
        .target_widgetId = widget_id,
        .evt = .{
            .mouse = .{
                .action = .{ .motion = dp },
                .button = finger,
                .mod = self.modifiers,
                .p = self.mouse_pt,
                .floating_win = winId,
            },
        },
    });

    const ret = (self.data().id != winId);
    try self.positionMouseEventAdd();
    return ret;
}

/// Add an event for a OS Window-level action (close, resize, etc.)
///
/// This can be called outside begin/end.  You should add all the events
/// for a frame either before begin() or just after begin() and before
/// calling normal dvui widgets.  end() clears the event list.
pub fn addEventWindow(self: *Self, evt: Event.Window) std.mem.Allocator.Error!void {
    self.positionMouseEventRemove();

    self.event_num += 1;
    try self.events.append(self.arena(), Event{
        .num = self.event_num,
        .target_windowId = self.data().id,
        .evt = .{ .window = evt },
    });

    try self.positionMouseEventAdd();
}

/// Add an event for an Application-level action (quit, going to background, etc.)
///
/// This can be called outside begin/end.  You should add all the events
/// for a frame either before begin() or just after begin() and before
/// calling normal dvui widgets.  end() clears the event list.
pub fn addEventApp(self: *Self, evt: Event.App) std.mem.Allocator.Error!void {
    self.positionMouseEventRemove();

    self.event_num += 1;
    try self.events.append(self.arena(), Event{
        .num = self.event_num,
        .target_windowId = self.data().id,
        .evt = .{ .app = evt },
    });

    try self.positionMouseEventAdd();
}

pub fn FPS(self: *const Self) f32 {
    const diff = self.frame_times[0];
    if (diff == 0) {
        return 0;
    }

    const avg = @as(f32, @floatFromInt(diff)) / @as(f32, @floatFromInt(self.frame_times.len - 1));
    const fps = 1_000_000.0 / avg;

    if (false) {
        std.debug.print("frame times\n", .{});
        var last: u32 = self.frame_times[0];
        for (self.frame_times, 0..) |t, i| {
            std.debug.print("  {d} {d} - {d}\n", .{ i, t, last - t });
            last = t;
        }
    }

    return fps;
}

/// Coordinates with `Window.waitTime` to run frames only when needed.
///
/// If on the previous frame you called `Window.waitTime` and waited with event
/// interruption, then pass true if that wait was interrupted (by an event).
///
/// Typically called right before `Window.begin`.
///
/// See usage in the example folder for the backend of you choice.
pub fn beginWait(self: *Self, interrupted: bool) i128 {
    var new_time = @max(self.frame_time_ns, self.backend.nanoTime());

    if (self.loop_wait_target) |target| {
        if (self.loop_wait_target_can_interrupt and interrupted) {
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

/// Takes output of `Window.end`.  Returns microseconds the app should wait
/// (with event interruption) before running the render loop again.
///
/// If `Window.max_fps` is not null, will sleep to keep the framerate under
/// that (usually set in the Debug window).
///
/// Pass return value to backend.waitEventTimeout().
/// Cooperates with `Window.beginWait` to estimate how much time is being spent
/// outside the render loop and account for that.
pub fn waitTime(self: *Self, end_micros: ?u32) u32 {
    // end_micros is the naive value we want to be between last begin and next begin

    // minimum time to wait to hit max fps target
    var min_micros: u32 = 0;
    if (self.max_fps) |mfps| {
        min_micros = @as(u32, @intFromFloat(1_000_000.0 / mfps));
    }

    //std.debug.print("  end {d:6} min {d:6}", .{end_micros, min_micros});

    // wait_micros is amount on top of min_micros we will conditionally wait
    var wait_micros = (end_micros orelse 0) -| min_micros;

    // assume that we won't target a specific time to sleep but if we do
    // calculate the targets before removing so_far and slop
    self.loop_wait_target = null;
    self.loop_wait_target_can_interrupt = false;
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
        self.loop_wait_target_can_interrupt = true;
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
) dvui.Backend.GenericError!void {
    try self.backend.accessKitInitInBegin(&self.accesskit);

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
    self.last_focused_id_this_frame = .zero;
    self.last_focused_id_in_subwindow = .zero;

    self.debug.reset(self.gpa);

    self.data_store.reset(self.gpa);
    self.texture_cache.reset(self.backend);
    self.subwindows.reset();
    self.fonts.reset(self.gpa, self.backend);

    for (self.frame_times, 0..) |_, i| {
        if (i == (self.frame_times.len - 1)) {
            self.frame_times[i] = 0;
        } else {
            self.frame_times[i] = self.frame_times[i + 1] +| micros_since_last;
        }
    }

    self.min_sizes.reset();
    //std.debug.print("min_sizes {d}\n", .{self.min_sizes.count()});

    {
        var it = self.tags.iterator();
        while (it.next_resetting()) |kv| {
            //std.debug.print("tag dead free {s}\n", .{kv.key});
            self.gpa.free(kv.key);
        }
        //std.debug.print("tags {d}\n", .{self.tags.count()});
    }

    // Swap current and previous tab index lists
    std.mem.swap(@TypeOf(self.tab_index), &self.tab_index, &self.tab_index_prev);
    // Retain capacity because it's likely to be small and that the same capacity will be needed again
    self.tab_index.clearRetainingCapacity();

    self.rect_pixels = .fromSize(self.backend.pixelSize());
    dvui.clipSet(self.rect_pixels);

    self.data().rect = Rect.Natural.fromSize(self.backend.windowSize()).scale(1.0 / self.content_scale, Rect);
    self.natural_scale = if (self.data().rect.w == 0) 1.0 else self.rect_pixels.w / self.data().rect.w;

    // deal with floating point weirdness when content_scale is like 1.25
    // otherwise we could end up with rect.w == 753.60004 or natural_scale 1.2499999
    self.data().rect.w = @round(self.data().rect.w * 100.0) / 100.0;
    self.data().rect.h = @round(self.data().rect.h * 100.0) / 100.0;
    self.natural_scale = @round(self.natural_scale * 100.0) / 100.0;

    //dvui.log.debug("window size {d} x {d} renderer size {d} x {d} scale {d} content_scale {d}", .{ self.data().rect.w, self.data().rect.h, self.rect_pixels.w, self.rect_pixels.h, self.natural_scale, self.content_scale });

    try self.subwindows.add(self.gpa, self.data().id, self.data().rect, self.rect_pixels, false, null, true);
    _ = self.subwindows.setCurrent(self.data().id, .cast(self.data().rect));

    self.extra_frames_needed -|= 1;
    self.secs_since_last_frame = @as(f32, @floatFromInt(micros_since_last)) / 1_000_000;

    {
        const micros: i32 = if (micros_since_last > math.maxInt(i32)) math.maxInt(i32) else @as(i32, @intCast(micros_since_last));
        var it = self.animations.iterator();
        while (it.next_used()) |kv| {
            if (kv.value_ptr.end_time <= 0) {
                @TypeOf(self.animations).setUsed(kv.value_ptr, false);
            } else {
                kv.value_ptr.start_time -|= micros;
                kv.value_ptr.end_time -|= micros;
                if (kv.value_ptr.start_time <= 0 and kv.value_ptr.end_time > 0) {
                    self.refreshWindow(@src(), null);
                }
            }
        }
        self.animations.reset();
    }

    if (!self.captured_last_frame) {
        // widget that had capture went away
        self.capture = null;
    }
    self.captured_last_frame = false;

    self.data().parent = self.widget();
    self.current_parent = self.widget();
    self.data().register();

    self.layout = .{};

    try self.backend.begin(self.arena());
}

fn positionMouseEventAdd(self: *Self) std.mem.Allocator.Error!void {
    const widget_id = if (self.capture) |cap| cap.id else null;

    try self.events.append(self.arena(), .{
        .num = self.event_num + 1,
        .target_widgetId = widget_id,
        .evt = .{ .mouse = .{
            .action = .position,
            .button = .none,
            .mod = self.modifiers,
            .p = self.mouse_pt,
            .floating_win = self.subwindows.windowFor(self.mouse_pt),
        } },
    });
}

fn positionMouseEventRemove(self: *Self) void {
    if (self.events.pop()) |e| {
        if (e.evt != .mouse or e.evt.mouse.action != .position) {
            log.err("positionMouseEventRemove removed a non-mouse or non-position event\n", .{});
        }
    }
}

/// Return the cursor the gui wants.  Client code should cache this if
/// switching the platform's cursor is expensive.
pub fn cursorRequested(self: *const Self) dvui.enums.Cursor {
    if (self.dragging.state == .dragging and self.dragging.cursor != null) {
        return self.dragging.cursor.?;
    } else {
        return self.cursor_requested orelse .arrow;
    }
}

/// Return the cursor the gui wants or null if mouse is not in gui windows.
/// Client code should cache this if switching the platform's cursor is
/// expensive.
pub fn cursorRequestedFloating(self: *const Self) ?dvui.enums.Cursor {
    if (self.capture != null or self.subwindows.windowFor(self.mouse_pt) != self.data().id) {
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

pub fn addRenderCommand(self: *Self, cmd: dvui.RenderCommand.Command, after: bool) void {
    var sw = self.subwindows.current() orelse &self.subwindows.stack.items[0];
    const render_cmd: dvui.RenderCommand = .{
        .clip = self.clipRect,
        .alpha = self.alpha,
        .snap = self.snap_to_pixels,
        .kerning = self.kerning,
        .cmd = cmd,
    };
    if (after) {
        sw.render_cmds_after.append(self.arena(), render_cmd) catch |err| {
            dvui.logError(@src(), err, "Could not append to render_cmds_after", .{});
        };
    } else {
        sw.render_cmds.append(self.arena(), render_cmd) catch |err| {
            dvui.logError(@src(), err, "Could not append to render_cmds", .{});
        };
    }
}

pub fn renderCommands(self: *Self, queue: []const dvui.RenderCommand) !void {
    const old_snap = self.snap_to_pixels;
    defer self.snap_to_pixels = old_snap;

    const old_kern = self.kerning;
    defer self.kerning = old_kern;

    const old_alpha = self.alpha;
    defer self.alpha = old_alpha;

    const old_clip = self.clipRect;
    defer self.clipRect = old_clip;

    const old_rendering = self.render_target.rendering;
    self.render_target.rendering = true;
    defer self.render_target.rendering = old_rendering;

    for (queue) |*drc| {
        self.snap_to_pixels = drc.snap;
        self.kerning = drc.kerning;
        self.clipRect = drc.clip;
        self.alpha = drc.alpha;
        switch (drc.cmd) {
            .text => |t| {
                try dvui.renderText(t);
            },
            .texture => |t| {
                try dvui.renderTexture(t.tex, t.rs, t.opts);
            },
            .pathFillConvex => |pf| {
                var options = pf.opts;
                options.color = options.color.opacity(self.alpha);
                var triangles = try pf.path.fillConvexTriangles(self.lifo(), options);
                defer triangles.deinit(self.lifo());
                try dvui.renderTriangles(triangles, null);
            },
            .pathStroke => |ps| {
                var options = ps.opts;
                options.color = options.color.opacity(self.alpha);
                var triangles = try ps.path.strokeTriangles(self.lifo(), options);
                defer triangles.deinit(self.lifo());
                try dvui.renderTriangles(triangles, null);
            },
            .triangles => |t| {
                try dvui.renderTriangles(t.tri, t.tex);
            },
        }
    }
}

pub fn timer(self: *Self, id: Id, micros: i32) void {
    // when start_time is in the future, we won't spam frames, so this will
    // cause a single frame and then expire
    const a = Animation{ .start_time = micros, .end_time = micros };
    const h = id.update("_timer");
    self.animations.put(self.gpa, h, a) catch |err| {
        dvui.logError(@src(), err, "Could not add timer for {x}", .{id});
    };
}

pub fn timerRemove(self: *Self, id: Id) void {
    const h = id.update("_timer");
    _ = self.animations.remove(h);
}

/// Standard way of showing toasts.  For the main window, this is called with
/// null in Window.end().
///
/// For floating windows or other widgets, pass non-null id. Then it shows
/// toasts that were previously added with non-null subwindow_id, and they are
/// shown on top of the current subwindow.
///
/// Toasts are shown in rect centered horizontally and 70% down vertically.
pub fn toastsShow(self: *Self, subwindow_id: ?Id, rect: Rect.Natural) void {
    var it = self.toasts.iterator(subwindow_id);
    it.i = self.toasts.indexOfSubwindow(subwindow_id) orelse return;
    var toast_win = dvui.FloatingWindowWidget.init(@src(), .{ .stay_above_parent_window = subwindow_id != null, .process_events_in_deinit = false }, .{ .background = false, .border = .{} });
    defer toast_win.deinit();

    toast_win.data().rect = dvui.placeIn(.cast(rect), toast_win.data().rect.size(), .none, .{ .x = 0.5, .y = 0.7 });
    toast_win.install();
    toast_win.drawBackground();
    toast_win.autoSize(); // affects next frame

    var vbox = dvui.box(@src(), .{}, .{});
    defer vbox.deinit();

    while (it.next()) |t| {
        t.display(t.id) catch |err| {
            dvui.logError(@src(), err, "Toast {x}", .{t.id});
        };
    }
}

pub const endOptions = struct {
    show_toasts: bool = true,
};

/// Normally this is called for you in `end`, but you can call it separately in
/// case you want to do something after everything has been rendered.
pub fn endRendering(self: *Self, opts: endOptions) void {
    if (opts.show_toasts) {
        dvui.toastsShow(null, dvui.windowRect());
    }
    var dialog_it = self.dialogs.iterator(null);
    while (dialog_it.next()) |d| {
        d.display(d.id) catch |err| {
            dvui.logError(@src(), err, "Dialog {x}", .{d.id});
        };
    }

    self.debug.show();

    for (self.subwindows.stack.items) |*sw| {
        self.renderCommands(sw.render_cmds.items) catch |err| {
            dvui.logError(@src(), err, "Failed to render commands for subwindow {x}", .{sw.id});
        };
        // Set to empty because it's allocated on the arena and will be freed there
        sw.render_cmds = .empty;

        self.renderCommands(sw.render_cmds_after.items) catch |err| {
            dvui.logError(@src(), err, "Failed to render commands after for subwindow {x}", .{sw.id});
        };
        // Set to empty because it's allocated on the arena and will be freed there
        sw.render_cmds_after = .empty;
    }

    self.end_rendering_done = true;
}

/// End of this window gui's rendering.  Renders retained dialogs and all
/// deferred rendering (subwindows, focus highlights).  Returns micros we
/// want between last call to `begin` and next call to `begin` (or null
/// meaning wait for event).  If wanted, pass return value to `waitTime` to
/// get a useful time to wait between render loops.
pub fn end(self: *Self, opts: endOptions) !?u32 {
    // make sure all widgets reset the parent
    dvui.parentReset(self.data().id, self.widget());

    if (!self.end_rendering_done) {
        self.endRendering(opts);
    }

    // Call this before freeing data so backend can use data allocated during frame.
    try self.backend.end();

    // events may have been tagged with a focus widget that never showed up
    const evts = dvui.events();
    for (evts) |*e| {
        if (self.dragging.state == .dragging and e.evt == .mouse and e.evt.mouse.action == .release) {
            if (self.debug.logEvents(null)) {
                log.debug("Clearing drag ({?s}) for unhandled mouse release", .{self.dragging.name});
            }
            self.dragging.state = .none;
            self.dragging.name = null;
            self.refreshWindow(@src(), null);
        }

        if (!dvui.eventMatch(e, .{ .id = self.data().id, .r = self.rect_pixels, .cleanup = true }))
            continue;

        if (e.evt == .mouse) {
            if (e.evt.mouse.action == .focus) {
                // unhandled click, clear focus
                self.focusWidget(null, null, null);
            }
        } else if (e.evt == .key) {
            if (e.evt.key.action == .down and e.evt.key.matchBind("next_widget")) {
                e.handle(@src(), self.data());
                dvui.tabIndexNext(e.num);
            }

            if (e.evt.key.action == .down and e.evt.key.matchBind("prev_widget")) {
                e.handle(@src(), self.data());
                dvui.tabIndexPrev(e.num);
            }
        }
    }

    if (self.debug.logEvents(null)) {
        for (evts) |*e| {
            if (e.handled) continue;
            log.debug("Unhandled {f}", .{e});
        }
        log.debug("Event Handing Frame End", .{});
    }

    self.mouse_pt_prev = self.mouse_pt;

    const focused_sw = self.subwindows.focused();
    if (focused_sw != null and !focused_sw.?.used) {
        // our focused subwindow didn't show this frame, focus the highest one that did
        var i = self.subwindows.stack.items.len;
        while (i > 0) : (i -= 1) {
            const sw = self.subwindows.stack.items[i - 1];
            if (sw.used and sw.stay_above_parent_window == null) {
                //std.debug.print("focused subwindow lost, focusing {d}\n", .{i - 1});
                self.focusSubwindow(sw.id, null);
                break;
            }
        }

        self.refreshWindow(@src(), null);
    }

    // Check that the final event was our synthetic mouse position event.
    // If one of the addEvent* functions forgot to add the synthetic mouse
    // event to the end this will print a debug message.
    self.positionMouseEventRemove();

    {
        const cap = self._arena.queryCapacity();
        //std.log.debug("_arena capacity {d}", .{cap});
        _ = self._arena.reset(.{ .retain_with_limit = cap - @divTrunc(cap, 10) });
    }

    {
        const cap = self._lifo_arena.queryCapacity();
        //std.log.debug("_lifo_arena capacity {d}", .{cap});
        _ = self._lifo_arena.reset(.{ .retain_with_limit = cap - @divTrunc(cap, 10) });
    }

    {
        const cap = self._widget_stack.queryCapacity();
        //std.log.debug("_widget_stack capacity {d}", .{cap});
        _ = self._widget_stack.reset(.{ .retain_with_limit = cap - @divTrunc(cap, 10) });
    }

    try self.initEvents();

    if (self.inject_motion_event) {
        self.inject_motion_event = false;
        _ = try self.addEventMouseMotion(.{ .pt = self.mouse_pt });
    }

    if (dvui.accesskit_enabled) {
        self.accesskit.pushUpdates();
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
    while (it.next_used()) |kv| {
        if (kv.value_ptr.start_time > 0) {
            const st = @as(u32, @intCast(kv.value_ptr.start_time));
            ret = @min(ret orelse st, st);
        } else if (kv.value_ptr.end_time > 0) {
            ret = 0;
            break;
        }
    }

    return ret;
}

fn initEvents(self: *Self) std.mem.Allocator.Error!void {
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
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *const Self) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *Self, id: Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    return self.layout.rectFor(self.data().rect, id, min_size, e, g);
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

const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Point = dvui.Point;
const Event = dvui.Event;
const WidgetData = dvui.WidgetData;
const Widget = dvui.Widget;
const Id = dvui.Id;

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
