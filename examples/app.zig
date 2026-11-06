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
            .app = "My-App",
            .org = "com.example.my-app",
            .icon = window_icon_png,
            .window_init_options = .{
                .keybinds_zoom = true, // Helps accessibility

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
    // Set log levels here
    .log_scope_levels = &.{.{
        .scope = .example_scope,
        .level = .debug,
    }},
};

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
pub fn appDeinit(win: *dvui.Window) void {
    _ = win;
    // good place to free anything you've allocated with win.gpa
}

// Run each frame to do normal UI
pub fn appFrame() !dvui.App.Result {
    {
        // Here's the dvui example content, replace/modify with your stuff

        if (menu()) |res| return res;

        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .style = .window });
        defer scroll.deinit();

        if (content()) |res| return res;
    }

    // only shows the demo if dvui.Examples.show_demo_window is true
    // .full -> .lite or comment out to speed up compile times
    dvui.Examples.demo(.lite);

    // after everything else, try pinch zoom
    global_pinch_zoom();

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
    if (dvui.button(@src(), "Debug Window", .{}, .{})) {
        dvui.toggleDebugWindow();
    }

    const label = if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window";
    if (dvui.button(@src(), label, .{}, .{ .tag = "show-demo-btn" })) {
        dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
    }

    {
        var directory_scroll_info: dvui.ScrollInfo = .{};
        var directories = std.ArrayList([]const u8).empty;
        directories.append(dvui.currentWindow().arena(), "Hello") catch @panic("OOM");
        directories.append(dvui.currentWindow().arena(), "Hello 2 ;lkasdjf ;laksjdf ;lkasdjf ;laksjdf ;lakjsdf ;laksjdf ;laksdjf ;asldfjk ") catch @panic("OOM");

        var directory_box = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both });
        defer directory_box.deinit();

        {
            var directory_list_box = dvui.box(@src(), .{
                .dir = .horizontal,
            }, .{ .expand = .both, .border = if (directories.items.len > 0) .all(1) else .all(0), .margin = .rect(4, if (directories.items.len > 0) 4 else 0, 0, 0), .padding = if (directories.items.len > 0) .rect(2, 0, 2, 0) else .rect(0, 4, 0, 0), .corners = .all(3) });
            defer directory_list_box.deinit();

            var directory_list = dvui.scrollArea(@src(), .{ .scroll_info = &directory_scroll_info, .vertical_bar = .hide, .horizontal_bar = .auto_overlay }, .{ .expand = .both, .max_size_content = .height(200) });
            defer directory_list.deinit();

            const directory_list_id = directory_list.data().id;
            dvui.dataSetSlice(dvui.currentWindow(), directory_list_id, "directories", directories.items);

            const directory_paths = dvui.dataGetSlice(dvui.currentWindow(), directory_list_id, "directories", [][]const u8) orelse @as([][]const u8, &.{});

            var grid = dvui.grid(@src(), .{}, .{ .expand = .both, .border = .all(0) });
            defer grid.deinit();

            for (directory_paths, 0..) |item, row| {
                {
                    var cell = grid.cell(.{ .row = row, .col = 0 }, .{ .expand = .both });
                    defer cell.deinit();

                    var cache = dvui.cacheSize(@src(), .{}, .{ .id_extra = row, .expand = .both });
                    defer cache.deinit();

                    if (cache.uncached()) {
                        dvui.label(@src(), "{s}\n", .{item}, .{ .expand = .both, .max_size_content = .width(1000) });
                    }
                }
                {
                    var cell = grid.cell(.{ .row = row, .col = 1 }, .{
                        .expand = .none,
                        //.min_size_content = .width(14),
                        //.max_size_content = .width(14),
                    });
                    defer cell.deinit();

                    var cache = dvui.cacheSize(@src(), .{}, .{
                        .id_extra = row,
                    });
                    defer cache.deinit();

                    if (cache.uncached()) {
                        if (dvui.buttonIcon(@src(), "minus", dvui.entypo.minus, .{ .draw_focus = false }, .{}, .{ .id_extra = row, .min_size_content = .{ .w = 14, .h = 14 }, .max_size_content = .{ .w = 14, .h = 14 }, .corners = .round(14), .gravity_x = 0.5, .gravity_y = 0.5 })) {
                            std.debug.print("{s}\n", .{"点击了移除按钮"});
                            _ = directories.orderedRemove(row);

                            dvui.dataSetSlice(dvui.currentWindow(), directory_list_id, "directories", directories.items);
                        }
                    }
                }
            }
        }
    }

    return null;
}

pub fn global_pinch_zoom() void {
    const uniqueId = dvui.parentGet().extendId(@src(), 0);
    const scale_gesture = dvui.dataGetPtrDefault(null, uniqueId, "scale_gesture", f32, 1.0);

    const evts = dvui.events();
    for (evts) |*e| {
        // only thing we care about now is if someone else already handled it
        if (!e.handled and e.evt == .mouse) {
            if (e.evt.mouse.action == .pinch_begin) {
                scale_gesture.* = dvui.currentWindow().content_scale;
            } else if (e.evt.mouse.action == .pinch_update) {
                dvui.currentWindow().content_scale = scale_gesture.* * e.evt.mouse.action.pinch_update;
            }
        }
    }
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
//    try t.snapshot(@src(), frame, .{});
//
//    try dvui.testing.pressKey(.tab, .none);
//    try dvui.testing.settle(frame);
//
//    try t.snapshot(@src(), frame, .{});
//}
