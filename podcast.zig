const std = @import("std");
const gui = @import("src/gui.zig");
const Backend = @import("src/SDLBackend.zig");

const sqlite = @import("sqlite");

// when set to true, looks for feed-{rowid}.xml and episode-{rowid}.mp3 instead
// of fetching from network
const DEBUG = true;

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();
var arena: std.mem.Allocator = undefined;

const db_name = "podcast-db.sqlite3";
var g_db: ?sqlite.Db = null;

var g_quit = false;

const Episode = struct {
    title: []const u8,
};

fn dbErrorCallafter(id: u32, response: gui.DialogResponse) void {
    _ = id;
    _ = response;
    g_quit = true;
}

fn dbError(comptime fmt: []const u8, args: anytype) !void {
    gui.dialogOk(@src(), 0, true, "DB Error", try std.fmt.allocPrint(gpa, fmt, args), dbErrorCallafter);
}

fn dbRow(comptime query: []const u8, comptime return_type: type, values: anytype) !?return_type {
    if (g_db) |*db| {
        var stmt = db.prepare(query) catch {
            try dbError("{}\n\npreparing statement:\n\n{s}", .{ db.getDetailedError(), query });
            return error.DB_ERROR;
        };
        defer stmt.deinit();

        const row = stmt.oneAlloc(return_type, arena, .{}, values) catch {
            try dbError("{}\n\nexecuting statement:\n\n{s}", .{ db.getDetailedError(), query });
            return error.DB_ERROR;
        };

        return row;
    }

    return null;
}

fn dbInit() !void {
    g_db = sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = db_name },
        .open_flags = .{
            .write = true,
            .create = true,
        },
    }) catch |err| {
        try dbError("Can't open/create db:\n{s}\n{}", .{ db_name, err });
        return error.DB_ERROR;
    };

    _ = try dbRow("CREATE TABLE IF NOT EXISTS 'schema' (version INTEGER)", u8, .{});

    if (try dbRow("SELECT version FROM schema", u32, .{})) |version| {
        if (version != 1) {
            try dbError("{s}\n\nbad schema version: {d}", .{ db_name, version });
            return error.DB_ERROR;
        }
    } else {
        // new database
        _ = try dbRow("INSERT INTO schema (version) VALUES (1)", u8, .{});
        _ = try dbRow("CREATE TABLE podcast (url TEXT, error TEXT, title TEXT, description TEXT, copyright TEXT, pubDate INTEGER, lastBuildDate TEXT, link TEXT, image_url TEXT, speed REAL)", u8, .{});
        _ = try dbRow("CREATE TABLE episode (podcast_id INTEGER, visible INTEGER DEFAULT 1, guid TEXT, title TEXT, description TEXT, pubDate INTEGER, enclosure_url TEXT, position INTEGER, duration INTEGER)", u8, .{});
        _ = try dbRow("CREATE TABLE player (episode_id INTEGER)", u8, .{});
        _ = try dbRow("INSERT INTO player (episode_id) values (0)", u8, .{});
    }

    _ = try dbRow("UPDATE podcast SET error=NULL", u8, .{});
}

fn bgFetchFeed(rowid: u32, url: []const u8) !void {
    if (DEBUG) {
        var buf = std.mem.zeroes([256:0]u8);
        const filename = try std.fmt.bufPrint(&buf, "feed-{d}.xml", .{rowid});
        std.debug.print("  bgFetchFeed fetching {s}\n", .{filename});

        const file = std.fs.cwd().openFile(filename, .{}) catch |err| switch (err) {
            error.FileNotFound => return,
            else => |e| return e,
        };
        defer file.close();

        const contents = try file.readToEndAlloc(arena, 1024 * 1024 * 20);
        _ = contents;
    } else {
        _ = url;
    }
}

fn bgUpdateFeed(rowid: u32) !void {
    std.debug.print("bgUpdateFeed {d}\n", .{rowid});
    if (try dbRow("SELECT url FROM podcast WHERE rowid = ?", []const u8, .{rowid})) |url| {
        std.debug.print("  updating url {s}\n", .{url});
        var timer = try std.time.Timer.start();
        try bgFetchFeed(rowid, url);
        const timens = timer.read();
        std.debug.print("  fetch took {d}ms\n", .{timens / 1000000});
    }
}

fn mainGui() !void {
    //var float = gui.floatingWindow(@src(), 0, false, null, null, .{});
    //defer float.deinit();

    var window_box = gui.box(@src(), 0, .vertical, .{ .expand = .both, .color_style = .window, .background = true });
    defer window_box.deinit();

    var b = gui.box(@src(), 0, .vertical, .{ .expand = .both, .background = false });
    defer b.deinit();

    if (g_db) |db| {
        _ = db;
        var paned = try gui.paned(@src(), 0, .horizontal, 400, .{ .expand = .both, .background = false });
        const collapsed = paned.collapsed();

        try podcastSide(paned);
        try episodeSide(paned);

        paned.deinit();

        if (collapsed) {
            try player();
        }
    }
}

