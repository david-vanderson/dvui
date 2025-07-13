var calculation: f64 = 0;
var calculand: ?f64 = null;
var active_op: ?u8 = null;
var next_op: ?u8 = null;
var digits_after_dot: f64 = 0;
var reset_on_digit: bool = false;

/// ![image](Examples-calculator.png)
pub fn calculator() void {
    var vbox = dvui.box(@src(), .vertical, .{});
    defer vbox.deinit();

    const loop_labels = [_]u8{ 'C', 'N', '%', '/', '7', '8', '9', 'x', '4', '5', '6', '-', '1', '2', '3', '+', '0', '.', '=' };
    dvui.label(@src(), "{d}", .{if (calculand) |val| round(val) else round(calculation)}, .{ .gravity_x = 1.0 });

    for (0..5) |row_i| {
        var b = dvui.box(@src(), .horizontal, .{ .min_size_content = .{ .w = 110 }, .id_extra = row_i });
        defer b.deinit();

        for (row_i * 4..(row_i + 1) * 4) |i| {
            if (i >= loop_labels.len) continue;
            const letter = loop_labels[i];

            var opts = dvui.ButtonWidget.defaults.min_sizeM(3, 1);
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

const dvui = @import("../dvui.zig");
