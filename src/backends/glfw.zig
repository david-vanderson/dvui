const std = @import("std");
const dvui = @import("dvui");
pub const zglfw = @import("zglfw");

pub const kind: dvui.enums.Backend = .glfw;

const log = std.log.scoped(.glfw_backend);

const BYTES_PER_VERTEX = 20;
// Max events we can process one frame
const MAX_EVENT_BUFFER_SIZE = 512;

// Create a singleton for events
var events: ?std.ArrayList(GlfwEvent) = null;
mutex: std.Io.Mutex = .init,
refreshing: bool = false,

vsync: bool,

io: std.Io,
gpa: std.mem.Allocator,
arena: std.heap.ArenaAllocator,

state: ?State,
cursors: std.EnumArray(zglfw.Cursor.Shape, ?*zglfw.Cursor),

userKeyCallback: ?zglfw.KeyFn,
userCharCallback: ?zglfw.CharFn,
userMouseButtonCallback: ?zglfw.MouseButtonFn,
userCursorPosCallback: ?zglfw.CursorPosFn,
userFramebufferSizeCallback: ?zglfw.FramebufferSizeFn,
userScrollCallback: ?zglfw.ScrollFn,
userCloseCallback: ?zglfw.WindowCloseFn,

window: *zglfw.Window,

pub const State = struct {
    pub fn save(window: *zglfw.Window) State {
        _ = window;
        return .{};
    }

    pub fn restore(state: State) void {
        _ = state;
        return;
    }
};

const GlfwEvent = union(enum) {
    KeyFn: struct { *zglfw.Window, zglfw.Key, c_int, zglfw.Action, zglfw.Mods },
    CharFn: struct { *zglfw.Window, u32 },
    MouseButtonFn: struct { *zglfw.Window, zglfw.MouseButton, zglfw.Action, zglfw.Mods },
    CursorPosFn: struct { *zglfw.Window, f64, f64 },
    FrameBufferSizeFn: struct { *zglfw.Window, c_int, c_int },
    ScrollFn: struct { *zglfw.Window, f64, f64 },
    CloseFn: struct { *zglfw.Window },
};

pub const InitOptions = struct {
    /// allocator used for general backend bookkeeping
    gpa: std.mem.Allocator,
    /// The initial size of the application window
    size: dvui.Size,
    /// Set the minimum size of the window
    min_size: ?dvui.Size = null,
    /// Set the maximum size of the window
    max_size: ?dvui.Size = null,
    vsync: bool,
    /// The application title to display
    title: [:0]const u8,
    /// content of a PNG image (or any other format stb_image can load)
    /// tip: use @embedFile
    icon: ?[]const u8 = null,
};

/// Pass the window handle (pointer) to the glfw window
pub fn init(io: std.Io, gpa: std.mem.Allocator, window_: *anyopaque) @This() {
    dvui.io = io;
    const window: *zglfw.Window = @ptrCast(window_);

    events = std.ArrayList(GlfwEvent).initCapacity(gpa, MAX_EVENT_BUFFER_SIZE) catch @panic("OOM");

    return .{
        .io = io,
        .vsync = false,
        .window = window,
        .gpa = gpa,
        .arena = .init(gpa),
        .state = null,
        .cursors = .initFill(null),
        .userKeyCallback = window.setKeyCallback(&glfwKeyCallback),
        .userCharCallback = window.setCharCallback(&glfwCharCallback),
        .userMouseButtonCallback = window.setMouseButtonCallback(&glfwMouseButtonCallback),
        .userCursorPosCallback = window.setCursorPosCallback(&glfwCursorPosCallback),
        .userFramebufferSizeCallback = window.setFramebufferSizeCallback(&glfwFramebufferSizeCallback),
        .userScrollCallback = window.setScrollCallback(&glfwScrollCallback),
        .userCloseCallback = window.setCloseCallback(&glfwCloseCallback),
    };
}

