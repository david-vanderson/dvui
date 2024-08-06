const std = @import("std");
const dvui = @import("dvui.zig");

const Size = dvui.Size;
const Vertex = dvui.Vertex;

const Backend = @This();

ptr: *anyopaque,
vtable: VTable,

pub fn VTableTypes(comptime Ptr: type) type {
    return struct {

        /// Get monotonic nanosecond timestamp. Doesn't have to be system time.
        pub const nanoTime = *const fn (ptr: Ptr) i128;

        /// Sleep for nanoseconds.
        pub const sleep = *const fn (ptr: Ptr, ns: u64) void;

	/// Called by dvui during Window.begin(), so prior to any dvui
	/// rendering.  Use to setup anything needed for this frame.  The arena
	/// arg is cleared before begin is called next, useful for any temporary
	/// allocations needed only for this frame.
        pub const begin = *const fn (ptr: Ptr, arena: std.mem.Allocator) void;

        /// Called by dvui during Window.end(), but currently unused by any
	/// backends.  Probably will be removed.
        pub const end = *const fn (ptr: Ptr) void;

	/// Return size of the window in physical pixels.  For a 300x200 retina
	/// window (so actually 600x400), this should return 600x400.
        pub const pixelSize = *const fn (ptr: Ptr) Size;

	/// Return size of the window in logical pixels.  For a 300x200 retina
	/// window (so actually 600x400), this should return 300x200.
        pub const windowSize = *const fn (ptr: Ptr) Size;

	/// Return the detected additional scaling.  This represents the user's
	/// additional display scaling (usually set in their window system's
	/// settings).  Currently only called during Window.init(), so currently
	/// this sets the initial content scale.
        pub const contentScale = *const fn (ptr: Ptr) f32;

	/// Render a triangle list using the idx indexes into the vtx vertexes
	/// clipped to to clipr.  Vertex positions and clipr are in physical
	/// pixels.  If texture is given, the vertexes uv coords are normalized
	/// (0-1).
        pub const drawClippedTriangles = *const fn (ptr: Ptr, texture: ?*anyopaque, vtx: []const Vertex, idx: []const u32, clipr: dvui.Rect) void;

	/// Create a texture from the given pixels in RGBA.  The returned
	/// pointer is what will later be passed to drawClippedTriangles.
        pub const textureCreate = *const fn (ptr: Ptr, pixels: [*]u8, width: u32, height: u32) *anyopaque;

	/// Destroy texture that was previously made with textureCreate.  After
	/// this call, this texture pointer will not be used by dvui.
        pub const textureDestroy = *const fn (ptr: Ptr, texture: *anyopaque) void;

        /// Get clipboard content (text only)
        pub const clipboardText = *const fn (ptr: Ptr) error{OutOfMemory}![]const u8;

        /// Set clipboard content (text only)
        pub const clipboardTextSet = *const fn (ptr: Ptr, text: []const u8) error{OutOfMemory}!void;

        /// Open URL in system browser
        pub const openURL = *const fn (ptr: Ptr, url: []const u8) error{OutOfMemory}!void;

	/// Called by dvui.refresh() when it is called from a background
	/// thread.  Used to wake up the gui thread.  It only has effect if you
	/// are using waitTime() or some other method of waiting until a new
	/// event comes in.
        pub const refresh = *const fn (ptr: Ptr) void;
    };
}

pub const VTable = struct {
    pub const I = VTableTypes(*anyopaque);

    nanoTime: I.nanoTime,
    sleep: I.sleep,
    begin: I.begin,
    end: I.end,
    pixelSize: I.pixelSize,
    windowSize: I.windowSize,
    contentScale: I.contentScale,
    drawClippedTriangles: I.drawClippedTriangles,
    textureCreate: I.textureCreate,
    textureDestroy: I.textureDestroy,
    clipboardText: I.clipboardText,
    clipboardTextSet: I.clipboardTextSet,
    openURL: I.openURL,
    refresh: I.refresh,
};

fn compile_assert(comptime x: bool, comptime msg: []const u8) void {
    if (!x) @compileError(msg);
}

pub fn init(
    pointer: anytype,
    comptime Interface: anytype,
) Backend {
    const Ptr = @TypeOf(pointer);
    const I = VTableTypes(Ptr);

    compile_assert(@sizeOf(Ptr) == @sizeOf(usize), "Must be a pointer-sized"); // calling convention dictates that any type can work here after converted to *anyopaque

    comptime var vtable: VTable = undefined;

    inline for (@typeInfo(I).Struct.decls) |decl| {
        const hasField = @hasDecl(Interface, decl.name);
        const DeclType = @field(I, decl.name);
        compile_assert(hasField, "Backend type " ++ @typeName(Interface) ++ " has no declaration '" ++ decl.name ++ ": " ++ @typeName(DeclType) ++ "'");
        const f: DeclType = &@field(Interface, decl.name);
        @field(vtable, decl.name) = @ptrCast(f);
    }

    return .{
        .ptr = pointer,
        .vtable = vtable,
    };
}

pub fn nanoTime(self: *Backend) i128 {
    return self.vtable.nanoTime(self.ptr);
}
pub fn sleep(self: *Backend, ns: u64) void {
    return self.vtable.sleep(self.ptr, ns);
}
pub fn begin(self: *Backend, arena: std.mem.Allocator) void {
    return self.vtable.begin(self.ptr, arena);
}
pub fn end(self: *Backend) void {
    return self.vtable.end(self.ptr);
}
pub fn pixelSize(self: *Backend) Size {
    return self.vtable.pixelSize(self.ptr);
}
pub fn windowSize(self: *Backend) Size {
    return self.vtable.windowSize(self.ptr);
}
pub fn contentScale(self: *Backend) f32 {
    return self.vtable.contentScale(self.ptr);
}
pub fn drawClippedTriangles(self: *Backend, texture: ?*anyopaque, vtx: []const Vertex, idx: []const u32, clipr: dvui.Rect) void {
    return self.vtable.drawClippedTriangles(self.ptr, texture, vtx, idx, clipr);
}
pub fn textureCreate(self: *Backend, pixels: [*]u8, width: u32, height: u32) *anyopaque {
    return self.vtable.textureCreate(self.ptr, pixels, width, height);
}
pub fn textureDestroy(self: *Backend, texture: *anyopaque) void {
    return self.vtable.textureDestroy(self.ptr, texture);
}
pub fn clipboardText(self: *Backend) error{OutOfMemory}![]const u8 {
    return self.vtable.clipboardText(self.ptr);
}
pub fn clipboardTextSet(self: *Backend, text: []const u8) error{OutOfMemory}!void {
    return self.vtable.clipboardTextSet(self.ptr, text);
}
pub fn openURL(self: *Backend, url: []const u8) error{OutOfMemory}!void {
    return self.vtable.openURL(self.ptr, url);
}
pub fn refresh(self: *Backend) void {
    return self.vtable.refresh(self.ptr);
}
