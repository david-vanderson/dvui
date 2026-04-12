const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const wio = @import("wio");

pub const kind: dvui.enums.Backend = .wio;

window: wio.Window,
size_natural: dvui.Size.Natural,
size_physical: dvui.Size.Physical,
arena: std.mem.Allocator = undefined, // assigned in begin()
mod: dvui.enums.Mod = .none,
touch: [10]dvui.Point = @splat(.{ .x = std.math.inf(f32), .y = std.math.inf(f32) }),

pub fn backend(self: *@This(), renderer: *dvui.render_backend) dvui.Backend {
    return .init(self, renderer);
}

pub const InitOptions = struct {
    window: wio.Window,
    /// Will be corrected by `addEvent()`, but should be set manually if events were already processed.
    size: wio.Size = .{ .width = 640, .height = 480 },
    /// Will be corrected by `addEvent()`, but should be set manually if events were already processed.
    framebuffer: wio.Size = .{ .width = 640, .height = 480 },
};

pub fn init(options: InitOptions) !@This() {
    return .{
        .window = options.window,
        .size_natural = .{ .w = @floatFromInt(options.size.width), .h = @floatFromInt(options.size.height) },
        .size_physical = .{ .w = @floatFromInt(options.framebuffer.width), .h = @floatFromInt(options.framebuffer.height) },
    };
}

pub fn deinit(_: *@This()) void {}

pub fn nanoTime(_: *@This()) i128 {
    return std.time.nanoTimestamp();
}

pub fn sleep(_: *@This(), ns: u64) void {
    std.Thread.sleep(ns);
}

pub fn begin(self: *@This(), arena: std.mem.Allocator) !void {
    self.arena = arena;
}

pub fn end(_: *@This()) !void {}

pub fn pixelSize(self: *@This()) dvui.Size.Physical {
    return self.size_physical;
}

pub fn windowSize(self: *@This()) dvui.Size.Natural {
    return self.size_natural;
}

pub fn contentScale(_: *@This()) f32 {
    return 1;
}

pub fn clipboardText(self: *@This()) ![]const u8 {
    return self.window.getClipboardText(self.arena) orelse "";
}

pub fn clipboardTextSet(self: *@This(), text: []const u8) !void {
    self.window.setClipboardText(text);
}

pub fn openURL(_: *@This(), url: []const u8, _: bool) !void {
    _ = url;
}

pub fn preferredColorScheme(_: *@This()) ?dvui.enums.ColorScheme {
    return null;
}

pub fn refresh(_: *@This()) void {
    wio.cancelWait();
}

pub fn native(self: *@This(), _: *dvui.Window) dvui.Window.Native {
    return switch (builtin.os.tag) {
        .windows => .{ .hwnd = self.window.backend.window },
        .macos => .{ .cocoa_window = self.window.backend.window },
        else => {},
    };
}

pub fn waitEventTimeout(_: *@This(), timeout_us: u32) void {
    if (timeout_us == std.math.maxInt(u32)) {
        wio.wait(.{});
    } else {
        wio.wait(.{ .timeout_ns = @as(u64, timeout_us) * std.time.ns_per_us });
    }
}

pub fn setTextInputRect(self: *@This(), maybe_rect: ?dvui.Rect.Natural) void {
    if (maybe_rect) |rect| {
        // FIXME: not actually the cursor position
        self.window.enableTextInput(.{ .cursor = .{ .x = std.math.lossyCast(u16, rect.x), .y = std.math.lossyCast(u16, rect.y) } });
    } else {
        self.window.disableTextInput();
    }
}

pub fn setCursor(self: *@This(), cursor: dvui.enums.Cursor) void {
    if (cursor == .hidden) {
        self.window.setCursorMode(.hidden);
        return;
    }

    self.window.setCursorMode(.normal);
    self.window.setCursor(switch (cursor) {
        .arrow => .arrow,
        .ibeam => .text,
        .wait => .busy,
        .wait_arrow => .arrow_busy,
        .crosshair => .crosshair,
        .arrow_nw_se => .size_nwse,
        .arrow_ne_sw => .size_nesw,
        .arrow_w_e => .size_ew,
        .arrow_n_s => .size_ns,
        .arrow_all => .move,
        .bad => .forbidden,
        .hand => .hand,
        .hidden => unreachable,
    });
}

