const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Point = dvui.Point;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const enums = dvui.enums;

const PanedWidget = @This();

pub const InitOptions = struct {
    direction: enums.Direction,
    collapsed_size: f32,
};

const handle_size = 4;

wd: WidgetData = undefined,

split_ratio: f32 = undefined,
dir: enums.Direction = undefined,
collapsed_size: f32 = 0,
hovered: bool = false,
prevClip: Rect = Rect{},
collapsed_state: bool = false,
collapsing: bool = false,
first_side: bool = true,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) PanedWidget {
    var self = PanedWidget{};
    const defaults = Options{ .name = "Paned" };
    self.wd = WidgetData.init(src, .{}, defaults.override(opts));
    self.dir = init_opts.direction;
    self.collapsed_size = init_opts.collapsed_size;

    const rect = self.wd.contentRect();
    const our_size = switch (self.dir) {
        .horizontal => rect.w,
        .vertical => rect.h,
    };

    self.collapsing = dvui.dataGet(null, self.wd.id, "_collapsing", bool) orelse false;

    self.collapsed_state = dvui.dataGet(null, self.wd.id, "_collapsed", bool) orelse (our_size < self.collapsed_size);
    if (self.collapsing) {
        self.collapsed_state = false;
    }

    if (dvui.dataGet(null, self.wd.id, "_split_ratio", f32)) |r| {
        self.split_ratio = r;
        if (!self.collapsing and !self.collapsed_state and our_size < self.collapsed_size) {
            // collapsing
            self.collapsing = true;
            if (self.split_ratio >= 0.5) {
                self.animateSplit(1.0);
            } else {
                self.animateSplit(0.0);
            }
        } else if (!self.collapsing and self.collapsed_state and our_size >= self.collapsed_size) {
            // expanding
            self.collapsed_state = false;
            if (self.split_ratio > 0.5) {
                self.animateSplit(0.5);
            } else {
                // we were on the second widget, this will
                // "remember" we were on it
                self.animateSplit(0.4999);
            }
        }
    } else {
        // first frame
        if (our_size < self.collapsed_size) {
            self.split_ratio = 1.0;
        } else {
            self.split_ratio = 0.5;
        }
    }

    if (dvui.animationGet(self.wd.id, "_split_ratio")) |a| {
        self.split_ratio = a.lerp();

        if (self.collapsing and a.done()) {
            self.collapsing = false;
            self.collapsed_state = our_size < self.collapsed_size;
        }
    }

    return self;
}

pub fn install(self: *PanedWidget) !void {
    try self.wd.register();

    try self.wd.borderAndBackground(.{});
    self.prevClip = dvui.clip(self.wd.contentRectScale().r);

    dvui.parentSet(self.widget());
}

pub fn matchEvent(self: *PanedWidget, e: *Event) bool {
    return dvui.eventMatchSimple(e, self.data());
}

pub fn processEvents(self: *PanedWidget) void {
    const evts = dvui.events();
    for (evts) |*e| {
        if (!self.matchEvent(e))
            continue;

        self.processEvent(e, false);
    }
}

pub fn draw(self: *PanedWidget) !void {
    if (!self.collapsed()) {
        if (self.hovered) {
            const rs = self.wd.contentRectScale();
            var r = rs.r;
            const thick = handle_size * rs.s;
            switch (self.dir) {
                .horizontal => {
                    r.x += r.w * self.split_ratio - thick / 2;
                    r.w = thick;
                    const height = r.h / 5;
                    r.y += r.h / 2 - height / 2;
                    r.h = height;
                },
                .vertical => {
                    r.y += r.h * self.split_ratio - thick / 2;
                    r.h = thick;
                    const width = r.w / 5;
                    r.x += r.w / 2 - width / 2;
                    r.w = width;
                },
            }
            try r.fill(Rect.all(thick), self.wd.options.color(.text).transparent(0.5));
        }
    }
}

pub fn collapsed(self: *PanedWidget) bool {
    return self.collapsed_state;
}

pub fn animateSplit(self: *PanedWidget, end_val: f32) void {
    dvui.animation(self.wd.id, "_split_ratio", dvui.Animation{ .start_val = self.split_ratio, .end_val = end_val, .end_time = 250_000 });
}

