const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");

const sdl_options = @import("sdl_options");
pub const sdl3 = sdl_options.version.major == 3;
pub const c = blk: {
    if (sdl3) {
        break :blk @cImport({
            @cDefine("SDL_DISABLE_OLD_NAMES", {});
            @cInclude("SDL3/SDL.h");
        });
    }
    break :blk @cImport({
        @cInclude("SDL2/SDL.h");
    });
};

pub const kind: dvui.enums.Backend = if (sdl3) .sdl3 else .sdl2;

pub const SDLBackend = @This();
pub const Context = *SDLBackend;

const log = std.log.scoped(.SDLBackend);

window: *c.SDL_Window,
renderer: *c.SDL_Renderer,
we_own_window: bool = false,
touch_mouse_events: bool = false,
log_events: bool = false,
initial_scale: f32 = 1.0,
cursor_last: dvui.enums.Cursor = .arrow,
cursor_backing: [@typeInfo(dvui.enums.Cursor).@"enum".fields.len]?*c.SDL_Cursor = [_]?*c.SDL_Cursor{null} ** @typeInfo(dvui.enums.Cursor).@"enum".fields.len,
cursor_backing_tried: [@typeInfo(dvui.enums.Cursor).@"enum".fields.len]bool = [_]bool{false} ** @typeInfo(dvui.enums.Cursor).@"enum".fields.len,
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
    /// use when running tests
    hidden: bool = false,
};

