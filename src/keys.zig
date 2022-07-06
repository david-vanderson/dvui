pub const Mod = enum(u16) {
    none = 0,

    lshift = 0b00000001,
    rshift = 0b00000010,

    lctrl = 0b00000100,
    rctrl = 0b00001000,

    lalt = 0b00010000,
    ralt = 0b00100000,

    lgui = 0b01000000,
    rgui = 0b10000000,

    // make non-exhaustive so that we can take combinations of the values
    _,

    pub fn shift(self: Mod) bool {
        return self == .lshift or self == .rshift;
    }

    pub fn ctrl(self: Mod) bool {
        return self == .lctrl or self == .rctrl;
    }

    pub fn alt(self: Mod) bool {
        return self == .lalt or self == .ralt;
    }

    pub fn gui(self: Mod) bool {
        return self == .lgui or self == .rgui;
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
    left_super,
    right_super,
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
