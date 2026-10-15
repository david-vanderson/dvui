const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
pub const pugl = @import("pugl");
pub const OpenGlBackend = @import("pugl-opengl");

pub const kind = dvui.enums.Backend.pugl;

const PuglBackend = @This();

io: std.Io,
gpa: std.mem.Allocator,
view: pugl.View,
// SAFETY: assigned in begin
arena: std.mem.Allocator = undefined,
opengl_backend: OpenGlBackend,
renderer: dvui.render_backend,

pub fn backend(self: *PuglBackend) dvui.Backend {
    return .init(self, &self.renderer);
}

pub const InitOptions = struct {
    io: std.Io,
    gpa: std.mem.Allocator,
    view: pugl.View,
};

/// This function will immediately call `pugl.View.realize` on `options.view`, so make sure it's properly configured
/// before. Its graphics API hints and pugl render backend will be overwritten.
pub fn init(options: InitOptions) !PuglBackend {
    dvui.io = options.io;

    try options.view.setContextApi(.opengl);
    try options.view.setIntHint(.context_version_major, 3);
    try options.view.setIntHint(.context_version_minor, 2);
    try options.view.setContextProfile(.core);

    const opengl_backend = OpenGlBackend.init(options.view);
    try options.view.setBackend(opengl_backend.backend);

    try options.view.realize();

    try opengl_backend.enterContext();

    var ret: PuglBackend = .{
        .io = options.io,
        .gpa = options.gpa,
        .view = options.view,
        .opengl_backend = opengl_backend,
        .renderer = try .init(options.gpa, getProcAddress, "330"),
    };

    errdefer ret.deinit();

    try opengl_backend.leaveContext();

    return ret;
}

pub fn deinit(self: *PuglBackend) void {
    self.renderer.deinit();
}

pub fn nanoTime(self: *PuglBackend) i128 {
    return std.Io.Clock.awake.now(self.io).toNanoseconds();
}

pub fn sleep(self: *PuglBackend, ns: u64) void {
    self.io.sleep(.fromNanoseconds(ns), .awake) catch {};
}

pub fn begin(self: *PuglBackend, arena: std.mem.Allocator) !void {
    self.arena = arena;
}

pub fn end(_: *PuglBackend) !void {}

pub fn pixelSize(self: *const PuglBackend) dvui.Size.Physical {
    const size = self.view.getSizeHint(.current);
    return .{
        .w = @floatFromInt(size.width),
        .h = @floatFromInt(size.height),
    };
}

pub fn windowSize(self: *const PuglBackend) dvui.Size.Natural {
    // HACK: pugl size hints are only physical
    const size = self.view.getSizeHint(.current);
    const scale: f32 = @floatCast(self.view.getScaleFactor());
    return .{
        .w = @as(f32, @floatFromInt(size.width)) / scale,
        .h = @as(f32, @floatFromInt(size.height)) / scale,
    };
}

pub fn contentScale(self: *const PuglBackend) f32 {
    return @floatCast(self.view.getScaleFactor());
}

pub fn clipboardText(self: *PuglBackend) dvui.Backend.GenericError![]const u8 {
    // HACK: pugl doesn't let us directly read the contents of the system clipboard,
    // so we have to request a DataOffer event and "paste" the received text later
    self.view.paste() catch return error.BackendError;
    return "";
}

pub fn clipboardTextSet(self: *PuglBackend, text: []const u8) dvui.Backend.GenericError!void {
    self.view.setClipboard(u8, .general, "text/plain", text) catch return error.BackendError;
}

pub fn openURL(_: *PuglBackend, _: []const u8, _: bool) !void {}

pub fn preferredColorScheme(self: *PuglBackend) ?dvui.enums.ColorScheme {
    return if (self.view.getBoolHint(.dark_frame)) |dark|
        if (dark) .dark else .light
    else
        null;
}

pub fn prefersReducedMotion(_: *PuglBackend) bool {
    return false;
}

