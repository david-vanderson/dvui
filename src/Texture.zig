//! A texture held by the backend.  Can be drawn with `dvui.renderTexture`.

ptr: *anyopaque,
width: u32,
height: u32,

const Texture = @This();

/// A texture held by the backend that can be drawn onto.  See `dvui.Picture`.
pub const Target = struct {
    ptr: *anyopaque,
    width: u32,
    height: u32,

    /// Create a texture that can be rendered with `renderTexture` and drawn to
    /// with `renderTarget`.  Starts transparent (all zero).
    ///
    /// Remember to destroy the texture at some point, see `destroyLater`.
    ///
    /// Only valid between `Window.begin`and `Window.end`.
    pub fn create(width: u32, height: u32, interpolation: TextureInterpolation) TextureError!Target {
        return try dvui.currentWindow().backend.textureCreateTarget(width, height, interpolation);
    }
};

pub const Cache = struct {
    cache: Storage = .empty,
    /// Used to defer destroying textures until the next call to `reset` or `deinit`
    trash: Trash = .empty,

    pub const Storage = dvui.TrackingAutoHashMap(Key, Texture, .{ .tracking = .get_and_put, .reset = .delayed });
    pub const Trash = std.ArrayListUnmanaged(dvui.Texture);

    pub const Key = u64;

    pub fn get(self: *Cache, key: Key) ?Texture {
        return self.cache.get(key);
    }

    /// Add a texture to the cache. This is useful if you want to load
    /// and image from disk, create a texture from it and then unload
    /// it from memory. The texture will remain in the cache as long
    /// as it's key is accessed at least once per call to `reset`.
    pub fn add(self: *Cache, gpa: std.mem.Allocator, key: Key, texture: Texture) std.mem.Allocator.Error!void {
        try self.trash.ensureUnusedCapacity(gpa, 1);
        const prev = try self.cache.fetchPut(gpa, key, texture);
        if (prev) |kv| {
            self.trash.appendAssumeCapacity(kv.value);
        }
    }

    /// Remove a key from the cache. This can force the re-creation
    /// of a texture created by `ImageSource` for example.
    ///
    /// `gpa` is needed to store the texture for deferred destruction
    pub fn invalidate(self: *Cache, gpa: std.mem.Allocator, key: Key) std.mem.Allocator.Error!void {
        try self.trash.ensureUnusedCapacity(gpa, 1);
        const prev = self.cache.fetchRemove(key);
        if (prev) |kv| {
            self.trash.appendAssumeCapacity(kv.value);
        }
    }

    /// Destroys all unused and trashed textures since the last
    /// call to `reset`
    ///
    /// `allocator` is only used for the returned slice and can be
    /// different from the one used for calls to `add`
    pub fn reset(self: *Cache, backend: dvui.Backend) void {
        var it = self.cache.iterator();
        while (it.next_resetting()) |kv| {
            backend.textureDestroy(kv.value);
        }
        for (self.trash.items) |tex| {
            backend.textureDestroy(tex);
        }
        self.trash.clearRetainingCapacity();
    }

    /// Deallocates and destroys all stored textures
    pub fn deinit(self: *Cache, gpa: std.mem.Allocator, backend: dvui.Backend) void {
        defer self.* = undefined;
        var it = self.cache.iterator();
        while (it.next()) |item| {
            backend.textureDestroy(item.value_ptr.*);
        }
        self.cache.deinit(gpa);
        for (self.trash.items) |tex| {
            backend.textureDestroy(tex);
        }
        self.trash.deinit(gpa);
    }
};

