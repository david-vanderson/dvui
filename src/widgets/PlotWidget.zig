pub const PlotWidget = @This();

src: std.builtin.SourceLocation,
opts: Options,
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
hover_data: ?HoverData = null,
data_min: Data = .{ .x = std.math.floatMax(f64), .y = std.math.floatMax(f64) },
data_max: Data = .{ .x = -std.math.floatMax(f64), .y = -std.math.floatMax(f64) },

pub var defaults: Options = .{
    .name = "Plot",
    .role = .group,
    .label = .{ .text = "Plot" },
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
    spine_color: ?dvui.Color = null,
    mouse_hover: bool = false,
    was_allocated_on_widget_stack: bool = false,
};

pub const Axis = struct {
    name: ?[]const u8 = null,
    min: ?f64 = null,
    max: ?f64 = null,

    scale: union(enum) {
        linear,
        log: struct {
            base: f64 = 10,
        },
    } = .linear,

    ticks: struct {
        locations: union(TickLocatorType) {
            none,
            auto: struct {
                num_ticks: usize,
            },
            custom: []const f64,
        } = .{ .auto = .{ .num_ticks = 3 } },

        lines: enum {
            none,
            one_side,
            mirrored,
        } = .mirrored,

        // if null it uses the default for `scale`
        format: ?TickFormating = null,
    } = .{},

    // only relevant if `ticks` != none
    draw_gridlines: bool = true,

    pub const TickLocatorType = enum {
        none,
        auto,
        custom,
    };

    pub const Ticks = struct {
        locator_type: TickLocatorType,
        values: []const f64,

        fn deinit(self: *Ticks, gpa: std.mem.Allocator) void {
            switch (self.locator_type) {
                .auto => {
                    gpa.free(self.values);
                },
                else => {},
            }
        }
    };

    pub const TickFormating = union(enum) {
        normal: struct {
            precision: usize = 2,
        },
        scientific_notation: struct {
            precision: usize = 4,
        },
        custom: *const fn (gpa: std.mem.Allocator, tick: f64) std.mem.Allocator.Error![]const u8,
    };

    pub fn formatTick(self: *Axis, gpa: std.mem.Allocator, tick: f64) ![]const u8 {
        const tick_format = self.ticks.format orelse
            switch (self.scale) {
                .linear => TickFormating{ .normal = .{} },
                .log => TickFormating{ .scientific_notation = .{} },
            };

        switch (tick_format) {
            .normal => |cfg| {
                return try std.fmt.allocPrint(gpa, "{d:.[1]}", .{ tick, cfg.precision });
            },
            .scientific_notation => |cfg| {
                return try std.fmt.allocPrint(gpa, "{e:.[1]}", .{ tick, cfg.precision });
            },
            .custom => |func| {
                return func(gpa, tick);
            },
        }
    }

    pub fn fraction(self: *Axis, val: f64) f32 {
        if (self.min == null or self.max == null) return 0;

        const min = self.min.?;
        const max = self.max.?;

        switch (self.scale) {
            .linear => {
                return @floatCast((val - min) / (max - min));
            },
            .log => |log_data| {
                const val_exp = std.math.log(f64, log_data.base, val);
                const min_exp = std.math.log(f64, log_data.base, min);
                const max_exp = std.math.log(f64, log_data.base, max);
                return @floatCast((val_exp - min_exp) / (max_exp - min_exp));
            },
        }
    }

    pub fn getTicksLinear(self: *Axis, gpa: std.mem.Allocator, tick_count: usize) ![]f64 {
        if (self.scale != .linear or tick_count == 0 or self.max == null or self.min == null)
            return &.{};

        const min = self.min.?;
        const max = self.max.?;

        var ticks = try gpa.alloc(f64, tick_count);

        switch (tick_count) {
            1 => ticks[0] = (min + max) / 2,
            2 => {
                ticks[0] = min;
                ticks[1] = max;
            },
            else => |n| {
                const span = max - min;
                const step = span / @as(f64, @floatFromInt(n - 1));
                for (0..n) |i| {
                    ticks[i] = min + step * @as(f64, @floatFromInt(i));
                }
            },
        }

        return ticks;
    }

    pub fn getTicksLog(self: *Axis, gpa: std.mem.Allocator, tick_count: usize) ![]f64 {
        if (self.scale != .log or tick_count == 0 or self.max == null or self.min == null)
            return &.{};

        const base = self.scale.log.base;

        const min = self.min.?;
        const max = self.max.?;
        if (min <= 0 or max <= 0) return &.{};

        const min_log = std.math.log(f64, base, min);
        const max_log = std.math.log(f64, base, max);

        var ticks = try gpa.alloc(f64, tick_count);

        switch (tick_count) {
            1 => ticks[0] = std.math.pow(f64, base, (min_log + max_log) / 2),
            2 => {
                ticks[0] = min;
                ticks[1] = max;
            },
            else => |n| {
                const span = max_log - min_log;
                const step = span / @as(f64, @floatFromInt(n - 1));
                for (0..n) |i| {
                    const exp = min_log + step * @as(f64, @floatFromInt(i));
                    ticks[i] = std.math.pow(f64, base, exp);
                }
            },
        }

        return ticks;
    }

    pub fn getTicks(self: *Axis, gpa: std.mem.Allocator) !Ticks {
        switch (self.ticks.locations) {
            .none => return Ticks{
                .locator_type = .none,
                .values = &.{},
            },
            .auto => |auto_ticks| {
                const values = try switch (self.scale) {
                    .linear => self.getTicksLinear(gpa, auto_ticks.num_ticks),
                    .log => self.getTicksLog(gpa, auto_ticks.num_ticks),
                };

                return Ticks{
                    .locator_type = .auto,
                    .values = values,
                };
            },
            .custom => |ticks| return Ticks{
                .locator_type = .custom,
                .values = ticks,
            },
        }
    }
};

