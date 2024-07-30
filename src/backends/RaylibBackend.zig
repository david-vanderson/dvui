pub const RaylibBackend = @This();
const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const ray = @cImport({
    @cInclude("raylib.h");
});

const conversion_factor = 1000000000.0;

initial_scale: f32 = 1.0,

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

pub fn begin(self: *RaylibBackend, arena: std.mem.allocator) void {
    _ = self; // autofix
    _ = arena; // autofix
    ray.BeginDrawing();
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
pub fn renderGeometry(self: *RaylibBackend, texture: ?*anyopaque, vtx: []const dvui.vertex, idx: []const u32) void {
    _ = self; // autofix
    _ = texture; // autofix
    _ = vtx; // autofix
    _ = idx; // autofix

}

//TODO implement
pub fn textureCreate(self: *RaylibBackend, pixels: [*]u8, width: u32, height: u32) *anyopaque {
    _ = self; // autofix
    _ = pixels; // autofix
    _ = width; // autofix
    _ = height; // autofix
}

pub fn textureDestroy(self: *RaylibBackend, texture: *anyopaque) void {
    _ = self; // autofix
    _ = texture; // autofix
}

pub fn clipboardText(self: *RaylibBackend) error{outofmemory}![]const u8 {
    _ = self; // autofix
    return std.mem.sliceTo(ray.GetClipboardText(), 0);
}

//TODO implement
pub fn clipboardTextSet(self: *RaylibBackend, text: []const u8) error{OutOfMemory}!void {
    _ = self; // autofix
    _ = text; // autofix

}

pub fn openURL(self: *RaylibBackend, url: []const u8) error{outofmemory}!void {
    _ = self; // autofix
    _ = url; // autofix
    //void OpenURL(const char *url);
}

pub fn refresh(self: *RaylibBackend) void {
    _ = self; // autofix

}

pub fn backend(self: *RaylibBackend) dvui.Backend {
    return dvui.Backend.init(self, nanoTime, sleep, begin, end, pixelSize, windowSize, contentScale, renderGeometry, textureCreate, textureDestroy, clipboardText, clipboardTextSet, openURL, refresh);
}
