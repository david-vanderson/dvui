
pub fn applets() void {
    var vbox = dvui.box(@src(), .{}, .{ .expand = .both });
    defer vbox.deinit();

    var tabs = dvui.tabs(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });

    const active_tab = dvui.dataGetPtrDefault(null, vbox.data().id, "active_tab", usize, 0);

    if (tabs.addTabLabel(active_tab.* == 0, "calculator")) {
        active_tab.* = 0;
    }
    if (tabs.addTabLabel(active_tab.* == 1, "drawing")) {
        active_tab.* = 1;
    }

    tabs.deinit();

    switch (active_tab.*) {
        0 => calculator(),
        1 => draw(),
        else => {},
    }
}

var calculation: f64 = 0;
var calculand: ?f64 = null;
var active_op: ?u8 = null;
var next_op: ?u8 = null;
var digits_after_dot: f64 = 0;
var reset_on_digit: bool = false;

/// ![image](Examples-calculator.png)
pub fn calculator() void {
    var vbox = dvui.box(@src(), .{}, .{});
    defer vbox.deinit();

    const loop_labels = [_]u8{ 'C', 'N', '%', '/', '7', '8', '9', 'x', '4', '5', '6', '-', '1', '2', '3', '+', '0', '.', '=' };
    dvui.label(@src(), "{d}", .{if (calculand) |val| round(val) else round(calculation)}, .{ .gravity_x = 1.0 });

    for (0..5) |row_i| {
        var b = dvui.box(@src(), .{ .dir = .horizontal }, .{ .min_size_content = .{ .w = 110 }, .id_extra = row_i });
        defer b.deinit();

        for (row_i * 4..(row_i + 1) * 4) |i| {
            if (i >= loop_labels.len) continue;
            const letter = loop_labels[i];

            var opts = dvui.ButtonWidget.defaults.themeOverride(null).min_sizeM(3, 1);
            if (letter == '0') {
                const extra_space = opts.padSize(.{}).w;
                opts.min_size_content.?.w *= 2; // be twice as wide as normal
                opts.min_size_content.?.w += extra_space; // add the extra space between 2 buttons
            }
            if (dvui.button(@src(), &[_]u8{letter}, .{}, opts.override(.{ .id_extra = letter }))) {
                blk: switch (letter) {
                    'C' => {
                        calculation = 0;
                        calculand = null;
                        active_op = null;
                        next_op = null;
                        digits_after_dot = 0;
                    },
                    '/' => {
                        next_op = '/';
                        continue :blk '=';
                    },
                    'x' => {
                        next_op = 'x';
                        continue :blk '=';
                    },
                    '-' => {
                        next_op = '-';
                        continue :blk '=';
                    },
                    '+' => {
                        next_op = '+';
                        continue :blk '=';
                    },
                    '.' => digits_after_dot = 1,
                    'N' => {
                        calculation = -calculation;
                        active_op = null;
                        reset_on_digit = true;
                    },
                    '%' => {
                        calculation /= 100;
                        active_op = null;
                        reset_on_digit = true;
                    },
                    '0'...'9' => {
                        if (active_op == null) {
                            if (reset_on_digit) {
                                calculation = 0.0;
                                reset_on_digit = false;
                            }
                            const letterDigit: f32 = @floatFromInt(letter - '0');

                            if (digits_after_dot > 0) {
                                calculation += letterDigit / @exp(@log(10.0) * digits_after_dot);
                                digits_after_dot += 1;
                            } else {
                                calculation *= 10;
                                calculation += letterDigit;
                            }
                        } else {
                            if (calculand == null) calculand = 0.0;
                            const letterDigit: f64 = @floatFromInt(letter - '0');
                            if (digits_after_dot > 0) {
                                calculand.? += letterDigit / @exp(@log(10.0) * digits_after_dot);
                                digits_after_dot += 1;
                            } else {
                                calculand.? *= 10;
                                calculand.? += letterDigit;
                            }
                        }
                    },
                    '=' => if (active_op != null) {
                        if (calculand) |val| {
                            if (active_op == '/') calculation /= val;
                            if (active_op == '-') calculation -= val;
                            if (active_op == '+') calculation += val;
                            if (active_op == 'x') calculation *= val;
                        }
                        active_op = next_op;
                        if (active_op == null) {
                            // User pressed equals. Start a new calc from here if a digit is pressed.
                            reset_on_digit = true;
                        }
                        next_op = null;
                        calculand = null;
                        digits_after_dot = 0;
                    },
                    else => unreachable,
                }
                if (active_op == null and next_op != null) {
                    active_op = next_op;
                    next_op = null;
                }
            }
        }
    }
}

