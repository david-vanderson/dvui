const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const FloatingWidget = @This();

pub var defaults: Options = .{
    .name = "Floating",
};

pub const InitOptions = struct {
    /// Whether mouse events can match this.  Set to false if this is a drag
    /// image (so the mouse release will match the window under this).
    mouse_events: bool = true,

    /// If not null, get min size and position according to from_gravity.
    /// If you know the size already, leave this null and use Options.rect.
    from: ?dvui.Point.Physical = null,
    from_gravity_x: f32 = 0.5,
    from_gravity_y: f32 = 0.5,
};

init_opts: InitOptions,
prev_rendering: bool = undefined,
wd: WidgetData,
prev_windowId: dvui.Id = undefined,
prevClip: Rect.Physical = undefined,
scale_val: f32,
scaler: dvui.ScaleWidget = undefined,

/// FloatingWidget is a subwindow to show any temporary floating thing.
/// It doesn't focus itself (as a subwindow), and whether it is shown or not is
/// entirely up to the calling code.
///
/// Don't put menus or menuItems in a floating widget because those depend on
/// focus to work.  FloatingMenu is made for that.
///
/// Use FloatingWindowWidget for a floating window that the user can change
/// size, move around, and adjust stacking.
pub fn init(self: *FloatingWidget, src: std.builtin.SourceLocation, init_opts: InitOptions, opts_in: Options) void {
    const scale_val = dvui.parentGet().screenRectScale(Rect{}).s / dvui.windowNaturalScale();
    var opts = opts_in;
    if (opts.min_size_content) |msc| {
        opts.min_size_content = msc.scale(scale_val, Size);
    }
    self.* = .{
        // get scale from parent
        .scale_val = scale_val,
        .init_opts = init_opts,
        .wd = WidgetData.init(src, .{ .subwindow = true }, defaults.override(opts).override(.{
            // passing options.rect will stop WidgetData.init from calling
            // rectFor/minSizeForChild which is important because we are outside
            // normal layout
            .rect = opts.rect orelse .{},
        })),
    };

    if (init_opts.from) |pt| {
        if (dvui.minSizeGet(self.data().id)) |_| {
            const ms = dvui.minSize(self.data().id, opts.min_sizeGet());
            const npt = dvui.windowRectScale().pointFromPhysical(pt);
            var start: Rect = .fromPoint(.cast(npt));
            start = start.toSize(ms);
            start.x -= start.w * (1.0 - init_opts.from_gravity_x);
            start.y -= start.h * (1.0 - init_opts.from_gravity_y);
            self.data().rect = .cast(dvui.placeOnScreen(dvui.windowRect(), .{}, .none, .cast(start)));
        } else {
            // need another frame to get our min size
            dvui.refresh(null, @src(), self.data().id);
        }
    }

    self.prev_rendering = dvui.renderingSet(false);
    self.data().register();

    dvui.parentSet(self.widget());

    self.prev_windowId = dvui.subwindowCurrentSet(self.data().id, null).id;

    const rs = self.data().rectScale();

    dvui.subwindowAdd(self.data().id, self.data().rect, rs.r, false, self.prev_windowId, self.init_opts.mouse_events);
    dvui.captureMouseMaintain(.{ .id = self.data().id, .rect = rs.r, .subwindow_id = self.data().id });

    // first break out of whatever clipping we were in
    self.prevClip = dvui.clipGet();
    dvui.clipSet(dvui.windowRectPixels());

    self.data().borderAndBackground(.{});

    // clip to just our window (using clipSet since we are not inside our parent)
    _ = dvui.clip(rs.r);

    self.scaler.init(@src(), .{ .scale = &self.scale_val }, .{ .expand = .both });
}

pub fn widget(self: *FloatingWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *FloatingWidget) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *FloatingWidget, id: dvui.Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.data().contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *FloatingWidget, rect: Rect) RectScale {
    return self.data().contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *FloatingWidget, s: Size) void {
    self.data().minSizeMax(self.data().options.padSize(s));
}

pub fn deinit(self: *FloatingWidget) void {
    defer if (dvui.widgetIsAllocated(self)) dvui.widgetFree(self);
    defer self.* = undefined;
    self.scaler.deinit();
    self.data().minSizeSetAndRefresh();

    // outside normal layout, don't call minSizeForChild or self.data().minSizeReportToParent();

    dvui.parentReset(self.data().id, self.data().parent);
    _ = dvui.subwindowCurrentSet(self.prev_windowId, null);
    dvui.clipSet(self.prevClip);
    _ = dvui.renderingSet(self.prev_rendering);
}

test {
    @import("std").testing.refAllDecls(@This());
}
