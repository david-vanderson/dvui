const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const FloatingTooltipWidget = @This();

// maintain a chain of all the nested FloatingTooltipWidgets
var tooltip_current: ?*FloatingTooltipWidget = null;

fn tooltipSet(tt: ?*FloatingTooltipWidget) ?*FloatingTooltipWidget {
    const ret = tooltip_current;
    tooltip_current = tt;
    return ret;
}

pub var defaults: Options = .{
    .name = "Tooltip",
    .corner_radius = Rect.all(5),
    .border = Rect.all(1),
    .background = true,
};

pub const Position = enum {
    /// Right of active_rect
    horizontal,
    /// Below active_rect
    vertical,
    /// Starts where mouse is but stays there
    sticky,
};

pub const InitOptions = struct {
    /// Show when mouse enters this rect in screen pixels
    active_rect: Rect,

    position: Position = .horizontal,
};

parent_tooltip: ?*FloatingTooltipWidget = null,
prev_rendering: bool = undefined,
wd: WidgetData = undefined,
prev_windowId: u32 = 0,
prevClip: Rect = Rect{},
scale_val: f32 = undefined,
scaler: dvui.ScaleWidget = undefined,
options: Options = undefined,
init_options: InitOptions = undefined,
showing: bool = false,
installed: bool = false,
tt_child_shown: bool = false,

/// FloatingTooltipWidget is a subwindow to show temporary floating tooltips,
/// possibly nested. It doesn't focus itself (as a subwindow).
///
/// Will show when the mouse is in the active rect.
///
/// Will stop if the mouse is outside the active rect AND outside
/// FloatingTooltipWidget's rect AND no nested FloatingTooltipWidget is still
/// showing.
///
/// Don't put menus or menuItems in this those depend on focus to work.
/// FloatingMenu is made for that.
///
/// Use FloatingWindowWidget for a floating window that the user can change
/// size, move around, and adjust stacking.
pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts_in: Options) FloatingTooltipWidget {
    var self = FloatingTooltipWidget{};

    // get scale from parent
    self.scale_val = dvui.parentGet().screenRectScale(Rect{}).s / dvui.windowNaturalScale();
    self.options = defaults.override(opts_in);
    if (self.options.min_size_content) |msc| {
        self.options.min_size_content = msc.scale(self.scale_val);
    }

    // passing options.rect will stop WidgetData.init from calling
    // rectFor/minSizeForChild which is important because we are outside
    // normal layout
    self.wd = WidgetData.init(src, .{ .subwindow = true }, (Options{ .name = "FloatingTooltip" }).override(.{ .rect = self.options.rect orelse .{} }));

    self.init_options = init_opts;
    self.showing = dvui.dataGet(null, self.wd.id, "_showing", bool) orelse false;

    return self;
}

pub fn shown(self: *FloatingTooltipWidget) !bool {
    // protect against this being called multiple times
    if (self.installed) {
        return true;
    }

    if (!self.showing) {
        // check if we should show
        const cw = dvui.currentWindow();
        if (cw.windowFor(cw.mouse_pt) == cw.subwindow_currentId and self.init_options.active_rect.contains(cw.mouse_pt)) {
            self.showing = true;
        }
    }

    if (self.showing) {
        switch (self.init_options.position) {
            .horizontal, .vertical => |o| {
                const ar = self.init_options.active_rect.scale(1 / dvui.windowNaturalScale());
                const r: Rect = dvui.Rect.fromPoint(ar.topLeft()).toSize(self.wd.rect.size());
                self.wd.rect = dvui.placeOnScreen(dvui.windowRect(), ar, if (o == .horizontal) .horizontal else .vertical, r);
            },
            .sticky => {
                if (dvui.firstFrame(self.wd.id)) {
                    const mp = dvui.currentWindow().mouse_pt.scale(1 / dvui.windowNaturalScale());
                    dvui.dataSet(null, self.wd.id, "_sticky_pt", mp);
                } else {
                    const mp = dvui.dataGet(null, self.wd.id, "_sticky_pt", dvui.Point) orelse dvui.Point{};
                    var r: Rect = dvui.Rect.fromPoint(mp).toSize(self.wd.rect.size());
                    r.x += 10;
                    r.y -= r.h + 10;
                    self.wd.rect = dvui.placeOnScreen(dvui.windowRect(), .{}, .none, r);
                }
            },
        }
        //std.debug.print("rect {}\n", .{self.wd.rect});

        try self.install();

        return true;
    }

    return false;
}

pub fn install(self: *FloatingTooltipWidget) !void {
    self.installed = true;
    self.prev_rendering = dvui.renderingSet(false);

    dvui.parentSet(self.widget());

    self.prev_windowId = dvui.subwindowCurrentSet(self.wd.id, null).id;
    self.parent_tooltip = tooltipSet(self);

    const rs = self.wd.rectScale();

    try dvui.subwindowAdd(self.wd.id, self.wd.rect, rs.r, false, self.prev_windowId);
    dvui.captureMouseMaintain(self.wd.id);
    try self.wd.register();

    // clip to just our window (using clipSet since we are not inside our parent)
    self.prevClip = dvui.clipGet();
    dvui.clipSet(rs.r);

    self.scaler = dvui.ScaleWidget.init(@src(), self.scale_val, self.options.override(.{ .expand = .both }));
    try self.scaler.install();
}

pub fn widget(self: *FloatingTooltipWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *FloatingTooltipWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *FloatingTooltipWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *FloatingTooltipWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *FloatingTooltipWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
}

pub fn processEvent(self: *FloatingTooltipWidget, e: *Event, bubbling: bool) void {
    // no event processing, everything stops
    _ = self;
    _ = e;
    _ = bubbling;
}

pub fn deinit(self: *FloatingTooltipWidget) void {
    if (!self.installed) {
        return;
    }

    // check if we should still be shown
    const mp = dvui.currentWindow().mouse_pt;
    if (self.tt_child_shown or self.init_options.active_rect.contains(mp) or self.wd.rectScale().r.contains(mp)) {
        dvui.dataSet(null, self.wd.id, "_showing", true);
        var parent: ?*FloatingTooltipWidget = self.parent_tooltip;
        while (parent) |p| {
            p.tt_child_shown = true;
            parent = p.parent_tooltip;
        }
    } else {
        // don't store showing if mouse is outside trigger and tooltip which will close it next frame
        dvui.dataRemove(null, self.wd.id, "_showing");
        dvui.refresh(null, @src(), self.wd.id); // refresh with new hidden state
    }

    self.scaler.deinit();
    self.wd.minSizeSetAndRefresh();

    // outside normal layout, don't call minSizeForChild or self.wd.minSizeReportToParent();

    _ = tooltipSet(self.parent_tooltip);
    dvui.parentReset(self.wd.id, self.wd.parent);
    _ = dvui.subwindowCurrentSet(self.prev_windowId, null);
    dvui.clipSet(self.prevClip);
    _ = dvui.renderingSet(self.prev_rendering);
}