pub fn initWindow(options: InitOptions) !SDLBackend {
    if (!sdl3) _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "linear");
    // needed according to https://discourse.libsdl.org/t/possible-to-run-sdl2-headless/25665/2
    // but getting error "offscreen not available"
    // if (options.hidden) _ = c.SDL_SetHint(c.SDL_HINT_VIDEODRIVER, "offscreen");

    // use the string version instead of the #define so we compile with SDL < 2.24
    _ = c.SDL_SetHint("SDL_HINT_WINDOWS_DPI_SCALING", "1");

    if (c.SDL_Init(c.SDL_INIT_VIDEO) != if (sdl3) true else 0) {
        log.err("Couldn't initialize SDL: {s}", .{c.SDL_GetError()});
        return error.BackendError;
    }

    const hidden_flag = if (options.hidden) c.SDL_WINDOW_HIDDEN else 0;
    var window: *c.SDL_Window = undefined;
    if (sdl3) {
        window = c.SDL_CreateWindow(options.title, @as(c_int, @intFromFloat(options.size.w)), @as(c_int, @intFromFloat(options.size.h)), @intCast(c.SDL_WINDOW_HIGH_PIXEL_DENSITY | c.SDL_WINDOW_RESIZABLE | hidden_flag)) orelse {
            log.err("Failed to open window: {s}", .{c.SDL_GetError()});
            return error.BackendError;
        };
    } else {
        window = c.SDL_CreateWindow(options.title, c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, @as(c_int, @intFromFloat(options.size.w)), @as(c_int, @intFromFloat(options.size.h)), @intCast(c.SDL_WINDOW_ALLOW_HIGHDPI | c.SDL_WINDOW_RESIZABLE | hidden_flag)) orelse {
            log.err("Failed to open window: {s}", .{c.SDL_GetError()});
            return error.BackendError;
        };
    }

    var renderer: *c.SDL_Renderer = undefined;
    if (sdl3) {
        const props = c.SDL_CreateProperties();
        defer c.SDL_DestroyProperties(props);

        _ = c.SDL_SetPointerProperty(props, c.SDL_PROP_RENDERER_CREATE_WINDOW_POINTER, window);

        if (options.vsync) {
            _ = c.SDL_SetNumberProperty(props, c.SDL_PROP_RENDERER_CREATE_PRESENT_VSYNC_NUMBER, 1);
        }

        renderer = c.SDL_CreateRendererWithProperties(props) orelse {
            log.err("Failed to create renderer: {s}", .{c.SDL_GetError()});
            return error.BackendError;
        };
    } else {
        renderer = c.SDL_CreateRenderer(window, -1, @intCast(c.SDL_RENDERER_TARGETTEXTURE | (if (options.vsync) c.SDL_RENDERER_PRESENTVSYNC else 0))) orelse {
            log.err("Failed to create renderer: {s}", .{c.SDL_GetError()});
            return error.BackendError;
        };
    }

    // do premultiplied alpha blending:
    // * rendering to a texture and then rendering the texture works the same
    // * any filtering happening across pixels won't bleed in transparent rgb values
    const pma_blend = c.SDL_ComposeCustomBlendMode(c.SDL_BLENDFACTOR_ONE, c.SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, c.SDL_BLENDOPERATION_ADD, c.SDL_BLENDFACTOR_ONE, c.SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, c.SDL_BLENDOPERATION_ADD);
    _ = c.SDL_SetRenderDrawBlendMode(renderer, pma_blend);

    var back = init(window, renderer);
    back.we_own_window = true;

    if (sdl3) {
        back.initial_scale = c.SDL_GetDisplayContentScale(c.SDL_GetDisplayForWindow(window));
        log.info("SDL3 backend scale {d}", .{back.initial_scale});
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
                    log.info("QT_AUTO_SCREEN_SCALE_FACTOR is 0, disabling content scale guessing", .{});
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
                    log.info("QT_SCALE_FACTOR is {d}, using that for initial content scale", .{qt_scale});
                    back.initial_scale = qt_scale;
                    guess_from_dpi = false;
                } else if (gdk_str) |str| {
                    const gdk_scale = std.fmt.parseFloat(f32, str) catch 1.0;
                    log.info("GDK_SCALE is {d}, using that for initial content scale", .{gdk_scale});
                    back.initial_scale = gdk_scale;
                    guess_from_dpi = false;
                }
            }

            if (guess_from_dpi) {
                var mdpi: ?f32 = null;

                // for X11, try to grab the output of xrdb -query
                //*customization: -color
                //Xft.dpi: 96
                //Xft.antialias: 1
                if (mdpi == null and builtin.os.tag == .linux) {
                    var stdout: std.ArrayListUnmanaged(u8) = .empty;
                    defer stdout.deinit(options.allocator);
                    var stderr: std.ArrayListUnmanaged(u8) = .empty;
                    defer stderr.deinit(options.allocator);
                    var child = std.process.Child.init(&.{ "xrdb", "-get", "Xft.dpi" }, options.allocator);
                    child.stdout_behavior = .Pipe;
                    child.stderr_behavior = .Pipe;
                    try child.spawn();
                    var ok = true;
                    child.collectOutput(options.allocator, &stdout, &stderr, 100) catch {
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
                            log.info("dpi {d} from xrdb -get Xft.dpi", .{dpi});
                        }
                    }
                }

                // This doesn't seem to be helping anybody and sometimes hurts,
                // so we'll try disabling it outside of windows for now.
                if (mdpi == null and builtin.os.tag == .windows) {
                    // see if we can guess correctly based on the dpi from SDL2
                    const display_num = c.SDL_GetWindowDisplayIndex(window);
                    var hdpi: f32 = undefined;
                    var vdpi: f32 = undefined;
                    _ = c.SDL_GetDisplayDPI(display_num, null, &hdpi, &vdpi);
                    mdpi = @max(hdpi, vdpi);
                    log.info("dpi {d} from SDL_GetDisplayDPI\n", .{mdpi.?});
                }

                if (mdpi) |dpi| {
                    if (builtin.os.tag == .windows) {
                        // Windows DPIs come in 25% increments, and sometimes SDL2
                        // reports something slightly off, which feels a bit blurry.
                        back.initial_scale = dpi / 100.0;
                        back.initial_scale = @round(back.initial_scale / 0.25) * 0.25;
                    } else {
                        // Other platforms get integer scaling until someone
                        // figures out how to make it better
                        if (dpi > 200) {
                            back.initial_scale = 4.0;
                        } else if (dpi > 100) {
                            back.initial_scale = 2.0;
                        }
                    }

                    log.info("guessing initial backend scale {d} from dpi {d}", .{ back.initial_scale, dpi });
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
        log.warn("when setting icon, stbi_load error: {s}", .{dvui.c.stbi_failure_reason()});
        return;
    }
    defer dvui.c.stbi_image_free(data);
    self.setIconFromABGR8888(data, icon_w, icon_h);
}

pub fn setIconFromABGR8888(self: *SDLBackend, data: [*]const u8, icon_w: c_int, icon_h: c_int) void {
    const surface = if (sdl3)
        c.SDL_CreateSurfaceFrom(icon_w, icon_h, c.SDL_PIXELFORMAT_ABGR8888, @ptrCast(@constCast(data)), 4 * icon_w)
    else
        c.SDL_CreateRGBSurfaceWithFormatFrom(@ptrCast(@constCast(data)), icon_w, icon_h, 32, 4 * icon_w, c.SDL_PIXELFORMAT_ABGR8888);

    defer if (sdl3) c.SDL_DestroySurface(surface) else c.SDL_FreeSurface(surface);

    _ = c.SDL_SetWindowIcon(self.window, surface);
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
    ue.type = if (sdl3) c.SDL_EVENT_USER else c.SDL_USEREVENT;
    _ = c.SDL_PushEvent(&ue);
}

