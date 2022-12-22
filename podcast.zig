const std = @import("std");
const gui = @import("src/gui.zig");
const Backend = @import("src/SDLBackend.zig");

const sqlite = @import("sqlite");
const curl = @import("curl");

pub const c = @cImport({
    @cDefine("_XOPEN_SOURCE", "1");
    @cInclude("time.h");

    @cInclude("locale.h");

    @cInclude("libxml/parser.h");

    @cDefine("LIBXML_XPATH_ENABLED", "1");
    @cInclude("libxml/xpath.h");
    @cInclude("libxml/xpathInternals.h");

    @cInclude("libavformat/avformat.h");
    @cInclude("libavcodec/avcodec.h");
    @cInclude("libswresample/swresample.h");
});

// when set to true, looks for feed-{rowid}.xml and episode-{rowid}.mp3 instead
// of fetching from network
const DEBUG = true;

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const db_name = "podcast-db.sqlite3";
var g_db: ?sqlite.Db = null;

var g_quit = false;

var g_podcast_id_on_right: usize = 0;

var g_audio_device: u32 = undefined;
var g_audio_spec: Backend.c.SDL_AudioSpec = undefined;

const Episode = struct {
    rowid: usize,
    title: []const u8,
    description: []const u8,
    position: f64,
    duration: f64,
};

fn dbErrorCallafter(id: u32, response: gui.DialogResponse) gui.Error!void {
    _ = id;
    _ = response;
    g_quit = true;
}

fn dbError(comptime fmt: []const u8, args: anytype) !void {
    try gui.dialogOk(@src(), 0, true, "DB Error", try std.fmt.allocPrint(gpa, fmt, args), dbErrorCallafter);
}

