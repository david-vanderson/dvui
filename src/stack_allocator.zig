//! A Last In Last Out (LIFO) Stack Allocator, based on `std.heap.ArenaAllocator`
//! with added support for freeing all memory like a stack.
//!
//! Remapping an resizing has limited support, meaning nothing but the last
//! allocation can be resized or remapped. This means using array lists will
//! cripple this allocator if it ever returns `error.OutOfMemory`, but should
//! work one at a time without issue.
//!
//! If the memory order is not upheld, a trace will be printed to the offending
//! allocations to show the order they should be freed. Freeing out-of-order
//! will attempt to reset when debugging is active, but will fail to free
//! when debug is disabled. Therefor all freeing errors needs to be addressed
//! for use without debug enabled.

const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Allocator = std.mem.Allocator;

// Comptime configurations
// TODO: Make these available as generic params out build options
const debug = builtin.mode == .Debug;
const stack_trace_frames = if (builtin.is_test) 3 else 8;

const log = if (!builtin.is_test)
    std.log.scoped(.stack_allocator)
else
    struct {
        const default = std.log.scoped(.stack_allocator);
        pub fn err(comptime format: []const u8, args: anytype) void {
            // Downgrade error logs to not fail tests
            default.warn(format, args);
        }
        pub fn warn(comptime format: []const u8, args: anytype) void {
            default.warn(format, args);
        }
        pub fn info(comptime format: []const u8, args: anytype) void {
            default.info(format, args);
        }
        pub fn debug(comptime format: []const u8, args: anytype) void {
            default.debug(format, args);
        }
    };