pub fn addAllEvents(self: *SDLBackend, win: *dvui.Window) !bool {
    //const flags = c.SDL_GetWindowFlags(self.window);
    //if (flags & c.SDL_WINDOW_MOUSE_FOCUS == 0 and flags & c.SDL_WINDOW_INPUT_FOCUS == 0) {
    //std.debug.print("bailing\n", .{});
    //}
    var event: c.SDL_Event = undefined;
    const poll_got_event = if (sdl3) true else 1;
    while (c.SDL_PollEvent(&event) == poll_got_event) {
        _ = try self.addEvent(win, event);
        switch (event.type) {
            if (sdl3) c.SDL_EVENT_QUIT else c.SDL_QUIT => {
                return true;
            },
            // TODO: revisit with sdl3
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
                .arrow => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_DEFAULT else c.SDL_SYSTEM_CURSOR_ARROW),
                .ibeam => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_TEXT else c.SDL_SYSTEM_CURSOR_IBEAM),
                .wait => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_WAIT),
                .wait_arrow => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_PROGRESS else c.SDL_SYSTEM_CURSOR_WAITARROW),
                .crosshair => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_CROSSHAIR),
                .arrow_nw_se => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_NWSE_RESIZE else c.SDL_SYSTEM_CURSOR_SIZENWSE),
                .arrow_ne_sw => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_NESW_RESIZE else c.SDL_SYSTEM_CURSOR_SIZENESW),
                .arrow_w_e => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_EW_RESIZE else c.SDL_SYSTEM_CURSOR_SIZEWE),
                .arrow_n_s => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_NS_RESIZE else c.SDL_SYSTEM_CURSOR_SIZENS),
                .arrow_all => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_MOVE else c.SDL_SYSTEM_CURSOR_SIZEALL),
                .bad => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_NOT_ALLOWED else c.SDL_SYSTEM_CURSOR_NO),
                .hand => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_POINTER else c.SDL_SYSTEM_CURSOR_HAND),
            };
        }

        if (self.cursor_backing[enum_int]) |cur| {
            if (sdl3) {
                _ = c.SDL_SetCursor(cur);
            } else {
                c.SDL_SetCursor(cur);
            }
        } else {
            log.err("SDL_CreateSystemCursor \"{s}\" failed", .{@tagName(cursor)});
        }
    }
}