pub fn addEvent(self: *@This(), win: *dvui.Window, event: wio.Event) !bool {
    switch (event) {
        .close => {
            try win.addEventWindow(.{ .action = .close });
            return false;
        },
        .focused => {
            const modifiers = wio.getModifiers();
            if (modifiers.shift) self.mod.combine(.lshift);
            if (modifiers.control) self.mod.combine(.lcontrol);
            if (modifiers.alt) self.mod.combine(.lalt);
            return false;
        },
        .unfocused => {
            self.mod = .none;
            return false;
        },
        .size_logical => |size| {
            self.size_natural = .{ .w = @floatFromInt(size.width), .h = @floatFromInt(size.height) };
            return false;
        },
        .size_physical => |size| {
            self.size_physical = .{ .w = @floatFromInt(size.width), .h = @floatFromInt(size.height) };
            return false;
        },
        .char => |char| {
            var utf8: [4]u8 = undefined;
            const len = try std.unicode.utf8Encode(char, &utf8);
            return try win.addEventText(.{ .text = utf8[0..len] });
        },
        .button_press, .button_release => |button| {
            const maybe_mouse: ?dvui.enums.Button = switch (button) {
                .mouse_left => .left,
                .mouse_right => .right,
                .mouse_middle => .middle,
                .mouse_back => .four,
                .mouse_forward => .five,
                else => null,
            };

            if (maybe_mouse) |mouse| {
                return try win.addEventMouseButton(mouse, if (event == .button_press) .press else .release);
            }

            const mod: dvui.enums.Mod = switch (button) {
                // left and right are not distinguished to match wio.getModifiers()
                .left_control, .right_control => .lcontrol,
                .left_shift, .right_shift => .lshift,
                .left_alt, .right_alt => .lalt,
                .left_gui => .lcommand,
                .right_gui => .rcommand,
                else => .none,
            };
            if (mod != .none) {
                if (event == .button_press) {
                    self.mod.combine(mod);
                } else {
                    self.mod.unset(mod);
                }
            }

            return try win.addEventKey(.{
                .code = buttonToDvuiKey(button),
                .action = if (event == .button_press) .down else .up,
                .mod = self.mod,
            });
        },
        .button_repeat => |button| return try win.addEventKey(.{
            .code = buttonToDvuiKey(button),
            .action = .repeat,
            .mod = self.mod,
        }),
        .mouse => |mouse| {
            const x: f32 = @floatFromInt(mouse.x);
            const y: f32 = @floatFromInt(mouse.y);
            const scale = self.pixelSize().w / self.windowSize().w;
            return try win.addEventMouseMotion(.{ .pt = .{ .x = x * scale, .y = y * scale } });
        },
        .scroll_vertical => |ticks| return try win.addEventMouseWheel(-ticks * dvui.scroll_speed, .vertical),
        .scroll_horizontal => |ticks| return try win.addEventMouseWheel(-ticks * dvui.scroll_speed, .horizontal),
        .touch => |touch| {
            const button = touchIdToDvuiButton(touch.id) orelse return false;
            const xnorm = @as(f32, @floatFromInt(touch.x)) / self.size_natural.w;
            const ynorm = @as(f32, @floatFromInt(touch.y)) / self.size_natural.h;
            const old = &self.touch[touch.id];
            if (std.math.isInf(old.x)) {
                old.* = .{ .x = xnorm, .y = ynorm };
                return try win.addEventPointer(.{ .button = button, .action = .press, .xynorm = .{ .x = xnorm, .y = ynorm } });
            } else {
                const dxnorm = old.x - xnorm;
                const dynorm = old.y - ynorm;
                old.* = .{ .x = xnorm, .y = ynorm };
                return try win.addEventTouchMotion(button, xnorm, ynorm, dxnorm, dynorm);
            }
        },
        .touch_end => |touch| {
            const button = touchIdToDvuiButton(touch.id) orelse return false;
            const xynorm = self.touch[touch.id];
            self.touch[touch.id] = .{ .x = std.math.inf(f32), .y = std.math.inf(f32) };
            return try win.addEventPointer(.{ .button = button, .action = .release, .xynorm = xynorm });
        },
        else => return false,
    }
}