pub const ImageSource = union(enum) {
    /// bytes of an supported image file (i.e. png, jpeg, gif, ...)
    imageFile: struct {
        bytes: []const u8,
        // Optional name/filename for debugging
        name: []const u8 = "imageFile",
        interpolation: TextureInterpolation = .linear,
        invalidation: InvalidationStrategy = .ptr,
    },

    /// bytes of an premultiplied rgba u8 array in row major order
    pixelsPMA: struct {
        rgba: []Color.PMA,
        width: u32,
        height: u32,
        interpolation: TextureInterpolation = .linear,
        invalidation: InvalidationStrategy = .ptr,
    },

    /// bytes of a non premultiplied rgba u8 array in row major order, will
    /// be converted to premultiplied when making a texture
    pixels: struct {
        /// FIXME: This cannot use `[]const Color` because it's not marked `extern`
        ///        and doesn't have a stable memory layout
        rgba: []const u8,
        width: u32,
        height: u32,
        interpolation: TextureInterpolation = .linear,
        invalidation: InvalidationStrategy = .ptr,
    },

    /// When providing a texture directly, `hash` will return 0 and it will
    /// not be inserted into the texture cache.
    texture: Texture,

    pub const InvalidationStrategy = enum {
        /// The pointer will be used to determine if the source has changed.
        ///
        /// Changing the data behind the pointer will NOT invalidate the texture
        ptr,
        /// The bytes will be used to determine if the source has changed.
        ///
        /// Changing the data behind the pointer WILL invalidate the texture,
        /// but checking all the bytes every frame can be costly
        bytes,
        /// Do not cache the texture at all and generate a new texture each frame
        always,
    };

    /// Pass the return value of this to `dvui.textureInvalidate` to
    /// remove the texture from the cache.
    ///
    /// When providing a texture directly with `ImageSource.texture`,
    /// this function will always return 0 as it doesn't interact with
    /// the texture cache.
    pub fn hash(self: ImageSource) u64 {
        var h = dvui.fnv.init();
        // .always hashes ptr (for uniqueness) and image dimensions so we can update the texture if dimensions stay the same
        const img_dimensions = self.size() catch Size{ .w = 0, .h = 0 };
        var dim: [2]u32 = .{ @intFromFloat(img_dimensions.w), @intFromFloat(img_dimensions.h) };
        const img_dim_bytes = std.mem.asBytes(&dim); // hashing u32 here instead of float because of unstable bit representation in floating point numbers

        switch (self) {
            .imageFile => |file| {
                switch (file.invalidation) {
                    .ptr => h.update(std.mem.asBytes(&file.bytes.ptr)),
                    .bytes => h.update(file.bytes),
                    .always => {
                        h.update(std.mem.asBytes(&file.bytes.ptr));
                        h.update(img_dim_bytes);
                    },
                }
                h.update(std.mem.asBytes(&@intFromEnum(file.interpolation)));
            },
            .pixelsPMA => |pixels| {
                switch (pixels.invalidation) {
                    .ptr, .always => h.update(std.mem.asBytes(&pixels.rgba.ptr)),
                    .bytes => h.update(@ptrCast(pixels.rgba)),
                }
                h.update(std.mem.asBytes(&@intFromEnum(pixels.interpolation)));
                h.update(img_dim_bytes);
            },
            .pixels => |pixels| {
                switch (pixels.invalidation) {
                    .ptr, .always => h.update(std.mem.asBytes(&pixels.rgba.ptr)),
                    .bytes => h.update(std.mem.sliceAsBytes(pixels.rgba)),
                }
                h.update(std.mem.asBytes(&@intFromEnum(pixels.interpolation)));
                h.update(img_dim_bytes);
            },
            .texture => return 0,
        }
        return h.final();
    }

    /// Will get the texture from cache or create it if it doesn't already exist
    ///
    /// Only valid between `Window.begin` and `Window.end`
    pub fn getTexture(self: ImageSource) !Texture {
        const key = self.hash();
        const invalidate = switch (self) {
            .imageFile => |f| f.invalidation,
            .pixels => |px| px.invalidation,
            .pixelsPMA => |px| px.invalidation,
            // return texture directly
            .texture => |tex| return tex,
        };
        if (dvui.textureGetCached(key)) |cached_texture| {
            // if invalidate = always, we update the texture using updateImageSource for efficency, otherwise return the cached Texture
            if (invalidate == .always) {
                var tex_mut = cached_texture;
                try tex_mut.updateImageSource(self);
                return tex_mut;
            } else return cached_texture;
        } else {
            // cache was empty we create a new Texture
            const new_texture = try Texture.fromImageSource(self);
            dvui.textureAddToCache(key, new_texture);
            return new_texture;
        }
    }

    /// Get the size of a raster image.  If source is .imageFile, this only decodes
    /// enough info to get the size.
    ///
    /// See `dvui.image`.
    ///
    /// Only valid between `Window.begin`and `Window.end`.
    pub fn size(source: ImageSource) !Size {
        switch (source) {
            .imageFile => |file| {
                var w: c_int = undefined;
                var h: c_int = undefined;
                var n: c_int = undefined;
                const ok = dvui.c.stbi_info_from_memory(file.bytes.ptr, @as(c_int, @intCast(file.bytes.len)), &w, &h, &n);
                if (ok == 1) {
                    return .{ .w = @floatFromInt(w), .h = @floatFromInt(h) };
                } else {
                    dvui.log.warn("imageSize stbi_info error on image \"{s}\": {s}\n", .{ file.name, dvui.c.stbi_failure_reason() });
                    return StbImageError.stbImageError;
                }
            },
            .pixelsPMA => |a| return .{ .w = @floatFromInt(a.width), .h = @floatFromInt(a.height) },
            .pixels => |a| return .{ .w = @floatFromInt(a.width), .h = @floatFromInt(a.height) },
            .texture => |tex| return .{ .w = @floatFromInt(tex.width), .h = @floatFromInt(tex.height) },
        }
    }
};

