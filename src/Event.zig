const dvui = @import("dvui.zig");
const std = @import("std");

const enums = dvui.enums;

const Event = @This();

/// Should not be set directly, use the `handle` method
handled: bool = false,
focus_windowId: ?dvui.WidgetId = null,
focus_widgetId: ?dvui.WidgetId = null,
// num increments within a frame, used in focusRemainingEvents
num: u16 = 0,
evt: union(enum) {
    // non-bubbleable
    mouse: Mouse,
    key: Key,

    // bubbleable
    text: Text,
    scroll_drag: ScrollDrag,
    scroll_to: ScrollTo,
    scroll_propagate: ScrollPropagate,
},

// All widgets have to bubble keyboard events if they can have keyboard focus
// so that pressing the up key in any child of a scrollarea will scroll.  Call
// this helper at the end of processEvent().
pub fn bubbleable(self: *const Event) bool {
    return (!self.handled and self.evt != .mouse and self.evt != .key);
}

/// Mark the event as handled
///
/// In general, the `dvui.WidgetData` passed here should be the same one that
/// matched this event, using `dvui.matchEvent` or similar.
/// This makes it possible to see which widget handled the event.
pub fn handle(self: *Event, src: std.builtin.SourceLocation, wd: *const dvui.WidgetData) void {
    if (dvui.currentWindow().debug_handled_event) {
        var action: []const u8 = "";
        switch (self.evt) {
            .mouse => action = @tagName(self.evt.mouse.action),
            .key => action = @tagName(self.evt.key.action),
            else => {},
        }
        dvui.log.debug("{s}:{d} {s} {s} event (num {d}) handled by {s} ({x})", .{ src.file, src.line, @tagName(self.evt), action, self.num, wd.options.name orelse "???", wd.id });
    }
    self.handled = true;
}

pub const Text = struct {
    txt: []u8,
    selected: bool = false,
};

pub const Key = struct {
    code: enums.Key,
    action: enum {
        down,
        repeat,
        up,
    },
    mod: enums.Mod,

    /// True if matches the named keybind (follows Keybind.also).  See `matchKeyBind`.
    pub fn matchBind(self: Key, keybind_name: []const u8) bool {
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

    /// True if matches the named keybind (ignores Keybind.also).  Usually you
    /// want `matchBind`.
    pub fn matchKeyBind(self: Key, kb: enums.Keybind) bool {
        return self.mod.matchKeyBind(kb) and (kb.key != null and kb.key.? == self.code);
    }
};

pub const Mouse = struct {
    pub const Action = union(enum) {
        // Focus events come right before their associated pointer event, usually
        // leftdown/rightdown or motion. Separated to enable changing what
        // causes focus changes.
        focus,
        press,
        release,

        wheel_x: f32,
        wheel_y: f32,

        // motion Point is the change in position
        // if you just want to react to the current mouse position if it got
        // moved at all, use the .position event with mouseTotalMotion()
        motion: dvui.Point.Physical,

        // always a single position event per frame, and it's always after all
        // other events, used to change mouse cursor and do widget highlighting
        // - also useful with mouseTotalMotion() to respond to mouse motion but
        // only at the final location
        // - generally you don't want to mark this as handled, the exception is
        // if you are covering up child widgets and don't want them to react to
        // the mouse hovering over them
        // - instead, call dvui.cursorSet()
        position,
    };

    action: Action,

    // This distinguishes between mouse and touch events.
    // .none is used for mouse wheel and position
    // mouse motion will be a touch or .none
    button: enums.Button,

    mod: enums.Mod,

    p: dvui.Point.Physical,
    floating_win: dvui.WidgetId,
};

/// Event bubbled from inside a scrollarea to ensure scrolling while dragging
/// if the mouse moves to the edge or outside the scrollarea.
///
/// During dragging, a widget should bubble this on each pointer motion event.
pub const ScrollDrag = struct {

    // mouse point from motion event
    mouse_pt: dvui.Point.Physical,

    // rect in screen coords of the widget doing the drag (scrolling will stop
    // if it wouldn't show more of this rect)
    screen_rect: dvui.Rect.Physical,

    // id of the widget that has mouse capture during the drag (needed to
    // inject synthetic motion events into the next frame to keep scrolling)
    capture_id: dvui.WidgetId,
};

/// Event bubbled from inside a scrollarea to scroll to a specific place.
pub const ScrollTo = struct {

    // rect in screen coords we want to be visible (might be outside
    // scrollarea's clipping region - we want to scroll to bring it inside)
    screen_rect: dvui.Rect.Physical,

    // whether to scroll outside the current scroll bounds (useful if the
    // current action might be expanding the scroll area)
    over_scroll: bool = false,
};

/// Event bubbled from a scrollarea when user tries to scroll farther than it
/// can.  Containing scrollareas use this to scroll if they can.
/// Example is scrolling a TextEntry to its top will then scroll the containing
/// page up.
pub const ScrollPropagate = struct {
    /// Motion field from the Mouse event that would have scrolled but we were
    /// at the edge.
    motion: dvui.Point.Physical,
};

test {
    @import("std").testing.refAllDecls(@This());
}
