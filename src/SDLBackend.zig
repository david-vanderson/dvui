const std = @import("std");
const gui = @import("gui");
pub const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const SDLBackend = @This();

window: *c.SDL_Window,
renderer: *c.SDL_Renderer,
cursor_last: gui.Cursor = .arrow,
cursor_backing: [@typeInfo(gui.Cursor).Enum.fields.len]?*c.SDL_Cursor = [_]?*c.SDL_Cursor{null} ** @typeInfo(gui.Cursor).Enum.fields.len,
cursor_backing_tried: [@typeInfo(gui.Cursor).Enum.fields.len]bool = [_]bool{false} ** @typeInfo(gui.Cursor).Enum.fields.len,
arena: std.mem.Allocator = undefined,

pub const initOptions = struct {
    width: u32,
    height: u32,
    vsync: bool,
    title: [:0]const u8,
};

pub fn init(options: initOptions) !SDLBackend {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
        std.debug.print("Couldn't initialize SDL: {s}\n", .{c.SDL_GetError()});
        return error.BackendError;
    }

    var window = c.SDL_CreateWindow(options.title, c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, @as(c_int, @intCast(options.width)), @as(c_int, @intCast(options.height)), c.SDL_WINDOW_ALLOW_HIGHDPI | c.SDL_WINDOW_RESIZABLE) orelse {
        std.debug.print("Failed to open window: {s}\n", .{c.SDL_GetError()});
        return error.BackendError;
    };

    _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "linear");

    var renderer = c.SDL_CreateRenderer(window, -1, if (options.vsync) c.SDL_RENDERER_PRESENTVSYNC else 0) orelse {
        std.debug.print("Failed to create renderer: {s}\n", .{c.SDL_GetError()});
        return error.BackendError;
    };

    _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND);

    var back = SDLBackend{ .window = window, .renderer = renderer };

    return back;
}

pub fn waitEventTimeout(_: *SDLBackend, timeout_micros: u32) void {
    if (timeout_micros == std.math.maxInt(u32)) {
        // wait no timeout
        _ = c.SDL_WaitEvent(null);
    } else if (timeout_micros > 0) {
        // wait with a timeout
        const timeout = @min((timeout_micros + 999) / 1000, std.math.maxInt(c_int));
        _ = c.SDL_WaitEventTimeout(null, @as(c_int, @intCast(timeout)));
    } else {
        // don't wait
    }
}

pub fn refresh() void {
    var ue = std.mem.zeroes(c.SDL_Event);
    ue.type = c.SDL_USEREVENT;
    _ = c.SDL_PushEvent(&ue);
}

pub fn addAllEvents(self: *SDLBackend, win: *gui.Window) !bool {
    //const flags = c.SDL_GetWindowFlags(self.window);
    //if (flags & c.SDL_WINDOW_MOUSE_FOCUS == 0 and flags & c.SDL_WINDOW_INPUT_FOCUS == 0) {
    //std.debug.print("bailing\n", .{});
    //}
    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event) != 0) {
        _ = try self.addEvent(win, event);
        switch (event.type) {
            c.SDL_QUIT => {
                return true;
            },
            else => {},
        }
    }

    return false;
}

pub fn setCursor(self: *SDLBackend, cursor: gui.Cursor) void {
    if (cursor != self.cursor_last) {
        self.cursor_last = cursor;

        const enum_int = @intFromEnum(cursor);
        const tried = self.cursor_backing_tried[enum_int];
        if (!tried) {
            self.cursor_backing_tried[enum_int] = true;
            self.cursor_backing[enum_int] = switch (cursor) {
                .arrow => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_ARROW),
                .ibeam => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_IBEAM),
                .wait => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_WAIT),
                .wait_arrow => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_WAITARROW),
                .crosshair => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_CROSSHAIR),
                .arrow_nw_se => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_SIZENWSE),
                .arrow_ne_sw => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_SIZENESW),
                .arrow_w_e => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_SIZEWE),
                .arrow_n_s => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_SIZENS),
                .arrow_all => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_SIZEALL),
                .bad => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_NO),
                .hand => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_HAND),
            };
        }

        if (self.cursor_backing[enum_int]) |cur| {
            c.SDL_SetCursor(cur);
        } else {
            std.log.warn("SDL_CreateSystemCursor \"{s}\" failed\n", .{@tagName(cursor)});
        }
    }
}