pub fn refresh(self: *PuglBackend) void {
    self.view.obscure() catch |e| dvui.log.err("failed to refresh window: {}", .{e});
}

pub fn native(self: *PuglBackend, _: *dvui.Window) dvui.Window.Native {
    const handle = self.view.getNativeView();
    return switch (builtin.os.tag) {
        .windows => .{ .hwnd = @ptrFromInt(handle) },
        .macos => .{ .cocoa_window = @ptrFromInt(handle) },
        else => {},
    };
}

pub fn title(self: *PuglBackend, _: *dvui.Window, new_title: []const u8) void {
    const new_title_sentinel = self.gpa.dupeSentinel(u8, new_title, 0) catch {
        dvui.log.err("out of memory", .{});
        return;
    };
    defer self.gpa.free(new_title_sentinel);
    self.view.setStringHint(.window_title, new_title_sentinel) catch |e| dvui.log.err("failed to set window title: {}", .{e});
}

pub fn windowStateSet(self: *PuglBackend, _: *dvui.Window, state: dvui.enums.WindowState) void {
    var style = self.view.getViewStyle();

    switch (state) {
        .normal => {
            style.tall = false;
            style.wide = false;
            style.fullscreen = false;
        },
        .fullscreen => {
            style.tall = false;
            style.wide = false;
            style.fullscreen = true;
        },
        .maximize => {
            style.tall = true;
            style.wide = true;
            style.fullscreen = false;
        },
    }

    self.view.setViewStyle(style) catch |e| dvui.log.err("failed to set window state '{}': {}", .{ state, e });
}

pub fn waitEventTimeout(self: *PuglBackend, timeout_us: u32) void {
    const world = self.view.getWorld();
    (if (timeout_us == std.math.maxInt(@TypeOf(timeout_us)))
        world.update(-1)
    else
        world.update(@as(f64, @floatFromInt(timeout_us)) / std.time.us_per_s)) catch |e|
        dvui.log.err("waitEventTimeout failed: {}", .{e});
}

pub fn renderPresent(_: *PuglBackend) void {}

pub fn textInputRect(_: *PuglBackend, _: ?dvui.Rect.Natural) void {}

pub fn setCursor(self: *PuglBackend, cursor: dvui.enums.Cursor) void {
    self.view.setCursor(switch (cursor) {
        .ibeam => .caret,
        .arrow_nw_se => .up_left_down_right,
        .arrow_ne_sw => .up_right_down_left,
        .arrow_w_e => .left_right,
        .arrow_n_s => .up_down,
        .arrow_all => .all_scroll,
        .bad => .no,
        .wait, .wait_arrow, .hidden => .arrow,
        inline else => |c| @field(pugl.View.Cursor, @tagName(c)),
    }) catch |e|
        dvui.log.err("failed to set cursor: {}", .{e});
}

