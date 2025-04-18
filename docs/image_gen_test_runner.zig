const std = @import("std");
const builtin = @import("builtin");

/// A global handle to the output directory.
///
/// The presence of this declaration signals that the image_gen is currently running
pub var dvui_image_doc_gen_dir: std.fs.Dir = undefined;

pub fn main() !void {
    var args_iter = try std.process.argsWithAllocator(std.testing.allocator);
    defer args_iter.deinit();
    _ = args_iter.skip(); // first arg is the executable
    const out_path = args_iter.next() orelse @panic("Missing out directory argument");
    dvui_image_doc_gen_dir = try std.fs.cwd().openDir(out_path, .{});
    defer dvui_image_doc_gen_dir.close();

    const test_fn_list: []const std.builtin.TestFn = builtin.test_functions;
    for (test_fn_list) |test_fn| {
        try test_fn.func();
    }
}
