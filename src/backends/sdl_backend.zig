const sdl3 = false;

const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");

pub const c = @cImport({
    @cInclude(if (sdl3) "SDL3/SDL.h" else "SDL2/SDL.h");
});

const SDLBackend = @This();
pub const Context = *SDLBackend;

window: *c.SDL_Window,
renderer: *c.SDL_Renderer,
we_own_window: bool = false,
touch_mouse_events: bool = false,
log_events: bool = false,
initial_scale: f32 = 1.0,
cursor_last: dvui.enums.Cursor = .arrow,
cursor_backing: [@typeInfo(dvui.enums.Cursor).Enum.fields.len]?*c.SDL_Cursor = [_]?*c.SDL_Cursor{null} ** @typeInfo(dvui.enums.Cursor).Enum.fields.len,
cursor_backing_tried: [@typeInfo(dvui.enums.Cursor).Enum.fields.len]bool = [_]bool{false} ** @typeInfo(dvui.enums.Cursor).Enum.fields.len,
arena: std.mem.Allocator = undefined,

pub const InitOptions = struct {
    /// The allocator used for temporary allocations used during init()
    allocator: std.mem.Allocator,
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

pub fn initWindow(options: InitOptions) !SDLBackend {
    _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "linear");

    // use the string version instead of the #define so we compile with SDL < 2.24
    _ = c.SDL_SetHint("SDL_HINT_WINDOWS_DPI_SCALING", "1");

    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
        dvui.log.err("SDL: Couldn't initialize SDL: {s}\n", .{c.SDL_GetError()});
        return error.BackendError;
    }

    var window: *c.SDL_Window = undefined;
    if (sdl3) {
        window = c.SDL_CreateWindow(options.title, @as(c_int, @intFromFloat(options.size.w)), @as(c_int, @intFromFloat(options.size.h)), c.SDL_WINDOW_HIGH_PIXEL_DENSITY | c.SDL_WINDOW_RESIZABLE) orelse {
            dvui.log.err("SDL: Failed to open window: {s}\n", .{c.SDL_GetError()});
            return error.BackendError;
        };
    } else {
        window = c.SDL_CreateWindow(options.title, c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, @as(c_int, @intFromFloat(options.size.w)), @as(c_int, @intFromFloat(options.size.h)), c.SDL_WINDOW_ALLOW_HIGHDPI | c.SDL_WINDOW_RESIZABLE) orelse {
            dvui.log.err("SDL: Failed to open window: {s}\n", .{c.SDL_GetError()});
            return error.BackendError;
        };
    }

    var renderer: *c.SDL_Renderer = undefined;
    if (sdl3) {
        renderer = c.SDL_CreateRenderer(window, null, if (options.vsync) c.SDL_RENDERER_PRESENTVSYNC else 0) orelse {
            dvui.log.err("SDL: Failed to create renderer: {s}\n", .{c.SDL_GetError()});
            return error.BackendError;
        };
    } else {
        renderer = c.SDL_CreateRenderer(window, -1, if (options.vsync) c.SDL_RENDERER_PRESENTVSYNC else 0) orelse {
            dvui.log.err("SDL: Failed to create renderer: {s}\n", .{c.SDL_GetError()});
            return error.BackendError;
        };
    }

    _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND);

    var back = init(window, renderer);
    back.we_own_window = true;

    if (sdl3) {
        back.initial_scale = c.SDL_GetDisplayContentScale(c.SDL_GetDisplayForWindow(window));
        dvui.log.info("SDL3 backend scale {d}\n", .{back.initial_scale});
    } else {
        const winSize = back.windowSize();
        const pxSize = back.pixelSize();
        const nat_scale = pxSize.w / winSize.w;
        if (nat_scale == 1.0) {
            var guess_from_dpi = true;

            // first try to inspect environment variables
            {
                const qt_auto_str: ?[]u8 = std.process.getEnvVarOwned(options.allocator, "QT_AUTO_SCREEN_SCALE_FACTOR") catch |err| switch (err) {
                    error.EnvironmentVariableNotFound => null,
                    else => return err,
                };
                defer if (qt_auto_str) |str| options.allocator.free(str);
                if (qt_auto_str != null and std.mem.eql(u8, qt_auto_str.?, "0")) {
                    dvui.log.info("QT_AUTO_SCREEN_SCALE_FACTOR is 0, disabling content scale guessing\n", .{});
                    guess_from_dpi = false;
                }
                const qt_str: ?[]u8 = std.process.getEnvVarOwned(options.allocator, "QT_SCALE_FACTOR") catch |err| switch (err) {
                    error.EnvironmentVariableNotFound => null,
                    else => return err,
                };
                defer if (qt_str) |str| options.allocator.free(str);
                const gdk_str: ?[]u8 = std.process.getEnvVarOwned(options.allocator, "GDK_SCALE") catch |err| switch (err) {
                    error.EnvironmentVariableNotFound => null,
                    else => return err,
                };
                defer if (gdk_str) |str| options.allocator.free(str);

                if (qt_str) |str| {
                    const qt_scale = std.fmt.parseFloat(f32, str) catch 1.0;
                    dvui.log.info("QT_SCALE_FACTOR is {d}, using that for initial content scale\n", .{qt_scale});
                    back.initial_scale = qt_scale;
                    guess_from_dpi = false;
                } else if (gdk_str) |str| {
                    const gdk_scale = std.fmt.parseFloat(f32, str) catch 1.0;
                    dvui.log.info("GDK_SCALE is {d}, using that for initial content scale\n", .{gdk_scale});
                    back.initial_scale = gdk_scale;
                    guess_from_dpi = false;
                }
            }

            if (guess_from_dpi) {
                var mdpi: ?f32 = null;

                // for X11, try to grab the output of xrdb -query
                //*customization:	-color
                //Xft.dpi:	96
                //Xft.antialias:	1
                if (mdpi == null and builtin.os.tag == .linux) {
                    var stdout = std.ArrayList(u8).init(options.allocator);
                    defer stdout.deinit();
                    var stderr = std.ArrayList(u8).init(options.allocator);
                    defer stderr.deinit();
                    var child = std.process.Child.init(&.{ "xrdb", "-get", "Xft.dpi" }, options.allocator);
                    child.stdout_behavior = .Pipe;
                    child.stderr_behavior = .Pipe;
                    try child.spawn();
                    var ok = true;
                    child.collectOutput(&stdout, &stderr, 100) catch {
                        ok = false;
                    };
                    _ = child.wait() catch {};
                    if (ok) {
                        const end_digits = std.mem.indexOfNone(u8, stdout.items, &.{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' }) orelse stdout.items.len;
                        const xrdb_dpi = std.fmt.parseInt(u32, stdout.items[0..end_digits], 10) catch null;
                        if (xrdb_dpi) |dpi| {
                            mdpi = @floatFromInt(dpi);
                        }

                        if (mdpi) |dpi| {
                            dvui.log.info("dpi {d} from xrdb -get Xft.dpi\n", .{dpi});
                        }
                    }
                }

                // This doesn't seem to be helping anybody and sometimes hurts,
                // so we'll try disabling it for now.
                //if (mdpi == null) {
                //    // see if we can guess correctly based on the dpi from SDL2
                //    const display_num = c.SDL_GetWindowDisplayIndex(window);
                //    var hdpi: f32 = undefined;
                //    var vdpi: f32 = undefined;
                //    _ = c.SDL_GetDisplayDPI(display_num, null, &hdpi, &vdpi);
                //    mdpi = @max(hdpi, vdpi);
                //    std.debug.print("SDLBackend dpi {d} from SDL_GetDisplayDPI\n", .{mdpi.?});
                //}

                if (mdpi) |dpi| {
                    if (dpi > 200) {
                        back.initial_scale = 4.0;
                    } else if (dpi > 100) {
                        back.initial_scale = 2.0;
                    }
                    dvui.log.info("SDL2 guessing initial backend scale {d}\n", .{back.initial_scale});
                }
            }

            if (back.initial_scale != 1.0) {
                _ = c.SDL_SetWindowSize(window, @as(c_int, @intFromFloat(back.initial_scale * options.size.w)), @as(c_int, @intFromFloat(back.initial_scale * options.size.h)));
            }
        }
    }

    if (options.icon) |bytes| {
        back.setIconFromFileContent(bytes);
    }

    if (options.min_size) |size| {
        _ = c.SDL_SetWindowMinimumSize(window, @as(c_int, @intFromFloat(back.initial_scale * size.w)), @as(c_int, @intFromFloat(back.initial_scale * size.h)));
    }

    if (options.max_size) |size| {
        _ = c.SDL_SetWindowMaximumSize(window, @as(c_int, @intFromFloat(back.initial_scale * size.w)), @as(c_int, @intFromFloat(back.initial_scale * size.h)));
    }

    return back;
}

pub fn init(window: *c.SDL_Window, renderer: *c.SDL_Renderer) SDLBackend {
    return SDLBackend{ .window = window, .renderer = renderer };
}

pub fn setIconFromFileContent(self: *SDLBackend, file_content: []const u8) void {
    var icon_w: c_int = undefined;
    var icon_h: c_int = undefined;
    var channels_in_file: c_int = undefined;
    const data = dvui.c.stbi_load_from_memory(file_content.ptr, @as(c_int, @intCast(file_content.len)), &icon_w, &icon_h, &channels_in_file, 4);
    if (data == null) {
        dvui.log.warn("when setting icon, stbi_load error: {s}\n", .{dvui.c.stbi_failure_reason()});
        return;
    }
    defer dvui.c.stbi_image_free(data);
    self.setIconFromABGR8888(data, icon_w, icon_h);
}

pub fn setIconFromABGR8888(self: *SDLBackend, data: [*]const u8, icon_w: c_int, icon_h: c_int) void {
    const surface = c.SDL_CreateRGBSurfaceWithFormatFrom(@ptrCast(@constCast(data)), icon_w, icon_h, 32, 4 * icon_w, c.SDL_PIXELFORMAT_ABGR8888);
    defer c.SDL_FreeSurface(surface);

    c.SDL_SetWindowIcon(self.window, surface);
}

pub fn waitEventTimeout(_: *SDLBackend, timeout_micros: u32) void {
    if (timeout_micros == std.math.maxInt(u32)) {
        // wait no timeout
        _ = c.SDL_WaitEvent(null);
    } else if (timeout_micros > 0) {
        // wait with a timeout
        const timeout = @min((timeout_micros + 999) / 1000, std.math.maxInt(c_int));
        _ = c.SDL_WaitEventTimeout(null, @as(c_int, @intCast(timeout)));

        // TODO: this call to SDL_PollEvent can be removed after resolution of
        // https://github.com/libsdl-org/SDL/issues/6539
        // maintaining this a little longer for people with older SDL versions
        _ = c.SDL_PollEvent(null);
    } else {
        // don't wait
    }
}

pub fn refresh(self: *SDLBackend) void {
    _ = self;
    var ue = std.mem.zeroes(c.SDL_Event);
    ue.type = c.SDL_USEREVENT;
    _ = c.SDL_PushEvent(&ue);
}

pub fn addAllEvents(self: *SDLBackend, win: *dvui.Window) !bool {
    //const flags = c.SDL_GetWindowFlags(self.window);
    //if (flags & c.SDL_WINDOW_MOUSE_FOCUS == 0 and flags & c.SDL_WINDOW_INPUT_FOCUS == 0) {
    //std.debug.print("bailing\n", .{});
    //}
    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event) != 0) {
        _ = try self.addEvent(win, event);
        switch (event.type) {
            if (sdl3) c.SDL_EVENT_QUIT else c.SDL_QUIT => {
                return true;
            },
            // revisit with sdl3
            //c.SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED => {
            //std.debug.print("sdl window scale changed event\n", .{});
            //},
            //c.SDL_EVENT_DISPLAY_CONTENT_SCALE_CHANGED => {
            //std.debug.print("sdl display scale changed event\n", .{});
            //},
            else => {},
        }
    }

    return false;
}

