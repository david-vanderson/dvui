//! This is a wrapper of the `ArenaAllocator` that keeps
//! track of the peak memory used in order to retain only
//! the most minimal allocation.
//!
//! This is important because dvui applications may allocate
//! large files like images on the arena, but never again for
//! the lifetime of the application. Retaining the capacity
//! for these the large files does no make sense when only
//! a fraction of that is used during a normal frame.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;
const ArenaAllocator = std.heap.ArenaAllocator;

const ShrinkingArenaAllocator = @This();

const allowed_extra_capacity = 0x1000;

arena: ArenaAllocator,
peak_usage: usize = 0,
current_usage: usize = 0,

pub fn init(child_allocator: Allocator) ShrinkingArenaAllocator {
    return .{ .arena = .init(child_allocator) };
}

pub fn deinit(self: ShrinkingArenaAllocator) void {
    self.arena.deinit();
}

/// Resets the inner arena, limiting the retained capacity to
/// the peak amount used + the extra allowed capacity
///
/// The function will return whether the reset operation was
/// successful or not. If the reallocation failed `false` is
/// returned. The arena will still be fully functional in that
/// case, all memory is released. Future allocations just
/// might be slower.
pub fn reset(self: *ShrinkingArenaAllocator, kind: enum { retain_capacity, shrink_to_peak_usage }) bool {
    defer self.current_usage = 0;
    defer self.peak_usage = 0;
    return switch (kind) {
        .retain_capacity => self.arena.reset(.retain_capacity),
        .shrink_to_peak_usage => self.arena.reset(.{ .retain_with_limit = self.peak_usage + allowed_extra_capacity }),
    };
}

pub fn debug_log(self: *const ShrinkingArenaAllocator) void {
    std.log.debug("{*} current used: {d}", .{ self, self.current_usage });
    std.log.debug("{*} peak used: {d}", .{ self, self.peak_usage });
    std.log.debug("{*} arena buf len: {d}", .{ self, self.arena.state.buffer_list.len() });
    std.log.debug("{*} arena capacity: {d}", .{ self, self.arena.queryCapacity() });
}

pub fn allocator(self: *ShrinkingArenaAllocator) Allocator {
    return .{
        .ptr = self,
        .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .remap = remap,
            .free = free,
        },
    };
}

/// This version of the allocator enforces that all calls to
/// free succeeds, meaning all allocations and frees are
/// performed in the order of last allocated, first freed.
///
/// This is most easily achieved by immidietly deferring the
/// freeing of allocated memory.
pub fn allocatorLIFO(self: *ShrinkingArenaAllocator) Allocator {
    return .{
        .ptr = self,
        .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .remap = remap,
            .free = freeLIFO,
        },
    };
}

pub fn has_expanded(self: *const ShrinkingArenaAllocator) bool {
    if (self.arena.state.buffer_list.first) |first| {
        // If there is a second buffer, we expanded past our first
        return first.next != null;
    } else return false;
}

/// Attempts to free the given memory and returns whether it
/// succeeded or not.
fn attemptFree(self: *ShrinkingArenaAllocator, memory: []u8, alignment: Alignment, ret_addr: usize) bool {
    const end_before = self.arena.state.end_index;
    self.arena.allocator().rawFree(memory, alignment, ret_addr);

    if (memory.len == 0) {
        // The allocation had no bytes, so cannot fail freeing
        return true;
    }

    if (!self.has_expanded()) {
        // Attempt to free acounting for alignment padding of allocations after the current one
        var align_diff: usize = 8;
        while (self.arena.state.end_index == end_before and align_diff > 0) : (align_diff >>= 1) {
            var mem = memory;
            mem.len = std.mem.alignForward(usize, @intFromPtr(memory.ptr) + memory.len, align_diff) - @intFromPtr(memory.ptr);
            self.arena.allocator().rawFree(mem, alignment, ret_addr);
        }
    }
    const succeeded = self.arena.state.end_index < end_before;
    if (succeeded) {
        self.current_usage -= memory.len;
    }
    return succeeded;
}

fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
    const self: *ShrinkingArenaAllocator = @ptrCast(@alignCast(ctx));
    const buf = self.arena.allocator().rawAlloc(len, alignment, ret_addr) orelse return null;
    self.current_usage += len;
    self.peak_usage = @max(self.peak_usage, self.current_usage);
    return buf;
}

fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
    const self: *ShrinkingArenaAllocator = @ptrCast(@alignCast(ctx));
    _ = self.attemptFree(memory, alignment, ret_addr);
}

fn freeLIFO(ctx: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
    const self: *ShrinkingArenaAllocator = @ptrCast(@alignCast(ctx));
    if (!self.attemptFree(memory, alignment, ret_addr) and !self.has_expanded()) {
        var addresses: [8]usize = undefined;
        var trace = std.builtin.StackTrace{
            .index = 0,
            .instruction_addresses = &addresses,
        };
        std.debug.captureStackTrace(ret_addr, &trace);
        std.log.debug("Free from lifo arena failed. Somewhere between when this was allocated and this call to free there was another allocation that was not freed first. Stack trace: {}", .{trace});
    }
}

fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    const self: *ShrinkingArenaAllocator = @ptrCast(@alignCast(ctx));
    const end_before = self.arena.state.end_index;
    const buf = self.arena.allocator().rawRemap(memory, alignment, new_len, ret_addr) orelse return null;
    if (self.arena.state.end_index != end_before) {
        if (new_len < memory.len) {
            self.current_usage -= memory.len - new_len;
        } else {
            self.current_usage += new_len - memory.len;
            self.peak_usage = @max(self.peak_usage, self.current_usage);
        }
    }
    return buf;
}

fn resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
    const self: *ShrinkingArenaAllocator = @ptrCast(@alignCast(ctx));
    if (self.arena.allocator().rawResize(memory, alignment, new_len, ret_addr)) {
        if (new_len < memory.len) {
            self.current_usage -= memory.len - new_len;
        } else {
            self.current_usage += new_len - memory.len;
            self.peak_usage = @max(self.peak_usage, self.current_usage);
        }
        return true;
    } else {
        return false;
    }
}

test {
    @import("std").testing.refAllDecls(@This());
}
