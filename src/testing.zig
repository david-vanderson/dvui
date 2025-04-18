allocator: std.mem.Allocator,
backend: *Backend,
window: *Window,
snapshot_dir: []const u8,

snapshot_index: u8 = 0,

/// Moves the mouse to the center of the widget
pub fn moveTo(tag: []const u8) !void {
    const tag_data = dvui.tagGet(tag) orelse {
        std.debug.print("tag \"{s}\" not found\n", .{tag});
        return error.TagNotFound;
    };
    if (!tag_data.visible) return error.WidgetNotVisible;
    try moveToPoint(tag_data.rect.center());
}

/// Moves the mouse to the provided absolute position
pub fn moveToPoint(point: dvui.Point) !void {
    const cw = dvui.currentWindow();
    _ = try cw.addEventMouseMotion(point.x, point.y);
}

/// Presses and releases the button at the current mouse position
pub fn click(b: dvui.enums.Button) !void {
    const cw = dvui.currentWindow();
    _ = try cw.addEventMouseButton(b, .press);
    _ = try cw.addEventMouseButton(b, .release);
}

pub fn writeText(text: []const u8) !void {
    const cw = dvui.currentWindow();
    _ = try cw.addEventText(text);
}

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

pub const InitOptions = struct {
    allocator: std.mem.Allocator = if (@import("builtin").is_test) std.testing.allocator else undefined,
    window_size: dvui.Size = .{ .w = 600, .h = 400 },
    snapshot_dir: []const u8 = "snapshots",
};