pub fn main() !void {
    var backend = try Backend.init(360, 600);
    defer backend.deinit();

    var win = gui.Window.init(gpa, backend.guiBackend());
    defer win.deinit();

    dbInit() catch |err| switch (err) {
        error.DB_ERROR => {},
        else => return err,
    };

    main_loop: while (true) {
        var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena_allocator.deinit();
        arena = arena_allocator.allocator();

        var nstime = win.beginWait(backend.hasEvent());
        win.begin(arena, nstime);

        const quit = backend.addAllEvents(&win);
        if (quit) break :main_loop;
        if (g_quit) break :main_loop;

        backend.clear();

        //_ = gui.examples.demo();

        mainGui() catch |err| switch (err) {
            error.DB_ERROR => {},
            else => return err,
        };

        const end_micros = try win.end();

        backend.setCursor(win.cursorRequested());

        backend.renderPresent();

        const wait_event_micros = win.wait(end_micros, null);

        backend.waitEventTimeout(wait_event_micros);
    }
}

var add_rss_dialog: bool = false;

fn podcastSide(paned: *gui.PanedWidget) !void {
    var b = gui.box(@src(), 0, .vertical, .{ .expand = .both });
    defer b.deinit();

    {
        var overlay = gui.overlay(@src(), 0, .{ .expand = .horizontal });
        defer overlay.deinit();

        {
            var menu = gui.menu(@src(), 0, .horizontal, .{ .expand = .horizontal });
            defer menu.deinit();

            _ = gui.spacer(@src(), 0, .{ .expand = .horizontal });

            if (gui.menuItemIcon(@src(), 0, true, try gui.themeGet().font_heading.lineSkip(), "toolbar dots", gui.icons.papirus.actions.xapp_prefs_toolbar_symbolic, .{})) |r| {
                var fw = gui.popup(@src(), 0, gui.Rect.fromPoint(gui.Point{ .x = r.x, .y = r.y + r.h }), .{});
                defer fw.deinit();
                if (try gui.menuItemLabel(@src(), 0, "Add RSS", false, .{})) |rr| {
                    _ = rr;
                    gui.menuGet().?.close();
                    add_rss_dialog = true;
                }

                if (try gui.menuItemLabel(@src(), 0, "Update All", false, .{})) |rr| {
                    _ = rr;
                    gui.menuGet().?.close();
                    if (g_db) |*db| {
                        const query = "SELECT rowid FROM podcast";
                        var stmt = db.prepare(query) catch {
                            try dbError("{}\n\npreparing statement:\n\n{s}", .{ db.getDetailedError(), query });
                            return error.DB_ERROR;
                        };
                        defer stmt.deinit();

                        var iter = try stmt.iterator(u32, .{});
                        while (try iter.nextAlloc(arena, .{})) |rowid| {
                            try bgUpdateFeed(rowid);
                        }
                    }
                }
            }
        }

        try gui.label(@src(), 0, "fps {d}", .{@round(gui.FPS())}, .{});
    }

    if (add_rss_dialog) {
        var dialog = gui.floatingWindow(@src(), 0, true, null, &add_rss_dialog, .{});
        defer dialog.deinit();

        try gui.labelNoFmt(@src(), 0, "Add RSS Feed", .{ .gravity = .center });

        const TextEntryText = struct {
            var text = [_]u8{0} ** 100;
        };

        var te = gui.TextEntryWidget.init(@src(), 0, 26.0, &TextEntryText.text, .{ .gravity = .center });
        if (gui.firstFrame(te.data().id)) {
            std.mem.set(u8, &TextEntryText.text, 0);
            gui.focusWidget(te.wd.id, null);
        }
        try te.install(.{});
        te.deinit();

        var box2 = gui.box(@src(), 0, .horizontal, .{ .gravity = .right });
        defer box2.deinit();
        if (try gui.button(@src(), 0, "Ok", .{})) {
            dialog.close();
            const url = std.mem.trim(u8, &TextEntryText.text, " \x00");
            const row = try dbRow("SELECT rowid FROM podcast WHERE url = ?", i32, .{url});
            if (row) |_| {
                gui.dialogOk(@src(), 0, true, "Note", try std.fmt.allocPrint(arena, "url already in db:\n\n{s}", .{url}), null);
            } else {
                _ = try dbRow("INSERT INTO podcast (url) VALUES (?)", i32, .{url});
                if (g_db) |*db| {
                    const rowid = db.getLastInsertRowID();
                    _ = rowid;
                }
            }
        }
        if (try gui.button(@src(), 0, "Cancel", .{})) {
            dialog.close();
        }
    }

    var scroll = gui.scrollArea(@src(), 0, null, .{ .expand = .both, .color_style = .window, .background = false });

    const oo3 = gui.Options{
        .expand = .horizontal,
        .gravity = .left,
        .color_style = .content,
    };

    var i: usize = 1;
    var buf: [256]u8 = undefined;
    while (i < 8) : (i += 1) {
        const title = std.fmt.bufPrint(&buf, "Podcast {d}", .{i}) catch unreachable;
        var margin: gui.Rect = .{ .x = 8, .y = 0, .w = 8, .h = 0 };
        var border: gui.Rect = .{ .x = 1, .y = 0, .w = 1, .h = 0 };
        var corner = gui.Rect.all(0);

        if (i != 1) {
            gui.separator(@src(), i, oo3.override(.{ .margin = margin }));
        }

        if (i == 1) {
            margin.y = 8;
            border.y = 1;
            corner.x = 9;
            corner.y = 9;
        } else if (i == 7) {
            margin.h = 8;
            border.h = 1;
            corner.w = 9;
            corner.h = 9;
        }

        if (try gui.button(@src(), i, title, oo3.override(.{
            .margin = margin,
            .border = border,
            .corner_radius = corner,
            .padding = gui.Rect.all(8),
        }))) {
            paned.showOther();
        }
    }

    scroll.deinit();

    if (!paned.collapsed()) {
        try player();
    }
}

