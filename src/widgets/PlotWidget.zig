pub const PlotWidget = @This();

/// SAFETY: Set in `install`
box: BoxWidget = undefined,
/// SAFETY: Set in `install`
data_rs: RectScale = undefined,
/// SAFETY: Set in `install`
old_clip: Rect.Physical = undefined,
init_options: InitOptions,
/// SAFETY: Set in `install`, might point to `x_axis_store`
x_axis: *Axis = undefined,
x_axis_store: Axis = .{},
/// SAFETY: Set in `install`, might point to `y_axis_store`
y_axis: *Axis = undefined,
y_axis_store: Axis = .{},
mouse_point: ?Point.Physical = null,
hover_data: ?Data = null,
data_min: Data = .{ .x = std.math.floatMax(f64), .y = std.math.floatMax(f64) },
data_max: Data = .{ .x = -std.math.floatMax(f64), .y = -std.math.floatMax(f64) },

pub var defaults: Options = .{
    .name = "Plot",
    .padding = Rect.all(6),
    .background = true,
    .min_size_content = .{ .w = 20, .h = 20 },
    .style = .content,
};

pub const InitOptions = struct {
    title: ?[]const u8 = null,
    x_axis: ?*Axis = null,
    y_axis: ?*Axis = null,
    border_thick: ?f32 = null,
    mouse_hover: bool = false,
    was_allocated_on_widget_stack: bool = false,
};

pub const Axis = struct {
    name: ?[]const u8 = null,
    min: ?f64 = null,
    max: ?f64 = null,

    pub fn fraction(self: *Axis, val: f64) f32 {
        if (self.min == null or self.max == null) return 0;
        return @floatCast((val - self.min.?) / (self.max.? - self.min.?));
    }
};

pub const Data = struct {
    x: f64,
    y: f64,
};

pub const Line = struct {
    plot: *PlotWidget,
    path: dvui.Path.Builder,

    pub fn point(self: *Line, x: f64, y: f64) void {
        const data_point: Data = .{ .x = x, .y = y };
        self.plot.dataForRange(data_point);
        const screen_p = self.plot.dataToScreen(data_point);
        if (self.plot.mouse_point) |mp| {
            const dp = Point.Physical.diff(mp, screen_p);
            const dps = dp.toNatural();
            if (@abs(dps.x) <= 3 and @abs(dps.y) <= 3) {
                self.plot.hover_data = data_point;
            }
        }
        self.path.addPoint(screen_p);
    }

    pub fn stroke(self: *Line, thick: f32, color: dvui.Color) void {
        self.path.build().stroke(.{ .thickness = thick * self.plot.data_rs.s, .color = color });
    }

    pub fn deinit(self: *Line) void {
        // The Line "widget" intentionally doesn't call `dvui.widgetFree` as it should always be created by `PlotWidget.line`
        defer self.* = undefined;
        self.path.deinit();
    }
};

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) PlotWidget {
    return .{
        .init_options = init_opts,
        .box = BoxWidget.init(src, .{ .dir = .vertical }, defaults.override(opts)),
    };
}

pub fn dataToScreen(self: *PlotWidget, data_point: Data) dvui.Point.Physical {
    const xfrac = self.x_axis.fraction(data_point.x);
    const yfrac = self.y_axis.fraction(data_point.y);
    return .{
        .x = self.data_rs.r.x + xfrac * self.data_rs.r.w,
        .y = self.data_rs.r.y + (1.0 - yfrac) * self.data_rs.r.h,
    };
}

pub fn dataForRange(self: *PlotWidget, data_point: Data) void {
    self.data_min.x = @min(self.data_min.x, data_point.x);
    self.data_max.x = @max(self.data_max.x, data_point.x);
    self.data_min.y = @min(self.data_min.y, data_point.y);
    self.data_max.y = @max(self.data_max.y, data_point.y);
}

