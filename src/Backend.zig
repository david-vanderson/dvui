//! Provides a consistent API for interacting with the backend

const std = @import("std");
const dvui = @import("dvui.zig");

const Implementation = @import("backend");
const Backend = @This();

pub const Common = @import("backends/common.zig");

pub const GenericError = std.mem.Allocator.Error || error{BackendError};
pub const TextureError = GenericError || error{ TextureCreate, TextureRead, TextureUpdate, NotImplemented };

/// The current implementation used
pub const kind = Implementation.kind;

impl: *Implementation,

pub fn init(impl: *Implementation) Backend {
    return .{ .impl = impl };
}

/// Get monotonic nanosecond timestamp. Doesn't have to be system time.
pub fn nanoTime(self: Backend) i128 {
    return self.impl.nanoTime();
}
/// Sleep for nanoseconds.
pub fn sleep(self: Backend, ns: u64) void {
    return self.impl.sleep(ns);
}
/// Called by dvui during `dvui.Window.begin`, so prior to any dvui
/// rendering.  Use to setup anything needed for this frame.  The arena
/// arg is cleared before `dvui.Window.begin` is called next, useful for any
/// temporary allocations needed only for this frame.
pub fn begin(self: Backend, arena: std.mem.Allocator) GenericError!void {
    return self.impl.begin(arena);
}

/// Called during `dvui.Window.end` before freeing any memory for the current frame.
pub fn end(self: Backend) GenericError!void {
    return self.impl.end();
}

/// Return size of the window in physical pixels.  For a 300x200 retina
/// window (so actually 600x400), this should return 600x400.
pub fn pixelSize(self: Backend) dvui.Size.Physical {
    return self.impl.pixelSize();
}

/// Return size of the window in logical pixels.  For a 300x200 retina
/// window (so actually 600x400), this should return 300x200.
pub fn windowSize(self: Backend) dvui.Size.Natural {
    return self.impl.windowSize();
}

/// Return the detected additional scaling.  This represents the user's
/// additional display scaling (usually set in their window system's
/// settings).  Currently only called during `dvui.Window.init`, so currently
/// this sets the initial content scale.
pub fn contentScale(self: Backend) f32 {
    return self.impl.contentScale();
}

/// Render a triangle list using the idx indexes into the vtx vertexes
/// clipped to to `clipr` (if given).  Vertex positions and `clipr` are in
/// physical pixels.  If `texture` is given, the vertexes uv coords are
/// normalized (0-1).
pub fn drawClippedTriangles(self: Backend, texture: ?dvui.Texture, vtx: []const dvui.Vertex, idx: []const u16, clipr: ?dvui.Rect.Physical) GenericError!void {
    return self.impl.drawClippedTriangles(texture, vtx, idx, clipr);
}

/// Create a `dvui.Texture` from premultiplied alpha `pixels` in RGBA.  The
/// returned pointer is what will later be passed to `drawClippedTriangles`.
pub fn textureCreate(self: Backend, pixels: [*]const u8, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) TextureError!dvui.Texture {
    return self.impl.textureCreate(pixels, width, height, interpolation);
}

/// Update a `dvui.Texture` from premultiplied alpha `pixels` in RGBA.  The
/// passed in texture must be created  with textureCreate
pub fn textureUpdate(self: Backend, texture: dvui.Texture, pixels: [*]const u8) TextureError!void {
    // we can handle backends that dont support textureUpdate by using destroy and create again!
    if (comptime !@hasDecl(Implementation, "textureUpdate")) return TextureError.NotImplemented else {
        return self.impl.textureUpdate(texture, pixels);
    }
}

/// Destroy `texture` made with `textureCreate`. After this call, this texture
/// pointer will not be used by dvui.
pub fn textureDestroy(self: Backend, texture: dvui.Texture) void {
    // std.debug.print("destroy ptr {} w: {}, h:{}\n", .{ @intFromPtr(texture.ptr), texture.width, texture.height });
    return self.impl.textureDestroy(texture);
}

/// Create a `dvui.Texture` that can be rendered to with `renderTarget`.  The
/// returned pointer is what will later be passed to `drawClippedTriangles`.
pub fn textureCreateTarget(self: Backend, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) TextureError!dvui.TextureTarget {
    return self.impl.textureCreateTarget(width, height, interpolation);
}

/// Read pixel data (RGBA) from `texture` into `pixels_out`.
pub fn textureReadTarget(self: Backend, texture: dvui.TextureTarget, pixels_out: [*]u8) TextureError!void {
    return self.impl.textureReadTarget(texture, pixels_out);
}

/// Convert texture target made with `textureCreateTarget` into return texture
/// as if made by `textureCreate`.  After this call, texture target will not be
/// used by dvui.
pub fn textureFromTarget(self: Backend, texture: dvui.TextureTarget) TextureError!dvui.Texture {
    return self.impl.textureFromTarget(texture);
}

/// Render future `drawClippedTriangles` to the passed `texture` (or screen
/// if null).
pub fn renderTarget(self: Backend, texture: ?dvui.TextureTarget) GenericError!void {
    return self.impl.renderTarget(texture);
}

/// Get clipboard content (text only)
pub fn clipboardText(self: Backend) GenericError![]const u8 {
    return try self.impl.clipboardText();
}

/// Set clipboard content (text only)
pub fn clipboardTextSet(self: Backend, text: []const u8) GenericError!void {
    return self.impl.clipboardTextSet(text);
}

/// Open URL in system browser
pub fn openURL(self: Backend, url: []const u8) GenericError!void {
    return self.impl.openURL(url);
}

/// Get the preferredColorScheme if available
pub fn preferredColorScheme(self: Backend) ?dvui.enums.ColorScheme {
    return self.impl.preferredColorScheme();
}

/// Show/hide the cursor.
///
/// Returns the previous state of the cursor, `true` meaning shown
pub fn cursorShow(self: Backend, value: ?bool) GenericError!bool {
    return self.impl.cursorShow(value);
}

/// Called by `dvui.refresh` when it is called from a background
/// thread.  Used to wake up the gui thread.  It only has effect if you
/// are using `dvui.Window.waitTime` or some other method of waiting until
/// a new event comes in.
pub fn refresh(self: Backend) void {
    return self.impl.refresh();
}

test {
    @import("std").testing.refAllDecls(@This());
}