pub fn setCursor(self: *SDLBackend, cursor: dvui.enums.Cursor) void {
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
            if (sdl3) {
                _ = c.SDL_SetCursor(cur);
            } else {
                c.SDL_SetCursor(cur);
            }
        } else {
            dvui.log.err("SDL_CreateSystemCursor \"{s}\" failed\n", .{@tagName(cursor)});
        }
    }
}

pub fn deinit(self: *SDLBackend) void {
    for (self.cursor_backing) |cursor| {
        if (cursor) |cur| {
            if (sdl3) {
                c.SDL_DestroyCursor(cur);
            } else {
                c.SDL_FreeCursor(cur);
            }
        }
    }

    if (self.we_own_window) {
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }
}

pub fn renderPresent(self: *SDLBackend) void {
    if (sdl3) {
        _ = c.SDL_RenderPresent(self.renderer);
    } else {
        c.SDL_RenderPresent(self.renderer);
    }
}

pub fn hasEvent(_: *SDLBackend) bool {
    return c.SDL_PollEvent(null) == 1;
}

pub fn backend(self: *SDLBackend) dvui.Backend {
    return dvui.Backend.init(self, @This());
}

pub fn nanoTime(self: *SDLBackend) i128 {
    _ = self;
    return std.time.nanoTimestamp();
}

