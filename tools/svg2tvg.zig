const std = @import("std");
const svg2tvg = @import("svg2tvg");

pub fn main() !void {
    return impl();
}

fn impl() !void {
    const gpa = std.heap.smp_allocator;
    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();

    _ = args.next();
    const input_path = args.next() orelse {
        std.debug.print("Usage: svg2tvg <svg file> -o <output file>\n", .{});
        return error.NoInputArg;
    };
    // this should be '-o' but we just ignore it
    _ = args.next() orelse return error.NoOutputFlag;
    const output_path = args.next() orelse {
        std.debug.print("Usage: svg2tvg <svg file> -o <output file>\n", .{});
        return error.NoOutputArg;
    };

    errdefer {
        var path_buf: [1024]u8 = undefined;
        std.debug.print("error: input_path='{s}' output_path='{s}'", .{ input_path, output_path });
        const cwd = std.fs.cwd().realpath(".", &path_buf) catch "CWD TOO LONG";
        std.debug.print(" cwd='{s}'\n", .{cwd});
    }

    const input_file = try std.fs.cwd().openFile(input_path, .{});
    defer input_file.close();

    const output_file = try std.fs.cwd().createFile(output_path, .{});
    defer output_file.close();

    var buf: [8192]u8 = undefined;
    //var reader = input_file.reader(read_buf);

    const svg_bytes = try input_file.readToEndAlloc(gpa, 1 << 16);
    const tvg_bytes = try svg2tvg.tvg_from_svg(gpa, svg_bytes, .{});

    var writer = output_file.writer(&buf);
    try writer.interface.writeAll(tvg_bytes);
    try writer.interface.flush();
    // REPORTME: would be nice to have a
}