pub fn deinit(ctx: *@This()) void {
    {
        var it = ctx.cursors.iterator();
        while (it.next()) |cursor| if (cursor.value.*) |cur| cur.destroy();
    }
    ctx.arena.deinit();
    if (events) |*_events| _events.deinit(ctx.gpa);
    _ = ctx.window.setKeyCallback(ctx.userKeyCallback);
    _ = ctx.window.setCharCallback(ctx.userCharCallback);
    _ = ctx.window.setMouseButtonCallback(ctx.userMouseButtonCallback);
    _ = ctx.window.setCursorPosCallback(ctx.userCursorPosCallback);
    _ = ctx.window.setFramebufferSizeCallback(ctx.userFramebufferSizeCallback);
    _ = ctx.window.setScrollCallback(ctx.userScrollCallback);
}

pub fn begin(ctx: *@This(), _: std.mem.Allocator) !void {
    ctx.state = State.save(ctx.window);
}

pub fn end(ctx: *@This()) !void {
    if (ctx.state) |s| {
        s.restore();
    } else {
        log.err("Begin has not been called before end!", .{});
        return error.BackendError;
    }
}

pub fn addAllEvents(_: *@This(), win: *dvui.Window) void {
    if (events) |*ev| {
        for (ev.items) |event| {
            switch (event) {
                .KeyFn => |v| handleKeyEvent(win, v[0], v[1], v[2], v[3], v[4]),
                .CharFn => |v| handleCharEvent(win, v[0], v[1]),
                .MouseButtonFn => |v| handleMouseButtonEvent(win, v[0], v[1], v[2], v[3]),
                .CursorPosFn => |v| handleCursorPosEvent(win, v[0], v[1], v[2]),
                .FrameBufferSizeFn => |v| handleFramebufferSizeEvent(win, v[0], v[1], v[2]),
                .ScrollFn => |v| handleScrollEvent(win, v[0], v[1], v[2]),
                .CloseFn => |v| handleCloseEvent(win, v[0]),
            }
        }
        ev.clearRetainingCapacity();
    }
}

pub fn pixelSize(ctx: *@This()) dvui.Size.Physical {
    const w, const h = ctx.window.getFramebufferSize();
    if (w < 0 or h < 0) log.warn("Window reports negative framebuffer size!", .{});
    return .{
        .h = @floatFromInt(@max(0, h)),
        .w = @floatFromInt(@max(0, w)),
    };
}

pub fn windowSize(ctx: *@This()) dvui.Size.Natural {
    var w: c_int, var h: c_int = .{ undefined, undefined };
    zglfw.getWindowSize(ctx.window, &w, &h);
    if (w < 0 or h < 0) log.warn("Window reports negative size!", .{});
    return .{
        .h = @floatFromInt(@max(0, h)),
        .w = @floatFromInt(@max(0, w)),
    };
}

pub fn contentScale(ctx: *@This()) f32 {
    const scale = ctx.window.getContentScale();
    return scale[0];
}

/// Get clipboard content (text only)
pub fn clipboardText(ctx: *@This()) ![]const u8 {
    const text = ctx.window.getClipboardString() orelse {
        log.warn("Failed get clipboard string!", .{});
        return error.BackendError;
    };
    return text[0 .. text.len - 2];
}

/// Set clipboard content (text only)
pub fn clipboardTextSet(ctx: *@This(), text: []const u8) !void {
    const textZ = try ctx.gpa.dupeSentinel(u8, text, 0);
    zglfw.setClipboardString(ctx.window, textZ);
    ctx.gpa.free(textZ);
}

/// Open URL in system browser.  If using the web backend, new_window controls
/// whether to navigate the current page to the url or open in a new window/tab.
pub fn openURL(_: *@This(), _: []const u8, _: bool) !void {
    return;
}

pub fn renderPresent(_: *@This()) void {}
pub fn textInputRect(_: *@This(), _: ?dvui.Rect.Natural) void {}