pub fn sleep(self: *SDLBackend, ns: u64) void {
    _ = self;
    std.time.sleep(ns);
}

pub fn clipboardText(self: *SDLBackend) ![]const u8 {
    const p = c.SDL_GetClipboardText();
    defer c.SDL_free(p);
    return try self.arena.dupe(u8, std.mem.sliceTo(p, 0));
}

pub fn clipboardTextSet(self: *SDLBackend, text: []const u8) !void {
    if (text.len == 0) return;

    var cstr = try self.arena.alloc(u8, text.len + 1);
    @memcpy(cstr[0..text.len], text);
    cstr[cstr.len - 1] = 0;
    _ = c.SDL_SetClipboardText(cstr.ptr);
}

pub fn openURL(self: *SDLBackend, url: []const u8) !void {
    var cstr = try self.arena.alloc(u8, url.len + 1);
    @memcpy(cstr[0..url.len], url);
    cstr[cstr.len - 1] = 0;
    _ = c.SDL_OpenURL(cstr.ptr);
}

pub fn begin(self: *SDLBackend, arena: std.mem.Allocator) void {
    self.arena = arena;
    const size = self.pixelSize();
    _ = c.SDL_RenderSetClipRect(self.renderer, &c.SDL_Rect{ .x = 0, .y = 0, .w = @intFromFloat(size.w), .h = @intFromFloat(size.h) });
}

