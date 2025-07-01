const std = @import("std");
const dvui = @import("dvui.zig");

const Color = dvui.Color;
const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetId = dvui.WidgetId;
const WidgetData = @This();

pub const InitOptions = struct {
    // if true, don't send our rect through our parent because we aren't located inside our parent
    subwindow: bool = false,
};

id: WidgetId,
parent: Widget,
init_options: InitOptions,
rect: Rect,
min_size: Size,
options: Options,
src: std.builtin.SourceLocation,
rect_scale_cache: ?RectScale = null,

pub fn init(src: std.builtin.SourceLocation, init_options: InitOptions, options: Options) WidgetData {
    const parent = dvui.parentGet();
    const id = parent.extendId(src, options.idExtra());
    const min_size = options.min_sizeGet().min(options.max_sizeGet());

    const ms = dvui.minSize(id, min_size);

    const rect = if (options.rect) |r|
        r.toSize(.{
            .w = if (options.expandGet().isHorizontal())
                parent.data().contentRect().w
            else if (r.w == 0) ms.w else r.w,
            .h = if (options.expandGet().isVertical())
                parent.data().contentRect().h
            else if (r.h == 0) ms.h else r.h,
        })
    else blk: {
        if (options.expandGet() == .ratio and (ms.w == 0 or ms.h == 0)) {
            dvui.log.debug("rectFor {x} expand is .ratio but min size is zero\n", .{id});
        }
        break :blk parent.rectFor(id, ms, options.expandGet(), options.gravityGet());
    };

    return .{
        .id = id,
        .parent = parent,
        .init_options = init_options,
        .min_size = min_size,
        .rect = rect,
        .options = options,
        .src = src,
    };
}

pub fn register(self: *WidgetData) void {
    self.rect_scale_cache = self.rectScale();

    // for normal widgets this is fine, but subwindows have to take care to
    // call captureMouseMaintain after subwindowCurrentSet and subwindowAdd
    if (!self.init_options.subwindow) {
        dvui.captureMouseMaintain(.{ .id = self.id, .rect = self.borderRectScale().r, .subwindow_id = dvui.subwindowCurrentId() });
    }

    var cw = dvui.currentWindow();
    const name: []const u8 = self.options.name orelse "???";

    if (self.options.tag) |t| {
        dvui.tag(t, .{ .id = self.id, .rect = self.rectScale().r, .visible = self.visible() });
    }

    cw.last_registered_id_this_frame = self.id;

    const focused_widget_id = dvui.focusedWidgetId();
    if (self.id == focused_widget_id) {
        cw.last_focused_id_this_frame = self.id;

        if (cw.scroll_to_focused) {
            cw.scroll_to_focused = false;
            dvui.scrollTo(.{
                .screen_rect = self.rectScale().r,
            });
        }
    }

    if (dvui.testing.widget_hasher) |*hasher| {
        hasher.update(std.mem.asBytes(&self.init_options));
        hasher.update(std.mem.asBytes(&self.options.hash()));
        hasher.update(std.mem.asBytes(&self.rectScale()));
        hasher.update(std.mem.asBytes(&self.visible()));
        hasher.update(std.mem.asBytes(&(self.id == focused_widget_id)));
    }

    if (cw.debug_under_focus and self.id == focused_widget_id) {
        cw.debug_widget_id = self.id;
    }

    if (cw.debug_under_mouse or self.id == cw.debug_widget_id) {
        var rs = self.rectScale();

        if (cw.debug_under_mouse and
            rs.r.contains(cw.mouse_pt) and
            // prevents stuff in scroll area outside viewport being caught
            dvui.clipGet().contains(cw.mouse_pt) and
            // prevents stuff in lower subwindows being caught
            cw.windowFor(cw.mouse_pt) == dvui.subwindowCurrentId())
        {
            const old = cw.debug_under_mouse_info;
            cw.debug_under_mouse_info = std.fmt.allocPrint(cw.gpa, "{s}\n{x} {s}", .{ old, self.id, name }) catch |err| blk: {
                dvui.logError(@src(), err, "Under mouse debug info could not be printed", .{});
                break :blk "";
            };
            if (old.len > 0) {
                cw.gpa.free(old);
            }

            cw.debug_widget_id = self.id;
        }

        if (self.id == cw.debug_widget_id) {
            if (cw.debug_widget_panic) {
                @panic("Debug Window Panic");
            }

            var min_size = Size{};
            if (dvui.minSizeGet(self.id)) |ms| {
                min_size = ms;
            }
            cw.debug_info_name_rect = std.fmt.allocPrint(cw.arena(), "{x} {s}\n\n{}\nmin {}\n{}\nscale {d}\npadding {}\nborder {}\nmargin {}", .{
                self.id,
                name,
                rs.r,
                min_size,
                self.options.expandGet(),
                rs.s,
                self.options.paddingGet().scale(rs.s, Rect.Physical),
                self.options.borderGet().scale(rs.s, Rect.Physical),
                self.options.marginGet().scale(rs.s, Rect.Physical),
            }) catch "ERROR allocPrint";
            const clipr = dvui.clipGet();
            // clip to whole window so we always see the outline
            dvui.clipSet(dvui.windowRectPixels());

            // intersect our rect with the clip - we only want to outline
            // the visible part
            var outline_rect = rs.r.intersect(clipr);

            // make sure something is visible
            outline_rect.w = @max(outline_rect.w, 1);
            outline_rect.h = @max(outline_rect.h, 1);

            if (cw.snap_to_pixels) {
                outline_rect.x = @ceil(outline_rect.x) - 0.5;
                outline_rect.y = @ceil(outline_rect.y) - 0.5;
            }

            outline_rect.stroke(.{}, .{ .thickness = 1 * rs.s, .color = dvui.themeGet().color_err, .after = true });

            dvui.clipSet(clipr);

            cw.debug_info_src_id_extra = std.fmt.allocPrint(cw.arena(), "{s}:{d}\nid_extra {d}", .{ self.src.file, self.src.line, self.options.idExtra() }) catch "ERROR allocPrint";
        }
    }
}