fn dbRow(arena: std.mem.Allocator, comptime query: []const u8, comptime return_type: type, values: anytype) !?return_type {
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

fn dbInit(arena: std.mem.Allocator) !void {
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

    _ = try dbRow(arena, "CREATE TABLE IF NOT EXISTS 'schema' (version INTEGER)", u8, .{});

    if (try dbRow(arena, "SELECT version FROM schema", u32, .{})) |version| {
        if (version != 1) {
            try dbError("{s}\n\nbad schema version: {d}", .{ db_name, version });
            return error.DB_ERROR;
        }
    } else {
        // new database
        _ = try dbRow(arena, "INSERT INTO schema (version) VALUES (1)", u8, .{});
        _ = try dbRow(arena, "CREATE TABLE podcast (url TEXT, title TEXT, description TEXT, copyright TEXT, pubDate INTEGER, lastBuildDate TEXT, link TEXT, image_url TEXT, speed REAL)", u8, .{});
        _ = try dbRow(arena, "CREATE TABLE episode (podcast_id INTEGER, visible INTEGER DEFAULT 1, guid TEXT, title TEXT, description TEXT, pubDate INTEGER, enclosure_url TEXT, position REAL, duration REAL)", u8, .{});
        _ = try dbRow(arena, "CREATE TABLE player (episode_id INTEGER)", u8, .{});
        _ = try dbRow(arena, "INSERT INTO player (episode_id) values (0)", u8, .{});
    }
}

pub fn getContent(xpathCtx: *c.xmlXPathContext, node_name: [:0]const u8, attr_name: ?[:0]const u8) ?[]u8 {
    var xpathObj = c.xmlXPathEval(node_name.ptr, xpathCtx);
    defer c.xmlXPathFreeObject(xpathObj);
    if (xpathObj.*.nodesetval.*.nodeNr >= 1) {
        if (attr_name) |attr| {
            var data = c.xmlGetProp(xpathObj.*.nodesetval.*.nodeTab[0], attr.ptr);
            return std.mem.sliceTo(data, 0);
        } else {
            return std.mem.sliceTo(xpathObj.*.nodesetval.*.nodeTab[0].*.children.*.content, 0);
        }
    }

    return null;
}

fn bgFetchFeed(arena: std.mem.Allocator, rowid: u32, url: []const u8) !void {
    var buf: [256]u8 = undefined;
    var contents: [:0]const u8 = undefined;
    if (DEBUG) {
        const filename = try std.fmt.bufPrint(&buf, "feed-{d}.xml", .{rowid});
        std.debug.print("  bgFetchFeed fetching {s}\n", .{filename});

        const file = std.fs.cwd().openFile(filename, .{}) catch |err| switch (err) {
            error.FileNotFound => return,
            else => |e| return e,
        };
        defer file.close();

        contents = try file.readToEndAllocOptions(arena, 1024 * 1024 * 20, null, @alignOf(u8), 0);
    } else {
        std.debug.print("  bgFetchFeed fetching {s}\n", .{url});

        var easy = try curl.Easy.init();
        defer easy.cleanup();

        const urlZ = try std.fmt.bufPrintZ(&buf, "{s}", .{url});
        try easy.setUrl(urlZ);
        try easy.setSslVerifyPeer(false);
        try easy.setAcceptEncodingGzip();

        const Fifo = std.fifo.LinearFifo(u8, .{ .Dynamic = {} });
        try easy.setWriteFn(struct {
            fn writeFn(ptr: ?[*]u8, size: usize, nmemb: usize, data: ?*anyopaque) callconv(.C) usize {
                _ = size;
                var slice = (ptr orelse return 0)[0..nmemb];
                const fifo = @ptrCast(
                    *Fifo,
                    @alignCast(
                        @alignOf(*Fifo),
                        data orelse return 0,
                    ),
                );

                fifo.writer().writeAll(slice) catch return 0;
                return nmemb;
            }
        }.writeFn);

        // don't deinit the fifo, it's using arena anyway and we need the contents later
        var fifo = Fifo.init(arena);
        try easy.setWriteData(&fifo);
        try easy.setVerbose(true);
        easy.perform() catch |err| {
            try gui.dialogOk(@src(), 0, true, "Network Error", try std.fmt.allocPrint(arena, "curl error {!}\ntrying to fetch url:\n{s}", .{ err, url }), null);
        };
        const code = try easy.getResponseCode();
        std.debug.print("  bgFetchFeed curl code {d}\n", .{code});

        // add null byte
        try fifo.writeItem(0);

        const tempslice = fifo.readableSlice(0);
        contents = tempslice[0 .. tempslice.len - 1 :0];

        const filename = try std.fmt.bufPrint(&buf, "feed-{d}.xml", .{rowid});
        const file = std.fs.cwd().createFile(filename, .{}) catch |err| switch (err) {
            error.FileNotFound => return,
            else => |e| return e,
        };
        defer file.close();

        try file.writeAll(contents);
    }

    const doc = c.xmlReadDoc(contents.ptr, null, null, 0);
    defer c.xmlFreeDoc(doc);

    var xpathCtx = c.xmlXPathNewContext(doc);
    defer c.xmlXPathFreeContext(xpathCtx);
    _ = c.xmlXPathRegisterNs(xpathCtx, "itunes", "http://www.itunes.com/dtds/podcast-1.0.dtd");

    {
        var xpathObj = c.xmlXPathEval("/rss/channel", xpathCtx);
        defer c.xmlXPathFreeObject(xpathObj);

        if (xpathObj.*.nodesetval.*.nodeNr > 0) {
            const node = xpathObj.*.nodesetval.*.nodeTab[0];
            _ = c.xmlXPathSetContextNode(node, xpathCtx);

            if (getContent(xpathCtx, "title", null)) |str| {
                _ = try dbRow(arena, "UPDATE podcast SET title=? WHERE rowid=?", i32, .{ str, rowid });
            }

            if (getContent(xpathCtx, "description", null)) |str| {
                _ = try dbRow(arena, "UPDATE podcast SET description=? WHERE rowid=?", i32, .{ str, rowid });
            }

            if (getContent(xpathCtx, "copyright", null)) |str| {
                _ = try dbRow(arena, "UPDATE podcast SET copyright=? WHERE rowid=?", i32, .{ str, rowid });
            }

            if (getContent(xpathCtx, "pubDate", null)) |str| {
                _ = c.setlocale(c.LC_ALL, "C");
                var tm: c.struct_tm = undefined;
                _ = c.strptime(str.ptr, "%a, %e %h %Y %H:%M:%S %z", &tm);
                _ = c.strftime(&buf, buf.len, "%s", &tm);
                _ = c.setlocale(c.LC_ALL, "");

                _ = try dbRow(arena, "UPDATE podcast SET pubDate=? WHERE rowid=?", i32, .{ std.mem.sliceTo(&buf, 0), rowid });
            }

            if (getContent(xpathCtx, "lastBuildDate", null)) |str| {
                _ = try dbRow(arena, "UPDATE podcast SET lastBuildDate=? WHERE rowid=?", i32, .{ str, rowid });
            }

            if (getContent(xpathCtx, "link", null)) |str| {
                _ = try dbRow(arena, "UPDATE podcast SET link=? WHERE rowid=?", i32, .{ str, rowid });
            }

            if (getContent(xpathCtx, "image/url", null)) |str| {
                _ = try dbRow(arena, "UPDATE podcast SET image_url=? WHERE rowid=?", i32, .{ str, rowid });
            }
        }
    }

    {
        var xpathObj = c.xmlXPathEval("//item", xpathCtx);
        defer c.xmlXPathFreeObject(xpathObj);

        var i: usize = 0;
        while (i < xpathObj.*.nodesetval.*.nodeNr) : (i += 1) {
            std.debug.print("node {d}\n", .{i});

            const node = xpathObj.*.nodesetval.*.nodeTab[i];
            _ = c.xmlXPathSetContextNode(node, xpathCtx);

            var episodeRow: ?i64 = null;
            if (getContent(xpathCtx, "guid", null)) |str| {
                if (try dbRow(arena, "SELECT rowid FROM episode WHERE podcast_id=? AND guid=?", i64, .{ rowid, str })) |erow| {
                    std.debug.print("podcast {d} existing episode {d} guid {s}\n", .{ rowid, erow, str });
                    episodeRow = erow;
                } else {
                    std.debug.print("podcast {d} new episode guid {s}\n", .{ rowid, str });
                    _ = try dbRow(arena, "INSERT INTO episode (podcast_id, guid) VALUES (?, ?)", i64, .{ rowid, str });
                    if (g_db) |*db| {
                        episodeRow = db.getLastInsertRowID();
                    }
                }
            } else if (getContent(xpathCtx, "title", null)) |str| {
                if (try dbRow(arena, "SELECT rowid FROM episode WHERE podcast_id=? AND title=?", i64, .{ rowid, str })) |erow| {
                    std.debug.print("podcast {d} existing episode {d} title {s}\n", .{ rowid, erow, str });
                    episodeRow = erow;
                } else {
                    std.debug.print("podcast {d} new episode title {s}\n", .{ rowid, str });
                    _ = try dbRow(arena, "INSERT INTO episode (podcast_id, title) VALUES (?, ?)", i64, .{ rowid, str });
                    if (g_db) |*db| {
                        episodeRow = db.getLastInsertRowID();
                    }
                }
            } else if (getContent(xpathCtx, "description", null)) |str| {
                if (try dbRow(arena, "SELECT rowid FROM episode WHERE podcast_id=? AND description=?", i64, .{ rowid, str })) |erow| {
                    std.debug.print("podcast {d} existing episode {d} description {s}\n", .{ rowid, erow, str });
                    episodeRow = erow;
                } else {
                    std.debug.print("podcast {d} new episode description {s}\n", .{ rowid, str });
                    _ = try dbRow(arena, "INSERT INTO episode (podcast_id, description) VALUES (?, ?)", i64, .{ rowid, str });
                    if (g_db) |*db| {
                        episodeRow = db.getLastInsertRowID();
                    }
                }
            }

            if (episodeRow) |erow| {
                if (getContent(xpathCtx, "guid", null)) |str| {
                    _ = try dbRow(arena, "UPDATE episode SET guid=? WHERE rowid=?", i32, .{ str, erow });
                }

                if (getContent(xpathCtx, "title", null)) |str| {
                    _ = try dbRow(arena, "UPDATE episode SET title=? WHERE rowid=?", i32, .{ str, erow });
                }

                if (getContent(xpathCtx, "description", null)) |str| {
                    _ = try dbRow(arena, "UPDATE episode SET description=? WHERE rowid=?", i32, .{ str, erow });
                }

                if (getContent(xpathCtx, "pubDate", null)) |str| {
                    _ = c.setlocale(c.LC_ALL, "C");
                    var tm: c.struct_tm = undefined;
                    _ = c.strptime(str.ptr, "%a, %e %h %Y %H:%M:%S %z", &tm);
                    _ = c.strftime(&buf, buf.len, "%s", &tm);
                    _ = c.setlocale(c.LC_ALL, "");

                    _ = try dbRow(arena, "UPDATE episode SET pubDate=? WHERE rowid=?", i32, .{ std.mem.sliceTo(&buf, 0), erow });
                }

                if (getContent(xpathCtx, "enclosure", "url")) |str| {
                    _ = try dbRow(arena, "UPDATE episode SET enclosure_url=? WHERE rowid=?", i32, .{ str, erow });
                }

                if (getContent(xpathCtx, "itunes:duration", null)) |str| {
                    std.debug.print("duration: {s}\n", .{str});
                    var it = std.mem.splitBackwards(u8, str, ":");
                    const secs = std.fmt.parseInt(u32, it.first(), 10) catch 0;
                    const mins = std.fmt.parseInt(u32, it.next() orelse "0", 10) catch 0;
                    const hrs = std.fmt.parseInt(u32, it.next() orelse "0", 10) catch 0;

                    const dur = @intToFloat(f64, secs) + 60.0 * @intToFloat(f64, mins) + 60.0 * 60.0 * @intToFloat(f64, hrs);

                    _ = try dbRow(arena, "UPDATE episode SET duration=? WHERE rowid=?", i32, .{ dur, erow });
                }
            }
        }
    }
}

fn bgUpdateFeed(arena: std.mem.Allocator, rowid: u32) !void {
    std.debug.print("bgUpdateFeed {d}\n", .{rowid});
    if (try dbRow(arena, "SELECT url FROM podcast WHERE rowid = ?", []const u8, .{rowid})) |url| {
        std.debug.print("  updating url {s}\n", .{url});
        var timer = try std.time.Timer.start();
        try bgFetchFeed(arena, rowid, url);
        const timens = timer.read();
        std.debug.print("  fetch took {d}ms\n", .{timens / 1000000});
    }
}

fn mainGui(arena: std.mem.Allocator) !void {
    //var float = gui.floatingWindow(@src(), 0, false, null, null, .{});
    //defer float.deinit();

    var window_box = try gui.box(@src(), 0, .vertical, .{ .expand = .both, .color_style = .window, .background = true });
    defer window_box.deinit();

    var b = try gui.box(@src(), 0, .vertical, .{ .expand = .both, .background = false });
    defer b.deinit();

    if (g_db) |db| {
        _ = db;
        var paned = try gui.paned(@src(), 0, .horizontal, 400, .{ .expand = .both, .background = false });
        const collapsed = paned.collapsed();

        try podcastSide(arena, paned);
        try episodeSide(arena, paned);

        paned.deinit();

        if (collapsed) {
            try player(arena);
        }
    }
}

pub fn main() !void {
    var backend = try Backend.init(360, 600);
    defer backend.deinit();

    var win = gui.Window.init(gpa, backend.guiBackend());
    defer win.deinit();

    {
        var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena_allocator.deinit();
        var arena = arena_allocator.allocator();
        dbInit(arena) catch |err| switch (err) {
            error.DB_ERROR => {},
            else => return err,
        };
    }

    if (Backend.c.SDL_InitSubSystem(Backend.c.SDL_INIT_AUDIO) < 0) {
        std.debug.print("Couldn't initialize SDL audio: {s}\n", .{Backend.c.SDL_GetError()});
        return error.BackendError;
    }

    var wanted_spec = std.mem.zeroes(Backend.c.SDL_AudioSpec);
    wanted_spec.freq = 44100;
    wanted_spec.format = Backend.c.AUDIO_S16SYS;
    wanted_spec.channels = 2;
    wanted_spec.callback = audio_callback;

    g_audio_device = Backend.c.SDL_OpenAudioDevice(null, 0, &wanted_spec, &g_audio_spec, 0);
    if (g_audio_device <= 1) {
        std.debug.print("SDL_OpenAudioDevice error: {s}\n", .{Backend.c.SDL_GetError()});
        return error.BackendError;
    }

    std.debug.print("audio device {d} spec: {}\n", .{ g_audio_device, g_audio_spec });

    const pt = try std.Thread.spawn(.{}, playback_thread, .{});
    pt.detach();

    main_loop: while (true) {
        var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena_allocator.deinit();
        var arena = arena_allocator.allocator();

        var nstime = win.beginWait(backend.hasEvent());
        try win.begin(arena, nstime);

        const quit = try backend.addAllEvents(&win);
        if (quit) break :main_loop;
        if (g_quit) break :main_loop;

        backend.clear();

        //_ = gui.examples.demo();

        mainGui(arena) catch |err| switch (err) {
            error.DB_ERROR => {},
            else => return err,
        };

        const end_micros = try win.end();

        backend.setCursor(win.cursorRequested());

        backend.renderPresent();

        const wait_event_micros = win.waitTime(end_micros, null);

        backend.waitEventTimeout(wait_event_micros);
    }
}

var add_rss_dialog: bool = false;

fn podcastSide(arena: std.mem.Allocator, paned: *gui.PanedWidget) !void {
    var b = try gui.box(@src(), 0, .vertical, .{ .expand = .both });
    defer b.deinit();

    {
        var overlay = try gui.overlay(@src(), 0, .{ .expand = .horizontal });
        defer overlay.deinit();

        {
            var menu = try gui.menu(@src(), 0, .horizontal, .{ .expand = .horizontal });
            defer menu.deinit();

            _ = gui.spacer(@src(), 0, .{}, .{ .expand = .horizontal });

            if (try gui.menuItemIcon(@src(), 0, true, "toolbar dots", gui.icons.papirus.actions.xapp_prefs_toolbar_symbolic, .{ .expand = .none })) |r| {
                var fw = try gui.popup(@src(), 0, gui.Rect.fromPoint(gui.Point{ .x = r.x, .y = r.y + r.h }), .{});
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
                            try bgUpdateFeed(arena, rowid);
                        }
                    }
                }
            }
        }

        try gui.label(@src(), 0, "fps {d}", .{@round(gui.FPS())}, .{});
    }

    if (add_rss_dialog) {
        var dialog = try gui.floatingWindow(@src(), 0, true, null, &add_rss_dialog, .{});
        defer dialog.deinit();

        try gui.labelNoFmt(@src(), 0, "Add RSS Feed", .{ .gravity = .center });

        const TextEntryText = struct {
            var text = [_]u8{0} ** 100;
        };

        const msize = gui.TextEntryWidget.defaults.font().textSize("M") catch unreachable;
        var te = gui.TextEntryWidget.init(@src(), 0, &TextEntryText.text, .{ .gravity = .center, .min_size_content = .{ .w = msize.w * 26.0, .h = msize.h } });
        if (gui.firstFrame(te.data().id)) {
            std.mem.set(u8, &TextEntryText.text, 0);
            gui.focusWidget(te.wd.id, null);
        }
        try te.install(.{});
        te.deinit();

        var box2 = try gui.box(@src(), 0, .horizontal, .{ .gravity = .right });
        defer box2.deinit();
        if (try gui.button(@src(), 0, "Ok", .{})) {
            dialog.close();
            const url = std.mem.trim(u8, &TextEntryText.text, " \x00");
            const row = try dbRow(arena, "SELECT rowid FROM podcast WHERE url = ?", i32, .{url});
            if (row) |_| {
                try gui.dialogOk(@src(), 0, true, "Note", try std.fmt.allocPrint(arena, "url already in db:\n\n{s}", .{url}), null);
            } else {
                _ = try dbRow(arena, "INSERT INTO podcast (url) VALUES (?)", i32, .{url});
                if (g_db) |*db| {
                    const rowid = db.getLastInsertRowID();
                    try bgUpdateFeed(arena, @intCast(u32, rowid));
                }
            }
        }
        if (try gui.button(@src(), 0, "Cancel", .{})) {
            dialog.close();
        }
    }

    var scroll = try gui.scrollArea(@src(), 0, .{ .expand = .both, .color_style = .window, .background = false });

    const oo3 = gui.Options{
        .expand = .horizontal,
        .gravity = .left,
        .color_style = .content,
    };

    if (g_db) |*db| {
        const num_podcasts = try dbRow(arena, "SELECT count(*) FROM podcast", usize, .{});

        const query = "SELECT rowid FROM podcast";
        var stmt = db.prepare(query) catch {
            try dbError("{}\n\npreparing statement:\n\n{s}", .{ db.getDetailedError(), query });
            return error.DB_ERROR;
        };
        defer stmt.deinit();

        var iter = try stmt.iterator(u32, .{});
        var i: usize = 1;
        while (try iter.nextAlloc(arena, .{})) |rowid| {
            defer i += 1;

            const title = try dbRow(arena, "SELECT title FROM podcast WHERE rowid=?", []const u8, .{rowid}) orelse "Error: No Title";
            var margin: gui.Rect = .{ .x = 8, .y = 0, .w = 8, .h = 0 };
            var border: gui.Rect = .{ .x = 1, .y = 0, .w = 1, .h = 0 };
            var corner = gui.Rect.all(0);

            if (i != 1) {
                try gui.separator(@src(), i, oo3.override(.{ .margin = margin }));
            }

            if (i == 1) {
                margin.y = 8;
                border.y = 1;
                corner.x = 9;
                corner.y = 9;
            }

            if (i == num_podcasts) {
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
                g_podcast_id_on_right = rowid;
                paned.showOther();
            }
        }
    }

    scroll.deinit();

    if (!paned.collapsed()) {
        try player(arena);
    }
}

