//! C-ABI render bridge injected by the host at plugin load time.
//! The proxy backend forwards dvui draw calls through this table so plugin
//! dylibs never link SDL or any other platform renderer.

const dvui = @import("dvui");

pub const TextSlice = extern struct {
    ptr: [*]const u8,
    len: usize,
};

pub const ClipRect = extern struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

pub const CreateOptions = extern struct {
    width: u32,
    height: u32,
    format: u8,
    interpolation: u8,
    wrap_u: u8,
    wrap_v: u8,
};

pub const TextureDesc = extern struct {
    ptr: ?*anyopaque,
    width: u32,
    height: u32,
    format: u8,
    interpolation: u8,
    wrap_u: u8,
    wrap_v: u8,
};

pub const SizePair = extern struct {
    w: f32,
    h: f32,
};

pub const RenderBridge = extern struct {
    ctx: ?*anyopaque,

    draw_clipped_triangles: *const fn (
        ctx: ?*anyopaque,
        texture: ?*const TextureDesc,
        vtx: [*]const dvui.Vertex,
        vtx_len: usize,
        idx: [*]const dvui.Vertex.Index,
        idx_len: usize,
        has_clip: u8,
        clip: ClipRect,
    ) callconv(.c) u8,

    texture_create: *const fn (
        ctx: ?*anyopaque,
        pixels: [*]const u8,
        options: CreateOptions,
    ) callconv(.c) TextureDesc,

    texture_update: *const fn (
        ctx: ?*anyopaque,
        texture: *const TextureDesc,
        pixels: [*]const u8,
    ) callconv(.c) u8,

    texture_update_sub_rect: *const fn (
        ctx: ?*anyopaque,
        texture: *const TextureDesc,
        pixels: [*]const u8,
        x: u32,
        y: u32,
        w: u32,
        h: u32,
    ) callconv(.c) u8,

    texture_destroy: *const fn (ctx: ?*anyopaque, texture: *const TextureDesc) callconv(.c) void,

    texture_create_target: *const fn (ctx: ?*anyopaque, options: CreateOptions) callconv(.c) TextureDesc,
    texture_read_target: *const fn (ctx: ?*anyopaque, target: *const TextureDesc, pixels_out: [*]u8) callconv(.c) u8,
    texture_destroy_target: *const fn (ctx: ?*anyopaque, target: *const TextureDesc) callconv(.c) void,
    texture_clear_target: *const fn (ctx: ?*anyopaque, target: *const TextureDesc) callconv(.c) void,
    texture_from_target: *const fn (ctx: ?*anyopaque, target: *const TextureDesc) callconv(.c) TextureDesc,
    texture_from_target_temp: *const fn (ctx: ?*anyopaque, target: *const TextureDesc) callconv(.c) TextureDesc,
    render_target: *const fn (ctx: ?*anyopaque, target: ?*const TextureDesc) callconv(.c) u8,

    pixel_size: *const fn (ctx: ?*anyopaque) callconv(.c) SizePair,
    window_size: *const fn (ctx: ?*anyopaque) callconv(.c) SizePair,
    content_scale: *const fn (ctx: ?*anyopaque) callconv(.c) f32,

    clipboard_text: *const fn (ctx: ?*anyopaque) callconv(.c) TextSlice,
    clipboard_text_set: *const fn (ctx: ?*anyopaque, text: [*]const u8, text_len: usize) callconv(.c) u8,
    open_url: *const fn (ctx: ?*anyopaque, url: [*]const u8, url_len: usize, new_window: u8) callconv(.c) u8,

    set_cursor: *const fn (ctx: ?*anyopaque, cursor: u8) callconv(.c) void,
    text_input_rect: *const fn (ctx: ?*anyopaque, has_rect: u8, rect: ClipRect) callconv(.c) void,

    preferred_color_scheme: *const fn (ctx: ?*anyopaque) callconv(.c) i8,
    prefers_reduced_motion: *const fn (ctx: ?*anyopaque) callconv(.c) u8,
};

/// Set by the host when a plugin dylib is loaded.
pub var bridge: ?*const RenderBridge = null;

pub fn setBridge(b: ?*const RenderBridge) void {
    bridge = b;
}

pub fn createOptionsFrom(options: dvui.Texture.CreateOptions) CreateOptions {
    return .{
        .width = options.width,
        .height = options.height,
        .format = @intFromEnum(options.format),
        .interpolation = @intFromEnum(options.interpolation),
        .wrap_u = @intFromEnum(options.wrap_u),
        .wrap_v = @intFromEnum(options.wrap_v),
    };
}

pub fn textureDescFrom(texture: dvui.Texture) TextureDesc {
    return .{
        .ptr = texture.ptr,
        .width = texture.width,
        .height = texture.height,
        .format = @intFromEnum(texture.format),
        .interpolation = @intFromEnum(texture.interpolation),
        .wrap_u = @intFromEnum(texture.wrap_u),
        .wrap_v = @intFromEnum(texture.wrap_v),
    };
}

pub fn textureDescFromTarget(texture: dvui.TextureTarget) TextureDesc {
    return .{
        .ptr = texture.ptr,
        .width = texture.width,
        .height = texture.height,
        .format = @intFromEnum(texture.format),
        .interpolation = @intFromEnum(texture.interpolation),
        .wrap_u = @intFromEnum(texture.wrap_u),
        .wrap_v = @intFromEnum(texture.wrap_v),
    };
}

pub fn textureFromDesc(desc: TextureDesc) error{TextureCreate}!dvui.Texture {
    const ptr = desc.ptr orelse return error.TextureCreate;
    return .{
        .ptr = ptr,
        .width = desc.width,
        .height = desc.height,
        .format = @enumFromInt(desc.format),
        .interpolation = @enumFromInt(desc.interpolation),
        .wrap_u = @enumFromInt(desc.wrap_u),
        .wrap_v = @enumFromInt(desc.wrap_v),
    };
}

pub fn targetFromDesc(desc: TextureDesc) error{TextureCreate}!dvui.TextureTarget {
    const ptr = desc.ptr orelse return error.TextureCreate;
    return .{
        .ptr = ptr,
        .width = desc.width,
        .height = desc.height,
        .format = @enumFromInt(desc.format),
        .interpolation = @enumFromInt(desc.interpolation),
        .wrap_u = @enumFromInt(desc.wrap_u),
        .wrap_v = @enumFromInt(desc.wrap_v),
    };
}