pub fn visible(self: *const WidgetData) bool {
    return !dvui.clipGet().intersect(self.borderRectScale().r).empty();
}

pub fn borderAndBackground(self: *const WidgetData, opts: struct { fill_color: ?Color = null }) void {
    if (!self.visible()) {
        return;
    }

    if (self.options.box_shadow) |bs| {
        const rs = self.borderRectScale();
        const radius = bs.corner_radius orelse self.options.corner_radiusGet();

        const prect = rs.r.insetAll(rs.s * bs.shrink).offsetPoint(bs.offset.scale(rs.s, dvui.Point.Physical));

        prect.fill(radius.scale(rs.s, Rect.Physical), .{ .color = bs.color.resolve().opacity(bs.alpha), .blur = rs.s * bs.blur });
    }

    var bg = self.options.backgroundGet();
    const b = self.options.borderGet();
    if (b.nonZero()) {
        const uniform: bool = (b.x == b.y and b.x == b.w and b.x == b.h);
        if (!bg and uniform) {
            // draw border as stroked path
            const r = self.borderRect().inset(b.scale(0.5, Rect));
            const rs = self.rectScale().rectToRectScale(r.offsetNeg(self.rect));
            rs.r.stroke(self.options.corner_radiusGet().scale(rs.s, Rect.Physical), .{ .thickness = b.x * rs.s, .color = self.options.color(.border) });
        } else {
            // draw border as large rect with background on top
            if (!bg) {
                dvui.log.debug("borderAndBackground {x} forcing background on to support non-uniform border\n", .{self.id});
                bg = true;
            }

            const rs = self.borderRectScale();
            if (!rs.r.empty()) {
                rs.r.fill(self.options.corner_radiusGet().scale(rs.s, Rect.Physical), .{ .color = self.options.color(.border) });
            }
        }
    }

    if (bg) {
        const rs = self.backgroundRectScale();
        if (!rs.r.empty()) {
            rs.r.fill(self.options.corner_radiusGet().scale(rs.s, Rect.Physical), .{ .color = opts.fill_color orelse self.options.color(.fill) });
        }
    }
}

