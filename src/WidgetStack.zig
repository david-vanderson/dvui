//! A wrapper around an arena allocator which enforces that
//! memory is freed like a stack. i.e. in LIFO order
//!
//! The widget stack can be queried to determine if any
//! pointer is an element of the stack using `created()`.

const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui.zig");

const DebugInfo = struct {
    ptr: *anyopaque,
    name: if (builtin.mode == .Debug) []const u8 else void,
};

arena: std.heap.ArenaAllocator = undefined,
allocations: std.ArrayList(DebugInfo) = .empty,

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
    self.allocations.append(window.gpa, .{ .ptr = result, .name = if (builtin.mode == .Debug) @typeName(T) else {} }) catch @panic("OOM");
    return result;
}

/// Destroy a widget
///
/// Check that widget was created by this widget stack and
/// that it is at the top of the stack.
pub fn destroy(self: *WidgetStack, ptr: anytype) void {
    if (self.allocations.items.len == 0) {
        dvui.log.debug("Attempt to free widget {*} from an empty widget stack", .{ptr});
        return;
    }
    if (!self.created(ptr)) {
        dvui.log.debug("Attempt to free widget {*} but it was not allocated by the widget stack", .{ptr});
        return;
    } else if (self.allocations.items[self.allocations.items.len - 1].ptr != @as(*anyopaque, @ptrCast(ptr))) {
        dvui.log.debug("Attempt to free widget {*}, but it is not at the top of the widget stack", .{ptr});
        if (builtin.mode == .Debug) {
            var i = self.allocations.items.len;
            while (i > 0) : (i -= 1) {
                const di = self.allocations.items[i - 1];
                if (di.ptr == @as(*anyopaque, @ptrCast(ptr))) break;
                dvui.log.debug("  {*} {s} not freed", .{ di.ptr, di.name });
            }
        }
        return;
    }

    _ = self.allocations.orderedRemove(self.allocations.items.len - 1);

    self.arena.allocator().destroy(ptr);
}

/// Returns whether this pointer belongs to a widget created by
/// the widget stack.
pub fn created(self: *const WidgetStack, ptr: *anyopaque) bool {
    var itr = std.mem.reverseIterator(self.allocations.items);
    while (itr.next()) |alloc_ptr| {
        if (alloc_ptr.ptr == ptr) return true;
    }
    return false;
}