pub fn textInputRect(self: *SDLBackend, rect: ?dvui.Rect.Natural) void {
    if (rect) |r| {
        if (sdl3) {
            // This is the offset from r.x in window coords, supposed to be the
            // location of the cursor I think so that the IME window can be put
            // at the cursor location.  We will use 0 for now, might need to
            // change it (or how we determine rect) if people are using huge
            // text entries).
            const cursor = 0;

            _ = c.SDL_SetTextInputArea(self.window, &c.SDL_Rect{ .x = @intFromFloat(r.x), .y = @intFromFloat(r.y), .w = @intFromFloat(r.w), .h = @intFromFloat(r.h) }, cursor);
        } else c.SDL_SetTextInputRect(&c.SDL_Rect{ .x = @intFromFloat(r.x), .y = @intFromFloat(r.y), .w = @intFromFloat(r.w), .h = @intFromFloat(r.h) });
        _ = if (sdl3) c.SDL_StartTextInput(self.window) else c.SDL_StartTextInput();
    } else {
        _ = if (sdl3) c.SDL_StopTextInput(self.window) else c.SDL_StopTextInput();
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
    return c.SDL_PollEvent(null) == if (sdl3) true else 1;
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
    _ = if (sdl3) c.SDL_SetRenderClipRect(self.renderer, &c.SDL_Rect{ .x = 0, .y = 0, .w = @intFromFloat(size.w), .h = @intFromFloat(size.h) }) else c.SDL_RenderSetClipRect(self.renderer, &c.SDL_Rect{ .x = 0, .y = 0, .w = @intFromFloat(size.w), .h = @intFromFloat(size.h) });
}

pub fn end(_: *SDLBackend) void {}

pub fn pixelSize(self: *SDLBackend) dvui.Size.Physical {
    var w: i32 = undefined;
    var h: i32 = undefined;
    if (sdl3) {
        _ = c.SDL_GetCurrentRenderOutputSize(self.renderer, &w, &h);
    } else {
        _ = c.SDL_GetRendererOutputSize(self.renderer, &w, &h);
    }
    return .{ .w = @as(f32, @floatFromInt(w)), .h = @as(f32, @floatFromInt(h)) };
}

pub fn windowSize(self: *SDLBackend) dvui.Size.Natural {
    var w: i32 = undefined;
    var h: i32 = undefined;
    _ = c.SDL_GetWindowSize(self.window, &w, &h);
    return .{ .w = @as(f32, @floatFromInt(w)), .h = @as(f32, @floatFromInt(h)) };
}

pub fn contentScale(self: *SDLBackend) f32 {
    return self.initial_scale;
}

pub fn drawClippedTriangles(self: *SDLBackend, texture: ?dvui.Texture, vtx: []const dvui.Vertex, idx: []const u16, maybe_clipr: ?dvui.Rect.Physical) void {
    //std.debug.print("drawClippedTriangles:\n", .{});
    //for (vtx) |v, i| {
    //  std.debug.print("  {d} vertex {}\n", .{i, v});
    //}
    //for (idx) |id, i| {
    //  std.debug.print("  {d} index {d}\n", .{i, id});
    //}

    var oldclip: c.SDL_Rect = undefined;

    if (maybe_clipr) |clipr| {
        if (sdl3) {
            _ = c.SDL_GetRenderClipRect(self.renderer, &oldclip);
        } else {
            _ = c.SDL_RenderGetClipRect(self.renderer, &oldclip);
        }

        // figure out how much we are losing by truncating x and y, need to add that back to w and h
        const clip = c.SDL_Rect{ .x = @as(c_int, @intFromFloat(clipr.x)), .y = @as(c_int, @intFromFloat(clipr.y)), .w = @max(0, @as(c_int, @intFromFloat(@ceil(clipr.w + clipr.x - @floor(clipr.x))))), .h = @max(0, @as(c_int, @intFromFloat(@ceil(clipr.h + clipr.y - @floor(clipr.y))))) };
        //std.debug.print("sdl clip {}\n", .{clipr});

        //std.debug.print("SDL clip {} -> SDL_Rect{{ .x = {d}, .y = {d}, .w = {d}, .h = {d} }}\n", .{ clipr, clip.x, clip.y, clip.w, clip.h });
        if (sdl3) {
            _ = c.SDL_SetRenderClipRect(self.renderer, &clip);
        } else {
            _ = c.SDL_RenderSetClipRect(self.renderer, &clip);
        }
    }

    var tex: ?*c.SDL_Texture = null;
    if (texture) |t| {
        tex = @ptrCast(@alignCast(t.ptr));
    }

    if (sdl3) {
        // not great, but seems sdl3 strictly accepts color only in floats
        // TODO: review if better solution is possible
        const vcols = self.arena.alloc(c.SDL_FColor, vtx.len) catch return;
        defer self.arena.free(vcols);
        for (vcols, 0..) |*col, i| {
            col.r = @as(f32, @floatFromInt(vtx[i].col.r)) / 255.0;
            col.g = @as(f32, @floatFromInt(vtx[i].col.g)) / 255.0;
            col.b = @as(f32, @floatFromInt(vtx[i].col.b)) / 255.0;
            col.a = @as(f32, @floatFromInt(vtx[i].col.a)) / 255.0;
        }

        _ = c.SDL_RenderGeometryRaw(
            self.renderer,
            tex,
            @as(*const f32, @ptrCast(&vtx[0].pos)),
            @sizeOf(dvui.Vertex),
            vcols.ptr,
            @sizeOf(c.SDL_FColor),
            @as(*const f32, @ptrCast(&vtx[0].uv)),
            @sizeOf(dvui.Vertex),
            @as(c_int, @intCast(vtx.len)),
            idx.ptr,
            @as(c_int, @intCast(idx.len)),
            @sizeOf(u16),
        );
    } else {
        _ = c.SDL_RenderGeometryRaw(
            self.renderer,
            tex,
            @as(*const f32, @ptrCast(&vtx[0].pos)),
            @sizeOf(dvui.Vertex),
            @as(*const c.SDL_Color, @ptrCast(@alignCast(&vtx[0].col))),
            @sizeOf(dvui.Vertex),
            @as(*const f32, @ptrCast(&vtx[0].uv)),
            @sizeOf(dvui.Vertex),
            @as(c_int, @intCast(vtx.len)),
            idx.ptr,
            @as(c_int, @intCast(idx.len)),
            @sizeOf(u16),
        );
    }

    if (maybe_clipr) |_| {
        if (sdl3) {
            _ = c.SDL_SetRenderClipRect(self.renderer, &oldclip);
        } else {
            _ = c.SDL_RenderSetClipRect(self.renderer, &oldclip);
        }
    }
}

pub fn textureCreate(self: *SDLBackend, pixels: [*]u8, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) dvui.Texture {
    if (!sdl3) switch (interpolation) {
        .nearest => _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "nearest"),
        .linear => _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "linear"),
    };

    var surface: *c.SDL_Surface = undefined;
    if (sdl3) {
        surface = c.SDL_CreateSurfaceFrom(@as(c_int, @intCast(width)), @as(c_int, @intCast(height)), c.SDL_PIXELFORMAT_ABGR8888, pixels, @as(c_int, @intCast(4 * width)));
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

    if (sdl3) {
        switch (interpolation) {
            .nearest => _ = c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_NEAREST),
            .linear => _ = c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_LINEAR),
        }
    }

    const pma_blend = c.SDL_ComposeCustomBlendMode(c.SDL_BLENDFACTOR_ONE, c.SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, c.SDL_BLENDOPERATION_ADD, c.SDL_BLENDFACTOR_ONE, c.SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, c.SDL_BLENDOPERATION_ADD);
    _ = c.SDL_SetTextureBlendMode(texture, pma_blend);
    return dvui.Texture{ .ptr = texture, .width = width, .height = height };
}

