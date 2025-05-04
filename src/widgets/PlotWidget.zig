pub const PlotWidget = @This();

box: BoxWidget = undefined,
data_rs: RectScale = undefined,
old_clip: Rect.Physical = undefined,
init_options: InitOptions = undefined,
x_axis: *Axis = undefined,
x_axis_store: Axis = .{},
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
};

pub const InitOptions = struct {
    title: ?[]const u8 = null,
    x_axis: ?*Axis = null,
    y_axis: ?*Axis = null,
    border_thick: ?f32 = null,
    mouse_hover: bool = false,
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
    path: dvui.PathArrayList,

    pub fn point(self: *Line, x: f64, y: f64) !void {
        const data: Data = .{ .x = x, .y = y };
        self.plot.dataForRange(data);
        const screen_p = self.plot.dataToScreen(data);
        if (self.plot.mouse_point) |mp| {
            const dp = Point.Physical.diff(mp, screen_p);
            const dps = dp.toNatural();
            if (@abs(dps.x) <= 3 and @abs(dps.y) <= 3) {
                self.plot.hover_data = data;
            }
        }
        try self.path.append(screen_p);
    }

    pub fn stroke(self: *Line, thick: f32, color: dvui.Color) !void {
        try dvui.pathStroke(self.path.items, thick * self.plot.data_rs.s, color, .{});
    }

    pub fn deinit(self: *Line) void {
        self.path.deinit();
    }
};

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) PlotWidget {
    var self = PlotWidget{};
    self.init_options = init_opts;
    self.box = BoxWidget.init(src, .vertical, false, defaults.override(opts));

    return self;
}

pub fn dataToScreen(self: *PlotWidget, data: Data) dvui.Point.Physical {
    const xfrac = self.x_axis.fraction(data.x);
    const yfrac = self.y_axis.fraction(data.y);
    return .{
        .x = self.data_rs.r.x + xfrac * self.data_rs.r.w,
        .y = self.data_rs.r.y + (1.0 - yfrac) * self.data_rs.r.h,
    };
}

pub fn dataForRange(self: *PlotWidget, data: Data) void {
    self.data_min.x = @min(self.data_min.x, data.x);
    self.data_max.x = @max(self.data_max.x, data.x);
    self.data_min.y = @min(self.data_min.y, data.y);
    self.data_max.y = @max(self.data_max.y, data.y);
}

