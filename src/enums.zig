const builtin = @import("builtin");

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

    pub fn is(self: Mod, other: Mod) bool {
        const s: u16 = @intFromEnum(self);
        const t: u16 = @intFromEnum(other);
        return (s & t) != 0;
    }

    pub fn shift(self: Mod) bool {
        return self.is(.lshift) or self.is(.rshift);
    }

    pub fn control(self: Mod) bool {
        return self.is(.lcontrol) or self.is(.rcontrol);
    }

    pub fn alt(self: Mod) bool {
        return self.is(.lalt) or self.is(.ralt);
    }

    pub fn command(self: Mod) bool {
        return self.is(.lcommand) or self.is(.rcommand);
    }

    pub fn controlCommand(self: Mod) bool {
        if (builtin.target.isDarwin()) {
            return self.command();
        } else {
            return self.control();
        }
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
    closed,
    ok,
    _,
};
