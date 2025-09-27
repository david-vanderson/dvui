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

wd: WidgetData,
init_opts: InitOptions,
hash: u64,
refresh_prev_value: u8,
state: enum { ok, texture_create_error, unsupported } = .ok,
caching_tex: ?dvui.TextureTarget = null,
tex_uv: Size,
/// SAFETY: Must be set when `caching_tex` is not null
old_target: dvui.RenderTarget = undefined,
old_clip: ?Rect.Physical = null,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) CacheWidget {
    const defaults = Options{ .name = "Cache" };
    const wd = WidgetData.init(src, .{}, defaults.override(opts));
    var self = CacheWidget{
        .wd = wd,
        .init_opts = init_opts,
        .hash = wd.id.update("_tex").asU64(),
        .tex_uv = dvui.dataGet(null, wd.id, "_tex_uv", Size) orelse .{},
        .refresh_prev_value = dvui.currentWindow().extra_frames_needed,
    };
    dvui.currentWindow().extra_frames_needed = 0;
    if (dvui.dataGet(null, self.wd.id, "_unsupported", bool) orelse false) self.state = .unsupported;
    return self;
}

fn drawCachedTexture(self: *CacheWidget, t: dvui.Texture) void {
    const rs = self.data().contentRectScale();

    dvui.renderTexture(t, rs, .{
        .uv = (Rect{}).toSize(self.tex_uv),
    }) catch |err| {
        dvui.logError(@src(), err, "Could not render texture", .{});
    };
    //if (self.data().options.debugGet()) {
    //    dvui.log.debug("drawing {d} {d} {d}x{d} {d}x{d} {d} {d}", .{ rs.r.x, rs.r.y, rs.r.w, rs.r.h, t.texture.width, t.texture.height, self.tex_uv.w, self.tex_uv.h });
    //}
}

/// Must be called before install().
pub fn invalidate(self: *CacheWidget) void {
    self.init_opts.invalidate = true;
}

pub fn install(self: *CacheWidget) void {
    dvui.parentSet(self.widget());
    self.data().register();
    self.data().borderAndBackground(.{});

    if (self.init_opts.invalidate) {
        if (dvui.textureGetCached(self.hash)) |t| {
            // if we had a texture, show it this frame because our contents needs a frame to get sizing
            self.drawCachedTexture(t);
            dvui.textureInvalidateCache(self.hash);

            // now we've shown the texture, so prevent any widgets from drawing on top of it this frame
            // - can happen if some widgets precalculate their size (like label)
            self.old_clip = dvui.clip(.{});
        }
    }

    if (self.state != .ok) return;

    if (dvui.textureGetCached(self.hash)) |t| {
        // successful cache, draw texture and enforce min size
        self.drawCachedTexture(t);
        self.data().minSizeMax(self.data().rect.size());
    } else {

        // we need to cache, but only do it if we didn't have any refreshes from last frame
        if (dvui.dataGet(null, self.data().id, "_cache_now", bool) orelse false) {
            const rs = self.data().contentRectScale();
            const w: u32 = @intFromFloat(@ceil(rs.r.w));
            const h: u32 = @intFromFloat(@ceil(rs.r.h));
            self.tex_uv = .{ .w = rs.r.w / @ceil(rs.r.w), .h = rs.r.h / @ceil(rs.r.h) };

            self.caching_tex = dvui.textureCreateTarget(w, h, .linear) catch |err| blk: switch (err) {
                error.TextureCreate => {
                    self.state = .texture_create_error;
                    if (dvui.dataGet(null, self.data().id, "_texture_create_error", bool) orelse false) {
                        // indicate that texture failed last frame to prevent backends that always return errors from forever refreshing
                        dvui.dataSet(null, self.data().id, "_texture_create_error", true);
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
                dvui.dataSet(null, self.data().id, "_unsupported", true);
            }
        }
    }
}

/// Must be called after install().
pub fn uncached(self: *const CacheWidget) bool {
    return (self.caching_tex != null or dvui.textureGetCached(self.hash) == null);
}

pub fn widget(self: *CacheWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *CacheWidget) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *CacheWidget, id: dvui.Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.data().contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *CacheWidget, rect: Rect) RectScale {
    return self.data().contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *CacheWidget, s: Size) void {
    self.data().minSizeMax(self.data().options.padSize(s));
}

/// This deinit function returns an error because of the additional
/// texture handling it requires.
pub fn deinit(self: *CacheWidget) void {
    const should_free = self.data().was_allocated_on_widget_stack;
    defer if (should_free) dvui.widgetFree(self);
    defer self.* = undefined;
    const cw = dvui.currentWindow();
    if (self.state == .ok and self.uncached()) {
        if (dvui.currentWindow().extra_frames_needed == 0) {
            dvui.dataSet(null, self.data().id, "_cache_now", true);
            dvui.refresh(null, @src(), self.data().id);
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
        dvui.textureAddToCache(self.hash, texture);
        // draw texture so we see it this frame
        self.drawCachedTexture(texture);

        dvui.dataSet(null, self.data().id, "_tex_uv", self.tex_uv);
        dvui.dataRemove(null, self.data().id, "_cache_now");
    }
    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();
    dvui.parentReset(self.data().id, self.data().parent);
}

pub const Helpers = struct {
    pub fn cache(src: std.builtin.SourceLocation, init_opts: CacheWidget.InitOptions, opts: Options) *CacheWidget {
        var ret = dvui.widgetAlloc(CacheWidget);
        ret.* = CacheWidget.init(src, init_opts, opts);
        ret.data().was_allocated_on_widget_stack = true;
        ret.install();
        return ret;
    }
};

test {
    @import("std").testing.refAllDecls(@This());
}
