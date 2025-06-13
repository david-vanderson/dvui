const std = @import("std");
const dvui = @import("../dvui.zig");

const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;
const Options = dvui.Options;
const Size = dvui.Size;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;

const CacheWidget = @This();

pub const InitOptions = struct {
    invalidate: bool = false,
};

wd: WidgetData = undefined,
hash: u64 = undefined,
refresh_prev_value: u8 = undefined,
state: enum { ok, texture_create_error, unsupported } = .ok,
caching_tex: ?dvui.TextureTarget = null,
tex_uv: Size = undefined,
old_target: dvui.RenderTarget = undefined,
old_clip: ?Rect.Physical = null,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) CacheWidget {
    _ = init_opts;
    var self = CacheWidget{};
    const defaults = Options{ .name = "Cache" };
    self.wd = WidgetData.init(src, .{}, defaults.override(opts));

    self.hash = dvui.hashIdKey(self.wd.id, "_tex");
    if (dvui.dataGet(null, self.wd.id, "_tex_uv", Size)) |uv| self.tex_uv = uv;
    if (dvui.dataGet(null, self.wd.id, "_unsupported", bool) orelse false) self.state = .unsupported;
    self.tex_uv = dvui.dataGet(null, self.wd.id, "_tex_uv", Size) orelse .{};
    self.refresh_prev_value = dvui.currentWindow().extra_frames_needed;
    dvui.currentWindow().extra_frames_needed = 0;
    return self;
}

fn getCachedTexture(self: *CacheWidget) ?dvui.Texture {
    const entry = dvui.currentWindow().texture_cache.getPtr(self.hash) orelse return null;
    return entry.texture;
}

fn drawCachedTexture(self: *CacheWidget, t: dvui.Texture) void {
    const rs = self.wd.contentRectScale();

    dvui.renderTexture(t, rs, .{
        .uv = (Rect{}).toSize(self.tex_uv),
        .debug = self.wd.options.debugGet(),
    }) catch |err| {
        dvui.logError(@src(), err, "Could not render texture", .{});
    };
    //if (self.wd.options.debugGet()) {
    //    dvui.log.debug("drawing {d} {d} {d}x{d} {d}x{d} {d} {d}", .{ rs.r.x, rs.r.y, rs.r.w, rs.r.h, t.texture.width, t.texture.height, self.tex_uv.w, self.tex_uv.h });
    //}
}

/// Must be called before install().
pub fn invalidate(self: *CacheWidget) void {
    if (self.getCachedTexture()) |t| {
        // if we had a texture, show it this frame because our contents needs a frame to get sizing
        self.drawCachedTexture(t);

        dvui.textureDestroyLater(t);
        _ = dvui.currentWindow().texture_cache.remove(self.hash);

        // now we've shown the texture, so prevent any widgets from drawing on top of it this frame
        // - can happen if some widgets precalculate their size (like label)
        self.old_clip = dvui.clip(.{});
    }
}

pub fn install(self: *CacheWidget) void {
    dvui.parentSet(self.widget());
    self.wd.register();
    self.wd.borderAndBackground(.{});

    if (self.state != .ok) return;

    if (self.getCachedTexture()) |t| {
        // successful cache, draw texture and enforce min size
        self.drawCachedTexture(t);
        self.wd.minSizeMax(self.wd.rect.size());
    } else {

        // we need to cache, but only do it if we didn't have any refreshes from last frame
        if (dvui.dataGet(null, self.wd.id, "_cache_now", bool) orelse false) {
            const rs = self.wd.contentRectScale();
            const w: u32 = @intFromFloat(@ceil(rs.r.w));
            const h: u32 = @intFromFloat(@ceil(rs.r.h));
            self.tex_uv = .{ .w = rs.r.w / @ceil(rs.r.w), .h = rs.r.h / @ceil(rs.r.h) };

            self.caching_tex = dvui.textureCreateTarget(w, h, .linear) catch |err| blk: switch (err) {
                error.TextureCreate => {
                    self.state = .texture_create_error;
                    if (dvui.dataGet(null, self.wd.id, "_texture_create_error", bool) orelse false) {
                        // indicate that texture failed last frame to prevent backends that always return errors from forever refreshing
                        dvui.dataSet(null, self.wd.id, "_texture_create_error", true);
                    }
                    break :blk null;
                },
                else => {
                    dvui.logError(@src(), err, "Could not create cache texture", .{});
                    break :blk null;
                },
            };

            if (self.caching_tex) |tex| {
                var offset = rs.r.topLeft();
                if (dvui.snapToPixels()) {
                    offset.x = @round(offset.x);
                    offset.y = @round(offset.y);
                }
                self.old_target = dvui.renderTarget(.{ .texture = tex, .offset = offset });

                // clip to just us, even if we are off screen
                self.old_clip = dvui.clipGet();
                dvui.clipSet(rs.r);
            } else if (self.state != .texture_create_error) {
                // `textureCreateTarget` returned null, indicating render target are unsupported
                dvui.dataSet(null, self.wd.id, "_unsupported", true);
            }
        }
    }
}

/// Must be called after install().
pub fn uncached(self: *CacheWidget) bool {
    return (self.caching_tex != null or self.getCachedTexture() == null);
}

pub fn widget(self: *CacheWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *CacheWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *CacheWidget, id: dvui.WidgetId, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *CacheWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *CacheWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
}

pub fn processEvent(self: *CacheWidget, e: *dvui.Event, bubbling: bool) void {
    _ = bubbling;
    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

/// This deinit function returns an error because of the additional
/// texture handling it requires.
pub fn deinit(self: *CacheWidget) void {
    defer dvui.widgetFree(self);
    const cw = dvui.currentWindow();
    if (self.state == .ok and self.uncached()) {
        if (dvui.currentWindow().extra_frames_needed == 0) {
            dvui.dataSet(null, self.wd.id, "_cache_now", true);
            dvui.refresh(null, @src(), self.wd.id);
        }
    }
    cw.extra_frames_needed = @max(cw.extra_frames_needed, self.refresh_prev_value);

    if (self.old_clip) |clip| {
        dvui.clipSet(clip);
    }
    if (self.caching_tex) |tex| blk: {
        _ = dvui.renderTarget(self.old_target);

        // convert texture target to normal texture, destroys self.caching_tex
        const texture = dvui.textureFromTarget(tex) catch |err| {
            dvui.logError(@src(), err, "Could not get texture from caching target", .{});
            break :blk;
        };
        cw.texture_cache.put(cw.gpa, self.hash, .{ .texture = texture }) catch |err| {
            dvui.logError(@src(), err, "Could not put texture into the cache", .{});
            break :blk;
        };
        // draw texture so we see it this frame
        self.drawCachedTexture(texture);

        dvui.dataSet(null, self.wd.id, "_tex_uv", self.tex_uv);
        dvui.dataRemove(null, self.wd.id, "_cache_now");
    }
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    dvui.parentReset(self.wd.id, self.wd.parent);
    self.* = undefined;
}

test {
    @import("std").testing.refAllDecls(@This());
}
