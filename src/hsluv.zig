//HSLuv-C: Human-friendly HSL
//<https://github.com/hsluv/hsluv-c>
//<https://www.hsluv.org/>
//
//Copyright (c) 2015 Alexei Boronine (original idea, JavaScript implementation)
//Copyright (c) 2015 Roger Tallada (Obj-C implementation)
//Copyright (c) 2017 Martin Mitáš (C implementation, based on Obj-C implementation)
//Copyright (c) 2024 David Vanderson (Zig implementation, based on C implementation)
//
//Permission is hereby granted, free of charge, to any person obtaining a
//copy of this software and associated documentation files (the "Software"),
//to deal in the Software without restriction, including without limitation
//the rights to use, copy, modify, merge, publish, distribute, sublicense,
//and/or sell copies of the Software, and to permit persons to whom the
//Software is furnished to do so, subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in
//all copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
//OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//IN THE SOFTWARE.

const std = @import("std");

pub const Triplet = struct {
    a: f32,
    b: f32,
    c: f32,
};

// zig fmt: off
// for RGB
const m: [3]Triplet = [_]Triplet{
    .{ .a =  3.24096994190452134377, .b = -1.53738317757009345794, .c = -0.49861076029300328366 },
    .{ .a = -0.96924363628087982613, .b =  1.87596750150772066772, .c =  0.04155505740717561247 },
    .{ .a =  0.05563007969699360846, .b = -0.20397695888897656435, .c =  1.05697151424287856072 }
};

// for XYZ
const m_inv: [3]Triplet = [_]Triplet{
    .{ .a = 0.41239079926595948129, .b = 0.35758433938387796373, .c = 0.18048078840183428751 },
    .{ .a = 0.21263900587151035754, .b = 0.71516867876775592746, .c = 0.07219231536073371500 },
    .{ .a = 0.01933081871559185069, .b = 0.11919477979462598791, .c = 0.95053215224966058086 }
};
// zig fmt: on

const ref_u = 0.19783000664283680764;
const ref_v = 0.46831999493879100370;

const kappa = 903.29629629629629629630;
const epsilon = 0.00885645167903563082;

const Bounds = struct {
    a: f32,
    b: f32,
};

fn get_bounds(l: f32, bounds: *[6]Bounds) void {
    const tl = l + 16.0;
    const sub1 = (tl * tl * tl) / 1560896.0;
    const sub2 = if (sub1 > epsilon) sub1 else (l / kappa);

    for (0..3) |channel| {
        const m1 = m[channel].a;
        const m2 = m[channel].b;
        const m3 = m[channel].c;

        for (0..2) |t| {
            const top1 = (284517.0 * m1 - 94839.0 * m3) * sub2;
            const top2 = (838422.0 * m3 + 769860.0 * m2 + 731718.0 * m1) * l * sub2 - 769860.0 * @as(f32, @floatFromInt(t)) * l;
            const bottom = (632260.0 * m3 - 126452.0 * m2) * sub2 + 126452.0 * @as(f32, @floatFromInt(t));

            bounds[channel * 2 + t].a = top1 / bottom;
            bounds[channel * 2 + t].b = top2 / bottom;
        }
    }
}

fn intersect_line_line(line1: Bounds, line2: Bounds) f32 {
    return (line1.b - line2.b) / (line2.a - line1.a);
}

fn dist_from_pole_squared(x: f32, y: f32) f32 {
    return x * x + y * y;
}

fn ray_length_until_intersect(theta: f32, line: Bounds) f32 {
    return line.b / (@sin(theta) - line.a * @cos(theta));
}

fn max_safe_chroma_for_l(l: f32) f32 {
    var min_len_squared: f32 = std.math.floatMax(f32);
    var bounds: [6]Bounds = undefined;

    get_bounds(l, &bounds);
    for (0..6) |i| {
        const m1 = bounds[i].a;
        const b1 = bounds[i].b;
        // x where line intersects with perpendicular running though (0, 0)
        const line2 = Bounds{ .a = -1.0 / m1, .b = 0.0 };
        const x = intersect_line_line(bounds[i], line2);
        const distance = dist_from_pole_squared(x, b1 + x * m1);

        if (distance < min_len_squared)
            min_len_squared = distance;
    }

    return @sqrt(min_len_squared);
}

fn max_chroma_for_lh(l: f32, h: f32) f32 {
    var min_len: f32 = std.math.floatMax(f32);
    const hrad = h * 0.01745329251994329577; // (2 * pi / 360)
    var bounds: [6]Bounds = undefined;

    get_bounds(l, &bounds);
    for (0..6) |i| {
        const len = ray_length_until_intersect(hrad, bounds[i]);

        if (len >= 0 and len < min_len)
            min_len = len;
    }
    return min_len;
}