pub fn install(self: *PlotWidget) void {
    if (self.init_options.x_axis) |xa| {
        self.x_axis = xa;
    } else {
        if (dvui.dataGet(null, self.box.data().id, "_x_axis", Axis)) |xaxis| {
            self.x_axis_store = xaxis;
        }
        self.x_axis = &self.x_axis_store;
    }

    if (self.init_options.y_axis) |ya| {
        self.y_axis = ya;
    } else {
        if (dvui.dataGet(null, self.box.data().id, "_y_axis", Axis)) |yaxis| {
            self.y_axis_store = yaxis;
        }
        self.y_axis = &self.y_axis_store;
    }

    self.box.install();
    self.box.drawBackground();

    if (self.init_options.title) |title| {
        dvui.label(@src(), "{s}", .{title}, .{ .gravity_x = 0.5, .font_style = .title_4 });
    }

    //const str = "000";
    const tick_font = (dvui.Options{ .font_style = .caption }).fontGet();
    //const tick_size = tick_font.sizeM(str.len, 1);

    const yticks = [_]?f64{ self.y_axis.min, self.y_axis.max };
    var tick_width: f32 = 0;
    if (self.y_axis.name) |_| {
        for (yticks) |m_ytick| {
            if (m_ytick) |ytick| {
                const tick_str = std.fmt.allocPrint(dvui.currentWindow().lifo(), "{d}", .{ytick}) catch "";
                defer dvui.currentWindow().lifo().free(tick_str);
                tick_width = @max(tick_width, tick_font.textSize(tick_str).w);
            }
        }
    }

    var hbox1 = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both });

    // y axis
    var yaxis = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .vertical, .min_size_content = .{ .w = tick_width } });
    var yaxis_rect = yaxis.data().rect;
    if (self.y_axis.name) |yname| {
        if (yname.len > 0) {
            dvui.label(@src(), "{s}", .{yname}, .{ .gravity_y = 0.5 });
        }
    }
    yaxis.deinit();

    // right padding (if adding, need to add a spacer to the right of xaxis as well)
    //var xaxis_padding = dvui.box(@src(), .horizontal, .{ .gravity_x = 1.0, .expand = .vertical, .min_size_content = .{ .w = tick_size.w / 2 } });
    //xaxis_padding.deinit();

    // data area
    var data_box = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both });

    // mouse hover
    if (self.init_options.mouse_hover) {
        const evts = dvui.events();
        for (evts) |*e| {
            if (!dvui.eventMatchSimple(e, data_box.data()))
                continue;

            switch (e.evt) {
                .mouse => |me| {
                    if (me.action == .position) {
                        dvui.cursorSet(.arrow);
                        self.mouse_point = me.p;
                    }
                },
                else => {},
            }
        }
    }

    yaxis_rect.h = data_box.data().rect.h;
    self.data_rs = data_box.data().contentRectScale();
    data_box.deinit();

    const bt: f32 = self.init_options.border_thick orelse 0.0;
    if (bt > 0) {
        self.data_rs.r.stroke(.{}, .{ .thickness = bt * self.data_rs.s, .color = self.box.data().options.color(.text) });
    }

    const pad = 2 * self.data_rs.s;

    hbox1.deinit();

    var hbox2 = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });

    // bottom left corner under y axis
    _ = dvui.spacer(@src(), .{ .min_size_content = .width(yaxis_rect.w), .expand = .vertical });

    var x_tick_height: f32 = 0;
    if (self.x_axis.name) |_| {
        if (self.x_axis.min != null or self.x_axis.max != null) {
            x_tick_height = tick_font.sizeM(1, 1).h;
        }
    }

    // x axis
    var xaxis = dvui.box(@src(), .{}, .{ .gravity_y = 1.0, .expand = .horizontal, .min_size_content = .{ .h = x_tick_height } });
    if (self.x_axis.name) |xname| {
        if (xname.len > 0) {
            dvui.label(@src(), "{s}", .{xname}, .{ .gravity_x = 0.5, .gravity_y = 0.5 });
        }
    }
    xaxis.deinit();

    hbox2.deinit();

    // y axis ticks
    if (self.y_axis.name) |_| {
        for (yticks) |m_ytick| {
            if (m_ytick) |ytick| {
                const tick: Data = .{ .x = self.x_axis.min orelse 0, .y = ytick };
                const tick_str = std.fmt.allocPrint(dvui.currentWindow().lifo(), "{d}", .{ytick}) catch "";
                defer dvui.currentWindow().lifo().free(tick_str);
                const tick_str_size = tick_font.textSize(tick_str).scale(self.data_rs.s, Size.Physical);
                var tick_p = self.dataToScreen(tick);
                tick_p.x -= tick_str_size.w + pad;
                tick_p.y = @max(tick_p.y, self.data_rs.r.y);
                tick_p.y = @min(tick_p.y, self.data_rs.r.y + self.data_rs.r.h - tick_str_size.h);
                //tick_p.y -= tick_str_size.h / 2;
                const tick_rs: RectScale = .{ .r = Rect.Physical.fromPoint(tick_p).toSize(tick_str_size), .s = self.data_rs.s };

                dvui.renderText(.{ .font = tick_font, .text = tick_str, .rs = tick_rs, .color = self.box.data().options.color(.text) }) catch |err| {
                    dvui.logError(@src(), err, "y axis tick text for {d}", .{ytick});
                };
            }
        }
    }

    // x axis ticks
    if (self.x_axis.name) |_| {
        const xticks = [_]?f64{ self.x_axis.min, self.x_axis.max };
        for (xticks) |m_xtick| {
            if (m_xtick) |xtick| {
                const tick: Data = .{ .x = xtick, .y = self.y_axis.min orelse 0 };
                const tick_str = std.fmt.allocPrint(dvui.currentWindow().lifo(), "{d}", .{xtick}) catch "";
                defer dvui.currentWindow().lifo().free(tick_str);
                const tick_str_size = tick_font.textSize(tick_str).scale(self.data_rs.s, Size.Physical);
                var tick_p = self.dataToScreen(tick);
                tick_p.x = @max(tick_p.x, self.data_rs.r.x);
                tick_p.x = @min(tick_p.x, self.data_rs.r.x + self.data_rs.r.w - tick_str_size.w);
                //tick_p.x -= tick_str_size.w / 2;
                tick_p.y += pad;
                const tick_rs: RectScale = .{ .r = Rect.Physical.fromPoint(tick_p).toSize(tick_str_size), .s = self.data_rs.s };

                dvui.renderText(.{ .font = tick_font, .text = tick_str, .rs = tick_rs, .color = self.box.data().options.color(.text) }) catch |err| {
                    dvui.logError(@src(), err, "x axis tick text for {d}", .{xtick});
                };
            }
        }
    }

    self.old_clip = dvui.clip(self.data_rs.r);
}

