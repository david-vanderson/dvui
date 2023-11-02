const std = @import("std");
const dvui = @import("dvui.zig");

const Size = dvui.Size;
const Vertex = dvui.Vertex;

const Backend = @This();

ptr: *anyopaque,
vtable: *const VTable,

const VTable = struct {
    begin: *const fn (ptr: *anyopaque, arena: std.mem.Allocator) void,
    end: *const fn (ptr: *anyopaque) void,
    pixelSize: *const fn (ptr: *anyopaque) Size,
    windowSize: *const fn (ptr: *anyopaque) Size,
    contentScale: *const fn (ptr: *anyopaque) f32,
    renderGeometry: *const fn (ptr: *anyopaque, texture: ?*anyopaque, vtx: []const Vertex, idx: []const u32) void,
    textureCreate: *const fn (ptr: *anyopaque, pixels: [*]u8, width: u32, height: u32) *anyopaque,
    textureDestroy: *const fn (ptr: *anyopaque, texture: *anyopaque) void,
    clipboardText: *const fn (ptr: *anyopaque) []u8,
    clipboardTextSet: *const fn (ptr: *anyopaque, text: []const u8) error{OutOfMemory}!void,
    free: *const fn (ptr: *anyopaque, p: *anyopaque) void,
    openURL: *const fn (ptr: *anyopaque, url: []const u8) error{OutOfMemory}!void,
    refresh: *const fn (ptr: *anyopaque) void,
};

pub fn init(
    pointer: anytype,
    comptime beginFn: fn (ptr: @TypeOf(pointer), arena: std.mem.Allocator) void,
    comptime endFn: fn (ptr: @TypeOf(pointer)) void,
    comptime pixelSizeFn: fn (ptr: @TypeOf(pointer)) Size,
    comptime windowSizeFn: fn (ptr: @TypeOf(pointer)) Size,
    comptime contentScaleFn: fn (ptr: @TypeOf(pointer)) f32,
    comptime renderGeometryFn: fn (ptr: @TypeOf(pointer), texture: ?*anyopaque, vtx: []const Vertex, idx: []const u32) void,
    comptime textureCreateFn: fn (ptr: @TypeOf(pointer), pixels: [*]u8, width: u32, height: u32) *anyopaque,
    comptime textureDestroyFn: fn (ptr: @TypeOf(pointer), texture: *anyopaque) void,
    comptime clipboardTextFn: fn (ptr: @TypeOf(pointer)) []u8,
    comptime clipboardTextSetFn: fn (ptr: @TypeOf(pointer), text: []const u8) error{OutOfMemory}!void,
    comptime freeFn: fn (ptr: @TypeOf(pointer), p: *anyopaque) void,
    comptime openURLFn: fn (ptr: @TypeOf(pointer), url: []const u8) error{OutOfMemory}!void,
    comptime refreshFn: fn (ptr: @TypeOf(pointer)) void,
) Backend {
    const Ptr = @TypeOf(pointer);
    const ptr_info = @typeInfo(Ptr);
    std.debug.assert(ptr_info == .Pointer); // Must be a pointer
    std.debug.assert(ptr_info.Pointer.size == .One); // Must be a single-item pointer

    const gen = struct {
        fn beginImpl(ptr: *anyopaque, arena: std.mem.Allocator) void {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            return @call(.always_inline, beginFn, .{ self, arena });
        }

        fn endImpl(ptr: *anyopaque) void {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            return @call(.always_inline, endFn, .{self});
        }

        fn pixelSizeImpl(ptr: *anyopaque) Size {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            return @call(.always_inline, pixelSizeFn, .{self});
        }

        fn windowSizeImpl(ptr: *anyopaque) Size {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            return @call(.always_inline, windowSizeFn, .{self});
        }

        fn contentScaleImpl(ptr: *anyopaque) f32 {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            return @call(.always_inline, contentScaleFn, .{self});
        }

        fn renderGeometryImpl(ptr: *anyopaque, texture: ?*anyopaque, vtx: []const Vertex, idx: []const u32) void {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            return @call(.always_inline, renderGeometryFn, .{ self, texture, vtx, idx });
        }

        fn textureCreateImpl(ptr: *anyopaque, pixels: [*]u8, width: u32, height: u32) *anyopaque {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            return @call(.always_inline, textureCreateFn, .{ self, pixels, width, height });
        }

        fn textureDestroyImpl(ptr: *anyopaque, texture: *anyopaque) void {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            return @call(.always_inline, textureDestroyFn, .{ self, texture });
        }

        fn clipboardTextImpl(ptr: *anyopaque) []u8 {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            return @call(.always_inline, clipboardTextFn, .{self});
        }

        fn clipboardTextSetImpl(ptr: *anyopaque, text: []const u8) error{OutOfMemory}!void {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            try @call(.always_inline, clipboardTextSetFn, .{ self, text });
        }

        fn freeImpl(ptr: *anyopaque, p: *anyopaque) void {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            return @call(.always_inline, freeFn, .{ self, p });
        }

        fn openURLImpl(ptr: *anyopaque, url: []const u8) error{OutOfMemory}!void {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            try @call(.always_inline, openURLFn, .{ self, url });
        }

        fn refreshImpl(ptr: *anyopaque) void {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            return @call(.always_inline, refreshFn, .{self});
        }

        const vtable = VTable{
            .begin = beginImpl,
            .end = endImpl,
            .pixelSize = pixelSizeImpl,
            .windowSize = windowSizeImpl,
            .contentScale = contentScaleImpl,
            .renderGeometry = renderGeometryImpl,
            .textureCreate = textureCreateImpl,
            .textureDestroy = textureDestroyImpl,
            .clipboardText = clipboardTextImpl,
            .clipboardTextSet = clipboardTextSetImpl,
            .free = freeImpl,
            .openURL = openURLImpl,
            .refresh = refreshImpl,
        };
    };

    return .{
        .ptr = pointer,
        .vtable = &gen.vtable,
    };
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

pub fn clipboardText(self: *Backend) []u8 {
    return self.vtable.clipboardText(self.ptr);
}

pub fn clipboardTextSet(self: *Backend, text: []const u8) error{OutOfMemory}!void {
    try self.vtable.clipboardTextSet(self.ptr, text);
}

pub fn free(self: *Backend, p: *anyopaque) void {
    return self.vtable.free(self.ptr, p);
}

pub fn openURL(self: *Backend, url: []const u8) error{OutOfMemory}!void {
    try self.vtable.openURL(self.ptr, url);
}

pub fn refresh(self: *Backend) void {
    self.vtable.refresh(self.ptr);
}
