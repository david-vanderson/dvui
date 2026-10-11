const std = @import("std");
const builtin = @import("builtin");

pub const std_options = std.Options{
    .log_level = .warn,
};

pub const DvuiDocGenRunner = @This();

pub fn main(init: std.process.Init.Minimal) !void {
    // Init testing stuff, copy-pasted from zig's runner
    std.testing.environ = init.environ;
    std.testing.allocator_instance = .init(std.heap.page_allocator, .{
        .canary = 0xc3a701ba,
        .check_write_after_free = true,
    });
    std.testing.io_instance = .init(std.testing.allocator, .{
        .argv0 = .init(init.args),
        .environ = init.environ,
    });

    // Gather all tests, run only the DOCIMG ones
    const test_fn_list: []const std.builtin.TestFn = builtin.test_functions;
    for (test_fn_list) |test_fn| {
        if (std.mem.findPos(u8, test_fn.name, 0, "DOCIMG")) |_| {
            std.debug.print("running {s}\n", .{test_fn.name});
        }
        try test_fn.func();
    }
}