pub fn setCursor(ctx: *@This(), cursor: dvui.enums.Cursor) void {
    // Initialize all different types of cursors at start
    // of dvui, and then simply turn different ones on.

    if (cursor == .hidden) return ctx.window.setInputMode(.cursor, .hidden) catch |err| {
        log.err("Failed to set input mode! Err: {t}", .{err});
        return;
    };
    ctx.window.setInputMode(.cursor, .normal) catch |err| {
        log.err("Failed to set input mode! Err: {t}", .{err});
        return;
    };

    const shape: zglfw.Cursor.Shape = switch (cursor) {
        .arrow => .arrow,
        .arrow_all => .resize_all,
        .arrow_n_s => .resize_ns,
        .arrow_ne_sw => .resize_nesw,
        .arrow_nw_se => .resize_nwse,
        .arrow_w_e => .resize_ew,
        .bad => .not_allowed,
        .crosshair => .crosshair,
        .hand => .hand,
        .ibeam => .ibeam,
        .wait => .arrow, //TODO: Make a more sensible choice
        .wait_arrow => .arrow,

        .hidden => unreachable,
    };
    if (ctx.cursors.get(shape)) |cur| ctx.window.setCursor(cur) else {
        ctx.cursors.getPtr(shape).* = zglfw.createStandardCursor(shape) catch |err| {
            log.err("Failed to create cursor! Err: {t}", .{err});
            return;
        };
    }
    ctx.window.setCursor(ctx.cursors.get(shape).?);
}

/// Get the preferredColorScheme if available
pub fn preferredColorScheme(_: *@This()) ?dvui.enums.ColorScheme {
    return null;
}

pub fn prefersReducedMotion(_: *@This()) bool {
    return false;
}

/// Return true if we woke up from an event or refresh, false if from timeout.
pub fn pollEventsTimeout(self: *@This(), wait_time: u32) bool {
    if (self.refreshCheck()) return true;
    const wt_ns: u64 = @as(u64, wait_time) * 1000;
    const wt_s = @as(f64, @floatFromInt(wait_time)) / std.time.us_per_s;
    const start = self.nanoTime();
    // Fix issue on Wayland where window is woken up by EGL buffer swap
    zglfw.waitEventsTimeout(@max(wt_s, 0));
    if (self.refreshCheck()) return true;

    if (events) |*ev| while (ev.items.len == 0) {
        const elapsed = self.nanoTime() - start;
        if (elapsed >= wt_ns) break;
        const elapsed_s = @as(f64, @floatFromInt(elapsed)) / std.time.ns_per_s;
        zglfw.waitEventsTimeout(@max(wt_s - elapsed_s, 0));
        if (self.refreshCheck()) return true;
    };

    return false;
}

pub fn nanoTime(self: *@This()) i128 {
    const ret = std.Io.Clock.awake.now(self.io);
    return ret.nanoseconds;
}

pub fn sleep(self: *@This(), ns: u64) void {
    std.Io.Clock.Duration.sleep(.{ .clock = .awake, .raw = .fromNanoseconds(ns) }, self.io) catch {};
}

/// Called by `dvui.refresh` when it is called from a background
/// thread.  Used to wake up the gui thread.  It only has effect if you
/// are using `dvui.Window.waitTime` or some other method of waiting until
/// a new event comes in.
pub fn refresh(self: *@This()) void {
    {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.refreshing = true;
    }
    return zglfw.postEmptyEvent();
}

fn refreshCheck(self: *@This()) bool {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    if (self.refreshing) {
        self.refreshing = false;
        return true;
    }

    return false;
}