pub const HoverData = union(enum) {
    point: Data,
    bar: struct {
        x: f64,
        y: f64,
        w: f64,
        h: f64,
    },
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
                self.plot.hover_data = .{ .point = data_point };
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

/// It's expected to call this when `self` is `undefined`
pub fn init(self: *PlotWidget, src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) void {
    self.* = .{
        .src = src,
        .opts = opts,
        .init_options = init_opts,
    };

    self.box.init(self.src, .{ .dir = .vertical }, defaults.override(self.opts));
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

    self.box.drawBackground();

    if (self.init_options.title) |title| {
        dvui.label(@src(), "{s}", .{title}, .{ .gravity_x = 0.5, .font_style = .title_4 });
    }

    const tick_font = (dvui.Options{ .font_style = .caption }).fontGet();

    var yticks = self.y_axis.getTicks(dvui.currentWindow().lifo()) catch Axis.Ticks{
        .locator_type = .none,
        .values = &.{},
    };
    defer yticks.deinit(dvui.currentWindow().lifo());

    var xticks = self.x_axis.getTicks(dvui.currentWindow().lifo()) catch Axis.Ticks{
        .locator_type = .none,
        .values = &.{},
    };
    defer xticks.deinit(dvui.currentWindow().lifo());

    const y_axis_tick_width: f32 = blk: {
        if (self.y_axis.name == null) break :blk 0;
        var max_width: f32 = 0;

        for (yticks.values) |ytick| {
            const tick_str = self.y_axis.formatTick(dvui.currentWindow().lifo(), ytick) catch "";
            defer dvui.currentWindow().lifo().free(tick_str);
            max_width = @max(max_width, tick_font.textSize(tick_str).w);
        }

        break :blk max_width;
    };

    const x_axis_last_tick_width: f32 = blk: {
        if (xticks.values.len == 0) break :blk 0;
        const str = self.x_axis.formatTick(
            dvui.currentWindow().lifo(),
            xticks.values[xticks.values.len - 1],
        ) catch "";
        defer dvui.currentWindow().lifo().free(str);

        break :blk tick_font.sizeM(@as(f32, @floatFromInt(str.len)), 1).w;
    };

    var hbox1 = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both });

    // y axis label
    var yaxis = dvui.box(@src(), .{ .dir = .horizontal }, .{
        .expand = .vertical,
        .min_size_content = .{ .w = y_axis_tick_width },
        .padding = dvui.Rect{ .w = y_axis_tick_width },
    });
    var yaxis_rect = yaxis.data().rect;
    if (self.y_axis.name) |yname| {
        if (yname.len > 0) {
            dvui.label(@src(), "{s}", .{yname}, .{ .gravity_y = 0.5, .rotation = std.math.pi * 1.5 });
        }
    }
    yaxis.deinit();

    // x axis padding
    if (self.x_axis.name) |_| {
        var xaxis_padding = dvui.box(@src(), .{ .dir = .horizontal }, .{
            .gravity_x = 1.0,
            .expand = .vertical,
            .min_size_content = .{ .w = x_axis_last_tick_width / 2 },
        });
        xaxis_padding.deinit();
    }

    // data area
    var data_box = dvui.box(@src(), .{ .dir = .horizontal }, .{
        .expand = .both,
        .role = .image,
        .label = .{ .text = self.init_options.title orelse "" },
    });

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
    const bc: dvui.Color = self.init_options.spine_color orelse self.box.data().options.color(.text);

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

    // x axis label
    var xaxis = dvui.box(@src(), .{}, .{
        .gravity_y = 1.0,
        .expand = .horizontal,
        .min_size_content = .{ .h = x_tick_height * 3 },
    });
    if (self.x_axis.name) |xname| {
        if (xname.len > 0) {
            dvui.label(@src(), "{s}", .{xname}, .{ .gravity_x = 0.5, .gravity_y = 1.0 });
        }
    }
    xaxis.deinit();

    _ = dvui.spacer(@src(), .{
        .min_size_content = .width(x_axis_last_tick_width / 2),
        .expand = .vertical,
    });

    hbox2.deinit();

    const tick_line_len = 5;

    // y axis ticks
    if (self.y_axis.name) |_| {
        for (yticks.values) |ytick| {
            const tick: Data = .{ .x = self.x_axis.min orelse 0, .y = ytick };
            const tick_str = self.y_axis.formatTick(dvui.currentWindow().lifo(), ytick) catch "";
            defer dvui.currentWindow().lifo().free(tick_str);
            const tick_str_size = tick_font.textSize(tick_str).scale(self.data_rs.s, Size.Physical);

            const tick_p = self.dataToScreen(tick);

            if (self.x_axis.draw_gridlines) {
                dvui.Path.stroke(.{
                    .points = &.{
                        dvui.Point.Physical{
                            .x = self.data_rs.r.x + tick_line_len,
                            .y = tick_p.y,
                        },
                        dvui.Point.Physical{
                            .x = self.data_rs.r.x + self.data_rs.r.w,
                            .y = tick_p.y,
                        },
                    },
                }, .{
                    .color = dvui.Color.gray.opacity(0.6),
                    .thickness = 1,
                });
            }

            const points: []const dvui.Point.Physical = &.{
                dvui.Point.Physical{
                    .x = self.data_rs.r.x,
                    .y = tick_p.y,
                },
                dvui.Point.Physical{
                    .x = self.data_rs.r.x + tick_line_len,
                    .y = tick_p.y,
                },
            };

            switch (self.y_axis.ticks.lines) {
                .none => {},
                .one_side => {
                    dvui.Path.stroke(.{ .points = points }, .{
                        .color = bc,
                        .thickness = 1,
                    });
                },
                .mirrored => {
                    const off = dvui.Point.Physical{ .x = self.data_rs.r.w - tick_line_len, .y = 0 };
                    const other_side_points = &.{ points[0].plus(off), points[1].plus(off) };

                    dvui.Path.stroke(.{ .points = points }, .{
                        .color = bc,
                        .thickness = 1,
                    });
                    dvui.Path.stroke(.{ .points = other_side_points }, .{
                        .color = bc,
                        .thickness = 1,
                    });
                },
            }

            var tick_label_p = tick_p;
            tick_label_p.x -= tick_str_size.w + pad;
            tick_label_p.y -= tick_str_size.h / 2;
            const tick_rs: RectScale = .{ .r = Rect.Physical.fromPoint(tick_label_p).toSize(tick_str_size), .s = self.data_rs.s };

            dvui.renderText(.{
                .font = tick_font,
                .text = tick_str,
                .rs = tick_rs,
                .color = self.box.data().options.color(.text),
            }) catch |err| {
                dvui.logError(@src(), err, "y axis tick text for {d}", .{ytick});
            };
        }
    }

    // x axis ticks
    if (self.x_axis.name) |_| {
        for (xticks.values) |xtick| {
            const tick: Data = .{ .x = xtick, .y = self.y_axis.min orelse 0 };
            const tick_str = self.x_axis.formatTick(dvui.currentWindow().lifo(), xtick) catch "";
            defer dvui.currentWindow().lifo().free(tick_str);
            const tick_str_size = tick_font.textSize(tick_str).scale(self.data_rs.s, Size.Physical);

            const tick_p = self.dataToScreen(tick);

            if (self.x_axis.draw_gridlines) {
                dvui.Path.stroke(.{
                    .points = &.{
                        dvui.Point.Physical{
                            .x = tick_p.x,
                            .y = self.data_rs.r.y,
                        },
                        dvui.Point.Physical{
                            .x = tick_p.x,
                            .y = self.data_rs.r.y + self.data_rs.r.h - 5,
                        },
                    },
                }, .{
                    .color = dvui.Color.gray.opacity(0.6),
                    .thickness = 1,
                });
            }

            const points: []const dvui.Point.Physical = &.{
                dvui.Point.Physical{
                    .x = tick_p.x,
                    .y = self.data_rs.r.y + self.data_rs.r.h,
                },
                dvui.Point.Physical{
                    .x = tick_p.x,
                    .y = self.data_rs.r.y + self.data_rs.r.h - 5,
                },
            };

            switch (self.x_axis.ticks.lines) {
                .none => {},
                .one_side => {
                    dvui.Path.stroke(.{ .points = points }, .{
                        .color = bc,
                        .thickness = 1,
                    });
                },
                .mirrored => {
                    const off = dvui.Point.Physical{ .x = 0, .y = -(self.data_rs.r.h - 5) };
                    const other_side_points = &.{ points[0].plus(off), points[1].plus(off) };

                    dvui.Path.stroke(.{ .points = points }, .{
                        .color = bc,
                        .thickness = 1,
                    });
                    dvui.Path.stroke(.{ .points = other_side_points }, .{
                        .color = bc,
                        .thickness = 1,
                    });
                },
            }

            var tick_label_p = tick_p;
            tick_label_p.x -= tick_str_size.w / 2;
            tick_label_p.y += pad;
            const tick_rs: RectScale = .{ .r = Rect.Physical.fromPoint(tick_label_p).toSize(tick_str_size), .s = self.data_rs.s };

            dvui.renderText(.{
                .font = tick_font,
                .text = tick_str,
                .rs = tick_rs,
                .color = self.box.data().options.color(.text),
            }) catch |err| {
                dvui.logError(@src(), err, "x axis tick text for {d}", .{xtick});
            };
        }
    }

    if (bt > 0) {
        self.data_rs.r.stroke(.{}, .{ .thickness = bt * self.data_rs.s, .color = bc });
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

pub const BarOptions = struct {
    x: f64,
    y: f64,
    w: f64,
    h: f64,
    color: ?dvui.Color = null,
};

pub fn bar(self: *PlotWidget, opts: BarOptions) void {
    const dp1 = Data{ .x = opts.x, .y = opts.y };
    const dp2 = Data{ .x = opts.x + opts.w, .y = opts.y + opts.h };

    self.dataForRange(dp1);
    self.dataForRange(dp2);

    const sp1 = self.dataToScreen(dp1);
    const sp2 = self.dataToScreen(dp2);

    if (self.mouse_point) |mp| {
        const smin: dvui.Point.Physical = .{ .x = @min(sp1.x, sp2.x), .y = @min(sp1.y, sp2.y) };
        const smax: dvui.Point.Physical = .{ .x = @max(sp1.x, sp2.x), .y = @max(sp1.y, sp2.y) };
        const srect = dvui.Rect.Physical{
            .x = smin.x,
            .y = smin.y,
            .w = smax.x - smin.x,
            .h = smax.y - smin.y,
        };
        if (srect.contains(mp)) {
            self.hover_data = .{ .bar = .{
                .x = opts.x,
                .y = opts.y,
                .w = opts.w,
                .h = opts.h,
            } };
        }
    }

    dvui.Path.fillConvex(
        .{
            .points = &.{
                sp1,
                .{ .x = sp2.x, .y = sp1.y },
                sp2,
                .{ .x = sp1.x, .y = sp2.y },
            },
        },
        .{ .color = opts.color orelse dvui.themeGet().focus },
    );
}

pub fn deinit(self: *PlotWidget) void {
    const should_free = self.init_options.was_allocated_on_widget_stack;
    defer if (should_free) dvui.widgetFree(self);
    defer self.* = undefined;
    dvui.clipSet(self.old_clip);

    if (self.data_min.x == self.data_max.x) {
        self.data_min.x = self.data_min.x - 1;
        self.data_max.x = self.data_max.x + 1;
    }

    if (self.data_min.y == self.data_max.y) {
        self.data_min.y = self.data_min.y - 1;
        self.data_max.y = self.data_max.y + 1;
    }

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
        switch (hd) {
            .point => |p| self.hoverLabel("{d}, {d}", .{ p.x, p.y }),
            .bar => |b| self.hoverLabel("{d} to {d}, {d} to {d}", .{ b.x, b.x + b.w, b.y, b.y + b.h }),
        }
    }

    self.box.deinit();
}

fn hoverLabel(self: *@This(), comptime fmt: []const u8, args: anytype) void {
    var p = self.box.data().contentRectScale().pointFromPhysical(self.mouse_point.?);
    const str = std.fmt.allocPrint(dvui.currentWindow().lifo(), fmt, args) catch "";
    // NOTE: Always calling free is safe because fallback is a 0 len slice, which is ignored
    defer dvui.currentWindow().lifo().free(str);
    const size: Size = (dvui.Options{}).fontGet().textSize(str);
    p.x -= size.w / 2;
    const padding = dvui.LabelWidget.defaults.paddingGet();
    p.y -= size.h + padding.y + padding.h + 8;
    dvui.label(@src(), fmt, args, .{ .rect = Rect.fromPoint(p), .background = true, .border = Rect.all(1), .margin = .{} });
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
