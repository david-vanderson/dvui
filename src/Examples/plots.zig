/// ![image](Examples-plots.png)
pub fn plots() void {
    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Simple", .{}, .{});

        const xs: []const f64 = &.{ 0, 1, 2, 3, 4, 5 };
        const ys: []const f64 = &.{ 0, 4, 2, 6, 5, 9 };
        dvui.plotXY(@src(), .{}, 1, xs, ys, .{});
    }

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Color and Thick", .{}, .{});

        const xs: []const f64 = &.{ 0, 1, 2, 3, 4, 5 };
        const ys: []const f64 = &.{ 9, 5, 6, 2, 4, 0 };
        dvui.plotXY(@src(), .{}, 2, xs, ys, .{ .color_accent = dvui.themeGet().err.fill orelse .red });
    }

    var save: bool = false;
    if (dvui.button(@src(), "Save Plot", .{}, .{ .gravity_x = 1.0 })) {
        save = true;
    }

    var vbox = dvui.box(@src(), .{}, .{ .min_size_content = .{ .w = 300, .h = 100 }, .expand = .ratio });
    defer vbox.deinit();

    var pic: ?dvui.Picture = null;
    if (save) {
        pic = dvui.Picture.start(vbox.data().contentRectScale().r);
    }

    const Static = struct {
        var xaxis: dvui.PlotWidget.Axis = .{
            .name = "X Axis",
            .min = 0.05,
            .max = 0.95,
        };

        var yaxis: dvui.PlotWidget.Axis = .{
            .name = "Y Axis",
            // let plot figure out min
            .max = 0.8,
        };
    };

    {
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
    }

    if (pic) |*p| {
        p.stop();
        defer p.deinit();

        const arena = dvui.currentWindow().lifo();

        if (p.png(arena) catch null) |png_slice| {
            defer arena.free(png_slice);

            if (dvui.wasm) {
                dvui.backend.downloadData("plot.png", png_slice) catch |err| {
                    dvui.logError(@src(), err, "Could not download plot.png", .{});
                };
            } else {
                const filename = dvui.dialogNativeFileSave(arena, .{ .path = "plot.png" }) catch null;
                if (filename) |fname| blk: {
                    defer arena.free(fname);

                    var file = std.fs.createFileAbsoluteZ(fname, .{}) catch |err| {
                        dvui.log.debug("Failed to create file {s}, got {!}", .{ fname, err });
                        dvui.toast(@src(), .{ .message = "Failed to create file" });
                        break :blk;
                    };
                    defer file.close();

                    file.writeAll(png_slice) catch |err| {
                        dvui.log.debug("Failed to write to file {s}, got {!}", .{ fname, err });
                    };
                }
            }
        }
    }
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "DOCIMG plots" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 500, .h = 300 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .color_fill = .fill_window });
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