/// Update a texture that was created with `textureCreate`. or fromImageSource
///
/// The dimensions of the image must match the initial dimensions!
/// Only valid to call while the underlying Texture is not destroyed!
///
/// Only valid between `Window.begin` and `Window.end`.
pub fn updateImageSource(self: *Texture, src: ImageSource) !void {
    switch (src) {
        .imageFile => |f| {
            const img = try Color.PMAImage.fromImageFile(f.name, dvui.currentWindow().arena(), f.bytes);
            defer dvui.currentWindow().arena().free(img.pma);
            try update(self, img.pma, f.interpolation);
        },
        .pixels => |px| {
            const copy = try dvui.currentWindow().arena().dupe(u8, px.rgba);
            defer dvui.currentWindow().arena().free(copy);
            const pma = Color.PMA.sliceFromRGBA(copy);
            try update(self, pma, px.interpolation);
        },
        .pixelsPMA => |px| {
            try update(self, px.rgba, px.interpolation);
        },
        .texture => |_| @panic("this is not supported currently"),
    }
}

/// creates a new Texture from an ImageSource
///
/// Only valid between `Window.begin` and `Window.end`.
pub fn fromImageSource(source: ImageSource) !Texture {
    return switch (source) {
        .imageFile => |f| try Texture.fromImageFile(f.name, f.bytes, f.interpolation),
        .pixelsPMA => |px| try Texture.fromPixelsPMA(px.rgba, px.width, px.height, px.interpolation),
        .pixels => |px| blk: {
            // Using arena here instead of lifo as this buffer is likely to be large and we
            // prefer that lifo doesn't reallocate as often. Arena is intended for larger,
            // one of allocations and we can still free the buffer here
            const copy = try dvui.currentWindow().arena().dupe(u8, px.rgba);
            defer dvui.currentWindow().arena().free(copy);
            break :blk try Texture.fromPixelsPMA(Color.PMA.sliceFromRGBA(copy), px.width, px.height, px.interpolation);
        },
        .texture => |t| t,
    };
}

pub fn fromImageFile(name: []const u8, image_bytes: []const u8, interpolation: TextureInterpolation) (TextureError || StbImageError)!Texture {
    const img = Color.PMAImage.fromImageFile(name, dvui.currentWindow().arena(), image_bytes) catch return StbImageError.stbImageError;
    defer dvui.currentWindow().arena().free(img.pma);
    return try create(img.pma, img.width, img.height, interpolation);
}

