const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");

const window_icon_png = @embedFile("zig-favicon.png");

// To be a dvui App:
// * declare "dvui_app"
// * expose the backend's main function
// * use the backend's log function
pub const dvui_app: dvui.App = .{
    .config = .{
        .options = .{
            .size = .{ .w = 800.0, .h = 600.0 },
            .min_size = .{ .w = 250.0, .h = 350.0 },
            .title = "DVUI App Example",
            .icon = window_icon_png,
            .window_init_options = .{
                // Could set a default theme here
                // .theme = dvui.Theme.builtin.dracula,
            },
        },
    },
    .frameFn = AppFrame,
    .initFn = AppInit,
    .deinitFn = AppDeinit,
};
pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{
    .logFn = dvui.App.logFn,
};

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

var orig_content_scale: f32 = 1.0;
var warn_on_quit: bool = false;
var warn_on_quit_closing: bool = false;

// Runs before the first frame, after backend and dvui.Window.init()
// - runs between win.begin()/win.end()
pub fn AppInit(win: *dvui.Window) !void {
    orig_content_scale = win.content_scale;

    // Add your own bundled font files...:
    // try dvui.addFont("NOTO", @embedFile("../src/fonts/NotoSansKR-Regular.ttf"), null);

    if (false) {
        // If you need to set a theme based on the users preferred color scheme, do it here
        const theme = switch (win.backend.preferredColorScheme() orelse .light) {
            .light => dvui.Theme.builtin.adwaita_light,
            .dark => dvui.Theme.builtin.adwaita_dark,
        };

        win.themeSet(theme);
    }
}

// Run as app is shutting down before dvui.Window.deinit()
pub fn AppDeinit() void {}

// Run each frame to do normal UI
pub fn AppFrame() !dvui.App.Result {
    return frame();
}

extern fn tree_sitter_zig() callconv(.c) *dvui.c.TSLanguage;

const tsQueryCursorCaptureIterator = struct {
    pub const Match = struct {
        node: dvui.c.TSNode,
        capture_index: u32,

        pub fn captureName(self: *const Match, query: *const dvui.c.TSQuery) []const u8 {
            var len: u32 = undefined;
            const name = dvui.c.ts_query_capture_name_for_id(query, self.capture_index, &len);
            return name[0..len];
        }
    };

    query_cursor: *dvui.c.TSQueryCursor,
    prev_match: ?Match,

    pub fn init(qc: *dvui.c.TSQueryCursor) tsQueryCursorCaptureIterator {
        return .{
            .query_cursor = qc,
            .prev_match = null,
        };
    }

    pub fn next(self: *tsQueryCursorCaptureIterator) ?Match {
        var match: dvui.c.TSQueryMatch = undefined;
        var captureIdx: u32 = undefined;
        loop: while (dvui.c.ts_query_cursor_next_capture(self.query_cursor, &match, &captureIdx)) {
            const capture = match.captures[captureIdx];
            if (self.prev_match) |pm| {
                if (dvui.c.ts_node_eq(pm.node, capture.node)) {
                    // same node as previous
                    self.prev_match = .{ .node = capture.node, .capture_index = capture.index };
                    continue :loop;
                }

                // not the same
                const ret = self.prev_match;
                self.prev_match = .{ .node = capture.node, .capture_index = capture.index };
                return ret;
            } else {
                // first time
                self.prev_match = .{ .node = capture.node, .capture_index = capture.index };
                continue :loop;
            }
        }

        const ret = self.prev_match;
        self.prev_match = null;
        return ret;
    }
};

var show_text_entry: bool = false;