fn dot_product(t1: Triplet, t2: Triplet) f32 {
    return (t1.a * t2.a + t1.b * t2.b + t1.c * t2.c);
}

// Used for rgb conversions
fn from_linear(c: f32) f32 {
    if (c <= 0.0031308) {
        return 12.92 * c;
    } else {
        return 1.055 * std.math.pow(f32, c, 1.0 / 2.4) - 0.055;
    }
}

fn to_linear(c: f32) f32 {
    if (c > 0.04045) {
        return std.math.pow(f32, (c + 0.055) / 1.055, 2.4);
    } else {
        return c / 12.92;
    }
}

pub fn xyz2rgb(in_out: *Triplet) void {
    const r = from_linear(dot_product(m[0], in_out.*));
    const g = from_linear(dot_product(m[1], in_out.*));
    const b = from_linear(dot_product(m[2], in_out.*));
    in_out.a = r;
    in_out.b = g;
    in_out.c = b;
}

pub fn rgb2xyz(in_out: *Triplet) void {
    const rgbl: Triplet = .{ .a = to_linear(in_out.a), .b = to_linear(in_out.b), .c = to_linear(in_out.c) };
    const x = dot_product(m_inv[0], rgbl);
    const y = dot_product(m_inv[1], rgbl);
    const z = dot_product(m_inv[2], rgbl);
    in_out.a = x;
    in_out.b = y;
    in_out.c = z;
}

// https://en.wikipedia.org/wiki/CIELUV
// In these formulas, Yn refers to the reference white point. We are using
// illuminant D65, so Yn (see refY in Maxima file) equals 1. The formula is
// simplified accordingly.

fn y2l(y: f32) f32 {
    if (y <= epsilon) {
        return y * kappa;
    } else {
        return 116.0 * std.math.cbrt(y) - 16.0;
    }
}

fn l2y(l: f32) f32 {
    if (l <= 8.0) {
        return l / kappa;
    } else {
        const x = (l + 16.0) / 116.0;
        return (x * x * x);
    }
}

pub fn xyz2luv(in_out: *Triplet) void {
    const var_u = (4.0 * in_out.a) / (in_out.a + (15.0 * in_out.b) + (3.0 * in_out.c));
    const var_v = (9.0 * in_out.b) / (in_out.a + (15.0 * in_out.b) + (3.0 * in_out.c));
    const l = y2l(in_out.b);
    const u = 13.0 * l * (var_u - ref_u);
    const v = 13.0 * l * (var_v - ref_v);

    in_out.a = l;
    if (l < 0.00001) {
        in_out.b = 0.0;
        in_out.c = 0.0;
    } else {
        in_out.b = u;
        in_out.c = v;
    }
}

pub fn luv2xyz(in_out: *Triplet) void {
    if (in_out.a <= 0.00001) {
        // Black will create a divide-by-zero error.
        in_out.a = 0.0;
        in_out.b = 0.0;
        in_out.c = 0.0;
        return;
    }

    const var_u = in_out.b / (13.0 * in_out.a) + ref_u;
    const var_v = in_out.c / (13.0 * in_out.a) + ref_v;
    const y = l2y(in_out.a);
    const x = -(9.0 * y * var_u) / ((var_u - 4.0) * var_v - var_u * var_v);
    const z = (9.0 * y - (15.0 * var_v * y) - (var_v * x)) / (3.0 * var_v);
    in_out.a = x;
    in_out.b = y;
    in_out.c = z;
}

pub fn luv2lch(in_out: *Triplet) void {
    const l = in_out.a;
    const u = in_out.b;
    const v = in_out.c;
    var h: f32 = undefined;
    const c = @sqrt(u * u + v * v);

    // Grays: disambiguate hue
    if (c < 0.0001) {
        h = 0;
    } else {
        h = std.math.atan2(v, u) * 57.29577951308232087680; // (180 / pi)
        if (h < 0.0)
            h += 360.0;
    }

    in_out.a = l;
    in_out.b = c;
    in_out.c = h;
}

pub fn lch2luv(in_out: *Triplet) void {
    const hrad = in_out.c * 0.01745329251994329577; // (pi / 180.0)
    const u = @cos(hrad) * in_out.b;
    const v = @sin(hrad) * in_out.b;

    in_out.b = u;
    in_out.c = v;
}

