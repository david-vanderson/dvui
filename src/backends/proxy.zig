//! Proxy dvui backend: forwards rendering and platform calls to an injected
//! RenderBridge so plugin dylibs can draw through the host's real backend
//! without linking SDL or other GPU libraries.

const std = @import("std");
const dvui = @import("dvui");
const proxy_bridge = @import("proxy_bridge");

allocator: std.mem.Allocator,
arena: std.mem.Allocator = undefined,

pub const kind: dvui.enums.Backend = .proxy;

pub const ProxyBackend = @This();
pub const Context = *ProxyBackend;

pub const InitOptions = struct {
    allocator: std.mem.Allocator,
};

pub fn init(opts: InitOptions) ProxyBackend {
    return .{ .allocator = opts.allocator };
}

pub fn deinit(_: *ProxyBackend) void {}

var clock_time: i128 = 0;

fn bridgeGeneric() dvui.Backend.GenericError!*const proxy_bridge.RenderBridge {
    return proxy_bridge.bridge orelse error.BackendError;
}

fn bridgeCtx(b: *const proxy_bridge.RenderBridge) ?*anyopaque {
    return b.ctx;
}

/// Get monotonic nanosecond timestamp. Doesn't have to be system time.
pub fn nanoTime(_: *ProxyBackend) i128 {
    defer clock_time += 1 * std.time.ns_per_ms;
    return clock_time;
}

/// Sleep for nanoseconds.
pub fn sleep(_: *ProxyBackend, _: u64) void {}

pub fn begin(self: *ProxyBackend, arena: std.mem.Allocator) !void {
    self.arena = arena;
}

pub fn end(_: *ProxyBackend) !void {}

pub fn pixelSize(_: *ProxyBackend) dvui.Size.Physical {
    const b = bridgeGeneric() catch return .{};
    const size = b.pixel_size(bridgeCtx(b));
    return .{ .w = size.w, .h = size.h };
}

pub fn windowSize(_: *ProxyBackend) dvui.Size.Natural {
    const b = bridgeGeneric() catch return .{};
    const size = b.window_size(bridgeCtx(b));
    return .{ .w = size.w, .h = size.h };
}

pub fn contentScale(_: *ProxyBackend) f32 {
    const b = bridgeGeneric() catch return 1;
    return b.content_scale(bridgeCtx(b));
}

pub fn drawClippedTriangles(_: *ProxyBackend, texture: ?dvui.Texture, vtx: []const dvui.Vertex, idx: []const dvui.Vertex.Index, clipr: ?dvui.Rect.Physical) !void {
    const b = try bridgeGeneric();
    var tex_desc: proxy_bridge.TextureDesc = undefined;
    const tex_ptr: ?*const proxy_bridge.TextureDesc = if (texture) |t| blk: {
        tex_desc = proxy_bridge.textureDescFrom(t);
        break :blk &tex_desc;
    } else null;

    var clip = proxy_bridge.ClipRect{ .x = 0, .y = 0, .w = 0, .h = 0 };
    const has_clip: u8 = if (clipr) |r| blk: {
        clip = .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
        break :blk 1;
    } else 0;

    if (b.draw_clipped_triangles(bridgeCtx(b), tex_ptr, vtx.ptr, vtx.len, idx.ptr, idx.len, has_clip, clip) == 0) {
        return error.BackendError;
    }
}

pub fn textureCreate(_: *ProxyBackend, pixels: [*]const u8, options: dvui.Texture.CreateOptions) !dvui.Texture {
    const b = proxy_bridge.bridge orelse return error.TextureCreate;
    const desc = b.texture_create(bridgeCtx(b), pixels, proxy_bridge.createOptionsFrom(options));
    return proxy_bridge.textureFromDesc(desc) catch error.TextureCreate;
}

pub fn textureUpdate(_: *ProxyBackend, texture: dvui.Texture, pixels: [*]const u8) !void {
    const b = proxy_bridge.bridge orelse return error.TextureUpdate;
    var desc = proxy_bridge.textureDescFrom(texture);
    if (b.texture_update(bridgeCtx(b), &desc, pixels) == 0) {
        return error.TextureUpdate;
    }
}

pub fn textureUpdateSubRect(_: *ProxyBackend, texture: dvui.Texture, pixels: [*]const u8, x: u32, y: u32, w: u32, h: u32) !void {
    const b = proxy_bridge.bridge orelse return error.TextureUpdate;
    var desc = proxy_bridge.textureDescFrom(texture);
    if (b.texture_update_sub_rect(bridgeCtx(b), &desc, pixels, x, y, w, h) == 0) {
        return error.TextureUpdate;
    }
}

pub fn textureDestroy(_: *ProxyBackend, texture: dvui.Texture) void {
    const b = bridgeGeneric() catch return;
    var desc = proxy_bridge.textureDescFrom(texture);
    b.texture_destroy(bridgeCtx(b), &desc);
}