fn episodeSide(arena: std.mem.Allocator, paned: *gui.PanedWidget) !void {
    var b = try gui.box(@src(), 0, .vertical, .{ .expand = .both });
    defer b.deinit();

    if (paned.collapsed()) {
        var menu = try gui.menu(@src(), 0, .horizontal, .{ .expand = .horizontal });
        defer menu.deinit();

        if (try gui.menuItemLabel(@src(), 0, "Back", false, .{ .expand = .none })) |rr| {
            _ = rr;
            paned.showOther();
        }
    }

    if (g_db) |*db| {
        const num_episodes = try dbRow(arena, "SELECT count(*) FROM episode WHERE podcast_id = ?", usize, .{g_podcast_id_on_right}) orelse 0;
        const height: f32 = 150;

        var scroll = try gui.scrollArea(@src(), 0, .{ .expand = .both, .background = false });
        scroll.setVirtualSize(.{ .w = 0, .h = height * @intToFloat(f32, num_episodes) });
        defer scroll.deinit();

        const query = "SELECT rowid, title, description, position, duration FROM episode WHERE podcast_id = ?";
        var stmt = db.prepare(query) catch {
            try dbError("{}\n\npreparing statement:\n\n{s}", .{ db.getDetailedError(), query });
            return error.DB_ERROR;
        };
        defer stmt.deinit();

        const visibleRect = scroll.scroll_info.viewport;
        var cursor: f32 = 0;

        var iter = try stmt.iterator(Episode, .{g_podcast_id_on_right});
        while (try iter.nextAlloc(arena, .{})) |episode| {
            defer cursor += height;
            const r = gui.Rect{ .x = 0, .y = cursor, .w = 0, .h = height };
            if (visibleRect.intersect(r).h > 0) {
                var tl = try gui.textLayout(@src(), episode.rowid, .{ .expand = .horizontal, .rect = r });
                defer tl.deinit();

                var cbox = try gui.box(@src(), 0, .vertical, gui.Options{ .gravity = .upright });

                _ = try gui.buttonIcon(@src(), 0, 18, "play", gui.icons.papirus.actions.media_playback_start_symbolic, .{ .padding = gui.Rect.all(6) });
                _ = try gui.buttonIcon(@src(), 0, 18, "more", gui.icons.papirus.actions.view_more_symbolic, .{ .padding = gui.Rect.all(6) });

                cbox.deinit();

                const hrs = @floor(episode.duration / 60.0 / 60.0);
                const mins = @floor((episode.duration - (hrs * 60.0 * 60.0)) / 60.0);
                const secs = @floor(episode.duration - (hrs * 60.0 * 60.0) - (mins * 60.0));
                try gui.label(@src(), 0, "{d:0>2}:{d:0>2}:{d:0>2}", .{ hrs, mins, secs }, .{ .font_style = .heading, .gravity = .downright });

                var f = gui.themeGet().font_heading;
                f.line_skip_factor = 1.3;
                try tl.format("{s}\n", .{episode.title}, .{ .font_style = .custom, .font_custom = f });
                //const lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.";
                //try tl.addText(lorem, .{});
                try tl.addText(episode.description, .{});
            }
        }
    }
}

