/// This is a widget that forwards all parent calls to its parent.  Useful
/// where you want to wrap widgets but only to adjust their IDs.
const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const FocusGroupWidget = @This();

wd: WidgetData,
child_rect_union: ?Rect = null,

last_focus: dvui.Id,

remember_focus: ?dvui.Id,
tab_index_prev: []dvui.TabIndex,
tab_index: std.ArrayListUnmanaged(dvui.TabIndex) = .empty,

pub fn init(src: std.builtin.SourceLocation, opts: Options) FocusGroupWidget {
    const id = dvui.parentGet().extendId(src, opts.idExtra());
    const rect = dvui.dataGet(null, id, "_rect", Rect);
    const defaults = Options{ .name = "Focus Group", .rect = rect orelse .{} };
    return FocusGroupWidget{
        .wd = WidgetData.init(src, .{}, defaults.override(opts)),
        .last_focus = dvui.lastFocusedIdInFrame(),
        .tab_index_prev = dvui.dataGetSlice(null, id, "_tab_prev", []dvui.TabIndex) orelse &.{},
        .remember_focus = dvui.dataGet(null, id, "_remember_focus", dvui.Id) orelse null,
    };
}

pub fn install(self: *FocusGroupWidget) void {
    dvui.parentSet(self.widget());
    self.data().register();

    // only register ourselves if there is no focus group already registered
    const cw = dvui.currentWindow();
    if (cw.subwindows.get(dvui.subwindowCurrentId())) |sw| {
        if (sw.focus_group == null) {

            // put ourselves in the tab index so the whole focus group can be focused by tab
            dvui.tabIndexSet(self.data().id, self.data().options.tab_index);

            if (self.data().id == dvui.focusedWidgetId()) {
                // if we got focused, focus our remembered focus or first id
                if (self.remember_focus) |id| {
                    dvui.focusWidget(id, null, null);
                } else {
                    dvui.tabIndexNextEx(null, self.tab_index_prev);
                }
            }

            sw.focus_group = self;
            //std.debug.print("subwindow {x} focus group {x}\n", .{ sw.id.asU64(), self.data().id.asU64() });
        }
    }
}

pub fn widget(self: *FocusGroupWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *FocusGroupWidget) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *FocusGroupWidget, id: dvui.Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    const ret = self.data().parent.rectFor(id, min_size, e, g);
    if (self.child_rect_union) |u| {
        self.child_rect_union = u.unionWith(ret);
    } else {
        self.child_rect_union = ret;
    }
    return ret;
}

pub fn screenRectScale(self: *FocusGroupWidget, rect: Rect) RectScale {
    return self.data().parent.screenRectScale(rect);
}

pub fn minSizeForChild(self: *FocusGroupWidget, s: Size) void {
    self.data().parent.minSizeForChild(s);
}

pub fn deinit(self: *FocusGroupWidget) void {
    const should_free = self.data().was_allocated_on_widget_stack;
    defer if (should_free) dvui.widgetFree(self);
    defer self.* = undefined;

    const cw = dvui.currentWindow();

    // only deregister ourselves if we were the one registered
    // also do unhandled arrow events
    if (cw.subwindows.get(dvui.subwindowCurrentId())) |sw| {
        if (sw.focus_group == self) {
            sw.focus_group = null;
            //std.debug.print("subwindow {x} focus group null\n", .{sw.id.asU64()});

            const focus_id = dvui.lastFocusedIdInFrameSince(self.last_focus);
            if (focus_id) |fid| dvui.dataSet(null, self.data().id, "_remember_focus", fid);
            const evts = dvui.events();
            for (evts) |*e| {
                if (!dvui.eventMatch(e, .{ .id = self.data().id, .focus_id = focus_id, .r = self.data().borderRectScale().r }))
                    continue;

                switch (e.evt) {
                    .key => |ke| {
                        if ((ke.action == .down or ke.action == .repeat) and (ke.code == .up or ke.code == .left)) {
                            e.handle(@src(), self.data());
                            dvui.tabIndexPrevEx(e.num, self.tab_index_prev);
                            if (dvui.focusedWidgetId() == null) {
                                // wrap around
                                dvui.tabIndexPrevEx(e.num, self.tab_index_prev);
                            }
                        } else if ((ke.action == .down or ke.action == .repeat) and (ke.code == .down or ke.code == .right)) {
                            e.handle(@src(), self.data());
                            dvui.tabIndexNextEx(e.num, self.tab_index_prev);
                            if (dvui.focusedWidgetId() == null) {
                                // wrap around
                                dvui.tabIndexNextEx(e.num, self.tab_index_prev);
                            }
                        }
                    },
                    else => {},
                }
            }
        }
    }

    dvui.dataSetSlice(null, self.data().id, "_tab_prev", self.tab_index.items);
    self.tab_index.deinit(cw.arena());

    if (self.child_rect_union) |u| {
        dvui.dataSet(null, self.data().id, "_rect", u);
    }
    dvui.parentReset(self.data().id, self.data().parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
