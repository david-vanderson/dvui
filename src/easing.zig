//! Easing functions mainly used for animations. Controls the rate of change of a value,
//! used to turn a linearly changing value into a smooth, styalized change.
//!
//! Note that some easing functions can return values outside 0 and 1 for values of t
//! between 0 and 1.
//!
//! See [easings.net](https://easings.net/) for examples and visualizations

// Adapted from https://gist.github.com/Kryzarel/bba64622057f21a1d6d44879f9cd7bd4

const std = @import("std");
const dvui = @import("dvui.zig");

pub const EasingFn = fn (t: f32) f32;

/// ![curve](easing-plot-linear.png)
pub fn linear(t: f32) f32 {
    return t;
}

/// ![curve](easing-plot-inQuad.png)
pub fn inQuad(t: f32) f32 {
    return t * t;
}
/// ![curve](easing-plot-outQuad.png)
pub fn outQuad(t: f32) f32 {
    return 1 - inQuad(1 - t);
}
/// ![curve](easing-plot-inOutQuad.png)
pub fn inOutQuad(t: f32) f32 {
    if (t < 0.5) return inQuad(t * 2) / 2;
    return 1 - inQuad((1 - t) * 2) / 2;
}

/// ![curve](easing-plot-inCubic.png)
pub fn inCubic(t: f32) f32 {
    return t * t * t;
}
/// ![curve](easing-plot-outCubic.png)
pub fn outCubic(t: f32) f32 {
    return 1 - inCubic(1 - t);
}
/// ![curve](easing-plot-inOutCubic.png)
pub fn inOutCubic(t: f32) f32 {
    if (t < 0.5) return inCubic(t * 2) / 2;
    return 1 - inCubic((1 - t) * 2) / 2;
}

/// ![curve](easing-plot-inQuart.png)
pub fn inQuart(t: f32) f32 {
    return t * t * t * t;
}
/// ![curve](easing-plot-outQuart.png)
pub fn outQuart(t: f32) f32 {
    return 1 - inQuart(1 - t);
}
/// ![curve](easing-plot-inOutQuart.png)
pub fn inOutQuart(t: f32) f32 {
    if (t < 0.5) return inQuart(t * 2) / 2;
    return 1 - inQuart((1 - t) * 2) / 2;
}

/// ![curve](easing-plot-inQuint.png)
pub fn inQuint(t: f32) f32 {
    return t * t * t * t * t;
}
/// ![curve](easing-plot-outQuint.png)
pub fn outQuint(t: f32) f32 {
    return 1 - inQuint(1 - t);
}
/// ![curve](easing-plot-inOutQuint.png)
pub fn inOutQuint(t: f32) f32 {
    if (t < 0.5) return inQuint(t * 2) / 2;
    return 1 - inQuint((1 - t) * 2) / 2;
}

/// ![curve](easing-plot-inSine.png)
pub fn inSine(t: f32) f32 {
    return 1 - std.math.cos(t * std.math.pi / 2);
}
/// ![curve](easing-plot-outSine.png)
pub fn outSine(t: f32) f32 {
    return std.math.sin(t * std.math.pi / 2);
}
/// ![curve](easing-plot-inOutSine.png)
pub fn inOutSine(t: f32) f32 {
    return (std.math.cos(t * std.math.pi) - 1) / -2;
}

/// ![curve](easing-plot-inExpo.png)
pub fn inExpo(t: f32) f32 {
    return std.math.pow(f32, 2, 10 * (t - 1));
}
/// ![curve](easing-plot-outExpo.png)
pub fn outExpo(t: f32) f32 {
    return 1 - inExpo(1 - t);
}
/// ![curve](easing-plot-inOutExpo.png)
pub fn inOutExpo(t: f32) f32 {
    if (t < 0.5) return inExpo(t * 2) / 2;
    return 1 - inExpo((1 - t) * 2) / 2;
}

/// ![curve](easing-plot-inCirc.png)
pub fn inCirc(t: f32) f32 {
    return -(std.math.sqrt(1 - t * t) - 1);
}
/// ![curve](easing-plot-outCirc.png)
pub fn outCirc(t: f32) f32 {
    return 1 - inCirc(1 - t);
}
/// ![curve](easing-plot-inOutCirc.png)
pub fn inOutCirc(t: f32) f32 {
    if (t < 0.5) return inCirc(t * 2) / 2;
    return 1 - inCirc((1 - t) * 2) / 2;
}