pub fn end(_: *SDLBackend) void {}

pub fn pixelSize(self: *SDLBackend) dvui.Size {
    var w: i32 = undefined;
    var h: i32 = undefined;
    if (sdl3) {
        _ = c.SDL_GetCurrentRenderOutputSize(self.renderer, &w, &h);
    } else {
        _ = c.SDL_GetRendererOutputSize(self.renderer, &w, &h);
    }
    return dvui.Size{ .w = @as(f32, @floatFromInt(w)), .h = @as(f32, @floatFromInt(h)) };
}

pub fn windowSize(self: *SDLBackend) dvui.Size {
    var w: i32 = undefined;
    var h: i32 = undefined;
    _ = c.SDL_GetWindowSize(self.window, &w, &h);
    return dvui.Size{ .w = @as(f32, @floatFromInt(w)), .h = @as(f32, @floatFromInt(h)) };
}

pub fn contentScale(self: *SDLBackend) f32 {
    return self.initial_scale;
}

pub fn drawClippedTriangles(self: *SDLBackend, texture: ?*anyopaque, vtx: []const dvui.Vertex, idx: []const u16, clipr: dvui.Rect) void {
    //std.debug.print("drawClippedTriangles:\n", .{});
    //for (vtx) |v, i| {
    //  std.debug.print("  {d} vertex {}\n", .{i, v});
    //}
    //for (idx) |id, i| {
    //  std.debug.print("  {d} index {d}\n", .{i, id});
    //}

    var oldclip: c.SDL_Rect = undefined;
    if (sdl3) {
        _ = c.SDL_GetRenderClipRect(self.renderer, &oldclip);
    } else {
        _ = c.SDL_RenderGetClipRect(self.renderer, &oldclip);
    }

    // figure out how much we are losing by truncating x and y, need to add that back to w and h
    const clip = c.SDL_Rect{ .x = @as(c_int, @intFromFloat(clipr.x)), .y = @as(c_int, @intFromFloat(clipr.y)), .w = @max(0, @as(c_int, @intFromFloat(@ceil(clipr.w + clipr.x - @floor(clipr.x))))), .h = @max(0, @as(c_int, @intFromFloat(@ceil(clipr.h + clipr.y - @floor(clipr.y))))) };

    //std.debug.print("SDL clip {} -> SDL_Rect{{ .x = {d}, .y = {d}, .w = {d}, .h = {d} }}\n", .{ clipr, clip.x, clip.y, clip.w, clip.h });
    if (sdl3) {
        _ = c.SDL_SetRenderClipRect(self.renderer, &clip);
    } else {
        _ = c.SDL_RenderSetClipRect(self.renderer, &clip);
    }

    const tex = @as(?*c.SDL_Texture, @ptrCast(texture));

    _ = c.SDL_RenderGeometryRaw(self.renderer, tex, @as(*const f32, @ptrCast(&vtx[0].pos)), @sizeOf(dvui.Vertex), @as(*const c.SDL_Color, @ptrCast(@alignCast(&vtx[0].col))), @sizeOf(dvui.Vertex), @as(*const f32, @ptrCast(&vtx[0].uv)), @sizeOf(dvui.Vertex), @as(c_int, @intCast(vtx.len)), idx.ptr, @as(c_int, @intCast(idx.len)), @sizeOf(u16));

    if (sdl3) {
        _ = c.SDL_SetRenderClipRect(self.renderer, &oldclip);
    } else {
        _ = c.SDL_RenderSetClipRect(self.renderer, &oldclip);
    }
}

