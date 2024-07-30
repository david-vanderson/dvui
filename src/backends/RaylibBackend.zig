pub const RaylibBackend = @This();
const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const ray = @cImport({
    @cInclude("raylib.h");
});

const conversion_factor = 1000000000.0;

initial_scale: f32 = 1.0,
arena: std.mem.Allocator,

//TODO verify this is correct
pub fn nanoTime(self: *RaylibBackend) i128 {
    _ = self;
    return @intFromFloat(ray.GetTime() * conversion_factor); // Get elapsed time in seconds since InitWindow()
}

pub fn sleep(self: *RaylibBackend, ns: u64) void {
    _ = self; // autofix
    const seconds: f64 = @floatFromInt(ns / conversion_factor);
    ray.WaitTime(seconds);
}

pub fn begin(self: *RaylibBackend, arena: std.mem.Allocator) void {
    _ = self; // autofix
    _ = arena; // autofix
    ray.SetConfigFlags(ray.FLAG_WINDOW_RESIZABLE);
    ray.SetConfigFlags(ray.FLAG_VSYNC_HINT);
    ray.InitWindow(800, 450, "dvui");
    ray.BeginDrawing();
}

pub fn end(self: *RaylibBackend) void {
    _ = self; // autofix
    ray.EndDrawing();
    ray.CloseWindow();
}

pub fn pixelSize(self: *RaylibBackend) dvui.Size {
    _ = self; // autofix
    return dvui.Size{
        .w = @as(f32, @floatFromInt(ray.GetRenderWidth())),
        .h = @as(f32, @floatFromInt(ray.GetRenderHeight())),
    };
}

pub fn windowSize(self: *RaylibBackend) dvui.Size {
    _ = self; // autofix
    return dvui.Size{
        .w = @as(f32, @floatFromInt(ray.GetScreenWidth())),
        .h = @as(f32, @floatFromInt(ray.GetScreenHeight())),
    };
}

pub fn contentScale(self: *RaylibBackend) f32 {
    return self.initial_scale;
}

//TODO implement
pub fn renderGeometry(self: *RaylibBackend, texture: ?*anyopaque, vtx: []const dvui.vertex, idx: []const u32) void {
    //Not sure exactly how to handle this function
    //It would probably need to use the raylib RenderMesh() function

    if (texture == null) return;

    const ptr: *ray.RenderTexture = @ptrCast(texture.?);
    ray.BeginTextureMode(ptr.*);
    defer ray.EndTextureMode();
    //Render Geometry here

    _ = self; // autofix
    _ = vtx; // autofix
    _ = idx; // autofix

    //NOTE, the rendering here will be applied to the RenderTexture, but when does the RenderTexture get rendered
    //Should that be implemented in refresh()?

}

pub fn textureCreate(self: *RaylibBackend, pixels: [*]u8, width: u32, height: u32) *anyopaque {
    const texture = try self.arena.create(ray.RenderTexture);
    texture.* = ray.LoadRenderTexture(@intCast(width), @intCast(height));
    ray.UpdateTexture(texture.texture, pixels);
    return texture;
}

pub fn textureDestroy(self: *RaylibBackend, texture: *anyopaque) void {
    const ptr: *ray.RenderTexture = @ptrCast(texture);
    ray.UnloadRenderTexture(ptr.*);
    self.arena.destroy(ptr);
}

pub fn clipboardText(self: *RaylibBackend) error{outofmemory}![]const u8 {
    _ = self; // autofix
    return std.mem.sliceTo(ray.GetClipboardText(), 0);
}

pub fn clipboardTextSet(self: *RaylibBackend, text: []const u8) error{OutOfMemory}!void {
    //TODO can I free this memory??
    const c_text = try self.arena.dupeZ(u8, text);
    ray.SetClipboardText(c_text.ptr);
}

pub fn openURL(self: *RaylibBackend, url: []const u8) error{outofmemory}!void {
    const c_url = try self.arena.dupeZ(u8, url);
    ray.SetClipboardText(c_url.ptr);
}

pub fn refresh(self: *RaylibBackend) void {
    _ = self; // autofix
    ray.EndDrawing();
    ray.BeginDrawing();
}

pub fn backend(self: *RaylibBackend) dvui.Backend {
    return dvui.Backend.init(self, nanoTime, sleep, begin, end, pixelSize, windowSize, contentScale, renderGeometry, textureCreate, textureDestroy, clipboardText, clipboardTextSet, openURL, refresh);
}


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

pub fn init(options: InitOptions) !SDLBackend {
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

    var back = SDLBackend{ .window = window, .renderer = renderer };

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