pub fn glfwCodeToDvuiCode(key: zglfw.Key) dvui.enums.Key {
    //TODO: Consider using scancode instead
    return switch (key) {
        .a => .a,
        .b => .b,
        .c => .c,
        .d => .d,
        .e => .e,
        .f => .f,
        .g => .g,
        .h => .h,
        .i => .i,
        .j => .j,
        .k => .k,
        .l => .l,
        .m => .m,
        .n => .n,
        .o => .o,
        .p => .p,
        .q => .q,
        .r => .r,
        .s => .s,
        .t => .t,
        .u => .u,
        .v => .v,
        .w => .w,
        .x => .x,
        .y => .y,
        .z => .z,

        .zero => .zero,
        .one => .one,
        .two => .two,
        .three => .three,
        .four => .four,
        .five => .five,
        .six => .six,
        .seven => .seven,
        .eight => .eight,
        .nine => .nine,

        .F1 => .f1,
        .F2 => .f2,
        .F3 => .f3,
        .F4 => .f4,
        .F5 => .f5,
        .F6 => .f6,
        .F7 => .f7,
        .F8 => .f7,
        .F9 => .f7,
        .F10 => .f7,
        .F11 => .f7,
        .F12 => .f7,
        .F13 => .f7,
        .F14 => .f14,
        .F15 => .f15,
        .F16 => .f16,
        .F17 => .f17,
        .F18 => .f18,
        .F19 => .f19,
        .F20 => .f20,
        .F21 => .f21,
        .F22 => .f22,
        .F23 => .f23,
        .F24 => .f24,
        .F25 => .f25,

        .kp_divide => .kp_divide,
        .kp_multiply => .kp_multiply,
        .kp_subtract => .kp_subtract,
        .kp_add => .kp_add,
        .kp_0 => .kp_0,
        .kp_1 => .kp_1,
        .kp_2 => .kp_2,
        .kp_3 => .kp_3,
        .kp_4 => .kp_4,
        .kp_5 => .kp_5,
        .kp_6 => .kp_6,
        .kp_7 => .kp_7,
        .kp_8 => .kp_8,
        .kp_9 => .kp_9,
        .kp_decimal => .kp_decimal,
        .kp_equal => .kp_equal,
        .kp_enter => .kp_enter,

        .enter => .enter,
        .escape => .escape,
        .tab => .tab,
        .left_shift => .left_shift,
        .right_shift => .right_shift,
        .left_control => .left_control,
        .right_control => .right_control,
        .left_alt => .left_alt,
        .right_alt => .right_alt,
        .left_super => .left_command,
        .right_super => .right_command,
        .menu => .menu,
        .num_lock => .num_lock,
        .caps_lock => .caps_lock,
        .print_screen => .print,
        .scroll_lock => .scroll_lock,
        .pause => .pause,
        .delete => .delete,
        .home => .home,
        .end => .end,
        .page_up => .page_up,
        .page_down => .page_down,
        .insert => .insert,
        .left => .left,
        .right => .right,
        .up => .up,
        .down => .down,
        .backspace => .backspace,
        .space => .space,
        .minus => .minus,
        .equal => .equal,
        .left_bracket => .left_bracket,
        .right_bracket => .right_bracket,
        .backslash => .backslash,
        .semicolon => .semicolon,
        .apostrophe => .apostrophe,
        .comma => .comma,
        .period => .period,
        .slash => .slash,
        .grave_accent => .grave,

        else => .unknown,
    };
}

fn glfwKeyCallback(
    window: *zglfw.Window,
    key: zglfw.Key,
    scancode: c_int,
    action: zglfw.Action,
    mods: zglfw.Mods,
) callconv(.c) void {
    if (events) |*ev| {
        if (ev.items.len >= MAX_EVENT_BUFFER_SIZE)
            return log.warn("Max event buffer size exceeded! Dropping event!", .{});
        std.debug.assert(ev.capacity == MAX_EVENT_BUFFER_SIZE);
        ev.appendAssumeCapacity(.{ .KeyFn = .{ window, key, scancode, action, mods } });
    } else log.warn("Events are currently not implemented!", .{});
}

