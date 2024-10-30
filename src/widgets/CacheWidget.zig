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
hash: u32 = undefined,
caching: bool = false,
old_target: dvui.RenderTarget = undefined,
old_clip: ?Rect = null,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) CacheWidget {
    _ = init_opts;
    var self = CacheWidget{};
    const defaults = Options{ .name = "Cache" };
    self.wd = WidgetData.init(src, .{}, defaults.override(opts));

    self.hash = dvui.hashIdKey(self.wd.id, "_tex");
    return self;
}

fn tce(self: *CacheWidget) ?dvui.TextureCacheEntry {
    const cw = dvui.currentWindow();
    if (cw.texture_cache.getPtr(self.hash)) |t| {
        t.used = true;
        return t.*;
    }

    return null;
}

fn drawTce(self: *CacheWidget, t: dvui.TextureCacheEntry) !void {
    const rs = self.wd.contentRectScale();
    const uw = rs.r.w / t.size.w;
    const vh = rs.r.h / t.size.h;

    try dvui.renderTexture(t.texture, rs, .{ .uv = .{ .w = uw, .h = vh }, .debug = self.wd.options.debugGet() });
    if (self.wd.options.debugGet()) {
        dvui.log.debug("drawing {d} {d} {d}x{d} {d}x{d} {d} {d}", .{ rs.r.x, rs.r.y, rs.r.w, rs.r.h, t.size.w, t.size.h, uw, vh });
    }
}

/// Must be called before install().
pub fn invalidate(self: *CacheWidget) !void {
    if (self.tce()) |t| {
        // if we had a texture, show it this frame because our contents needs a frame to get sizing
        try self.drawTce(t);

        dvui.textureDestroyLater(t.texture);
        _ = dvui.currentWindow().texture_cache.remove(self.hash);

        // now we've shown the texture, so prevent any widgets from drawing on top of it this frame
        // - can happen if some widgets precalculate their size (like label)
        self.old_clip = dvui.clip(.{});
    }
}

pub fn install(self: *CacheWidget) !void {
    dvui.parentSet(self.widget());
    try self.wd.register();
    try self.wd.borderAndBackground(.{});

    if (self.tce()) |t| {
        // successful cache, draw texture and enforce min size
        try self.drawTce(t);
        self.wd.minSizeMax(self.wd.rect.size());
    } else {

        // try to cache, but only do it if our size was stable from last frame (to prevent caching on startup)
        if (dvui.dataGet(null, self.wd.id, "_size", dvui.Size)) |bs| {
            if (bs.w == self.wd.rect.w and bs.h == self.wd.rect.h) {
                self.caching = true;
            }
        }

        dvui.dataSet(null, self.wd.id, "_size", self.wd.rect.size());

        if (self.caching) {
            const rs = self.wd.contentRectScale();
            const w: u32 = @intFromFloat(@ceil(rs.r.w));
            const h: u32 = @intFromFloat(@ceil(rs.r.h));
            const tex = dvui.textureCreateTarget(w, h, .linear) catch blk: {
                self.caching = false;
                break :blk null;
            };

            if (self.caching) {
                const entry = dvui.TextureCacheEntry{ .texture = tex.?, .size = .{ .w = @as(f32, @floatFromInt(w)), .h = @as(f32, @floatFromInt(h)) } };
                try dvui.currentWindow().texture_cache.put(self.hash, entry);

                var offset = rs.r.topLeft();
                if (dvui.snapToPixels()) {
                    offset.x = @round(offset.x);
                    offset.y = @round(offset.y);
                }
                self.old_target = dvui.renderTarget(.{ .texture = tex.?, .offset = offset });
            }
        }
    }
}

/// Must be called after install().
pub fn uncached(self: *CacheWidget) bool {
    return (self.caching or self.tce() == null);
}

pub fn widget(self: *CacheWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *CacheWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *CacheWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
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

pub fn deinit(self: *CacheWidget) void {
    if (self.old_clip) |clip| {
        dvui.clipSet(clip);
    }
    if (self.caching) {
        _ = dvui.renderTarget(self.old_target);
        if (self.tce()) |t| {
            // successful cache, draw texture
            self.drawTce(t) catch {
                dvui.log.debug("{x} CacheWidget.deinit failed to render texture\n", .{self.wd.id});
            };
        }
    }
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    dvui.parentReset(self.wd.id, self.wd.parent);
}
