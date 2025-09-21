const builtin = @import("builtin");
const std = @import("std");
const dvui = @import("../dvui.zig");
const enums_backend = @import("enums_backend.zig");

pub const Backend = enums_backend.Backend;

pub const DialogButtonOrder = enum {
    cancel_ok,
    ok_cancel,
};

pub const Units = enum {
    /// None is the logical units. It's used for relative placements
    /// and other non-pixel use cases
    none,
    /// Natural pixels is the unit for subwindows. It differs from
    /// physical pixels on hidpi screens or with content scaling.
    natural,
    /// Physical pixels is the units for rendering and dvui events.
    /// Regardless of dpi or content scaling, physical pixels always
    /// matches the output screen.
    physical,
};

pub const TextureInterpolation = enum {
    nearest,
    linear,
};

pub const Button = enum {
    // used for mouse motion/wheel/position events, but never for press/release
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

    pub fn format(self: *const Keybind, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        var needs_space = false;
        if (self.control) |ctrl| {
            if (needs_space) try writer.writeByte(' ') else needs_space = true;
            if (!ctrl) try writer.writeByte('!');
            try writer.writeAll("ctrl");
        }

        if (self.command) |cmd| {
            if (needs_space) try writer.writeByte(' ') else needs_space = true;
            if (!cmd) try writer.writeByte('!');
            try writer.writeAll("cmd");
        }

        if (self.alt) |alt| {
            if (needs_space) try writer.writeByte(' ') else needs_space = true;
            if (!alt) try writer.writeByte('!');
            try writer.writeAll("alt");
        }

        if (self.shift) |shift| {
            if (needs_space) try writer.writeByte(' ') else needs_space = true;
            if (!shift) try writer.writeByte('!');
            try writer.writeAll("shift");
        }

        if (self.key) |key| {
            if (needs_space) try writer.writeByte(' ') else needs_space = true;
            try writer.writeAll(@tagName(key));
        }
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
        if (self == .none) return false;
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

    /// True if matches the named keybind ignoring Keybind.key (follows
    /// Keybind.also).  See `matchKeyBind`.
    pub fn matchBind(self: Mod, keybind_name: []const u8) bool {
        const cw = dvui.currentWindow();

        var name = keybind_name;
        while (true) {
            if (cw.keybinds.get(name)) |kb| {
                if (self.matchKeyBind(kb)) {
                    return true;
                } else if (kb.also) |also_name| {
                    name = also_name;
                    continue;
                } else {
                    return false;
                }
            } else {
                return false;
            }
        }
    }

    /// True if matches the named keybind ignoring Keybind.key (ignores
    /// Keybind.also).   Usually you want `matchBind`.
    pub fn matchKeyBind(self: Mod, kb: Keybind) bool {
        return ((kb.shift == null or kb.shift.? == self.shift()) and
            (kb.control == null or kb.control.? == self.control()) and
            (kb.alt == null or kb.alt.? == self.alt()) and
            (kb.command == null or kb.command.? == self.command()));
    }

    pub fn format(self: *const Mod, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll("Mod(");
        var needs_separator = false;

        if (self.* == .none) {
            try writer.writeAll("none");
        } else {
            const mod_fields = comptime std.meta.fieldNames(Mod);
            inline for (mod_fields[0..9]) |field_name| {
                if (self.has(@field(Mod, field_name))) {
                    if (needs_separator) try writer.writeAll(", ") else needs_separator = true;
                    try writer.writeAll(field_name);
                }
            }
        }

        try writer.writeAll(")");
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

    pub fn invert(self: Direction) Direction {
        return switch (self) {
            .horizontal => .vertical,
            .vertical => .horizontal,
        };
    }
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
    hidden,
};

pub const ColorScheme = enum { light, dark };

test {
    @import("std").testing.refAllDecls(@This());
}
