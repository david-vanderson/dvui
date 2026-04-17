//! Provides a consistent API for interacting with the backend

const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui.zig");

const Implementation = @import("backend");
const Backend = @This();

pub const Common = @import("backends/common.zig");

pub const GenericError = std.mem.Allocator.Error || error{BackendError};
pub const TextureError = GenericError || error{ TextureCreate, TextureRead, TextureUpdate, NotImplemented };

/// The current implementation used
pub const kind = Implementation.kind;

impl: *Implementation,
render_impl: if (dvui.render_backend.kind == .default) void else *dvui.render_backend,

pub const init = if (dvui.render_backend.kind == .default) initDefault else initRenderer;

fn initDefault(impl: *Implementation) Backend {
    return .{ .impl = impl, .render_impl = {} };
}

fn initRenderer(impl: *Implementation, render_impl: *dvui.render_backend) Backend {
    return .{ .impl = impl, .render_impl = render_impl };
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
    try self.impl.begin(arena);
    if (dvui.render_backend.kind != .default) try self.render_impl.begin(arena);
}

/// Called during `dvui.Window.end` before freeing any memory for the current frame.
pub fn end(self: Backend) GenericError!void {
    if (dvui.render_backend.kind != .default) try self.render_impl.end();
    try self.impl.end();
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
/// normalized (0-1). `clipr` (if given) has whole pixel values.
pub fn drawClippedTriangles(self: Backend, texture: ?dvui.Texture, vtx: []const dvui.Vertex, idx: []const dvui.Vertex.Index, clipr: ?dvui.Rect.Physical) GenericError!void {
    if (dvui.render_backend.kind == .default) {
        try self.impl.drawClippedTriangles(texture, vtx, idx, clipr);
    } else {
        try self.renderer().drawClippedTriangles(self.impl.pixelSize(), texture, vtx, idx, clipr);
    }
}

/// Create a `dvui.Texture` from premultiplied alpha `pixels` in RGBA.  The
/// returned pointer is what will later be passed to `drawClippedTriangles`.
pub fn textureCreate(self: Backend, pixels: [*]const u8, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation, format: dvui.enums.TexturePixelFormat) TextureError!dvui.Texture {
    return self.renderer().textureCreate(pixels, width, height, interpolation, format);
}

/// Update a `dvui.Texture` from premultiplied alpha `pixels` in RGBA.  The
/// passed in texture must be created  with textureCreate
pub fn textureUpdate(self: Backend, texture: dvui.Texture, pixels: [*]const u8) TextureError!void {
    // we can handle backends that dont support textureUpdate by using destroy and create again!
    if (comptime !@hasDecl(@TypeOf(self.renderer().*), "textureUpdate")) return TextureError.NotImplemented else {
        return self.renderer().textureUpdate(texture, pixels);
    }
}

/// Update a sub-rectangle of a `dvui.Texture` from premultiplied alpha
/// `pixels`. The pixel pointer must point to the start of the full texture
/// row that contains the sub-rect (i.e. same pointer as full update, with
/// pitch = texture.width * bpp). The backend reads only the rows/columns
/// within the given rect.
pub fn textureUpdateSubRect(self: Backend, texture: dvui.Texture, pixels: [*]const u8, x: u32, y: u32, w: u32, h: u32) TextureError!void {
    if (comptime !@hasDecl(Implementation, "textureUpdateSubRect")) return TextureError.NotImplemented else {
        return self.impl.textureUpdateSubRect(texture, pixels, x, y, w, h);
    }
}

/// Destroy `texture` made with `textureCreate`. After this call, this texture
/// pointer will not be used by dvui.
pub fn textureDestroy(self: Backend, texture: dvui.Texture) void {
    // std.debug.print("destroy ptr {} w: {}, h:{}\n", .{ @intFromPtr(texture.ptr), texture.width, texture.height });
    return self.renderer().textureDestroy(texture);
}

/// Create a `dvui.Texture` that can be rendered to with `renderTarget`.  The
/// returned pointer is what will later be passed to `drawClippedTriangles`.
pub fn textureCreateTarget(self: Backend, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation, format: dvui.enums.TexturePixelFormat) TextureError!dvui.TextureTarget {
    return self.renderer().textureCreateTarget(width, height, interpolation, format);
}

/// Read pixel data (RGBA) from `texture` into `pixels_out`.
pub fn textureReadTarget(self: Backend, texture: dvui.TextureTarget, pixels_out: [*]u8) TextureError!void {
    return self.renderer().textureReadTarget(texture, pixels_out);
}

/// Destroy `texture` made with `Target.Create`. After this call, this texture
/// pointer will not be used by dvui.
pub fn textureClearTarget(self: Backend, texture: dvui.Texture.Target) void {
    return self.renderer().textureClearTarget(texture);
}

/// Destroy `texture` made with `Target.Create`. After this call, this texture
/// pointer will not be used by dvui.
pub fn textureDestroyTarget(self: Backend, texture: dvui.Texture.Target) void {
    return self.renderer().textureDestroyTarget(texture);
}

/// Convert `target` made with `textureCreateTarget` into return texture
/// as if made by `textureCreate`.  target will be destroyed.
pub fn textureFromTarget(self: Backend, target: dvui.TextureTarget) TextureError!dvui.Texture {
    return self.renderer().textureFromTarget(target);
}

/// Get a temporary drawable texture from this target, as if made by
/// `textureCreate` and then passed to `textureDestroyLater`.  target is not
/// destroyed.
pub fn textureFromTargetTemp(self: Backend, target: dvui.TextureTarget) TextureError!dvui.Texture {
    return self.renderer().textureFromTargetTemp(target);
}

/// Render future `drawClippedTriangles` to the passed `texture` (or screen
/// if null).
pub fn renderTarget(self: Backend, texture: ?dvui.TextureTarget) GenericError!void {
    return self.renderer().renderTarget(texture);
}

fn renderer(self: Backend) if (dvui.render_backend.kind == .default) *Implementation else *dvui.render_backend {
    return if (dvui.render_backend.kind == .default)
        self.impl
    else
        self.render_impl;
}

/// Get clipboard content (text only)
pub fn clipboardText(self: Backend) GenericError![]const u8 {
    return try self.impl.clipboardText();
}

/// Set clipboard content (text only)
pub fn clipboardTextSet(self: Backend, text: []const u8) GenericError!void {
    return self.impl.clipboardTextSet(text);
}

/// Open URL in system browser.  If using the web backend, new_window controls
/// whether to navigate the current page to the url or open in a new window/tab.
pub fn openURL(self: Backend, url: []const u8, new_window: bool) GenericError!void {
    return self.impl.openURL(url, new_window);
}

/// Get the preferredColorScheme if available
pub fn preferredColorScheme(self: Backend) ?dvui.enums.ColorScheme {
    return self.impl.preferredColorScheme();
}

/// Get the prefersReducedMotion if available
pub fn prefersReducedMotion(self: Backend) bool {
    return self.impl.prefersReducedMotion();
}

/// Called by `dvui.refresh` when it is called from a background
/// thread.  Used to wake up the gui thread.  It only has effect if you
/// are using `dvui.Window.waitTime` or some other method of waiting until
/// a new event comes in.
pub fn refresh(self: Backend) void {
    return self.impl.refresh();
}

/// Initialize accessKit from `Window.begin`. Returns `true` if access kit was initialized
// NOTE: Also requires `pub fn accessKitShouldInitialize(self) bool` to be implemented
pub fn accessKitInitInBegin(self: Backend, accessKit: *dvui.AccessKit) GenericError!void {
    if (!dvui.accesskit_enabled or !@hasDecl(Implementation, "accessKitShouldInitialize")) return;
    if (self.impl.accessKitShouldInitialize()) {
        accessKit.initialize();
        try self.impl.accessKitInitInBegin();
    }
}

pub fn native(self: Backend, window: *dvui.Window) dvui.Window.Native {
    if (comptime !@hasDecl(Implementation, "native")) {
        return switch (builtin.os.tag) {
            .windows => .{ .hwnd = null },
            .macos => .{ .cocoa_window = null },
            else => {},
        };
    } else {
        return self.impl.native(window);
    }
}

test {
    @import("std").testing.refAllDecls(@This());
}