pub fn deinit(self: *SDLBackend) void {
    for (self.cursor_backing) |cursor| {
        if (cursor) |cur| {
            c.SDL_FreeCursor(cur);
        }
    }
    c.SDL_DestroyRenderer(self.renderer);
    c.SDL_DestroyWindow(self.window);
    c.SDL_Quit();
}

pub fn renderPresent(self: *SDLBackend) void {
    c.SDL_RenderPresent(self.renderer);
}

pub fn hasEvent(_: *SDLBackend) bool {
    return c.SDL_PollEvent(null) == 1;
}

pub fn clear(self: *SDLBackend) void {
    _ = c.SDL_SetRenderDrawColor(self.renderer, 0, 0, 0, 255);
    _ = c.SDL_RenderClear(self.renderer);
}

pub fn guiBackend(self: *SDLBackend) gui.Backend {
    return gui.Backend.init(self, begin, end, pixelSize, windowSize, renderGeometry, textureCreate, textureDestroy, clipboardText, clipboardTextSet, free);
}

pub fn clipboardText(self: *SDLBackend) []u8 {
    _ = self;
    return std.mem.sliceTo(c.SDL_GetClipboardText(), 0);
}

pub fn clipboardTextSet(self: *SDLBackend, text: []u8) !void {
    var cstr = try self.arena.alloc(u8, text.len + 1);
    @memcpy(cstr[0..text.len], text);
    cstr[cstr.len - 1] = 0;
    _ = c.SDL_SetClipboardText(cstr.ptr);
}

pub fn free(self: *SDLBackend, p: *anyopaque) void {
    _ = self;
    c.SDL_free(p);
}

pub fn begin(self: *SDLBackend, arena: std.mem.Allocator) void {
    self.arena = arena;
}

pub fn end(_: *SDLBackend) void {}

pub fn pixelSize(self: *SDLBackend) gui.Size {
    var w: i32 = undefined;
    var h: i32 = undefined;
    _ = c.SDL_GetRendererOutputSize(self.renderer, &w, &h);
    return gui.Size{ .w = @as(f32, @floatFromInt(w)), .h = @as(f32, @floatFromInt(h)) };
}

pub fn windowSize(self: *SDLBackend) gui.Size {
    var w: i32 = undefined;
    var h: i32 = undefined;
    _ = c.SDL_GetWindowSize(self.window, &w, &h);
    return gui.Size{ .w = @as(f32, @floatFromInt(w)), .h = @as(f32, @floatFromInt(h)) };
}

pub fn renderGeometry(self: *SDLBackend, texture: ?*anyopaque, vtx: []const gui.Vertex, idx: []const u32) void {
    const clipr = gui.windowRectPixels().intersect(gui.clipGet());
    if (clipr.empty()) {
        return;
    }

    //std.debug.print("renderGeometry:\n", .{});
    //for (vtx) |v, i| {
    //  std.debug.print("  {d} vertex {}\n", .{i, v});
    //}
    //for (idx) |id, i| {
    //  std.debug.print("  {d} index {d}\n", .{i, id});
    //}

    // figure out how much we are losing by truncating x and y, need to add that back to w and h
    const clip = c.SDL_Rect{ .x = @as(c_int, @intFromFloat(clipr.x)), .y = @as(c_int, @intFromFloat(clipr.y)), .w = @max(0, @as(c_int, @intFromFloat(@ceil(clipr.w + clipr.x - @floor(clipr.x))))), .h = @max(0, @as(c_int, @intFromFloat(@ceil(clipr.h + clipr.y - @floor(clipr.y))))) };

    //std.debug.print("SDL clip {} -> SDL_Rect{{ .x = {d}, .y = {d}, .w = {d}, .h = {d} }}\n", .{ clipr, clip.x, clip.y, clip.w, clip.h });
    _ = c.SDL_RenderSetClipRect(self.renderer, &clip);

    const tex = @as(?*c.SDL_Texture, @ptrCast(texture));

    _ = c.SDL_RenderGeometryRaw(self.renderer, tex, @as(*const f32, @ptrCast(&vtx[0].pos)), @sizeOf(gui.Vertex), @as(*const c.SDL_Color, @ptrCast(@alignCast(&vtx[0].col))), @sizeOf(gui.Vertex), @as(*const f32, @ptrCast(&vtx[0].uv)), @sizeOf(gui.Vertex), @as(c_int, @intCast(vtx.len)), idx.ptr, @as(c_int, @intCast(idx.len)), @sizeOf(u32));
}