pub fn fromPixelsPMA(pma: []const Color.PMA, width: u32, height: u32, interpolation: TextureInterpolation) TextureError!Texture {
    return try dvui.textureCreate(pma, width, height, interpolation);
}

/// Render `tvg_bytes` at `height` into a `Texture`.  Name is for debugging.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn fromTvgFile(name: []const u8, tvg_bytes: []const u8, height: u32, icon_opts: IconRenderOptions) (TextureError || TvgError)!Texture {
    const cw = dvui.currentWindow();
    const img = Color.PMAImage.fromTvgFile(name, cw.lifo(), cw.arena(), tvg_bytes, height, icon_opts) catch return TvgError.tvgError;
    defer cw.lifo().free(img.pma);
    return try create(img.pma, img.width, img.height, .linear);
}

/// Create a texture that can be rendered with `renderTexture`.
///
/// Remember to destroy the texture at some point, see `destroyLater`.
///
/// Only valid between `Window.begin` and `Window.end`.
pub fn create(pixels: []const Color.PMA, width: u32, height: u32, interpolation: TextureInterpolation) TextureError!Texture {
    if (pixels.len != width * height) {
        dvui.log.err("Texture was created with an incorrect amount of pixels, expected {d} but got {d} (w: {d}, h: {d})", .{ pixels.len, width * height, width, height });
    }
    return dvui.currentWindow().backend.textureCreate(@ptrCast(pixels.ptr), width, height, interpolation);
}

/// Update a texture that was created with `textureCreate`.
///
/// If the backend does not support updating textures, it will be destroyed and
/// recreated, changing the pointer inside tex.
///
/// Only valid between `Window.begin` and `Window.end`.
pub fn update(tex: *Texture, pma: []const Color.PMA, interpolation: TextureInterpolation) !void {
    if (pma.len != tex.width * tex.height) @panic("Texture size and supplied Content did not match");
    dvui.currentWindow().backend.textureUpdate(tex.*, @ptrCast(pma.ptr)) catch |err| {
        // texture update not supported by backend, destroy and create texture
        if (err == TextureError.NotImplemented) {
            const new_tex = try create(pma, tex.width, tex.height, interpolation);
            destroyLater(tex.*);
            tex.* = new_tex;
        } else {
            return err;
        }
    };
}

/// Read pixels from texture created with `textureCreateTarget`.
///
/// Returns pixels allocated by arena.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn readTarget(arena: std.mem.Allocator, texture: Target) TextureError![]Color.PMA {
    const size: usize = texture.width * texture.height * @sizeOf(Color.PMA);
    const pixels = try arena.alloc(u8, size);
    errdefer arena.free(pixels);

    try dvui.currentWindow().backend.textureReadTarget(texture, pixels.ptr);

    return @ptrCast(pixels);
}

/// Convert a target texture to a normal texture.  target is destroyed.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn fromTarget(target: Target) TextureError!Texture {
    return dvui.currentWindow().backend.textureFromTarget(target);
}

/// Destroy a texture created with `textureCreate` at the end of the frame.
///
/// While `Backend.textureDestroy` immediately destroys the texture, this
/// function deferres the destruction until the end of the frame, so it is safe
/// to use even in a subwindow where rendering is deferred.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn destroyLater(texture: Texture) void {
    const cw = dvui.currentWindow();
    cw.texture_cache.trash.append(cw.gpa, texture) catch |err| {
        dvui.log.err("Texture destroyLater got {any}\n", .{err});
    };
}

const std = @import("std");
const dvui = @import("dvui.zig");

const Size = dvui.Size;
const Color = dvui.Color;
const IconRenderOptions = dvui.IconRenderOptions;
const TextureInterpolation = dvui.enums.TextureInterpolation;

const TextureError = dvui.Backend.TextureError;
const StbImageError = dvui.StbImageError;
const TvgError = dvui.TvgError;

test {
    @import("std").testing.refAllDecls(@This());
}
