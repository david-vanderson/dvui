//! This is a testing backend that does no rendering at all intended for non graphical
//! dvui logic tests.

allocator: std.mem.Allocator,

arena: std.mem.Allocator = undefined,

size: dvui.Size,
size_pixels: dvui.Size.Physical,
time: i128 = 0,
clipboard: ?[]const u8 = null,

pub const kind: dvui.enums.Backend = .testing;

pub const TestingBackend = @This();
pub const Context = *TestingBackend;

pub const InitOptions = struct {
    allocator: std.mem.Allocator,
    size: dvui.Size,
    size_pixels: dvui.Size.Physical,
};

pub fn init(opts: InitOptions) TestingBackend {
    return .{
        .allocator = opts.allocator,
        .size = opts.size,
        .size_pixels = opts.size_pixels,
    };
}

pub fn deinit(self: *TestingBackend) void {
    if (self.clipboard) |text| {
        self.allocator.free(text);
    }
}

/// Get monotonic nanosecond timestamp. Doesn't have to be system time.
pub fn nanoTime(self: *TestingBackend) i128 {
    defer self.time += 1 * std.time.ns_per_ms; // arbitrary clock increment
    return self.time; // maybe should return static value?
}

/// Sleep for nanoseconds.
pub fn sleep(_: *TestingBackend, _: u64) void {}

/// Called by dvui during Window.begin(), so prior to any dvui
/// rendering.  Use to setup anything needed for this frame.  The arena
/// arg is cleared before begin is called next, useful for any temporary
/// allocations needed only for this frame.
pub fn begin(self: *TestingBackend, arena: std.mem.Allocator) void {
    self.arena = arena;
}

/// Called by dvui during Window.end(), but currently unused by any
/// backends.  Probably will be removed.
pub fn end(_: *TestingBackend) void {}

/// Return size of the window in physical pixels.  For a 300x200 retina
/// window (so actually 600x400), this should return 600x400.
pub fn pixelSize(self: *TestingBackend) dvui.Size.Physical {
    return self.size_pixels;
}

/// Return size of the window in logical pixels.  For a 300x200 retina
/// window (so actually 600x400), this should return 300x200.
pub fn windowSize(self: *TestingBackend) dvui.Size {
    return self.size;
}

/// Return the detected additional scaling.  This represents the user's
/// additional display scaling (usually set in their window system's
/// settings).  Currently only called during Window.init(), so currently
/// this sets the initial content scale.
pub fn contentScale(_: *TestingBackend) f32 {
    return 1;
}

/// Render a triangle list using the idx indexes into the vtx vertexes
/// clipped to to clipr (if given).  Vertex positions and clipr are in
/// physical pixels.  If texture is given, the vertexes uv coords are
/// normalized (0-1).
pub fn drawClippedTriangles(_: *TestingBackend, _: ?dvui.Texture, _: []const dvui.Vertex, _: []const u16, _: ?dvui.Rect.Physical) void {}

/// Create a texture from the given pixels in RGBA.  The returned
/// pointer is what will later be passed to drawClippedTriangles.
pub fn textureCreate(self: *TestingBackend, pixels: [*]u8, width: u32, height: u32, _: dvui.enums.TextureInterpolation) dvui.Texture {
    const new_pixels = self.allocator.dupe(u8, pixels[0 .. width * height * 4]) catch @panic("Couldn't create texture: OOM");
    return .{
        .width = width,
        .height = height,
        .ptr = new_pixels.ptr,
    };
}

/// Create a texture that can be rendered to with renderTarget().  The
/// returned pointer is what will later be passed to drawClippedTriangles.
pub fn textureCreateTarget(_: *TestingBackend, _: u32, _: u32, _: dvui.enums.TextureInterpolation) error{ OutOfMemory, TextureCreate }!dvui.TextureTarget {
    return error.TextureCreate;
}

/// Read pixel data (RGBA) from texture into pixel.
pub fn textureReadTarget(_: *TestingBackend, texture: dvui.TextureTarget, pixels: [*]u8) error{TextureRead}!void {
    const ptr: [*]const u8 = @ptrCast(texture.ptr);
    @memcpy(pixels, ptr[0..(texture.width * texture.height * 4)]);
}

/// Destroy texture that was previously made with textureCreate() or
/// textureFromTarget().  After this call, this texture pointer will not
/// be used by dvui.
pub fn textureDestroy(self: *TestingBackend, texture: dvui.Texture) void {
    const ptr: [*]const u8 = @ptrCast(texture.ptr);
    self.allocator.free(ptr[0..(texture.width * texture.height * 4)]);
}

pub fn textureFromTarget(_: *TestingBackend, texture: dvui.TextureTarget) dvui.Texture {
    return .{ .ptr = texture.ptr, .width = texture.width, .height = texture.height };
}

/// Render future drawClippedTriangles() to the passed texture (or screen
/// if null).
pub fn renderTarget(_: *TestingBackend, _: ?dvui.TextureTarget) void {}

/// Get clipboard content (text only)
pub fn clipboardText(self: *TestingBackend) error{OutOfMemory}![]const u8 {
    if (self.clipboard) |text| {
        return try self.arena.dupe(u8, text);
    } else {
        return "";
    }
}

/// Set clipboard content (text only)
pub fn clipboardTextSet(self: *TestingBackend, text: []const u8) error{OutOfMemory}!void {
    if (self.clipboard) |prev_text| {
        self.allocator.free(prev_text);
    }
    self.clipboard = try self.allocator.dupe(u8, text);
}

/// Open URL in system browser
pub fn openURL(_: *TestingBackend, _: []const u8) error{OutOfMemory}!void {}

/// Called by dvui.refresh() when it is called from a background
/// thread.  Used to wake up the gui thread.  It only has effect if you
/// are using waitTime() or some other method of waiting until a new
/// event comes in.
pub fn refresh(_: *TestingBackend) void {}

pub fn backend(self: *TestingBackend) dvui.Backend {
    return dvui.Backend.init(self, TestingBackend);
}

test {
    //std.debug.print("testing backend test\n", .{});
    std.testing.refAllDecls(@This());
}

pub const dvui = @import("dvui");
pub const std = @import("std");
