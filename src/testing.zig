allocator: std.mem.Allocator,
backend: *Backend,
window: *Window,

snapshot_index: u8 = 0,

pub fn pressKey(code: dvui.enums.Key, mod: dvui.enums.Mod) !void {
    const cw = dvui.currentWindow();
    _ = try cw.addEventKey(.{ .code = code, .mod = mod, .action = .down });
    _ = try cw.addEventKey(.{ .code = code, .mod = mod, .action = .up });
}

// Assumes we are just after Window.begin
pub fn settle(frame: dvui.App.frameFunction) !void {
    const cw = dvui.currentWindow();
    if (try frame() == .close) return error.closed;

    for (0..100) |_| {
        const wait_time = try cw.end(.{});
        try cw.begin(cw.frame_time_ns + 100 * std.time.ns_per_ms);

        if (wait_time == 0) {
            // need another frame, someone called refresh()
            if (try frame() == .close) return error.closed;
            continue;
        }

        return;
    }

    return error.unsettled;
}

pub fn init(allocator: std.mem.Allocator, window_size: dvui.Size) !Self {
    if (Backend.kind != .sdl) {
        @compileError("dvui.testing can only be used with the SDL backend");
    }

    if (should_write_snapshots()) {
        // ensure snapshot directory exists
        // NOTE: do fs operation through cwd to handle relative and absolute paths
        std.fs.cwd().makeDir(testing_options.snapshot_dir) catch |err| switch (err) {
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
        .hidden = true,
    });

    const window = try allocator.create(Window);
    window.* = try dvui.Window.init(@src(), allocator, backend.backend(), .{});

    window.begin(0) catch unreachable;

    return .{
        .allocator = allocator,
        .backend = backend,
        .window = window,
    };
}

pub fn deinit(self: *Self) void {
    _ = self.window.end(.{}) catch |err| {
        std.debug.print("window.end() returned {!}\n", .{err});
    };
    self.window.deinit();
    self.backend.deinit();
    self.allocator.destroy(self.window);
    self.allocator.destroy(self.backend);
}

pub fn expectFocused(tag: []const u8) !void {
    if (dvui.tagGet(tag)) |data| {
        try std.testing.expectEqual(data.id, dvui.focusedWidgetId());
    } else {
        std.debug.print("tag \"{s}\" not found\n", .{tag});
        return error.TestExpectedEqual;
    }
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
    // NOTE: do fs operation through cwd to handle relative and absolute paths
    var dir = std.fs.cwd().openDir(testing_options.snapshot_dir, .{}) catch |err| switch (err) {
        error.FileNotFound => {
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
