const dvui = @import("dvui.zig");
const std = @import("std");

const enums = dvui.enums;

const Event = @This();

pub const EventTypes = union(enum) {
    mouse: Mouse,
    key: Key,
    text: Text,
    window: Window,
    app: App,
};

/// Should not be set directly, use the `handle` method
handled: bool = false,

/// For key events these represents focus. For mouse events widgetId represents
/// capture, windowId unused.
target_windowId: ?dvui.Id = null,
target_widgetId: ?dvui.Id = null,

// num increments within a frame, used in focusRemainingEvents
num: u16 = 0,

evt: EventTypes,

pub fn format(self: *const Event, writer: *std.Io.Writer) !void {
    try writer.print("Event({d}){{{s} ", .{ self.num, @tagName(self.evt) });
    switch (self.evt) {
        .mouse => |me| try writer.print("{s}}}", .{@tagName(me.action)}),
        .key => |ke| try writer.print("{s}}}", .{@tagName(ke.action)}),
        .text => try writer.print("}}", .{}),
        .window => |w| try writer.print("{s}}}", .{@tagName(w.action)}),
        .app => |a| try writer.print("{s}}}", .{@tagName(a.action)}),
    }
}

/// Mark the event as handled
///
/// In general, the `dvui.WidgetData` passed here should be the same one that
/// matched this event, using `dvui.matchEvent` or similar.
/// This makes it possible to see which widget handled the event.
pub fn handle(self: *Event, src: std.builtin.SourceLocation, wd: *const dvui.WidgetData) void {
    if (dvui.currentWindow().debug.logEvents(null)) {
        dvui.log.debug("{s}:{d} {f} handled by {s} ({x})", .{ src.file, src.line, self, wd.options.name orelse "???", wd.id });
    }
    self.handled = true;
}

pub const Text = struct {
    txt: []u8,
    selected: bool = false,
    replace: bool = false,
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
    // .none is used for mouse wheel and position and focus (when focus comes
    // from an accessibility action)
    // mouse motion will be a touch or .none
    button: enums.Button,

    mod: enums.Mod,

    p: dvui.Point.Physical,
    floating_win: dvui.Id,
};

pub const Window = struct {
    pub const Action = enum {
        /// User clicked close (or did something) so the window manager is
        /// telling this window to close.
        close,
    };

    action: Action,
};

pub const App = struct {
    pub const Action = enum {
        /// App as a whole is requested to quit.  Usually this is just behind
        /// the Window close event for the last remaining OS window.
        quit,
    };

    action: Action,
};

test {
    @import("std").testing.refAllDecls(@This());
}
