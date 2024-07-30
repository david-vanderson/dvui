const std = @import("std");
const dvui = @import("dvui.zig");

const Color = dvui.Color;
const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;

const WidgetData = @This();

pub const InitOptions = struct {
    // if true, don't send our rect through our parent because we aren't located inside our parent
    subwindow: bool = false,
};

id: u32 = undefined,
parent: Widget = undefined,
init_options: InitOptions = undefined,
rect: Rect = Rect{},
min_size: Size = Size{},
options: Options = undefined,
src: std.builtin.SourceLocation,

pub fn init(src: std.builtin.SourceLocation, init_options: InitOptions, opts: Options) WidgetData {
    var self = WidgetData{ .src = src };
    self.init_options = init_options;
    self.options = opts;

    self.parent = dvui.parentGet();
    self.id = self.parent.extendId(src, opts.idExtra());

    // for normal widgets this is fine, but subwindows have to take care to
    // call captureMouseMaintain after subwindowCurrentSet and subwindowAdd
    if (!init_options.subwindow) {
        dvui.captureMouseMaintain(self.id);
    }

    self.min_size = self.options.min_sizeGet();

    if (self.options.rect) |r| {
        self.rect = r;
        if (self.options.expandGet().isHorizontal()) {
            self.rect.w = self.parent.data().contentRect().w;
        } else if (self.rect.w == 0) {
            self.rect.w = dvui.minSize(self.id, self.min_size).w;
        }

        if (self.options.expandGet().isVertical()) {
            self.rect.h = self.parent.data().contentRect().h;
        } else if (self.rect.h == 0) {
            self.rect.h = dvui.minSize(self.id, self.min_size).h;
        }
    } else {
        self.rect = self.parent.rectFor(self.id, self.min_size, self.options.expandGet(), self.options.gravityGet());
    }

    var cw = dvui.currentWindow();
    if (self.id == cw.debug_widget_id) {
        cw.debug_info_src_id_extra = std.fmt.allocPrint(cw.arena, "{s}:{d}\nid_extra {d}", .{ src.file, src.line, self.options.idExtra() }) catch "ERROR allocPrint";
    }

    return self;
}

pub fn register(self: *const WidgetData) !void {
    var cw = dvui.currentWindow();
    const name: []const u8 = self.options.name orelse "???";
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
            cw.debug_under_mouse_info = try std.fmt.allocPrint(cw.gpa, "{s}\n{x} {s}", .{ old, self.id, name });
            if (old.len > 0) {
                cw.gpa.free(old);
            }

            cw.debug_widget_id = self.id;
        }

        if (self.id == cw.debug_widget_id) {
            var min_size = Size{};
            if (dvui.minSizeGet(self.id)) |ms| {
                min_size = ms;
            }
            cw.debug_info_name_rect = try std.fmt.allocPrint(cw.arena, "{x} {s}\n\n{}\nmin {}\n{}\nscale {d}\npadding {}\nborder {}\nmargin {}", .{ self.id, name, rs.r, min_size, self.options.expandGet(), rs.s, self.options.paddingGet().scale(rs.s), self.options.borderGet().scale(rs.s), self.options.marginGet().scale(rs.s) });
            const clipr = dvui.clipGet();
            // clip to whole window so we always see the outline
            dvui.clipSet(dvui.windowRectPixels());

            // intersect our rect with the clip - we only want to outline
            // the visible part
            var outline_rect = rs.r.intersect(clipr);
            if (cw.snap_to_pixels) {
                outline_rect.x = @ceil(outline_rect.x) - 0.5;
                outline_rect.y = @ceil(outline_rect.y) - 0.5;
            }
            try dvui.pathAddRect(outline_rect, .{});
            const color = dvui.themeGet().color_err;
            try dvui.pathStrokeAfter(true, true, 1 * rs.s, .none, color);
            dvui.clipSet(clipr);
        }
    }
}

pub fn visible(self: *const WidgetData) bool {
    return !dvui.clipGet().intersect(self.borderRectScale().r).empty();
}

pub fn borderAndBackground(self: *const WidgetData, opts: struct { fill_color: ?Color = null }) !void {
    if (!self.visible()) {
        return;
    }

    var bg = self.options.backgroundGet();
    if (self.options.borderGet().nonZero()) {
        if (!bg) {
            dvui.log.debug("borderAndBackground {x} forcing background on to support border\n", .{self.id});
            bg = true;
        }
        const rs = self.borderRectScale();
        if (!rs.r.empty()) {
            try dvui.pathAddRect(rs.r, self.options.corner_radiusGet().scale(rs.s));
            const col = self.options.color(.border);
            try dvui.pathFillConvex(col);
        }
    }

    if (bg) {
        const rs = self.backgroundRectScale();
        if (!rs.r.empty()) {
            try dvui.pathAddRect(rs.r, self.options.corner_radiusGet().scale(rs.s));
            try dvui.pathFillConvex(opts.fill_color orelse self.options.color(.fill));
        }
    }
}

pub fn focusBorder(self: *const WidgetData) !void {
    if (self.visible()) {
        const rs = self.borderRectScale();
        const thick = 2 * rs.s;
        try dvui.pathAddRect(rs.r, self.options.corner_radiusGet().scale(rs.s));
        const color = self.options.color(.accent);
        try dvui.pathStrokeAfter(true, true, thick, .none, color);
    }
}

pub fn rectScale(self: *const WidgetData) RectScale {
    if (self.init_options.subwindow) {
        const s = dvui.windowNaturalScale();
        const scaled = self.rect.scale(s);
        return RectScale{ .r = scaled.offset(dvui.windowRectPixels()), .s = s };
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

pub fn padSize(self: *const WidgetData, s: Size) Size {
    return s.pad(self.options.paddingGet()).pad(self.options.borderGet()).pad(self.options.marginGet());
}

pub fn minSizeMax(self: *WidgetData, s: Size) void {
    self.min_size = Size.max(self.min_size, s);
}

pub fn minSizeSetAndRefresh(self: *const WidgetData) void {
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

    const existing_min_size = cw.min_sizes.fetchPut(self.id, .{ .size = self.min_size }) catch |err| blk: {
        // returning an error here means that all widgets deinit can return
        // it, which is very annoying because you can't "defer try
        // widget.deinit()".  Also if we are having memory issues then we
        // have larger problems than here.
        dvui.log.err("minSizeSetAndRefresh got {!} when trying to set min size of widget {x}\n", .{ err, self.id });

        break :blk null;
    };

    if (existing_min_size) |kv| {
        if (kv.value.used) {
            dvui.log.err("{s}:{d} duplicate widget id {x} (widget highlighted in red); you may need to pass .{{.id_extra=<loop index>}} as widget options (see https://github.com/david-vanderson/dvui/blob/master/readme-implementation.md#widget-ids )\n", .{ self.src.file, self.src.line, self.id });
            cw.debug_widget_id = self.id;
        }
    }
}

pub fn minSizeReportToParent(self: *const WidgetData) void {
    if (self.options.rect == null) {
        self.parent.minSizeForChild(self.min_size);
    }
}
