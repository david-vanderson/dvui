allocator: std.mem.Allocator,
backend: *Backend,
runner: *Runner,
window: *Window,

snapshot_index: u8 = 0,

pub fn init(allocator: std.mem.Allocator, frameFn: *const fn () anyerror!void, window_size: dvui.Size) !Self {
    if (Backend.kind != .sdl) {
        @compileError("dvui.testing can only be used with the SDL backend");
    }

    if (should_write_snapshots()) {
        // ensure snapshot directory exists
        std.fs.makeDirAbsolute(testing_options.snapshot_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    // init SDL backend (creates and owns OS window)
    const backend = try allocator.create(Backend);
    backend.* = try Backend.initWindow(.{
        .allocator = allocator,
        .size = window_size,
        .vsync = false,
        .title = "",
    });

    const window = try allocator.create(Window);
    window.* = try dvui.Window.init(@src(), allocator, backend.backend(), .{});
    const runner = try allocator.create(Runner);
    runner.* = dvui.Runner.init(window, backend, frameFn);

    return .{
        .allocator = allocator,
        .backend = backend,
        .runner = runner,
        .window = window,
    };
}

pub fn deinit(self: *Self) void {
    self.runner.deinit();
    self.window.deinit();
    self.backend.deinit();
    self.allocator.destroy(self.runner);
    self.allocator.destroy(self.window);
    self.allocator.destroy(self.backend);
}

pub fn expectFocused(self: *Self, test_id: []const u8, id_extra: ?u32) !void {
    const info = try self.runner.getWidgetInfo(test_id, id_extra);
    try std.testing.expectEqual(self.window.last_focused_id_this_frame, info.wd.id);
}

pub const SnapshotError = error{
    MissingSnapshotDirectory,
    MissingSnapshotFile,
    SnapshotsDidNotMatch,
};

/// Captures one frame and compares to an earilier captured frame, returning an error if they are not the same
///
/// Set the environment variable DVUI_SNAPSHOT_WRITE to create/overwrite the snapshot files
///
/// Dvui does not clear out old or unused snapshot files. To clean the snapshot directory follow these steps:
/// 1. Ensure all snapshot test pass
/// 2. Delete the snapshot directory
/// 3. Run all snapshot tests with DVUI_SNAPSHOT_WRITE set to recreate only the used files
pub fn snapshot(self: *Self, src: std.builtin.SourceLocation) !void {
    const png_extension = ".png";
    defer self.snapshot_index += 1;
    const filename = try std.fmt.allocPrint(self.allocator, "{s}-{s}-{d}" ++ png_extension, .{ src.file, src.fn_name, self.snapshot_index });
    defer self.allocator.free(filename);
    var dir = std.fs.openDirAbsolute(testing_options.snapshot_dir, .{}) catch |err| switch (err) {
        std.fs.File.OpenError.FileNotFound => {
            std.debug.print("Snapshot directory did not exist! Run the test with -Dwrite-snapshots to create all snapshot files\n", .{});
            return SnapshotError.MissingSnapshotDirectory;
        },
        else => return err,
    };
    defer dir.close();

    const png = try self.runner.capturePng();
    defer png.deinit();

    const file = dir.openFile(filename, .{}) catch |err| switch (err) {
        std.fs.File.OpenError.FileNotFound => {
            if (should_write_snapshots()) {
                try dir.writeFile(.{ .sub_path = filename, .data = png.data, .flags = .{} });
                std.debug.print("Snapshot: Created file \"{s}\"\n", .{filename});
                return;
            }
            std.debug.print("Snapshot file did not exist! Run the test with -Dwrite-snapshots to create all snapshot files\n", .{});
            return SnapshotError.MissingSnapshotFile;
        },
        else => return err,
    };
    const prev_hash = try hash_png(file.reader().any());
    file.close();

    var png_reader = std.io.fixedBufferStream(png.data);
    const new_hash = try hash_png(png_reader.reader().any());

    if (prev_hash != new_hash) {
        if (should_write_snapshots()) {
            try dir.writeFile(.{ .sub_path = filename, .data = png.data, .flags = .{} });
            std.debug.print("Snapshot: Overwrote file \"{s}\"\n", .{filename});
            return;
        }
        const failed_filename = try std.fmt.allocPrint(self.allocator, "{s}-failed" ++ png_extension, .{filename[0 .. filename.len - png_extension.len]});
        defer self.allocator.free(failed_filename);
        try dir.writeFile(.{ .sub_path = failed_filename, .data = png.data, .flags = .{} });

        return SnapshotError.SnapshotsDidNotMatch;
    }
}

fn hash_png(png_reader: std.io.AnyReader) !u32 {
    var hasher = dvui.fnv.init();

    var read_buf: [1024 * 4]u8 = undefined;
    var len: usize = read_buf.len;
    // len < read_buf indicates the end of the data
    while (len == read_buf.len) {
        len = try png_reader.readAll(&read_buf);
        hasher.update(read_buf[0..len]);
    }
    return hasher.final();
}

fn should_write_snapshots() bool {
    return std.process.hasEnvVarConstant("DVUI_SNAPSHOT_WRITE");
}

const Self = @This();

const std = @import("std");
const dvui = @import("dvui.zig");

const testing_options = @import("testing_options");

const Backend = dvui.backend;
const Runner = dvui.Runner;
const Window = dvui.Window;
