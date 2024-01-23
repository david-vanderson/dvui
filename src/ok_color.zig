const std = @import("std");
fn powf(l: f32, r: f32) f32 {
    return std.math.pow(f32, l, r);
}
fn cbrtf(x: f32) f32 {
    return std.math.cbrt(x);
}
fn sqrtf(x: f32) f32 {
    return @sqrt(x);
}
fn atan2f(y: f32, x: f32) f32 {
    return std.math.atan2(f32, y, x);
}

pub const __builtin_bswap16 = @import("std").zig.c_builtins.__builtin_bswap16;
pub const __builtin_bswap32 = @import("std").zig.c_builtins.__builtin_bswap32;
pub const __builtin_bswap64 = @import("std").zig.c_builtins.__builtin_bswap64;
pub const __builtin_signbit = @import("std").zig.c_builtins.__builtin_signbit;
pub const __builtin_signbitf = @import("std").zig.c_builtins.__builtin_signbitf;
pub const __builtin_popcount = @import("std").zig.c_builtins.__builtin_popcount;
pub const __builtin_ctz = @import("std").zig.c_builtins.__builtin_ctz;
pub const __builtin_clz = @import("std").zig.c_builtins.__builtin_clz;
pub const __builtin_sqrt = @import("std").zig.c_builtins.__builtin_sqrt;
pub const __builtin_sqrtf = @import("std").zig.c_builtins.__builtin_sqrtf;
pub const __builtin_sin = @import("std").zig.c_builtins.__builtin_sin;
pub const __builtin_sinf = @import("std").zig.c_builtins.__builtin_sinf;
pub const __builtin_cos = @import("std").zig.c_builtins.__builtin_cos;
pub const __builtin_cosf = @import("std").zig.c_builtins.__builtin_cosf;
pub const __builtin_exp = @import("std").zig.c_builtins.__builtin_exp;
pub const __builtin_expf = @import("std").zig.c_builtins.__builtin_expf;
pub const __builtin_exp2 = @import("std").zig.c_builtins.__builtin_exp2;
pub const __builtin_exp2f = @import("std").zig.c_builtins.__builtin_exp2f;
pub const __builtin_log = @import("std").zig.c_builtins.__builtin_log;
pub const __builtin_logf = @import("std").zig.c_builtins.__builtin_logf;
pub const __builtin_log2 = @import("std").zig.c_builtins.__builtin_log2;
pub const __builtin_log2f = @import("std").zig.c_builtins.__builtin_log2f;
pub const __builtin_log10 = @import("std").zig.c_builtins.__builtin_log10;
pub const __builtin_log10f = @import("std").zig.c_builtins.__builtin_log10f;
pub const __builtin_abs = @import("std").zig.c_builtins.__builtin_abs;
pub const __builtin_fabs = @import("std").zig.c_builtins.__builtin_fabs;
pub const __builtin_fabsf = @import("std").zig.c_builtins.__builtin_fabsf;
pub const __builtin_floor = @import("std").zig.c_builtins.__builtin_floor;
pub const __builtin_floorf = @import("std").zig.c_builtins.__builtin_floorf;
pub const __builtin_ceil = @import("std").zig.c_builtins.__builtin_ceil;
pub const __builtin_ceilf = @import("std").zig.c_builtins.__builtin_ceilf;
pub const __builtin_trunc = @import("std").zig.c_builtins.__builtin_trunc;
pub const __builtin_truncf = @import("std").zig.c_builtins.__builtin_truncf;
pub const __builtin_round = @import("std").zig.c_builtins.__builtin_round;
pub const __builtin_roundf = @import("std").zig.c_builtins.__builtin_roundf;
pub const __builtin_strlen = @import("std").zig.c_builtins.__builtin_strlen;
pub const __builtin_strcmp = @import("std").zig.c_builtins.__builtin_strcmp;
pub const __builtin_object_size = @import("std").zig.c_builtins.__builtin_object_size;
pub const __builtin___memset_chk = @import("std").zig.c_builtins.__builtin___memset_chk;
pub const __builtin_memset = @import("std").zig.c_builtins.__builtin_memset;
pub const __builtin___memcpy_chk = @import("std").zig.c_builtins.__builtin___memcpy_chk;
pub const __builtin_memcpy = @import("std").zig.c_builtins.__builtin_memcpy;
pub const __builtin_expect = @import("std").zig.c_builtins.__builtin_expect;
pub const __builtin_nanf = @import("std").zig.c_builtins.__builtin_nanf;
pub const __builtin_huge_valf = @import("std").zig.c_builtins.__builtin_huge_valf;
pub const __builtin_inff = @import("std").zig.c_builtins.__builtin_inff;
pub const __builtin_isnan = @import("std").zig.c_builtins.__builtin_isnan;
pub const __builtin_isinf = @import("std").zig.c_builtins.__builtin_isinf;
pub const __builtin_isinf_sign = @import("std").zig.c_builtins.__builtin_isinf_sign;
pub const __has_builtin = @import("std").zig.c_builtins.__has_builtin;
pub const __builtin_assume = @import("std").zig.c_builtins.__builtin_assume;
pub const __builtin_unreachable = @import("std").zig.c_builtins.__builtin_unreachable;
pub const __builtin_constant_p = @import("std").zig.c_builtins.__builtin_constant_p;
pub const __builtin_mul_overflow = @import("std").zig.c_builtins.__builtin_mul_overflow;
pub const struct_RGB = extern struct {
    r: f32,
    g: f32,
    b: f32,
};
pub const RGB = struct_RGB;
pub const struct_HSV = extern struct {
    h: f32,
    s: f32,
    v: f32,
};
pub const HSV = struct_HSV;
pub const struct_HSL = extern struct {
    h: f32,
    s: f32,
    l: f32,
};
pub const HSL = struct_HSL;
pub const struct_Lab = extern struct {
    L: f32,
    a: f32,
    b: f32,
};
pub const Lab = struct_Lab;
pub const struct_Cs = extern struct {
    C_0: f32,
    C_mid: f32,
    C_max: f32,
};
pub const Cs = struct_Cs;
pub fn srgb_to_okhsl(arg_rgb: RGB) HSL {
    var rgb = arg_rgb;
    var lab: Lab = linear_srgb_to_oklab(RGB{
        .r = srgb_transfer_function_inv(rgb.r),
        .g = srgb_transfer_function_inv(rgb.g),
        .b = srgb_transfer_function_inv(rgb.b),
    });
    var C: f32 = sqrtf((lab.a * lab.a) + (lab.b * lab.b));
    var a_: f32 = lab.a / C;
    var b_: f32 = lab.b / C;
    var L: f32 = lab.L;
    var h: f32 = 0.5 + ((0.5 * atan2f(-lab.b, -lab.a)) / pi);
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
    var a_: f32 = cosf((2.0 * pi) * h);
    var b_: f32 = sinf((2.0 * pi) * h);
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
pub const struct_LC = extern struct {
    L: f32,
    C: f32,
};
pub const LC = struct_LC;
pub const struct_ST = extern struct {
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
    var C: f32 = sqrtf((lab.a * lab.a) + (lab.b * lab.b));
    var a_: f32 = lab.a / C;
    var b_: f32 = lab.b / C;
    var L: f32 = lab.L;
    var h: f32 = 0.5 + ((0.5 * atan2f(-lab.b, -lab.a)) / pi);
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
    var scale_L: f32 = cbrtf(@as(f32, @floatCast(@as(f64, @floatCast(1.0)) / @max(@max(@as(f64, @floatCast(rgb_scale.r)), @as(f64, @floatCast(rgb_scale.g))), @max(@as(f64, @floatCast(rgb_scale.b)), @as(f64, @floatCast(0.0)))))));
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
    var a_: f32 = cosf((2.0 * pi) * h);
    var b_: f32 = sinf((2.0 * pi) * h);
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
    var scale_L: f32 = cbrtf(@as(f32, @floatCast(@as(f64, @floatCast(1.0)) / @max(@max(@as(f64, @floatCast(rgb_scale.r)), @as(f64, @floatCast(rgb_scale.g))), @max(@as(f64, @floatCast(rgb_scale.b)), @as(f64, @floatCast(0.0)))))));
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
pub const float_t = f32;
pub const double_t = f64;
pub extern fn __fpclassify(f64) c_int;
pub extern fn __fpclassifyf(f32) c_int;
pub extern fn __fpclassifyl(c_longdouble) c_int;
pub fn __FLOAT_BITS(arg___f: f32) callconv(.C) c_uint {
    var __f = arg___f;
    const union_unnamed_1 = extern union {
        __f: f32,
        __i: c_uint,
    };
    _ = @TypeOf(union_unnamed_1);
    var __u: union_unnamed_1 = undefined;
    __u.__f = __f;
    return __u.__i;
}
pub fn __DOUBLE_BITS(arg___f: f64) callconv(.C) c_ulonglong {
    var __f = arg___f;
    const union_unnamed_2 = extern union {
        __f: f64,
        __i: c_ulonglong,
    };
    _ = @TypeOf(union_unnamed_2);
    var __u: union_unnamed_2 = undefined;
    __u.__f = __f;
    return __u.__i;
}
pub extern fn __signbit(f64) c_int;
pub extern fn __signbitf(f32) c_int;
pub extern fn __signbitl(c_longdouble) c_int;
pub fn __islessf(arg___x: float_t, arg___y: float_t) callconv(.C) c_int {
    var __x = arg___x;
    var __y = arg___y;
    return @intFromBool(!((if ((if (@sizeOf(float_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(__x) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(float_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__x))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__x))) == @as(c_int, 0))) != 0) blk: {
        _ = @TypeOf(__y);
        break :blk @as(c_int, 1);
    } else if (@sizeOf(float_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(__y) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(float_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__y))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__y))) == @as(c_int, 0))) != 0) and (__x < __y));
}
pub fn __isless(arg___x: double_t, arg___y: double_t) callconv(.C) c_int {
    var __x = arg___x;
    var __y = arg___y;
    return @intFromBool(!((if ((if (@sizeOf(double_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__x))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(double_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(__x) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__x))) == @as(c_int, 0))) != 0) blk: {
        _ = @TypeOf(__y);
        break :blk @as(c_int, 1);
    } else if (@sizeOf(double_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__y))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(double_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(__y) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__y))) == @as(c_int, 0))) != 0) and (__x < __y));
}
pub fn __islessl(arg___x: c_longdouble, arg___y: c_longdouble) callconv(.C) c_int {
    var __x = arg___x;
    var __y = arg___y;
    return @intFromBool(!((if ((if (@sizeOf(c_longdouble) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__x))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(c_longdouble) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__x))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(__x) == @as(c_int, 0))) != 0) blk: {
        _ = @TypeOf(__y);
        break :blk @as(c_int, 1);
    } else if (@sizeOf(c_longdouble) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__y))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(c_longdouble) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__y))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(__y) == @as(c_int, 0))) != 0) and (__x < __y));
}
pub fn __islessequalf(arg___x: float_t, arg___y: float_t) callconv(.C) c_int {
    var __x = arg___x;
    var __y = arg___y;
    return @intFromBool(!((if ((if (@sizeOf(float_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(__x) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(float_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__x))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__x))) == @as(c_int, 0))) != 0) blk: {
        _ = @TypeOf(__y);
        break :blk @as(c_int, 1);
    } else if (@sizeOf(float_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(__y) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(float_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__y))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__y))) == @as(c_int, 0))) != 0) and (__x <= __y));
}
pub fn __islessequal(arg___x: double_t, arg___y: double_t) callconv(.C) c_int {
    var __x = arg___x;
    var __y = arg___y;
    return @intFromBool(!((if ((if (@sizeOf(double_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__x))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(double_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(__x) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__x))) == @as(c_int, 0))) != 0) blk: {
        _ = @TypeOf(__y);
        break :blk @as(c_int, 1);
    } else if (@sizeOf(double_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__y))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(double_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(__y) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__y))) == @as(c_int, 0))) != 0) and (__x <= __y));
}
pub fn __islessequall(arg___x: c_longdouble, arg___y: c_longdouble) callconv(.C) c_int {
    var __x = arg___x;
    var __y = arg___y;
    return @intFromBool(!((if ((if (@sizeOf(c_longdouble) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__x))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(c_longdouble) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__x))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(__x) == @as(c_int, 0))) != 0) blk: {
        _ = @TypeOf(__y);
        break :blk @as(c_int, 1);
    } else if (@sizeOf(c_longdouble) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__y))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(c_longdouble) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__y))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(__y) == @as(c_int, 0))) != 0) and (__x <= __y));
}
pub fn __islessgreaterf(arg___x: float_t, arg___y: float_t) callconv(.C) c_int {
    var __x = arg___x;
    var __y = arg___y;
    return @intFromBool(!((if ((if (@sizeOf(float_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(__x) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(float_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__x))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__x))) == @as(c_int, 0))) != 0) blk: {
        _ = @TypeOf(__y);
        break :blk @as(c_int, 1);
    } else if (@sizeOf(float_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(__y) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(float_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__y))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__y))) == @as(c_int, 0))) != 0) and (__x != __y));
}
pub fn __islessgreater(arg___x: double_t, arg___y: double_t) callconv(.C) c_int {
    var __x = arg___x;
    var __y = arg___y;
    return @intFromBool(!((if ((if (@sizeOf(double_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__x))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(double_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(__x) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__x))) == @as(c_int, 0))) != 0) blk: {
        _ = @TypeOf(__y);
        break :blk @as(c_int, 1);
    } else if (@sizeOf(double_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__y))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(double_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(__y) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__y))) == @as(c_int, 0))) != 0) and (__x != __y));
}
pub fn __islessgreaterl(arg___x: c_longdouble, arg___y: c_longdouble) callconv(.C) c_int {
    var __x = arg___x;
    var __y = arg___y;
    return @intFromBool(!((if ((if (@sizeOf(c_longdouble) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__x))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(c_longdouble) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__x))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(__x) == @as(c_int, 0))) != 0) blk: {
        _ = @TypeOf(__y);
        break :blk @as(c_int, 1);
    } else if (@sizeOf(c_longdouble) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__y))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(c_longdouble) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__y))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(__y) == @as(c_int, 0))) != 0) and (__x != __y));
}
pub fn __isgreaterf(arg___x: float_t, arg___y: float_t) callconv(.C) c_int {
    var __x = arg___x;
    var __y = arg___y;
    return @intFromBool(!((if ((if (@sizeOf(float_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(__x) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(float_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__x))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__x))) == @as(c_int, 0))) != 0) blk: {
        _ = @TypeOf(__y);
        break :blk @as(c_int, 1);
    } else if (@sizeOf(float_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(__y) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(float_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__y))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__y))) == @as(c_int, 0))) != 0) and (__x > __y));
}
pub fn __isgreater(arg___x: double_t, arg___y: double_t) callconv(.C) c_int {
    var __x = arg___x;
    var __y = arg___y;
    return @intFromBool(!((if ((if (@sizeOf(double_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__x))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(double_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(__x) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__x))) == @as(c_int, 0))) != 0) blk: {
        _ = @TypeOf(__y);
        break :blk @as(c_int, 1);
    } else if (@sizeOf(double_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__y))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(double_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(__y) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__y))) == @as(c_int, 0))) != 0) and (__x > __y));
}
pub fn __isgreaterl(arg___x: c_longdouble, arg___y: c_longdouble) callconv(.C) c_int {
    var __x = arg___x;
    var __y = arg___y;
    return @intFromBool(!((if ((if (@sizeOf(c_longdouble) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__x))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(c_longdouble) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__x))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(__x) == @as(c_int, 0))) != 0) blk: {
        _ = @TypeOf(__y);
        break :blk @as(c_int, 1);
    } else if (@sizeOf(c_longdouble) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__y))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(c_longdouble) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__y))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(__y) == @as(c_int, 0))) != 0) and (__x > __y));
}
pub fn __isgreaterequalf(arg___x: float_t, arg___y: float_t) callconv(.C) c_int {
    var __x = arg___x;
    var __y = arg___y;
    return @intFromBool(!((if ((if (@sizeOf(float_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(__x) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(float_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__x))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__x))) == @as(c_int, 0))) != 0) blk: {
        _ = @TypeOf(__y);
        break :blk @as(c_int, 1);
    } else if (@sizeOf(float_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(__y) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(float_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__y))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__y))) == @as(c_int, 0))) != 0) and (__x >= __y));
}
pub fn __isgreaterequal(arg___x: double_t, arg___y: double_t) callconv(.C) c_int {
    var __x = arg___x;
    var __y = arg___y;
    return @intFromBool(!((if ((if (@sizeOf(double_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__x))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(double_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(__x) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__x))) == @as(c_int, 0))) != 0) blk: {
        _ = @TypeOf(__y);
        break :blk @as(c_int, 1);
    } else if (@sizeOf(double_t) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__y))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(double_t) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(__y) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(@as(c_longdouble, @floatCast(__y))) == @as(c_int, 0))) != 0) and (__x >= __y));
}
pub fn __isgreaterequall(arg___x: c_longdouble, arg___y: c_longdouble) callconv(.C) c_int {
    var __x = arg___x;
    var __y = arg___y;
    return @intFromBool(!((if ((if (@sizeOf(c_longdouble) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__x))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(c_longdouble) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__x))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(__x) == @as(c_int, 0))) != 0) blk: {
        _ = @TypeOf(__y);
        break :blk @as(c_int, 1);
    } else if (@sizeOf(c_longdouble) == @sizeOf(f32)) @intFromBool((__FLOAT_BITS(@as(f32, @floatCast(__y))) & @as(c_uint, @bitCast(@as(c_int, 2147483647)))) > @as(c_uint, @bitCast(@as(c_int, 2139095040)))) else if (@sizeOf(c_longdouble) == @sizeOf(f64)) @intFromBool((__DOUBLE_BITS(@as(f64, @floatCast(__y))) & (-%@as(c_ulonglong, 1) >> @intCast(1))) > (@as(c_ulonglong, 2047) << @intCast(52))) else @intFromBool(__fpclassifyl(__y) == @as(c_int, 0))) != 0) and (__x >= __y));
}
pub extern fn acos(f64) f64;
pub extern fn acosf(f32) f32;
pub extern fn acosl(c_longdouble) c_longdouble;
pub extern fn acosh(f64) f64;
pub extern fn acoshf(f32) f32;
pub extern fn acoshl(c_longdouble) c_longdouble;
pub extern fn asin(f64) f64;
pub extern fn asinf(f32) f32;
pub extern fn asinl(c_longdouble) c_longdouble;
pub extern fn asinh(f64) f64;
pub extern fn asinhf(f32) f32;
pub extern fn asinhl(c_longdouble) c_longdouble;
pub extern fn atan(f64) f64;
pub extern fn atanf(f32) f32;
pub extern fn atanl(c_longdouble) c_longdouble;
pub extern fn atan2(f64, f64) f64;
pub extern fn atan2l(c_longdouble, c_longdouble) c_longdouble;
pub extern fn atanh(f64) f64;
pub extern fn atanhf(f32) f32;
pub extern fn atanhl(c_longdouble) c_longdouble;
pub extern fn cbrt(f64) f64;
pub extern fn cbrtl(c_longdouble) c_longdouble;
pub extern fn ceil(f64) f64;
pub extern fn ceilf(f32) f32;
pub extern fn ceill(c_longdouble) c_longdouble;
pub extern fn copysign(f64, f64) f64;
pub extern fn copysignf(f32, f32) f32;
pub extern fn copysignl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn cos(f64) f64;
pub extern fn cosf(f32) f32;
pub extern fn cosl(c_longdouble) c_longdouble;
pub extern fn cosh(f64) f64;
pub extern fn coshf(f32) f32;
pub extern fn coshl(c_longdouble) c_longdouble;
pub extern fn erf(f64) f64;
pub extern fn erff(f32) f32;
pub extern fn erfl(c_longdouble) c_longdouble;
pub extern fn erfc(f64) f64;
pub extern fn erfcf(f32) f32;
pub extern fn erfcl(c_longdouble) c_longdouble;
pub extern fn exp(f64) f64;
pub extern fn expf(f32) f32;
pub extern fn expl(c_longdouble) c_longdouble;
pub extern fn exp2(f64) f64;
pub extern fn exp2f(f32) f32;
pub extern fn exp2l(c_longdouble) c_longdouble;
pub extern fn expm1(f64) f64;
pub extern fn expm1f(f32) f32;
pub extern fn expm1l(c_longdouble) c_longdouble;
pub extern fn fabs(f64) f64;
pub extern fn fabsf(f32) f32;
pub extern fn fabsl(c_longdouble) c_longdouble;
pub extern fn fdim(f64, f64) f64;
pub extern fn fdimf(f32, f32) f32;
pub extern fn fdiml(c_longdouble, c_longdouble) c_longdouble;
pub extern fn floor(f64) f64;
pub extern fn floorf(f32) f32;
pub extern fn floorl(c_longdouble) c_longdouble;
pub extern fn fma(f64, f64, f64) f64;
pub extern fn fmaf(f32, f32, f32) f32;
pub extern fn fmal(c_longdouble, c_longdouble, c_longdouble) c_longdouble;
pub extern fn fmaxf(f32, f32) f32;
pub extern fn fmaxl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn fmod(f64, f64) f64;
pub extern fn fmodf(f32, f32) f32;
pub extern fn fmodl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn frexp(f64, [*c]c_int) f64;
pub extern fn frexpf(f32, [*c]c_int) f32;
pub extern fn frexpl(c_longdouble, [*c]c_int) c_longdouble;
pub extern fn hypot(f64, f64) f64;
pub extern fn hypotf(f32, f32) f32;
pub extern fn hypotl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn ilogb(f64) c_int;
pub extern fn ilogbf(f32) c_int;
pub extern fn ilogbl(c_longdouble) c_int;
pub extern fn ldexp(f64, c_int) f64;
pub extern fn ldexpf(f32, c_int) f32;
pub extern fn ldexpl(c_longdouble, c_int) c_longdouble;
pub extern fn lgamma(f64) f64;
pub extern fn lgammaf(f32) f32;
pub extern fn lgammal(c_longdouble) c_longdouble;
pub extern fn llrint(f64) c_longlong;
pub extern fn llrintf(f32) c_longlong;
pub extern fn llrintl(c_longdouble) c_longlong;
pub extern fn llround(f64) c_longlong;
pub extern fn llroundf(f32) c_longlong;
pub extern fn llroundl(c_longdouble) c_longlong;
pub extern fn log(f64) f64;
pub extern fn logf(f32) f32;
pub extern fn logl(c_longdouble) c_longdouble;
pub extern fn log10(f64) f64;
pub extern fn log10f(f32) f32;
pub extern fn log10l(c_longdouble) c_longdouble;
pub extern fn log1p(f64) f64;
pub extern fn log1pf(f32) f32;
pub extern fn log1pl(c_longdouble) c_longdouble;
pub extern fn log2(f64) f64;
pub extern fn log2f(f32) f32;
pub extern fn log2l(c_longdouble) c_longdouble;
pub extern fn logb(f64) f64;
pub extern fn logbf(f32) f32;
pub extern fn logbl(c_longdouble) c_longdouble;
pub extern fn lrint(f64) c_long;
pub extern fn lrintf(f32) c_long;
pub extern fn lrintl(c_longdouble) c_long;
pub extern fn lround(f64) c_long;
pub extern fn lroundf(f32) c_long;
pub extern fn lroundl(c_longdouble) c_long;
pub extern fn modf(f64, [*c]f64) f64;
pub extern fn modff(f32, [*c]f32) f32;
pub extern fn modfl(c_longdouble, [*c]c_longdouble) c_longdouble;
pub extern fn nan([*c]const u8) f64;
pub extern fn nanf([*c]const u8) f32;
pub extern fn nanl([*c]const u8) c_longdouble;
pub extern fn nearbyint(f64) f64;
pub extern fn nearbyintf(f32) f32;
pub extern fn nearbyintl(c_longdouble) c_longdouble;
pub extern fn nextafter(f64, f64) f64;
pub extern fn nextafterf(f32, f32) f32;
pub extern fn nextafterl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn nexttoward(f64, c_longdouble) f64;
pub extern fn nexttowardf(f32, c_longdouble) f32;
pub extern fn nexttowardl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn pow(f64, f64) f64;
pub extern fn powl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn remainder(f64, f64) f64;
pub extern fn remainderf(f32, f32) f32;
pub extern fn remainderl(c_longdouble, c_longdouble) c_longdouble;
pub extern fn remquo(f64, f64, [*c]c_int) f64;
pub extern fn remquof(f32, f32, [*c]c_int) f32;
pub extern fn remquol(c_longdouble, c_longdouble, [*c]c_int) c_longdouble;
pub extern fn rint(f64) f64;
pub extern fn rintf(f32) f32;
pub extern fn rintl(c_longdouble) c_longdouble;
pub extern fn round(f64) f64;
pub extern fn roundf(f32) f32;
pub extern fn roundl(c_longdouble) c_longdouble;
pub extern fn scalbln(f64, c_long) f64;
pub extern fn scalblnf(f32, c_long) f32;
pub extern fn scalblnl(c_longdouble, c_long) c_longdouble;
pub extern fn scalbn(f64, c_int) f64;
pub extern fn scalbnf(f32, c_int) f32;
pub extern fn scalbnl(c_longdouble, c_int) c_longdouble;
pub extern fn sin(f64) f64;
pub extern fn sinf(f32) f32;
pub extern fn sinl(c_longdouble) c_longdouble;
pub extern fn sinh(f64) f64;
pub extern fn sinhf(f32) f32;
pub extern fn sinhl(c_longdouble) c_longdouble;
pub extern fn sqrtl(c_longdouble) c_longdouble;
pub extern fn tan(f64) f64;
pub extern fn tanf(f32) f32;
pub extern fn tanl(c_longdouble) c_longdouble;
pub extern fn tanh(f64) f64;
pub extern fn tanhf(f32) f32;
pub extern fn tanhl(c_longdouble) c_longdouble;
pub extern fn tgamma(f64) f64;
pub extern fn tgammaf(f32) f32;
pub extern fn tgammal(c_longdouble) c_longdouble;
pub extern fn trunc(f64) f64;
pub extern fn truncf(f32) f32;
pub extern fn truncl(c_longdouble) c_longdouble;
pub extern var signgam: c_int;
pub extern fn j0(f64) f64;
pub extern fn j1(f64) f64;
pub extern fn jn(c_int, f64) f64;
pub extern fn y0(f64) f64;
pub extern fn y1(f64) f64;
pub extern fn yn(c_int, f64) f64;
pub extern fn drem(f64, f64) f64;
pub extern fn dremf(f32, f32) f32;
pub extern fn finite(f64) c_int;
pub extern fn finitef(f32) c_int;
pub extern fn scalb(f64, f64) f64;
pub extern fn scalbf(f32, f32) f32;
pub extern fn significand(f64) f64;
pub extern fn significandf(f32) f32;
pub extern fn lgamma_r(f64, [*c]c_int) f64;
pub extern fn lgammaf_r(f32, [*c]c_int) f32;
pub extern fn j0f(f32) f32;
pub extern fn j1f(f32) f32;
pub extern fn jnf(c_int, f32) f32;
pub extern fn y0f(f32) f32;
pub extern fn y1f(f32) f32;
pub extern fn ynf(c_int, f32) f32;
pub const pi: f32 = 3.1415927410125732;
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
    return if (0.0031308000907301903 >= a) 12.920000076293945 * a else (1.0549999475479126 * powf(a, 0.4166666567325592)) - 0.054999999701976776;
}
pub fn srgb_transfer_function_inv(arg_a: f32) f32 {
    var a = arg_a;
    return if (0.040449999272823334 < a) powf((a + 0.054999999701976776) / 1.0549999475479126, 2.4000000953674316) else a / 12.920000076293945;
}
pub fn linear_srgb_to_oklab(arg_c: RGB) Lab {
    var c = arg_c;
    var l: f32 = ((0.4122214615345001 * c.r) + (0.5363325476646423 * c.g)) + (0.05144599452614784 * c.b);
    var m: f32 = ((0.21190349757671356 * c.r) + (0.6806995272636414 * c.g)) + (0.10739696025848389 * c.b);
    var s: f32 = ((0.08830246329307556 * c.r) + (0.2817188501358032 * c.g)) + (0.6299787163734436 * c.b);
    var l_: f32 = cbrtf(l);
    var m_: f32 = cbrtf(m);
    var s_: f32 = cbrtf(s);
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
    var L_cusp: f32 = cbrtf(@as(f32, @floatCast(@as(f64, @floatCast(1.0)) / @max(@max(@as(f64, @floatCast(rgb_at_max.r)), @as(f64, @floatCast(rgb_at_max.g))), @as(f64, @floatCast(rgb_at_max.b))))));
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
                t += @min(@as(f64, @floatCast(t_r)), @min(@as(f64, @floatCast(t_g)), @as(f64, @floatCast(t_b))));
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
    var C: f32 = @as(f32, @floatCast(@max(@as(f64, @floatCast(eps)), @as(f64, @floatCast(sqrtf((lab.a * lab.a) + (lab.b * lab.b)))))));
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
    var C: f32 = @as(f32, @floatCast(@max(@as(f64, @floatCast(eps)), @as(f64, @floatCast(sqrtf((lab.a * lab.a) + (lab.b * lab.b)))))));
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
    var C: f32 = @as(f32, @floatCast(@max(@as(f64, @floatCast(eps)), @as(f64, @floatCast(sqrtf((lab.a * lab.a) + (lab.b * lab.b)))))));
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
    return 0.5 * (((k_3 * x) - k_1) + sqrtf((((k_3 * x) - k_1) * ((k_3 * x) - k_1)) + (((@as(f32, @floatFromInt(@as(c_int, 4))) * k_2) * k_3) * x)));
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
        C_mid = (0.8999999761581421 * k) * sqrtf(sqrtf(1.0 / ((1.0 / (((C_a * C_a) * C_a) * C_a)) + (1.0 / (((C_b * C_b) * C_b) * C_b)))));
    }
    var C_0: f32 = undefined;
    {
        var C_a: f32 = L * 0.4000000059604645;
        var C_b: f32 = (1.0 - L) * 0.800000011920929;
        C_0 = sqrtf(1.0 / ((1.0 / (C_a * C_a)) + (1.0 / (C_b * C_b))));
    }
    return Cs{
        .C_0 = C_0,
        .C_mid = C_mid,
        .C_max = C_max,
    };
}
pub const __INTMAX_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `L`"); // (no file):80:9
pub const __UINTMAX_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `UL`"); // (no file):86:9
pub const __FLT16_DENORM_MIN__ = @compileError("unable to translate C expr: unexpected token 'IntegerLiteral'"); // (no file):109:9
pub const __FLT16_EPSILON__ = @compileError("unable to translate C expr: unexpected token 'IntegerLiteral'"); // (no file):113:9
pub const __FLT16_MAX__ = @compileError("unable to translate C expr: unexpected token 'IntegerLiteral'"); // (no file):119:9
pub const __FLT16_MIN__ = @compileError("unable to translate C expr: unexpected token 'IntegerLiteral'"); // (no file):122:9
pub const __INT64_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `L`"); // (no file):183:9
pub const __UINT32_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `U`"); // (no file):205:9
pub const __UINT64_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `UL`"); // (no file):213:9
pub const __seg_gs = @compileError("unable to translate macro: undefined identifier `__attribute__`"); // (no file):345:9
pub const __seg_fs = @compileError("unable to translate macro: undefined identifier `__attribute__`"); // (no file):346:9
pub const __restrict = @compileError("unable to translate C expr: unexpected token 'restrict'"); // /home/user/.zvm/0.11.0/lib/libc/include/generic-musl/features.h:20:9
pub const __inline = @compileError("unable to translate C expr: unexpected token 'inline'"); // /home/user/.zvm/0.11.0/lib/libc/include/generic-musl/features.h:26:9
pub const __REDIR = @compileError("unable to translate macro: undefined identifier `__typeof__`"); // /home/user/.zvm/0.11.0/lib/libc/include/generic-musl/features.h:38:9
pub const HUGE_VALL = @compileError("unable to translate: TODO long double"); // /home/user/.zvm/0.11.0/lib/libc/include/generic-musl/math.h:24:9
pub const __ISREL_DEF = @compileError("unable to translate macro: undefined identifier `__is`"); // /home/user/.zvm/0.11.0/lib/libc/include/generic-musl/math.h:104:9
pub const __tg_pred_2 = @compileError("unable to translate macro: undefined identifier `f`"); // /home/user/.zvm/0.11.0/lib/libc/include/generic-musl/math.h:124:9
pub const FLT_EVAL_METHOD = @compileError("unable to translate macro: undefined identifier `__FLT_EVAL_METHOD__`"); // /home/user/.zvm/0.11.0/lib/include/float.h:91:9
pub const FLT_ROUNDS = @compileError("unable to translate macro: undefined identifier `__builtin_flt_rounds`"); // /home/user/.zvm/0.11.0/lib/include/float.h:93:9
pub const __llvm__ = @as(c_int, 1);
pub const __clang__ = @as(c_int, 1);
pub const __clang_major__ = @as(c_int, 16);
pub const __clang_minor__ = @as(c_int, 0);
pub const __clang_patchlevel__ = @as(c_int, 6);
pub const __clang_version__ = "16.0.6 (https://github.com/ziglang/zig-bootstrap 1dda86241204c4649f668d46b6a37feed707c7b4)";
pub const __GNUC__ = @as(c_int, 4);
pub const __GNUC_MINOR__ = @as(c_int, 2);
pub const __GNUC_PATCHLEVEL__ = @as(c_int, 1);
pub const __GXX_ABI_VERSION = @as(c_int, 1002);
pub const __ATOMIC_RELAXED = @as(c_int, 0);
pub const __ATOMIC_CONSUME = @as(c_int, 1);
pub const __ATOMIC_ACQUIRE = @as(c_int, 2);
pub const __ATOMIC_RELEASE = @as(c_int, 3);
pub const __ATOMIC_ACQ_REL = @as(c_int, 4);
pub const __ATOMIC_SEQ_CST = @as(c_int, 5);
pub const __OPENCL_MEMORY_SCOPE_WORK_ITEM = @as(c_int, 0);
pub const __OPENCL_MEMORY_SCOPE_WORK_GROUP = @as(c_int, 1);
pub const __OPENCL_MEMORY_SCOPE_DEVICE = @as(c_int, 2);
pub const __OPENCL_MEMORY_SCOPE_ALL_SVM_DEVICES = @as(c_int, 3);
pub const __OPENCL_MEMORY_SCOPE_SUB_GROUP = @as(c_int, 4);
pub const __PRAGMA_REDEFINE_EXTNAME = @as(c_int, 1);
pub const __VERSION__ = "Clang 16.0.6 (https://github.com/ziglang/zig-bootstrap 1dda86241204c4649f668d46b6a37feed707c7b4)";
pub const __OBJC_BOOL_IS_BOOL = @as(c_int, 0);
pub const __CONSTANT_CFSTRINGS__ = @as(c_int, 1);
pub const __clang_literal_encoding__ = "UTF-8";
pub const __clang_wide_literal_encoding__ = "UTF-32";
pub const __ORDER_LITTLE_ENDIAN__ = @as(c_int, 1234);
pub const __ORDER_BIG_ENDIAN__ = @as(c_int, 4321);
pub const __ORDER_PDP_ENDIAN__ = @as(c_int, 3412);
pub const __BYTE_ORDER__ = __ORDER_LITTLE_ENDIAN__;
pub const __LITTLE_ENDIAN__ = @as(c_int, 1);
pub const _LP64 = @as(c_int, 1);
pub const __LP64__ = @as(c_int, 1);
pub const __CHAR_BIT__ = @as(c_int, 8);
pub const __BOOL_WIDTH__ = @as(c_int, 8);
pub const __SHRT_WIDTH__ = @as(c_int, 16);
pub const __INT_WIDTH__ = @as(c_int, 32);
pub const __LONG_WIDTH__ = @as(c_int, 64);
pub const __LLONG_WIDTH__ = @as(c_int, 64);
pub const __BITINT_MAXWIDTH__ = @import("std").zig.c_translation.promoteIntLiteral(c_int, 8388608, .decimal);
pub const __SCHAR_MAX__ = @as(c_int, 127);
pub const __SHRT_MAX__ = @as(c_int, 32767);
pub const __INT_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __LONG_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __LONG_LONG_MAX__ = @as(c_longlong, 9223372036854775807);
pub const __WCHAR_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __WCHAR_WIDTH__ = @as(c_int, 32);
pub const __WINT_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const __WINT_WIDTH__ = @as(c_int, 32);
pub const __INTMAX_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INTMAX_WIDTH__ = @as(c_int, 64);
pub const __SIZE_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __SIZE_WIDTH__ = @as(c_int, 64);
pub const __UINTMAX_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __UINTMAX_WIDTH__ = @as(c_int, 64);
pub const __PTRDIFF_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __PTRDIFF_WIDTH__ = @as(c_int, 64);
pub const __INTPTR_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INTPTR_WIDTH__ = @as(c_int, 64);
pub const __UINTPTR_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __UINTPTR_WIDTH__ = @as(c_int, 64);
pub const __SIZEOF_DOUBLE__ = @as(c_int, 8);
pub const __SIZEOF_FLOAT__ = @as(c_int, 4);
pub const __SIZEOF_INT__ = @as(c_int, 4);
pub const __SIZEOF_LONG__ = @as(c_int, 8);
pub const __SIZEOF_LONG_DOUBLE__ = @as(c_int, 16);
pub const __SIZEOF_LONG_LONG__ = @as(c_int, 8);
pub const __SIZEOF_POINTER__ = @as(c_int, 8);
pub const __SIZEOF_SHORT__ = @as(c_int, 2);
pub const __SIZEOF_PTRDIFF_T__ = @as(c_int, 8);
pub const __SIZEOF_SIZE_T__ = @as(c_int, 8);
pub const __SIZEOF_WCHAR_T__ = @as(c_int, 4);
pub const __SIZEOF_WINT_T__ = @as(c_int, 4);
pub const __SIZEOF_INT128__ = @as(c_int, 16);
pub const __INTMAX_TYPE__ = c_long;
pub const __INTMAX_FMTd__ = "ld";
pub const __INTMAX_FMTi__ = "li";
pub const __UINTMAX_TYPE__ = c_ulong;
pub const __UINTMAX_FMTo__ = "lo";
pub const __UINTMAX_FMTu__ = "lu";
pub const __UINTMAX_FMTx__ = "lx";
pub const __UINTMAX_FMTX__ = "lX";
pub const __PTRDIFF_TYPE__ = c_long;
pub const __PTRDIFF_FMTd__ = "ld";
pub const __PTRDIFF_FMTi__ = "li";
pub const __INTPTR_TYPE__ = c_long;
pub const __INTPTR_FMTd__ = "ld";
pub const __INTPTR_FMTi__ = "li";
pub const __SIZE_TYPE__ = c_ulong;
pub const __SIZE_FMTo__ = "lo";
pub const __SIZE_FMTu__ = "lu";
pub const __SIZE_FMTx__ = "lx";
pub const __SIZE_FMTX__ = "lX";
pub const __WCHAR_TYPE__ = c_int;
pub const __WINT_TYPE__ = c_uint;
pub const __SIG_ATOMIC_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __SIG_ATOMIC_WIDTH__ = @as(c_int, 32);
pub const __CHAR16_TYPE__ = c_ushort;
pub const __CHAR32_TYPE__ = c_uint;
pub const __UINTPTR_TYPE__ = c_ulong;
pub const __UINTPTR_FMTo__ = "lo";
pub const __UINTPTR_FMTu__ = "lu";
pub const __UINTPTR_FMTx__ = "lx";
pub const __UINTPTR_FMTX__ = "lX";
pub const __FLT16_HAS_DENORM__ = @as(c_int, 1);
pub const __FLT16_DIG__ = @as(c_int, 3);
pub const __FLT16_DECIMAL_DIG__ = @as(c_int, 5);
pub const __FLT16_HAS_INFINITY__ = @as(c_int, 1);
pub const __FLT16_HAS_QUIET_NAN__ = @as(c_int, 1);
pub const __FLT16_MANT_DIG__ = @as(c_int, 11);
pub const __FLT16_MAX_10_EXP__ = @as(c_int, 4);
pub const __FLT16_MAX_EXP__ = @as(c_int, 16);
pub const __FLT16_MIN_10_EXP__ = -@as(c_int, 4);
pub const __FLT16_MIN_EXP__ = -@as(c_int, 13);
pub const __FLT_DENORM_MIN__ = @as(f32, 1.40129846e-45);
pub const __FLT_HAS_DENORM__ = @as(c_int, 1);
pub const __FLT_DIG__ = @as(c_int, 6);
pub const __FLT_DECIMAL_DIG__ = @as(c_int, 9);
pub const __FLT_EPSILON__ = @as(f32, 1.19209290e-7);
pub const __FLT_HAS_INFINITY__ = @as(c_int, 1);
pub const __FLT_HAS_QUIET_NAN__ = @as(c_int, 1);
pub const __FLT_MANT_DIG__ = @as(c_int, 24);
pub const __FLT_MAX_10_EXP__ = @as(c_int, 38);
pub const __FLT_MAX_EXP__ = @as(c_int, 128);
pub const __FLT_MAX__ = @as(f32, 3.40282347e+38);
pub const __FLT_MIN_10_EXP__ = -@as(c_int, 37);
pub const __FLT_MIN_EXP__ = -@as(c_int, 125);
pub const __FLT_MIN__ = @as(f32, 1.17549435e-38);
pub const __DBL_DENORM_MIN__ = @as(f64, 4.9406564584124654e-324);
pub const __DBL_HAS_DENORM__ = @as(c_int, 1);
pub const __DBL_DIG__ = @as(c_int, 15);
pub const __DBL_DECIMAL_DIG__ = @as(c_int, 17);
pub const __DBL_EPSILON__ = @as(f64, 2.2204460492503131e-16);
pub const __DBL_HAS_INFINITY__ = @as(c_int, 1);
pub const __DBL_HAS_QUIET_NAN__ = @as(c_int, 1);
pub const __DBL_MANT_DIG__ = @as(c_int, 53);
pub const __DBL_MAX_10_EXP__ = @as(c_int, 308);
pub const __DBL_MAX_EXP__ = @as(c_int, 1024);
pub const __DBL_MAX__ = @as(f64, 1.7976931348623157e+308);
pub const __DBL_MIN_10_EXP__ = -@as(c_int, 307);
pub const __DBL_MIN_EXP__ = -@as(c_int, 1021);
pub const __DBL_MIN__ = @as(f64, 2.2250738585072014e-308);
pub const __LDBL_DENORM_MIN__ = @as(c_longdouble, 3.64519953188247460253e-4951);
pub const __LDBL_HAS_DENORM__ = @as(c_int, 1);
pub const __LDBL_DIG__ = @as(c_int, 18);
pub const __LDBL_DECIMAL_DIG__ = @as(c_int, 21);
pub const __LDBL_EPSILON__ = @as(c_longdouble, 1.08420217248550443401e-19);
pub const __LDBL_HAS_INFINITY__ = @as(c_int, 1);
pub const __LDBL_HAS_QUIET_NAN__ = @as(c_int, 1);
pub const __LDBL_MANT_DIG__ = @as(c_int, 64);
pub const __LDBL_MAX_10_EXP__ = @as(c_int, 4932);
pub const __LDBL_MAX_EXP__ = @as(c_int, 16384);
pub const __LDBL_MAX__ = @as(c_longdouble, 1.18973149535723176502e+4932);
pub const __LDBL_MIN_10_EXP__ = -@as(c_int, 4931);
pub const __LDBL_MIN_EXP__ = -@as(c_int, 16381);
pub const __LDBL_MIN__ = @as(c_longdouble, 3.36210314311209350626e-4932);
pub const __POINTER_WIDTH__ = @as(c_int, 64);
pub const __BIGGEST_ALIGNMENT__ = @as(c_int, 16);
pub const __WINT_UNSIGNED__ = @as(c_int, 1);
pub const __INT8_TYPE__ = i8;
pub const __INT8_FMTd__ = "hhd";
pub const __INT8_FMTi__ = "hhi";
pub const __INT8_C_SUFFIX__ = "";
pub const __INT16_TYPE__ = c_short;
pub const __INT16_FMTd__ = "hd";
pub const __INT16_FMTi__ = "hi";
pub const __INT16_C_SUFFIX__ = "";
pub const __INT32_TYPE__ = c_int;
pub const __INT32_FMTd__ = "d";
pub const __INT32_FMTi__ = "i";
pub const __INT32_C_SUFFIX__ = "";
pub const __INT64_TYPE__ = c_long;
pub const __INT64_FMTd__ = "ld";
pub const __INT64_FMTi__ = "li";
pub const __UINT8_TYPE__ = u8;
pub const __UINT8_FMTo__ = "hho";
pub const __UINT8_FMTu__ = "hhu";
pub const __UINT8_FMTx__ = "hhx";
pub const __UINT8_FMTX__ = "hhX";
pub const __UINT8_C_SUFFIX__ = "";
pub const __UINT8_MAX__ = @as(c_int, 255);
pub const __INT8_MAX__ = @as(c_int, 127);
pub const __UINT16_TYPE__ = c_ushort;
pub const __UINT16_FMTo__ = "ho";
pub const __UINT16_FMTu__ = "hu";
pub const __UINT16_FMTx__ = "hx";
pub const __UINT16_FMTX__ = "hX";
pub const __UINT16_C_SUFFIX__ = "";
pub const __UINT16_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_int, 65535, .decimal);
pub const __INT16_MAX__ = @as(c_int, 32767);
pub const __UINT32_TYPE__ = c_uint;
pub const __UINT32_FMTo__ = "o";
pub const __UINT32_FMTu__ = "u";
pub const __UINT32_FMTx__ = "x";
pub const __UINT32_FMTX__ = "X";
pub const __UINT32_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const __INT32_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __UINT64_TYPE__ = c_ulong;
pub const __UINT64_FMTo__ = "lo";
pub const __UINT64_FMTu__ = "lu";
pub const __UINT64_FMTx__ = "lx";
pub const __UINT64_FMTX__ = "lX";
pub const __UINT64_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __INT64_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INT_LEAST8_TYPE__ = i8;
pub const __INT_LEAST8_MAX__ = @as(c_int, 127);
pub const __INT_LEAST8_WIDTH__ = @as(c_int, 8);
pub const __INT_LEAST8_FMTd__ = "hhd";
pub const __INT_LEAST8_FMTi__ = "hhi";
pub const __UINT_LEAST8_TYPE__ = u8;
pub const __UINT_LEAST8_MAX__ = @as(c_int, 255);
pub const __UINT_LEAST8_FMTo__ = "hho";
pub const __UINT_LEAST8_FMTu__ = "hhu";
pub const __UINT_LEAST8_FMTx__ = "hhx";
pub const __UINT_LEAST8_FMTX__ = "hhX";
pub const __INT_LEAST16_TYPE__ = c_short;
pub const __INT_LEAST16_MAX__ = @as(c_int, 32767);
pub const __INT_LEAST16_WIDTH__ = @as(c_int, 16);
pub const __INT_LEAST16_FMTd__ = "hd";
pub const __INT_LEAST16_FMTi__ = "hi";
pub const __UINT_LEAST16_TYPE__ = c_ushort;
pub const __UINT_LEAST16_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_int, 65535, .decimal);
pub const __UINT_LEAST16_FMTo__ = "ho";
pub const __UINT_LEAST16_FMTu__ = "hu";
pub const __UINT_LEAST16_FMTx__ = "hx";
pub const __UINT_LEAST16_FMTX__ = "hX";
pub const __INT_LEAST32_TYPE__ = c_int;
pub const __INT_LEAST32_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __INT_LEAST32_WIDTH__ = @as(c_int, 32);
pub const __INT_LEAST32_FMTd__ = "d";
pub const __INT_LEAST32_FMTi__ = "i";
pub const __UINT_LEAST32_TYPE__ = c_uint;
pub const __UINT_LEAST32_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const __UINT_LEAST32_FMTo__ = "o";
pub const __UINT_LEAST32_FMTu__ = "u";
pub const __UINT_LEAST32_FMTx__ = "x";
pub const __UINT_LEAST32_FMTX__ = "X";
pub const __INT_LEAST64_TYPE__ = c_long;
pub const __INT_LEAST64_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INT_LEAST64_WIDTH__ = @as(c_int, 64);
pub const __INT_LEAST64_FMTd__ = "ld";
pub const __INT_LEAST64_FMTi__ = "li";
pub const __UINT_LEAST64_TYPE__ = c_ulong;
pub const __UINT_LEAST64_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __UINT_LEAST64_FMTo__ = "lo";
pub const __UINT_LEAST64_FMTu__ = "lu";
pub const __UINT_LEAST64_FMTx__ = "lx";
pub const __UINT_LEAST64_FMTX__ = "lX";
pub const __INT_FAST8_TYPE__ = i8;
pub const __INT_FAST8_MAX__ = @as(c_int, 127);
pub const __INT_FAST8_WIDTH__ = @as(c_int, 8);
pub const __INT_FAST8_FMTd__ = "hhd";
pub const __INT_FAST8_FMTi__ = "hhi";
pub const __UINT_FAST8_TYPE__ = u8;
pub const __UINT_FAST8_MAX__ = @as(c_int, 255);
pub const __UINT_FAST8_FMTo__ = "hho";
pub const __UINT_FAST8_FMTu__ = "hhu";
pub const __UINT_FAST8_FMTx__ = "hhx";
pub const __UINT_FAST8_FMTX__ = "hhX";
pub const __INT_FAST16_TYPE__ = c_short;
pub const __INT_FAST16_MAX__ = @as(c_int, 32767);
pub const __INT_FAST16_WIDTH__ = @as(c_int, 16);
pub const __INT_FAST16_FMTd__ = "hd";
pub const __INT_FAST16_FMTi__ = "hi";
pub const __UINT_FAST16_TYPE__ = c_ushort;
pub const __UINT_FAST16_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_int, 65535, .decimal);
pub const __UINT_FAST16_FMTo__ = "ho";
pub const __UINT_FAST16_FMTu__ = "hu";
pub const __UINT_FAST16_FMTx__ = "hx";
pub const __UINT_FAST16_FMTX__ = "hX";
pub const __INT_FAST32_TYPE__ = c_int;
pub const __INT_FAST32_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __INT_FAST32_WIDTH__ = @as(c_int, 32);
pub const __INT_FAST32_FMTd__ = "d";
pub const __INT_FAST32_FMTi__ = "i";
pub const __UINT_FAST32_TYPE__ = c_uint;
pub const __UINT_FAST32_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const __UINT_FAST32_FMTo__ = "o";
pub const __UINT_FAST32_FMTu__ = "u";
pub const __UINT_FAST32_FMTx__ = "x";
pub const __UINT_FAST32_FMTX__ = "X";
pub const __INT_FAST64_TYPE__ = c_long;
pub const __INT_FAST64_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const __INT_FAST64_WIDTH__ = @as(c_int, 64);
pub const __INT_FAST64_FMTd__ = "ld";
pub const __INT_FAST64_FMTi__ = "li";
pub const __UINT_FAST64_TYPE__ = c_ulong;
pub const __UINT_FAST64_MAX__ = @import("std").zig.c_translation.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const __UINT_FAST64_FMTo__ = "lo";
pub const __UINT_FAST64_FMTu__ = "lu";
pub const __UINT_FAST64_FMTx__ = "lx";
pub const __UINT_FAST64_FMTX__ = "lX";
pub const __USER_LABEL_PREFIX__ = "";
pub const __NO_MATH_ERRNO__ = @as(c_int, 1);
pub const __FINITE_MATH_ONLY__ = @as(c_int, 0);
pub const __GNUC_STDC_INLINE__ = @as(c_int, 1);
pub const __GCC_ATOMIC_TEST_AND_SET_TRUEVAL = @as(c_int, 1);
pub const __CLANG_ATOMIC_BOOL_LOCK_FREE = @as(c_int, 2);
pub const __CLANG_ATOMIC_CHAR_LOCK_FREE = @as(c_int, 2);
pub const __CLANG_ATOMIC_CHAR16_T_LOCK_FREE = @as(c_int, 2);
pub const __CLANG_ATOMIC_CHAR32_T_LOCK_FREE = @as(c_int, 2);
pub const __CLANG_ATOMIC_WCHAR_T_LOCK_FREE = @as(c_int, 2);
pub const __CLANG_ATOMIC_SHORT_LOCK_FREE = @as(c_int, 2);
pub const __CLANG_ATOMIC_INT_LOCK_FREE = @as(c_int, 2);
pub const __CLANG_ATOMIC_LONG_LOCK_FREE = @as(c_int, 2);
pub const __CLANG_ATOMIC_LLONG_LOCK_FREE = @as(c_int, 2);
pub const __CLANG_ATOMIC_POINTER_LOCK_FREE = @as(c_int, 2);
pub const __GCC_ATOMIC_BOOL_LOCK_FREE = @as(c_int, 2);
pub const __GCC_ATOMIC_CHAR_LOCK_FREE = @as(c_int, 2);
pub const __GCC_ATOMIC_CHAR16_T_LOCK_FREE = @as(c_int, 2);
pub const __GCC_ATOMIC_CHAR32_T_LOCK_FREE = @as(c_int, 2);
pub const __GCC_ATOMIC_WCHAR_T_LOCK_FREE = @as(c_int, 2);
pub const __GCC_ATOMIC_SHORT_LOCK_FREE = @as(c_int, 2);
pub const __GCC_ATOMIC_INT_LOCK_FREE = @as(c_int, 2);
pub const __GCC_ATOMIC_LONG_LOCK_FREE = @as(c_int, 2);
pub const __GCC_ATOMIC_LLONG_LOCK_FREE = @as(c_int, 2);
pub const __GCC_ATOMIC_POINTER_LOCK_FREE = @as(c_int, 2);
pub const __NO_INLINE__ = @as(c_int, 1);
pub const __PIC__ = @as(c_int, 2);
pub const __pic__ = @as(c_int, 2);
pub const __PIE__ = @as(c_int, 2);
pub const __pie__ = @as(c_int, 2);
pub const __FLT_RADIX__ = @as(c_int, 2);
pub const __DECIMAL_DIG__ = __LDBL_DECIMAL_DIG__;
pub const __SSP_STRONG__ = @as(c_int, 2);
pub const __GCC_ASM_FLAG_OUTPUTS__ = @as(c_int, 1);
pub const __code_model_small__ = @as(c_int, 1);
pub const __amd64__ = @as(c_int, 1);
pub const __amd64 = @as(c_int, 1);
pub const __x86_64 = @as(c_int, 1);
pub const __x86_64__ = @as(c_int, 1);
pub const __SEG_GS = @as(c_int, 1);
pub const __SEG_FS = @as(c_int, 1);
pub const __k8 = @as(c_int, 1);
pub const __k8__ = @as(c_int, 1);
pub const __tune_k8__ = @as(c_int, 1);
pub const __REGISTER_PREFIX__ = "";
pub const __NO_MATH_INLINES = @as(c_int, 1);
pub const __AES__ = @as(c_int, 1);
pub const __PCLMUL__ = @as(c_int, 1);
pub const __LAHF_SAHF__ = @as(c_int, 1);
pub const __LZCNT__ = @as(c_int, 1);
pub const __RDRND__ = @as(c_int, 1);
pub const __FSGSBASE__ = @as(c_int, 1);
pub const __BMI__ = @as(c_int, 1);
pub const __BMI2__ = @as(c_int, 1);
pub const __POPCNT__ = @as(c_int, 1);
pub const __PRFCHW__ = @as(c_int, 1);
pub const __RDSEED__ = @as(c_int, 1);
pub const __ADX__ = @as(c_int, 1);
pub const __MOVBE__ = @as(c_int, 1);
pub const __FMA__ = @as(c_int, 1);
pub const __F16C__ = @as(c_int, 1);
pub const __FXSR__ = @as(c_int, 1);
pub const __XSAVE__ = @as(c_int, 1);
pub const __XSAVEOPT__ = @as(c_int, 1);
pub const __XSAVEC__ = @as(c_int, 1);
pub const __XSAVES__ = @as(c_int, 1);
pub const __PKU__ = @as(c_int, 1);
pub const __CLFLUSHOPT__ = @as(c_int, 1);
pub const __SGX__ = @as(c_int, 1);
pub const __INVPCID__ = @as(c_int, 1);
pub const __AVX2__ = @as(c_int, 1);
pub const __AVX__ = @as(c_int, 1);
pub const __SSE4_2__ = @as(c_int, 1);
pub const __SSE4_1__ = @as(c_int, 1);
pub const __SSSE3__ = @as(c_int, 1);
pub const __SSE3__ = @as(c_int, 1);
pub const __SSE2__ = @as(c_int, 1);
pub const __SSE2_MATH__ = @as(c_int, 1);
pub const __SSE__ = @as(c_int, 1);
pub const __SSE_MATH__ = @as(c_int, 1);
pub const __MMX__ = @as(c_int, 1);
pub const __GCC_HAVE_SYNC_COMPARE_AND_SWAP_1 = @as(c_int, 1);
pub const __GCC_HAVE_SYNC_COMPARE_AND_SWAP_2 = @as(c_int, 1);
pub const __GCC_HAVE_SYNC_COMPARE_AND_SWAP_4 = @as(c_int, 1);
pub const __GCC_HAVE_SYNC_COMPARE_AND_SWAP_8 = @as(c_int, 1);
pub const __GCC_HAVE_SYNC_COMPARE_AND_SWAP_16 = @as(c_int, 1);
pub const __SIZEOF_FLOAT128__ = @as(c_int, 16);
pub const unix = @as(c_int, 1);
pub const __unix = @as(c_int, 1);
pub const __unix__ = @as(c_int, 1);
pub const linux = @as(c_int, 1);
pub const __linux = @as(c_int, 1);
pub const __linux__ = @as(c_int, 1);
pub const __ELF__ = @as(c_int, 1);
pub const __gnu_linux__ = @as(c_int, 1);
pub const __FLOAT128__ = @as(c_int, 1);
pub const __STDC__ = @as(c_int, 1);
pub const __STDC_HOSTED__ = @as(c_int, 1);
pub const __STDC_VERSION__ = @as(c_long, 201710);
pub const __STDC_UTF_16__ = @as(c_int, 1);
pub const __STDC_UTF_32__ = @as(c_int, 1);
pub const _DEBUG = @as(c_int, 1);
pub const __GCC_HAVE_DWARF2_CFI_ASM = @as(c_int, 1);
pub const _MATH_H = "";
pub const _FEATURES_H = "";
pub const _BSD_SOURCE = @as(c_int, 1);
pub const _XOPEN_SOURCE = @as(c_int, 700);
pub const __NEED_float_t = "";
pub const __NEED_double_t = "";
pub const _Addr = c_long;
pub const _Int64 = c_long;
pub const _Reg = c_long;
pub const __BYTE_ORDER = @as(c_int, 1234);
pub const __LONG_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_long, 0x7fffffffffffffff, .hexadecimal);
pub const __DEFINED_float_t = "";
pub const __DEFINED_double_t = "";
pub const __LITTLE_ENDIAN = @as(c_int, 1234);
pub const __BIG_ENDIAN = @as(c_int, 4321);
pub const __USE_TIME_BITS64 = @as(c_int, 1);
pub const NAN = __builtin_nanf("");
pub const INFINITY = __builtin_inff();
pub const HUGE_VALF = INFINITY;
pub const HUGE_VAL = @import("std").zig.c_translation.cast(f64, INFINITY);
pub const MATH_ERRNO = @as(c_int, 1);
pub const MATH_ERREXCEPT = @as(c_int, 2);
pub const math_errhandling = @as(c_int, 2);
pub const FP_ILOGBNAN = -@as(c_int, 1) - @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hexadecimal);
pub const FP_ILOGB0 = FP_ILOGBNAN;
pub const FP_NAN = @as(c_int, 0);
pub const FP_INFINITE = @as(c_int, 1);
pub const FP_ZERO = @as(c_int, 2);
pub const FP_SUBNORMAL = @as(c_int, 3);
pub const FP_NORMAL = @as(c_int, 4);
pub inline fn fpclassify(x: anytype) @TypeOf(if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) __fpclassifyf(x) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) __fpclassify(x) else __fpclassifyl(x)) {
    return if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) __fpclassifyf(x) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) __fpclassify(x) else __fpclassifyl(x);
}
pub inline fn isinf(x: anytype) @TypeOf(if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) (__FLOAT_BITS(x) & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hexadecimal)) == @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7f800000, .hexadecimal) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) (__DOUBLE_BITS(x) & (-@as(c_ulonglong, 1) >> @as(c_int, 1))) == (@as(c_ulonglong, 0x7ff) << @as(c_int, 52)) else __fpclassifyl(x) == FP_INFINITE) {
    return if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) (__FLOAT_BITS(x) & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hexadecimal)) == @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7f800000, .hexadecimal) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) (__DOUBLE_BITS(x) & (-@as(c_ulonglong, 1) >> @as(c_int, 1))) == (@as(c_ulonglong, 0x7ff) << @as(c_int, 52)) else __fpclassifyl(x) == FP_INFINITE;
}
pub inline fn isnan(x: anytype) @TypeOf(if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) (__FLOAT_BITS(x) & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hexadecimal)) > @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7f800000, .hexadecimal) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) (__DOUBLE_BITS(x) & (-@as(c_ulonglong, 1) >> @as(c_int, 1))) > (@as(c_ulonglong, 0x7ff) << @as(c_int, 52)) else __fpclassifyl(x) == FP_NAN) {
    return if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) (__FLOAT_BITS(x) & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hexadecimal)) > @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7f800000, .hexadecimal) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) (__DOUBLE_BITS(x) & (-@as(c_ulonglong, 1) >> @as(c_int, 1))) > (@as(c_ulonglong, 0x7ff) << @as(c_int, 52)) else __fpclassifyl(x) == FP_NAN;
}
pub inline fn isnormal(x: anytype) @TypeOf(if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) ((__FLOAT_BITS(x) + @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x00800000, .hexadecimal)) & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hexadecimal)) >= @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x01000000, .hexadecimal) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) ((__DOUBLE_BITS(x) + (@as(c_ulonglong, 1) << @as(c_int, 52))) & (-@as(c_ulonglong, 1) >> @as(c_int, 1))) >= (@as(c_ulonglong, 1) << @as(c_int, 53)) else __fpclassifyl(x) == FP_NORMAL) {
    return if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) ((__FLOAT_BITS(x) + @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x00800000, .hexadecimal)) & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hexadecimal)) >= @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x01000000, .hexadecimal) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) ((__DOUBLE_BITS(x) + (@as(c_ulonglong, 1) << @as(c_int, 52))) & (-@as(c_ulonglong, 1) >> @as(c_int, 1))) >= (@as(c_ulonglong, 1) << @as(c_int, 53)) else __fpclassifyl(x) == FP_NORMAL;
}
pub inline fn isfinite(x: anytype) @TypeOf(if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) (__FLOAT_BITS(x) & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hexadecimal)) < @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7f800000, .hexadecimal) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) (__DOUBLE_BITS(x) & (-@as(c_ulonglong, 1) >> @as(c_int, 1))) < (@as(c_ulonglong, 0x7ff) << @as(c_int, 52)) else __fpclassifyl(x) > FP_INFINITE) {
    return if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) (__FLOAT_BITS(x) & @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7fffffff, .hexadecimal)) < @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x7f800000, .hexadecimal) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) (__DOUBLE_BITS(x) & (-@as(c_ulonglong, 1) >> @as(c_int, 1))) < (@as(c_ulonglong, 0x7ff) << @as(c_int, 52)) else __fpclassifyl(x) > FP_INFINITE;
}
pub inline fn signbit(x: anytype) @TypeOf(if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) @import("std").zig.c_translation.cast(c_int, __FLOAT_BITS(x) >> @as(c_int, 31)) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) @import("std").zig.c_translation.cast(c_int, __DOUBLE_BITS(x) >> @as(c_int, 63)) else __signbitl(x)) {
    return if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f32)) @import("std").zig.c_translation.cast(c_int, __FLOAT_BITS(x) >> @as(c_int, 31)) else if (@import("std").zig.c_translation.sizeof(x) == @import("std").zig.c_translation.sizeof(f64)) @import("std").zig.c_translation.cast(c_int, __DOUBLE_BITS(x) >> @as(c_int, 63)) else __signbitl(x);
}
pub inline fn isunordered(x: anytype, y: anytype) @TypeOf(if (isnan(x))
blk_2: {
    _ = @import("std").zig.c_translation.cast(anyopaque, y);
    break :blk_2 @as(c_int, 1);
} else isnan(y)) {
    return if (isnan(x)) blk_2: {
        _ = @import("std").zig.c_translation.cast(anyopaque, y);
        break :blk_2 @as(c_int, 1);
    } else isnan(y);
}
pub inline fn isless(x: anytype, y: anytype) @TypeOf(__tg_pred_2(x, y, __isless)) {
    return __tg_pred_2(x, y, __isless);
}
pub inline fn islessequal(x: anytype, y: anytype) @TypeOf(__tg_pred_2(x, y, __islessequal)) {
    return __tg_pred_2(x, y, __islessequal);
}
pub inline fn islessgreater(x: anytype, y: anytype) @TypeOf(__tg_pred_2(x, y, __islessgreater)) {
    return __tg_pred_2(x, y, __islessgreater);
}
pub inline fn isgreater(x: anytype, y: anytype) @TypeOf(__tg_pred_2(x, y, __isgreater)) {
    return __tg_pred_2(x, y, __isgreater);
}
pub inline fn isgreaterequal(x: anytype, y: anytype) @TypeOf(__tg_pred_2(x, y, __isgreaterequal)) {
    return __tg_pred_2(x, y, __isgreaterequal);
}
pub const MAXFLOAT = @as(f32, 3.40282346638528859812e+38);
pub const M_E = @as(f64, 2.7182818284590452354);
pub const M_LOG2E = @as(f64, 1.4426950408889634074);
pub const M_LOG10E = @as(f64, 0.43429448190325182765);
pub const M_LN2 = @as(f64, 0.69314718055994530942);
pub const M_LN10 = @as(f64, 2.30258509299404568402);
pub const M_PI = @as(f64, 3.14159265358979323846);
pub const M_PI_2 = @as(f64, 1.57079632679489661923);
pub const M_PI_4 = @as(f64, 0.78539816339744830962);
pub const M_1_PI = @as(f64, 0.31830988618379067154);
pub const M_2_PI = @as(f64, 0.63661977236758134308);
pub const M_2_SQRTPI = @as(f64, 1.12837916709551257390);
pub const M_SQRT2 = @as(f64, 1.41421356237309504880);
pub const M_SQRT1_2 = @as(f64, 0.70710678118654752440);
pub const HUGE = @as(f32, 3.40282346638528859812e+38);
pub const __CLANG_FLOAT_H = "";
pub const FLT_RADIX = __FLT_RADIX__;
pub const FLT_MANT_DIG = __FLT_MANT_DIG__;
pub const DBL_MANT_DIG = __DBL_MANT_DIG__;
pub const LDBL_MANT_DIG = __LDBL_MANT_DIG__;
pub const DECIMAL_DIG = __DECIMAL_DIG__;
pub const FLT_DIG = __FLT_DIG__;
pub const DBL_DIG = __DBL_DIG__;
pub const LDBL_DIG = __LDBL_DIG__;
pub const FLT_MIN_EXP = __FLT_MIN_EXP__;
pub const DBL_MIN_EXP = __DBL_MIN_EXP__;
pub const LDBL_MIN_EXP = __LDBL_MIN_EXP__;
pub const FLT_MIN_10_EXP = __FLT_MIN_10_EXP__;
pub const DBL_MIN_10_EXP = __DBL_MIN_10_EXP__;
pub const LDBL_MIN_10_EXP = __LDBL_MIN_10_EXP__;
pub const FLT_MAX_EXP = __FLT_MAX_EXP__;
pub const DBL_MAX_EXP = __DBL_MAX_EXP__;
pub const LDBL_MAX_EXP = __LDBL_MAX_EXP__;
pub const FLT_MAX_10_EXP = __FLT_MAX_10_EXP__;
pub const DBL_MAX_10_EXP = __DBL_MAX_10_EXP__;
pub const LDBL_MAX_10_EXP = __LDBL_MAX_10_EXP__;
pub const FLT_MAX = __FLT_MAX__;
pub const DBL_MAX = __DBL_MAX__;
pub const LDBL_MAX = __LDBL_MAX__;
pub const FLT_EPSILON = __FLT_EPSILON__;
pub const DBL_EPSILON = __DBL_EPSILON__;
pub const LDBL_EPSILON = __LDBL_EPSILON__;
pub const FLT_MIN = __FLT_MIN__;
pub const DBL_MIN = __DBL_MIN__;
pub const LDBL_MIN = __LDBL_MIN__;
pub const FLT_TRUE_MIN = __FLT_DENORM_MIN__;
pub const DBL_TRUE_MIN = __DBL_DENORM_MIN__;
pub const LDBL_TRUE_MIN = __LDBL_DENORM_MIN__;
pub const FLT_DECIMAL_DIG = __FLT_DECIMAL_DIG__;
pub const DBL_DECIMAL_DIG = __DBL_DECIMAL_DIG__;
pub const LDBL_DECIMAL_DIG = __LDBL_DECIMAL_DIG__;
pub const FLT_HAS_SUBNORM = __FLT_HAS_DENORM__;
pub const DBL_HAS_SUBNORM = __DBL_HAS_DENORM__;
pub const LDBL_HAS_SUBNORM = __LDBL_HAS_DENORM__;
