/// list of subwindows including base, later windows are on top of earlier
/// windows
stack: std.ArrayList(Subwindow) = .empty,
/// id of the subwindow widgets are being added to
current_id: Id = .zero,
/// natural rect of the last subwindow, dialogs use this
/// to center themselves
current_rect: Rect.Natural = .{},
/// id of the subwindow that has focus
focused_id: Id = .zero,

const Subwindows = @This();

pub const Subwindow = struct {
    id: Id,
    rect: Rect,
    rect_pixels: Rect.Physical,
    focused_widget_id: ?Id = null,
    /// Uses `arena` allocator
    render_cmds: std.ArrayList(dvui.RenderCommand) = .empty,
    /// Uses `arena` allocator
    render_cmds_after: std.ArrayList(dvui.RenderCommand) = .empty,
    used: bool = true,
    modal: bool = false,
    stay_above_parent_window: ?Id = null,
    mouse_events: bool = true,
};

pub fn add(self: *Subwindows, gpa: std.mem.Allocator, id: Id, rect: Rect, rect_pixels: Rect.Physical, modal: bool, stay_above_parent_window: ?Id, mouse_events: bool) !void {
    if (self.get(id)) |sw| {
        if (sw.render_cmds.items.len > 0 or sw.render_cmds_after.items.len > 0) {
            dvui.log.warn("subwindowAdd {x} is clearing some drawing commands (did you try to draw between subwindowCurrentSet and subwindowAdd?)\n", .{id});
        }
        // this window was here previously, just update data, so it stays in the same place in the stack
        sw.used = true;
        sw.rect = rect;
        sw.rect_pixels = rect_pixels;
        sw.modal = modal;
        sw.stay_above_parent_window = stay_above_parent_window;
        sw.mouse_events = mouse_events;

        sw.render_cmds.clearRetainingCapacity();
        sw.render_cmds_after.clearRetainingCapacity();
        return;
    }
    // haven't seen this window before
    const sw = Subwindow{
        .id = id,
        .rect = rect,
        .rect_pixels = rect_pixels,
        .modal = modal,
        .stay_above_parent_window = stay_above_parent_window,
        .mouse_events = mouse_events,
    };
    if (stay_above_parent_window) |subwin_id| {
        // it wants to be above subwin_id
        var i: usize = 0;
        while (i < self.stack.items.len and self.stack.items[i].id != subwin_id) {
            i += 1;
        }
        if (i < self.stack.items.len) {
            i += 1;
        }
        // i points just past subwin_id, go until we run out of subwindows that want to be on top of this subwin_id
        while (i < self.stack.items.len and self.stack.items[i].stay_above_parent_window == subwin_id) {
            i += 1;
        }
        // i points just past all subwindows that want to be on top of this subwin_id
        try self.stack.insert(gpa, i, sw);
    } else {
        // just put it on the top
        try self.stack.append(gpa, sw);
    }
}

/// Return the previous current values
pub fn setCurrent(self: *Subwindows, id: Id, rect: ?Rect.Natural) struct { Id, Rect.Natural } {
    defer { // Set the new values after returning the previous
        self.current_id = id;
        if (rect) |r| self.current_rect = r;
    }
    return .{ self.current_id, self.current_rect };
}

pub fn raise(self: *Subwindows, id: Id) error{CouldNotFindSubwindow}!void {
    // don't check against subwindows[0] - that's that main window
    const items = self.stack.items[1..];
    for (items, 0..) |sw, i| {
        if (sw.id == id) {
            if (sw.stay_above_parent_window != null) {
                //std.debug.print("raiseSubwindow: tried to raise a subwindow {x} with stay_above_parent_window set\n", .{subwindow_id});
                return;
            }
            if (i == (items.len - 1)) {
                // already on top
                return;
            }
            // move it to the end, also move any stay_above_parent_window subwindows
            // directly on top of it as well - we know from above that the
            // first window does not have stay_above_parent_window so this loop ends
            var first = true;
            while (first or items[i].stay_above_parent_window != null) {
                first = false;
                const item = items[i];
                for (items[i..(items.len - 1)], 0..) |*b, k| {
                    b.* = items[i + 1 + k];
                }
                items[items.len - 1] = item;
            }
            return;
        }
    }
    return error.CouldNotFindSubwindow;
}

pub fn windowFor(self: *const Subwindows, p: Point.Physical) Id {
    var i = self.stack.items.len;
    while (i > 0) : (i -= 1) {
        const sw = &self.stack.items[i - 1];
        if (sw.mouse_events and (sw.modal or sw.rect_pixels.contains(p))) {
            return sw.id;
        }
    }
    return .zero;
}

pub fn current(self: *Subwindows) ?*Subwindow {
    return self.get(self.current_id);
}

pub fn focused(self: *Subwindows) ?*Subwindow {
    return self.get(self.focused_id);
}

/// Iterates the subwindows from the top of the stack (last item in the array)
pub fn get(self: *Subwindows, id: Id) ?*Subwindow {
    var i = self.stack.items.len;
    while (i > 0) : (i -= 1) {
        const sw = &self.stack.items[i - 1];
        if (sw.id == id) return sw;
    }
    return null;
}

/// Removes all subwindows that were not used ((re)added) since the last call to `reset`
pub fn reset(self: *Subwindows) void {
    var i = self.stack.items.len;
    while (i > 0) : (i -= 1) {
        const sw = &self.stack.items[i - 1];
        if (sw.used) {
            sw.used = false;
        } else {
            _ = self.stack.orderedRemove(i);
        }
    }
}

pub fn deinit(self: *Subwindows, gpa: std.mem.Allocator) void {
    defer self.* = undefined;
    self.stack.deinit(gpa);
}

const std = @import("std");
const dvui = @import("./dvui.zig");

const Id = dvui.Id;
const Rect = dvui.Rect;
const Point = dvui.Point;
const RenderCommand = dvui.RenderCommand;

test {
    @import("std").testing.refAllDecls(@This());
}
