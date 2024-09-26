const std = @import("std");
const dvui = @import("dvui.zig");

const Context = dvui.backend.Context;
const Size = dvui.Size;
const Vertex = dvui.Vertex;

const Backend = @This();

ctx: Context,
vtable: VTable,

const VTableTypes = struct {
    /// Get monotonic nanosecond timestamp. Doesn't have to be system time.
    pub const nanoTime = *const fn (ctx: Context) i128;

    /// Sleep for nanoseconds.
    pub const sleep = *const fn (ctx: Context, ns: u64) void;

    /// Called by dvui during Window.begin(), so prior to any dvui
    /// rendering.  Use to setup anything needed for this frame.  The arena
    /// arg is cleared before begin is called next, useful for any temporary
    /// allocations needed only for this frame.
    pub const begin = *const fn (ctx: Context, arena: std.mem.Allocator) void;

    /// Called by dvui during Window.end(), but currently unused by any
    /// backends.  Probably will be removed.
    pub const end = *const fn (ctx: Context) void;

    /// Return size of the window in physical pixels.  For a 300x200 retina
    /// window (so actually 600x400), this should return 600x400.
    pub const pixelSize = *const fn (ctx: Context) Size;

    /// Return size of the window in logical pixels.  For a 300x200 retina
    /// window (so actually 600x400), this should return 300x200.
    pub const windowSize = *const fn (ctx: Context) Size;

    /// Return the detected additional scaling.  This represents the user's
    /// additional display scaling (usually set in their window system's
    /// settings).  Currently only called during Window.init(), so currently
    /// this sets the initial content scale.
    pub const contentScale = *const fn (ctx: Context) f32;

    /// Render a triangle list using the idx indexes into the vtx vertexes
    /// clipped to to clipr.  Vertex positions and clipr are in physical
    /// pixels.  If texture is given, the vertexes uv coords are normalized
    /// (0-1).
    pub const drawClippedTriangles = *const fn (ctx: Context, texture: ?*anyopaque, vtx: []const Vertex, idx: []const u16, clipr: dvui.Rect) void;

    /// Create a texture from the given pixels in RGBA.  The returned
    /// pointer is what will later be passed to drawClippedTriangles.
    pub const textureCreate = *const fn (ctx: Context, pixels: [*]u8, width: u32, height: u32) *anyopaque;

    /// Destroy texture that was previously made with textureCreate.  After
    /// this call, this texture pointer will not be used by dvui.
    pub const textureDestroy = *const fn (ctx: Context, texture: *anyopaque) void;

    /// Get clipboard content (text only)
    pub const clipboardText = *const fn (ctx: Context) error{OutOfMemory}![]const u8;

    /// Set clipboard content (text only)
    pub const clipboardTextSet = *const fn (ctx: Context, text: []const u8) error{OutOfMemory}!void;

    /// Open URL in system browser
    pub const openURL = *const fn (ctx: Context, url: []const u8) error{OutOfMemory}!void;

    /// Called by dvui.refresh() when it is called from a background
    /// thread.  Used to wake up the gui thread.  It only has effect if you
    /// are using waitTime() or some other method of waiting until a new
    /// event comes in.
    pub const refresh = *const fn (ctx: Context) void;
};

pub const VTable = struct {
    pub const I = VTableTypes;

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

/// Create backend (vtable) from implementation
///
/// `impl`: the implementation struct. it should have declarations that match `VTableTypes`
pub fn init(
    ctx: Context,
    comptime implementation: anytype,
) Backend {
    const I = VTableTypes;

    compile_assert(
        @sizeOf(Context) == @sizeOf(usize),
        "(@TypeOf(ctx)) " ++ @typeName(Context) ++ " must be a pointer-sized; has size of " ++ std.fmt.comptimePrint("{d}", .{@sizeOf(Context)}),
    ); // calling convention dictates that any type can work here after converted to usize

    comptime var vtable: VTable = undefined;

    inline for (@typeInfo(I).Struct.decls) |decl| {
        const hasField = @hasDecl(implementation, decl.name);
        const DeclType = @field(I, decl.name);
        compile_assert(hasField, "Backend type " ++ @typeName(implementation) ++ " has no declaration '" ++ decl.name ++ ": " ++ @typeName(DeclType) ++ "'");
        const f: DeclType = &@field(implementation, decl.name);
        @field(vtable, decl.name) = @ptrCast(f);
    }

    return .{
        .ctx = ctx,
        .vtable = vtable,
    };
}

pub fn nanoTime(self: *Backend) i128 {
    return self.vtable.nanoTime(self.ctx);
}
pub fn sleep(self: *Backend, ns: u64) void {
    return self.vtable.sleep(self.ctx, ns);
}
pub fn begin(self: *Backend, arena: std.mem.Allocator) void {
    return self.vtable.begin(self.ctx, arena);
}
pub fn end(self: *Backend) void {
    return self.vtable.end(self.ctx);
}
pub fn pixelSize(self: *Backend) Size {
    return self.vtable.pixelSize(self.ctx);
}
pub fn windowSize(self: *Backend) Size {
    return self.vtable.windowSize(self.ctx);
}
pub fn contentScale(self: *Backend) f32 {
    return self.vtable.contentScale(self.ctx);
}
pub fn drawClippedTriangles(self: *Backend, texture: ?*anyopaque, vtx: []const Vertex, idx: []const u16, clipr: dvui.Rect) void {
    return self.vtable.drawClippedTriangles(self.ctx, texture, vtx, idx, clipr);
}
pub fn textureCreate(self: *Backend, pixels: [*]u8, width: u32, height: u32) *anyopaque {
    return self.vtable.textureCreate(self.ctx, pixels, width, height);
}
pub fn textureDestroy(self: *Backend, texture: *anyopaque) void {
    return self.vtable.textureDestroy(self.ctx, texture);
}
pub fn clipboardText(self: *Backend) error{OutOfMemory}![]const u8 {
    return self.vtable.clipboardText(self.ctx);
}
pub fn clipboardTextSet(self: *Backend, text: []const u8) error{OutOfMemory}!void {
    return self.vtable.clipboardTextSet(self.ctx, text);
}
pub fn openURL(self: *Backend, url: []const u8) error{OutOfMemory}!void {
    return self.vtable.openURL(self.ctx, url);
}
pub fn refresh(self: *Backend) void {
    return self.vtable.refresh(self.ctx);
}
