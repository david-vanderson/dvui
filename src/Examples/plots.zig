/// ![image](Examples-plots.png)
pub fn plots() void {
    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Simple", .{}, .{});

        const xs: []const f64 = &.{ 0, 1, 2, 3, 4, 5 };
        const ys: []const f64 = &.{ 0, 4, 2, 6, 5, 9 };
        dvui.plotXY(@src(), .{ .xs = xs, .ys = ys }, .{});
    }

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Color and Thick", .{}, .{});

        const xs: []const f64 = &.{ 0, 1, 2, 3, 4, 5 };
        const ys: []const f64 = &.{ 9, 5, 6, 2, 4, 0 };
        dvui.plotXY(@src(), .{ .thick = 2, .xs = xs, .ys = ys, .color = dvui.themeGet().err.fill orelse .red }, .{});
    }

    var save: ?enum { png, jpg } = null;
    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();
        if (dvui.button(@src(), "Save png", .{}, .{})) {
            save = .png;
        }
        if (dvui.button(@src(), "Save jpg", .{}, .{})) {
            save = .jpg;
        }
    }

    {
        var vbox = dvui.box(@src(), .{}, .{ .min_size_content = .{ .w = 300, .h = 100 }, .expand = .ratio });
        defer vbox.deinit();

        var pic: ?dvui.Picture = null;
        if (save != null) {
            pic = dvui.Picture.start(vbox.data().contentRectScale().r);
        }

        const Static = struct {
            var xaxis: dvui.PlotWidget.Axis = .{
                .name = "X Axis",
                .min = 0.05,
                .max = 0.95,
                .ticks = .{
                    .lines = .one_side,
                },
                .draw_gridlines = false,
            };

            var yaxis: dvui.PlotWidget.Axis = .{
                .name = "Y Axis",
                // let plot figure out min
                .max = 0.8,
                .ticks = .{
                    .lines = .mirrored,
                },
                .draw_gridlines = false,
            };
        };

        var plot = dvui.plot(@src(), .{
            .title = "Plot Title",
            .x_axis = &Static.xaxis,
            .y_axis = &Static.yaxis,
            .border_thick = 1.0,
            .mouse_hover = true,
        }, .{ .expand = .both });
        defer plot.deinit();

        var s1 = plot.line();
        defer s1.deinit();

        const points: usize = 1000;
        const freq: f32 = 5;
        for (0..points + 1) |i| {
            const fval: f64 = @sin(2.0 * std.math.pi * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(points)) * freq);
            s1.point(@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(points)), fval);
        }
        s1.stroke(1, dvui.themeGet().focus);

        if (pic) |*p| {
            // `save` is not null because `pic` is not null
            p.stop();
            defer p.deinit();

            const filename: []const u8 = switch (save.?) {
                .png => "plot.png",
                .jpg => "plot.jpg",
            };

            if (dvui.wasm) blk: {
                var writer = std.Io.Writer.Allocating.init(dvui.currentWindow().arena());
                defer writer.deinit();
                (switch (save.?) {
                    .png => p.png(&writer.writer),
                    .jpg => p.jpg(&writer.writer),
                }) catch |err| {
                    dvui.logError(@src(), err, "Failed to write plot {t} image", .{save.?});
                    break :blk;
                };
                // No need to call `writer.flush` because `Allocating` doesn't drain it's buffer anywhere
                dvui.backend.downloadData(filename, writer.written()) catch |err| {
                    dvui.logError(@src(), err, "Could not download {s}", .{filename});
                };
            } else if (!dvui.useTinyFileDialogs) {
                dvui.toast(@src(), .{ .message = "Tiny File Dilaogs disabled" });
            } else {
                const maybe_path = dvui.dialogNativeFileSave(dvui.currentWindow().lifo(), .{ .path = filename }) catch null;
                if (maybe_path) |path| blk: {
                    defer dvui.currentWindow().lifo().free(path);

                    var file = std.fs.createFileAbsoluteZ(path, .{}) catch |err| {
                        dvui.log.debug("Failed to create file {s}, got {any}", .{ path, err });
                        dvui.toast(@src(), .{ .message = "Failed to create file" });
                        break :blk;
                    };
                    defer file.close();

                    var buffer: [256]u8 = undefined;
                    var writer = file.writer(&buffer);

                    (switch (save.?) {
                        .png => p.png(&writer.interface),
                        .jpg => p.jpg(&writer.interface),
                    }) catch |err| {
                        dvui.logError(@src(), err, "Failed to write plot {t} to file {s}", .{ save.?, path });
                    };
                    // End writing to file and potentially truncate any additional preexisting data
                    writer.end() catch |err| {
                        dvui.logError(@src(), err, "Failed to end file write for {s}", .{path});
                    };
                }
            }
        }
    }

    {
        const S = struct {
            var resistance: f64 = 159;
            var capacitance: f64 = 1e-6;
        };

        dvui.label(@src(), "Resistance (Ohm)", .{}, .{});
        const r_res = dvui.textEntryNumber(@src(), f64, .{
            .value = &S.resistance,
            .min = std.math.floatMin(f64),
        }, .{});

        dvui.label(@src(), "Capacitance (Farad)", .{}, .{});
        const c_res = dvui.textEntryNumber(@src(), f64, .{
            .value = &S.capacitance,
            .min = std.math.floatMin(f64),
        }, .{});

        const valid = r_res.value == .Valid and c_res.value == .Valid;

        const cutoff_angular_freq = 1 / (S.resistance * S.capacitance);

        dvui.label(@src(), "Cutoff frequency: {:.2} Hz", .{cutoff_angular_freq / (2 * std.math.pi)}, .{});

        var vbox = dvui.box(@src(), .{}, .{ .min_size_content = .{ .w = 300, .h = 100 }, .expand = .ratio });
        defer vbox.deinit();

        const Static = struct {
            var xaxis: dvui.PlotWidget.Axis = .{
                .name = "Frequency",
                .scale = .{ .log = .{} },
                .ticks = .{
                    .locations = .{
                        .auto = .{ .num_ticks = 9 },
                    },
                    .format = .{
                        .custom = formatFrequency,
                    },
                },
            };

            var yaxis: dvui.PlotWidget.Axis = .{
                .name = "Amplitude (dB)",
                .max = 10,
                .ticks = .{
                    .locations = .{
                        .auto = .{ .num_ticks = 6 },
                    },
                },
            };
        };

        var plot = dvui.plot(@src(), .{
            .title = "RC low-pass filter",
            .x_axis = &Static.xaxis,
            .y_axis = &Static.yaxis,
            .border_thick = 2.0,
            .mouse_hover = true,
        }, .{ .expand = .both });
        defer plot.deinit();

        var s1 = plot.line();
        defer s1.deinit();

        const start_exp: f64 = 0;
        const end_exp: f64 = 8;
        const points: usize = 1000;
        const step: f64 = (end_exp - start_exp) / @as(f64, @floatFromInt(points));

        for (0..points) |i| {
            const exp = start_exp + step * @as(f64, @floatFromInt(i));

            const freq: f64 = std.math.pow(f64, 10, exp);
            const angular_freq: f64 = 2 * std.math.pi * freq;

            const tmp = angular_freq * S.resistance * S.capacitance;
            const amplitude = std.math.sqrt(1 / (1 + tmp * tmp));
            const amplitude_db: f64 = 20 * @log10(amplitude);
            s1.point(freq, amplitude_db);
        }
        s1.stroke(1, if (valid) dvui.themeGet().focus else dvui.Color.red);
    }
}

fn formatFrequency(gpa: std.mem.Allocator, freq: f64) ![]const u8 {
    const exp = @log10(freq);
    const rounded_exp = std.math.round(exp);

    const val = std.math.pow(f64, 10, rounded_exp);

    if (rounded_exp < 3) {
        return try std.fmt.allocPrint(gpa, "{d:.0} Hz", .{val});
    } else if (rounded_exp < 6) {
        return try std.fmt.allocPrint(gpa, "{d:.0} kHz", .{val / 1e3});
    } else if (rounded_exp < 9) {
        return try std.fmt.allocPrint(gpa, "{d:.0} MHz", .{val / 1e6});
    } else unreachable;
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "DOCIMG plots" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 500, .h = 300 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .style = .window });
            defer box.deinit();
            plots();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-plots.png");
}

const std = @import("std");
const dvui = @import("../dvui.zig");
