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

extern fn tree_sitter_c() callconv(.c) *dvui.c.TSLanguage;

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

    //var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font = .theme(.title) });
    //const lorem = "This is a dvui.App example that can compile on multiple backends.";
    //tl.addText(lorem, .{});
    //tl.addText("\n", .{});
    //tl.format("Current backend: {s}", .{@tagName(dvui.backend.kind)}, .{});
    //if (dvui.backend.kind == .web) {
    //    tl.format(" : {s}", .{if (dvui.backend.wasm.wasm_about_webgl2() == 1) "webgl2" else "webgl (no mipmaps)"}, .{});
    //}
    //tl.deinit();

    //var tl2 = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
    //tl2.addText(
    //    \\DVUI
    //    \\- paints the entire window
    //    \\- can show floating windows and dialogs
    //    \\- rest of the window is a scroll area
    //, .{});
    //tl2.addText("\n\n", .{});
    //tl2.addText("Framerate is variable and adjusts as needed for input events and animations.", .{});
    //tl2.addText("\n\n", .{});
    //tl2.addText("Framerate is capped by vsync.", .{});
    //tl2.addText("\n\n", .{});
    //tl2.addText("Cursor is always being set by dvui.", .{});
    //tl2.addText("\n\n", .{});
    //if (dvui.useFreeType) {
    //    tl2.addText("Fonts are being rendered by FreeType 2.", .{});
    //} else {
    //    tl2.addText("Fonts are being rendered by stb_truetype.", .{});
    //}
    //tl2.deinit();

    {
        const source =
            \\int main() {
            \\// Create a parser.
            \\TSParser *parser = ts_parser_new();
            \\
            \\// Set the parser's language (JSON in this case).
            \\ts_parser_set_language(parser, tree_sitter_json());
            \\
            \\// Build a syntax tree based on source code stored in a string.
            \\const char *source_code = "[1, null]";
        ;

        const queries =
            \\(identifier) @variable
            \\
            \\((identifier) @constant
            \\ (#match? @constant "^[A-Z][A-Z\\d_]*$"))
            \\
            \\"break" @keyword
            \\"case" @keyword
            \\"const" @keyword
            \\"continue" @keyword
            \\"default" @keyword
            \\"do" @keyword
            \\"else" @keyword
            \\"enum" @keyword
            \\"extern" @keyword
            \\"for" @keyword
            \\"if" @keyword
            \\"inline" @keyword
            \\"return" @keyword
            \\"sizeof" @keyword
            \\"static" @keyword
            \\"struct" @keyword
            \\"switch" @keyword
            \\"typedef" @keyword
            \\"union" @keyword
            \\"volatile" @keyword
            \\"while" @keyword
            \\
            \\"#define" @keyword
            \\"#elif" @keyword
            \\"#else" @keyword
            \\"#endif" @keyword
            \\"#if" @keyword
            \\"#ifdef" @keyword
            \\"#ifndef" @keyword
            \\"#include" @keyword
            \\(preproc_directive) @keyword
            \\
            \\"--" @operator
            \\"-" @operator
            \\"-=" @operator
            \\"->" @operator
            \\"=" @operator
            \\"!=" @operator
            \\"*" @operator
            \\"&" @operator
            \\"&&" @operator
            \\"+" @operator
            \\"++" @operator
            \\"+=" @operator
            \\"<" @operator
            \\"==" @operator
            \\">" @operator
            \\"||" @operator
            \\
            \\"." @delimiter
            \\";" @delimiter
            \\
            \\(string_literal) @string
            \\(system_lib_string) @string
            \\
            \\(null) @constant
            \\(number_literal) @number
            \\(char_literal) @number
            \\
            \\(field_identifier) @property
            \\(statement_identifier) @label
            \\(type_identifier) @type
            \\(primitive_type) @type
            \\(sized_type_specifier) @type
            \\
            \\(call_expression
            \\  function: (identifier) @function)
            \\(call_expression
            \\  function: (field_expression
            \\    field: (field_identifier) @function))
            \\(function_declarator
            \\  declarator: (identifier) @function)
            \\(preproc_function_def
            \\  name: (identifier) @function.special)
            \\
            \\(comment) @comment
        ;

        var te: dvui.TextEntryWidget = undefined;
        te.init(@src(), .{ .multiline = true }, .{ .expand = .horizontal, .min_size_content = .height(200) });
        defer te.deinit();

        if (dvui.firstFrame(te.data().id)) {
            te.textSet(source, false);
        }

        te.processEvents();
        te.drawBeforeText();

        const text = te.textGet();

        // used to output text that's not highlighted
        var start: usize = 0;

        // parsing
        const parser = dvui.c.ts_parser_new();
        defer dvui.c.ts_parser_delete(parser);
        _ = dvui.c.ts_parser_set_language(parser, tree_sitter_c());
        // TODO: set byte range for parsing
        const tree = dvui.c.ts_parser_parse_string(parser, null, text.ptr, @intCast(text.len));
        const root = dvui.c.ts_tree_root_node(tree);
        //const str = dvui.c.ts_node_string(root);
        defer dvui.c.ts_tree_delete(tree);

        // queries
        var errorOffset: u32 = undefined;
        var errorType: dvui.c.TSQueryError = undefined;
        const query = dvui.c.ts_query_new(tree_sitter_c(), queries.ptr, queries.len, &errorOffset, &errorType);
        defer if (query) |q| dvui.c.ts_query_delete(q);
        const qc = dvui.c.ts_query_cursor_new();
        defer dvui.c.ts_query_cursor_delete(qc);
        // TODO: set byte range for qc
        if (query) |q| dvui.c.ts_query_cursor_exec(qc, q, root);
        var prev_match: ?struct {
            node: dvui.c.TSNode,
            capture_name: []const u8,
        } = null;
        var match: dvui.c.TSQueryMatch = undefined;
        var captureIdx: u32 = undefined;
        while (dvui.c.ts_query_cursor_next_capture(qc, &match, &captureIdx)) {
            const capture = match.captures[captureIdx];
            if (prev_match) |pm| {
                if (!dvui.c.ts_node_eq(pm.node, capture.node)) {
                    // new capture is not the same as previous, so render previous
                    const nstart = dvui.c.ts_node_start_byte(pm.node);
                    const nend = dvui.c.ts_node_end_byte(pm.node);
                    if (start < nstart) {
                        // render non highlighted text up to this node
                        te.textLayout.format("{s}", .{text[start..nstart]}, .{});
                    }

                    var opts: dvui.Options = .{};
                    if (std.mem.eql(u8, pm.capture_name, "function")) {
                        opts = .{ .color_text = .red };
                    }

                    //std.debug.print("  \"{s}\"\n", .{source[nstart..nend]});
                    te.textLayout.format("{s}", .{text[nstart..nend]}, opts);

                    start = nend;
                }
            }

            //std.debug.print("next_capture: {d} {d} {d}\n", .{ match.capture_count, captureIdx, match.pattern_index });
            var capture_name_len: u32 = undefined;
            const capture_name = dvui.c.ts_query_capture_name_for_id(query, capture.index, &capture_name_len);
            const cname = capture_name[0..capture_name_len];
            //const nstart = dvui.c.ts_node_start_byte(capture.node);
            //const nend = dvui.c.ts_node_end_byte(capture.node);
            //std.debug.print("  node {s} name {s} \"{s}\"\n", .{ dvui.c.ts_node_string(capture.node), cname, text[nstart..nend] });
            prev_match = .{ .node = capture.node, .capture_name = cname };
        }

        if (prev_match) |pm| {
            //std.debug.print("rendering last match\n", .{});
            // new capture is not the same as previous, so render previous
            const nstart = dvui.c.ts_node_start_byte(pm.node);
            const nend = dvui.c.ts_node_end_byte(pm.node);
            if (start < nstart) {
                // render non highlighted text up to this node
                te.textLayout.format("{s}", .{text[start..nstart]}, .{});
            }

            var opts: dvui.Options = .{};
            if (std.mem.eql(u8, pm.capture_name, "function")) {
                opts = .{ .color_text = .red };
            }

            //std.debug.print("  \"{s}\"\n", .{source[nstart..nend]});
            te.textLayout.format("{s}", .{text[nstart..nend]}, opts);

            start = nend;
        }

        if (start < text.len) {
            te.textLayout.format("{s}", .{text[start..text.len]}, .{});
        }
        te.textLayout.addTextDone(.{});
        te.drawAfterText();
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