/// This allocator takes an existing allocator, wraps it, and provides an interface where
/// you can allocate and then free it all together. Calls to free an individual item only
/// free the item if it was the most recent allocation, otherwise calls to free do
/// nothing.
pub const StackAllocator = struct {
    child_allocator: Allocator,
    buffer_list: BufList = .{},
    // If we are freeing items, we want to be able to point the current index
    // to an earlier node. If this is null, use the first node in the buf list
    current_node: ?*BufNode = null,
    last_freed_alignment: mem.Alignment = .@"1",

    meta: if (debug) std.ArrayListUnmanaged(DebugMeta) = if (debug) .empty else {},

    const DebugMeta = struct {
        item_buf: []u8,
        alignment: mem.Alignment,
        alloc_trace: [stack_trace_frames]usize = undefined,

        fn captureTrace(self: *DebugMeta, start_addr: usize) void {
            var trace = std.builtin.StackTrace{
                .instruction_addresses = &self.alloc_trace,
                .index = 0,
            };
            std.debug.captureStackTrace(start_addr, &trace);
        }

        const Printer = struct {
            metas: []const DebugMeta,

            pub fn format(self: *const Printer, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
                for (0..self.metas.len) |i| {
                    var meta = self.metas[self.metas.len - 1 - i];
                    const trace = std.builtin.StackTrace{
                        .instruction_addresses = &meta.alloc_trace,
                        .index = mem.indexOfScalar(usize, &meta.alloc_trace, 0) orelse meta.alloc_trace.len,
                    };
                    try std.fmt.format(writer, "\nItem {d}: {}\n", .{ i, trace });
                }
            }
        };
    };

    pub fn allocator(self: *StackAllocator) Allocator {
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

    const BufList = std.DoublyLinkedList(struct { len: u32, end_index: u32 = 0 });

    const BufNode = BufList.Node;
    const BufNode_alignment: mem.Alignment = .fromByteUnits(@alignOf(BufNode));

    pub fn init(child_allocator: Allocator) StackAllocator {
        return .{ .child_allocator = child_allocator };
    }

    pub fn deinit(self: *StackAllocator) void {
        // NOTE: When changing this, make sure `reset()` is adjusted accordingly!

        var it = self.buffer_list.first;
        while (it) |node| {
            // this has to occur before the free because the free frees node
            const next_it = node.next;
            const alloc_buf = @as([*]u8, @ptrCast(node))[0..node.data.len];
            self.child_allocator.rawFree(alloc_buf, BufNode_alignment, @returnAddress());
            it = next_it;
        }

        if (debug) {
            self.meta.deinit(self.child_allocator);
        }
    }

    pub const ResetMode = union(enum) {
        /// Releases all allocated memory in the arena.
        free_all,
        /// This will pre-heat the arena for future allocations by allocating a
        /// large enough buffer for all previously done allocations.
        /// Preheating will speed up the allocation process by invoking the backing allocator
        /// less often than before. If `reset()` is used in a loop, this means that after the
        /// biggest operation, no memory allocations are performed anymore.
        retain_capacity,
        /// This is the same as `retain_capacity`, but the memory will be shrunk to
        /// this value if it exceeds the limit.
        retain_with_limit: usize,
    };
    /// Queries the current memory use of this arena.
    /// This will **not** include the storage required for internal keeping.
    pub fn queryCapacity(self: StackAllocator) usize {
        var size: usize = 0;
        var it = self.buffer_list.first;
        while (it) |node| : (it = node.next) {
            // Compute the actually allocated size excluding the
            // linked list node.
            size += node.data.len - @sizeOf(BufNode);
        }
        return size;
    }
    /// Resets the allocator and frees all allocated memory.
    ///
    /// `mode` defines how the currently allocated memory is handled.
    /// See the variant documentation for `ResetMode` for the effects of each mode.
    ///
    /// The function will return whether the reset operation was successful or not.
    /// If the reallocation  failed `false` is returned. The arena will still be fully
    /// functional in that case, all memory is released. Future allocations just might
    /// be slower.
    ///
    /// NOTE: If `mode` is `free_all`, the function will always return `true`.
    pub fn reset(self: *StackAllocator, mode: ResetMode) bool {
        // Some words on the implementation:
        // The reset function can be implemented with two basic approaches:
        // - Counting how much bytes were allocated since the last reset, and storing that
        //   information in State. This will make reset fast and alloc only a teeny tiny bit
        //   slower.
        // - Counting how much bytes were allocated by iterating the chunk linked list. This
        //   will make reset slower, but alloc() keeps the same speed when reset() as if reset()
        //   would not exist.
        //
        // The second variant was chosen for implementation, as with more and more calls to reset(),
        // the function will get faster and faster. At one point, the complexity of the function
        // will drop to amortized O(1), as we're only ever having a single chunk that will not be
        // reallocated, and we're not even touching the backing allocator anymore.
        //
        // Thus, only the first hand full of calls to reset() will actually need to iterate the linked
        // list, all future calls are just taking the first node, and only resetting the `end_index`
        // value.

        if (debug and self.meta.items.len > 0) {
            log.err("Not all allocations were freed before resetting the allocator. These allocations remained: {}", .{DebugMeta.Printer{ .metas = self.meta.items }});
            self.meta.clearRetainingCapacity();
        }

        const requested_capacity = switch (mode) {
            .retain_capacity => self.queryCapacity(),
            .retain_with_limit => |limit| @min(limit, self.queryCapacity()),
            .free_all => 0,
        };
        if (requested_capacity == 0) {
            // just reset when we don't have anything to reallocate
            self.deinit();
            self.* = .{ .child_allocator = self.child_allocator };
            return true;
        }
        const total_size = requested_capacity + @sizeOf(BufNode);
        // Free all nodes except for the last one
        var it = self.buffer_list.first;
        const maybe_first_node = while (it) |node| {
            // this has to occur before the free because the free frees node
            const next_it = node.next;
            if (next_it == null)
                break node;
            self.buffer_list.remove(node);
            const alloc_buf = @as([*]u8, @ptrCast(node))[0..node.data.len];
            self.child_allocator.rawFree(alloc_buf, BufNode_alignment, @returnAddress());
            it = next_it;
        } else null;
        std.debug.assert(maybe_first_node == null or maybe_first_node.?.next == null);
        // reset the state before we try resizing the buffers, so we definitely have reset the arena to 0.
        self.current_node = null;
        if (debug) self.meta.clearAndFree(self.child_allocator);
        if (maybe_first_node) |first_node| {
            first_node.data.end_index = 0;
            self.buffer_list.first = first_node;
            // perfect, no need to invoke the child_allocator
            if (first_node.data.len == total_size)
                return true;
            const first_alloc_buf = @as([*]u8, @ptrCast(first_node))[0..first_node.data.len];
            if (self.child_allocator.rawResize(first_alloc_buf, BufNode_alignment, total_size, @returnAddress())) {
                // successful resize
                first_node.data.len = @intCast(total_size);
            } else {
                // manual realloc
                const new_ptr = self.child_allocator.rawAlloc(total_size, BufNode_alignment, @returnAddress()) orelse {
                    // we failed to preheat the arena properly, signal this to the user.
                    return false;
                };
                self.child_allocator.rawFree(first_alloc_buf, BufNode_alignment, @returnAddress());
                const node: *BufNode = @ptrCast(@alignCast(new_ptr));
                node.* = .{ .data = .{ .len = @intCast(total_size) } };
                self.buffer_list.first = node;
            }
        }
        return true;
    }

    pub fn ownsSlice(self: *StackAllocator, buf: []const u8) bool {
        var node = self.current();
        while (node != null) : (node = node.?.next) {
            const node_buf = @as([*]u8, @ptrCast(node.?))[@sizeOf(BufNode)..node.?.data.len];
            if (sliceContainsSlice(node_buf, buf)) {
                return true;
            }
        }
        return false;
    }

    fn createNode(self: *StackAllocator, prev_len: usize, minimum_size: usize) ?*BufNode {
        const actual_min_size = minimum_size + (@sizeOf(BufNode) + mem.Alignment.@"16".toByteUnits());
        const big_enough_len = prev_len + actual_min_size;
        const len = big_enough_len + big_enough_len / 2;
        const ptr = self.child_allocator.rawAlloc(len, BufNode_alignment, @returnAddress()) orelse
            return null;
        const buf_node: *BufNode = @ptrCast(@alignCast(ptr));
        buf_node.* = .{ .data = .{ .len = @intCast(len) } };
        self.buffer_list.prepend(buf_node);
        self.current_node = null;
        return buf_node;
    }

    fn current(self: *StackAllocator) ?*BufNode {
        return self.current_node orelse self.buffer_list.first;
    }

    fn alloc(ctx: *anyopaque, n: usize, alignment: mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *StackAllocator = @ptrCast(@alignCast(ctx));

        const ptr_align = alignment.toByteUnits();
        var cur_node = if (self.current()) |node|
            node
        else
            (self.createNode(0, n + ptr_align) orelse return null);
        while (true) {
            const cur_alloc_buf = @as([*]u8, @ptrCast(cur_node))[0..cur_node.data.len];
            const cur_buf = cur_alloc_buf[@sizeOf(BufNode)..];
            const addr = @intFromPtr(cur_buf.ptr) + cur_node.data.end_index;
            const adjusted_addr = mem.alignForward(usize, addr, alignment.toByteUnits());
            const adjusted_index = @as(usize, @intCast(cur_node.data.end_index)) + (adjusted_addr - addr);
            const new_end_index = adjusted_index + n;

            if (new_end_index <= cur_buf.len) {
                const result = cur_buf[adjusted_index..new_end_index];

                if (debug) {
                    // FIXME: Should this fail the allocation or can we maybe
                    //        continue without the meta data?
                    const meta = self.meta.addOne(self.child_allocator) catch return null;
                    meta.* = .{ .item_buf = result, .alignment = alignment };
                    meta.captureTrace(ret_addr);
                }

                self.current_node = cur_node;
                cur_node.data.end_index = @intCast(new_end_index);
                return result.ptr;
            }

            const bigger_buf_size = @sizeOf(BufNode) + new_end_index;
            if (self.child_allocator.rawResize(cur_alloc_buf, BufNode_alignment, bigger_buf_size, @returnAddress())) {
                cur_node.data.len = @intCast(bigger_buf_size);
            } else if (cur_node.prev) |node| {
                cur_node = node;
            } else {
                // Allocate a new node if that's not possible
                cur_node = self.createNode(cur_buf.len, n + ptr_align) orelse return null;
            }
        }
    }

    fn resize(ctx: *anyopaque, buf: []u8, alignment: mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *StackAllocator = @ptrCast(@alignCast(ctx));
        _ = alignment;
        _ = ret_addr;

        const cur_node = self.current() orelse return false;
        const cur_alloc_buf = @as([*]u8, @ptrCast(cur_node))[0..cur_node.data.len];
        const cur_buf = cur_alloc_buf[@sizeOf(BufNode)..];
        if (@intFromPtr(cur_buf.ptr) + cur_node.data.end_index != @intFromPtr(buf.ptr) + buf.len) {
            // It's not the most recent allocation, so because we
            // need to be able to free, we cannot even shrink
            return false;
        }
        if (buf.len >= new_len) {
            cur_node.data.end_index -= @intCast(buf.len - new_len);
            if (debug) self.meta.items[self.meta.items.len - 1].item_buf.len = new_len;
            return true;
        } else if (cur_buf.len - cur_node.data.end_index >= new_len - buf.len) {
            cur_node.data.end_index += @intCast(new_len - buf.len);
            if (debug) self.meta.items[self.meta.items.len - 1].item_buf.len = new_len;
            return true;
        } else {
            // Try to expand the current buffer
            const bigger_size = cur_alloc_buf.len + (new_len - buf.len);
            if (self.child_allocator.rawResize(cur_alloc_buf, BufNode_alignment, bigger_size, @returnAddress())) {
                cur_node.data.len = @intCast(bigger_size);
                cur_node.data.end_index += @intCast(new_len - buf.len);
                if (debug) self.meta.items[self.meta.items.len - 1].item_buf.len = new_len;
                return true;
            }
            return false;
        }
    }

    fn remap(ctx: *anyopaque, buf: []u8, alignment: mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *StackAllocator = @ptrCast(@alignCast(ctx));
        return if (resize(ctx, buf, alignment, new_len, ret_addr)) buf.ptr else {
            const cur_node = self.current() orelse return null;
            const cur_buf = @as([*]u8, @ptrCast(cur_node))[@sizeOf(BufNode)..cur_node.data.len];
            // If we are not the last allocation, there is nothing we can do.
            if (@intFromPtr(cur_buf.ptr) + cur_node.data.end_index != @intFromPtr(buf.ptr) + buf.len) return null;

            // Resize failed so we know this will create a new buffer
            const new_buf = alloc(ctx, new_len, alignment, ret_addr) orelse return null;
            std.debug.assert(cur_node != self.current());
            @memcpy(new_buf, buf);
            // "free" the data from the previous buffer
            cur_node.data.end_index = @intCast(@intFromPtr(buf.ptr) - @intFromPtr(cur_buf.ptr));

            if (debug) {
                // remove meta added by alloc
                _ = self.meta.pop();
                const meta = &self.meta.items[self.meta.items.len - 1];
                meta.item_buf = new_buf[0..new_len];
                std.debug.assert(meta.alignment.compare(.eq, alignment));
            }
            return new_buf;
        };
    }

    fn free(ctx: *anyopaque, buf: []u8, alignment: mem.Alignment, ret_addr: usize) void {
        const self: *StackAllocator = @ptrCast(@alignCast(ctx));

        const cur_node = self.current() orelse return;
        const cur_buf = @as([*]u8, @ptrCast(cur_node))[@sizeOf(BufNode)..cur_node.data.len];

        const end_index, const aligned_end_index = if (sliceContainsSlice(cur_buf, buf)) blk: {
            const start_index = @intFromPtr(buf.ptr) - @intFromPtr(cur_buf.ptr);
            const end_index = start_index + buf.len;
            break :blk .{
                end_index,
                mem.alignForward(usize, start_index + buf.len, self.last_freed_alignment.toByteUnits()),
            };
        } else .{ null, null };

        // We check again unaligned end index as well incase the allocation before
        // made us switch buffers and thus didn't affect the alignment of the current buffer
        if (cur_node.data.end_index == aligned_end_index or cur_node.data.end_index == end_index) {
            self.last_freed_alignment = alignment;
            cur_node.data.end_index = @intCast(@intFromPtr(buf.ptr) - @intFromPtr(cur_buf.ptr));
            @memset(buf, undefined);

            const start_of_buf = mem.alignForward(usize, @intFromPtr(cur_buf.ptr), alignment.toByteUnits()) - @intFromPtr(cur_buf.ptr);

            if (cur_node.data.end_index == start_of_buf) {
                var next = cur_node.next;
                self.current_node = next;
                // Find the first non empty node
                while (next) |node| : (next = node.next) {
                    if (node.data.end_index != 0) {
                        self.current_node = node;
                        break;
                    }
                }
                // Fallback to the last node in the list
                if (self.current_node == null) {
                    self.current_node = self.buffer_list.last;
                }
            }

            if (debug) {
                // Meta should always have been kept up to date
                const meta = self.meta.pop().?;
                std.debug.assert(meta.item_buf.ptr == buf.ptr);
                std.debug.assert(meta.item_buf.len == buf.len);
                std.debug.assert(meta.alignment.compare(.eq, alignment));
            }
        } else if (debug) {
            // getLast asserts there is atlest one meta information
            if (sliceContainsSlice(self.meta.getLast().item_buf, buf) and self.meta.getLast().item_buf.len != buf.len) {
                // Something within an existing allocation is trying to free itself, we ignore it
                return;
            }

            var addresses: [stack_trace_frames]usize = @splat(0);
            var trace = std.builtin.StackTrace{ .instruction_addresses = &addresses, .index = 0 };
            std.debug.captureStackTrace(ret_addr, &trace);

            if (!self.ownsSlice(buf)) {
                log.warn("This allocation was not created by this allocator! {}", .{trace});
                return;
            }

            if (!sliceContainsSlice(cur_buf, buf) or cur_node.data.end_index < end_index orelse 0) {
                log.warn("An item lower in the stack has already been freed! {}", .{trace});
            }

            // There was other things above us in the stack, find out where we are
            var i: usize = 0;
            while (i < self.meta.items.len) : (i += 1) {
                if (self.meta.items[self.meta.items.len - 1 - i].item_buf.ptr == buf.ptr) break;
            }
            // We could not find this allocation in the list
            if (i == self.meta.items.len) {
                // log.err("The freed item ptr was not anywhere in the free list. (This might be an issue with the allocator implementation?) {}", .{trace});
                return;
            }

            log.err(
                \\The following item as freed when not at the top of the stack: {}
                \\
                \\ 
                \\These items should be freed in the following order: {}"
            , .{ trace, DebugMeta.Printer{ .metas = self.meta.items[i..] } });

            // We reset the stack to where we think we should be.
            // This should keep the stack working if we forgot to
            // free something and hopefully cause a use of undefined
            // error on the not freed items.
            const meta = self.meta.items[i];
            self.meta.items.len = i;
            var node = self.current();
            while (node) |n| : (node = n.next) {
                const node_buf = @as([*]u8, @ptrCast(n))[@sizeOf(BufNode)..n.data.len];
                if (sliceContainsSlice(node_buf, meta.item_buf)) {
                    const prev_end = n.data.end_index;
                    n.data.end_index = @intCast(@intFromPtr(meta.item_buf.ptr) - @intFromPtr(node_buf.ptr));
                    @memset(node_buf[n.data.end_index..prev_end], undefined);
                    self.current_node = n;
                    self.last_freed_alignment = meta.alignment;
                    break;
                } else {
                    @memset(node_buf[0..n.data.end_index], undefined);
                    n.data.end_index = 0;
                }
            }
        }
    }
};

fn sliceContainsSlice(container: []const u8, slice: []const u8) bool {
    return @intFromPtr(slice.ptr) >= @intFromPtr(container.ptr) and
        (@intFromPtr(slice.ptr) + slice.len) <= (@intFromPtr(container.ptr) + container.len);
}

test "stack behaviour" {
    var instance = StackAllocator.init(std.testing.allocator);
    defer instance.deinit();
    const alloc = instance.allocator();

    {
        const a1 = try alloc.alloc(usize, 10);
        defer alloc.free(a1);
        try std.testing.expectEqual(@sizeOf(usize) * 10, instance.current().?.data.end_index);
    }
    try std.testing.expectEqual(0, instance.current().?.data.end_index);

    {
        const a2 = try alloc.alloc(u8, 3);
        defer alloc.free(a2);
        try std.testing.expectEqual(@sizeOf(u8) * 3, instance.current().?.data.end_index);
        const a3 = try alloc.alloc(usize, 4);
        defer alloc.free(a3);
        try std.testing.expectEqual(@sizeOf(usize) * 5, instance.current().?.data.end_index);
    }
    try std.testing.expectEqual(0, instance.current().?.data.end_index);
}

test "out of order frees" {
    var instance = StackAllocator.init(std.testing.allocator);
    defer instance.deinit();
    const alloc = instance.allocator();
    log.warn("IGNORE ERRORS PRINTED FOR THIS TEST, THEY ARE EXPECTED", .{});

    {
        const a1 = try alloc.alloc(usize, 1);
        a1[0] = 0xdeadbeaf;
        defer alloc.free(a1);

        try std.testing.expectEqual(@sizeOf(usize) * 1, instance.current().?.data.end_index);
        const a2 = try alloc.alloc(usize, 4);
        try std.testing.expectEqual(@sizeOf(usize) * 5, instance.current().?.data.end_index);
        const a3 = try alloc.alloc(usize, 5);
        try std.testing.expectEqual(@sizeOf(usize) * 10, instance.current().?.data.end_index);
        alloc.free(a2);
        try std.testing.expectEqual(@sizeOf(usize) * 1, instance.current().?.data.end_index);
        alloc.free(a3);

        // The first value is untouched even though the earlier values failed
        try std.testing.expectEqual(0xdeadbeaf, a1[0]);
        try std.testing.expectEqual(@sizeOf(usize) * 1, instance.current().?.data.end_index);
    }
    try std.testing.expectEqual(0, instance.current().?.data.end_index);

    {
        const a1 = try alloc.alloc(usize, 1);
        a1[0] = 0xdeadbeaf;
        defer alloc.free(a1);

        const a2 = try alloc.alloc(usize, 4);
        try std.testing.expectEqual(@sizeOf(usize) * 5, instance.current().?.data.end_index);
        // Force a second buffer
        _ = try alloc.alloc(usize, 100);
        try std.testing.expectEqual(2, instance.buffer_list.len);
        try std.testing.expectEqual(@sizeOf(usize) * 100, instance.current().?.data.end_index);
        alloc.free(a2);

        // We have reset back to the first buffer
        try std.testing.expect(instance.current() != instance.buffer_list.first);

        // The first value is untouched even though the earlier values failed
        try std.testing.expectEqual(0xdeadbeaf, a1[0]);
        try std.testing.expectEqual(@sizeOf(usize) * 1, instance.current().?.data.end_index);
    }
}

test "reset while retaining a buffer" {
    var instance = StackAllocator.init(std.testing.allocator);
    defer instance.deinit();
    const alloc = instance.allocator();

    {
        // Create two internal buffers
        const a1 = try alloc.alloc(u8, 1);
        defer alloc.free(a1);
        const a2 = try alloc.alloc(u8, 1000);
        defer alloc.free(a2);
    }

    // Check that we have at least two buffers
    try std.testing.expectEqual(2, instance.buffer_list.len);

    // This retains the first allocated buffer
    try std.testing.expect(instance.reset(.{ .retain_with_limit = 1 }));
    try std.testing.expectEqual(1, instance.buffer_list.len);
}

test "array usage" {
    var instance = StackAllocator.init(std.testing.allocator);
    defer instance.deinit();
    const alloc = instance.allocator();

    {
        var array = std.ArrayList(usize).init(alloc);
        defer array.deinit();
        for (0..100) |i| {
            try array.append(i);
        }
    }

    // try std.testing.expect(instance.buffer_list.len() > 1);
    // const temp = try alloc.alloc(usize, 1000);
    // alloc.free(temp);

    try std.testing.expect(instance.buffer_list.len > 1);
    try std.testing.expect(instance.reset(.retain_capacity));
    try std.testing.expectEqual(1, instance.buffer_list.len);
    try std.testing.expect(instance.queryCapacity() > 1000);

    {
        var array = std.ArrayList(usize).init(alloc);
        defer array.deinit();
        for (0..200) |i| {
            try array.append(i);
        }
    }

    try std.testing.expect(instance.reset(.free_all));
    try std.testing.expectEqual(0, instance.buffer_list.len);
}
