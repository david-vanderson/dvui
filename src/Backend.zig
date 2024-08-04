const std = @import("std");
const dvui = @import("dvui.zig");

const Size = dvui.Size;
const Vertex = dvui.Vertex;

const Backend = @This();

ptr: *anyopaque,
vtable: VTable,

pub fn VTableTypes(comptime Ptr: type) type {
    return struct {
        pub const nanoTime = *const fn (ptr: Ptr) i128;
        pub const sleep = *const fn (ptr: Ptr, ns: u64) void;
        pub const begin = *const fn (ptr: Ptr, arena: std.mem.Allocator) void;
        pub const end = *const fn (ptr: Ptr) void;
        pub const pixelSize = *const fn (ptr: Ptr) Size;
        pub const windowSize = *const fn (ptr: Ptr) Size;
        pub const contentScale = *const fn (ptr: Ptr) f32;
        pub const renderGeometry = *const fn (ptr: Ptr, texture: ?*anyopaque, vtx: []const Vertex, idx: []const u32) void;
        pub const textureCreate = *const fn (ptr: Ptr, pixels: [*]u8, width: u32, height: u32) *anyopaque;
        pub const textureDestroy = *const fn (ptr: Ptr, texture: *anyopaque) void;
        pub const clipboardText = *const fn (ptr: Ptr) error{OutOfMemory}![]const u8;
        pub const clipboardTextSet = *const fn (ptr: Ptr, text: []const u8) error{OutOfMemory}!void;
        pub const openURL = *const fn (ptr: Ptr, url: []const u8) error{OutOfMemory}!void;
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
    renderGeometry: I.renderGeometry,
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
    comptime interface: anytype,
) Backend {
    const Ptr = @TypeOf(pointer);
    const I = VTableTypes(Ptr);

    compile_assert(@sizeOf(Ptr) == @sizeOf(usize), "Must be a pointer-sized"); // calling convention dictates that any type can work here after converted to *anyopaque

    comptime var vtable: VTable = undefined;

    inline for (@typeInfo(I).Struct.decls) |decl| {
        const f: @field(I, decl.name) = &@field(interface, decl.name);
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
    self.vtable.begin(self.ptr, arena);
}

pub fn end(self: *Backend) void {
    self.vtable.end(self.ptr);
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

pub fn renderGeometry(self: *Backend, texture: ?*anyopaque, vtx: []const Vertex, idx: []const u32) void {
    self.vtable.renderGeometry(self.ptr, texture, vtx, idx);
}

pub fn textureCreate(self: *Backend, pixels: [*]u8, width: u32, height: u32) *anyopaque {
    return self.vtable.textureCreate(self.ptr, pixels, width, height);
}

pub fn textureDestroy(self: *Backend, texture: *anyopaque) void {
    self.vtable.textureDestroy(self.ptr, texture);
}

pub fn clipboardText(self: *Backend) error{OutOfMemory}![]const u8 {
    return self.vtable.clipboardText(self.ptr);
}

pub fn clipboardTextSet(self: *Backend, text: []const u8) error{OutOfMemory}!void {
    try self.vtable.clipboardTextSet(self.ptr, text);
}

pub fn openURL(self: *Backend, url: []const u8) error{OutOfMemory}!void {
    try self.vtable.openURL(self.ptr, url);
}

pub fn refresh(self: *Backend) void {
    self.vtable.refresh(self.ptr);
}