pub fn init(options: InitOptions) !Self {
    // init SDL backend (creates and owns OS window)
    const backend = try options.allocator.create(Backend);
    errdefer options.allocator.destroy(backend);
    backend.* = switch (Backend.kind) {
        .sdl2, .sdl3 => try Backend.initWindow(.{
            .allocator = options.allocator,
            .size = options.window_size,
            .vsync = false,
            .title = "",
            .hidden = true,
        }),
        .testing => Backend.init(.{
            .allocator = options.allocator,
            .size = options.window_size,
        }),
        inline else => |kind| {
            std.debug.print("dvui.testing does not support the {s} backend\n", .{@tagName(kind)});
            return error.SkipZigTest;
        },
    };

    if (should_write_snapshots()) {
        // ensure snapshot directory exists
        // NOTE: do fs operation through cwd to handle relative and absolute paths
        std.fs.cwd().makeDir(options.snapshot_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    const window = try options.allocator.create(Window);
    window.* = try dvui.Window.init(@src(), options.allocator, backend.backend(), .{});

    window.begin(0) catch unreachable;

    return .{
        .allocator = options.allocator,
        .backend = backend,
        .window = window,
        .snapshot_dir = options.snapshot_dir,
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
        return error.TagNotFound;
    }
}

pub fn expectVisible(tag: []const u8) !void {
    if (dvui.tagGet(tag)) |data| {
        try std.testing.expect(data.visible);
    } else {
        std.debug.print("tag \"{s}\" not found\n", .{tag});
        return error.TagNotFound;
    }
}

pub const SnapshotError = error{
    MissingSnapshotDirectory,
    MissingSnapshotFile,
    SnapshotsDidNotMatch,
};

/// Captures one frame and return the png data for that frame
///
/// The returned data is allocated by `Self.allocator` and should be freed by the caller
pub fn capturePng(self: *Self, frame: dvui.App.frameFunction) ![]const u8 {
    // render the whole screen to a texture
    var picture = dvui.Picture.start(dvui.windowRectPixels()) orelse {
        std.debug.print("Current backend does not support capturing images\n", .{});
        return error.Unsupported;
    };

    // run the gui code
    if (try frame() == .close) return error.closed;

    // render the retained dialogs and deferred renders
    _ = try dvui.currentWindow().endRendering(.{});

    const texture = picture.stop();

    // texture will be destroyed in Window.end() so grab pixels now
    const png_data = try dvui.pngFromTexture(self.allocator, texture, .{});

    const cw = dvui.currentWindow();

    _ = try cw.end(.{});
    try cw.begin(cw.frame_time_ns + 100 * std.time.ns_per_ms);

    return png_data;
}
const png_extension = ".png";

/// Captures one frame and compares to an earilier captured frame, returning an error if they are not the same
///
/// IMPORTANT: Snapshots are unstable and both backend and platform dependent. Changing any of these might fail the test.
///
/// All snapshot tests can be ignored (without skipping the whole test) by setting the environment variable `DVUI_SNAPSHOT_IGNORE`
///
/// Set the environment variable `DVUI_SNAPSHOT_WRITE` to create/overwrite the snapshot files
///
/// Dvui does not clear out old or unused snapshot files. To clean the snapshot directory follow these steps:
/// 1. Ensure all snapshot test pass
/// 2. Delete the snapshot directory
/// 3. Run all snapshot tests with `DVUI_SNAPSHOT_WRITE` set to recreate only the used files
pub fn snapshot(self: *Self, src: std.builtin.SourceLocation, frame: dvui.App.frameFunction) !void {
    if (should_ignore_snapshots()) return;

    defer self.snapshot_index += 1;
    const filename = try std.fmt.allocPrint(self.allocator, "{s}-{s}-{d}" ++ png_extension, .{ src.file, src.fn_name, self.snapshot_index });
    defer self.allocator.free(filename);
    // NOTE: do fs operation through cwd to handle relative and absolute paths
    var dir = std.fs.cwd().openDir(self.snapshot_dir, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("{s}:{d}:{d}: Snapshot directory did not exist! Run the test with DVUI_SNAPSHOT_WRITE to create all snapshot files\n", .{ src.file, src.line, src.column });
            return error.SkipZigTest; // FIXME: Test should fail with missing snapshots, but we don't want to commit snapshots while they are unstable, so skip tests instead
        },
        else => return err,
    };
    defer dir.close();

    const png_data = self.capturePng(frame);
    defer self.allocator.free(png_data);

    const file = dir.openFile(filename, .{}) catch |err| switch (err) {
        std.fs.File.OpenError.FileNotFound => {
            if (should_write_snapshots()) {
                try dir.writeFile(.{ .sub_path = filename, .data = png_data, .flags = .{} });
                std.debug.print("Snapshot: Created file \"{s}\"\n", .{filename});
                return;
            }
            std.debug.print("{s}:{d}:{d}: Snapshot file did not exist! Run the test with `DVUI_SNAPSHOT_WRITE` to create all snapshot files\n", .{ src.file, src.line, src.column });
            return error.SkipZigTest; // FIXME: Test should fail with missing snapshots, but we don't want to commit snapshots while they are unstable, so skip tests instead
        },
        else => return err,
    };
    const prev_hash = try hash_png(file.reader().any());
    file.close();

    var png_reader = std.io.fixedBufferStream(png_data);
    const new_hash = try hash_png(png_reader.reader().any());

    if (prev_hash != new_hash) {
        if (should_write_snapshots()) {
            try dir.writeFile(.{ .sub_path = filename, .data = png_data, .flags = .{} });
            std.debug.print("Snapshot: Overwrote file \"{s}\"\n", .{filename});
            return;
        }
        const failed_filename = try std.fmt.allocPrint(self.allocator, "{s}-failed" ++ png_extension, .{filename[0 .. filename.len - png_extension.len]});
        defer self.allocator.free(failed_filename);
        try dir.writeFile(.{ .sub_path = failed_filename, .data = png_data, .flags = .{} });

        std.debug.print("Snapshot did not match! See the \"{s}\" for the current output", .{failed_filename});

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

fn should_ignore_snapshots() bool {
    return Backend.kind == .testing or std.process.hasEnvVarConstant("DVUI_SNAPSHOT_IGNORE");
}

fn should_write_snapshots() bool {
    return !should_ignore_snapshots() and std.process.hasEnvVarConstant("DVUI_SNAPSHOT_WRITE");
}

/// Internal use only!
///
/// Generates and saves images for documentation. The test name is required to end with `.png` and can include '/' directory separators
pub fn saveDocImage(self: *Self, src: std.builtin.SourceLocation, sub_name: ?[]const u8, frame: dvui.App.frameFunction) !void {
    if (!std.mem.endsWith(u8, src.fn_name, png_extension)) {
        return error.SaveDocImageRequiresPNGExtensionInTestName;
    }

    const root = @import("root");
    if (!@hasDecl(root, "dvui_image_doc_gen_dir")) {
        // Do nothing if we are not running with the doc_gen test runner.
        // This means that the rest of the test is still performed and used as a normal dvui test.
        return;
    }

    const test_prefix = "test.";
    const filename = try std.fmt.allocPrint(self.allocator, "{s}{s}" ++ png_extension, .{
        src.fn_name[test_prefix.len..(src.fn_name.len - png_extension.len)],
        sub_name orelse "",
    });
    defer self.allocator.free(filename);

    const png_data = try self.capturePng(frame);
    defer self.allocator.free(png_data);

    try root.dvui_image_doc_gen_dir.writeFile(.{
        .data = png_data,
        .sub_path = filename,
        // set exclusive flag to error if two test generate an image with the same name
        .flags = .{ .exclusive = true },
    });
}

const Self = @This();

const std = @import("std");
const dvui = @import("dvui.zig");

const Backend = dvui.backend;
const Window = dvui.Window;

test {
    @import("std").testing.refAllDecls(@This());
}