pub fn handleEvent(self: *PuglBackend, event: pugl.event.Event, window: *dvui.Window) pugl.Error!void {
    switch (event) {
        .close => try window.addEventWindow(.{ .action = .close }),
        .key_press, .key_release => |key| _ =
            try window.addEventKey(puglKeyToDvui(key.key, key.state, @fromBackingInt(@intCast(@backingInt(key.type))))),
        .text => |text| {
            if (window.textInputRequested() != null and !(text.state.ctrl or text.state.alt or text.state.super))
                _ = try window.addEventText(.{
                    .text = &text.string,
                });
        },
        .pointer_in => _ = try window.addEventPointer(.{
            .action = .focus,
            .button = .none,
        }),
        .button_press => |button| _ = try window.addEventMouseButton(
            std.enums.fromInt(dvui.enums.Button, button.button + 1) orelse return,
            .press,
        ),
        .button_release => |button| _ = try window.addEventMouseButton(
            std.enums.fromInt(dvui.enums.Button, button.button + 1) orelse return,
            .release,
        ),
        .motion => |motion| _ = try window.addEventMouseMotion(.{
            .pt = .{
                .x = @floatCast(motion.x),
                .y = @floatCast(motion.y),
            },
        }),
        .scroll => |scroll| switch (scroll.direction) {
            .up, .down => {
                const ticks: f32 = @floatCast(scroll.dy);
                _ = try window.addEventMouseWheel(
                    ticks * dvui.scroll_speed,
                    .vertical,
                    dvui.Window.mouseTypeGLFW(window.mouseWheelBatch(.vertical, ticks)),
                );
            },
            .left, .right => {
                const ticks: f32 = @floatCast(scroll.dx);
                _ = try window.addEventMouseWheel(
                    ticks * dvui.scroll_speed,
                    .horizontal,
                    dvui.Window.mouseTypeGLFW(window.mouseWheelBatch(.horizontal, ticks)),
                );
            },
            .smooth => {
                if (scroll.dx != 0)
                    _ = try window.addEventMouseWheel(@floatCast(scroll.dx), .horizontal, null);
                if (scroll.dy != 0)
                    _ = try window.addEventMouseWheel(@floatCast(scroll.dy), .vertical, null);
            },
        },
        .data_offer => |offer| {
            var type_index: ?u32 = null;

            // accept text/plain, fallback to first text/*
            for (0..self.view.getNumClipboardTypes(.general)) |i| {
                const mime = self.view.getClipboardType(.general, @intCast(i));

                if (std.mem.startsWith(u8, mime, "text/plain")) {
                    type_index = @intCast(i);
                    break;
                }

                if (std.mem.startsWith(u8, mime, "text/"))
                    type_index = @intCast(i);
            }

            if (type_index) |i|
                try self.view.acceptOffer(&offer, i, .copy, .{ .x = 0, .y = 0 }, .{ .width = 0, .height = 0 });
        },
        .data => |data| {
            if (window.textInputRequested() != null) {
                if (self.view.getClipboard(u8, .general, data.type_index)) |content|
                    // simulate pasting
                    _ = try window.addEventText(.{ .text = content });
            }
        },
        else => {},
    }
}

fn puglKeyToDvui(key: u32, state: pugl.event.Mods, e_type: pugl.event.Type) dvui.Event.Key {
    return .{
        .code = if (std.enums.fromInt(pugl.Keycode, key)) |code|
            switch (code) {
                .none => .unknown,
                .print_screen => .print,
                .shift_l => .left_shift,
                .shift_r => .right_shift,
                .ctrl_l => .left_control,
                .ctrl_r => .right_control,
                .alt_l => .left_alt,
                .alt_r => .right_alt,
                .super_l => .left_command,
                .super_r => .right_command,
                .keypad_0 => .kp_0,
                .keypad_1 => .kp_1,
                .keypad_2 => .kp_2,
                .keypad_3 => .kp_3,
                .keypad_4 => .kp_4,
                .keypad_5 => .kp_5,
                .keypad_6 => .kp_6,
                .keypad_7 => .kp_7,
                .keypad_8 => .kp_8,
                .keypad_9 => .kp_9,
                .keypad_enter => .kp_enter,
                .keypad_page_up => .page_up,
                .keypad_page_down => .page_down,
                .keypad_end => .end,
                .keypad_home => .home,
                .keypad_left => .left,
                .keypad_up => .up,
                .keypad_right => .right,
                .keypad_down => .down,
                .keypad_insert => .insert,
                .keypad_delete => .delete,
                .keypad_equal => .kp_equal,
                .keypad_multiply => .kp_multiply,
                .keypad_add => .kp_add,
                .keypad_separator => .kp_decimal,
                .keypad_subtract => .kp_subtract,
                .keypad_decimal => .kp_decimal,
                .keypad_divide => .kp_divide,

                .keypad_clear => .unknown,
                inline else => |c| @field(dvui.enums.Key, @tagName(c)),
            }
        else switch (key) {
            // 0-9
            48...57 => |n| @fromBackingInt(@intCast(@backingInt(dvui.enums.Key.zero) + n - 48)),
            // a-z
            97...122 => |n| @fromBackingInt(@intCast(@backingInt(dvui.enums.Key.a) + n - 97)),
            else => .unknown,
        },
        .action = switch (e_type) {
            .key_press => .down,
            .key_release => .up,
            else => unreachable,
        },
        .mod = blk: {
            var mod = dvui.enums.Mod.none;
            if (state.shift)
                mod.combine(.lshift);
            if (state.ctrl)
                mod.combine(.lcontrol);
            if (state.alt)
                mod.combine(.lalt);
            if (state.super)
                mod.combine(.lcommand);
            break :blk mod;
        },
    };
}