pub fn hsluv2lch(in_out: *Triplet) void {
    var h: f32 = in_out.a;
    const s = in_out.b;
    const l = in_out.c;
    var c: f32 = undefined;

    // White and black: disambiguate chroma
    if (l > 99.9999 or l < 0.00001) {
        c = 0.0;
    } else {
        c = max_chroma_for_lh(l, h) / 100.0 * s;
    }

    // Grays: disambiguate hue
    if (s < 0.00001)
        h = 0.0;

    in_out.a = l;
    in_out.b = c;
    in_out.c = h;
}

pub fn lch2hsluv(in_out: *Triplet) void {
    const l = in_out.a;
    const c = in_out.b;
    var h: f32 = in_out.c;
    var s: f32 = undefined;

    // White and black: disambiguate saturation
    if (l > 99.9999 or l < 0.00001) {
        s = 0.0;
    } else {
        s = c / max_chroma_for_lh(l, h) * 100.0;
    }

    // Grays: disambiguate hue
    if (c < 0.00001) {
        h = 0.0;
    }

    in_out.a = h;
    in_out.b = s;
    in_out.c = l;
}

pub fn hpluv2lch(in_out: *Triplet) void {
    var h: f32 = in_out.a;
    const s = in_out.b;
    const l = in_out.c;
    var c: f32 = undefined;

    // White and black: disambiguate chroma
    if (l > 99.9999 or l < 0.00001) {
        c = 0.0;
    } else {
        c = max_safe_chroma_for_l(l) / 100.0 * s;
    }

    // Grays: disambiguate hue
    if (s < 0.00001)
        h = 0.0;

    in_out.a = l;
    in_out.b = c;
    in_out.c = h;
}

pub fn lch2hpluv(in_out: *Triplet) void {
    const l = in_out.a;
    const c = in_out.b;
    var h: f32 = in_out.c;
    var s: f32 = undefined;

    // White and black: disambiguate saturation
    if (l > 99.9999 or l < 0.00001) {
        s = 0.0;
    } else {
        s = c / max_safe_chroma_for_l(l) * 100.0;
    }

    // Grays: disambiguate hue
    if (c < 0.00001)
        h = 0.0;

    in_out.a = h;
    in_out.b = s;
    in_out.c = l;
}

pub fn hsluv2rgb(h: f32, s: f32, l: f32, pr: *f32, pg: *f32, pb: *f32) void {
    var tmp = Triplet{ .a = h, .b = s, .c = l };

    hsluv2lch(&tmp);
    lch2luv(&tmp);
    luv2xyz(&tmp);
    xyz2rgb(&tmp);

    pr.* = std.math.clamp(tmp.a, 0.0, 1.0);
    pg.* = std.math.clamp(tmp.b, 0.0, 1.0);
    pb.* = std.math.clamp(tmp.c, 0.0, 1.0);
}

pub fn hpluv2rgb(h: f32, s: f32, l: f32, pr: *f32, pg: *f32, pb: *f32) void {
    var tmp = Triplet{ .a = h, .b = s, .c = l };

    hpluv2lch(&tmp);
    lch2luv(&tmp);
    luv2xyz(&tmp);
    xyz2rgb(&tmp);

    pr.* = std.math.clamp(tmp.a, 0.0, 1.0);
    pg.* = std.math.clamp(tmp.b, 0.0, 1.0);
    pb.* = std.math.clamp(tmp.c, 0.0, 1.0);
}

pub fn rgb2hsluv(r: f32, g: f32, b: f32, ph: *f32, ps: *f32, pl: *f32) void {
    var tmp = Triplet{ .a = r, .b = g, .c = b };

    rgb2xyz(&tmp);
    xyz2luv(&tmp);
    luv2lch(&tmp);
    lch2hsluv(&tmp);

    ph.* = std.math.clamp(tmp.a, 0.0, 360.0);
    ps.* = std.math.clamp(tmp.b, 0.0, 100.0);
    pl.* = std.math.clamp(tmp.c, 0.0, 100.0);
}

pub fn rgb2hpluv(r: f32, g: f32, b: f32, ph: *f32, ps: *f32, pl: *f32) bool {
    var tmp = Triplet{ .a = r, .b = g, .c = b };

    rgb2xyz(&tmp);
    xyz2luv(&tmp);
    luv2lch(&tmp);
    lch2hpluv(&tmp);

    ph.* = std.math.clamp(tmp.a, 0.0, 360.0);
    // Do NOT clamp the saturation. Application may want to have an idea
    // how much off the valid range the given RGB color is.
    ps.* = tmp.b;
    pl.* = std.math.clamp(tmp.c, 0.0, 100.0);

    return if (0.0 <= tmp.b and tmp.b <= 100.0) true else false;
}

test {
    @import("std").testing.refAllDecls(@This());
}
