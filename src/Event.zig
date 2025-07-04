const dvui = @import("dvui.zig");
const std = @import("std");

const enums = dvui.enums;

const Event = @This();

/// Should not be set directly, use the `handle` method
handled: bool = false,

/// For key events these represents focus. For mouse events widgetId represents
/// capture, windowId unused.
target_windowId: ?dvui.WidgetId = null,
target_widgetId: ?dvui.WidgetId = null,

// num increments within a frame, used in focusRemainingEvents
num: u16 = 0,
evt: union(enum) {
    mouse: Mouse,
    key: Key,
    text: Text,
},

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

test {
    @import("std").testing.refAllDecls(@This());
}
