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
        std.log.warn("tag \"{s}\" not found\n", .{tag});
        return error.TagNotFound;
    };
    if (!tag_data.visible) return error.WidgetNotVisible;
    const cw = dvui.currentWindow();
    _ = try cw.addEventMouseMotion(.{ .pt = tag_data.rect.center() });
}

/// Presses and releases the button at the current mouse position
pub fn click(b: dvui.enums.Button) !void {
    const cw = dvui.currentWindow();
    _ = try cw.addEventMouseButton(b, .press);
    _ = try cw.addEventMouseButton(b, .release);
}

pub fn writeText(text: []const u8) !void {
    const cw = dvui.currentWindow();
    _ = try cw.addEventText(.{ .text = text });
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
    io: std.Io = if (@import("builtin").is_test) std.testing.io else undefined,
    allocator: std.mem.Allocator = if (@import("builtin").is_test) std.testing.allocator else undefined,
    window_size: dvui.Size = .{ .w = 600, .h = 400 },
    window_init_opts: Window.InitOptions = .{},
    image_dir: ?[]const u8 = null,
    snapshot_dir: []const u8 = "snapshots",
};

pub fn init(options: InitOptions) !Self {
    dvui.io = options.io;
    // init SDL backend (creates and owns OS window)
    const backend = try options.allocator.create(Backend);
    errdefer options.allocator.destroy(backend);
    backend.* = switch (Backend.kind) {
        .sdl2, .sdl3 => try Backend.initWindow(.{
            .io = options.io,
            .size = options.window_size,
            .vsync = false,
            .title = "",
            .app = "",
            .org = "",
            .hidden = true,
            .persist_window_geometry = false,
        }),
        .testing => Backend.init(.{
            .allocator = options.allocator,
            .size = .cast(options.window_size),
            .size_pixels = options.window_size.scale(2, dvui.Size.Physical),
        }),
        inline else => |kind| {
            std.log.warn("dvui.testing does not support the {s} backend\n", .{@tagName(kind)});
            return error.SkipZigTest;
        },
    };

    if (should_write_snapshots()) {
        // ensure snapshot directory exists
        // NOTE: do fs operation through cwd to handle relative and absolute paths
        std.Io.Dir.cwd().createDir(dvui.io, options.snapshot_dir, .default_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    var window_init_opts = options.window_init_opts;
    // Define a defaults so that tests aren't platform dependent.
    // These would otherwise check for OS tag or OS configuration.
    if (window_init_opts.color_scheme == null) {
        window_init_opts.color_scheme = .light;
    }
    if (window_init_opts.keybinds == null) {
        window_init_opts.keybinds = .windows;
    }

    const window = try options.allocator.create(Window);
    window.* = try dvui.Window.init(@src(), options.allocator, backend.backend(), window_init_opts);

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
        std.log.warn("window.end() returned {any}\n", .{err});
    };
    self.window.deinit();
    self.backend.deinit();
    self.allocator.destroy(self.window);
    self.allocator.destroy(self.backend);
}

pub fn expectFocused(tag: []const u8) !void {
    const data = try tagGet(tag);
    try std.testing.expectEqual(data.id, dvui.focusedWidgetId());
}

pub fn expectNotFocused(tag: []const u8) !void {
    const data = try tagGet(tag);
    try std.testing.expect(data.id != dvui.focusedWidgetId());
}

pub fn expectVisible(tag: []const u8) !void {
    const data = try tagGet(tag);
    try std.testing.expect(data.visible);
}

pub fn expectNotVisible(tag: []const u8) !void {
    const data = try tagGet(tag);
    try std.testing.expect(!data.visible);
}

pub fn tagGet(tag: []const u8) !dvui.TagData {
    return dvui.tagGet(tag) orelse {
        std.log.warn("tag \"{s}\" not found\n", .{tag});
        return error.TagNotFound;
    };
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
pub fn capturePng(frame: dvui.App.frameFunction, rect: ?dvui.Rect.Physical, writer: *std.Io.Writer) !void {
    var picture = dvui.Picture.start(rect orelse dvui.windowRectPixels()) orelse {
        std.log.warn("Current backend does not support capturing images\n", .{});
        return error.Unsupported;
    };

    // run the gui code
    if (try frame() == .close) return error.closed;

    // render the retained dialogs and deferred renders
    _ = dvui.currentWindow().endRendering(.{});

    picture.stop();

    // texture will be destroyed in picture.deinit() so grab pixels now
    try picture.png(writer);

    // draw texture and destroy
    picture.deinit();

    const cw = dvui.currentWindow();

    _ = try cw.end(.{});
    try cw.begin(cw.frame_time_ns + 100 * std.time.ns_per_ms);
}

pub const SnapshotOptions = struct {
    /// Path of the snapshot file, relative to the snapshot directory.
    /// If not provided defaults to "{src.file}-{src.fn_name}-{snapshot_index}" with illegal
    /// characters for paths sanitized to `_`.
    /// Snapshots with a custom path do not advance `snapshot_index`.
    path: ?[]const u8 = null,
};

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
pub fn snapshot(self: *Self, src: std.builtin.SourceLocation, frame: dvui.App.frameFunction, opts: SnapshotOptions) !void {
    if (should_ignore_snapshots()) {
        _ = try step(frame);
        return;
    }

    const filename = if (opts.path) |path| path else blk: {
        break :blk try std.fmt.allocPrint(self.allocator, "{f}-{f}-{d}", .{
            SanitizedPath.init(src.file),
            SanitizedFileName.init(src.fn_name),
            self.snapshot_index,
        });
    };
    defer if (opts.path == null) {
        self.allocator.free(filename);
        self.snapshot_index += 1;
    };

    // NOTE: do fs operation through cwd to handle relative and absolute paths
    var dir = std.Io.Dir.cwd().openDir(dvui.io, self.snapshot_dir, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            std.log.warn("{s}:{d}:{d}: Snapshot directory did not exist! Run the test with DVUI_SNAPSHOT_WRITE to create all snapshot files\n", .{ src.file, src.line, src.column });
            return error.MissingSnapshotFile;
        },
        else => return err,
    };
    defer dir.close(dvui.io);

    widget_hasher = .init();
    defer widget_hasher = null;

    if (@import("build_options").snapshot_image_suffix) |image_suffix| {
        const image_name = try std.fmt.allocPrint(self.allocator, "images/{s}-{s}.png", .{ filename, image_suffix });
        defer self.allocator.free(image_name);
        if (std.Io.Dir.path.dirname(image_name)) |sub| try dir.createDirPath(dvui.io, sub);
        var file = try dir.createFile(dvui.io, image_name, .{});
        defer file.close(dvui.io);

        var buf: [512]u8 = undefined;
        var writer = file.writer(dvui.io, &buf);
        try capturePng(frame, null, &writer.interface);
        try writer.end();
        // Do not continue with checking hashes as it is not deterministic across content_scales because
        // fonts render in integer steps and scaling changes the step used and the size of the test
        return; // Do not skip test because other snapshots might run after this one
    } else {
        _ = try step(frame);
    }

    const HashInt = u64;
    const hash: HashInt = widget_hasher.?.final();
    // used both for reading or writing the hash
    var hash_buf: [@sizeOf(HashInt) * 2]u8 = undefined;

    const file = dir.openFile(dvui.io, filename, .{ .mode = .read_write }) catch |err| switch (err) {
        std.Io.File.OpenError.FileNotFound => {
            if (should_write_snapshots()) {
                if (std.Io.Dir.path.dirname(filename)) |sub| try dir.createDirPath(dvui.io, sub);
                const file = try dir.createFile(dvui.io, filename, .{});
                defer file.close(dvui.io);
                var writer = file.writer(dvui.io, &hash_buf);
                try writer.interface.print("{X}", .{hash});
                try writer.end();
                std.log.info("Snapshot: Created file \"{s}\"\n", .{filename});
                return;
            }
            std.log.warn("{s}:{d}:{d}: Snapshot file did not exist! Run the test with `DVUI_SNAPSHOT_WRITE` to create all snapshot files\n", .{ src.file, src.line, src.column });
            return error.MissingSnapshotFile;
        },
        else => return err,
    };
    defer file.close(dvui.io);

    var read_buf: [64]u8 = undefined;
    var reader = file.reader(dvui.io, &read_buf);
    const len = try reader.interface.readSliceShort(&hash_buf);
    const prev_hash = try std.fmt.parseUnsigned(HashInt, hash_buf[0..len], 16);

    if (prev_hash != hash) {
        if (should_write_snapshots()) {
            var writer = file.writer(dvui.io, &hash_buf);
            try writer.seekTo(0);
            try writer.interface.print("{X}", .{hash});
            try writer.end();
            std.log.info("Snapshot: Overwrote file \"{s}\"\n", .{filename});
            return;
        }
        return SnapshotError.SnapshotsDidNotMatch;
    }
}

/// Formats `name` with characters that are not allowed in file names on common platforms,
/// including path separators, replaced by `_`
pub const SanitizedFileName = struct {
    name: []const u8,

    pub fn init(name: []const u8) SanitizedFileName {
        return .{ .name = name };
    }

    pub fn format(self: SanitizedFileName, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        for (self.name) |c| try writer.writeByte(sanitizeFileNameChar(c, false));
    }
};

/// Like `SanitizedFileName`, but keeps path separators
pub const SanitizedPath = struct {
    path: []const u8,

    pub fn init(path: []const u8) SanitizedPath {
        return .{ .path = path };
    }

    pub fn format(self: SanitizedPath, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        for (self.path) |c| try writer.writeByte(sanitizeFileNameChar(c, true));
    }
};

/// Replaces characters that are not allowed in file names on common platforms with `_`
fn sanitizeFileNameChar(c: u8, keep_separators: bool) u8 {
    return switch (c) {
        '/', '\\' => if (keep_separators) c else '_',
        0...0x1f, '<', '>', ':', '"', '|', '?', '*' => '_',
        else => c,
    };
}

fn should_ignore_snapshots() bool {
    // If there is a snapshot image suffix, we expect to generate images, thus not ignore the test
    return @import("build_options").snapshot_image_suffix == null and (Backend.kind != .testing or std.testing.environ.containsConstant("DVUI_SNAPSHOT_IGNORE"));
}

fn should_write_snapshots() bool {
    return !should_ignore_snapshots() and std.testing.environ.containsConstant("DVUI_SNAPSHOT_WRITE");
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

    var dir = try std.Io.Dir.cwd().createDirPathOpen(dvui.io, self.image_dir.?, .{});
    defer dir.close(dvui.io);
    if (std.Io.Dir.path.dirname(filename)) |sub| try dir.createDirPath(dvui.io, sub);
    const file = try dir.createFile(dvui.io, filename, .{});
    defer file.close(dvui.io);
    var buf: [512]u8 = undefined;
    var writer = file.writer(dvui.io, &buf);
    try capturePng(frame, rect, &writer.interface);
    try writer.end();
}

const Self = @This();

const std = @import("std");
const dvui = @import("dvui.zig");

const Backend = dvui.backend;
const Window = dvui.Window;

test {
    @import("std").testing.refAllDecls(@This());
}

test "Platform independent defaults" {
    {
        var t = try dvui.testing.init(.{});
        defer t.deinit();

        // Should always be in lightmode unless otherwise specified
        try std.testing.expect(!t.window.theme.dark);

        // Should always be windows unless otherwise specified
        // TODO: We use ctrl/cmd as a proxy for keybind platform, should probably
        //       be stored somewhere (maybe a key in the keybinds map?).
        try std.testing.expect(t.window.keybinds.get("ctrl/cmd").?.control.?);
    }
    {
        var t = try dvui.testing.init(.{
            .window_init_opts = .{ .color_scheme = .dark, .keybinds = .mac },
        });
        defer t.deinit();

        // Should be set to darkmode
        try std.testing.expect(t.window.theme.dark);

        // Should be set to `.mac`
        // TODO: We use ctrl/cmd as a proxy for keybind platform, should probably
        //       be stored somewhere (maybe a key in the keybinds map?).
        try std.testing.expect(t.window.keybinds.get("ctrl/cmd").?.command.?);
    }
}

test snapshot {
    if (should_ignore_snapshots()) {
        // Only the testing backend will always run this test.
        // To run under another backend (e.g. sdl3), make sure to
        // set -Dsnapshot-images=[before|after] to not ignore snapshots
        return error.SkipZigTest;
    }

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const snapshot_dir = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(snapshot_dir);

    var t = try dvui.testing.init(.{ .snapshot_dir = snapshot_dir });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            dvui.labelNoFmt(@src(), "test app", .{}, .{});
            return .ok;
        }
    }.frame;
    try settle(frame);

    const src = @src();

    if (should_write_snapshots()) {
        try t.snapshot(src, frame, .{});
    } else {
        // zig fails tests that write to stderr, but MissingSnapshotFile emits a warning.
        // We simply move the log level to error so that the warning isn't printed.
        const prev_log_level = std.testing.log_level;
        std.testing.log_level = .err;
        defer std.testing.log_level = prev_log_level;

        try std.testing.expectError(error.MissingSnapshotFile, t.snapshot(src, frame, .{}));
    }
}

