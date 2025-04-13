const Self = @This();

window: *dvui.Window,
backend: *Backend,
frameFn: *const fn () anyerror!void,

time_ns: i128 = 0,
rendering_disabled: bool = true,

named_widgets: std.AutoHashMap(u32, WidgetInfo),

pub const WidgetInfo = struct {
    /// The Widget data is guaranteed to have the rect_scale_cache populated.
    ///
    /// IMPORTANT: All functions that interact with the window and parent widget are invalid to call!
    // we store WidgetData directly to use its logic for rect sizing
    wd: dvui.WidgetData,
    visible: bool,
};

pub fn init(window: *dvui.Window, backend: *Backend, frameFn: *const fn () anyerror!void) Self {
    return .{
        .window = window,
        .backend = backend,
        .frameFn = frameFn,
        .named_widgets = .init(window.gpa),
    };
}

pub fn deinit(self: *Self) void {
    self.named_widgets.deinit();
}

pub fn registerWidgetData(self: *Self, wd: *const dvui.WidgetData) !void {
    if (wd.options.test_id) |test_id| {
        const hashed_id = dvui.hashIdKey(@intCast(wd.options.idExtra()), test_id);
        const prev_entry = try self.named_widgets.fetchPut(hashed_id, .{
            .wd = wd.*,
            .visible = wd.visible(),
        });
        if (prev_entry != null) {
            dvui.log.err("Duplicate entry for test_id '{s}' ({?d})", .{
                test_id,
                wd.options.id_extra,
            });
        }
    }
}

pub fn getWidgetInfo(self: *Self, test_id: []const u8, id_extra: ?u32) !*const WidgetInfo {
    const hashed_id = dvui.hashIdKey(id_extra orelse 0, test_id);
    return self.named_widgets.getPtr(hashed_id) orelse return error.NamedWidgetDidNotExist;
}

pub fn run(self: *Self) !void {
    defer self.time_ns += 1000 * std.time.ns_per_ms; // Move time really fast to finish animations quicker

    self.window.runner = self;
    defer self.window.runner = null;

    var i: usize = 0;
    // 0 indicates that dvui want to render as fast as possible
    var wait_time: ?u32 = 0;
    while (wait_time == 0 and i < 100) : (i += 1) {
        self.named_widgets.clearRetainingCapacity();
        try self.window.begin(self.time_ns);
        try self.frameFn();
        wait_time = try self.window.end(.{});
    }
    //std.debug.print("Run exited with i {d}\n", .{i});
}

pub const Frame = struct {
    /// pixel array in RGBA
    pixels: []u8,
    width: usize,
    height: usize,

    pub fn deinit(self: Frame, allocator: std.mem.Allocator) void {
        allocator.free(self.pixels);
    }
};

pub const PngFrame = struct {
    data: []u8,

    pub fn deinit(self: PngFrame) void {
        dvui.c.free(self.data.ptr);
    }
};

/// Captures one frame without incrementing the "time" of the application
pub fn capturePng(self: *Self) !PngFrame {
    const frame = try self.captureFrame(self.window.arena());
    defer frame.deinit(self.window.arena());

    var len: c_int = undefined;
    const png_bytes = dvui.c.stbi_write_png_to_mem(frame.pixels.ptr, @intCast(frame.width * 4), @intCast(frame.width), @intCast(frame.height), 4, &len);

    return .{ .data = png_bytes[0..@intCast(len)] };
}

/// Captures one frame without incrementing the "time" of the application
pub fn captureFrame(self: *Self, allocator: std.mem.Allocator) !Frame {
    comptime if (!@hasDecl(Backend, "SDLBackend")) {
        @compileError("Runner can only capture frames when using the SDL backend");
    };

    _ = Backend.c.SDL_SetRenderDrawColor(self.backend.renderer, 0, 0, 0, 255);
    _ = Backend.c.SDL_RenderClear(self.backend.renderer);

    self.rendering_disabled = false;
    defer self.rendering_disabled = true;
    // still install runner incase the window were to change during this frame
    self.window.runner = self;
    defer self.window.runner = null;
    self.named_widgets.clearRetainingCapacity();

    // run one frame
    try self.window.begin(self.time_ns);
    try self.frameFn();
    _ = try self.window.end(.{});

    const width: usize = @intFromFloat(self.window.clipRect.w);
    const height: usize = @intFromFloat(self.window.clipRect.h);
    const pixel_buf = try allocator.alloc(u8, width * height * 4);
    try self.readWindowPixels(width, height, pixel_buf.ptr);

    return .{
        .pixels = pixel_buf,
        .width = width,
        .height = height,
    };
}

