const std = @import("std");
const gui = @import("gui.zig");
const c = @import("c.zig").c;

const SDLBackend = @This();

window: *c.SDL_Window,
renderer: *c.SDL_Renderer,
cursor_last: gui.CursorKind = .arrow,
cursor_backing: [@typeInfo(gui.CursorKind).Enum.fields.len]*c.SDL_Cursor = undefined,

pub fn init(width: u32, height: u32) !SDLBackend {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
        std.debug.print("Couldn't initialize SDL: {s}\n", .{c.SDL_GetError()});
        return error.BackendError;
    }

    var window = c.SDL_CreateWindow("Gui Test", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, @intCast(c_int, width), @intCast(c_int, height), c.SDL_WINDOW_ALLOW_HIGHDPI | c.SDL_WINDOW_RESIZABLE) orelse {
        std.debug.print("Failed to open window: {s}\n", .{c.SDL_GetError()});
        return error.BackendError;
    };

    _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "linear");

    var renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED) // | c.SDL_RENDERER_PRESENTVSYNC)
    orelse {
        std.debug.print("Failed to create renderer: {s}\n", .{c.SDL_GetError()});
        return error.BackendError;
    };

    _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND);

    var back = SDLBackend{ .window = window, .renderer = renderer };

    back.CreateCursors();

    return back;
}

pub fn waitEventTimeout(_: *SDLBackend, timeout_micros: u32) void {
    if (timeout_micros == std.math.maxInt(u32)) {
        // wait no timeout
        _ = c.SDL_WaitEvent(null);
    } else if (timeout_micros > 0) {
        // wait with a timeout
        const timeout = std.math.min((timeout_micros + 999) / 1000, std.math.maxInt(c_int));
        _ = c.SDL_WaitEventTimeout(null, @intCast(c_int, timeout));
    } else {
        // don't wait
    }
}

pub fn addAllEvents(self: *SDLBackend, win: *gui.Window) !bool {
    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event) != 0) {
        _ = try self.addEvent(win, event);
        switch (event.type) {
            c.SDL_KEYDOWN => {
                if (((event.key.keysym.mod & c.KMOD_CTRL) > 0) and event.key.keysym.sym == c.SDLK_q) {
                    return true;
                }
            },
            c.SDL_QUIT => {
                return true;
            },
            else => {},
        }
    }

    return false;
}

pub fn setCursor(self: *SDLBackend, cursor: gui.CursorKind) void {
    if (cursor != self.cursor_last) {
        self.cursor_last = cursor;
        c.SDL_SetCursor(self.cursor_backing[@enumToInt(cursor)]);
    }
}