fn episodeSide(paned: *gui.PanedWidget) !void {
    var b = gui.box(@src(), 0, .vertical, .{ .expand = .both });
    defer b.deinit();

    if (paned.collapsed()) {
        var menu = gui.menu(@src(), 0, .horizontal, .{ .expand = .horizontal });
        defer menu.deinit();

        if (try gui.menuItemLabel(@src(), 0, "Back", false, .{})) |rr| {
            _ = rr;
            paned.showOther();
        }
    }

    var scroll = gui.scrollArea(@src(), 0, null, .{ .expand = .both, .background = false });
    defer scroll.deinit();

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var tl = gui.textLayout(@src(), i, .{ .expand = .horizontal });

        var cbox = gui.box(@src(), 0, .vertical, gui.Options{ .gravity = .upright });

        _ = gui.buttonIcon(@src(), 0, 18, "play", gui.icons.papirus.actions.media_playback_start_symbolic, .{ .padding = gui.Rect.all(6) });
        _ = gui.buttonIcon(@src(), 0, 18, "more", gui.icons.papirus.actions.view_more_symbolic, .{ .padding = gui.Rect.all(6) });

        cbox.deinit();

        var f = gui.themeGet().font_heading;
        f.line_skip_factor = 1.3;
        try tl.addText("Episode Title\n", .{ .font_style = .custom, .font_custom = f });
        const lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.";
        try tl.addText(lorem, .{});
        tl.deinit();
    }
}

fn player() !void {
    const oo = gui.Options{
        .expand = .horizontal,
        .color_style = .content,
    };

    var box2 = gui.box(@src(), 0, .vertical, oo.override(.{ .background = true }));
    defer box2.deinit();

    var episode = Episode{ .title = "Episode Title" };

    const episode_id = try dbRow("SELECT episode_id FROM player", i32, .{});
    if (episode_id) |id| {
        episode = try dbRow("SELECT title FROM episode WHERE rowid = ?", Episode, .{id}) orelse episode;
    }

    try gui.label(@src(), 0, "{s}", .{episode.title}, oo.override(.{
        .margin = gui.Rect{ .x = 8, .y = 4, .w = 8, .h = 4 },
        .font_style = .heading,
    }));

    var box3 = gui.box(@src(), 0, .horizontal, oo.override(.{ .padding = .{ .x = 4, .y = 0, .w = 4, .h = 4 } }));
    defer box3.deinit();

    const oo2 = gui.Options{ .expand = .horizontal, .gravity = .center };

    _ = gui.buttonIcon(@src(), 0, 20, "back", gui.icons.papirus.actions.media_seek_backward_symbolic, oo2);

    try gui.label(@src(), 0, "0.00%", .{}, oo2.override(.{ .color_style = .content }));

    _ = gui.buttonIcon(@src(), 0, 20, "forward", gui.icons.papirus.actions.media_seek_forward_symbolic, oo2);

    _ = gui.buttonIcon(@src(), 0, 20, "play", gui.icons.papirus.actions.media_playback_start_symbolic, oo2);
}
