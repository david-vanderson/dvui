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
tex: ?*anyopaque = null,
caching: bool = false,
old_target: dvui.RenderTarget = undefined,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) CacheWidget {
    _ = init_opts;
    var self = CacheWidget{};
    const defaults = Options{ .name = "Cache" };
    self.wd = WidgetData.init(src, .{}, defaults.override(opts));

    self.tex = dvui.dataGet(null, self.wd.id, "_tex", *anyopaque);

    return self;
}

/// Must be called before install().
pub fn invalidate(self: *CacheWidget) !void {
    if (self.tex) |t| {
        // if we had a texture, show it this frame because our contents needs a frame to get sizing
        try dvui.renderTexture(t, self.wd.contentRectScale(), .{});
        dvui.textureDestroyLater(t);
    }
    dvui.dataRemove(null, self.wd.id, "_tex");
    self.tex = null;
}

pub fn install(self: *CacheWidget) !void {
    dvui.parentSet(self.widget());
    try self.wd.register();
    try self.wd.borderAndBackground(.{});

    if (self.tex) |t| {
        // successful cache, draw texture and enforce min size
        var rs = self.wd.contentRectScale();
        rs.r.w = @floor(rs.r.w);
        rs.r.h = @floor(rs.r.h);
        if (self.wd.options.debugGet()) {
            std.debug.print("cached tex {}\n", .{rs.r});
        }
        try dvui.renderTexture(t, rs, .{});
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
            const w: u32 = @intFromFloat(rs.r.w);
            const h: u32 = @intFromFloat(rs.r.h);
            if (self.wd.options.debugGet()) {
                std.debug.print("caching {d} {d}\n", .{ w, h });
            }
            self.tex = dvui.textureCreateTarget(@intFromFloat(rs.r.w), @intFromFloat(rs.r.h), .linear) catch blk: {
                self.caching = false;
                break :blk null;
            };

            if (self.caching) {
                self.old_target = dvui.renderTarget(.{ .texture = self.tex, .offset = rs.r.topLeft() });
            }
        }
    }
}

/// Must be called after install().
pub fn uncached(self: *CacheWidget) bool {
    return (self.caching or self.tex == null);
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
    if (self.caching) {
        _ = dvui.renderTarget(self.old_target);
        dvui.renderTexture(self.tex.?, self.wd.contentRectScale(), .{}) catch {
            dvui.log.debug("{x} CacheWidget.deinit failed to render texture\n", .{self.wd.id});
        };
        dvui.dataSet(null, self.wd.id, "_tex", self.tex.?);
    }
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    dvui.parentReset(self.wd.id, self.wd.parent);
}