/// ![curve](easing-plot-inElastic.png)
///
/// This function extents past 0 and 1 for values of t between 0 and 1
pub fn inElastic(t: f32) f32 {
    return 1 - outElastic(1 - t);
}
/// ![curve](easing-plot-outElastic.png)
///
/// This function extents past 0 and 1 for values of t between 0 and 1
pub fn outElastic(t: f32) f32 {
    const p: f32 = 0.3;
    return std.math.pow(f32, 2, -10 * t) * std.math.sin((t - p / 4) * (2 * std.math.pi) / p) + 1;
}
/// ![curve](easing-plot-inOutElastic.png)
///
/// This function extents past 0 and 1 for values of t between 0 and 1
pub fn inOutElastic(t: f32) f32 {
    if (t < 0.5) return inElastic(t * 2) / 2;
    return 1 - inElastic((1 - t) * 2) / 2;
}

/// ![curve](easing-plot-inBack.png)
///
/// This function extents past 0 and 1 for values of t between 0 and 1
pub fn inBack(t: f32) f32 {
    const s: f32 = 1.70158;
    return t * t * ((s + 1) * t - s);
}
/// ![curve](easing-plot-outBack.png)
///
/// This function extents past 0 and 1 for values of t between 0 and 1
pub fn outBack(t: f32) f32 {
    return 1 - inBack(1 - t);
}
/// ![curve](easing-plot-inOutBack.png)
///
/// This function extents past 0 and 1 for values of t between 0 and 1
pub fn inOutBack(t: f32) f32 {
    if (t < 0.5) return inBack(t * 2) / 2;
    return 1 - inBack((1 - t) * 2) / 2;
}

/// ![curve](easing-plot-inBounce.png)
pub fn inBounce(t: f32) f32 {
    return 1 - outBounce(1 - t);
}
/// ![curve](easing-plot-outBounce.png)
pub fn outBounce(t: f32) f32 {
    const div: f32 = 2.75;
    const mult: f32 = 7.5625;

    if (t < 1 / div) {
        return mult * t * t;
    } else if (t < 2 / div) {
        const x = t - 1.5 / div;
        return mult * x * x + 0.75;
    } else if (t < 2.5 / div) {
        const x = t - 2.25 / div;
        return mult * x * x + 0.9375;
    } else {
        const x = t - 2.625 / div;
        return mult * x * x + 0.984375;
    }
}
/// ![curve](easing-plot-inOutBounce.png)
pub fn inOutBounce(t: f32) f32 {
    if (t < 0.5) return inBounce(t * 2) / 2;
    return 1 - inBounce((1 - t) * 2) / 2;
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "DOCIMG easing plots" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 300, .h = 400 } });
    defer t.deinit();

    const plot = struct {
        var easing: *const EasingFn = linear;

        const resolution = 100;

        fn frame() !dvui.App.Result {
            var y_axis = dvui.PlotWidget.Axis{ .min = -0.5, .max = 1.5 };
            var x_axis = dvui.PlotWidget.Axis{ .min = -0.25, .max = 1.25 };
            var plot = dvui.plot(@src(), .{ .x_axis = &x_axis, .y_axis = &y_axis }, .{ .expand = .both });
            defer plot.deinit();

            var x_line = plot.line();
            defer x_line.deinit();
            x_line.point(0, 0);
            x_line.point(1, 0);
            x_line.stroke(1, dvui.Color.black);

            var y_line = plot.line();
            defer y_line.deinit();
            y_line.point(0, 0);
            y_line.point(0, 1);
            y_line.stroke(1, dvui.Color.black);

            var line = plot.line();
            defer line.deinit();
            for (0..resolution) |i| {
                const x = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(resolution));
                const y = easing(@floatCast(x));
                line.point(x, y);
            }
            line.stroke(1, plot.box.data().options.color(.accent));
            return .ok;
        }
    };

    try dvui.testing.settle(plot.frame);
    try t.saveImage(plot.frame, null, "easing-plot-linear.png");

    inline for (@typeInfo(@This()).@"struct".decls) |decl| {
        if (comptime std.mem.startsWith(u8, decl.name, "in") or std.mem.startsWith(u8, decl.name, "out")) {
            plot.easing = @field(@This(), decl.name);
            try t.saveImage(plot.frame, null, "easing-plot-" ++ decl.name ++ ".png");
        }
    }
}