test SanitizedPath {
    try std.testing.expectFmt("sub\\dir/a_b.zig", "{f}", .{SanitizedPath.init("sub\\dir/a:b.zig")});
    try std.testing.expectFmt("x_y_z _______", "{f}", .{SanitizedFileName.init("x/y\\z <*?\"|>\t")});
}

// Profiling aid: drives every demo window in `dvui.Examples` through the
// headless testing backend and records what each mapping data structure (the
// `TrackingAutoHashMap`s registered with `dvui.profiling`) did while that demo
// ran. Off unless `DVUI_DS_USAGE` is set, since it renders all 18 demos;
// `DVUI_DS_REPORT=<path>` writes the table out for reading afterwards.
//
// The assertion is the point of keeping it: the demos must actually reach the
// tracked maps, so a demo that silently stops rendering shows up here.
test "ds usage across every demo window" {
    if (!std.testing.environ.containsConstant("DVUI_DS_USAGE")) return error.SkipZigTest;

    var t = try dvui.testing.init(.{ .window_size = .{ .w = 1000, .h = 700 } });
    defer t.deinit();

    dvui.profiling.recording = true;
    defer dvui.profiling.recording = false;

    dvui.Examples.show_demo_window = true;
    defer dvui.Examples.show_demo_window = false;

    try settle(demoFrame);

    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try aw.writer.print("{s:<16} {s:<20} {s:>5} {s:>5} {s:>8} {s:>8} {s:>5} {s:>6} {s:>7}\n", .{
        "demo", "map", "live", "peak", "puts", "gets", "hit%", "dead", "rescans",
    });

    const Kind = dvui.Examples.demoKind;
    const kinds = std.enums.values(Kind);

    var prev = try dvui.profiling.sample(std.testing.allocator);
    defer std.testing.allocator.free(prev);
    try aw.writer.print("# recording={} maps={d}\n", .{ dvui.profiling.recording, prev.len });

    var rows: usize = 0;
    var demos: usize = 0;
    for (kinds) |kind| {
        // The demo list lives in the first pane; step back to it if the last
        // demo left the second pane showing.
        if (try clickIfPresent("dvui_demo_window_back")) try settle(demoFrame);

        var tag_buf: [64]u8 = undefined;
        const tag = try std.fmt.bufPrint(&tag_buf, "demo_button_{s}", .{@tagName(kind)});
        if (!try clickIfPresent(tag)) continue;
        demos += 1;
        try settle(demoFrame);
        // A few more frames so lazily built content (fonts, caches, images)
        // gets exercised too.
        for (0..3) |_| _ = try step(demoFrame);

        const after = try dvui.profiling.sample(std.testing.allocator);

        for (after, prev) |a, b| {
            try std.testing.expectEqualStrings(a.name, b.name);
            const d = dvui.profiling.Counters.delta(a.counters, b.counters);
            if (d.puts + d.gets + d.dead + d.rescans == 0) continue;
            try aw.writer.print("{s:<16} {s:<20} {d:>5} {d:>5} {d:>8} {d:>8} {d:>5.0} {d:>6} {d:>7}\n", .{
                @tagName(kind), a.name, d.live, d.peak, d.puts, d.gets, d.hitRate() * 100.0, d.dead, d.rescans,
            });
            rows += 1;
        }

        std.testing.allocator.free(prev);
        prev = after;
    }

    // The table is the deliverable. Nothing goes to stderr (zig fails a test
    // that writes there), so it is written where asked instead.
    if (std.testing.environ.getPosix("DVUI_DS_REPORT")) |path| {
        var file = try std.Io.Dir.cwd().createFile(dvui.io, path, .{});
        defer file.close(dvui.io);
        var buf: [4096]u8 = undefined;
        var fw = file.writer(dvui.io, &buf);
        try fw.interface.writeAll(aw.written());
        try fw.end();
    }

    try std.testing.expectEqual(kinds.len, demos);
    try std.testing.expect(rows >= kinds.len);
    try std.testing.expect(dvui.profiling.totals().gets > 0);
}

fn demoFrame() !dvui.App.Result {
    dvui.Examples.demo(.full);
    return .ok;
}

/// Moves the mouse onto `tag` and clicks it, if a widget with that tag exists
/// and is visible this frame.
fn clickIfPresent(tag: []const u8) !bool {
    if (dvui.tagGet(tag) == null) return false;
    moveTo(tag) catch return false;
    try click(.left);
    return true;
}
