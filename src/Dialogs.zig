mutex: std.Thread.Mutex = .{},
stack: std.ArrayListUnmanaged(Dialog) = .empty,

const Dialogs = @This();

pub const Dialog = struct {
    id: Id,
    /// Used for subwindow filtering, null means the main window
    subwindow_id: ?Id = null,
    display: DisplayFn,

    pub const DisplayFn = *const fn (Id) anyerror!void;
};

pub const IdMutex = struct {
    id: Id,
    mutex: *std.Thread.Mutex,
};

/// Add a dialog to be displayed on the GUI thread during `Window.end`.
///
/// Returns an locked mutex that **must** be unlocked by the caller. Caller
/// does any `Window.dataSet` calls before unlocking the mutex to ensure that
/// data is available before the dialog is displayed.
///
/// Can be called from any thread.
pub fn add(self: *Dialogs, gpa: std.mem.Allocator, dialog: Dialog) !*std.Thread.Mutex {
    self.mutex.lock();
    errdefer self.mutex.unlock();
    for (self.stack.items) |*d| {
        if (d.id == dialog.id) {
            d.* = dialog;
            break;
        }
    } else {
        try self.stack.append(gpa, dialog);
    }
    return &self.mutex;
}

/// Only called from gui thread.
pub fn remove(self: *Dialogs, id: Id) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    for (self.stack.items, 0..) |*d, i| {
        if (d.id == id) {
            _ = self.stack.orderedRemove(i);
            return;
        }
    }
}

pub const Iterator = struct {
    dialogs: *Dialogs,
    subwindow_id: ?Id,
    i: usize = 0,
    last_id: Id = .zero,

    pub fn next(self: *Iterator) ?Dialog {
        self.dialogs.mutex.lock();
        defer self.dialogs.mutex.unlock();

        // have to deal with toasts possibly removing themselves inbetween
        // calls to next()

        const items = self.dialogs.stack.items;
        if (self.i < items.len and self.last_id == items[self.i].id) {
            // we already did this one, move to the next
            self.i += 1;
        }

        while (self.i < items.len and items[self.i].subwindow_id != self.subwindow_id) {
            self.i += 1;
        }

        if (self.i < items.len) {
            self.last_id = items[self.i].id;
            return items[self.i];
        }

        return null;
    }
};

pub fn iterator(self: *Dialogs, subwindow_id: ?Id) Iterator {
    return .{ .dialogs = self, .subwindow_id = subwindow_id };
}

/// Finds the index of the first dialog with the specific subwindow_id, or null if none exists
pub fn indexOfSubwindow(self: *Dialogs, subwindow_id: ?Id) ?usize {
    self.mutex.lock();
    defer self.mutex.unlock();
    for (self.stack.items, 0..) |dialog, i| {
        if (dialog.subwindow_id == subwindow_id) return i;
    }
    return null;
}

/// Runs the display function for all the current dialogs
pub fn show(self: *Dialogs) void {
    var i: usize = 0;
    var dia: ?Dialog = null;
    while (true) {
        self.mutex.lock();
        if (i < self.stack.items.len and
            dia != null and
            dia.?.id == self.stack.items[i].id)
        {
            // we just did this one, move to the next
            i += 1;
        }

        if (i < self.stack.items.len) {
            dia = self.stack.items[i];
        } else {
            dia = null;
        }
        self.mutex.unlock();

        if (dia) |d| {
            d.display(d.id) catch |err| {
                dvui.log.warn("Dialog {x} got {any} from its display function", .{ d.id, err });
            };
        } else {
            break;
        }
    }
}

pub fn deinit(self: *Dialogs, gpa: std.mem.Allocator) void {
    defer self.* = undefined;
    self.stack.deinit(gpa);
}

const std = @import("std");
const dvui = @import("./dvui.zig");

const Id = dvui.Id;

test {
    @import("std").testing.refAllDecls(@This());
}
