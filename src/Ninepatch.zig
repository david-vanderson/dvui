pub const builtins = struct {
    pub const raised = dvui.Ninepatch.Source{
        .bytes = @embedFile("themes/raised.png"),
        .name = "raised.png",
        .uv = &UV.fromPixelInset(.all(2), .all(6)),
        .interpolation = .nearest,
    };
    pub const sunken = dvui.Ninepatch.Source{
        .bytes = @embedFile("themes/sunken.png"),
        .name = "sunken.png",
        .uv = &UV.fromPixelInset(.all(2), .all(6)),
        .interpolation = .nearest,
    };
};

const Ninepatch = @This();

tex: Texture,
uv: *const UV,

pub fn size(this: *const @This(), patch: usize) Size {
    return .{
        .w = @as(f32, @floatFromInt(this.tex.width)) * this.uv.uv[patch].w,
        .h = @as(f32, @floatFromInt(this.tex.height)) * this.uv.uv[patch].h,
    };
}

pub fn minSize(ninepatch: *const @This()) Size {
    const sz_top_left = ninepatch.size(0);
    const sz_top_right = ninepatch.size(2);
    const sz_bottom_left = ninepatch.size(6);
    const sz_bottom_right = ninepatch.size(8);

    const min_total_width_top = sz_top_left.w + sz_top_right.w;
    const min_total_width_bot = sz_bottom_left.w + sz_bottom_right.w;
    const min_total_height_left = sz_top_left.h + sz_bottom_left.h;
    const min_total_height_right = sz_top_right.h + sz_bottom_right.h;

    std.debug.assert(min_total_width_top == min_total_width_bot);
    std.debug.assert(min_total_height_left == min_total_height_right);

    return .{ .w = min_total_width_top, .h = min_total_height_left };
}

pub const UV = struct {
    uv: [9]Rect,

    pub fn fromPixel(patches: [9]Rect, texture_size: Size) UV {
        const w, const h, const p = .{ texture_size.w - 1, texture_size.h - 1, patches };
        return .{ .uv = .{
            .{ .x = p[0].topLeft().x / w, .y = p[0].topLeft().y / h, .w = p[0].w / w, .h = p[0].h / h },
            .{ .x = p[1].topLeft().x / w, .y = p[1].topLeft().y / h, .w = p[1].w / w, .h = p[1].h / h },
            .{ .x = p[2].topLeft().x / w, .y = p[2].topLeft().y / h, .w = p[2].w / w, .h = p[2].h / h },

            .{ .x = p[3].topLeft().x / w, .y = p[3].topLeft().y / h, .w = p[3].w / w, .h = p[3].h / h },
            .{ .x = p[4].topLeft().x / w, .y = p[4].topLeft().y / h, .w = p[4].w / w, .h = p[4].h / h },
            .{ .x = p[5].topLeft().x / w, .y = p[5].topLeft().y / h, .w = p[5].w / w, .h = p[5].h / h },

            .{ .x = p[6].topLeft().x / w, .y = p[6].topLeft().y / h, .w = p[6].w / w, .h = p[6].h / h },
            .{ .x = p[7].topLeft().x / w, .y = p[7].topLeft().y / h, .w = p[7].w / w, .h = p[7].h / h },
            .{ .x = p[8].topLeft().x / w, .y = p[8].topLeft().y / h, .w = p[8].w / w, .h = p[8].h / h },
        } };
    }

    /// Returns set of 9 uvs dividing the image from top left to bottom right at lines specified by inset.
    pub fn fromInset(inset: Rect) UV {
        const v = [_]f32{ 0, inset.x, 1 - inset.w, 1 }; // vertical lines across image
        const h = [_]f32{ 0, inset.y, 1 - inset.h, 1 }; // horizontal lines across image
        return .{ .uv = .{
            .{ .x = h[0], .y = v[0], .w = h[1] - h[0], .h = v[1] - v[0] },
            .{ .x = h[1], .y = v[0], .w = h[2] - h[1], .h = v[1] - v[0] },
            .{ .x = h[2], .y = v[0], .w = h[3] - h[2], .h = v[1] - v[0] },

            .{ .x = h[0], .y = v[1], .w = h[1] - h[0], .h = v[2] - v[1] },
            .{ .x = h[1], .y = v[1], .w = h[2] - h[1], .h = v[2] - v[1] },
            .{ .x = h[2], .y = v[1], .w = h[3] - h[2], .h = v[2] - v[1] },

            .{ .x = h[0], .y = v[2], .w = h[1] - h[0], .h = v[3] - v[2] },
            .{ .x = h[1], .y = v[2], .w = h[2] - h[1], .h = v[3] - v[2] },
            .{ .x = h[2], .y = v[2], .w = h[3] - h[2], .h = v[3] - v[2] },
        } };
    }

    /// Returns set of 9 uvs dividing the image from top left to bottom right at lines specified by inset
    pub fn fromPixelInset(inset_px: Rect, texture_size: Size) UV {
        const v = [_]f32{ 0, inset_px.x, texture_size.w - 1 - inset_px.w, texture_size.w }; // vertical lines across image
        const h = [_]f32{ 0, inset_px.y, texture_size.h - 1 - inset_px.h, texture_size.h }; // horizontal lines across image
        const uv_px = [9]Rect{
            .{ .x = h[0], .y = v[0], .w = h[1] - h[0], .h = v[1] - v[0] },
            .{ .x = h[1], .y = v[0], .w = h[2] - h[1], .h = v[1] - v[0] },
            .{ .x = h[2], .y = v[0], .w = h[3] - h[2], .h = v[1] - v[0] },

            .{ .x = h[0], .y = v[1], .w = h[1] - h[0], .h = v[2] - v[1] },
            .{ .x = h[1], .y = v[1], .w = h[2] - h[1], .h = v[2] - v[1] },
            .{ .x = h[2], .y = v[1], .w = h[3] - h[2], .h = v[2] - v[1] },

            .{ .x = h[0], .y = v[2], .w = h[1] - h[0], .h = v[3] - v[2] },
            .{ .x = h[1], .y = v[2], .w = h[2] - h[1], .h = v[3] - v[2] },
            .{ .x = h[2], .y = v[2], .w = h[3] - h[2], .h = v[3] - v[2] },
        };
        return fromPixel(uv_px, texture_size);
    }
};

pub const Source = struct {
    bytes: []const u8,
    name: []const u8,
    uv: *const UV,
    interpolation: TextureInterpolation = .linear,
    invalidation: Texture.ImageSource.InvalidationStrategy = .ptr,

    pub fn getNinepatch(patch: Source) !Ninepatch {
        const texture_src = ImageSource{ .imageFile = .{
            .bytes = patch.bytes,
            .name = patch.name,
            .interpolation = patch.interpolation,
            .invalidation = patch.invalidation,
        } };
        const tex = try texture_src.getTexture();
        return .{ .tex = tex, .uv = patch.uv };
    }
};

const std = @import("std");
const dvui = @import("dvui.zig");

const Color = dvui.Color;
const Size = dvui.Size;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Texture = dvui.Texture;
const ImageSource = dvui.ImageSource;
const TextureInterpolation = dvui.enums.TextureInterpolation;
