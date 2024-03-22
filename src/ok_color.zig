const std = @import("std");
const sqrt = std.zig.c_builtins.__builtin_sqrtf;
const sin = std.zig.c_builtins.__builtin_sinf;
const cos = std.zig.c_builtins.__builtin_cosf;
fn atan2(a: f32, b: f32) f32 {
    return std.math.atan2(f32, a, b);
}
fn pow(a: f32, b: f32) f32 {
    return std.math.pow(f32, a, b);
}
fn cbrt(a: f32) f32 {
    return std.math.cbrt(a);
}
const pi = std.math.pi;

pub const RGB = struct {
    r: f32,
    g: f32,
    b: f32,
};
pub const HSV = struct {
    h: f32,
    s: f32,
    v: f32,
};
pub const HSL = struct {
    h: f32,
    s: f32,
    l: f32,
};
pub const Lab = struct {
    L: f32,
    a: f32,
    b: f32,
};
pub const Cs = struct {
    C_0: f32,
    C_mid: f32,
    C_max: f32,
};
pub fn srgb_to_okhsl(arg_rgb: RGB) HSL {
    var rgb = arg_rgb;
    var lab: Lab = linear_srgb_to_oklab(RGB{
        .r = srgb_transfer_function_inv(rgb.r),
        .g = srgb_transfer_function_inv(rgb.g),
        .b = srgb_transfer_function_inv(rgb.b),
    });
    var C: f32 = sqrt((lab.a * lab.a) + (lab.b * lab.b));
    var a_: f32 = lab.a / C;
    var b_: f32 = lab.b / C;
    var L: f32 = lab.L;
    var h: f32 = 0.5 + ((0.5 * atan2(-lab.b, -lab.a)) / pi);
    var cs: Cs = get_Cs(L, a_, b_);
    var C_0: f32 = cs.C_0;
    var C_mid: f32 = cs.C_mid;
    var C_max: f32 = cs.C_max;
    var mid: f32 = 0.800000011920929;
    var mid_inv: f32 = 1.25;
    var s: f32 = undefined;
    if (C < C_mid) {
        var k_1: f32 = mid * C_0;
        var k_2: f32 = 1.0 - (k_1 / C_mid);
        var t: f32 = C / (k_1 + (k_2 * C));
        s = t * mid;
    } else {
        var k_0: f32 = C_mid;
        var k_1: f32 = (((((1.0 - mid) * C_mid) * C_mid) * mid_inv) * mid_inv) / C_0;
        var k_2: f32 = 1.0 - (k_1 / (C_max - C_mid));
        var t: f32 = (C - k_0) / (k_1 + (k_2 * (C - k_0)));
        s = mid + ((1.0 - mid) * t);
    }
    var l: f32 = toe(L);
    return HSL{
        .h = h,
        .s = s,
        .l = l,
    };
}
pub fn okhsl_to_srgb(arg_hsl: HSL) RGB {
    var hsl = arg_hsl;
    var h: f32 = hsl.h;
    var s: f32 = hsl.s;
    var l: f32 = hsl.l;
    if (l == 1.0) {
        return RGB{
            .r = 1.0,
            .g = 1.0,
            .b = 1.0,
        };
    } else if (l == 0.0) {
        return RGB{
            .r = 0.0,
            .g = 0.0,
            .b = 0.0,
        };
    }
    var a_: f32 = cos((2.0 * pi) * h);
    var b_: f32 = sin((2.0 * pi) * h);
    var L: f32 = toe_inv(l);
    var cs: Cs = get_Cs(L, a_, b_);
    var C_0: f32 = cs.C_0;
    var C_mid: f32 = cs.C_mid;
    var C_max: f32 = cs.C_max;
    var mid: f32 = 0.800000011920929;
    var mid_inv: f32 = 1.25;
    var C: f32 = undefined;
    var t: f32 = undefined;
    var k_0: f32 = undefined;
    var k_1: f32 = undefined;
    var k_2: f32 = undefined;
    if (s < mid) {
        t = mid_inv * s;
        k_1 = mid * C_0;
        k_2 = 1.0 - (k_1 / C_mid);
        C = (t * k_1) / (1.0 - (k_2 * t));
    } else {
        t = (s - mid) / (@as(f32, @floatFromInt(@as(c_int, 1))) - mid);
        k_0 = C_mid;
        k_1 = (((((1.0 - mid) * C_mid) * C_mid) * mid_inv) * mid_inv) / C_0;
        k_2 = 1.0 - (k_1 / (C_max - C_mid));
        C = k_0 + ((t * k_1) / (1.0 - (k_2 * t)));
    }
    var rgb: RGB = oklab_to_linear_srgb(Lab{
        .L = L,
        .a = C * a_,
        .b = C * b_,
    });
    return RGB{
        .r = srgb_transfer_function(rgb.r),
        .g = srgb_transfer_function(rgb.g),
        .b = srgb_transfer_function(rgb.b),
    };
}
pub const struct_LC = struct {
    L: f32,
    C: f32,
};
pub const LC = struct_LC;
pub const struct_ST = struct {
    S: f32,
    T: f32,
};
pub const ST = struct_ST;
pub fn srgb_to_okhsv(arg_rgb: RGB) HSV {
    var rgb = arg_rgb;
    var lab: Lab = linear_srgb_to_oklab(RGB{
        .r = srgb_transfer_function_inv(rgb.r),
        .g = srgb_transfer_function_inv(rgb.g),
        .b = srgb_transfer_function_inv(rgb.b),
    });
    var C: f32 = sqrt((lab.a * lab.a) + (lab.b * lab.b));
    var a_: f32 = lab.a / C;
    var b_: f32 = lab.b / C;
    var L: f32 = lab.L;
    var h: f32 = 0.5 + ((0.5 * atan2(-lab.b, -lab.a)) / pi);
    var cusp: LC = find_cusp(a_, b_);
    var ST_max: ST = to_ST(cusp);
    var S_max: f32 = ST_max.S;
    var T_max: f32 = ST_max.T;
    var S_0: f32 = 0.5;
    var k: f32 = @as(f32, @floatFromInt(@as(c_int, 1))) - (S_0 / S_max);
    var t: f32 = T_max / (C + (L * T_max));
    var L_v: f32 = t * L;
    var C_v: f32 = t * C;
    var L_vt: f32 = toe_inv(L_v);
    var C_vt: f32 = (C_v * L_vt) / L_v;
    var rgb_scale: RGB = oklab_to_linear_srgb(Lab{
        .L = L_vt,
        .a = a_ * C_vt,
        .b = b_ * C_vt,
    });
    var scale_L: f32 = cbrt(@as(f32, @floatCast(@as(f64, @floatCast(1.0)) / @max(@max(@as(f64, @floatCast(rgb_scale.r)), @as(f64, @floatCast(rgb_scale.g))), @max(@as(f64, @floatCast(rgb_scale.b)), @as(f64, @floatCast(0.0)))))));
    L = L / scale_L;
    C = C / scale_L;
    C = (C * toe(L)) / L;
    L = toe(L);
    var v: f32 = L / L_v;
    var s: f32 = ((S_0 + T_max) * C_v) / ((T_max * S_0) + ((T_max * k) * C_v));
    return HSV{
        .h = h,
        .s = s,
        .v = v,
    };
}
pub fn okhsv_to_srgb(arg_hsv: HSV) RGB {
    var hsv = arg_hsv;
    var h: f32 = hsv.h;
    var s: f32 = hsv.s;
    var v: f32 = hsv.v;
    var a_: f32 = cos((2.0 * pi) * h);
    var b_: f32 = sin((2.0 * pi) * h);
    var cusp: LC = find_cusp(a_, b_);
    var ST_max: ST = to_ST(cusp);
    var S_max: f32 = ST_max.S;
    var T_max: f32 = ST_max.T;
    var S_0: f32 = 0.5;
    var k: f32 = @as(f32, @floatFromInt(@as(c_int, 1))) - (S_0 / S_max);
    var L_v: f32 = @as(f32, @floatFromInt(@as(c_int, 1))) - ((s * S_0) / ((S_0 + T_max) - ((T_max * k) * s)));
    var C_v: f32 = ((s * T_max) * S_0) / ((S_0 + T_max) - ((T_max * k) * s));
    var L: f32 = v * L_v;
    var C: f32 = v * C_v;
    var L_vt: f32 = toe_inv(L_v);
    var C_vt: f32 = (C_v * L_vt) / L_v;
    var L_new: f32 = toe_inv(L);
    C = (C * L_new) / L;
    L = L_new;
    var rgb_scale: RGB = oklab_to_linear_srgb(Lab{
        .L = L_vt,
        .a = a_ * C_vt,
        .b = b_ * C_vt,
    });
    var scale_L: f32 = cbrt(@as(f32, @floatCast(@as(f64, @floatCast(1.0)) / @max(@max(@as(f64, @floatCast(rgb_scale.r)), @as(f64, @floatCast(rgb_scale.g))), @max(@as(f64, @floatCast(rgb_scale.b)), @as(f64, @floatCast(0.0)))))));
    L = L * scale_L;
    C = C * scale_L;
    var rgb: RGB = oklab_to_linear_srgb(Lab{
        .L = L,
        .a = C * a_,
        .b = C * b_,
    });
    return RGB{
        .r = srgb_transfer_function(rgb.r),
        .g = srgb_transfer_function(rgb.g),
        .b = srgb_transfer_function(rgb.b),
    };
}
pub fn clamp(arg_x: f32, arg_min: f32, arg_max: f32) f32 {
    var x = arg_x;
    var min = arg_min;
    var max = arg_max;
    if (x < min) return min;
    if (x > max) return max;
    return x;
}
pub fn sgn(arg_x: f32) f32 {
    var x = arg_x;
    return @as(f32, @floatFromInt(0.0 < x)) - @as(f32, @floatFromInt(x < 0.0));
}
pub fn srgb_transfer_function(arg_a: f32) f32 {
    var a = arg_a;
    return if (0.0031308000907301903 >= a) 12.920000076293945 * a else (1.0549999475479126 * pow(a, 0.4166666567325592)) - 0.054999999701976776;
}
pub fn srgb_transfer_function_inv(arg_a: f32) f32 {
    var a = arg_a;
    return if (0.040449999272823334 < a) pow((a + 0.054999999701976776) / 1.0549999475479126, 2.4000000953674316) else a / 12.920000076293945;
}
pub fn linear_srgb_to_oklab(arg_c: RGB) Lab {
    var c = arg_c;
    var l: f32 = ((0.4122214615345001 * c.r) + (0.5363325476646423 * c.g)) + (0.05144599452614784 * c.b);
    var m: f32 = ((0.21190349757671356 * c.r) + (0.6806995272636414 * c.g)) + (0.10739696025848389 * c.b);
    var s: f32 = ((0.08830246329307556 * c.r) + (0.2817188501358032 * c.g)) + (0.6299787163734436 * c.b);
    var l_: f32 = cbrt(l);
    var m_: f32 = cbrt(m);
    var s_: f32 = cbrt(s);
    return Lab{
        .L = ((0.21045425534248352 * l_) + (0.7936177849769592 * m_)) - (0.004072046838700771 * s_),
        .a = ((1.9779984951019287 * l_) - (2.4285922050476074 * m_)) + (0.4505937099456787 * s_),
        .b = ((0.025904037058353424 * l_) + (0.7827717661857605 * m_)) - (0.8086757659912109 * s_),
    };
}
pub fn oklab_to_linear_srgb(arg_c: Lab) RGB {
    var c = arg_c;
    var l_: f32 = (c.L + (0.3963377773761749 * c.a)) + (0.21580375730991364 * c.b);
    var m_: f32 = (c.L - (0.10556134581565857 * c.a)) - (0.0638541728258133 * c.b);
    var s_: f32 = (c.L - (0.08948417752981186 * c.a)) - (1.2914855480194092 * c.b);
    var l: f32 = (l_ * l_) * l_;
    var m: f32 = (m_ * m_) * m_;
    var s: f32 = (s_ * s_) * s_;
    return RGB{
        .r = ((4.076741695404053 * l) - (3.307711601257324 * m)) + (0.23096993565559387 * s),
        .g = ((-1.2684379816055298 * l) + (2.609757423400879 * m)) - (0.34131938219070435 * s),
        .b = ((-0.004196086432784796 * l) - (0.7034186124801636 * m)) + (1.7076146602630615 * s),
    };
}
pub fn compute_max_saturation(arg_a: f32, arg_b: f32) f32 {
    var a = arg_a;
    var b = arg_b;
    var k0: f32 = undefined;
    var k1: f32 = undefined;
    var k2: f32 = undefined;
    var k3: f32 = undefined;
    var k4: f32 = undefined;
    var wl: f32 = undefined;
    var wm: f32 = undefined;
    var ws: f32 = undefined;
    if (((-1.88170325756073 * a) - (0.809364914894104 * b)) > @as(f32, @floatFromInt(@as(c_int, 1)))) {
        k0 = 1.190862774848938;
        k1 = 1.7657673358917236;
        k2 = 0.5966264009475708;
        k3 = 0.7551519870758057;
        k4 = 0.5677124261856079;
        wl = 4.076741695404053;
        wm = -3.307711601257324;
        ws = 0.23096993565559387;
    } else if (((1.8144410848617554 * a) - (1.1944527626037598 * b)) > @as(f32, @floatFromInt(@as(c_int, 1)))) {
        k0 = 0.7395651340484619;
        k1 = -0.45954403281211853;
        k2 = 0.0828542709350586;
        k3 = 0.12541070580482483;
        k4 = 0.14503203332424164;
        wl = -1.2684379816055298;
        wm = 2.609757423400879;
        ws = -0.34131938219070435;
    } else {
        k0 = 1.3573365211486816;
        k1 = -0.009157990105450153;
        k2 = -1.1513020992279053;
        k3 = -0.5055960416793823;
        k4 = 0.006921669933944941;
        wl = -0.004196086432784796;
        wm = -0.7034186124801636;
        ws = 1.7076146602630615;
    }
    var S: f32 = (((k0 + (k1 * a)) + (k2 * b)) + ((k3 * a) * a)) + ((k4 * a) * b);
    var k_l: f32 = (0.3963377773761749 * a) + (0.21580375730991364 * b);
    var k_m: f32 = (-0.10556134581565857 * a) - (0.0638541728258133 * b);
    var k_s: f32 = (-0.08948417752981186 * a) - (1.2914855480194092 * b);
    {
        var l_: f32 = 1.0 + (S * k_l);
        var m_: f32 = 1.0 + (S * k_m);
        var s_: f32 = 1.0 + (S * k_s);
        var l: f32 = (l_ * l_) * l_;
        var m: f32 = (m_ * m_) * m_;
        var s: f32 = (s_ * s_) * s_;
        var l_dS: f32 = ((3.0 * k_l) * l_) * l_;
        var m_dS: f32 = ((3.0 * k_m) * m_) * m_;
        var s_dS: f32 = ((3.0 * k_s) * s_) * s_;
        var l_dS2: f32 = ((6.0 * k_l) * k_l) * l_;
        var m_dS2: f32 = ((6.0 * k_m) * k_m) * m_;
        var s_dS2: f32 = ((6.0 * k_s) * k_s) * s_;
        var f: f32 = ((wl * l) + (wm * m)) + (ws * s);
        var f1: f32 = ((wl * l_dS) + (wm * m_dS)) + (ws * s_dS);
        var f2: f32 = ((wl * l_dS2) + (wm * m_dS2)) + (ws * s_dS2);
        S = S - ((f * f1) / ((f1 * f1) - ((0.5 * f) * f2)));
    }
    return S;
}
pub fn find_cusp(arg_a: f32, arg_b: f32) LC {
    var a = arg_a;
    var b = arg_b;
    var S_cusp: f32 = compute_max_saturation(a, b);
    var rgb_at_max: RGB = oklab_to_linear_srgb(Lab{
        .L = @as(f32, @floatFromInt(@as(c_int, 1))),
        .a = S_cusp * a,
        .b = S_cusp * b,
    });
    var L_cusp: f32 = cbrt(@as(f32, @floatCast(@as(f64, @floatCast(1.0)) / @max(@max(@as(f64, @floatCast(rgb_at_max.r)), @as(f64, @floatCast(rgb_at_max.g))), @as(f64, @floatCast(rgb_at_max.b))))));
    var C_cusp: f32 = L_cusp * S_cusp;
    return LC{
        .L = L_cusp,
        .C = C_cusp,
    };
}
pub fn find_gamut_intersection_6(arg_a: f32, arg_b: f32, arg_L1: f32, arg_C1: f32, arg_L0: f32, arg_cusp: LC) f32 {
    var a = arg_a;
    var b = arg_b;
    var L1 = arg_L1;
    var C1 = arg_C1;
    var L0 = arg_L0;
    var cusp = arg_cusp;
    var t: f32 = undefined;
    if ((((L1 - L0) * cusp.C) - ((cusp.L - L0) * C1)) <= 0.0) {
        t = (cusp.C * L0) / ((C1 * cusp.L) + (cusp.C * (L0 - L1)));
    } else {
        t = (cusp.C * (L0 - 1.0)) / ((C1 * (cusp.L - 1.0)) + (cusp.C * (L0 - L1)));
        {
            var dL: f32 = L1 - L0;
            var dC: f32 = C1;
            var k_l: f32 = (0.3963377773761749 * a) + (0.21580375730991364 * b);
            var k_m: f32 = (-0.10556134581565857 * a) - (0.0638541728258133 * b);
            var k_s: f32 = (-0.08948417752981186 * a) - (1.2914855480194092 * b);
            var l_dt: f32 = dL + (dC * k_l);
            var m_dt: f32 = dL + (dC * k_m);
            var s_dt: f32 = dL + (dC * k_s);
            {
                var L: f32 = (L0 * (1.0 - t)) + (t * L1);
                var C: f32 = t * C1;
                var l_: f32 = L + (C * k_l);
                var m_: f32 = L + (C * k_m);
                var s_: f32 = L + (C * k_s);
                var l: f32 = (l_ * l_) * l_;
                var m: f32 = (m_ * m_) * m_;
                var s: f32 = (s_ * s_) * s_;
                var ldt: f32 = ((@as(f32, @floatFromInt(@as(c_int, 3))) * l_dt) * l_) * l_;
                var mdt: f32 = ((@as(f32, @floatFromInt(@as(c_int, 3))) * m_dt) * m_) * m_;
                var sdt: f32 = ((@as(f32, @floatFromInt(@as(c_int, 3))) * s_dt) * s_) * s_;
                var ldt2: f32 = ((@as(f32, @floatFromInt(@as(c_int, 6))) * l_dt) * l_dt) * l_;
                var mdt2: f32 = ((@as(f32, @floatFromInt(@as(c_int, 6))) * m_dt) * m_dt) * m_;
                var sdt2: f32 = ((@as(f32, @floatFromInt(@as(c_int, 6))) * s_dt) * s_dt) * s_;
                var r: f32 = (((4.076741695404053 * l) - (3.307711601257324 * m)) + (0.23096993565559387 * s)) - @as(f32, @floatFromInt(@as(c_int, 1)));
                var r1: f32 = ((4.076741695404053 * ldt) - (3.307711601257324 * mdt)) + (0.23096993565559387 * sdt);
                var r2: f32 = ((4.076741695404053 * ldt2) - (3.307711601257324 * mdt2)) + (0.23096993565559387 * sdt2);
                var u_r: f32 = r1 / ((r1 * r1) - ((0.5 * r) * r2));
                var t_r: f32 = -r * u_r;
                var g: f32 = (((-1.2684379816055298 * l) + (2.609757423400879 * m)) - (0.34131938219070435 * s)) - @as(f32, @floatFromInt(@as(c_int, 1)));
                var g1: f32 = ((-1.2684379816055298 * ldt) + (2.609757423400879 * mdt)) - (0.34131938219070435 * sdt);
                var g2: f32 = ((-1.2684379816055298 * ldt2) + (2.609757423400879 * mdt2)) - (0.34131938219070435 * sdt2);
                var u_g: f32 = g1 / ((g1 * g1) - ((0.5 * g) * g2));
                var t_g: f32 = -g * u_g;
                var b_1: f32 = (((-0.004196086432784796 * l) - (0.7034186124801636 * m)) + (1.7076146602630615 * s)) - @as(f32, @floatFromInt(@as(c_int, 1)));
                var b1: f32 = ((-0.004196086432784796 * ldt) - (0.7034186124801636 * mdt)) + (1.7076146602630615 * sdt);
                var b2: f32 = ((-0.004196086432784796 * ldt2) - (0.7034186124801636 * mdt2)) + (1.7076146602630615 * sdt2);
                var u_b: f32 = b1 / ((b1 * b1) - ((0.5 * b_1) * b2));
                var t_b: f32 = -b_1 * u_b;
                t_r = if (u_r >= 0.0) t_r else 340282346638528860000000000000000000000.0;
                t_g = if (u_g >= 0.0) t_g else 340282346638528860000000000000000000000.0;
                t_b = if (u_b >= 0.0) t_b else 340282346638528860000000000000000000000.0;
                t += @min(@as(f32, @floatCast(t_r)), @min(@as(f32, @floatCast(t_g)), @as(f32, @floatCast(t_b))));
            }
        }
    }
    return t;
}
pub fn find_gamut_intersection(arg_a: f32, arg_b: f32, arg_L1: f32, arg_C1: f32, arg_L0: f32) f32 {
    var a = arg_a;
    var b = arg_b;
    var L1 = arg_L1;
    var C1 = arg_C1;
    var L0 = arg_L0;
    var cusp: LC = find_cusp(a, b);
    return find_gamut_intersection_6(a, b, L1, C1, L0, cusp);
}
pub fn gamut_clip_preserve_chroma(arg_rgb: RGB) RGB {
    var rgb = arg_rgb;
    if ((((((rgb.r < @as(f32, @floatFromInt(@as(c_int, 1)))) and (rgb.g < @as(f32, @floatFromInt(@as(c_int, 1))))) and (rgb.b < @as(f32, @floatFromInt(@as(c_int, 1))))) and (rgb.r > @as(f32, @floatFromInt(@as(c_int, 0))))) and (rgb.g > @as(f32, @floatFromInt(@as(c_int, 0))))) and (rgb.b > @as(f32, @floatFromInt(@as(c_int, 0))))) return rgb;
    var lab: Lab = linear_srgb_to_oklab(rgb);
    var L: f32 = lab.L;
    var eps: f32 = 0.000009999999747378752;
    var C: f32 = @as(f32, @floatCast(@max(@as(f64, @floatCast(eps)), @as(f64, @floatCast(sqrt((lab.a * lab.a) + (lab.b * lab.b)))))));
    var a_: f32 = lab.a / C;
    var b_: f32 = lab.b / C;
    var L0: f32 = clamp(L, @as(f32, @floatFromInt(@as(c_int, 0))), @as(f32, @floatFromInt(@as(c_int, 1))));
    var t: f32 = find_gamut_intersection(a_, b_, L, C, L0);
    var L_clipped: f32 = (L0 * (@as(f32, @floatFromInt(@as(c_int, 1))) - t)) + (t * L);
    var C_clipped: f32 = t * C;
    return oklab_to_linear_srgb(Lab{
        .L = L_clipped,
        .a = C_clipped * a_,
        .b = C_clipped * b_,
    });
}
pub fn gamut_clip_project_to_0_5(arg_rgb: RGB) RGB {
    var rgb = arg_rgb;
    if ((((((rgb.r < @as(f32, @floatFromInt(@as(c_int, 1)))) and (rgb.g < @as(f32, @floatFromInt(@as(c_int, 1))))) and (rgb.b < @as(f32, @floatFromInt(@as(c_int, 1))))) and (rgb.r > @as(f32, @floatFromInt(@as(c_int, 0))))) and (rgb.g > @as(f32, @floatFromInt(@as(c_int, 0))))) and (rgb.b > @as(f32, @floatFromInt(@as(c_int, 0))))) return rgb;
    var lab: Lab = linear_srgb_to_oklab(rgb);
    var L: f32 = lab.L;
    var eps: f32 = 0.000009999999747378752;
    var C: f32 = @as(f32, @floatCast(@max(@as(f64, @floatCast(eps)), @as(f64, @floatCast(sqrt((lab.a * lab.a) + (lab.b * lab.b)))))));
    var a_: f32 = lab.a / C;
    var b_: f32 = lab.b / C;
    var L0: f32 = @as(f32, @floatCast(0.5));
    var t: f32 = find_gamut_intersection(a_, b_, L, C, L0);
    var L_clipped: f32 = (L0 * (@as(f32, @floatFromInt(@as(c_int, 1))) - t)) + (t * L);
    var C_clipped: f32 = t * C;
    return oklab_to_linear_srgb(Lab{
        .L = L_clipped,
        .a = C_clipped * a_,
        .b = C_clipped * b_,
    });
}
pub fn gamut_clip_project_to_L_cusp(arg_rgb: RGB) RGB {
    var rgb = arg_rgb;
    if ((((((rgb.r < @as(f32, @floatFromInt(@as(c_int, 1)))) and (rgb.g < @as(f32, @floatFromInt(@as(c_int, 1))))) and (rgb.b < @as(f32, @floatFromInt(@as(c_int, 1))))) and (rgb.r > @as(f32, @floatFromInt(@as(c_int, 0))))) and (rgb.g > @as(f32, @floatFromInt(@as(c_int, 0))))) and (rgb.b > @as(f32, @floatFromInt(@as(c_int, 0))))) return rgb;
    var lab: Lab = linear_srgb_to_oklab(rgb);
    var L: f32 = lab.L;
    var eps: f32 = 0.000009999999747378752;
    var C: f32 = @as(f32, @floatCast(@max(@as(f64, @floatCast(eps)), @as(f64, @floatCast(sqrt((lab.a * lab.a) + (lab.b * lab.b)))))));
    var a_: f32 = lab.a / C;
    var b_: f32 = lab.b / C;
    var cusp: LC = find_cusp(a_, b_);
    var L0: f32 = cusp.L;
    var t: f32 = find_gamut_intersection(a_, b_, L, C, L0);
    var L_clipped: f32 = (L0 * (@as(f32, @floatFromInt(@as(c_int, 1))) - t)) + (t * L);
    var C_clipped: f32 = t * C;
    return oklab_to_linear_srgb(Lab{
        .L = L_clipped,
        .a = C_clipped * a_,
        .b = C_clipped * b_,
    });
}
pub fn toe(arg_x: f32) f32 {
    var x = arg_x;
    const k_1: f32 = 0.20600000023841858;
    const k_2: f32 = 0.029999999329447746;
    const k_3: f32 = (1.0 + k_1) / (1.0 + k_2);
    return 0.5 * (((k_3 * x) - k_1) + sqrt((((k_3 * x) - k_1) * ((k_3 * x) - k_1)) + (((@as(f32, @floatFromInt(@as(c_int, 4))) * k_2) * k_3) * x)));
}
pub fn toe_inv(arg_x: f32) f32 {
    var x = arg_x;
    const k_1: f32 = 0.20600000023841858;
    const k_2: f32 = 0.029999999329447746;
    const k_3: f32 = (1.0 + k_1) / (1.0 + k_2);
    return ((x * x) + (k_1 * x)) / (k_3 * (x + k_2));
}
pub fn to_ST(arg_cusp: LC) ST {
    var cusp = arg_cusp;
    var L: f32 = cusp.L;
    var C: f32 = cusp.C;
    return ST{
        .S = C / L,
        .T = C / (@as(f32, @floatFromInt(@as(c_int, 1))) - L),
    };
}
pub fn get_ST_mid(arg_a_: f32, arg_b_: f32) ST {
    var a_ = arg_a_;
    var b_ = arg_b_;
    var S: f32 = 0.11516992747783661 + (1.0 / ((7.447789669036865 + (4.159012317657471 * b_)) + (a_ * ((-2.195573568344116 + (1.7519840002059937 * b_)) + (a_ * ((-2.137049436569214 - (10.02301025390625 * b_)) + (a_ * ((-4.248945713043213 + (5.3877081871032715 * b_)) + (4.698910236358643 * a_)))))))));
    var T: f32 = 0.11239641904830933 + (1.0 / ((1.6132031679153442 - (0.6812437772750854 * b_)) + (a_ * ((0.4037061333656311 + (0.9014812111854553 * b_)) + (a_ * ((-0.2708794176578522 + (0.6122398972511292 * b_)) + (a_ * ((0.0029921499080955982 - (0.4539956748485565 * b_)) - (0.14661872386932373 * a_)))))))));
    return ST{
        .S = S,
        .T = T,
    };
}
pub fn get_Cs(arg_L: f32, arg_a_: f32, arg_b_: f32) Cs {
    var L = arg_L;
    var a_ = arg_a_;
    var b_ = arg_b_;
    var cusp: LC = find_cusp(a_, b_);
    var C_max: f32 = find_gamut_intersection_6(a_, b_, L, @as(f32, @floatFromInt(@as(c_int, 1))), L, cusp);
    var ST_max: ST = to_ST(cusp);
    var k: f32 = @as(f32, @floatCast(@as(f64, @floatCast(C_max)) / @min(@as(f64, @floatCast(L * ST_max.S)), @as(f64, @floatCast((@as(f32, @floatFromInt(@as(c_int, 1))) - L) * ST_max.T)))));
    var C_mid: f32 = undefined;
    {
        var ST_mid: ST = get_ST_mid(a_, b_);
        var C_a: f32 = L * ST_mid.S;
        var C_b: f32 = (1.0 - L) * ST_mid.T;
        C_mid = (0.8999999761581421 * k) * sqrt(sqrt(1.0 / ((1.0 / (((C_a * C_a) * C_a) * C_a)) + (1.0 / (((C_b * C_b) * C_b) * C_b)))));
    }
    var C_0: f32 = undefined;
    {
        var C_a: f32 = L * 0.4000000059604645;
        var C_b: f32 = (1.0 - L) * 0.800000011920929;
        C_0 = sqrt(1.0 / ((1.0 / (C_a * C_a)) + (1.0 / (C_b * C_b))));
    }
    return Cs{
        .C_0 = C_0,
        .C_mid = C_mid,
        .C_max = C_max,
    };
}