pub fn frame() !dvui.App.Result {
    var scaler = dvui.scale(@src(), .{ .scale = &dvui.currentWindow().content_scale, .pinch_zoom = .global }, .{ .rect = .cast(dvui.windowRect()) });
    scaler.deinit();

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .style = .window, .background = true, .expand = .horizontal });
        defer hbox.deinit();

        var m = dvui.menu(@src(), .horizontal, .{});
        defer m.deinit();

        if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{ .tag = "first-focusable" })) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();

            if (dvui.menuItemLabel(@src(), "Close Menu", .{}, .{ .expand = .horizontal }) != null) {
                m.close();
            }

            if (dvui.backend.kind != .web) {
                if (dvui.menuItemLabel(@src(), "Exit", .{}, .{ .expand = .horizontal }) != null) {
                    return .close;
                }
            }
        }
    }

    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .style = .window });
    defer scroll.deinit();

    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font = .theme(.title) });
    const lorem = "This is a dvui.App example that can compile on multiple backends.";
    tl.addText(lorem, .{});
    tl.addText("\n", .{});
    tl.format("Current backend: {s}", .{@tagName(dvui.backend.kind)}, .{});
    if (dvui.backend.kind == .web) {
        tl.format(" : {s}", .{if (dvui.backend.wasm.wasm_about_webgl2() == 1) "webgl2" else "webgl (no mipmaps)"}, .{});
    }
    tl.deinit();

    var tl2 = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
    tl2.addText(
        \\DVUI
        \\- paints the entire window
        \\- can show floating windows and dialogs
        \\- rest of the window is a scroll area
    , .{});
    tl2.addText("\n\n", .{});
    tl2.addText("Framerate is variable and adjusts as needed for input events and animations.", .{});
    tl2.addText("\n\n", .{});
    tl2.addText("Framerate is capped by vsync.", .{});
    tl2.addText("\n\n", .{});
    tl2.addText("Cursor is always being set by dvui.", .{});
    tl2.addText("\n\n", .{});
    if (dvui.useFreeType) {
        tl2.addText("Fonts are being rendered by FreeType 2.", .{});
    } else {
        tl2.addText("Fonts are being rendered by stb_truetype.", .{});
    }
    tl2.deinit();

    if (dvui.useTreeSitter) {
        if (dvui.button(@src(), "Show Highlighted Code", .{}, .{})) {
            show_text_entry = !show_text_entry;
        }

        if (show_text_entry) {
            const source = @embedFile("app.zig");
            const queries = @embedFile("tree_sitter_zig_queries.scm");

            var te: dvui.TextEntryWidget = undefined;
            te.init(@src(), .{ .multiline = true, .cache_layout = true, .text = .{ .internal = .{ .limit = 1_000_000 } } }, .{ .expand = .horizontal, .min_size_content = .height(300) });
            defer te.deinit();

            if (dvui.firstFrame(te.data().id)) {
                te.textSet(source, false);
            }

            te.processEvents();
            te.drawBeforeText();

            const text = te.textGet();

            // used to output text that's not highlighted
            var start: usize = 0;

            const Parser = struct {
                parser: *dvui.c.TSParser,
                tree: *dvui.c.TSTree,
                query: *dvui.c.TSQuery,

                pub fn deinit(ptr: *anyopaque) void {
                    const self: *@This() = @ptrCast(@alignCast(ptr));

                    dvui.c.ts_query_delete(self.query);
                    dvui.c.ts_tree_delete(self.tree);
                    dvui.c.ts_parser_delete(self.parser);
                }
            };

            var parser = dvui.dataGetPtr(null, te.data().id, "parser", Parser) orelse blk: {
                const p = dvui.c.ts_parser_new();
                _ = dvui.c.ts_parser_set_language(p, tree_sitter_zig());
                const tree = dvui.c.ts_parser_parse_string(p, null, text.ptr, @intCast(text.len));

                var errorOffset: u32 = undefined;
                var errorType: dvui.c.TSQueryError = undefined;
                const query = dvui.c.ts_query_new(tree_sitter_zig(), queries.ptr, queries.len, &errorOffset, &errorType);

                const parser: Parser = .{ .parser = p.?, .tree = tree.?, .query = query.? };
                dvui.dataSet(null, te.data().id, "parser", parser);
                dvui.dataSetDeinitFunction(null, te.data().id, "parser", &Parser.deinit);
                break :blk dvui.dataGetPtr(null, te.data().id, "parser", Parser).?;
            };

            if (te.text_changed and !dvui.firstFrame(te.data().id)) {
                var edit: dvui.c.TSInputEdit = undefined;
                edit.start_byte = @intCast(te.text_changed_start);
                edit.old_end_byte = @intCast(te.text_changed_end);
                edit.new_end_byte = @intCast(@as(i64, @intCast(te.text_changed_end)) + te.text_changed_added);

                edit.start_point = .{ .row = 0, .column = 0 };
                edit.old_end_point = .{ .row = 0, .column = 0 };
                edit.new_end_point = .{ .row = 0, .column = 0 };

                dvui.c.ts_tree_edit(parser.tree, &edit);

                const tree = dvui.c.ts_parser_parse_string(parser.parser, parser.tree, text.ptr, @intCast(text.len));
                dvui.c.ts_tree_delete(parser.tree);
                parser.tree = tree.?;
            }

            // parsing
            const root = dvui.c.ts_tree_root_node(parser.tree);

            // queries
            const qc = dvui.c.ts_query_cursor_new();
            defer dvui.c.ts_query_cursor_delete(qc);

            if (te.textLayout.cache_layout_bytes) |clb| {
                _ = dvui.c.ts_query_cursor_set_byte_range(qc, @intCast(clb.start), @intCast(clb.end));
            }

            dvui.c.ts_query_cursor_exec(qc, parser.query, root);

            var iter: tsQueryCursorCaptureIterator = .init(qc.?);
            while (iter.next()) |match| {
                const nstart = dvui.c.ts_node_start_byte(match.node);
                const nend = dvui.c.ts_node_end_byte(match.node);
                if (start < nstart) {
                    // render non highlighted text up to this node
                    te.textLayout.format("{s}", .{text[start..nstart]}, .{});
                } else if (nstart < start) {
                    // this match is inside (or overlapping) the previous match
                    // maybe we could be smarter here, but for now drop it
                    continue;
                }

                var opts: dvui.Options = .{};
                if (std.mem.startsWith(u8, match.captureName(parser.query), "variable")) {
                    opts.color_text = .aqua;
                } else if (std.mem.startsWith(u8, match.captureName(parser.query), "type")) {
                    opts.color_text = .blue;
                } else if (std.mem.startsWith(u8, match.captureName(parser.query), "keyword")) {
                    opts.color_text = .purple;
                } else if (std.mem.eql(u8, match.captureName(parser.query), "operator")) {
                    opts.color_text = .silver;
                } else if (std.mem.eql(u8, match.captureName(parser.query), "string")) {
                    opts.color_text = .maroon;
                } else if (std.mem.eql(u8, match.captureName(parser.query), "escape_sequence")) {
                    opts.color_text = .teal;
                } else if (std.mem.eql(u8, match.captureName(parser.query), "comment")) {
                    opts.color_text = .green;
                } else if (std.mem.startsWith(u8, match.captureName(parser.query), "function")) {
                    opts.color_text = dvui.Color.yellow.lighten(-30);
                }

                te.textLayout.format("{s}", .{text[nstart..nend]}, opts);

                start = nend;
            }

            if (start < text.len) {
                // any leftover non highlighted text
                te.textLayout.format("{s}", .{text[start..text.len]}, .{});
            }
            te.textLayout.addTextDone(.{});
            te.drawAfterText();
        }
    }

    const label = if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window";
    if (dvui.button(@src(), label, .{}, .{ .tag = "show-demo-btn" })) {
        dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
    }

    if (dvui.button(@src(), "Debug Window", .{}, .{})) {
        dvui.toggleDebugWindow();
    }

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();
        dvui.label(@src(), "Pinch Zoom or Scale", .{}, .{});
        if (dvui.buttonIcon(@src(), "plus", dvui.entypo.plus, .{}, .{}, .{})) {
            dvui.currentWindow().content_scale *= 1.1;
        }

        if (dvui.buttonIcon(@src(), "minus", dvui.entypo.minus, .{}, .{}, .{})) {
            dvui.currentWindow().content_scale /= 1.1;
        }

        if (dvui.currentWindow().content_scale != orig_content_scale) {
            if (dvui.button(@src(), "Reset Scale", .{}, .{})) {
                dvui.currentWindow().content_scale = orig_content_scale;
            }
        }
    }

    if (dvui.backend.kind != .web) {
        _ = dvui.checkbox(@src(), &warn_on_quit, "Warn on Quit", .{});

        if (warn_on_quit) {
            if (warn_on_quit_closing) return .close;

            const wd = dvui.currentWindow().data();
            for (dvui.events()) |*e| {
                if (!dvui.eventMatchSimple(e, wd)) continue;

                if ((e.evt == .window and e.evt.window.action == .close) or (e.evt == .app and e.evt.app.action == .quit)) {
                    e.handle(@src(), wd);

                    const warnAfter: dvui.DialogCallAfterFn = struct {
                        fn warnAfter(_: dvui.Id, response: dvui.enums.DialogResponse) !void {
                            if (response == .ok) warn_on_quit_closing = true;
                        }
                    }.warnAfter;

                    dvui.dialog(@src(), .{}, .{ .message = "Really Quit?", .cancel_label = "Cancel", .callafterFn = warnAfter });
                }
            }
        }
    }

    // look at demo() for examples of dvui widgets, shows in a floating window
    dvui.Examples.demo();

    return .ok;
}

