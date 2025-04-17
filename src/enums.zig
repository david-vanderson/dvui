const builtin = @import("builtin");
const std = @import("std");

pub const Backend = enum {
    custom,
    /// DEPRECATED: Use either sdl2 or sdl3
    sdl,
    sdl2,
    sdl3,
    raylib,
    dx11,
    web,
};

pub const TextureInterpolation = enum {
    nearest,
    linear,
};

pub const Button = enum {
    // used for mouse motion events
    none,

    left,
    right,
    middle,
    four,
    five,
    six,
    seven,
    eight,

    touch0,
    touch1,
    touch2,
    touch3,
    touch4,
    touch5,
    touch6,
    touch7,
    touch8,
    touch9,

    pub fn touch(self: Button) bool {
        const s = @intFromEnum(self);
        const start = @intFromEnum(Button.touch0);
        const end = @intFromEnum(Button.touch9);
        return (s >= start and s <= end);
    }

    pub fn pointer(self: Button) bool {
        return (self == .left or self.touch());
    }
};

pub const Keybind = struct {
    shift: ?bool = null,
    control: ?bool = null,
    alt: ?bool = null,
    command: ?bool = null,
    key: ?Key = null,
    also: ?[]const u8 = null,

    pub fn format(self: Keybind, arena: std.mem.Allocator) ![]u8 {
        var ctrl_str: []const u8 = "";
        if (self.control) |ctrl| {
            ctrl_str = if (ctrl) "ctrl " else "!ctrl ";
        }

        var cmd_str: []const u8 = "";
        if (self.command) |cmd| {
            cmd_str = if (cmd) "cmd " else "!cmd ";
        }

        var alt_str: []const u8 = "";
        if (self.alt) |alt| {
            alt_str = if (alt) "alt " else "!alt ";
        }

        var shift_str: []const u8 = "";
        if (self.shift) |shift| {
            shift_str = if (shift) "shift " else "!shift ";
        }

        var key_str: []const u8 = "";
        if (self.key) |key| {
            key_str = @tagName(key);
        }

        return try std.fmt.allocPrint(arena, "{s}{s}{s}{s}{s}", .{ ctrl_str, cmd_str, alt_str, shift_str, key_str });
    }
};

pub const Mod = enum(u16) {
    none = 0,

    lshift = 0b00000001,
    rshift = 0b00000010,

    lcontrol = 0b00000100,
    rcontrol = 0b00001000,

    lalt = 0b00010000,
    ralt = 0b00100000,

    lcommand = 0b01000000,
    rcommand = 0b10000000,

    // make non-exhaustive so that we can take combinations of the values
    _,

    pub fn has(self: Mod, other: Mod) bool {
        const s: u16 = @intFromEnum(self);
        const t: u16 = @intFromEnum(other);
        return (s & t) != 0;
    }

    //returns whether shift is the only modifier
    pub fn shiftOnly(self: Mod) bool {
        const lsh = @intFromEnum(Mod.lshift);
        const rsh = @intFromEnum(Mod.rshift);
        const mask = lsh | rsh;
        const input = @intFromEnum(self);
        return (input & mask) == input;
    }

    pub fn shift(self: Mod) bool {
        return self.has(.lshift) or self.has(.rshift);
    }

    pub fn control(self: Mod) bool {
        return self.has(.lcontrol) or self.has(.rcontrol);
    }

    pub fn alt(self: Mod) bool {
        return self.has(.lalt) or self.has(.ralt);
    }

    pub fn command(self: Mod) bool {
        return self.has(.lcommand) or self.has(.rcommand);
    }

    ///combine two modifiers
    pub fn combine(self: *Mod, other: Mod) void {
        const s: u16 = @intFromEnum(self.*);
        const t: u16 = @intFromEnum(other);
        self.* = @enumFromInt(s | t);
    }

    ///remove modifier
    pub fn unset(self: *Mod, other: Mod) void {
        const s: u16 = @intFromEnum(self.*);
        const t: u16 = @intFromEnum(other);
        self.* = @enumFromInt(s & (~t));
    }

    ///for debugging
    pub fn print(self: Mod) void {
        std.debug.print("Mod(", .{});

        var found_set = false;

        const mod_fields = comptime std.meta.fieldNames(Mod);
        inline for (mod_fields[0..9]) |field_name| {
            if (self.has(@field(Mod, field_name))) {
                std.debug.print(".{s}, ", .{field_name});
                found_set = true;
            }
        }

        if (found_set == false) {
            std.debug.print("{}", .{self});
        }

        std.debug.print(")\n", .{});
    }
};

pub const Key = enum {
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,

    zero,
    one,
    two,
    three,
    four,
    five,
    six,
    seven,
    eight,
    nine,

    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    f13,
    f14,
    f15,
    f16,
    f17,
    f18,
    f19,
    f20,
    f21,
    f22,
    f23,
    f24,
    f25,

    kp_divide,
    kp_multiply,
    kp_subtract,
    kp_add,
    kp_0,
    kp_1,
    kp_2,
    kp_3,
    kp_4,
    kp_5,
    kp_6,
    kp_7,
    kp_8,
    kp_9,
    kp_decimal,
    kp_equal,
    kp_enter,

    enter,
    escape,
    tab,
    left_shift,
    right_shift,
    left_control,
    right_control,
    left_alt,
    right_alt,
    left_command,
    right_command,
    menu,
    num_lock,
    caps_lock,
    print,
    scroll_lock,
    pause,
    delete,
    home,
    end,
    page_up,
    page_down,
    insert,
    left,
    right,
    up,
    down,
    backspace,
    space,
    minus,
    equal,
    left_bracket,
    right_bracket,
    backslash,
    semicolon,
    apostrophe,
    comma,
    period,
    slash,
    grave,

    unknown,
};

pub const Direction = enum {
    horizontal,
    vertical,
};

pub const DialogResponse = enum(u8) {
    cancel,
    ok,
    _,
};

pub const Cursor = enum(u8) {
    arrow,
    ibeam,
    wait,
    wait_arrow,
    crosshair,
    arrow_nw_se,
    arrow_ne_sw,
    arrow_w_e,
    arrow_n_s,
    arrow_all,
    bad,
    hand,
};

test {
    @import("std").testing.refAllDecls(@This());
}
