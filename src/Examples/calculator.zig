var calculation: f64 = 0;
var calculand: ?f64 = null;
var active_op: ?u8 = null;
var digits_after_dot: f64 = 0;

/// ![image](Examples-calculator.png)
pub fn calculator() void {
    var vbox = dvui.box(@src(), .vertical, .{});
    defer vbox.deinit();

    const loop_labels = [_]u8{ 'C', 'N', '%', '/', '7', '8', '9', 'x', '4', '5', '6', '-', '1', '2', '3', '+', '0', '.', '=' };
    const loop_count = @sizeOf(@TypeOf(loop_labels)) / @sizeOf(@TypeOf(loop_labels[0]));

    dvui.label(@src(), "{d}", .{if (calculand) |val| val else calculation}, .{ .gravity_x = 1.0 });

    for (0..5) |row_i| {
        var b = dvui.box(@src(), .horizontal, .{ .min_size_content = .{ .w = 110 }, .id_extra = row_i });
        defer b.deinit();

        for (row_i * 4..(row_i + 1) * 4) |i| {
            if (i >= loop_count) continue;
            const letter = loop_labels[i];

            var opts = dvui.ButtonWidget.defaults.min_sizeM(3, 1);
            if (letter == '0') {
                const extra_space = opts.padSize(.{}).w;
                opts.min_size_content.?.w *= 2; // be twice as wide as normal
                opts.min_size_content.?.w += extra_space; // add the extra space between 2 buttons
            }
            if (dvui.button(@src(), &[_]u8{letter}, .{}, opts.override(.{ .id_extra = letter }))) {
                if (letter == 'C') {
                    calculation = 0;
                    calculand = null;
                    active_op = null;
                    digits_after_dot = 0;
                }

                if (letter == '/') {
                    active_op = '/';
                    digits_after_dot = 0;
                }
                if (letter == 'x') {
                    active_op = 'x';
                    digits_after_dot = 0;
                }
                if (letter == '-') {
                    active_op = '-';
                    digits_after_dot = 0;
                }
                if (letter == '+') {
                    active_op = '+';
                    digits_after_dot = 0;
                }
                if (letter == '.') digits_after_dot = 1;

                if (letter == 'N') calculation = -calculation;
                if (letter == '%') calculation /= 100;

                if (active_op == null) {
                    if (letter >= '0' and letter <= '9') {
                        const letterDigit: f32 = @floatFromInt(letter - '0');

                        if (digits_after_dot > 0) {
                            calculation += letterDigit / @exp(@log(10.0) * digits_after_dot);
                            digits_after_dot += 1;
                        } else {
                            calculation *= 10;
                            calculation += letterDigit;
                        }
                    }
                    if (letter == '.') {}
                }

                if (active_op != null) {
                    if (letter >= '0' and letter <= '9') {
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
                    if (letter == '=') {
                        if (calculand) |val| {
                            if (active_op == '/') calculation /= val;
                            if (active_op == '-') calculation -= val;
                            if (active_op == '+') calculation += val;
                            if (active_op == 'x') calculation *= val;
                        }
                        active_op = null;
                        calculand = null;
                        digits_after_dot = 0;
                    }
                }
            }
        }
    }
}

const dvui = @import("../dvui.zig");