pub fn textureCreate(self: *SDLBackend, pixels: []u8, width: u32, height: u32) *anyopaque {
    var surface = c.SDL_CreateRGBSurfaceWithFormatFrom(pixels.ptr, @as(c_int, @intCast(width)), @as(c_int, @intCast(height)), 32, @as(c_int, @intCast(4 * width)), c.SDL_PIXELFORMAT_ABGR8888);
    defer c.SDL_FreeSurface(surface);

    const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface) orelse unreachable;
    return texture;
}

pub fn textureDestroy(_: *SDLBackend, texture: *anyopaque) void {
    c.SDL_DestroyTexture(@as(*c.SDL_Texture, @ptrCast(texture)));
}

pub fn addEvent(_: *SDLBackend, win: *gui.Window, event: c.SDL_Event) !bool {
    switch (event.type) {
        c.SDL_KEYDOWN => {
            return try win.addEventKey(.{
                .code = SDL_keysym_to_gui(event.key.keysym.sym),
                .action = if (event.key.repeat > 0) .repeat else .down,
                .mod = SDL_keymod_to_gui(event.key.keysym.mod),
            });
        },
        c.SDL_TEXTINPUT => {
            return try win.addEventText(std.mem.sliceTo(&event.text.text, 0));
        },
        c.SDL_MOUSEMOTION => {
            return try win.addEventMouseMotion(@as(f32, @floatFromInt(event.motion.x)), @as(f32, @floatFromInt(event.motion.y)));
        },
        c.SDL_MOUSEBUTTONDOWN => {
            return try win.addEventMouseButton(.{ .press = SDL_mouse_button_to_gui(event.button.button) });
        },
        c.SDL_MOUSEBUTTONUP => {
            return try win.addEventMouseButton(.{ .release = SDL_mouse_button_to_gui(event.button.button) });
        },
        c.SDL_MOUSEWHEEL => {
            const ticks = @as(f32, @floatFromInt(event.wheel.y));
            return try win.addEventMouseWheel(ticks);
        },
        else => {
            //std.debug.print("unhandled SDL event type {}\n", .{event.type});
            return false;
        },
    }
}

pub fn SDL_mouse_button_to_gui(button: u8) gui.enums.Button {
    return switch (button) {
        c.SDL_BUTTON_LEFT => .left,
        c.SDL_BUTTON_MIDDLE => .middle,
        c.SDL_BUTTON_RIGHT => .right,
        c.SDL_BUTTON_X1 => .four,
        c.SDL_BUTTON_X2 => .five,
        else => blk: {
            std.debug.print("SDL_mouse_button_to_gui unknown button {d}\n", .{button});
            break :blk .six;
        },
    };
}

pub fn SDL_keymod_to_gui(keymod: u16) gui.enums.Mod {
    if (keymod == c.KMOD_NONE) return gui.enums.Mod.none;

    var m: u16 = 0;
    if (keymod & c.KMOD_LSHIFT > 0) m |= @intFromEnum(gui.enums.Mod.lshift);
    if (keymod & c.KMOD_RSHIFT > 0) m |= @intFromEnum(gui.enums.Mod.rshift);
    if (keymod & c.KMOD_LCTRL > 0) m |= @intFromEnum(gui.enums.Mod.lctrl);
    if (keymod & c.KMOD_RCTRL > 0) m |= @intFromEnum(gui.enums.Mod.rctrl);
    if (keymod & c.KMOD_LALT > 0) m |= @intFromEnum(gui.enums.Mod.lalt);
    if (keymod & c.KMOD_RALT > 0) m |= @intFromEnum(gui.enums.Mod.ralt);
    if (keymod & c.KMOD_LGUI > 0) m |= @intFromEnum(gui.enums.Mod.lgui);
    if (keymod & c.KMOD_RGUI > 0) m |= @intFromEnum(gui.enums.Mod.rgui);

    return @as(gui.enums.Mod, @enumFromInt(m));
}