pub fn textureCreateTarget(_: *ProxyBackend, options: dvui.Texture.CreateOptions) !dvui.TextureTarget {
    const b = proxy_bridge.bridge orelse return error.TextureCreate;
    const desc = b.texture_create_target(bridgeCtx(b), proxy_bridge.createOptionsFrom(options));
    return proxy_bridge.targetFromDesc(desc) catch error.TextureCreate;
}

pub fn textureClearTarget(_: *ProxyBackend, target: dvui.TextureTarget) void {
    const b = bridgeGeneric() catch return;
    var desc = proxy_bridge.textureDescFromTarget(target);
    b.texture_clear_target(bridgeCtx(b), &desc);
}

pub fn textureReadTarget(_: *ProxyBackend, target: dvui.TextureTarget, pixels: [*]u8) !void {
    const b = proxy_bridge.bridge orelse return error.TextureRead;
    var desc = proxy_bridge.textureDescFromTarget(target);
    if (b.texture_read_target(bridgeCtx(b), &desc, pixels) == 0) {
        return error.TextureRead;
    }
}

pub fn textureDestroyTarget(_: *ProxyBackend, target: dvui.Texture.Target) void {
    const b = bridgeGeneric() catch return;
    var desc = proxy_bridge.textureDescFromTarget(target);
    b.texture_destroy_target(bridgeCtx(b), &desc);
}

pub fn textureFromTarget(_: *ProxyBackend, target: dvui.TextureTarget) !dvui.Texture {
    const b = proxy_bridge.bridge orelse return error.TextureCreate;
    var desc = proxy_bridge.textureDescFromTarget(target);
    const out = b.texture_from_target(bridgeCtx(b), &desc);
    return proxy_bridge.textureFromDesc(out) catch error.TextureCreate;
}

pub fn textureFromTargetTemp(_: *ProxyBackend, target: dvui.TextureTarget) !dvui.Texture {
    const b = proxy_bridge.bridge orelse return error.TextureCreate;
    var desc = proxy_bridge.textureDescFromTarget(target);
    const out = b.texture_from_target_temp(bridgeCtx(b), &desc);
    return proxy_bridge.textureFromDesc(out) catch error.TextureCreate;
}

pub fn renderTarget(_: *ProxyBackend, target: ?dvui.TextureTarget) !void {
    const b = try bridgeGeneric();
    var desc: proxy_bridge.TextureDesc = undefined;
    const target_ptr: ?*const proxy_bridge.TextureDesc = if (target) |t| blk: {
        desc = proxy_bridge.textureDescFromTarget(t);
        break :blk &desc;
    } else null;
    if (b.render_target(bridgeCtx(b), target_ptr) == 0) {
        return error.BackendError;
    }
}

pub fn setCursor(_: *ProxyBackend, cursor: dvui.enums.Cursor) void {
    const b = bridgeGeneric() catch return;
    b.set_cursor(bridgeCtx(b), @intFromEnum(cursor));
}

pub fn textInputRect(_: *ProxyBackend, rect: ?dvui.Rect.Natural) void {
    const b = bridgeGeneric() catch return;
    var clip = proxy_bridge.ClipRect{ .x = 0, .y = 0, .w = 0, .h = 0 };
    const has_rect: u8 = if (rect) |r| blk: {
        clip = .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
        break :blk 1;
    } else 0;
    b.text_input_rect(bridgeCtx(b), has_rect, clip);
}

pub fn renderPresent(_: *ProxyBackend) void {}

pub fn clipboardText(self: *ProxyBackend) ![]const u8 {
    const b = try bridgeGeneric();
    const slice = b.clipboard_text(bridgeCtx(b));
    if (slice.len == 0) return "";
    return try self.arena.dupe(u8, slice.ptr[0..slice.len]);
}

pub fn clipboardTextSet(_: *ProxyBackend, text: []const u8) !void {
    const b = try bridgeGeneric();
    if (b.clipboard_text_set(bridgeCtx(b), text.ptr, text.len) == 0) {
        return error.OutOfMemory;
    }
}

pub fn openURL(_: *ProxyBackend, url: []const u8, new_window: bool) !void {
    const b = try bridgeGeneric();
    if (b.open_url(bridgeCtx(b), url.ptr, url.len, @intFromBool(new_window)) == 0) {
        return error.BackendError;
    }
}

pub fn preferredColorScheme(_: *ProxyBackend) ?dvui.enums.ColorScheme {
    const b = bridgeGeneric() catch return null;
    return switch (b.preferred_color_scheme(bridgeCtx(b))) {
        -1 => null,
        0 => .light,
        1 => .dark,
        else => null,
    };
}

pub fn prefersReducedMotion(_: *ProxyBackend) bool {
    const b = bridgeGeneric() catch return false;
    return b.prefers_reduced_motion(bridgeCtx(b)) != 0;
}

pub fn refresh(_: *ProxyBackend) void {}

pub fn backend(self: *ProxyBackend) dvui.Backend {
    return dvui.Backend.init(self);
}

test {
    std.testing.refAllDecls(@This());
}
