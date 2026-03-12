const std = @import("std");

pub fn UpdateThread(comptime T: type) type {
    return struct {
        self: *anyopaque,
        update_fn: *const fn (*anyopaque, T) anyerror!void,
        thread: std.Thread = undefined,
        queue: UpdateMessageQueue = undefined,
        queue_initialized: bool = false,
        fatal_errors: bool = false,

        pub const UpdateMessageQueue = struct {
            channel: std.ArrayList(T) = .empty,
            mutex: std.Thread.Mutex = .{},
            condvar: std.Thread.Condition = .{},
            running: bool = true,
        };

        const Self = @This();

        pub fn update(self: *Self, message: T) void {
            self.update_fn(self.self, message) catch |err|
                if (self.fatal_errors)
                    std.debug.panic("fatal error in update fn: {s}", .{@errorName(err)})
                else
                    std.log.err("update function error: {s}", .{@errorName(err)});
        }

        pub fn updateWorker(self: *Self) void {
            while (true) {
                self.queue.mutex.lock();
                defer self.queue.mutex.unlock();

                while (self.queue.channel.items.len == 0 and self.queue.running) {
                    self.queue.condvar.wait(&self.queue.mutex);
                }

                if (!self.queue.running and self.queue.channel.items.len == 0) break;

                for (self.queue.channel.items) |msg| self.update(msg);
                self.queue.channel.clearRetainingCapacity();
            }
        }

        pub fn run(self: *Self) !void {
            self.queue = .{};
            self.queue_initialized = true;
            self.thread = try std.Thread.spawn(.{}, updateWorker, .{self});
        }

        pub fn send(self: *Self, alloc: std.mem.Allocator, msg: T) !void {
            if (!self.queue_initialized) return error.NotStarted;
            self.queue.mutex.lock();
            defer self.queue.mutex.unlock();
            try self.queue.channel.append(alloc, msg);
            self.queue.condvar.signal();
        }

        pub fn stop(self: *Self) void {
            {
                self.queue.mutex.lock();
                defer self.queue.mutex.unlock();
                self.queue.running = false;
                self.queue.condvar.signal();
            }
            self.thread.join();
        }

        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            self.queue.channel.deinit(alloc);
        }
    };
}
