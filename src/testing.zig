allocator: std.mem.Allocator,
backend: *Backend,
window: *Window,
image_dir: ?[]const u8,
snapshot_dir: []const u8,

snapshot_index: u8 = 0,

/// Used to hash widget data during a frame for snapshot testing
pub var widget_hasher: ?dvui.fnv = null;

/// Moves the mouse to the center of the widget
pub fn moveTo(tag: []const u8) !void {
    const tag_data = dvui.tagGet(tag) orelse {
        std.debug.print("tag \"{s}\" not found\n", .{tag});
        return error.TagNotFound;
    };
    if (!tag_data.visible) return error.WidgetNotVisible;
    const cw = dvui.currentWindow();
    const point = tag_data.rect.center().toNatural();
    _ = try cw.addEventMouseMotion(point);
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

/// Runs frames until `dvui.refresh` was not called.
///
/// Assumes we are just after `dvui.Window.begin`, and on return will be just
/// after a future `dvui.Window.begin`.
pub fn settle(frame: dvui.App.frameFunction) !void {
    for (0..100) |_| {
        const wait_time = try step(frame);

        if (wait_time == 0) {
            // need another frame, someone called refresh()
            continue;
        }

        return;
    }

    return error.unsettled;
}

/// Runs exactly one frame, returning the wait_time from `dvui.Window.end`.
///
/// Assumes we are just after `dvui.Window.begin`, and moves to just after the
/// next `dvui.Window.begin`.
///
/// Useful when you know the frame will not settle, but you need the frame
/// to handle events.
pub fn step(frame: dvui.App.frameFunction) !?u32 {
    const cw = dvui.currentWindow();
    if (try frame() == .close) return error.closed;
    const wait_time = try cw.end(.{});
    try cw.begin(cw.frame_time_ns + 100 * std.time.ns_per_ms);
    return wait_time;
}

pub const InitOptions = struct {
    allocator: std.mem.Allocator = if (@import("builtin").is_test) std.testing.allocator else undefined,
    window_size: dvui.Size = .{ .w = 600, .h = 400 },
    image_dir: ?[]const u8 = null,
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
            .size = .cast(options.window_size),
            .size_pixels = options.window_size.scale(2, dvui.Size.Physical),
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
        .image_dir = options.image_dir orelse @import("build_options").image_dir,
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

/// Captures one frame and return the png data for that frame.
///
/// Captures the physical pixels in rect, or if null the entire OS window.
///
/// The returned data is allocated by `Self.allocator` and should be freed by the caller.
pub fn capturePng(self: *Self, frame: dvui.App.frameFunction, rect: ?dvui.Rect.Physical) ![]const u8 {
    var picture = dvui.Picture.start(rect orelse dvui.windowRectPixels()) orelse {
        std.debug.print("Current backend does not support capturing images\n", .{});
        return error.Unsupported;
    };

    // run the gui code
    if (try frame() == .close) return error.closed;

    // render the retained dialogs and deferred renders
    _ = try dvui.currentWindow().endRendering(.{});

    picture.stop();

    // texture will be destroyed in picture.deinit() so grab pixels now
    const png_data = try picture.png(self.allocator);

    // draw texture and destroy
    picture.deinit();

    const cw = dvui.currentWindow();

    _ = try cw.end(.{});
    try cw.begin(cw.frame_time_ns + 100 * std.time.ns_per_ms);

    return png_data;
}

/// Runs exactly one frame, creating a hash of the state of that frame and compares to an earilier saved hash,
/// returning an error if they are not the same.
///
/// IMPORTANT: Snapshots are unstable and both backend and platform dependent. Changing any of these might fail the test.
///
/// All snapshot tests can be ignored (without skipping the whole test) by setting the environment variable `DVUI_SNAPSHOT_IGNORE`.
///
/// Set the environment variable `DVUI_SNAPSHOT_WRITE` to create/overwrite the snapshot files
///
/// To generate and image of the snapshot for debugging pass `-Dsnapshot-images` with a suffix like "before" or "after".
/// The images will be places in a `images` directory next to the snapshot files in question
///
/// Dvui does not clear out old or unused snapshot files. To clean the snapshot directory follow these steps:
/// 1. Ensure all snapshot test pass
/// 2. Delete the snapshot directory
/// 3. Run all snapshot tests with `DVUI_SNAPSHOT_WRITE` set to recreate only the used files
pub fn snapshot(self: *Self, src: std.builtin.SourceLocation, frame: dvui.App.frameFunction) !void {
    if (should_ignore_snapshots()) {
        _ = try step(frame);
        return;
    }

    defer self.snapshot_index += 1;
    const filename = try std.fmt.allocPrint(self.allocator, "{s}-{s}-{d}", .{ src.file, src.fn_name, self.snapshot_index });
    defer self.allocator.free(filename);
    // NOTE: do fs operation through cwd to handle relative and absolute paths
    var dir = std.fs.cwd().openDir(self.snapshot_dir, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("{s}:{d}:{d}: Snapshot directory did not exist! Run the test with DVUI_SNAPSHOT_WRITE to create all snapshot files\n", .{ src.file, src.line, src.column });
            return error.MissingSnapshotFile;
        },
        else => return err,
    };
    defer dir.close();

    widget_hasher = .init();
    defer widget_hasher = null;

    if (@import("build_options").snapshot_image_suffix) |image_suffix| {
        const png_data = try self.capturePng(frame, null);
        defer self.allocator.free(png_data);
        dir.makeDir("images") catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        const image_name = try std.fmt.allocPrint(self.allocator, "images/{s}-{s}.png", .{ filename, image_suffix });
        defer self.allocator.free(image_name);
        try dir.writeFile(.{ .sub_path = image_name, .data = png_data, .flags = .{} });
        // Do not continue with checking hashes as it is not deterministic across content_scales because
        // fonts render in integer steps and scaling changes the step used and the size of the test
        return; // Do not skip test because other snapshots might run after this one
    } else {
        _ = try step(frame);
    }

    const HashInt = u32;
    const hash: HashInt = widget_hasher.?.final();

    const file = dir.openFile(filename, .{ .mode = .read_write }) catch |err| switch (err) {
        std.fs.File.OpenError.FileNotFound => {
            if (should_write_snapshots()) {
                const file = try dir.createFile(filename, .{});
                try file.writer().print("{X}", .{hash});
                std.debug.print("Snapshot: Created file \"{s}\"\n", .{filename});
                return;
            }
            std.debug.print("{s}:{d}:{d}: Snapshot file did not exist! Run the test with `DVUI_SNAPSHOT_WRITE` to create all snapshot files\n", .{ src.file, src.line, src.column });
            return error.MissingSnapshotFile;
        },
        else => return err,
    };
    defer file.close();

    var hash_buf: [@sizeOf(HashInt) * 2]u8 = undefined;
    _ = try file.readAll(&hash_buf);
    const prev_hash = try std.fmt.parseUnsigned(HashInt, &hash_buf, 16);

    if (prev_hash != hash) {
        if (should_write_snapshots()) {
            try file.seekTo(0);
            try file.writer().print("{X}", .{hash});
            std.debug.print("Snapshot: Overwrote file \"{s}\"\n", .{filename});
            return;
        }
        return SnapshotError.SnapshotsDidNotMatch;
    }
}

fn should_ignore_snapshots() bool {
    // If there is a snapshot image suffix, we expect to generate images, thus not ignore the test
    return @import("build_options").snapshot_image_suffix == null and (Backend.kind != .testing or std.process.hasEnvVarConstant("DVUI_SNAPSHOT_IGNORE"));
}

fn should_write_snapshots() bool {
    return !should_ignore_snapshots() and std.process.hasEnvVarConstant("DVUI_SNAPSHOT_WRITE");
}

/// Internal use only!
///
/// Always runs a single frame. If `-Dgenerate-images` is passed to `zig build docs`,
/// capture the physical pixels in rect, and write those as a png file.
///
/// If rect is null, capture the whole OS window.
///
/// Generates and saves images for documentation. The test name is required to
/// end with `.png` and are format strings evaluated at comptime.
pub fn saveImage(self: *Self, frame: dvui.App.frameFunction, rect: ?dvui.Rect.Physical, filename: []const u8) !void {
    if (self.image_dir == null) {
        // This means that the rest of the test is still performed and used as a normal dvui test.
        _ = try step(frame);
        return;
    }

    const png_data = try self.capturePng(frame, rect);
    defer self.allocator.free(png_data);

    var dir = try std.fs.cwd().makeOpenPath(self.image_dir.?, .{});
    defer dir.close();
    try dir.writeFile(.{ .data = png_data, .sub_path = filename });
}

/// Used internally for documentation generation
pub const is_dvui_doc_gen_runner = @hasDecl(@import("root"), "DvuiDocGenRunner");

const Self = @This();

const std = @import("std");
const dvui = @import("dvui.zig");

const Backend = dvui.backend;
const Window = dvui.Window;

test {
    @import("std").testing.refAllDecls(@This());
}