fn handleKeyEvent(
    dvui_window: *dvui.Window,
    window: *zglfw.Window,
    key: zglfw.Key,
    scancode: c_int,
    action: zglfw.Action,
    mods: zglfw.Mods,
) callconv(.c) void {
    const ctx: *@This() = dvui_window.backend.impl;
    const dvui_action: @FieldType(dvui.Event.Key, "action") = switch (action) {
        .press => .down,
        .release => .up,
        .repeat => .repeat,
    };
    const dvui_key = glfwCodeToDvuiCode(key);
    const dvui_mod = blk: {
        const Mod = dvui.enums.Mod;
        var mod = Mod.none;
        mod.combine(if (mods.shift or key == .left_shift) .lshift else .none);
        mod.combine(if (mods.alt or key == .left_alt) .lalt else .none);
        mod.combine(if (mods.control or key == .left_control) .lcontrol else .none);
        mod.combine(if (mods.super or key == .left_super) .lcommand else .none);
        break :blk mod;
    };
    if (!(dvui_window.addEventKey(.{ .action = dvui_action, .code = dvui_key, .mod = dvui_mod }) catch |err| {
        log.err("Encountered error when adding event! Err: {}", .{err});
        return;
    })) {
        if (ctx.userKeyCallback) |callback| callback(window, key, scancode, action, mods);
    }
}

fn glfwCharCallback(window: *zglfw.Window, codepoint: u32) callconv(.c) void {
    if (events) |*ev| {
        if (ev.items.len >= MAX_EVENT_BUFFER_SIZE)
            return log.warn("Max event buffer size exceeded! Dropping event!", .{});
        std.debug.assert(ev.capacity == MAX_EVENT_BUFFER_SIZE);
        ev.appendAssumeCapacity(.{ .CharFn = .{ window, codepoint } });
    } else log.warn("Events are currently not implemented!", .{});
}

fn handleCharEvent(dvui_window: *dvui.Window, window: *zglfw.Window, codepoint: u32) void {
    const ctx: *@This() = dvui_window.backend.impl;
    if (!(dvui_window.addEventText(.{ .text = @as([4]u8, @bitCast(codepoint))[0..] }) catch |err| {
        log.err("Encountered error when adding event! Err: {}", .{err});
        if (ctx.userCharCallback) |callback| callback(window, codepoint);
        return;
    })) {
        if (ctx.userCharCallback) |callback| callback(window, codepoint);
    }
}

fn glfwCursorPosCallback(window: *zglfw.Window, xpos: f64, ypos: f64) callconv(.c) void {
    if (events) |*ev| {
        if (ev.items.len >= MAX_EVENT_BUFFER_SIZE)
            return log.warn("Max event buffer size exceeded! Dropping event!", .{});
        std.debug.assert(ev.capacity == MAX_EVENT_BUFFER_SIZE);
        ev.appendAssumeCapacity(.{ .CursorPosFn = .{ window, xpos, ypos } });
    } else log.warn("Events are currently not implemented!", .{});
}

fn handleCursorPosEvent(dvui_window: *dvui.Window, window: *zglfw.Window, xpos: f64, ypos: f64) void {
    const ctx: *@This() = dvui_window.backend.impl;
    const windowW = ctx.windowSize().w;
    const scale = if (windowW == 0) 1.0 else (ctx.pixelSize().w / ctx.windowSize().w);

    const physical: dvui.Point.Physical = .{
        .x = @floatCast(xpos * scale),
        .y = @floatCast(ypos * scale),
    };
    if (!(dvui_window.addEventMouseMotion(.{ .pt = physical }) catch |err| {
        log.err("Encountered error when adding event! Err: {}", .{err});
        if (ctx.userCursorPosCallback) |callback| callback(window, xpos, ypos);
        return;
    })) {
        if (ctx.userCursorPosCallback) |callback| callback(window, xpos, ypos);
    }
}

fn glfwMouseButtonCallback(
    window: *zglfw.Window,
    button: zglfw.MouseButton,
    action: zglfw.Action,
    mods: zglfw.Mods,
) callconv(.c) void {
    if (events) |*ev| {
        if (ev.items.len >= MAX_EVENT_BUFFER_SIZE)
            return log.warn("Max event buffer size exceeded! Dropping event!", .{});
        std.debug.assert(ev.capacity == MAX_EVENT_BUFFER_SIZE);
        ev.appendAssumeCapacity(.{ .MouseButtonFn = .{ window, button, action, mods } });
    } else log.warn("Events are currently not implemented!", .{});
}