pub fn line(self: *PlotWidget) Line {
    // NOTE: Should not allocate Line as a stack widget. Line doesn't call `dvui.widgetFree`
    return .{
        .plot = self,
        .path = .init(dvui.currentWindow().lifo()),
    };
}

pub fn deinit(self: *PlotWidget) void {
    const should_free = self.init_options.was_allocated_on_widget_stack;
    defer if (should_free) dvui.widgetFree(self);
    defer self.* = undefined;
    dvui.clipSet(self.old_clip);

    // maybe we got no data
    if (self.data_min.x == std.math.floatMax(f64)) {
        self.data_min = .{ .x = 0, .y = 0 };
        self.data_max = .{ .x = 10, .y = 10 };
    }

    if (self.init_options.x_axis) |x_axis| {
        if (x_axis.min == null) {
            x_axis.min = self.data_min.x;
        }
        if (x_axis.max == null) {
            x_axis.max = self.data_max.x;
        }
    } else {
        self.x_axis.min = self.data_min.x;
        self.x_axis.max = self.data_max.x;
        dvui.dataSet(null, self.box.data().id, "_x_axis", self.x_axis.*);
    }
    if (self.init_options.y_axis) |y_axis| {
        if (y_axis.min == null) {
            y_axis.min = self.data_min.y;
        }
        if (y_axis.max == null) {
            y_axis.max = self.data_max.y;
        }
    } else {
        self.y_axis.min = self.data_min.y;
        self.y_axis.max = self.data_max.y;
        dvui.dataSet(null, self.box.data().id, "_y_axis", self.y_axis.*);
    }

    if (self.hover_data) |hd| {
        var p = self.box.data().contentRectScale().pointFromPhysical(self.mouse_point.?);
        const str = std.fmt.allocPrint(dvui.currentWindow().lifo(), "{d}, {d}", .{ hd.x, hd.y }) catch "";
        // NOTE: Always calling free is safe because fallback is a 0 len slice, which is ignored
        defer dvui.currentWindow().lifo().free(str);
        const size: Size = (dvui.Options{}).fontGet().textSize(str);
        p.x -= size.w / 2;
        const padding = dvui.LabelWidget.defaults.paddingGet();
        p.y -= size.h + padding.y + padding.h + 8;
        dvui.label(@src(), "{d}, {d}", .{ hd.x, hd.y }, .{ .rect = Rect.fromPoint(p), .background = true, .border = Rect.all(1), .margin = .{} });
    }

    self.box.deinit();
}

pub const Helpers = struct {
    pub fn plot(src: std.builtin.SourceLocation, plot_opts: PlotWidget.InitOptions, opts: Options) *PlotWidget {
        var ret = dvui.widgetAlloc(PlotWidget);
        ret.* = PlotWidget.init(src, plot_opts, opts);
        ret.init_options.was_allocated_on_widget_stack = true;
        ret.install();
        return ret;
    }

    pub const PlotXYOptions = struct {
        plot_opts: InitOptions = .{},

        // Logical pixels
        thick: f32 = 1.0,

        // If null, uses Theme.highlight.fill
        color: ?dvui.Color = null,

        xs: []const f64,
        ys: []const f64,
    };

    pub fn plotXY(src: std.builtin.SourceLocation, init_opts: PlotXYOptions, opts: Options) void {
        const xy_defaults: Options = .{ .padding = .{} };
        var p = dvui.plot(src, init_opts.plot_opts, xy_defaults.override(opts));

        var s1 = p.line();
        for (init_opts.xs, init_opts.ys) |x, y| {
            s1.point(x, y);
        }

        s1.stroke(init_opts.thick, init_opts.color orelse dvui.themeGet().color(.highlight, .fill));

        s1.deinit();
        p.deinit();
    }
};

const Options = dvui.Options;
const Point = dvui.Point;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;

const BoxWidget = dvui.BoxWidget;

const std = @import("std");
const dvui = @import("../dvui.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
