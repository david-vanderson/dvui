const std = @import("std");
const svg2tvg = @import("svg2tvg");

pub fn main(main_init: std.process.Init) !void {
    const args = try main_init.minimal.args.toSlice(main_init.arena.allocator());

    if (args.len != 4) {
        std.debug.print("Usage: svg2tvg <svg file> -o <output file>\n", .{});
        return error.NoInputArg;
    }

    const input_path = args[1];
    const output_path = args[3];

    errdefer {
        var path_buf: [1024]u8 = undefined;
        std.debug.print("error: input_path='{s}' output_path='{s}'", .{ input_path, output_path });
        const n = std.Io.Dir.cwd().realPathFile(main_init.io, ".", &path_buf) catch 0;
        const cwd: []const u8 = if (n > 0) path_buf[0..n] else "CWD TOO LONG";
        std.debug.print(" cwd='{s}'\n", .{cwd});
    }

    const input_file = try std.Io.Dir.cwd().openFile(main_init.io, input_path, .{});
    defer input_file.close(main_init.io);

    const output_file = try std.Io.Dir.cwd().createFile(main_init.io, output_path, .{});
    defer output_file.close(main_init.io);

    var buf: [8192]u8 = undefined;

    var file_reader = input_file.reader(main_init.io, &.{});
    const svg_bytes = try file_reader.interface.allocRemaining(main_init.arena.allocator(), .limited(1 << 16));
    const tvg_bytes = try svg2tvg.tvg_from_svg(main_init.arena.allocator(), svg_bytes, .{});

    var writer = output_file.writer(main_init.io, &buf);
    try writer.interface.writeAll(tvg_bytes);
    try writer.interface.flush();
    // REPORTME: would be nice to have a
}
