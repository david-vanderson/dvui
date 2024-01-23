const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Rect = dvui.Rect;
const ScrollInfo = dvui.ScrollInfo;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const enums = dvui.enums;

const ScrollBarWidget = @This();

pub var defaults: Options = .{
    .name = "ScrollBar",
    .min_size_content = .{ .w = 10, .h = 10 },
};

pub const InitOptions = struct {
    scroll_info: *ScrollInfo,
    direction: enums.Direction = .vertical,
    focus_id: ?u32 = null,
    overlay: bool = false,
};

wd: WidgetData = undefined,
grabRect: Rect = Rect{},
si: *ScrollInfo = undefined,
focus_id: ?u32 = null,
dir: enums.Direction = undefined,
overlay: bool = false,
highlight: bool = false,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) ScrollBarWidget {
    var self = ScrollBarWidget{};
    self.si = init_opts.scroll_info;
    self.focus_id = init_opts.focus_id;
    self.dir = init_opts.direction;
    self.overlay = init_opts.overlay;

    var options = defaults.override(opts);
    if (self.overlay) {
        // we don't want to take any space from parent
        options.min_size_content = .{ .w = 5, .h = 5 };
        options.rect = dvui.placeIn(dvui.parentGet().data().contentRect().justSize(), options.min_sizeGet(), opts.expandGet(), opts.gravityGet());
    }
    self.wd = WidgetData.init(src, .{}, options);

    return self;
}

pub fn install(self: *ScrollBarWidget) !void {
    try self.wd.register();
    try self.wd.borderAndBackground(.{});

    self.grabRect = self.wd.contentRect();
    switch (self.dir) {
        .vertical => {
            self.grabRect.h = @min(self.grabRect.h, @max(20.0, self.grabRect.h * self.si.fraction_visible(self.dir)));
            const insideH = self.wd.contentRect().h - self.grabRect.h;
            self.grabRect.y += insideH * self.si.scroll_fraction(self.dir);
        },
        .horizontal => {
            self.grabRect.w = @min(self.grabRect.w, @max(20.0, self.grabRect.w * self.si.fraction_visible(self.dir)));
            const insideH = self.wd.contentRect().w - self.grabRect.w;
            self.grabRect.x += insideH * self.si.scroll_fraction(self.dir);
        },
    }

    const grabrs = self.wd.parent.screenRectScale(self.grabRect);
    self.processEvents(grabrs.r);
}

pub fn data(self: *ScrollBarWidget) *WidgetData {
    return &self.wd;
}

pub fn processEvents(self: *ScrollBarWidget, grabrs: Rect) void {
    const rs = self.wd.borderRectScale();
    var evts = dvui.events();
    for (evts) |*e| {
        if (!dvui.eventMatch(e, .{ .id = self.data().id, .r = rs.r }))
            continue;

        switch (e.evt) {
            .mouse => |me| {
                switch (me.action) {
                    .focus => {
                        if (self.focus_id) |fid| {
                            e.handled = true;
                            dvui.focusWidget(fid, null, e.num);
                        }
                    },
                    .press => {
                        if (me.button.pointer()) {
                            e.handled = true;
                            if (grabrs.contains(me.p)) {
                                // capture and start drag
                                _ = dvui.captureMouse(self.data().id);
                                switch (self.dir) {
                                    .vertical => dvui.dragPreStart(me.p, .arrow, .{ .y = me.p.y - (grabrs.y + grabrs.h / 2) }),
                                    .horizontal => dvui.dragPreStart(me.p, .arrow, .{ .x = me.p.x - (grabrs.x + grabrs.w / 2) }),
                                }
                            } else {
                                var fi = self.si.fraction_visible(self.dir);
                                // the last page is scroll fraction 1.0, so there is
                                // one less scroll position between 0 and 1.0
                                fi = 1.0 / ((1.0 / fi) - 1);
                                var f: f32 = undefined;
                                if (if (self.dir == .vertical) (me.p.y < grabrs.y) else (me.p.x < grabrs.x)) {
                                    // clicked above grab
                                    f = self.si.scroll_fraction(self.dir) - fi;
                                } else {
                                    // clicked below grab
                                    f = self.si.scroll_fraction(self.dir) + fi;
                                }
                                self.si.scrollToFraction(self.dir, f);
                                dvui.refresh(null, @src(), self.wd.id);
                            }
                        }
                    },
                    .release => {
                        if (me.button.pointer()) {
                            e.handled = true;
                            // stop possible drag and capture
                            dvui.captureMouse(null);
                        }
                    },
                    .motion => {
                        if (dvui.captured(self.data().id)) {
                            e.handled = true;
                            // move if dragging
                            if (dvui.dragging(me.p)) |dps| {
                                _ = dps;
                                const min = switch (self.dir) {
                                    .vertical => rs.r.y + grabrs.h / 2,
                                    .horizontal => rs.r.x + grabrs.w / 2,
                                };
                                const max = switch (self.dir) {
                                    .vertical => rs.r.y + rs.r.h - grabrs.h / 2,
                                    .horizontal => rs.r.x + rs.r.w - grabrs.w / 2,
                                };
                                const grabmid = switch (self.dir) {
                                    .vertical => me.p.y - dvui.dragOffset().y,
                                    .horizontal => me.p.x - dvui.dragOffset().x,
                                };
                                var f: f32 = 0;
                                if (max > min) {
                                    f = (grabmid - min) / (max - min);
                                }
                                self.si.scrollToFraction(self.dir, f);
                                dvui.refresh(null, @src(), self.wd.id);
                            }
                        }
                    },
                    .position => {
                        e.handled = true;
                        self.highlight = true;
                    },
                    .wheel_y => {
                        e.handled = true;
                        switch (self.dir) {
                            .vertical => {
                                self.si.viewport.y -= me.data.wheel_y;
                                self.si.viewport.y = dvui.math.clamp(self.si.viewport.y, 0, self.si.scroll_max(.vertical));
                            },
                            .horizontal => {
                                self.si.viewport.x -= me.data.wheel_y;
                                self.si.viewport.x = dvui.math.clamp(self.si.viewport.x, 0, self.si.scroll_max(.horizontal));
                            },
                        }
                        dvui.refresh(null, @src(), self.wd.id);
                    },
                }
            },
            else => {},
        }

        if (e.bubbleable()) {
            self.wd.parent.processEvent(e, true);
        }
    }
}

pub fn deinit(self: *ScrollBarWidget) void {
    var fill = self.wd.options.color(.text).multiply_alpha(0.5);
    if (dvui.captured(self.wd.id) or self.highlight) {
        fill = self.wd.options.color(.text).multiply_alpha(0.3);
    }
    self.grabRect = self.grabRect.insetAll(2);
    const grabrs = self.wd.parent.screenRectScale(self.grabRect);
    dvui.pathAddRect(grabrs.r, Rect.all(100)) catch {};
    dvui.pathFillConvex(fill) catch {};

    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
}