pub fn textureCreate(self: *SDLBackend, pixels: [*]u8, width: u32, height: u32) *anyopaque {
    // TODO: is SDL converting to premultiplied alpha internally?
    var surface: *c.SDL_Surface = undefined;
    if (sdl3) {
        surface = c.SDL_CreateSurfaceFrom(pixels, @as(c_int, @intCast(width)), @as(c_int, @intCast(height)), @as(c_int, @intCast(4 * width)), c.SDL_PIXELFORMAT_ABGR8888);
    } else {
        surface = c.SDL_CreateRGBSurfaceWithFormatFrom(pixels, @as(c_int, @intCast(width)), @as(c_int, @intCast(height)), 32, @as(c_int, @intCast(4 * width)), c.SDL_PIXELFORMAT_ABGR8888);
    }
    defer {
        if (sdl3) {
            c.SDL_DestroySurface(surface);
        } else {
            c.SDL_FreeSurface(surface);
        }
    }

    const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface) orelse unreachable;
    return texture;
}

pub fn textureDestroy(_: *SDLBackend, texture: *anyopaque) void {
    c.SDL_DestroyTexture(@as(*c.SDL_Texture, @ptrCast(texture)));
}

pub fn addEvent(self: *SDLBackend, win: *dvui.Window, event: c.SDL_Event) !bool {
    switch (event.type) {
        if (sdl3) c.SDL_EVENT_KEY_DOWN else c.SDL_KEYDOWN => {
            const code = SDL_keysym_to_dvui(event.key.keysym.sym);
            const mod = SDL_keymod_to_dvui(event.key.keysym.mod);
            if (self.log_events) {
                std.debug.print("sdl event KEYDOWN {d} {s} {b}\n", .{event.key.keysym.sym, @tagName(code), mod});
            }

            return try win.addEventKey(.{
                .code = code,
                .action = if (event.key.repeat > 0) .repeat else .down,
                .mod = mod,
            });
        },
        if (sdl3) c.SDL_EVENT_KEY_UP else c.SDL_KEYUP => {
            const code = SDL_keysym_to_dvui(event.key.keysym.sym);
            const mod = SDL_keymod_to_dvui(event.key.keysym.mod);
            if (self.log_events) {
                std.debug.print("sdl event KEYUP {d} {s} {b}\n", .{event.key.keysym.sym, @tagName(code), mod});
            }

            return try win.addEventKey(.{
                .code = code,
                .action = .up,
                .mod = mod,
            });
        },
        if (sdl3) c.SDL_EVENT_TEXT_INPUT else c.SDL_TEXTINPUT => {
            const txt = std.mem.sliceTo(&event.text.text, 0);
            if (self.log_events) {
                std.debug.print("sdl event TEXTINPUT {s}\n", .{txt});
            }

            return try win.addEventText(txt);
        },
        if (sdl3) c.SDL_EVENT_MOUSE_MOTION else c.SDL_MOUSEMOTION => {
            const touch = event.motion.which == c.SDL_TOUCH_MOUSEID;
            if (self.log_events) {
                var touch_str: []const u8 = " ";
                if (touch) touch_str = " touch ";
                if (touch and !self.touch_mouse_events) touch_str = " touch ignored ";
                std.debug.print("sdl event{s}MOUSEMOTION {d} {d}\n", .{ touch_str, event.motion.x, event.motion.y });
            }

            if (touch and !self.touch_mouse_events) {
                return false;
            }

            if (sdl3) {
                return try win.addEventMouseMotion(event.motion.x, event.motion.y);
            } else {
                return try win.addEventMouseMotion(@as(f32, @floatFromInt(event.motion.x)), @as(f32, @floatFromInt(event.motion.y)));
            }
        },
        if (sdl3) c.SDL_EVENT_MOUSE_BUTTON_DOWN else c.SDL_MOUSEBUTTONDOWN => {
            const touch = event.motion.which == c.SDL_TOUCH_MOUSEID;
            if (self.log_events) {
                var touch_str: []const u8 = " ";
                if (touch) touch_str = " touch ";
                if (touch and !self.touch_mouse_events) touch_str = " touch ignored ";
                std.debug.print("sdl event{s}MOUSEBUTTONDOWN {d}\n", .{ touch_str, event.button.button });
            }

            if (touch and !self.touch_mouse_events) {
                return false;
            }

            return try win.addEventMouseButton(SDL_mouse_button_to_dvui(event.button.button), .press);
        },
        if (sdl3) c.SDL_EVENT_MOUSE_BUTTON_UP else c.SDL_MOUSEBUTTONUP => {
            const touch = event.motion.which == c.SDL_TOUCH_MOUSEID;
            if (self.log_events) {
                var touch_str: []const u8 = " ";
                if (touch) touch_str = " touch ";
                if (touch and !self.touch_mouse_events) touch_str = " touch ignored ";
                std.debug.print("sdl event{s}MOUSEBUTTONUP {d}\n", .{ touch_str, event.button.button });
            }

            if (touch and !self.touch_mouse_events) {
                return false;
            }

            return try win.addEventMouseButton(SDL_mouse_button_to_dvui(event.button.button), .release);
        },
        if (sdl3) c.SDL_EVENT_MOUSE_WHEEL else c.SDL_MOUSEWHEEL => {
            if (self.log_events) {
                std.debug.print("sdl event MOUSEWHEEL {d} {d}\n", .{ event.wheel.y, event.wheel.which });
            }

            const ticks = if (sdl3) event.wheel.y else @as(f32, @floatFromInt(event.wheel.y));

            // TODO: some real solution to interpreting the mouse wheel across OSes
            const ticks_adj = switch (builtin.target.os.tag) {
                .linux => ticks * 20,
                .windows => ticks * 20,
                .macos => ticks * 10,
                else => ticks,
            };

            return try win.addEventMouseWheel(ticks_adj);
        },
        if (sdl3) c.SDL_FINGERDOWN else c.SDL_FINGERDOWN => {
            if (self.log_events) {
                std.debug.print("sdl event FINGERDOWN {d} {d} {d}\n", .{ event.tfinger.fingerId, event.tfinger.x, event.tfinger.y });
            }

            return try win.addEventPointer(.touch0, .press, .{ .x = event.tfinger.x, .y = event.tfinger.y });
        },
        if (sdl3) c.SDL_FINGERUP else c.SDL_FINGERUP => {
            if (self.log_events) {
                std.debug.print("sdl event FINGERUP {d} {d} {d}\n", .{ event.tfinger.fingerId, event.tfinger.x, event.tfinger.y });
            }

            return try win.addEventPointer(.touch0, .release, .{ .x = event.tfinger.x, .y = event.tfinger.y });
        },
        if (sdl3) c.SDL_FINGERMOTION else c.SDL_FINGERMOTION => {
            if (self.log_events) {
                std.debug.print("sdl event FINGERMOTION {d} {d} {d} {d} {d}\n", .{ event.tfinger.fingerId, event.tfinger.x, event.tfinger.y, event.tfinger.dx, event.tfinger.dy });
            }

            return try win.addEventTouchMotion(.touch0, event.tfinger.x, event.tfinger.y, event.tfinger.dx, event.tfinger.dy);
        },
        else => {
            if (self.log_events) {
                std.debug.print("unhandled SDL event type {}\n", .{event.type});
            }
            return false;
        },
    }
}