fn player(arena: std.mem.Allocator) !void {
    const oo = gui.Options{
        .expand = .horizontal,
        .color_style = .content,
    };

    var box2 = try gui.box(@src(), 0, .vertical, oo.override(.{ .background = true }));
    defer box2.deinit();

    var episode = Episode{ .rowid = 0, .title = "Episode Title", .description = "", .position = 0, .duration = 0 };

    const episode_id = try dbRow(arena, "SELECT episode_id FROM player", i32, .{});
    if (episode_id) |id| {
        episode = try dbRow(arena, "SELECT rowid, title FROM episode WHERE rowid = ?", Episode, .{id}) orelse episode;
    }

    try gui.label(@src(), 0, "{s}", .{episode.title}, oo.override(.{
        .margin = gui.Rect{ .x = 8, .y = 4, .w = 8, .h = 4 },
        .font_style = .heading,
    }));

    var box3 = try gui.box(@src(), 0, .horizontal, oo.override(.{ .padding = .{ .x = 4, .y = 0, .w = 4, .h = 4 } }));
    defer box3.deinit();

    const oo2 = gui.Options{ .expand = .both, .gravity = .center };

    mutex.lock();
    if (try gui.buttonIcon(@src(), 0, 20, "back", gui.icons.papirus.actions.media_seek_backward_symbolic, oo2)) {
        stream_seek_time = std.math.max(0.0, current_time - 5.0);
        buffer.discard(buffer.readableLength());
        buffer_last_time = stream_seek_time.?;
        current_time = stream_seek_time.?;
        condition.signal();
    }

    const time_max_size = oo2.font().textSize("0:00:00") catch unreachable;
    try gui.label(@src(), 0, "0:00:{d:0>2.0}", .{current_time}, oo2.override(.{ .min_size_content = time_max_size }));

    if (try gui.buttonIcon(@src(), 0, 20, if (playing) "pause" else "play", if (playing) gui.icons.papirus.actions.media_playback_pause_symbolic else gui.icons.papirus.actions.media_playback_start_symbolic, oo2)) {
        if (playing) {
            pause();
        } else {
            play();
        }
    }

    if (try gui.buttonIcon(@src(), 0, 20, "forward", gui.icons.papirus.actions.media_seek_forward_symbolic, oo2)) {
        stream_seek_time = current_time + 5.0;
        buffer.discard(buffer.readableLength());
        buffer_last_time = stream_seek_time.?;
        current_time = stream_seek_time.?;
        condition.signal();
    }

    if (playing) {
        const timerId = gui.parentGet().extendID(@src(), 0);
        const millis = @divFloor(gui.frameTimeNS(), 1_000_000);
        const left = @intCast(i32, @rem(millis, 1000));

        if (gui.timerDone(timerId) or !gui.timerExists(timerId)) {
            const wait = 1000 * (1000 - left);
            try gui.timer(timerId, wait);
        }
    }
    mutex.unlock();
}