pub fn main() !void {
    const app = dvui.App.get() orelse return error.DvuiAppNotDefined;
    const config = app.config.get();

    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator = debug_allocator.allocator();

    try wio.init(allocator, .{});
    defer wio.deinit();

    var window = try wio.createWindow(.{
        .title = config.title,
        .size = .{ .width = @intFromFloat(config.size.w), .height = @intFromFloat(config.size.h) },
        .scale = 1,
        .opengl = if (dvui.render_backend.kind == .opengl) .{
            .major_version = 3,
            .minor_version = 2,
            .profile = .core,
        } else null,
    });
    defer window.destroy();

    var renderer = blk: switch (dvui.render_backend.kind) {
        .opengl => {
            window.makeContextCurrent();
            if (config.vsync) {
                window.swapInterval(1);
            }
            break :blk try dvui.render_backend.init(allocator, wio.glGetProcAddress, "150");
        },
        else => @compileError("unsupported renderer for backend"),
    };

    var dvui_wio = try @This().init(.{ .window = window });
    defer dvui_wio.deinit();

    var win = try dvui.Window.init(@src(), allocator, dvui_wio.backend(&renderer), config.window_init_options);
    defer win.deinit();

    if (app.initFn) |initFn| {
        try win.begin(win.frame_time_ns);
        try initFn(&win);
        _ = try win.end(.{});
    }
    defer if (app.deinitFn) |deinitFn| deinitFn();

    while (true) {
        wio.update();
        while (window.getEvent()) |event| {
            _ = try dvui_wio.addEvent(&win, event);
        }

        const time = win.beginWait(true);
        try win.begin(time);
        var res = try app.frameFn();
        for (dvui.events()) |*e| {
            if (!e.handled) {
                if (e.evt == .window and e.evt.window.action == .close) res = .close;
            }
        }
        const end_us = try win.end(.{});
        if (res != .ok) break;

        dvui_wio.setTextInputRect(win.textInputRequested());
        dvui_wio.setCursor(win.cursorRequested());

        window.swapBuffers();

        const wait_us = win.waitTime(end_us);
        dvui_wio.waitEventTimeout(wait_us);
    }
}

fn touchIdToDvuiButton(id: u8) ?dvui.enums.Button {
    return switch (id) {
        0 => .touch0,
        1 => .touch1,
        2 => .touch2,
        3 => .touch3,
        4 => .touch4,
        5 => .touch5,
        6 => .touch6,
        7 => .touch7,
        8 => .touch8,
        9 => .touch9,
        else => null,
    };
}

fn buttonToDvuiKey(button: wio.Button) dvui.enums.Key {
    return switch (button) {
        .mouse_left, .mouse_right, .mouse_middle, .mouse_back, .mouse_forward => unreachable,
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
        .@"1" => .one,
        .@"2" => .two,
        .@"3" => .three,
        .@"4" => .four,
        .@"5" => .five,
        .@"6" => .six,
        .@"7" => .seven,
        .@"8" => .eight,
        .@"9" => .nine,
        .@"0" => .zero,
        .enter => .enter,
        .escape => .escape,
        .backspace => .backspace,
        .tab => .tab,
        .space => .space,
        .minus => .minus,
        .equals => .equal,
        .left_bracket => .left_bracket,
        .right_bracket => .right_bracket,
        .backslash => .backslash,
        .semicolon => .semicolon,
        .apostrophe => .apostrophe,
        .grave => .grave,
        .comma => .comma,
        .dot => .period,
        .slash => .slash,
        .caps_lock => .caps_lock,
        .f1 => .f1,
        .f2 => .f2,
        .f3 => .f3,
        .f4 => .f4,
        .f5 => .f5,
        .f6 => .f6,
        .f7 => .f7,
        .f8 => .f8,
        .f9 => .f9,
        .f10 => .f10,
        .f11 => .f11,
        .f12 => .f12,
        .print_screen => .print,
        .scroll_lock => .scroll_lock,
        .pause => .pause,
        .insert => .insert,
        .home => .home,
        .page_up => .page_up,
        .delete => .delete,
        .end => .end,
        .page_down => .page_down,
        .right => .right,
        .left => .left,
        .down => .down,
        .up => .up,
        .num_lock => .num_lock,
        .kp_slash => .kp_divide,
        .kp_star => .kp_multiply,
        .kp_minus => .kp_subtract,
        .kp_plus => .kp_add,
        .kp_enter => .kp_enter,
        .kp_1 => .kp_1,
        .kp_2 => .kp_2,
        .kp_3 => .kp_3,
        .kp_4 => .kp_4,
        .kp_5 => .kp_5,
        .kp_6 => .kp_6,
        .kp_7 => .kp_7,
        .kp_8 => .kp_8,
        .kp_9 => .kp_9,
        .kp_0 => .kp_0,
        .kp_dot => .kp_decimal,
        .iso_backslash => .backslash,
        .application => .menu,
        .kp_equals => .kp_equal,
        .f13 => .f13,
        .f14 => .f14,
        .f15 => .f15,
        .f16 => .f16,
        .f17 => .f17,
        .f18 => .f18,
        .f19 => .f19,
        .f20 => .f20,
        .f21 => .f21,
        .f22 => .f22,
        .f23 => .f23,
        .f24 => .f24,
        .left_control => .left_control,
        .left_shift => .left_shift,
        .left_alt => .left_alt,
        .left_gui => .left_command,
        .right_control => .right_control,
        .right_shift => .right_shift,
        .right_alt => .right_alt,
        .right_gui => .right_command,
        .kp_comma, .international1, .international2, .international3, .international4, .international5, .lang1, .lang2 => .unknown,
    };
}