pub fn textureCreateTarget(self: *SDLBackend, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) !dvui.TextureTarget {
    if (!sdl3) {
        switch (interpolation) {
            .nearest => _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "nearest"),
            .linear => _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "linear"),
        }
    }

    const texture = c.SDL_CreateTexture(self.renderer, c.SDL_PIXELFORMAT_ABGR8888, c.SDL_TEXTUREACCESS_TARGET, @intCast(width), @intCast(height)) orelse unreachable;

    if (sdl3) {
        switch (interpolation) {
            .nearest => _ = c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_NEAREST),
            .linear => _ = c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_LINEAR),
        }
    }

    const pma_blend = c.SDL_ComposeCustomBlendMode(c.SDL_BLENDFACTOR_ONE, c.SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, c.SDL_BLENDOPERATION_ADD, c.SDL_BLENDFACTOR_ONE, c.SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, c.SDL_BLENDOPERATION_ADD);
    _ = c.SDL_SetTextureBlendMode(texture, pma_blend);
    //_ = c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND);

    // make sure texture starts out transparent
    const old = c.SDL_GetRenderTarget(self.renderer);
    defer _ = c.SDL_SetRenderTarget(self.renderer, old);

    var oldBlend: [1]c_uint = undefined;
    _ = c.SDL_GetRenderDrawBlendMode(self.renderer, &oldBlend);
    defer _ = c.SDL_SetRenderDrawBlendMode(self.renderer, oldBlend[0]);

    _ = c.SDL_SetRenderTarget(self.renderer, texture);
    _ = c.SDL_SetRenderDrawBlendMode(self.renderer, c.SDL_BLENDMODE_NONE);
    _ = c.SDL_SetRenderDrawColor(self.renderer, 0, 0, 0, 0);
    _ = c.SDL_RenderFillRect(self.renderer, null);

    return dvui.TextureTarget{ .ptr = texture, .width = width, .height = height };
}

pub fn textureReadTarget(self: *SDLBackend, texture: dvui.TextureTarget, pixels_out: [*]u8) error{TextureRead}!void {
    if (sdl3) {
        const orig_target = c.SDL_GetRenderTarget(self.renderer);
        const r = c.SDL_SetRenderTarget(self.renderer, @ptrCast(@alignCast(texture.ptr)));
        defer _ = c.SDL_SetRenderTarget(self.renderer, orig_target);

        if (!r) {
            std.debug.print("setRenderTarget Error: {s}", .{c.SDL_GetError()});
            return error.TextureRead;
        }

        var surface: *c.SDL_Surface = c.SDL_RenderReadPixels(self.renderer, null) orelse return error.TextureRead;
        defer c.SDL_DestroySurface(surface);
        if (texture.width * texture.height != surface.*.w * surface.*.h) {
            std.debug.print("texture {d} {d} surface {d} {d}\n", .{ texture.width, texture.height, surface.*.w, surface.*.h });
            return error.TextureRead;
        }
        // TODO: most common format is RGBA8888, doing conversion during copy to pixels_out should be faster
        if (surface.*.format != c.SDL_PIXELFORMAT_ABGR8888) {
            surface = c.SDL_ConvertSurface(surface, c.SDL_PIXELFORMAT_ABGR8888) orelse return error.TextureRead;
        }
        @memcpy(pixels_out[0 .. texture.width * texture.height * 4], @as(?[*]u8, @ptrCast(surface.*.pixels)).?[0 .. texture.width * texture.height * 4]);
        return;
    }

    // If SDL picks directX11 as a rendering backend, it could not support
    // SDL_PIXELFORMAT_ABGR8888 so this works around that.  For some reason sdl
    // crashes if we ask it to do the conversion for us.
    var swap_rb = true;
    var info: c.SDL_RendererInfo = undefined;
    _ = c.SDL_GetRendererInfo(self.renderer, &info);
    //std.debug.print("renderer name {s} formats:\n", .{info.name});
    for (0..info.num_texture_formats) |i| {
        //std.debug.print("  {s}\n", .{c.SDL_GetPixelFormatName(info.texture_formats[i])});
        if (info.texture_formats[i] == c.SDL_PIXELFORMAT_ABGR8888) {
            swap_rb = false;
        }
    }

    //var format: u32 = undefined;
    //var access: c_int = undefined;
    //var w: c_int = undefined;
    //var h: c_int = undefined;
    //_ = c.SDL_QueryTexture(@ptrCast(texture), &format, &access, &w, &h);
    //std.debug.print("query texture: {s} {d} {d} {d} width {d}\n", .{c.SDL_GetPixelFormatName(format), access, w, h, width});

    const orig_target = c.SDL_GetRenderTarget(self.renderer);
    _ = c.SDL_SetRenderTarget(self.renderer, @ptrCast(texture.ptr));
    defer _ = c.SDL_SetRenderTarget(self.renderer, orig_target);

    _ = c.SDL_RenderReadPixels(self.renderer, null, if (swap_rb) c.SDL_PIXELFORMAT_ARGB8888 else c.SDL_PIXELFORMAT_ABGR8888, pixels_out, @intCast(texture.width * 4));

    if (swap_rb) {
        for (0..texture.width * texture.height) |i| {
            const r = pixels_out[i * 4 + 0];
            const b = pixels_out[i * 4 + 2];
            pixels_out[i * 4 + 0] = b;
            pixels_out[i * 4 + 2] = r;
        }
    }
}

