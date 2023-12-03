const dvui = @import("dvui.zig");

const Point = dvui.Point;
const Rect = dvui.Rect;

const enums = dvui.enums;

const Event = @This();

handled: bool = false,
focus_windowId: ?u32 = null,
focus_widgetId: ?u32 = null,
// num increments withing a frame, used in focusRemainingEvents
num: u16 = 0,
evt: union(enum) {
    // non-bubbleable
    mouse: Mouse,

    // bubbleable
    key: Key,
    text: []u8,
    close_popup: ClosePopup,
    scroll_drag: ScrollDrag,
    scroll_to: ScrollTo,
},

// All widgets have to bubble keyboard events if they can have keyboard focus
// so that pressing the up key in any child of a scrollarea will scroll.  Call
// this helper at the end of processEvent().
pub fn bubbleable(self: *const Event) bool {
    return (!self.handled and (self.evt != .mouse));
}

pub const Key = struct {
    code: enums.Key,
    action: enum {
        down,
        repeat,
        up,
    },
    mod: enums.Mod,
};

pub const Mouse = struct {
    pub const Action = enum {
        // Focus events come right before their associated pointer event, usually
        // leftdown/rightdown or motion. Separated to enable changing what
        // causes focus changes.
        focus,
        press,
        release,

        wheel_y,

        // motion Point is the change in position
        // if you just want to react to the current mouse position if it got
        // moved at all, use the .position event with mouseTotalMotion()
        motion,

        // only one position event per frame, and it's always after all other
        // mouse events, used to change mouse cursor and do widget highlighting
        // - also useful with mouseTotalMotion() to respond to mouse motion but
        // only at the final location
        position,
    };

    action: Action,

    // This distinguishes between mouse and touch events.
    // .none is used for mouse wheel and position
    // mouse motion will be a touch or .none
    button: enums.Button,

    p: Point,
    floating_win: u32,

    data: union {
        none: void,
        motion: Point,
        wheel_y: f32,
    } = .{ .none = {} },
};

pub const ClosePopup = struct {
    // are we closing because of a specific user action (clicked on menu item,
    // pressed escape), or because they clicked off the menu somewhere?
    intentional: bool = true,
};

pub const ScrollDrag = struct {
    // bubbled up from a child to tell a containing scrollarea to
    // possibly scroll to show more of the child
    mouse_pt: Point,
    screen_rect: Rect,
    capture_id: u32,
};

pub const ScrollTo = struct {
    // bubbled up from a child to tell a containing scrollarea to
    // scroll to show the given rect
    screen_rect: Rect,

    // whether to scroll outside the current scroll bounds (useful if the
    // current action might be expanding the scroll area)
    over_scroll: bool = false,
};
