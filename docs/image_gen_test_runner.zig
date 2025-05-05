const std = @import("std");
const builtin = @import("builtin");

pub const std_options = std.Options{
    .log_level = .warn,
};

pub const DvuiDocGenRunner = @This();

pub fn main() !void {
    const test_fn_list: []const std.builtin.TestFn = builtin.test_functions;
    for (test_fn_list) |test_fn| {
        try test_fn.func();
    }
}