pub fn textureDestroy(_: *SDLBackend, texture: dvui.Texture) void {
    c.SDL_DestroyTexture(@as(*c.SDL_Texture, @ptrCast(@alignCast(texture.ptr))));
}

pub fn textureFromTarget(self: *SDLBackend, texture: dvui.TextureTarget) dvui.Texture {
    // SDL can't read from non-target textures, so read all the pixels and make a new texture
    const pixels = dvui.textureReadTarget(self.arena, texture) catch unreachable;
    defer self.arena.free(pixels);

    c.SDL_DestroyTexture(@as(*c.SDL_Texture, @ptrCast(@alignCast(texture.ptr))));

    return self.textureCreate(pixels.ptr, texture.width, texture.height, .linear);
}

pub fn renderTarget(self: *SDLBackend, texture: ?dvui.TextureTarget) void {
    const ptr: ?*anyopaque = if (texture) |tex| tex.ptr else null;
    _ = c.SDL_SetRenderTarget(self.renderer, @ptrCast(@alignCast(ptr)));

    // by default sdl sets an empty clip, let's ensure it is the full texture/screen
    if (sdl3) {
        // sdl3 crashes if w/h are too big, this seems to work
        _ = c.SDL_SetRenderClipRect(self.renderer, &c.SDL_Rect{ .x = 0, .y = 0, .w = 65536, .h = 65536 });
    } else {
        _ = c.SDL_RenderSetClipRect(self.renderer, &c.SDL_Rect{ .x = 0, .y = 0, .w = std.math.maxInt(c_int), .h = std.math.maxInt(c_int) });
    }
}

