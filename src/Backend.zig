const std = @import("std");
const dvui = @import("dvui.zig");

const Context = dvui.backend.Context;
const Backend = @This();

ctx: Context,
vtable: VTable,

const VTableTypes = struct {
    pub const nanoTime = *const fn (ctx: Context) i128;
    pub const sleep = *const fn (ctx: Context, ns: u64) void;

    pub const begin = *const fn (ctx: Context, arena: std.mem.Allocator) void;
    pub const end = *const fn (ctx: Context) void;

    pub const pixelSize = *const fn (ctx: Context) dvui.Size.Physical;
    pub const windowSize = *const fn (ctx: Context) dvui.Size;
    pub const contentScale = *const fn (ctx: Context) f32;

    pub const drawClippedTriangles = *const fn (ctx: Context, texture: ?dvui.Texture, vtx: []const dvui.Vertex, idx: []const u16, clipr: ?dvui.Rect.Physical) void;

    pub const textureCreate = *const fn (ctx: Context, pixels: [*]u8, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) dvui.Texture;
    pub const textureDestroy = *const fn (ctx: Context, texture: dvui.Texture) void;
    pub const textureFromTarget = *const fn (ctx: Context, texture: dvui.TextureTarget) dvui.Texture;

    pub const textureCreateTarget = *const fn (ctx: Context, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) error{ OutOfMemory, TextureCreate }!dvui.TextureTarget;
    pub const textureReadTarget = *const fn (ctx: Context, texture: dvui.TextureTarget, pixels_out: [*]u8) error{TextureRead}!void;
    pub const renderTarget = *const fn (ctx: Context, texture: ?dvui.TextureTarget) void;

    pub const clipboardText = *const fn (ctx: Context) error{OutOfMemory}![]const u8;
    pub const clipboardTextSet = *const fn (ctx: Context, text: []const u8) error{OutOfMemory}!void;

    pub const openURL = *const fn (ctx: Context, url: []const u8) error{OutOfMemory}!void;
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
    textureFromTarget: I.textureFromTarget,
    textureCreateTarget: I.textureCreateTarget,
    textureReadTarget: I.textureReadTarget,
    renderTarget: I.renderTarget,
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

    inline for (@typeInfo(I).@"struct".decls) |decl| {
        const hasField = @hasDecl(implementation, decl.name);
        const DeclType = @field(I, decl.name);
        compile_assert(hasField, "Backend type " ++ @typeName(implementation) ++ " has no declaration '" ++ decl.name ++ ": " ++ @typeName(DeclType) ++ "'");
        const f: DeclType = &@field(implementation, decl.name);
        @field(vtable, decl.name) = f;
    }

    return .{
        .ctx = ctx,
        .vtable = vtable,
    };
}

/// Get monotonic nanosecond timestamp. Doesn't have to be system time.
pub fn nanoTime(self: *Backend) i128 {
    return self.vtable.nanoTime(self.ctx);
}
/// Sleep for nanoseconds.
pub fn sleep(self: *Backend, ns: u64) void {
    return self.vtable.sleep(self.ctx, ns);
}
/// Called by dvui during `dvui.Window.begin`, so prior to any dvui
/// rendering.  Use to setup anything needed for this frame.  The arena
/// arg is cleared before `dvui.Window.begin` is called next, useful for any
/// temporary allocations needed only for this frame.
pub fn begin(self: *Backend, arena: std.mem.Allocator) void {
    return self.vtable.begin(self.ctx, arena);
}

/// Called during `dvui.Window.end` before freeing any memory for the current frame.
pub fn end(self: *Backend) void {
    return self.vtable.end(self.ctx);
}

/// Return size of the window in physical pixels.  For a 300x200 retina
/// window (so actually 600x400), this should return 600x400.
pub fn pixelSize(self: *Backend) dvui.Size.Physical {
    return self.vtable.pixelSize(self.ctx);
}

/// Return size of the window in logical pixels.  For a 300x200 retina
/// window (so actually 600x400), this should return 300x200.
pub fn windowSize(self: *Backend) dvui.Size {
    return self.vtable.windowSize(self.ctx);
}

/// Return the detected additional scaling.  This represents the user's
/// additional display scaling (usually set in their window system's
/// settings).  Currently only called during `dvui.Window.init`, so currently
/// this sets the initial content scale.
pub fn contentScale(self: *Backend) f32 {
    return self.vtable.contentScale(self.ctx);
}

/// Render a triangle list using the idx indexes into the vtx vertexes
/// clipped to to `clipr` (if given).  Vertex positions and `clipr` are in
/// physical pixels.  If `texture` is given, the vertexes uv coords are
/// normalized (0-1).
pub fn drawClippedTriangles(self: *Backend, texture: ?dvui.Texture, vtx: []const dvui.Vertex, idx: []const u16, clipr: ?dvui.Rect.Physical) void {
    return self.vtable.drawClippedTriangles(self.ctx, texture, vtx, idx, clipr);
}

/// Create a `dvui.Texture` from the given `pixels` in RGBA.  The returned
/// pointer is what will later be passed to `drawClippedTriangles`.
pub fn textureCreate(self: *Backend, pixels: [*]u8, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) dvui.Texture {
    return self.vtable.textureCreate(self.ctx, pixels, width, height, interpolation);
}

/// Destroy `texture` made with `textureCreate`. After this call, this texture
/// pointer will not be used by dvui.
pub fn textureDestroy(self: *Backend, texture: dvui.Texture) void {
    return self.vtable.textureDestroy(self.ctx, texture);
}

/// Create a `dvui.Texture` that can be rendered to with `renderTarget`.  The
/// returned pointer is what will later be passed to `drawClippedTriangles`.
pub fn textureCreateTarget(self: *Backend, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) !dvui.TextureTarget {
    return try self.vtable.textureCreateTarget(self.ctx, width, height, interpolation);
}

/// Read pixel data (RGBA) from `texture` into `pixels_out`.
pub fn textureReadTarget(self: *Backend, texture: dvui.TextureTarget, pixels_out: [*]u8) !void {
    return try self.vtable.textureReadTarget(self.ctx, texture, pixels_out);
}

/// Convert texture target made with `textureCreateTarget` into return texture
/// as if made by `textureCreate`.  After this call, texture target will not be
/// used by dvui.
pub fn textureFromTarget(self: *Backend, texture: dvui.TextureTarget) dvui.Texture {
    return self.vtable.textureFromTarget(self.ctx, texture);
}

/// Render future `drawClippedTriangles` to the passed `texture` (or screen
/// if null).
pub fn renderTarget(self: *Backend, texture: ?dvui.TextureTarget) void {
    return self.vtable.renderTarget(self.ctx, texture);
}

/// Get clipboard content (text only)
pub fn clipboardText(self: *Backend) error{OutOfMemory}![]const u8 {
    return self.vtable.clipboardText(self.ctx);
}

/// Set clipboard content (text only)
pub fn clipboardTextSet(self: *Backend, text: []const u8) error{OutOfMemory}!void {
    return self.vtable.clipboardTextSet(self.ctx, text);
}

/// Open URL in system browser
pub fn openURL(self: *Backend, url: []const u8) error{OutOfMemory}!void {
    return self.vtable.openURL(self.ctx, url);
}

/// Called by `dvui.refresh` when it is called from a background
/// thread.  Used to wake up the gui thread.  It only has effect if you
/// are using `dvui.Window.waitTime` or some other method of waiting until
/// a new event comes in.
pub fn refresh(self: *Backend) void {
    return self.vtable.refresh(self.ctx);
}

test {
    @import("std").testing.refAllDecls(@This());
}