fn readWindowPixels(self: *Self, width: usize, height: usize, pixels_out: [*]u8) !void {
    const c = Backend.c;

    if (Backend.sdl3) {
        var surface: *c.SDL_Surface = c.SDL_RenderReadPixels(self.backend.renderer, null) orelse return error.TextureRead;
        defer c.SDL_DestroySurface(surface);
        if (width * height != surface.*.w * surface.*.h) return error.TextureRead;
        // TODO: most common format is RGBA8888, doing conversion during copy to pixels_out should be faster
        if (surface.*.format != c.SDL_PIXELFORMAT_ABGR8888) {
            surface = c.SDL_ConvertSurface(surface, c.SDL_PIXELFORMAT_ABGR8888) orelse return error.TextureRead;
        }
        @memcpy(pixels_out[0 .. width * height * 4], @as(?[*]u8, @ptrCast(surface.*.pixels)).?[0 .. width * height * 4]);
        return;
    }

    // If SDL picks directX11 as a rendering backend, it could not support
    // SDL_PIXELFORMAT_ABGR8888 so this works around that.  For some reason sdl
    // crashes if we ask it to do the conversion for us.
    var swap_rb = true;
    var info: c.SDL_RendererInfo = undefined;
    _ = c.SDL_GetRendererInfo(self.backend.renderer, &info);
    //std.debug.print("renderer name {s} formats:\n", .{info.name});
    for (0..info.num_texture_formats) |i| {
        //std.debug.print("  {s}\n", .{c.SDL_GetPixelFormatName(info.texture_formats[i])});
        if (info.texture_formats[i] == c.SDL_PIXELFORMAT_ABGR8888) {
            swap_rb = false;
        }
    }

    _ = c.SDL_RenderReadPixels(self.backend.renderer, null, if (swap_rb) c.SDL_PIXELFORMAT_ARGB8888 else c.SDL_PIXELFORMAT_ABGR8888, pixels_out, @intCast(width * 4));

    if (swap_rb) {
        for (0..width * height) |i| {
            const r = pixels_out[i * 4 + 0];
            const b = pixels_out[i * 4 + 2];
            pixels_out[i * 4 + 0] = b;
            pixels_out[i * 4 + 2] = r;
        }
    }
}

// Adds a position event to move the mouse over the widget
fn moveToWidgetInfo(self: *Self, info: *const WidgetInfo) !void {
    if (!info.visible) return error.WidgetNotVisible;
    const center = info.wd.rect.topLeft().plus(.{ .x = info.wd.rect.w / 2, .y = info.wd.rect.h / 2 });
    try self.moveMouseTo(center);
}

pub fn clickWidget(self: *Self, test_id: []const u8, id_extra: ?u32) !void {
    try self.moveToWidgetInfo(try self.getWidgetInfo(test_id, id_extra));
    try self.mouseClick(.left);
}

/// Moves the mouse pointer to the center of the widget
pub fn moveToWidget(self: *Self, test_id: []const u8, id_extra: ?u32) !void {
    try self.moveToWidgetInfo(try self.getWidgetInfo(test_id, id_extra));
}

/// Moves the mouse to the provided absolute position
pub fn moveMouseTo(self: *Self, point: dvui.Point) !void {
    const movement = point.diff(self.window.mouse_pt);
    std.debug.print("Moving {}", .{movement});
    if (movement.nonZero()) {
        _ = try self.window.addEventMouseMotion(movement.x, movement.y);
    }
}

pub fn mouseClick(self: *Self, b: dvui.enums.Button) !void {
    _ = try self.window.addEventMouseButton(b, .press);
    _ = try self.window.addEventMouseButton(b, .release);
}

pub fn pressKey(self: *Self, code: dvui.enums.Key, mod: dvui.enums.Mod) !void {
    _ = try self.window.addEventKey(.{ .code = code, .mod = mod, .action = .down });
    _ = try self.window.addEventKey(.{ .code = code, .mod = mod, .action = .up });
}

pub fn writeText(self: *Self, text: []const u8) !void {
    _ = try self.window.addEventText(text);
}

const std = @import("std");
const dvui = @import("dvui.zig");
const Backend = dvui.backend;