test "tab order" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    try dvui.testing.settle(frame);

    try dvui.testing.expectNotFocused("first-focusable");

    try dvui.testing.pressKey(.tab, .none);
    try dvui.testing.settle(frame);

    try dvui.testing.expectFocused("first-focusable");
}

test "open example window" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    try dvui.testing.settle(frame);

    // FIXME: The global show_demo_window variable makes tests order dependent
    dvui.Examples.show_demo_window = false;

    try std.testing.expect(dvui.tagGet(dvui.Examples.demo_window_tag) == null);

    try dvui.testing.moveTo("show-demo-btn");
    try dvui.testing.click(.left);
    try dvui.testing.settle(frame);

    try dvui.testing.expectVisible(dvui.Examples.demo_window_tag);
}

// disabling snapshot tests until we figure out a better (less sensitive) way of doing them
//test "snapshot" {
//    // snapshot tests are unstable
//    var t = try dvui.testing.init(.{});
//    defer t.deinit();
//
//    // FIXME: The global show_demo_window variable makes tests order dependent
//    dvui.Examples.show_demo_window = false;
//
//    try dvui.testing.settle(frame);
//
//    // Try swapping the names of ./snapshots/app.zig-test.snapshot-X.png
//    try t.snapshot(@src(), frame);
//
//    try dvui.testing.pressKey(.tab, .none);
//    try dvui.testing.settle(frame);
//
//    try t.snapshot(@src(), frame);
//}