pub fn SDL_keysym_to_gui(keysym: i32) gui.enums.Key {
    return switch (keysym) {
        c.SDLK_a => .a,
        c.SDLK_b => .b,
        c.SDLK_c => .c,
        c.SDLK_d => .d,
        c.SDLK_e => .e,
        c.SDLK_f => .f,
        c.SDLK_g => .g,
        c.SDLK_h => .h,
        c.SDLK_i => .i,
        c.SDLK_j => .j,
        c.SDLK_k => .k,
        c.SDLK_l => .l,
        c.SDLK_m => .m,
        c.SDLK_n => .n,
        c.SDLK_o => .o,
        c.SDLK_p => .p,
        c.SDLK_q => .q,
        c.SDLK_r => .r,
        c.SDLK_s => .s,
        c.SDLK_t => .t,
        c.SDLK_u => .u,
        c.SDLK_v => .v,
        c.SDLK_w => .w,
        c.SDLK_x => .x,
        c.SDLK_y => .y,
        c.SDLK_z => .z,

        c.SDLK_0 => .zero,
        c.SDLK_1 => .one,
        c.SDLK_2 => .two,
        c.SDLK_3 => .three,
        c.SDLK_4 => .four,
        c.SDLK_5 => .five,
        c.SDLK_6 => .six,
        c.SDLK_7 => .seven,
        c.SDLK_8 => .eight,
        c.SDLK_9 => .nine,

        c.SDLK_F1 => .f1,
        c.SDLK_F2 => .f2,
        c.SDLK_F3 => .f3,
        c.SDLK_F4 => .f4,
        c.SDLK_F5 => .f5,
        c.SDLK_F6 => .f6,
        c.SDLK_F7 => .f7,
        c.SDLK_F8 => .f8,
        c.SDLK_F9 => .f9,
        c.SDLK_F10 => .f10,
        c.SDLK_F11 => .f11,
        c.SDLK_F12 => .f12,

        c.SDLK_KP_DIVIDE => .kp_divide,
        c.SDLK_KP_MULTIPLY => .kp_multiply,
        c.SDLK_KP_MINUS => .kp_subtract,
        c.SDLK_KP_PLUS => .kp_add,
        c.SDLK_KP_ENTER => .kp_enter,
        c.SDLK_KP_0 => .kp_0,
        c.SDLK_KP_1 => .kp_1,
        c.SDLK_KP_2 => .kp_2,
        c.SDLK_KP_3 => .kp_3,
        c.SDLK_KP_4 => .kp_4,
        c.SDLK_KP_5 => .kp_5,
        c.SDLK_KP_6 => .kp_6,
        c.SDLK_KP_7 => .kp_7,
        c.SDLK_KP_8 => .kp_8,
        c.SDLK_KP_9 => .kp_9,
        c.SDLK_KP_PERIOD => .kp_decimal,

        c.SDLK_RETURN => .enter,
        c.SDLK_ESCAPE => .escape,
        c.SDLK_TAB => .tab,
        c.SDLK_LSHIFT => .left_shift,
        c.SDLK_RSHIFT => .right_shift,
        c.SDLK_LCTRL => .left_control,
        c.SDLK_RCTRL => .right_control,
        c.SDLK_LALT => .left_alt,
        c.SDLK_RALT => .right_alt,
        c.SDLK_LGUI => .left_super,
        c.SDLK_RGUI => .right_super,
        c.SDLK_MENU => .menu,
        c.SDLK_NUMLOCKCLEAR => .num_lock,
        c.SDLK_CAPSLOCK => .caps_lock,
        c.SDLK_PRINTSCREEN => .print,
        c.SDLK_SCROLLLOCK => .scroll_lock,
        c.SDLK_PAUSE => .pause,
        c.SDLK_DELETE => .delete,
        c.SDLK_HOME => .home,
        c.SDLK_END => .end,
        c.SDLK_PAGEUP => .page_up,
        c.SDLK_PAGEDOWN => .page_down,
        c.SDLK_INSERT => .insert,
        c.SDLK_LEFT => .left,
        c.SDLK_RIGHT => .right,
        c.SDLK_UP => .up,
        c.SDLK_DOWN => .down,
        c.SDLK_BACKSPACE => .backspace,
        c.SDLK_SPACE => .space,
        c.SDLK_MINUS => .minus,
        c.SDLK_EQUALS => .equal,
        c.SDLK_LEFTBRACKET => .left_bracket,
        c.SDLK_RIGHTBRACKET => .right_bracket,
        c.SDLK_BACKSLASH => .backslash,
        c.SDLK_SEMICOLON => .semicolon,
        c.SDLK_QUOTE => .apostrophe,
        c.SDLK_COMMA => .comma,
        c.SDLK_PERIOD => .period,
        c.SDLK_SLASH => .slash,
        c.SDLK_BACKQUOTE => .grave,

        else => blk: {
            std.debug.print("SDL_keysym_to_gui unknown keysym {d}\n", .{keysym});
            break :blk .unknown;
        },
    };
}
