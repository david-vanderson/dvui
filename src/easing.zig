//! Easing functions mainly used for animations. Controls the rate of change of a value,
//! used to turn a linearly changing value into a smooth, styalized change.
//!
//! See [easings.net](https://easings.net/) for examples and visualizations

// Adapted from https://gist.github.com/Kryzarel/bba64622057f21a1d6d44879f9cd7bd4

const std = @import("std");

pub const EasingFn = fn (t: f32) f32;

pub fn linear(t: f32) f32 {
    return t;
}

pub fn inQuad(t: f32) f32 {
    return t * t;
}
pub fn outQuad(t: f32) f32 {
    return 1 - inQuad(1 - t);
}
pub fn inOutQuad(t: f32) f32 {
    if (t < 0.5) return inQuad(t * 2) / 2;
    return 1 - inQuad((1 - t) * 2) / 2;
}

pub fn inCubic(t: f32) f32 {
    return t * t * t;
}
pub fn outCubic(t: f32) f32 {
    return 1 - inCubic(1 - t);
}
pub fn inOutCubic(t: f32) f32 {
    if (t < 0.5) return inCubic(t * 2) / 2;
    return 1 - inCubic((1 - t) * 2) / 2;
}

pub fn inQuart(t: f32) f32 {
    return t * t * t * t;
}
pub fn outQuart(t: f32) f32 {
    return 1 - inQuart(1 - t);
}
pub fn inOutQuart(t: f32) f32 {
    if (t < 0.5) return inQuart(t * 2) / 2;
    return 1 - inQuart((1 - t) * 2) / 2;
}

pub fn inQuint(t: f32) f32 {
    return t * t * t * t * t;
}
pub fn outQuint(t: f32) f32 {
    return 1 - inQuint(1 - t);
}
pub fn inOutQuint(t: f32) f32 {
    if (t < 0.5) return inQuint(t * 2) / 2;
    return 1 - inQuint((1 - t) * 2) / 2;
}

pub fn inSine(t: f32) f32 {
    return 1 - std.math.cos(t * std.math.pi / 2);
}
pub fn outSine(t: f32) f32 {
    return std.math.sin(t * std.math.pi / 2);
}
pub fn inOutSine(t: f32) f32 {
    return (std.math.cos(t * std.math.pi) - 1) / -2;
}

pub fn inExpo(t: f32) f32 {
    return std.math.pow(f32, 2, 10 * (t - 1));
}
pub fn outExpo(t: f32) f32 {
    return 1 - inExpo(1 - t);
}
pub fn inOutExpo(t: f32) f32 {
    if (t < 0.5) return inExpo(t * 2) / 2;
    return 1 - inExpo((1 - t) * 2) / 2;
}

pub fn inCirc(t: f32) f32 {
    return -(std.math.sqrt(1 - t * t) - 1);
}
pub fn outCirc(t: f32) f32 {
    return 1 - inCirc(1 - t);
}
pub fn inOutCirc(t: f32) f32 {
    if (t < 0.5) return inCirc(t * 2) / 2;
    return 1 - inCirc((1 - t) * 2) / 2;
}

pub fn inElastic(t: f32) f32 {
    return 1 - outElastic(1 - t);
}
pub fn outElastic(t: f32) f32 {
    const p: f32 = 0.3;
    return std.math.pow(f32, 2, -10 * t) * std.math.sin((t - p / 4) * (2 * std.math.pi) / p) + 1;
}
pub fn inOutElastic(t: f32) f32 {
    if (t < 0.5) return inElastic(t * 2) / 2;
    return 1 - inElastic((1 - t) * 2) / 2;
}

pub fn inBack(t: f32) f32 {
    const s: f32 = 1.70158;
    return t * t * ((s + 1) * t - s);
}
pub fn outBack(t: f32) f32 {
    return 1 - inBack(1 - t);
}
pub fn inOutBack(t: f32) f32 {
    if (t < 0.5) return inBack(t * 2) / 2;
    return 1 - inBack((1 - t) * 2) / 2;
}

pub fn inBounce(t: f32) f32 {
    return 1 - outBounce(1 - t);
}
pub fn outBounce(t: f32) f32 {
    const div: f32 = 2.75;
    const mult: f32 = 7.5625;

    if (t < 1 / div) {
        return mult * t * t;
    } else if (t < 2 / div) {
        t -= 1.5 / div;
        return mult * t * t + 0.75;
    } else if (t < 2.5 / div) {
        t -= 2.25 / div;
        return mult * t * t + 0.9375;
    } else {
        t -= 2.625 / div;
        return mult * t * t + 0.984375;
    }
}
pub fn inOutBounce(t: f32) f32 {
    if (t < 0.5) return inBounce(t * 2) / 2;
    return 1 - inBounce((1 - t) * 2) / 2;
}
