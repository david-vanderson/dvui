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
    /// Use Options.rect as natural coords
    absolute,
};

pub const InitOptions = struct {
    /// Show when mouse enters this physical rect
    active_rect: Rect.Physical,

    position: Position = .horizontal,

    /// Is true if the user should be able to hover the tooltips content without it disappearing
    interactive: bool = false,
};

parent_tooltip: ?*FloatingTooltipWidget = null,
prev_rendering: bool = undefined,
wd: WidgetData = undefined,
prev_windowId: dvui.WidgetId = undefined,
prevClip: Rect.Physical = .{},
scale_val: f32 = undefined,
scaler: dvui.ScaleWidget = undefined,
options: Options = undefined,
init_options: InitOptions = undefined,
showing: bool = false,
mouse_good_this_frame: bool = false,
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
        self.options.min_size_content = msc.scale(self.scale_val, Size);
    }

    // passing options.rect will stop WidgetData.init from calling
    // rectFor/minSizeForChild which is important because we are outside
    // normal layout
    self.wd = WidgetData.init(src, .{ .subwindow = true }, (Options{ .name = "FloatingTooltip" }).override(.{ .rect = self.options.rect orelse .{} }));

    // if a rect got passed, we don't want to also pass it to scaler
    self.options.rect = null;

    self.init_options = init_opts;
    self.showing = dvui.dataGet(null, self.wd.id, "_showing", bool) orelse false;

    return self;
}

pub fn shown(self: *FloatingTooltipWidget) bool {
    // protect against this being called multiple times
    if (self.installed) {
        return true;
    }

    // check for mouse position in active_rect
    const evts = dvui.events();
    for (evts) |*e| {
        if (!dvui.eventMatch(e, .{ .id = self.wd.id, .r = self.init_options.active_rect })) {
            continue;
        }

        if (e.evt == .mouse and e.evt.mouse.action == .position) {
            self.mouse_good_this_frame = true;
            if (!self.showing) {
                self.showing = true;
            }
        }
    }

    if (self.showing) {
        switch (self.init_options.position) {
            .horizontal, .vertical => |o| {
                const ar = self.init_options.active_rect.toNatural();
                const r = Rect.Natural.fromPoint(ar.topLeft()).toSize(.cast(self.wd.rect.size()));
                self.wd.rect = .cast(dvui.placeOnScreen(dvui.windowRect(), ar, if (o == .horizontal) .horizontal else .vertical, r));
            },
            .sticky => {
                if (dvui.firstFrame(self.wd.id)) {
                    const mp = dvui.currentWindow().mouse_pt.toNatural();
                    dvui.dataSet(null, self.wd.id, "_sticky_pt", mp);
                } else {
                    const mp = dvui.dataGet(null, self.wd.id, "_sticky_pt", dvui.Point.Natural) orelse dvui.Point.Natural{};
                    var r = Rect.Natural.fromPoint(mp).toSize(.cast(self.wd.rect.size()));
                    r.x += 10;
                    r.y -= r.h + 10;
                    self.wd.rect = .cast(dvui.placeOnScreen(dvui.windowRect(), .{}, .none, r));
                }
            },
            .absolute => {},
        }
        //std.debug.print("rect {}\n", .{self.wd.rect});

        self.install();

        if (self.init_options.interactive) {
            // check for mouse position in tooltip window rect
            for (evts) |*e| {
                if (!dvui.eventMatch(e, .{ .id = self.wd.id, .r = self.wd.borderRectScale().r })) {
                    continue;
                }

                if (e.evt == .mouse and e.evt.mouse.action == .position) {
                    self.mouse_good_this_frame = true;
                }
            }
        }

        return true;
    }

    return false;
}

pub fn install(self: *FloatingTooltipWidget) void {
    self.installed = true;
    self.prev_rendering = dvui.renderingSet(false);

    dvui.parentSet(self.widget());

    self.prev_windowId = dvui.subwindowCurrentSet(self.wd.id, null).id;
    self.parent_tooltip = tooltipSet(self);

    const rs = self.wd.rectScale();

    dvui.subwindowAdd(self.wd.id, self.wd.rect, rs.r, false, self.prev_windowId);
    dvui.captureMouseMaintain(.{ .id = self.wd.id, .rect = rs.r, .subwindow_id = self.wd.id });
    self.wd.register();

    // first clip to the whole window to break out of whatever clipping we
    // might have been in (example: might be nested inside another tooltip)
    self.prevClip = dvui.clipGet();
    dvui.clipSet(dvui.windowRectPixels());

    // scaler is what is drawing our background/border/box_shadow
    self.scaler = dvui.ScaleWidget.init(@src(), .{ .scale = &self.scale_val }, self.options.override(.{ .expand = .both }));
    self.scaler.install();

    // clip to just our window (using clipSet since we are not inside our parent)
    _ = dvui.clip(rs.r);
}

pub fn widget(self: *FloatingTooltipWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *FloatingTooltipWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *FloatingTooltipWidget, id: dvui.WidgetId, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *FloatingTooltipWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *FloatingTooltipWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
}

pub fn deinit(self: *FloatingTooltipWidget) void {
    defer dvui.widgetFree(self);
    if (!self.installed) {
        return;
    }

    // check if we should still be shown
    if (self.mouse_good_this_frame or (self.init_options.interactive and self.tt_child_shown)) {
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
    self.* = undefined;
}

test {
    @import("std").testing.refAllDecls(@This());
}