pub fn SDL_mouse_button_to_dvui(button: u8) dvui.enums.Button {
    return switch (button) {
        c.SDL_BUTTON_LEFT => .left,
        c.SDL_BUTTON_MIDDLE => .middle,
        c.SDL_BUTTON_RIGHT => .right,
        c.SDL_BUTTON_X1 => .four,
        c.SDL_BUTTON_X2 => .five,
        else => blk: {
            dvui.log.debug("SDL_mouse_button_to_dvui.unknown button {d}\n", .{button});
            break :blk .six;
        },
    };
}

pub fn SDL_keymod_to_dvui(keymod: u16) dvui.enums.Mod {
    if (keymod == if (sdl3) c.SDL_KMOD_NONE else c.KMOD_NONE) return dvui.enums.Mod.none;

    var m: u16 = 0;
    if (keymod & (if (sdl3) c.SDL_KMOD_LSHIFT else c.KMOD_LSHIFT) > 0) m |= @intFromEnum(dvui.enums.Mod.lshift);
    if (keymod & (if (sdl3) c.SDL_KMOD_RSHIFT else c.KMOD_RSHIFT) > 0) m |= @intFromEnum(dvui.enums.Mod.rshift);
    if (keymod & (if (sdl3) c.SDL_KMOD_LCTRL else c.KMOD_LCTRL) > 0) m |= @intFromEnum(dvui.enums.Mod.lcontrol);
    if (keymod & (if (sdl3) c.SDL_KMOD_RCTRL else c.KMOD_RCTRL) > 0) m |= @intFromEnum(dvui.enums.Mod.rcontrol);
    if (keymod & (if (sdl3) c.SDL_KMOD_LALT else c.KMOD_LALT) > 0) m |= @intFromEnum(dvui.enums.Mod.lalt);
    if (keymod & (if (sdl3) c.SDL_KMOD_RALT else c.KMOD_RALT) > 0) m |= @intFromEnum(dvui.enums.Mod.ralt);
    if (keymod & (if (sdl3) c.SDL_KMOD_LGUI else c.KMOD_LGUI) > 0) m |= @intFromEnum(dvui.enums.Mod.lcommand);
    if (keymod & (if (sdl3) c.SDL_KMOD_RGUI else c.KMOD_RGUI) > 0) m |= @intFromEnum(dvui.enums.Mod.rcommand);

    return @as(dvui.enums.Mod, @enumFromInt(m));
}

pub fn SDL_keysym_to_dvui(keysym: i32) dvui.enums.Key {
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
        c.SDLK_LGUI => .left_command,
        c.SDLK_RGUI => .right_command,
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
            dvui.log.debug("SDL_keysym_to_dvui unknown keysym {d}\n", .{keysym});
            break :blk .unknown;
        },
    };
}