var mutex = std.Thread.Mutex{};
var condition = std.Thread.Condition{};
var playing = false;
var stream_new = true;
var stream_seek_time: ?f64 = null;
var buffer = std.fifo.LinearFifo(u8, .{ .Static = std.math.pow(usize, 2, 20) }).init();
var buffer_eof = false;
var stream_timebase: f64 = 1.0;
var buffer_last_time: f64 = 0;
var current_time: f64 = 0;

// must hold mutex when calling this
fn play() void {
    //std.debug.print("play\n", .{});
    if (playing) {
        std.debug.print("already playing\n", .{});
        return;
    }

    Backend.c.SDL_PauseAudioDevice(g_audio_device, 0);
    playing = true;
    condition.signal();
}

// must hold mutex when calling this
fn pause() void {
    //std.debug.print("pause\n", .{});
    if (!playing) {
        std.debug.print("already paused\n", .{});
        return;
    }

    Backend.c.SDL_PauseAudioDevice(g_audio_device, 1);
    playing = false;
}

export fn audio_callback(user_data: ?*anyopaque, stream: [*c]u8, length: c_int) void {
    _ = user_data;
    var len = @intCast(usize, length);
    var i: usize = 0;

    mutex.lock();
    defer mutex.unlock();

    while (i < len and buffer.readableLength() > 0) {
        const size = std.math.min(len - i, buffer.readableLength());
        for (buffer.readableSlice(0)[0..size]) |s| {
            stream[i] = s;
            i += 1;
        }
        buffer.discard(size);
        current_time = buffer_last_time - (@intToFloat(f64, buffer.readableLength()) / @intToFloat(f64, g_audio_spec.freq * 2 * 2));

        if (!buffer_eof and buffer.readableLength() < buffer.writableLength()) {
            // buffer is less than half full
            condition.signal();
        }
    }

    if (i < len) {
        while (i < len) {
            stream[i] = g_audio_spec.silence;
            i += 1;
        }

        if (buffer_eof) {
            // played all the way to the end
            //std.debug.print("ac: eof\n", .{});
            buffer_eof = false;
            stream_new = true;
            pause();

            // refresh gui
            var ue = std.mem.zeroes(Backend.c.SDL_Event);
            ue.type = Backend.c.SDL_USEREVENT;
            _ = Backend.c.SDL_PushEvent(&ue);
        }
    }
}