pub fn install(self: *PlotWidget) !void {
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

    try self.box.install();
    try self.box.drawBackground();

    if (self.init_options.title) |title| {
        try dvui.label(@src(), "{s}", .{title}, .{ .gravity_x = 0.5, .font_style = .title_4 });
    }

    //const str = "000";
    const tick_font = (dvui.Options{ .font_style = .caption }).fontGet();
    //const tick_size = tick_font.sizeM(str.len, 1);

    const yticks = [_]?f64{ self.y_axis.min, self.y_axis.max };
    var tick_width: f32 = 0;
    if (self.y_axis.name) |_| {
        for (yticks) |m_ytick| {
            if (m_ytick) |ytick| {
                const tick_str = try std.fmt.allocPrint(dvui.currentWindow().arena(), "{d}", .{ytick});
                tick_width = @max(tick_width, tick_font.textSize(tick_str).w);
            }
        }
    }

    var hbox1 = try dvui.box(@src(), .horizontal, .{ .expand = .both });

    // y axis
    var yaxis = try dvui.box(@src(), .horizontal, .{ .expand = .vertical, .min_size_content = .{ .w = tick_width } });
    var yaxis_rect = yaxis.data().rect;
    if (self.y_axis.name) |yname| {
        if (yname.len > 0) {
            try dvui.label(@src(), "{s}", .{yname}, .{ .gravity_y = 0.5 });
        }
    }
    yaxis.deinit();

    // right padding (if adding, need to add a spacer to the right of xaxis as well)
    //var xaxis_padding = try dvui.box(@src(), .horizontal, .{ .gravity_x = 1.0, .expand = .vertical, .min_size_content = .{ .w = tick_size.w / 2 } });
    //xaxis_padding.deinit();

    // data area
    var data_box = try dvui.box(@src(), .horizontal, .{ .expand = .both });

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
        try self.data_rs.r.stroke(.{}, bt * self.data_rs.s, self.box.data().options.color(.text), .{});
    }

    const pad = 2 * self.data_rs.s;

    hbox1.deinit();

    var hbox2 = try dvui.box(@src(), .horizontal, .{ .expand = .horizontal });

    // bottom left corner under y axis
    _ = try dvui.spacer(@src(), .{ .w = yaxis_rect.w }, .{ .expand = .vertical });

    var x_tick_height: f32 = 0;
    if (self.x_axis.name) |_| {
        if (self.x_axis.min != null or self.x_axis.max != null) {
            x_tick_height = tick_font.sizeM(1, 1).h;
        }
    }

    // x axis
    var xaxis = try dvui.box(@src(), .vertical, .{ .gravity_y = 1.0, .expand = .horizontal, .min_size_content = .{ .h = x_tick_height } });
    if (self.x_axis.name) |xname| {
        if (xname.len > 0) {
            try dvui.label(@src(), "{s}", .{xname}, .{ .gravity_x = 0.5, .gravity_y = 0.5 });
        }
    }
    xaxis.deinit();

    hbox2.deinit();

    // y axis ticks
    if (self.y_axis.name) |_| {
        for (yticks) |m_ytick| {
            if (m_ytick) |ytick| {
                const tick: Data = .{ .x = self.x_axis.min orelse 0, .y = ytick };
                const tick_str = try std.fmt.allocPrint(dvui.currentWindow().arena(), "{d}", .{ytick});
                const tick_str_size = tick_font.textSize(tick_str).scale(self.data_rs.s, Size.Physical);
                var tick_p = self.dataToScreen(tick);
                tick_p.x -= tick_str_size.w + pad;
                tick_p.y = @max(tick_p.y, self.data_rs.r.y);
                tick_p.y = @min(tick_p.y, self.data_rs.r.y + self.data_rs.r.h - tick_str_size.h);
                //tick_p.y -= tick_str_size.h / 2;
                const tick_rs: RectScale = .{ .r = Rect.Physical.fromPoint(tick_p).toSize(tick_str_size), .s = self.data_rs.s };

                try dvui.renderText(.{ .font = tick_font, .text = tick_str, .rs = tick_rs, .color = self.box.data().options.color(.text) });
            }
        }
    }

    // x axis ticks
    if (self.x_axis.name) |_| {
        const xticks = [_]?f64{ self.x_axis.min, self.x_axis.max };
        for (xticks) |m_xtick| {
            if (m_xtick) |xtick| {
                const tick: Data = .{ .x = xtick, .y = self.y_axis.min orelse 0 };
                const tick_str = try std.fmt.allocPrint(dvui.currentWindow().arena(), "{d}", .{xtick});
                const tick_str_size = tick_font.textSize(tick_str).scale(self.data_rs.s, Size.Physical);
                var tick_p = self.dataToScreen(tick);
                tick_p.x = @max(tick_p.x, self.data_rs.r.x);
                tick_p.x = @min(tick_p.x, self.data_rs.r.x + self.data_rs.r.w - tick_str_size.w);
                //tick_p.x -= tick_str_size.w / 2;
                tick_p.y += pad;
                const tick_rs: RectScale = .{ .r = Rect.Physical.fromPoint(tick_p).toSize(tick_str_size), .s = self.data_rs.s };

                try dvui.renderText(.{ .font = tick_font, .text = tick_str, .rs = tick_rs, .color = self.box.data().options.color(.text) });
            }
        }
    }

    self.old_clip = dvui.clip(self.data_rs.r);
}

pub fn line(self: *PlotWidget) Line {
    return .{
        .plot = self,
        .path = .init(dvui.currentWindow().arena()),
    };
}

pub fn deinit(self: *PlotWidget) void {
    dvui.clipSet(self.old_clip);

    // maybe we got no data
    if (self.data_min.x == std.math.floatMax(f64)) {
        self.data_min = .{ .x = 0, .y = 0 };
        self.data_max = .{ .x = 10, .y = 10 };
    }

    if (self.init_options.x_axis == null or self.init_options.x_axis.?.min == null) {
        self.x_axis.min = self.data_min.x;
    }
    if (self.init_options.x_axis == null or self.init_options.x_axis.?.max == null) {
        self.x_axis.max = self.data_max.x;
    }
    if (self.init_options.y_axis == null or self.init_options.y_axis.?.min == null) {
        self.y_axis.min = self.data_min.y;
    }
    if (self.init_options.y_axis == null or self.init_options.y_axis.?.max == null) {
        self.y_axis.max = self.data_max.y;
    }
    dvui.dataSet(null, self.box.data().id, "_x_axis", self.x_axis.*);
    dvui.dataSet(null, self.box.data().id, "_y_axis", self.y_axis.*);

    if (self.hover_data) |hd| {
        var p = self.box.data().contentRectScale().pointFromScreen(self.mouse_point.?);
        const str = std.fmt.allocPrint(dvui.currentWindow().arena(), "{d}, {d}", .{ hd.x, hd.y }) catch "";
        const size: Size = (dvui.Options{}).fontGet().textSize(str);
        p.x -= size.w / 2;
        const padding = dvui.LabelWidget.defaults.paddingGet();
        p.y -= size.h + padding.y + padding.h + 8;
        dvui.label(@src(), "{d}, {d}", .{ hd.x, hd.y }, .{ .rect = Rect.fromPoint(p), .background = true, .border = Rect.all(1), .margin = .{} }) catch {};
    }

    self.box.deinit();
}

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
