//! A wrapper around an arena allocator that enforces that
//! memory is freed like a stack. i.e. in LIFO order
//!
//! The widget stack can be queried to determine if any
//! pointer is an element of the stack.

const std = @import("std");
const dvui = @import("dvui.zig");

arena: std.heap.ArenaAllocator = undefined,
allocations: std.ArrayList(*anyopaque) = .empty,

const WidgetStack = @This();

pub fn init(gpa: std.mem.Allocator) WidgetStack {
    return .{
        .arena = .init(gpa),
    };
}

pub fn deinit(self: *WidgetStack) void {
    const window: *const dvui.Window = @alignCast(@fieldParentPtr("_widget_stack", self));
    self.allocations.deinit(window.gpa);
    _ = self.arena.reset(.free_all);
}

/// Forget all widget allocations.
/// Reset the widget stack arena according to `mode`
pub fn reset(self: *WidgetStack, mode: std.heap.ArenaAllocator.ResetMode) void {
    self.allocations.clearRetainingCapacity();
    _ = self.arena.reset(mode);
}

/// Create a widget and remember it.
pub fn create(self: *WidgetStack, T: type) *T {
    const window: *const dvui.Window = @alignCast(@fieldParentPtr("_widget_stack", self));
    const result = self.arena.allocator().create(T) catch @panic("OOM");
    self.allocations.append(window.gpa, result) catch @panic("OOM");
    return result;
}

/// Destroy a widget
///
/// Check that widget was created by this widget stack and
/// that it is at the top of the stack.
pub fn destroy(self: *WidgetStack, ptr: anytype) void {
    if (self.allocations.items.len == 0) {
        dvui.log.err("Attempt to free widget {*} from an empty widget stack", .{ptr});
        return;
    }
    if (!self.created(ptr)) {
        dvui.log.err("Attempt to free widget {*} but it was not allocated by the widget stack", .{ptr});
        return;
    } else if (self.allocations.items[self.allocations.items.len - 1] != @as(*anyopaque, @ptrCast(ptr))) {
        dvui.log.err("Attempt to free widget {*}, but it is not at the top of the widget stack", .{ptr});
        return;
    }

    _ = self.allocations.orderedRemove(self.allocations.items.len - 1);
    self.arena.allocator().destroy(ptr);
}

/// Returns whether this pointer belongs to a widget created by
/// the widget stack.
pub fn created(self: *const WidgetStack, ptr: *anyopaque) bool {
    if (self.allocations.items.len == 0) return false;
    var idx: usize = self.allocations.items.len;
    while (idx > 0) : (idx -= 1) {
        if (self.allocations.items[idx - 1] == ptr) return true;
    }
    return false;
}