pub fn widget(self: *PanedWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *PanedWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *PanedWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) dvui.Rect {
    _ = id;
    var r = self.wd.contentRect().justSize();
    if (self.first_side) {
        self.first_side = false;
        if (self.collapsed()) {
            if (self.split_ratio == 0.0) {
                r.w = 0;
                r.h = 0;
            } else {
                switch (self.dir) {
                    .horizontal => r.x -= (r.w - (r.w * self.split_ratio)),
                    .vertical => r.y -= (r.h - (r.h * self.split_ratio)),
                }
            }
        } else {
            switch (self.dir) {
                .horizontal => r.w = r.w * self.split_ratio - handle_size / 2,
                .vertical => r.h = r.h * self.split_ratio - handle_size / 2,
            }
        }
        return dvui.placeIn(r, min_size, e, g);
    } else {
        if (self.collapsed()) {
            if (self.split_ratio == 1.0) {
                r.w = 0;
                r.h = 0;
            } else {
                switch (self.dir) {
                    .horizontal => {
                        r.x = r.w * self.split_ratio;
                    },
                    .vertical => {
                        r.y = r.h * self.split_ratio;
                    },
                }
            }
        } else {
            switch (self.dir) {
                .horizontal => {
                    const first = r.w * self.split_ratio - handle_size / 2;
                    r.w -= first + handle_size;
                    r.x += first + handle_size;
                },
                .vertical => {
                    const first = r.h * self.split_ratio - handle_size / 2;
                    r.h -= first + handle_size;
                    r.y += first + handle_size;
                },
            }
        }
        return dvui.placeIn(r, min_size, e, g);
    }
}

pub fn screenRectScale(self: *PanedWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *PanedWidget, s: dvui.Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
}

pub fn processEvent(self: *PanedWidget, e: *Event, bubbling: bool) void {
    _ = bubbling;
    if (e.evt == .mouse) {
        const rs = self.wd.contentRectScale();
        var target: f32 = undefined;
        var mouse: f32 = undefined;
        var cursor: enums.Cursor = undefined;
        switch (self.dir) {
            .horizontal => {
                target = rs.r.x + rs.r.w * self.split_ratio;
                mouse = e.evt.mouse.p.x;
                cursor = .arrow_w_e;
            },
            .vertical => {
                target = rs.r.y + rs.r.h * self.split_ratio;
                mouse = e.evt.mouse.p.y;
                cursor = .arrow_n_s;
            },
        }

        if (dvui.captured(self.wd.id) or @abs(mouse - target) < (5 * rs.s)) {
            self.hovered = true;
            if (e.evt.mouse.action == .press and e.evt.mouse.button.pointer()) {
                e.handled = true;
                // capture and start drag
                dvui.captureMouse(self.wd.id);
                dvui.dragPreStart(e.evt.mouse.p, .{ .cursor = cursor });
            } else if (e.evt.mouse.action == .release and e.evt.mouse.button.pointer()) {
                e.handled = true;
                // stop possible drag and capture
                dvui.captureMouse(null);
                dvui.dragEnd();
            } else if (e.evt.mouse.action == .motion and dvui.captured(self.wd.id)) {
                e.handled = true;
                // move if dragging
                if (dvui.dragging(e.evt.mouse.p)) |dps| {
                    _ = dps;
                    switch (self.dir) {
                        .horizontal => {
                            self.split_ratio = (e.evt.mouse.p.x - rs.r.x) / rs.r.w;
                        },
                        .vertical => {
                            self.split_ratio = (e.evt.mouse.p.y - rs.r.y) / rs.r.h;
                        },
                    }

                    self.split_ratio = @max(0.0, @min(1.0, self.split_ratio));
                }
            } else if (e.evt.mouse.action == .position) {
                dvui.cursorSet(cursor);
            }
        }
    }

    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *PanedWidget) void {
    dvui.clipSet(self.prevClip);
    dvui.dataSet(null, self.wd.id, "_collapsing", self.collapsing);
    dvui.dataSet(null, self.wd.id, "_collapsed", self.collapsed_state);
    dvui.dataSet(null, self.wd.id, "_split_ratio", self.split_ratio);
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    dvui.parentReset(self.wd.id, self.wd.parent);
}
