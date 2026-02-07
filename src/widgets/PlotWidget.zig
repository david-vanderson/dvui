pub const PlotWidget = @This();

src: std.builtin.SourceLocation,
opts: Options,
box: BoxWidget = undefined,
data_rs: RectScale = undefined,
old_clip: Rect.Physical = undefined,
init_options: InitOptions,
x_axis: *Axis = undefined,
x_axis_store: Axis = .{},
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
                tick_num_suggestion: usize = 5,
                tick_num_max: usize = 20,
            },
            custom: []const f64,
        } = .{ .auto = .{} },

        side: TicklinesSide = .both,

        // if null it uses the default for `scale`
        format: ?TickFormating = null,

        subticks: bool = false,
    } = .{},

    // only relevant if `ticks.locations` != none
    // if null the gridlines are not rendered
    gridline_color: ?dvui.Color = null,
    subtick_gridline_color: ?dvui.Color = null,

    pub const TicklinesSide = enum {
        none,
        left_or_top,
        right_or_bottom,
        both,
    };

    pub const TickLocatorType = enum {
        none,
        auto,
        custom,
    };

    pub const Ticks = struct {
        locator_type: TickLocatorType,
        values: []const f64,
        subticks: []const f64,

        fn deinit(self: *Ticks, gpa: std.mem.Allocator) void {
            switch (self.locator_type) {
                .auto => {
                    gpa.free(self.values);
                    gpa.free(self.subticks);
                },
                else => {},
            }
        }

        const empty = Ticks{
            .locator_type = .none,
            .values = &.{},
            .subticks = &.{},
        };
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

    // nice steps are 1, 2, 5, 10
    fn niceStep(approx_step: f64) f64 {
        const exp = std.math.floor(std.math.log10(approx_step));
        const multiplier = std.math.pow(f64, 10, exp);
        const mantissa = approx_step / multiplier;
        // mantissa is [0, 10)

        const nice_mantissa: f64 = if (mantissa < 1.5)
            1
        else if (mantissa < 3)
            2
        else if (mantissa < 7)
            5
        else
            10;

        return nice_mantissa * multiplier;
    }

    fn getTicksLinear(
        gpa: std.mem.Allocator,
        min: f64,
        max: f64,
        tick_num_suggestion: usize,
        tick_num_max: usize,
        calc_subticks: bool,
    ) !Ticks {
        if (tick_num_suggestion == 0 or tick_num_max == 0) return Ticks.empty;

        const approximate_step = (max - min) / @as(f64, @floatFromInt(tick_num_suggestion));
        const nice_step = niceStep(approximate_step);

        const first_tick = std.math.ceil(min / nice_step) * nice_step;
        const tick_count_best: usize = @intFromFloat(std.math.ceil((max - first_tick) / nice_step));

        const tick_count = @min(tick_num_max, tick_count_best);

        var ticks = try gpa.alloc(f64, tick_count);
        for (0..tick_count) |i| {
            const tick = first_tick + @as(f64, @floatFromInt(i)) * nice_step;
            ticks[i] = tick;
        }

        const subticks = blk: {
            if (calc_subticks) {
                const subtick_count: usize = 3;
                const subticks = try gpa.alloc(f64, (ticks.len + 1) * subtick_count);

                for (0..ticks.len + 1) |i| {
                    const tick = if (i == 0)
                        ticks[0] - nice_step
                    else
                        ticks[i - 1];

                    for (0..subtick_count) |j| {
                        const ratio = @as(f64, @floatFromInt(1 + j)) / @as(f64, @floatFromInt(subtick_count + 1));
                        const off: f64 = ratio * nice_step;
                        subticks[i * subtick_count + j] = tick + off;
                    }
                }
                break :blk subticks;
            } else {
                break :blk &.{};
            }
        };

        return Ticks{
            .locator_type = .auto,
            .values = ticks,
            .subticks = subticks,
        };
    }

    fn getTicksLog(
        gpa: std.mem.Allocator,
        base: f64,
        min: f64,
        max: f64,
        tick_num_suggestion: usize,
        tick_num_max: usize,
        calc_subticks: bool,
    ) !Ticks {
        const first_tick_exp = std.math.ceil(std.math.log(f64, base, min));
        const last_tick_exp = std.math.floor(std.math.log(f64, base, max));

        const exp_range = last_tick_exp - first_tick_exp;
        const step_raw = std.math.round(exp_range / @as(f64, @floatFromInt(tick_num_suggestion)));
        // the exponent step is clamped to a minimum of 1
        const step = @max(step_raw, 1);

        const tick_count = @min(
            tick_num_max,
            @as(usize, @intFromFloat(last_tick_exp - first_tick_exp)) + 1,
        );

        var ticks = try gpa.alloc(f64, tick_count);
        for (0..tick_count) |i| {
            const exp = first_tick_exp + @as(f64, @floatFromInt(i)) * step;
            const tick = std.math.pow(f64, base, exp);
            ticks[i] = tick;
        }

        const subticks = blk: {
            if (calc_subticks) {
                const subtick_count: usize = @intFromFloat(base - 2);
                const subticks = try gpa.alloc(f64, ticks.len * subtick_count);

                for (0.., ticks) |i, tick| {
                    for (0..subtick_count) |j| {
                        const multiplier: f64 = @floatFromInt(2 + j);
                        subticks[i * subtick_count + j] = tick * multiplier;
                    }
                }
                break :blk subticks;
            } else {
                break :blk &.{};
            }
        };

        return Ticks{
            .locator_type = .auto,
            .values = ticks,
            .subticks = subticks,
        };
    }

    pub fn getTicks(self: *Axis, gpa: std.mem.Allocator) !Ticks {
        switch (self.ticks.locations) {
            .none => return Ticks.empty,
            .auto => |auto_ticks| {
                const min = self.min orelse return Ticks.empty;
                const max = self.max orelse return Ticks.empty;

                return switch (self.scale) {
                    .linear => getTicksLinear(
                        gpa,
                        min,
                        max,
                        auto_ticks.tick_num_suggestion,
                        auto_ticks.tick_num_max,
                        self.ticks.subticks,
                    ),
                    .log => |log_scale| getTicksLog(
                        gpa,
                        log_scale.base,
                        min,
                        max,
                        auto_ticks.tick_num_suggestion,
                        auto_ticks.tick_num_max,
                        self.ticks.subticks,
                    ),
                };
            },
            .custom => |ticks| {
                return Ticks{
                    .locator_type = .custom,
                    .values = ticks,
                    .subticks = &.{},
                };
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
        dvui.label(@src(), "{s}", .{title}, .{ .gravity_x = 0.5, .font = opts.themeGet().font_title });
    }

    const tick_font = opts.themeGet().font_body.larger(-3);

    var yticks = self.y_axis.getTicks(dvui.currentWindow().lifo()) catch Axis.Ticks.empty;
    defer yticks.deinit(dvui.currentWindow().lifo());

    var xticks = self.x_axis.getTicks(dvui.currentWindow().lifo()) catch Axis.Ticks.empty;
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
    const subtick_line_len = 3;

    // y axis ticks
    if (self.y_axis.name) |_| {
        for (yticks.values) |ytick| {
            const tick: Data = .{ .x = self.x_axis.min orelse 0, .y = ytick };
            const tick_str = self.y_axis.formatTick(dvui.currentWindow().lifo(), ytick) catch "";
            defer dvui.currentWindow().lifo().free(tick_str);
            const tick_str_size = tick_font.textSize(tick_str).scale(self.data_rs.s, Size.Physical);

            const tick_p = self.dataToScreen(tick);
            self.drawTickline(
                .vertical,
                tick_p,
                tick_line_len,
                self.y_axis.ticks.side,
                bc,
                self.y_axis.gridline_color,
            );

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

        for (yticks.subticks) |ytick| {
            const tick: Data = .{ .x = self.x_axis.min orelse 0, .y = ytick };
            const tick_p = self.dataToScreen(tick);
            self.drawTickline(
                .vertical,
                tick_p,
                subtick_line_len,
                self.y_axis.ticks.side,
                bc,
                self.y_axis.subtick_gridline_color,
            );
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
            self.drawTickline(
                .horizontal,
                tick_p,
                tick_line_len,
                self.x_axis.ticks.side,
                bc,
                self.x_axis.gridline_color,
            );

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

        for (xticks.subticks) |xtick| {
            const tick: Data = .{ .x = xtick, .y = self.y_axis.min orelse 0 };
            const tick_p = self.dataToScreen(tick);
            self.drawTickline(
                .horizontal,
                tick_p,
                subtick_line_len,
                self.x_axis.ticks.side,
                bc,
                self.x_axis.subtick_gridline_color,
            );
        }
    }

    if (bt > 0) {
        self.data_rs.r.stroke(.{}, .{ .thickness = bt * self.data_rs.s, .color = bc });
    }

    self.old_clip = dvui.clip(self.data_rs.r);
}

fn drawTickline(
    self: *PlotWidget,
    dir: dvui.enums.Direction,
    tick_p: dvui.Point.Physical,
    tick_line_len: f32,
    side: PlotWidget.Axis.TicklinesSide,
    tick_line_color: dvui.Color,
    gridline_color: ?dvui.Color,
) void {
    if (tick_p.x < self.data_rs.r.x or tick_p.x > self.data_rs.r.x + self.data_rs.r.w) return;
    if (tick_p.y < self.data_rs.r.y or tick_p.y > self.data_rs.r.y + self.data_rs.r.h) return;
    // these are the positions for ticks on the left or top
    const line_start, const line_end, const gridline_start, const gridline_end = switch (dir) {
        .horizontal => blk: {
            const start = dvui.Point.Physical{
                .x = tick_p.x,
                .y = self.data_rs.r.y + self.data_rs.r.h - tick_line_len,
            };
            const end = dvui.Point.Physical{
                .x = tick_p.x,
                .y = self.data_rs.r.y + self.data_rs.r.h,
            };

            const gridline_start = dvui.Point.Physical{
                .x = tick_p.x,
                .y = self.data_rs.r.y,
            };
            const gridline_end = dvui.Point.Physical{
                .x = tick_p.x,
                .y = self.data_rs.r.y + self.data_rs.r.h,
            };

            break :blk .{ start, end, gridline_start, gridline_end };
        },
        .vertical => blk: {
            const start = dvui.Point.Physical{
                .x = self.data_rs.r.x,
                .y = tick_p.y,
            };
            const end = dvui.Point.Physical{
                .x = self.data_rs.r.x + tick_line_len,
                .y = tick_p.y,
            };

            const gridline_start = dvui.Point.Physical{
                .x = self.data_rs.r.x,
                .y = tick_p.y,
            };
            const gridline_end = dvui.Point.Physical{
                .x = self.data_rs.r.x + self.data_rs.r.w,
                .y = tick_p.y,
            };

            break :blk .{ start, end, gridline_start, gridline_end };
        },
    };

    if (gridline_color) |col| {
        dvui.Path.stroke(.{
            .points = &.{ gridline_start, gridline_end },
        }, .{
            .color = col,
            .thickness = 1,
        });
    }

    const left_or_top_pts: []const dvui.Point.Physical = &.{ line_start, line_end };

    const off = switch (dir) {
        .horizontal => dvui.Point.Physical{ .x = 0, .y = -(self.data_rs.r.h - tick_line_len) },
        .vertical => dvui.Point.Physical{ .x = self.data_rs.r.w - tick_line_len, .y = 0 },
    };

    const right_or_bottom_pts: []const dvui.Point.Physical = &.{
        left_or_top_pts[0].plus(off),
        left_or_top_pts[1].plus(off),
    };

    switch (side) {
        .none => {},
        .left_or_top => {
            dvui.Path.stroke(.{ .points = left_or_top_pts }, .{
                .color = tick_line_color,
                .thickness = 1,
            });
        },
        .right_or_bottom => {
            dvui.Path.stroke(.{ .points = right_or_bottom_pts }, .{
                .color = tick_line_color,
                .thickness = 1,
            });
        },
        .both => {
            dvui.Path.stroke(.{ .points = left_or_top_pts }, .{
                .color = tick_line_color,
                .thickness = 1,
            });
            dvui.Path.stroke(.{ .points = right_or_bottom_pts }, .{
                .color = tick_line_color,
                .thickness = 1,
            });
        },
    }
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
    defer if (dvui.widgetIsAllocated(self)) dvui.widgetFree(self);
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
