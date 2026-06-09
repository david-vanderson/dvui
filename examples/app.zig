const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const csv_parse = @import("csv_parse.zig");

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
    .frameFn = appFrame,
    .initFn = appInit,
    .deinitFn = appDeinit,
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
var extra_os_win: bool = false;

// Runs before the first frame, after backend and dvui.Window.init()
// - runs between win.begin()/win.end()
pub fn appInit(win: *dvui.Window) !void {
    orig_content_scale = win.content_scale;

    // Add your own bundled font files...:
    // try dvui.addFont("NOTO", @embedFile("../src/fonts/NotoSansKR-Regular.ttf"), null);

    // If you want a custom theme use something like this:
    // const theme = switch (win.backend.preferredColorScheme() orelse .light) {
    //     .light => dvui.Theme.builtin.adwaita_light,
    //     .dark => dvui.Theme.builtin.adwaita_dark,
    // };
    // win.themeSet(theme);
}

// Run as app is shutting down before dvui.Window.deinit()
pub fn appDeinit() void {}

// Run each frame to do normal UI
pub fn appFrame() !dvui.App.Result {
    {
        // Here's the dvui example content, replace/modify with your stuff

        var scaler = dvui.scale(@src(), .{ .scale = &dvui.currentWindow().content_scale, .pinch_zoom = .global }, .{ .rect = .cast(dvui.windowRect()) });
        scaler.deinit();

        if (menu()) |res| return res;

        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .style = .window });
        defer scroll.deinit();

        if (content()) |res| return res;
    }

    // only shows the demo if dvui.Examples.show_demo_window is true
    // .full -> .lite or comment out to speed up compile times
    dvui.Examples.demo(.lite);

    return .ok;
}

pub fn menu() ?dvui.App.Result {
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

    return null;
}