fn handleMouseButtonEvent(
    dvui_window: *dvui.Window,
    window: *zglfw.Window,
    button: zglfw.MouseButton,
    action: zglfw.Action,
    mods: zglfw.Mods,
) void {
    const ctx: *@This() = dvui_window.backend.impl;
    const dvui_button: dvui.enums.Button = switch (button) {
        .left => .left,
        .right => .right,
        .middle => .middle,
        .four => .four,
        .five => .five,
        .six => .six,
        .seven => .seven,
        .eight => .eight,
    };
    const dvui_action: dvui.Event.Mouse.Action = switch (action) {
        .press => .press,
        .release => .release,
        else => unreachable,
    };
    if (!(dvui_window.addEventMouseButton(dvui_button, dvui_action) catch |err| {
        log.err("Encountered error when adding event! Err: {}", .{err});
        if (ctx.userMouseButtonCallback) |callback| callback(window, button, action, mods);
        return;
    })) {
        if (ctx.userMouseButtonCallback) |callback| callback(window, button, action, mods);
    }
}
fn glfwScrollCallback(window: *zglfw.Window, xrel: f64, yrel: f64) callconv(.c) void {
    if (events) |*ev| {
        if (ev.items.len >= MAX_EVENT_BUFFER_SIZE)
            return log.warn("Max event buffer size exceeded! Dropping event!", .{});
        std.debug.assert(ev.capacity == MAX_EVENT_BUFFER_SIZE);
        ev.appendAssumeCapacity(.{ .ScrollFn = .{ window, xrel, yrel } });
    } else log.warn("Events are currently not implemented!", .{});
}

fn handleScrollEvent(dvui_window: *dvui.Window, window: *zglfw.Window, xrel: f64, yrel: f64) void {
    const ctx: *@This() = dvui_window.backend.impl;
    var consumed_x: bool = false;
    var consumed_y: bool = false;
    if (xrel != 0) {
        const scrollx: f32 = @floatCast(xrel * dvui.scroll_speed);
        const min = dvui_window.mouseWheelBatch(.horizontal, @floatCast(xrel));
        const mouse_type = dvui.Window.mouseTypeGLFW(min);
        consumed_x = dvui_window.addEventMouseWheel(scrollx, .horizontal, mouse_type) catch |err| {
            log.err("Encountered error when adding event! Err: {t}", .{err});
            if (ctx.userScrollCallback) |callback| callback(window, xrel, yrel);
            return;
        };
    }

    if (yrel != 0) {
        const scrolly: f32 = @floatCast(yrel * dvui.scroll_speed);
        const min = dvui_window.mouseWheelBatch(.vertical, @floatCast(yrel));
        const mouse_type = dvui.Window.mouseTypeGLFW(min);
        consumed_y = dvui_window.addEventMouseWheel(scrolly, .vertical, mouse_type) catch |err| {
            log.err("Encountered error when adding event! Err: {t}", .{err});
            if (ctx.userScrollCallback) |callback| callback(window, xrel, yrel);
            return;
        };
    }

    if (!(consumed_x and consumed_y)) {
        if (ctx.userScrollCallback) |callback| callback(
            window,
            if (consumed_x) 0 else xrel,
            if (consumed_y) 0 else yrel,
        );
    }
}

fn glfwFramebufferSizeCallback(
    window: *zglfw.Window,
    width: c_int,
    height: c_int,
) callconv(.c) void {
    if (events) |*ev| {
        if (ev.items.len >= MAX_EVENT_BUFFER_SIZE)
            return log.warn("Max event buffer size exceeded! Dropping event!", .{});
        std.debug.assert(ev.capacity == MAX_EVENT_BUFFER_SIZE);
        ev.appendAssumeCapacity(.{ .FrameBufferSizeFn = .{ window, width, height } });
    } else log.warn("Events are currently not implemented!", .{});
}