fn playback_thread() !void {
    var buf: [256]u8 = undefined;

    stream: while (true) {
        // wait to play
        mutex.lock();
        while (!playing) {
            condition.wait(&mutex);
        }
        mutex.unlock();
        stream_new = false;
        //std.debug.print("playback starting\n", .{});

        //const filename = "test.mp3";
        const filename = "episode-2.mp3";

        var avfc: ?*c.AVFormatContext = null;
        var err = c.avformat_open_input(&avfc, filename, null, null);
        if (err != 0) {
            _ = c.av_strerror(err, &buf, 256);
            std.debug.print("avformat_open_input err {d} : {s}\n", .{ err, std.mem.sliceTo(&buf, 0) });
            return;
        }

        defer c.avformat_close_input(&avfc);

        // unsure if this is needed
        //c.av_format_inject_global_side_data(avfc);

        err = c.avformat_find_stream_info(avfc, null);
        if (err != 0) {
            _ = c.av_strerror(err, &buf, 256);
            std.debug.print("avformat_find_stream_info err {d} : {s}\n", .{ err, std.mem.sliceTo(&buf, 0) });
            return;
        }

        c.av_dump_format(avfc, 0, filename, 0);

        var audio_stream_idx = c.av_find_best_stream(avfc, c.AVMEDIA_TYPE_AUDIO, -1, -1, null, 0);
        if (audio_stream_idx < 0) {
            _ = c.av_strerror(audio_stream_idx, &buf, 256);
            std.debug.print("av_find_best_stream err {d} : {s}\n", .{ audio_stream_idx, std.mem.sliceTo(&buf, 0) });
            return;
        }

        const avstream = avfc.?.streams[@intCast(usize, audio_stream_idx)];
        var avctx: *c.AVCodecContext = c.avcodec_alloc_context3(null);
        defer c.avcodec_free_context(@ptrCast([*c][*c]c.AVCodecContext, &avctx));

        err = c.avcodec_parameters_to_context(avctx, avstream.*.codecpar);
        if (err != 0) {
            _ = c.av_strerror(err, &buf, 256);
            std.debug.print("avcodec_parameters_to_context err {d} : {s}\n", .{ err, std.mem.sliceTo(&buf, 0) });
            return;
        }

        mutex.lock();
        stream_timebase = @intToFloat(f64, avstream.*.time_base.num) / @intToFloat(f64, avstream.*.time_base.den);
        std.debug.print("timebase {d}\n", .{stream_timebase});
        mutex.unlock();

        const codec = c.avcodec_find_decoder(avctx.codec_id);
        if (codec == 0) {
            std.debug.print("no decoder found for codec {s}\n", .{c.avcodec_get_name(avctx.codec_id)});
            return;
        }

        err = c.avcodec_open2(avctx, codec, null);
        if (err != 0) {
            _ = c.av_strerror(err, &buf, 256);
            std.debug.print("avcodec_open2 err {d} : {s}\n", .{ err, std.mem.sliceTo(&buf, 0) });
            return;
        }

        avstream.*.discard = c.AVDISCARD_DEFAULT;
        var target_ch_layout: c.AVChannelLayout = undefined;
        c.av_channel_layout_default(&target_ch_layout, 2);

        var frame: *c.AVFrame = c.av_frame_alloc();
        defer c.av_frame_free(@ptrCast([*c][*c]c.AVFrame, &frame));
        var pkt: *c.AVPacket = c.av_packet_alloc();
        var swrctx: ?*c.SwrContext = null;

        seek: while (true) {
            defer {
                c.avcodec_flush_buffers(avctx);
                if (swrctx != null) {
                    c.swr_free(&swrctx);
                    swrctx = null;
                }
            }

            mutex.lock();
            while (!playing) {
                condition.wait(&mutex);
            }
            mutex.unlock();
            //std.debug.print("seek starting\n", .{});

            if (stream_seek_time) |st| {
                stream_seek_time = null;
                std.debug.print("seeking to {d}\n", .{st});
                err = c.avformat_seek_file(avfc, audio_stream_idx, 0, @floatToInt(i64, st / stream_timebase), std.math.maxInt(i64), 0);
                if (err != 0) {
                    _ = c.av_strerror(err, &buf, 256);
                    std.debug.print("av_format_seek_file err {d} : {s}\n", .{ err, std.mem.sliceTo(&buf, 0) });
                    return;
                }
            }

            var draining = false;
            while (true) {
                // checkout av_read_pause and av_read_play if doing a network stream

                if (!draining) {
                    err = c.av_read_frame(avfc, pkt);
                    if (err == c.AVERROR_EOF) {
                        //std.debug.print("read_frame eof\n", .{});
                        draining = true;
                    } else if (err != 0) {
                        _ = c.av_strerror(err, &buf, 256);
                        std.debug.print("read_frame err {d} : {s}\n", .{ err, std.mem.sliceTo(&buf, 0) });
                        return;
                    }

                    err = c.avcodec_send_packet(avctx, if (draining) null else pkt);
                    // could return eagain if codec is full, have to call receive_frame to proceed
                    if (err == c.AVERROR(c.EAGAIN)) {
                        std.debug.print("avcodec_send_packet eagain\n", .{});
                    } else if (err != 0) {
                        _ = c.av_strerror(err, &buf, 256);
                        std.debug.print("send_packet err {d} : {s}\n", .{ err, std.mem.sliceTo(&buf, 0) });
                        // could be a spurious bug like extra invalid data
                        // TODO: count number of sequential errors and bail if too many
                        continue;
                    }

                    if (!draining) {
                        c.av_packet_unref(pkt);
                    }
                }

                var eof = false;
                var ret = c.avcodec_receive_frame(avctx, frame);
                // could return eagain if codec is empty, have to call send_packet to proceed
                if (ret == c.AVERROR_EOF) {
                    //std.debug.print("receive_frame eof\n", .{});
                    eof = true;
                } else if (ret == c.AVERROR(c.EAGAIN)) {
                    //std.debug.print("receive_frame eagain\n", .{});
                    continue;
                } else if (ret < 0) {
                    _ = c.av_strerror(ret, &buf, 256);
                    std.debug.print("receive_frame err {d} : {s}\n", .{ ret, std.mem.sliceTo(&buf, 0) });
                    return;
                }

                // only used if we are in eof and flushing the last samples out of swr_convert
                var out_samples: c_int = 256;

                if (!eof and swrctx == null) {
                    err = c.swr_alloc_set_opts2(&swrctx, &target_ch_layout, c.AV_SAMPLE_FMT_S16, g_audio_spec.freq, &frame.*.ch_layout, frame.*.format, frame.*.sample_rate, 0, null);
                    if (err != 0) {
                        _ = c.av_strerror(err, &buf, 256);
                        std.debug.print("swr_alloc_set_opts2 err {d} : {s}\n", .{ err, std.mem.sliceTo(&buf, 0) });
                        return;
                    }

                    err = c.swr_init(swrctx);
                    if (err != 0) {
                        _ = c.av_strerror(err, &buf, 256);
                        std.debug.print("swr_init err {d} : {s}\n", .{ err, std.mem.sliceTo(&buf, 0) });
                        return;
                    }
                }

                if (!eof) {
                    out_samples = @divTrunc(frame.*.nb_samples * g_audio_spec.freq, frame.*.sample_rate) + 256;
                }

                const data_size = @intCast(usize, out_samples * 2 * 2); // 2 bytes per sample per channel

                if (swrctx != null) {
                    mutex.lock();
                    defer mutex.unlock();

                    while (buffer.writableLength() < data_size) {
                        condition.wait(&mutex);
                    }

                    if (stream_new) {
                        continue :stream;
                    }

                    if (stream_seek_time != null) {
                        continue :seek;
                    }

                    var slice = buffer.writableWithSize(data_size) catch unreachable;
                    err = c.swr_convert(
                        swrctx,
                        @ptrCast([*c][*c]u8, &slice.ptr),
                        out_samples,
                        if (eof) null else &frame.*.data[0],
                        if (eof) 0 else frame.*.nb_samples,
                    );
                    if (err < 0) {
                        _ = c.av_strerror(err, &buf, 256);
                        std.debug.print("swr_convert err {d} : {s}\n", .{ err, std.mem.sliceTo(&buf, 0) });
                        return;
                    }

                    const data_written = @intCast(usize, err * 2 * 2); // 2 bytes per sample per channel
                    buffer.update(data_written);
                    const seconds_written = @intToFloat(f64, err) / @intToFloat(f64, g_audio_spec.freq);

                    if (!eof) {
                        buffer_last_time = @intToFloat(f64, frame.*.best_effort_timestamp) * stream_timebase + seconds_written;
                    } else {
                        buffer_last_time += seconds_written;
                    }

                    //std.debug.print("ts: {d}\n", .{buffer_last_time});

                    //std.debug.print(".", .{});
                    //std.debug.print("|{d}", .{err});
                    if (eof) {
                        // signal audio_callback to pause when it runs out of samples
                        //std.debug.print("buffer_eof\n", .{});
                        buffer_eof = true;

                        while (true) {
                            condition.wait(&mutex);

                            if (stream_new) {
                                continue :stream;
                            }

                            if (stream_seek_time != null) {
                                continue :seek;
                            }
                        }
                    }
                }
            }
        }
    }
}
