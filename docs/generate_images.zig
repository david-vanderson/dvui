const std = @import("std");
const dvui = @import("dvui");

pub fn main() !void {
    var gpa_allocator = std.heap.DebugAllocator(.{}).init;
    defer std.debug.assert(gpa_allocator.deinit() == .ok);
    const gpa = gpa_allocator.allocator();

    var args_iter = try std.process.argsWithAllocator(gpa);
    defer args_iter.deinit();
    _ = args_iter.skip(); // first arg is the executable
    const out_path = args_iter.next() orelse @panic("Missing out directory argument");
    var out_dir = try std.fs.cwd().openDir(out_path, .{});
    defer out_dir.close();

    var image_fns = ImageFunctions{ .allocator = gpa, .out_dir = out_dir };

    inline for (@typeInfo(ImageFunctions).@"struct".decls) |decl| {
        const image_fn = @field(ImageFunctions, decl.name);
        if (@typeInfo(@TypeOf(image_fn)).@"fn".params.len != 1) continue;
        std.debug.print("Fn: {s}\n", .{decl.name});
        try @call(.auto, image_fn, .{&image_fns});
    }
}

const ImageFunctions = struct {
    allocator: std.mem.Allocator,
    out_dir: std.fs.Dir,
    t: dvui.testing = undefined,

    /// Files saved with this
    fn save(self: *ImageFunctions, comptime name: []const u8, frame: dvui.App.frameFunction) !void {
        const png_data = try self.t.capturePng(frame);
        defer self.t.allocator.free(png_data);
        try self.out_dir.writeFile(.{
            .sub_path = name ++ ".png",
            .data = png_data,
        });
    }

    pub fn Example(self: *ImageFunctions) !void {
        self.t = try dvui.testing.init(.{ .allocator = self.allocator, .window_size = .{ .w = 800, .h = 600 } });
        defer self.t.deinit();

        dvui.Examples.show_demo_window = true;

        const frame = struct {
            fn frame() !dvui.App.Result {
                var over = try dvui.overlay(@src(), .{ .expand = .both, .background = true, .color_fill = .{ .name = .fill_window } });
                defer over.deinit();
                try dvui.Examples.demo();
                return .ok;
            }
        }.frame;

        try dvui.testing.settle(frame);

        try self.save("Example-demo", frame);
    }
};
