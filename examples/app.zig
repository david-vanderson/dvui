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
    dvui.Examples.demo(.full);

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

pub const fnv = std.hash.Fnv1a_64;
pub const TableWidget = struct {
    pub var defaults: dvui.Options = .{
        .name = "TableWidget",
        .role = .grid,
        .corner_radius = .{ .x = 0, .y = 0, .w = 5, .h = 5 },
        .style = .content,
        .background = true,
    };

    pub const InitOptions = struct {
        // Scroll options for the grid body
        scroll_opts: dvui.ScrollAreaWidget.InitOpts = .{},
    };

    pub const Cell = struct {
        col: usize,
        row: usize,
    };

    vbox: dvui.BoxWidget,
    cols: usize,
    rows: usize,
    max_seen: Cell = .{ .col = 0, .row = 0 },
    col_width: f32,
    row_height: f32,
    cursor: Cell = .{ .col = 0, .row = 0 },

    msi: *dvui.ScrollInfo, // main scroll info
    scroll: dvui.ScrollAreaWidget, // main scroll area
    cscroll: ?dvui.ScrollAreaWidget = null, // column header scroll area
    rscroll: ?dvui.ScrollAreaWidget = null, // row header scroll area
    bscroll: ?dvui.ScrollContainerWidget = null, // body scroll container
    frame_viewport: dvui.Point = .{}, // Fixed scroll viewport for this frame
    scroll_to_cursor: bool = false,

    pub fn init(self: *TableWidget, src: std.builtin.SourceLocation, init_opts: InitOptions, opts: dvui.Options) void {
        self.* = .{
            .vbox = undefined,
            .cols = undefined,
            .rows = undefined,
            .col_width = undefined,
            .row_height = undefined,
            .scroll = undefined,
            .msi = undefined,
        };

        self.vbox.init(src, .{}, defaults.themeOverride(opts.theme).override(opts));
        self.vbox.drawBackground();

        dvui.tabIndexSet(self.data().id, null, self.data().rectScale().r);

        self.cols = dvui.dataGet(null, self.data().id, "__cols", usize) orelse 0;
        self.rows = dvui.dataGet(null, self.data().id, "__rows", usize) orelse 0;
        self.col_width = dvui.dataGet(null, self.data().id, "__col_width", f32) orelse 10;
        self.row_height = dvui.dataGet(null, self.data().id, "__row_height", f32) orelse 10;
        self.cursor = dvui.dataGet(null, self.data().id, "__cursor", Cell) orelse .{ .col = 0, .row = 0 };
        self.scroll_to_cursor = dvui.dataGet(null, self.data().id, "__scroll_to_cursor", bool) orelse false;

        var scroll_opts = init_opts.scroll_opts;
        scroll_opts.frame_viewport_out = scroll_opts.frame_viewport_out orelse &self.frame_viewport;

        self.scroll.init(
            @src(),
            scroll_opts,
            .{
                .name = "TableWidgetScrollArea",
                .role = .none,
                .expand = .both,
                .background = false,
            },
        );

        self.msi = self.scroll.si;
        self.frame_viewport = scroll_opts.frame_viewport_out.?.*; // noop unless frame_viewport_out was passed into us
    }

    pub fn data(self: *TableWidget) *dvui.WidgetData {
        return self.vbox.data();
    }

    pub const CellResult = struct {
        rect: dvui.Rect,
        id_extra: usize,
        focus: bool,
    };

    pub fn cell(self: *TableWidget, col: usize, row: usize) CellResult {
        self.max_seen = .{
            .col = @max(self.max_seen.col, col),
            .row = @max(self.max_seen.row, row),
        };
        var hash = fnv.init();
        hash.update("col");
        hash.update(std.mem.asBytes(&col));
        hash.update("row");
        hash.update(std.mem.asBytes(&row));

        const rect: dvui.Rect = .{
            .x = @as(f32, @floatFromInt(col)) * self.col_width,
            .y = @as(f32, @floatFromInt(row)) * self.row_height,
            .w = self.col_width,
            .h = self.row_height,
        };

        const focus = self.data().id == dvui.focusedWidgetId() and col == self.cursor.col and row == self.cursor.row;

        if (focus and self.scroll_to_cursor) {
            // FIXME: scroll to rect
            self.scroll_to_cursor = false;
        }

        return .{
            .rect = rect,
            .id_extra = hash.final(),
            .focus = focus,
        };
    }

    pub fn cellMinSize(self: *TableWidget, _: usize, _: usize, min_size: dvui.Size) void {
        self.col_width = @max(self.col_width, min_size.w);
        self.row_height = @max(self.row_height, min_size.h);
    }

    pub fn matchEvent(self: *TableWidget, e: *dvui.Event) bool {
        return dvui.eventMatchSimple(e, self.data());
    }

    pub fn deinit(self: *TableWidget) void {
        defer if (dvui.widgetIsAllocated(self)) dvui.widgetFree(self);
        defer self.* = undefined;

        const evts = dvui.events();
        for (evts) |*e| {
            if (!self.matchEvent(e)) continue;

            switch (e.evt) {
                .key => |*ke| {
                    if (ke.action == .down or ke.action == .repeat) {
                        if (ke.matchBind("char_up")) {
                            e.handle(@src(), self.data());
                            self.cursor.row -|= 1;
                            dvui.refresh(null, @src(), self.data().id);
                            continue;
                        }
                        if (ke.matchBind("char_down")) {
                            e.handle(@src(), self.data());
                            self.cursor.row = @min(self.rows, self.cursor.row + 1);
                            dvui.refresh(null, @src(), self.data().id);
                            continue;
                        }
                        if (ke.matchBind("char_left")) {
                            e.handle(@src(), self.data());
                            self.cursor.col -|= 1;
                            dvui.refresh(null, @src(), self.data().id);
                            continue;
                        }
                        if (ke.matchBind("char_right")) {
                            e.handle(@src(), self.data());
                            self.cursor.col = @min(self.cols, self.cursor.col + 1);
                            dvui.refresh(null, @src(), self.data().id);
                            continue;
                        }
                    }
                },
                else => {},
            }
        }

        var s: dvui.Size = .{ .w = @floatFromInt(self.max_seen.col + 1), .h = @floatFromInt(self.max_seen.row + 1) };
        s.w *= self.col_width;
        s.h *= self.row_height;
        self.scroll.scroll.?.minSizeForChild(s);

        self.scroll.deinit();

        dvui.dataSet(null, self.data().id, "__cols", self.max_seen.col);
        dvui.dataSet(null, self.data().id, "__rows", self.max_seen.row);
        dvui.dataSet(null, self.data().id, "__col_width", self.col_width);
        dvui.dataSet(null, self.data().id, "__row_height", self.row_height);
        dvui.dataSet(null, self.data().id, "__cursor", self.cursor);
        dvui.dataSet(null, self.data().id, "__scroll_to_cursor", self.scroll_to_cursor);

        self.vbox.deinit();
    }
};

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
    const cols = dvui.dataGetPtrDefault(null, uniqueId, "cols", f32, 5);
    const rows = dvui.dataGetPtrDefault(null, uniqueId, "rows", f32, 5);

    _ = dvui.sliderEntry(@src(), "cols: {d}", .{ .value = cols, .min = 0, .max = 100, .interval = 1 }, .{});
    _ = dvui.sliderEntry(@src(), "rows: {d}", .{ .value = rows, .min = 0, .max = 100, .interval = 1 }, .{});

    {
        var table: TableWidget = undefined;
        table.init(@src(), .{}, .{ .border = .all(1), .style = .content, .background = true, .max_size_content = .height(300) });
        defer table.deinit();

        for (0..@trunc(cols.*)) |col| {
            for (0..@trunc(rows.*)) |row| {
                const cell = table.cell(col, row);

                const id = dvui.parentGet().extendId(@src(), cell.id_extra);
                const editing = dvui.dataGet(null, id, "editing", bool) orelse false;

                const src = @src();

                var wd: dvui.WidgetData = undefined;
                if (!editing) {
                    dvui.label(src, "Cell {d} {d}", .{ col, row }, .{ .data_out = &wd, .id_extra = cell.id_extra, .rect = cell.rect, .border = .all(1) });

                    if (cell.focus) {
                        const evts = dvui.events();
                        for (evts) |*e| {
                            if (!table.matchEvent(e)) continue;

                            switch (e.evt) {
                                .key => |*ke| {
                                    if (ke.action == .down and ke.code == .enter) {
                                        e.handle(@src(), &wd);
                                        dvui.dataSet(null, id, "editing", true);
                                        dvui.focusWidget(wd.id, null, e.num);
                                        dvui.refresh(null, @src(), wd.id);
                                        continue;
                                    }
                                },
                                else => {},
                            }
                        }
                    }
                } else {
                    var te = dvui.textEntry(src, .{}, .{ .data_out = &wd, .id_extra = cell.id_extra, .rect = cell.rect, .border = .all(1), .margin = .{}, .corner_radius = .{}, .min_size_content = .{} });
                    te.deinit();

                    if (wd.id != dvui.focusedWidgetIdInCurrentSubwindow()) {
                        // we lost focus
                        dvui.dataRemove(null, id, "editing");
                        dvui.refresh(null, @src(), wd.id);
                    }

                    const evts = dvui.events();
                    for (evts) |*e| {
                        if (!dvui.eventMatchSimple(e, &wd)) continue;

                        switch (e.evt) {
                            .key => |*ke| {
                                if (ke.action == .down and ke.code == .enter) {
                                    e.handle(@src(), &wd);
                                    dvui.dataRemove(null, id, "editing");
                                    dvui.focusWidget(table.data().id, null, e.num);
                                    dvui.refresh(null, @src(), wd.id);
                                    continue;
                                }
                            },
                            else => {},
                        }
                    }
                }

                table.cellMinSize(col, row, dvui.minSizeGet(wd.id).?);

                if (cell.focus) {
                    const rs = dvui.parentGet().screenRectScale(cell.rect);
                    rs.r.stroke(.{}, .{ .thickness = 2 * rs.s, .color = dvui.themeGet().focus, .after = true });
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
