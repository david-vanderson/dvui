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
    scroll_propogate: ScrollPropogate,
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

/// Event bubbled from inside a scrollarea to ensure scrolling while dragging
/// if the mouse moves to the edge or outside the scrollarea.
///
/// During dragging, a widget should bubble this on each pointer motion event.
pub const ScrollDrag = struct {

    // mouse point from motion event
    mouse_pt: Point,

    // rect in screen coords of the widget doing the drag (scrolling will stop
    // if it wouldn't show more of this rect)
    screen_rect: Rect,

    // id of the widget that has mouse capture during the drag (needed to
    // inject synthetic motion events into the next frame to keep scrolling)
    capture_id: u32,
};

/// Event bubbled from inside a scrollarea to scroll to a specific place.
pub const ScrollTo = struct {

    // rect in screen coords we want to be visible (might be outside
    // scrollarea's clipping region - we want to scroll to bring it inside)
    screen_rect: Rect,

    // whether to scroll outside the current scroll bounds (useful if the
    // current action might be expanding the scroll area)
    over_scroll: bool = false,
};

/// Event bubbled from a scrollarea when user tries to scroll farther than it
/// can.  Containing scrollareas use this to scroll if they can.
/// Example is scrolling a TextEntry to its top will then scroll the containing
/// page up.
pub const ScrollPropogate = struct {
    /// Motion field from the Mouse event that would have scrolled but we were
    /// at the edge.
    motion: Point,
};