pub fn addEvent(self: *SDLBackend, win: *dvui.Window, event: c.SDL_Event) !bool {
    switch (event.type) {
        if (sdl3) c.SDL_EVENT_KEY_DOWN else c.SDL_KEYDOWN => {
            const sdl_key: i32 = if (sdl3) @intCast(event.key.key) else event.key.keysym.sym;
            const code = SDL_keysym_to_dvui(@intCast(sdl_key));
            const mod = SDL_keymod_to_dvui(if (sdl3) @intCast(event.key.mod) else event.key.keysym.mod);
            if (self.log_events) {
                log.debug("event KEYDOWN {} {s} {} {}\n", .{ sdl_key, @tagName(code), mod, event.key.repeat });
            }

            return try win.addEventKey(.{
                .code = code,
                .action = if (if (sdl3) event.key.repeat else event.key.repeat != 0) .repeat else .down,
                .mod = mod,
            });
        },
        if (sdl3) c.SDL_EVENT_KEY_UP else c.SDL_KEYUP => {
            const sdl_key: i32 = if (sdl3) @intCast(event.key.key) else event.key.keysym.sym;
            const code = SDL_keysym_to_dvui(@intCast(sdl_key));
            const mod = SDL_keymod_to_dvui(if (sdl3) @intCast(event.key.mod) else event.key.keysym.mod);
            if (self.log_events) {
                log.debug("event KEYUP {} {s} {}\n", .{ sdl_key, @tagName(code), mod });
            }

            return try win.addEventKey(.{
                .code = code,
                .action = .up,
                .mod = mod,
            });
        },
        if (sdl3) c.SDL_EVENT_TEXT_INPUT else c.SDL_TEXTINPUT => {
            const txt = std.mem.sliceTo(if (sdl3) event.text.text else &event.text.text, 0);
            if (self.log_events) {
                log.debug("event TEXTINPUT {s}\n", .{txt});
            }

            return try win.addEventText(txt);
        },
        if (sdl3) c.SDL_EVENT_TEXT_EDITING else c.SDL_TEXTEDITING => {
            const strlen: u8 = @intCast(c.SDL_strlen(if (sdl3) event.edit.text else &event.edit.text));
            if (self.log_events) {
                log.debug("event TEXTEDITING {s} start {d} len {d} strlen {d}\n", .{ event.edit.text, event.edit.start, event.edit.length, strlen });
            }
            return try win.addEventTextEx(event.edit.text[0..strlen], true);
        },
        if (sdl3) c.SDL_EVENT_MOUSE_MOTION else c.SDL_MOUSEMOTION => {
            const touch = event.motion.which == c.SDL_TOUCH_MOUSEID;
            if (self.log_events) {
                var touch_str: []const u8 = " ";
                if (touch) touch_str = " touch ";
                if (touch and !self.touch_mouse_events) touch_str = " touch ignored ";
                log.debug("event{s}MOUSEMOTION {d} {d}\n", .{ touch_str, event.motion.x, event.motion.y });
            }

            if (touch and !self.touch_mouse_events) {
                return false;
            }

            if (sdl3) {
                return try win.addEventMouseMotion(.{.x = event.motion.x, .y = event.motion.y});
            } else {
                return try win.addEventMouseMotion(.{.x = @as(f32, @floatFromInt(event.motion.x)), .y = @as(f32, @floatFromInt(event.motion.y))});
            }
        },
        if (sdl3) c.SDL_EVENT_MOUSE_BUTTON_DOWN else c.SDL_MOUSEBUTTONDOWN => {
            const touch = event.motion.which == c.SDL_TOUCH_MOUSEID;
            if (self.log_events) {
                var touch_str: []const u8 = " ";
                if (touch) touch_str = " touch ";
                if (touch and !self.touch_mouse_events) touch_str = " touch ignored ";
                log.debug("event{s}MOUSEBUTTONDOWN {d}\n", .{ touch_str, event.button.button });
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
                log.debug("event{s}MOUSEBUTTONUP {d}\n", .{ touch_str, event.button.button });
            }

            if (touch and !self.touch_mouse_events) {
                return false;
            }

            return try win.addEventMouseButton(SDL_mouse_button_to_dvui(event.button.button), .release);
        },
        if (sdl3) c.SDL_EVENT_MOUSE_WHEEL else c.SDL_MOUSEWHEEL => {
            if (self.log_events) {
                log.debug("event MOUSEWHEEL {d} {d} {d}\n", .{ event.wheel.x, event.wheel.y, event.wheel.which });
            }

            const ticks_x = if (sdl3) event.wheel.x else @as(f32, @floatFromInt(event.wheel.x));
            const ticks_y = if (sdl3) event.wheel.y else @as(f32, @floatFromInt(event.wheel.y));
            const ticks = if (ticks_x == 0) ticks_y else ticks_x;

            // TODO: some real solution to interpreting the mouse wheel across OSes
            const ticks_adj = switch (builtin.target.os.tag) {
                .linux => ticks * 20,
                .windows => ticks * 20,
                .macos => ticks * 10,
                else => ticks,
            };

            return try win.addEventMouseWheel(ticks_adj, if (event.wheel.x == 0) .vertical else .horizontal);
        },
        if (sdl3) c.SDL_EVENT_FINGER_DOWN else c.SDL_FINGERDOWN => {
            if (self.log_events) {
                log.debug("event FINGERDOWN {d} {d} {d}\n", .{ if (sdl3) event.tfinger.fingerID else event.tfinger.fingerId, event.tfinger.x, event.tfinger.y });
            }

            return try win.addEventPointer(.touch0, .press, .{ .x = event.tfinger.x, .y = event.tfinger.y });
        },
        if (sdl3) c.SDL_EVENT_FINGER_UP else c.SDL_FINGERUP => {
            if (self.log_events) {
                log.debug("event FINGERUP {d} {d} {d}\n", .{ if (sdl3) event.tfinger.fingerID else event.tfinger.fingerId, event.tfinger.x, event.tfinger.y });
            }

            return try win.addEventPointer(.touch0, .release, .{ .x = event.tfinger.x, .y = event.tfinger.y });
        },
        if (sdl3) c.SDL_EVENT_FINGER_MOTION else c.SDL_FINGERMOTION => {
            if (self.log_events) {
                log.debug("event FINGERMOTION {d} {d} {d} {d} {d}\n", .{ if (sdl3) event.tfinger.fingerID else event.tfinger.fingerId, event.tfinger.x, event.tfinger.y, event.tfinger.dx, event.tfinger.dy });
            }

            return try win.addEventTouchMotion(.touch0, event.tfinger.x, event.tfinger.y, event.tfinger.dx, event.tfinger.dy);
        },
        else => {
            if (self.log_events) {
                log.debug("unhandled SDL event type {}\n", .{event.type});
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
            log.debug("SDL_mouse_button_to_dvui.unknown button {d}", .{button});
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
        if (sdl3) c.SDLK_A else c.SDLK_a => .a,
        if (sdl3) c.SDLK_B else c.SDLK_b => .b,
        if (sdl3) c.SDLK_C else c.SDLK_c => .c,
        if (sdl3) c.SDLK_D else c.SDLK_d => .d,
        if (sdl3) c.SDLK_E else c.SDLK_e => .e,
        if (sdl3) c.SDLK_F else c.SDLK_f => .f,
        if (sdl3) c.SDLK_G else c.SDLK_g => .g,
        if (sdl3) c.SDLK_H else c.SDLK_h => .h,
        if (sdl3) c.SDLK_I else c.SDLK_i => .i,
        if (sdl3) c.SDLK_J else c.SDLK_j => .j,
        if (sdl3) c.SDLK_K else c.SDLK_k => .k,
        if (sdl3) c.SDLK_L else c.SDLK_l => .l,
        if (sdl3) c.SDLK_M else c.SDLK_m => .m,
        if (sdl3) c.SDLK_N else c.SDLK_n => .n,
        if (sdl3) c.SDLK_O else c.SDLK_o => .o,
        if (sdl3) c.SDLK_P else c.SDLK_p => .p,
        if (sdl3) c.SDLK_Q else c.SDLK_q => .q,
        if (sdl3) c.SDLK_R else c.SDLK_r => .r,
        if (sdl3) c.SDLK_S else c.SDLK_s => .s,
        if (sdl3) c.SDLK_T else c.SDLK_t => .t,
        if (sdl3) c.SDLK_U else c.SDLK_u => .u,
        if (sdl3) c.SDLK_V else c.SDLK_v => .v,
        if (sdl3) c.SDLK_W else c.SDLK_w => .w,
        if (sdl3) c.SDLK_X else c.SDLK_x => .x,
        if (sdl3) c.SDLK_Y else c.SDLK_y => .y,
        if (sdl3) c.SDLK_Z else c.SDLK_z => .z,

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
        if (sdl3) c.SDLK_APOSTROPHE else c.SDLK_QUOTE => .apostrophe,
        c.SDLK_COMMA => .comma,
        c.SDLK_PERIOD => .period,
        c.SDLK_SLASH => .slash,
        if (sdl3) c.SDLK_GRAVE else c.SDLK_BACKQUOTE => .grave,

        else => blk: {
            log.debug("SDL_keysym_to_dvui unknown keysym {d}", .{keysym});
            break :blk .unknown;
        },
    };
}

pub fn getSDLVersion() std.SemanticVersion {
    if (sdl3) {
        const v: u32 = @bitCast(c.SDL_GetVersion());
        return .{
            .major = @divTrunc(v, 1000000),
            .minor = @mod(@divTrunc(v, 1000), 1000),
            .patch = @mod(v, 1000),
        };
    } else {
        var v: c.SDL_version = .{};
        c.SDL_GetVersion(&v);
        return .{
            .major = @intCast(v.major),
            .minor = @intCast(v.minor),
            .patch = @intCast(v.patch),
        };
    }
}

// Optional: windows os only
const winapi = if (builtin.os.tag == .windows) struct {
    extern "kernel32" fn AttachConsole(dwProcessId: std.os.windows.DWORD) std.os.windows.BOOL;
} else struct {};

// This must be exposed in the app's root source file.
pub fn main() !void {
    const app = dvui.App.get() orelse return error.DvuiAppNotDefined;

    if (@import("builtin").os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
        _ = winapi.AttachConsole(0xFFFFFFFF);
    }
    log.info("version: {}", .{getSDLVersion()});

    const init_opts = app.config.get();

    var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_instance.allocator();

    defer if (gpa_instance.deinit() != .ok) @panic("Memory leak on exit!");

    // init SDL backend (creates and owns OS window)
    var back = try initWindow(.{
        .allocator = gpa,
        .size = init_opts.size,
        .min_size = init_opts.min_size,
        .max_size = init_opts.max_size,
        .vsync = init_opts.vsync,
        .title = init_opts.title,
        .icon = init_opts.icon,
        .hidden = init_opts.hidden,
    });
    defer back.deinit();

    _ = c.SDL_EnableScreenSaver();

    //// init dvui Window (maps onto a single OS window)
    var win = try dvui.Window.init(@src(), gpa, back.backend(), .{});
    defer win.deinit();

    if (app.initFn) |initFn| initFn(&win);
    defer if (app.deinitFn) |deinitFn| deinitFn();

    main_loop: while (true) {

        // beginWait coordinates with waitTime below to run frames only when needed
        const nstime = win.beginWait(back.hasEvent());

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(nstime);

        // send all SDL events to dvui for processing
        const quit = try back.addAllEvents(&win);
        if (quit) break :main_loop;

        // if dvui widgets might not cover the whole window, then need to clear
        // the previous frame's render
        _ = c.SDL_SetRenderDrawColor(back.renderer, 0, 0, 0, 255);
        _ = c.SDL_RenderClear(back.renderer);

        const res = try app.frameFn();

        const end_micros = try win.end(.{});

        back.setCursor(win.cursorRequested());
        back.textInputRect(win.textInputRequested());

        back.renderPresent();

        if (res != .ok) break :main_loop;

        const wait_event_micros = win.waitTime(end_micros, null);
        back.waitEventTimeout(wait_event_micros);
    }
}

test {
    //std.debug.print("{s} backend test\n", .{if (sdl3) "SDL3" else "SDL2"});
    std.testing.refAllDecls(@This());
}