pub fn deinit(self: *SDLBackend) void {
    for (self.cursor_backing) |cursor| {
        c.SDL_FreeCursor(cursor);
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

pub fn CreateCursors(self: *SDLBackend) void {
    self.cursor_backing[@enumToInt(gui.CursorKind.arrow)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_ARROW) orelse unreachable;
    self.cursor_backing[@enumToInt(gui.CursorKind.ibeam)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_IBEAM) orelse unreachable;
    self.cursor_backing[@enumToInt(gui.CursorKind.wait)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_WAIT) orelse unreachable;
    self.cursor_backing[@enumToInt(gui.CursorKind.crosshair)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_CROSSHAIR) orelse unreachable;
    self.cursor_backing[@enumToInt(gui.CursorKind.arrow_nw_se)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_SIZENWSE) orelse unreachable;
    self.cursor_backing[@enumToInt(gui.CursorKind.arrow_ne_sw)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_SIZENESW) orelse unreachable;
    self.cursor_backing[@enumToInt(gui.CursorKind.arrow_w_e)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_SIZEWE) orelse unreachable;
    self.cursor_backing[@enumToInt(gui.CursorKind.arrow_n_s)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_SIZENS) orelse unreachable;
    self.cursor_backing[@enumToInt(gui.CursorKind.arrow_all)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_SIZEALL) orelse unreachable;
    self.cursor_backing[@enumToInt(gui.CursorKind.bad)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_NO) orelse unreachable;
    self.cursor_backing[@enumToInt(gui.CursorKind.hand)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_HAND) orelse unreachable;
}

pub fn clear(self: *SDLBackend) void {
    _ = c.SDL_SetRenderDrawColor(self.renderer, 0, 0, 0, 255);
    _ = c.SDL_RenderClear(self.renderer);
}

pub fn guiBackend(self: *SDLBackend) gui.Backend {
    return gui.Backend.init(self, begin, end, pixelSize, windowSize, renderGeometry, textureCreate, textureDestroy);
}

pub fn begin(_: *SDLBackend, _: std.mem.Allocator) void {}

pub fn end(_: *SDLBackend) void {}

pub fn pixelSize(self: *SDLBackend) gui.Size {
    var w: i32 = undefined;
    var h: i32 = undefined;
    _ = c.SDL_GetRendererOutputSize(self.renderer, &w, &h);
    return gui.Size{ .w = @intToFloat(f32, w), .h = @intToFloat(f32, h) };
}

pub fn windowSize(self: *SDLBackend) gui.Size {
    var w: i32 = undefined;
    var h: i32 = undefined;
    _ = c.SDL_GetWindowSize(self.window, &w, &h);
    return gui.Size{ .w = @intToFloat(f32, w), .h = @intToFloat(f32, h) };
}

pub fn renderGeometry(self: *SDLBackend, texture: ?*anyopaque, vtx: []gui.Vertex, idx: []u32) void {
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
    const clip = c.SDL_Rect{ .x = @floatToInt(c_int, clipr.x), .y = @floatToInt(c_int, clipr.y), .w = std.math.max(0, @floatToInt(c_int, @ceil(clipr.w + clipr.x - @floor(clipr.x)))), .h = std.math.max(0, @floatToInt(c_int, @ceil(clipr.h + clipr.y - @floor(clipr.y)))) };

    _ = c.SDL_RenderSetClipRect(self.renderer, &clip);

    const tex = @ptrCast(?*c.SDL_Texture, texture);

    _ = c.SDL_RenderGeometryRaw(self.renderer, tex, @ptrCast(*f32, &vtx[0].pos), @sizeOf(gui.Vertex), @ptrCast(*c.SDL_Color, @alignCast(4, &vtx[0].col)), @sizeOf(gui.Vertex), @ptrCast(*f32, &vtx[0].uv), @sizeOf(gui.Vertex), @intCast(c_int, vtx.len), idx.ptr, @intCast(c_int, idx.len), @sizeOf(u32));
}

pub fn textureCreate(self: *SDLBackend, pixels: []u8, width: u32, height: u32) *anyopaque {
    var surface = c.SDL_CreateRGBSurfaceWithFormatFrom(pixels.ptr, @intCast(c_int, width), @intCast(c_int, height), 32, @intCast(c_int, 4 * width), c.SDL_PIXELFORMAT_ABGR8888);
    defer c.SDL_FreeSurface(surface);

    const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface) orelse unreachable;
    return texture;
}

pub fn textureDestroy(_: *SDLBackend, texture: *anyopaque) void {
    c.SDL_DestroyTexture(@ptrCast(*c.SDL_Texture, texture));
}

pub fn addEvent(_: *SDLBackend, win: *gui.Window, event: c.SDL_Event) !bool {
    switch (event.type) {
        c.SDL_KEYDOWN => {
            return try win.addEventKey(
                SDL_keysym_to_gui(event.key.keysym.sym),
                SDL_keymod_to_gui(event.key.keysym.mod),
                if (event.key.repeat > 0) .repeat else .down,
            );
        },
        c.SDL_TEXTINPUT => {
            return try win.addEventText(std.mem.sliceTo(&event.text.text, 0));
        },
        c.SDL_MOUSEMOTION => {
            return try win.addEventMouseMotion(@intToFloat(f32, event.motion.x), @intToFloat(f32, event.motion.y));
        },
        c.SDL_MOUSEBUTTONDOWN, c.SDL_MOUSEBUTTONUP => |updown| {
            var state: gui.MouseEvent.Kind = undefined;
            if (event.button.button == c.SDL_BUTTON_LEFT) {
                if (updown == c.SDL_MOUSEBUTTONDOWN) {
                    state = .leftdown;
                } else {
                    state = .leftup;
                }
            } else if (event.button.button == c.SDL_BUTTON_RIGHT) {
                if (updown == c.SDL_MOUSEBUTTONDOWN) {
                    state = .rightdown;
                } else {
                    state = .rightup;
                }
            }

            return try win.addEventMouseButton(state);
        },
        c.SDL_MOUSEWHEEL => {
            const ticks = @intToFloat(f32, event.wheel.y);
            return try win.addEventMouseWheel(ticks);
        },
        else => {
            //std.debug.print("unhandled SDL event type {}\n", .{event.type});
            return false;
        },
    }
}

pub fn SDL_keymod_to_gui(keymod: u16) gui.keys.Mod {
    if (keymod == c.KMOD_NONE) return gui.keys.Mod.none;

    var m: u16 = 0;
    if (keymod & c.KMOD_LSHIFT > 0) m |= @enumToInt(gui.keys.Mod.lshift);
    if (keymod & c.KMOD_RSHIFT > 0) m |= @enumToInt(gui.keys.Mod.rshift);
    if (keymod & c.KMOD_LCTRL > 0) m |= @enumToInt(gui.keys.Mod.lctrl);
    if (keymod & c.KMOD_RCTRL > 0) m |= @enumToInt(gui.keys.Mod.rctrl);
    if (keymod & c.KMOD_LALT > 0) m |= @enumToInt(gui.keys.Mod.lalt);
    if (keymod & c.KMOD_RALT > 0) m |= @enumToInt(gui.keys.Mod.ralt);
    if (keymod & c.KMOD_LGUI > 0) m |= @enumToInt(gui.keys.Mod.lgui);
    if (keymod & c.KMOD_RGUI > 0) m |= @enumToInt(gui.keys.Mod.rgui);

    return @intToEnum(gui.keys.Mod, m);
}

pub fn SDL_keysym_to_gui(keysym: i32) gui.keys.Key {
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

        c.SDLK_SPACE => .space,
        c.SDLK_BACKSPACE => .backspace,
        c.SDLK_UP => .up,
        c.SDLK_DOWN => .down,
        c.SDLK_LEFT => .left,
        c.SDLK_RIGHT => .right,
        c.SDLK_TAB => .tab,
        c.SDLK_ESCAPE => .escape,
        else => .unknown,
    };
}
