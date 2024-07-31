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
    ray.BeginDrawing();
    _ = self; // autofix
    _ = arena; // autofix
}

pub fn end(self: *RaylibBackend) void {
    _ = self; // autofix
    ray.EndDrawing();
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
pub fn renderGeometry(self: *RaylibBackend, texture: ?*anyopaque, vtx: []const dvui.Vertex, idx: []const u32) void {
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

pub fn clipboardText(self: *RaylibBackend) error{OutOfMemory}![]const u8 {
    _ = self; // autofix
    return std.mem.sliceTo(ray.GetClipboardText(), 0);
}

pub fn clipboardTextSet(self: *RaylibBackend, text: []const u8) error{OutOfMemory}!void {
    //TODO can I free this memory??
    const c_text = try self.arena.dupeZ(u8, text);
    ray.SetClipboardText(c_text.ptr);
}

pub fn openURL(self: *RaylibBackend, url: []const u8) error{OutOfMemory}!void {
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

pub fn init(options: InitOptions) !RaylibBackend {
    ray.SetConfigFlags(ray.FLAG_WINDOW_RESIZABLE);
    if (options.vsync) {
        ray.SetConfigFlags(ray.FLAG_VSYNC_HINT);
    }
    ray.InitWindow(@intFromFloat(options.size.w), @intFromFloat(options.size.h), options.title);

    if (options.min_size) |min| {
        ray.SetWindowMinSize(min.intWidth(), min.intHeight());
    }
    if (options.max_size) |max| {
        ray.SetWindowMinSize(max.intWidth(), max.intHeight());
    }

    //TODO implement icon
    return RaylibBackend{
        .initial_scale = 1.0,
        .arena = options.allocator,
    };
}

pub fn deinit(self: *RaylibBackend) void {
    _ = self; // autofix
    ray.CloseWindow();
}

pub fn setIconFromFileContent(self: *RaylibBackend, file_content: []const u8) void {
    _ = self; // autofix
    _ = file_content; // autofix
    //TODO implement
}

pub fn hasEvent(self: *RaylibBackend) bool {
    _ = self; // autofix
}

pub fn clear(self: *RaylibBackend) bool {
    _ = self; // autofix
}