pub fn focusBorder(self: *const WidgetData) void {
    if (self.visible()) {
        const rs = self.borderRectScale();
        const thick = 2 * rs.s;

        rs.r.stroke(self.options.corner_radiusGet().scale(rs.s, Rect.Physical), .{ .thickness = thick, .color = dvui.themeGet().color_accent, .after = true });
    }
}

pub fn rectScale(self: *const WidgetData) RectScale {
    if (self.rect_scale_cache) |rsc| {
        return rsc;
    }

    if (self.init_options.subwindow) {
        return dvui.windowRectScale().rectToRectScale(self.rect);
    }

    return self.parent.screenRectScale(self.rect);
}

pub fn borderRect(self: *const WidgetData) Rect {
    return self.rect.inset(self.options.marginGet());
}

pub fn borderRectScale(self: *const WidgetData) RectScale {
    const r = self.borderRect().offsetNeg(self.rect);
    return self.rectScale().rectToRectScale(r);
}

pub fn backgroundRect(self: *const WidgetData) Rect {
    return self.rect.inset(self.options.marginGet()).inset(self.options.borderGet());
}

pub fn backgroundRectScale(self: *const WidgetData) RectScale {
    const r = self.backgroundRect().offsetNeg(self.rect);
    return self.rectScale().rectToRectScale(r);
}

pub fn contentRect(self: *const WidgetData) Rect {
    return self.rect.inset(self.options.marginGet()).inset(self.options.borderGet()).inset(self.options.paddingGet());
}

pub fn contentRectScale(self: *const WidgetData) RectScale {
    const r = self.contentRect().offsetNeg(self.rect);
    return self.rectScale().rectToRectScale(r);
}

pub fn minSizeMax(self: *WidgetData, s: Size) void {
    self.min_size = Size.max(self.min_size, s);
}

pub fn minSizeSetAndRefresh(self: *WidgetData) void {
    self.min_size = self.min_size.min(self.options.max_sizeGet());

    if (dvui.minSizeGet(self.id)) |ms| {
        // If the size we got was exactly our previous min size then our min size
        // was a binding constraint.  So if our min size changed it might cause
        // layout changes.

        // If this was like a Label where we knew the min size before getting our
        // rect, then either our min size is the same as previous, or our rect is
        // a different size than our previous min size.
        if ((self.rect.w == ms.w and ms.w != self.min_size.w) or
            (self.rect.h == ms.h and ms.h != self.min_size.h))
        {
            //std.debug.print("{x} minSizeSetAndRefresh {} {} {}\n", .{ self.id, self.rect, ms, self.min_size });

            dvui.refresh(null, @src(), self.id);
        }
    } else {
        // This is the first frame for this widget.  Almost always need a
        // second frame to appear correctly since nobody knew our min size the
        // first frame.
        dvui.refresh(null, @src(), self.id);
    }

    var cw = dvui.currentWindow();

    const existing_min_size = cw.min_sizes.fetchPut(cw.gpa, self.id, self.min_size) catch |err| blk: {
        // returning an error here means that all widgets deinit can return
        // it, which is very annoying because you can't "defer try
        // widget.deinit()".  Also if we are having memory issues then we
        // have larger problems than here.
        dvui.log.err("minSizeSetAndRefresh got {!} when trying to set min size of widget {x}\n", .{ err, self.id });

        break :blk null;
    };

    if (existing_min_size) |kv| {
        if (kv.used) {
            const name: []const u8 = self.options.name orelse "???";
            dvui.log.err("{s}:{d} duplicate widget id {x} (widget \"{s}\" highlighted in red); you may need to pass .{{.id_extra=<loop index>}} as widget options (see https://github.com/david-vanderson/dvui/blob/master/readme-implementation.md#widget-ids )\n", .{ self.src.file, self.src.line, self.id, name });
            cw.debug_widget_id = self.id;
        }
    }
}

pub fn minSizeReportToParent(self: *const WidgetData) void {
    if (self.options.rect == null) {
        self.parent.minSizeForChild(self.min_size);
    }
}

pub fn validate(self: *const WidgetData) *WidgetData {
    std.debug.assert(self.id != WidgetId.undef); // Indicates a use after deinit() error.
    return @constCast(self);
}

test {
    @import("std").testing.refAllDecls(@This());
}