fn handleFramebufferSizeEvent(
    dvui_window: *dvui.Window,
    window: *zglfw.Window,
    width: c_int,
    height: c_int,
) void {
    const ctx: *@This() = dvui_window.backend.impl;
    if (ctx.userFramebufferSizeCallback) |callback| callback(window, width, height);
}

fn glfwCloseCallback(window: *zglfw.Window) callconv(.c) void {
    if (events) |*ev| {
        if (ev.items.len >= MAX_EVENT_BUFFER_SIZE)
            return log.warn("Max event buffer size exceeded! Dropping event!", .{});
        std.debug.assert(ev.capacity == MAX_EVENT_BUFFER_SIZE);
        ev.appendAssumeCapacity(.{ .CloseFn = .{window} });
    } else log.warn("Events are currently not implemented!", .{});
}

fn handleCloseEvent(dvui_window: *dvui.Window, window: *zglfw.Window) void {
    dvui_window.addEventWindow(.{ .action = .close }) catch |err| {
        log.err("Encountered error when adding event! Err: {t}", .{err});
    };
    const ctx: *@This() = dvui_window.backend.impl;
    if (ctx.userCloseCallback) |callback| callback(window);
}

pub fn main(main_init: std.process.Init) !void {
    dvui.App.main_init = main_init;
    const app = dvui.App.get() orelse return error.DvuiAppNotDefined;
    const config = app.config.get();

    const gpa = config.gpa orelse main_init.gpa;
    const io = config.io orelse main_init.io;

    var window: *zglfw.Window = undefined;

    try zglfw.init();
    zglfw.windowHint(.scale_to_monitor, true);

    if (dvui.render_backend.kind == .opengl) {
        zglfw.windowHint(.context_version_major, 3);
        zglfw.windowHint(.context_version_minor, 3);
        zglfw.windowHint(.opengl_profile, .opengl_core_profile);
        zglfw.windowHint(.opengl_forward_compat, true);
        zglfw.windowHint(.client_api, .opengl_api);
    }
    window = try zglfw.Window.create(
        @trunc(config.size.w),
        @trunc(config.size.h),
        config.title,
        null,
    );

    var renderer = blk: switch (dvui.render_backend.kind) {
        .opengl => {
            zglfw.makeContextCurrent(window);
            if (config.vsync) zglfw.swapInterval(1) else zglfw.swapInterval(0);
            break :blk try dvui.render_backend.init(gpa, zglfw.getProcAddress, "330");
        },
        else => @compileError("unsupported renderer for backend"),
    };
    defer renderer.deinit();

    var impl = init(io, gpa, window);
    defer impl.deinit();

    const backend = dvui.Backend.init(&impl, &renderer);
    var win = try dvui.Window.init(@src(), gpa, backend, .{});
    defer win.deinit();

    if (config.window_init_options.open_flag != null)
        dvui.log.warn("`open_flag` option has no effect in dvui App. It is managed internally in that case.", .{});
    var window_open = true;
    win.open_flag = &window_open;

    var interrupted = true;

    while (!window.shouldClose() and window_open) {
        impl.addAllEvents(&win);

        // temporarily disabled due to "unable to perform tail call: compiler backend 'stage2_x86_64' does not support tail calls"
        // zgl.clearColor(0.1, 0.4, 0.25, 1.0);
        // zgl.clear(.{ .color = true, .stencil = true, .depth = true });

        const nstime = win.beginWait(interrupted);
        try win.begin(nstime);

        const res = try app.frameFn();

        const end_micros = try win.end(.{});
        const wait_event_micros = win.waitTime(end_micros);

        if (res != .ok or !window_open) break;

        window.swapBuffers();

        interrupted = impl.pollEventsTimeout(wait_event_micros);
    }
}