pub fn content() ?dvui.App.Result {
    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font = .theme(.title) });
    const lorem = "This is a dvui.App example that can compile on multiple backends.\n";
    tl.addText(lorem, .{});
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
        \\
        \\
    , .{});
    tl2.addText("Framerate is variable and adjusts as needed for input events and animations.\n\n", .{});
    tl2.addText("Framerate is capped by vsync.\n\n", .{});
    tl2.addText("Cursor is always being set by dvui.\n\n", .{});
    if (dvui.useFreeType) {
        tl2.addText("Fonts are being rendered by FreeType 2.", .{});
    } else {
        tl2.addText("Fonts are being rendered by stb_truetype.", .{});
    }

    tl2.deinit();

    const uniqueId = dvui.parentGet().extendId(@src(), 0);
    const csv_table = dvui.dataGetPtrDefault(null, uniqueId, "csv", ?csv_parse.Table, null);
    const col_header = dvui.dataGetPtrDefault(null, uniqueId, "col_header", bool, true);
    const rows_visible = dvui.dataGetPtrDefault(null, uniqueId, "rows_visible", bool, false);
    const cols = dvui.dataGetPtrDefault(null, uniqueId, "cols", f32, 5);
    const rows = dvui.dataGetPtrDefault(null, uniqueId, "rows", f32, 5);

    dvui.dataSetDeinitFunction(null, uniqueId, "csv", (struct {
        pub fn deinit(ptr: *anyopaque) void {
            const self: *?csv_parse.Table = @ptrCast(@alignCast(ptr));
            if (self.*) |ct| {
                dvui.currentWindow().gpa.free(ct.src);
                dvui.currentWindow().gpa.free(ct.cells);
                self.* = null;
            }
        }
    }).deinit);

    if (dvui.button(@src(), "Toggle CSV", .{}, .{})) {
        if (csv_table.*) |ct| {
            dvui.currentWindow().gpa.free(ct.src);
            dvui.currentWindow().gpa.free(ct.cells);
            csv_table.* = null;
        } else {
            const filename = dvui.dialogNativeFileOpen(dvui.currentWindow().arena(), .{
                .title = "Load CSV",
                .filters = &.{"*.csv"},
                .filter_description = "images",
            }) catch @panic("blah");
            if (filename) |f| {
                const csv_content = std.Io.Dir.cwd().readFileAlloc(dvui.io, f, dvui.currentWindow().gpa, .unlimited) catch @panic("blah1");
                errdefer dvui.currentWindow().gpa.free(csv_content);
                errdefer csv_table.* = null;

                csv_table.* = csv_parse.parse(dvui.currentWindow().gpa, csv_content) catch @panic("blah2");
                cols.* = @floatFromInt(csv_table.*.?.num_cols);
                rows.* = @floatFromInt(csv_table.*.?.num_rows);
            }
        }
    }

    _ = dvui.checkbox(@src(), col_header, "Column Header", .{});
    _ = dvui.checkbox(@src(), rows_visible, "Only Visible Rows", .{});
    var auto_size = false;
    if (dvui.button(@src(), "Auto Size", .{}, .{})) {
        auto_size = true;
    }

    if (csv_table.*) |ct| {
        cols.* = @floatFromInt(ct.num_cols);
        rows.* = @floatFromInt(ct.num_rows);
    } else {
        _ = dvui.sliderEntry(@src(), "cols: {d}", .{ .value = cols, .min = 0, .max = 100, .interval = 1 }, .{});
        _ = dvui.sliderEntry(@src(), "rows: {d}", .{ .value = rows, .min = 0, .max = 1_000_000, .interval = 1 }, .{});
    }

    {
        var table: dvui.TableWidget = undefined;
        table.init(@src(), .{ .scroll_opts = .{ .horizontal = .auto }, .rows = if (rows_visible.*) @trunc(rows.*) else null }, .{ .border = .all(1), .style = .content, .background = true, .max_size_content = .height(300) });
        defer table.deinit();

        if (auto_size) table.autoSize();

        if (col_header.*) {
            for (0..@trunc(cols.*)) |col| {
                const cell = table.colHeader(col, .{ .border = .all(1) });
                defer cell.deinit();

                dvui.label(@src(), "Col {d}", .{col}, .{ .expand = .both });
            }
        }

        var start_row: usize = 0;
        var end_row: usize = @trunc(rows.*);
        if (rows_visible.*) {
            start_row, end_row = table.rowsVisible();
        }
        for (start_row..end_row) |row| {
            for (0..@trunc(cols.*)) |col| {
                var cell = table.cell(col, row, .{ .border = .all(1) });
                defer cell.deinit();

                const txt = dvui.dataGetSlice(null, cell.data().id, "data", []u8) orelse std.fmt.allocPrint(dvui.currentWindow().arena(), "Cell {d} {d}", .{ col, row }) catch "Error";
                if (cell.editable(if (csv_table.*) |ct| ct.cell(row, col) else txt, .{})) |new_text| {
                    dvui.dataSetSlice(null, cell.data().id, "data", new_text);
                    if (csv_table.*) |ct| {
                        const cells = @constCast(ct.cells);
                        cells[row * ct.num_cols + col] = dvui.dataGetSlice(null, cell.data().id, "data", []u8).?;
                    }
                }
            }
        }
    }

    const label = if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window";
    if (dvui.button(@src(), label, .{}, .{ .tag = "show-demo-btn" })) {
        dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
    }

    if (dvui.button(@src(), "Debug Window", .{}, .{})) {
        dvui.toggleDebugWindow();
    }

    const os_win_label = if (extra_os_win) "Close the Os Window" else "Extra OS Window (experimental)";
    if (dvui.button(@src(), os_win_label, .{}, .{})) {
        extra_os_win = !extra_os_win;
    }
    if (extra_os_win) {
        const os_win = dvui.osWindow(
            @src(),
            .{ .title = "Child os window (or so I hope)", .size = .{ .w = 500, .h = 300 } },
            .{ .open_flag = &extra_os_win },
        );
        defer os_win.deinit();
        const b = dvui.box(@src(), .{}, .{ .background = true });
        defer b.deinit();
        if (dvui.expander(@src(), "Show me a Spinner !!", .{ .default_expanded = false }, .{})) {
            dvui.spinner(@src(), .{});
        }
        if (dvui.button(@src(), "Close me", .{}, .{})) {
            extra_os_win = false;
        }
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

    return null;
}

test "tab order" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    try dvui.testing.settle(appFrame);

    try dvui.testing.expectNotFocused("first-focusable");

    try dvui.testing.pressKey(.tab, .none);
    try dvui.testing.settle(appFrame);

    try dvui.testing.expectFocused("first-focusable");
}

test "open example window" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    try dvui.testing.settle(appFrame);

    // FIXME: The global show_demo_window variable makes tests order dependent
    dvui.Examples.show_demo_window = false;

    try std.testing.expect(dvui.tagGet(dvui.Examples.demo_window_tag) == null);

    try dvui.testing.moveTo("show-demo-btn");
    try dvui.testing.click(.left);
    try dvui.testing.settle(appFrame);

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