fn getProcAddress(name: [*:0]const u8) ?*const anyopaque {
    return OpenGlBackend.getProcAddress(std.mem.span(name));
}

const AppState = struct {
    backend: PuglBackend,
    window: dvui.Window,
    run: bool = true,
    end_us: ?u32 = 0,
    wait_us: u32 = 0,
};

pub fn main(main_init: std.process.Init) !void {
    var state: AppState = .{
        .backend = undefined,
        .window = undefined,
    };

    dvui.App.main_init = main_init;

    const app = dvui.App.get() orelse return error.DvuiAppNotDefined;
    const config = app.config.get();

    const gpa = config.gpa orelse main_init.gpa;
    const io = config.io orelse main_init.io;

    const world = try pugl.World.init(.program, .{});
    defer world.deinit();

    const view = try pugl.View.init(&world);
    defer view.deinit();

    try view.setSizeHint(.default, .{
        .width = @trunc(config.size.w),
        .height = @trunc(config.size.h),
    });
    if (config.min_size) |min_size|
        try view.setSizeHint(.minimum, .{
            .width = @trunc(min_size.w),
            .height = @trunc(min_size.h),
        });
    if (config.max_size) |max_size|
        try view.setSizeHint(.maximum, .{
            .width = @trunc(max_size.w),
            .height = @trunc(max_size.h),
        });

    try view.setStringHint(.window_title, config.title);
    try view.setBoolHint(.resizable, true);

    view.setHandle(&state);
    try view.setEventFunc(appOnEvent);

    state.backend = try init(.{ .gpa = gpa, .io = io, .view = view });
    defer state.backend.deinit();

    state.window = try dvui.Window.init(@src(), gpa, state.backend.backend(), config.window_init_options);
    defer state.window.deinit();

    try view.show(.raise);

    if (app.initFn) |initFn| {
        try state.window.begin(state.window.frame_time_ns);
        try initFn(&state.window);
        _ = try state.window.end(.{});
    }
    defer if (app.deinitFn) |deinitFn| deinitFn(&state.window);

    while (state.run) {
        state.backend.waitEventTimeout(state.wait_us);
        state.wait_us = state.window.waitTime(state.end_us);
    }
}

fn appOnEvent(view: *const pugl.View, event: pugl.event.Event) pugl.Error!void {
    const state: *AppState = @ptrCast(@alignCast(view.getHandle()));
    const app = dvui.App.get().?;
    try state.backend.handleEvent(event, &state.window);

    switch (event) {
        .expose => {
            const nstime = state.window.beginWait(true);
            state.window.begin(nstime) catch return error.BackendFailed;

            state.backend.renderer.clear();
            const res = app.frameFn() catch |e| blk: {
                dvui.log.err("{}", .{e});
                state.run = false;
                break :blk .close;
            };

            state.end_us = state.window.end(.{}) catch return error.BackendFailed;
            if (res != .ok) state.run = false;
        },
        .update => if (state.end_us != null) try view.obscure(),
        .close => state.run = false,
        .configure, .realize, .unrealize => {},
        else => try view.obscure(),
    }
}