pub fn round(val: f64) f64 {
    const dec_places = 1_000_000;
    return @round(val * dec_places) / dec_places;
}

const Tools = enum {
    pencil,
    eraser,
};

pub fn draw() void {
    const uniqId = dvui.parentGet().extendId(@src(), 0);
    const active_tool = dvui.dataGetPtrDefault(null, uniqId, "active_tool", Tools, .pencil);
    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        var group = dvui.radioGroup(@src(), .{}, .{ .label = .{ .text = "Drawing Tools" } });
        defer group.deinit();

        if (dvui.radio(@src(), active_tool.* == .pencil, "Pencil", .{})) {
            active_tool.* = .pencil;
        }

        if (dvui.radio(@src(), active_tool.* == .eraser, "Eraser", .{})) {
            active_tool.* = .eraser;
        }
    }

    var points: std.ArrayList(dvui.Point) = .empty;
    if (dvui.dataGetSlice(null, uniqId, "points", []dvui.Point)) |pts| {
        points.appendSlice(dvui.currentWindow().arena(), pts) catch @panic("OOM");
    }

    var canvas = dvui.box(@src(), .{}, .{ .expand = .both });
    defer canvas.deinit();
    const rs = canvas.data().contentRectScale();

    const events = dvui.events();
    for (events) |*e| {
        if (!dvui.eventMatchSimple(e, canvas.data())) continue;

        switch (e.evt) {
            .mouse => |m| {
                switch (m.action) {
                    .press => {
                        if (m.button == .left) {
                            e.handle(@src(), canvas.data());
                            dvui.captureMouse(canvas.data(), e.num);
                            const newp = rs.pointFromPhysical(m.p);
                            if (active_tool.* == .pencil) {
                                points.append(dvui.currentWindow().arena(), newp) catch @panic("OOM");
                                dvui.refresh(null, @src(), canvas.data().id);
                            } else if (active_tool.* == .eraser) {
                                var i: usize = 0;
                                while (i < points.items.len) {
                                    const p = points.items[i];
                                    const dx = p.x - newp.x;
                                    const dy = p.y - newp.y;
                                    if ((dx * dx + dy * dy) < 5 * 5) {
                                        _ = points.swapRemove(i);
                                    } else {
                                        i += 1;
                                    }
                                }
                            }
                        }
                    },
                    .motion => {
                        if (dvui.captured(canvas.data().id)) {
                            const newp = rs.pointFromPhysical(m.p);
                            if (active_tool.* == .pencil) {
                                points.append(dvui.currentWindow().arena(), newp) catch @panic("OOM");
                                dvui.refresh(null, @src(), canvas.data().id);
                            } else if (active_tool.* == .eraser) {
                                var i: usize = 0;
                                while (i < points.items.len) {
                                    const p = points.items[i];
                                    const dx = p.x - newp.x;
                                    const dy = p.y - newp.y;
                                    if ((dx * dx + dy * dy) < 5 * 5) {
                                        _ = points.swapRemove(i);
                                    } else {
                                        i += 1;
                                    }
                                }
                            }
                        }
                    },
                    .release => {
                        if (dvui.captured(canvas.data().id)) {
                            dvui.captureMouse(null, e.num);
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    for (points.items) |p| {
        dvui.Path.stroke(.{ .points = &.{ rs.pointToPhysical(p) } }, .{
            .color = dvui.Color{ .b = 120, .g = 12, .r = 212 },
            .thickness = 5 * rs.s,
        });
    }

    dvui.dataSetSlice(null, uniqId, "points", points.items);
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "DOCIMG calculator" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 250, .h = 250 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .style = .window });
            defer box.deinit();
            calculator();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-calculator.png");
}

const dvui = @import("../dvui.zig");
const std = @import("std");
