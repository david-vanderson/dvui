const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;
const ArenaAllocator = std.heap.ArenaAllocator;

const log = std.log.scoped(.shrinking_arena);

const InitOptions = struct {
    /// If this is set to `false` all memory returned will
    /// not be reused until `reset` is called.
    reuse_memory: bool = true,
};

///
const NeverFree = struct {
    arena: ArenaAllocator,
    map: std.AutoHashMapUnmanaged([*]u8, [*]u8) = .empty,
    /// This is needed so that we can simulate `has_expanded` if `arena`
    /// fails to remap, which is the only reason `ShrinkingArenaAllocator` would fail
    failed_remap: bool = false,

    fn deinit(self: *NeverFree) void {
        self.arena.deinit();
        self.map.deinit(self.arena.child_allocator);
    }

    fn reset(self: *NeverFree) void {
        self.failed_remap = false;
        _ = self.arena.reset(.retain_capacity);
        self.map.clearRetainingCapacity();
    }
};

/// This is a wrapper of the `ArenaAllocator` that keeps
/// track of the peak memory used in order to retain only
/// the most minimal allocation.
///
/// This is important because dvui applications may allocate
/// large files like images on the arena, but never again for
/// the lifetime of the application. Retaining the capacity
/// for these the large files does no make sense when only
/// a fraction of that is used during a normal frame.
pub fn ShrinkingArenaAllocator(comptime opts: InitOptions) type {
    const has_never_free = !opts.reuse_memory;
    return struct {
        arena: ArenaAllocator,
        peak_usage: usize = 0,
        current_usage: usize = 0,
        last_freed_ptr: ?usize = null,

        never_free: if (has_never_free) NeverFree else void = undefined,

        const Self = @This();

        pub fn init(child_allocator: Allocator) Self {
            return .{
                .arena = .init(child_allocator),
                .never_free = if (has_never_free) .{ .arena = .init(child_allocator) },
            };
        }

        pub fn initArena(arena: ArenaAllocator) Self {
            return .{
                .arena = arena,
                .never_free = if (has_never_free) .{ .arena = .init(arena.child_allocator) },
            };
        }

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
            if (has_never_free) self.never_free.deinit();
            self.* = undefined;
        }

        pub const ResetMode = union(enum) {
            /// Releases all allocated memory in the arena.
            free_all,
            /// This will pre-heat the arena for future allocations by allocating
            /// a large enough buffer for all previously done allocations.
            /// Preheating will speed up the allocation process by invoking
            /// the backing allocator less often than before. If `reset()`
            /// is used in a loop, this means that after the biggest operation,
            /// no memory allocations are performed anymore.
            retain_capacity,
            /// Shrinks the capacity to the peak usage plus some fraction
            /// of the peak usage. This ensures that small variations in
            /// the allocated memory won't cause any new allocations.
            shrink_to_peak_usage,
            /// Shrinks the capacity to exactly the peak amount used. This
            /// means that any additional amount of capacity needed will
            /// cause a new buffer to be allocated by the backing allocator.
            shrink_to_peak_usage_exact,
        };

        /// Resets the inner arena using the strategy decided by `mode`
        ///
        /// The function will return whether the reset operation was
        /// successful or not. If the reallocation failed `false` is
        /// returned. The arena will still be fully functional in that
        /// case, all memory is released. Future allocations just
        /// might be slower.
        pub fn reset(self: *Self, mode: ResetMode) bool {
            defer self.current_usage = 0;
            defer self.peak_usage = 0;
            if (has_never_free) self.never_free.reset();
            const arena_mode: ArenaAllocator.ResetMode = switch (mode) {
                .free_all => .free_all,
                .retain_capacity => .retain_capacity,
                .shrink_to_peak_usage => .{ .retain_with_limit = self.peak_usage + self.peak_usage / 2 },
                .shrink_to_peak_usage_exact => .{ .retain_with_limit = self.peak_usage },
            };
            return self.arena.reset(arena_mode);
        }

        pub fn debug_log(self: *const Self) void {
            log.debug("{x} current used: {d}", .{ @intFromPtr(self), self.current_usage });
            log.debug("{x} peak used: {d}", .{ @intFromPtr(self), self.peak_usage });
            log.debug("{x} arena buf len: {d}", .{ @intFromPtr(self), self.arena.state.buffer_list.len() });
            log.debug("{x} arena capacity: {d}", .{ @intFromPtr(self), self.arena.queryCapacity() });
        }

        pub fn allocator(self: *Self) Allocator {
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
        pub fn allocatorLIFO(self: *Self) Allocator {
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

        pub fn has_expanded(self: *const Self) bool {
            if (has_never_free and self.never_free.failed_remap) return true;
            if (self.arena.state.buffer_list.first) |first| {
                // If there is a second buffer, we expanded past our first
                return first.next != null;
            } else return false;
        }

        /// Attempts to free the given memory and returns an error it failed
        fn attemptFree(self: *Self, in_memory: []u8, alignment: Alignment, ret_addr: usize) !void {
            const memory = if (has_never_free)
                // If the ptr is not in the map, it's likely not allocated by us
                if (self.never_free.map.get(in_memory.ptr)) |ptr| ptr[0..in_memory.len] else in_memory
                // We intentionally do not free `in_memory` from `never_free_arena` and to not remove
                // the entry from `never_free_map` because we might be freeing the first field in a
                // larger struct, so the translation needs to remain
            else
                in_memory;

            // Extend the allocated length to the previous freed allocation
            // to account for padding between allocations
            const index_adjustment = if (self.last_freed_ptr) |ptr|
                @min(ptr -| (@intFromPtr(memory.ptr) + memory.len), Alignment.@"32".toByteUnits())
            else
                0;
            if (self.arena.state.end_index > index_adjustment) {
                self.arena.state.end_index -= index_adjustment;
            }
            errdefer if (self.arena.state.end_index > index_adjustment) {
                self.arena.state.end_index += index_adjustment;
            };

            const end_before = self.arena.state.end_index;

            self.arena.allocator().rawFree(memory, alignment, ret_addr);

            const succeeded = memory.len == 0 or self.arena.state.end_index < end_before;
            if (succeeded) {
                self.current_usage -= memory.len;
                self.last_freed_ptr = @intFromPtr(memory.ptr);
            } else {
                return error.Failed;
            }
        }

        fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return self.attemptAlloc(len, alignment, ret_addr) catch return null;
        }

        fn attemptAlloc(self: *Self, len: usize, alignment: Alignment, ret_addr: usize) Allocator.Error!?[*]u8 {
            const buf = self.arena.allocator().rawAlloc(len, alignment, ret_addr) orelse return null;
            errdefer self.arena.allocator().rawFree(buf[0..len], alignment, ret_addr);

            self.current_usage += len;
            errdefer self.current_usage -= len;
            const prev_peak = self.peak_usage;
            errdefer self.peak_usage = prev_peak;
            self.peak_usage = @max(self.peak_usage, self.current_usage);

            if (has_never_free) {
                const never_free_buf = self.never_free.arena.allocator().rawAlloc(len, alignment, ret_addr) orelse return Allocator.Error.OutOfMemory;
                errdefer self.never_free.arena.allocator().rawFree(never_free_buf[0..len], alignment, ret_addr);

                try self.never_free.map.put(self.never_free.arena.child_allocator, never_free_buf, buf);

                self.last_freed_ptr = null;
                return never_free_buf;
            } else {
                self.last_freed_ptr = null;
                return buf;
            }
        }

        fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.attemptFree(memory, alignment, ret_addr) catch {};
        }

        fn freeLIFO(ctx: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.attemptFree(memory, alignment, ret_addr) catch if (!self.has_expanded()) {
                var addresses: [8]usize = undefined;
                var trace = std.builtin.StackTrace{
                    .index = 0,
                    .instruction_addresses = &addresses,
                };
                std.debug.captureStackTrace(ret_addr, &trace);
                log.debug("Free from lifo arena failed. Somewhere between when this was allocated and this call to free there was another allocation that was not freed first. Stack trace: {f}", .{trace});
            };
        }

        fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
            // NOTE: Calling resize here is only okay because `ArenaAllocator` does the same!
            return if (resize(ctx, memory, alignment, new_len, ret_addr)) memory.ptr else null;
        }

        fn resize(ctx: *anyopaque, in_memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
            const self: *Self = @ptrCast(@alignCast(ctx));

            const memory = if (has_never_free)
                // If the ptr is not in the map, it's likely not allocated by us
                if (self.never_free.map.get(in_memory.ptr)) |ptr| ptr[0..in_memory.len] else in_memory
            else
                in_memory;

            if (self.arena.allocator().rawResize(memory, alignment, new_len, ret_addr)) {
                if (new_len < memory.len) {
                    self.current_usage -= memory.len - new_len;
                } else {
                    self.current_usage += new_len - memory.len;
                    self.peak_usage = @max(self.peak_usage, self.current_usage);
                }

                if (has_never_free and !self.never_free.arena.allocator().rawResize(in_memory, alignment, new_len, ret_addr)) {
                    // reset the size in the normal arena, which should always succeed
                    std.debug.assert(self.arena.allocator().rawResize(memory.ptr[0..new_len], alignment, memory.len, ret_addr));
                    // log.debug("A false negative resize/remap failure was introduced", .{});
                    self.never_free.failed_remap = true;
                    return false;
                }

                return true;
            }

            // Pretend to have allocated memory to the new_len, which should guarantee
            // the allocation of a new buffer on the next call to alloc. If it wouldn't
            // create a new buffer, an ArrayList that is remapping would free it's
            // previous buffer and freeLIFO would log an error
            self.arena.state.end_index += new_len;
            return false;
        }
    };
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "alignment frees" {
    var instance = ShrinkingArenaAllocator(.{}).init(std.testing.allocator);
    defer instance.deinit();
    const arena = instance.allocatorLIFO();

    const byte = try arena.create(u8);
    const int = try arena.create(u32);
    arena.destroy(int);
    const second_byte = try arena.create(u8);
    arena.destroy(second_byte);
    // There are padding bytes above the first byte
    try std.testing.expect(@sizeOf(u8) < instance.arena.state.end_index);
    arena.destroy(byte);
    try std.testing.expectEqual(0, instance.current_usage);
    try std.testing.expectEqual(0, instance.arena.state.end_index);
}

test "alignment frees multiple buffers" {
    var instance = ShrinkingArenaAllocator(.{}).init(std.testing.allocator);
    defer instance.deinit();
    const arena = instance.allocatorLIFO();

    const byte = try arena.create(u8);
    const int = try arena.create(u32);
    arena.destroy(int);
    // Force second buffer to be allocated
    const large = try arena.alloc(u8, 1000);
    arena.free(large);
    try std.testing.expect(instance.has_expanded());
    const second_byte = try arena.create(u8);
    arena.destroy(second_byte);
    // This free should fail
    arena.destroy(byte);
    try std.testing.expectEqual(1, instance.current_usage);
}
