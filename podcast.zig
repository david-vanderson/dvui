const std = @import("std");
const gui = @import("src/gui.zig");
const Backend = @import("src/SDLBackend.zig");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

pub fn main() !void {
    var backend = try Backend.init(360, 600);

    var win = gui.Window.init(gpa, backend.guiBackend());

    main_loop: while (true) {
        var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena_allocator.deinit();
        const arena = arena_allocator.allocator();

        var nstime = win.beginWait(backend.hasEvent());
        win.begin(arena, nstime);

        const quit = backend.addAllEvents(&win);
        if (quit) break :main_loop;

        backend.clear();

        {
            var float = gui.FloatingWindow(@src(), 0, false, null, null, .{});
            defer float.deinit();

            //var window_box = gui.Box(@src(), 0, .vertical, .{.expand = .both, .color_style = .window, .background = true});
            //defer window_box.deinit();

            var scale = gui.Scale(@src(), 0, 1.0, .{ .expand = .both, .background = false });
            defer scale.deinit();

            var box = gui.Box(@src(), 0, .vertical, .{ .expand = .both, .background = false });
            defer box.deinit();

            var paned = gui.Paned(@src(), 0, .horizontal, 400, .{ .expand = .both, .background = false });
            const collapsed = paned.collapsed();

            podcastSide(paned);
            episodeSide(paned);

            paned.deinit();

            if (collapsed) {
                player();
            }
        }

        const end_micros = win.end();

        if (win.CursorRequestedFloating()) |cursor| {
            backend.setCursor(cursor);
        } else {
            backend.setCursor(.bad);
        }

        backend.renderPresent();

        const wait_event_micros = win.wait(end_micros, null);

        backend.waitEventTimeout(wait_event_micros);
    }

    backend.deinit();
}

var show_dialog: bool = false;

fn podcastSide(paned: *gui.PanedWidget) void {
    var box = gui.Box(@src(), 0, .vertical, .{ .expand = .both });
    defer box.deinit();

    {
        var overlay = gui.Overlay(@src(), 0, .{ .expand = .horizontal });
        defer overlay.deinit();

        {
            var menu = gui.Menu(@src(), 0, .horizontal, .{ .expand = .horizontal });
            defer menu.deinit();

            gui.Spacer(@src(), 0, .{ .expand = .horizontal });

            if (gui.MenuItemLabel(@src(), 0, "Hello", true, .{})) |r| {
                var fw = gui.Popup(@src(), 0, gui.Rect.fromPoint(gui.Point{ .x = r.x, .y = r.y + r.h }), &menu.submenus_activated, menu, .{});
                defer fw.deinit();
                if (gui.MenuItemLabel(@src(), 0, "Add RSS", false, .{})) |rr| {
                    _ = rr;
                    show_dialog = true;
                    gui.MenuGet().?.close();
                }
            }
        }

        gui.Label(@src(), 0, "fps {d}", .{@round(gui.FPS())}, .{});
    }

    if (show_dialog) {
        var dialog = gui.FloatingWindow(@src(), 0, true, null, &show_dialog, .{});
        defer dialog.deinit();

        gui.LabelNoFormat(@src(), 0, "Add RSS Feed", .{ .gravity = .center });

        const TextEntryText = struct {
            //var text = array(u8, 100, "abcdefghijklmnopqrstuvwxyz");
            var text1 = array(u8, 100, "");
            fn array(comptime T: type, comptime size: usize, items: ?[]const T) [size]T {
                var output = std.mem.zeroes([size]T);
                if (items) |slice| std.mem.copy(T, &output, slice);
                return output;
            }
        };

        gui.TextEntry(@src(), 0, 26.0, &TextEntryText.text1, .{ .gravity = .center });

        var box2 = gui.Box(@src(), 0, .horizontal, .{ .gravity = .right });
        defer box2.deinit();
        if (gui.Button(@src(), 0, "Ok", .{})) {
            dialog.close();
        }
        if (gui.Button(@src(), 0, "Cancel", .{})) {
            dialog.close();
        }
    }

    var scroll = gui.ScrollArea(@src(), 0, null, .{ .expand = .both, .color_style = .window, .background = false });

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
            gui.Separator(@src(), i, oo3.override(.{ .margin = margin, .min_size = .{ .w = 1, .h = 1 }, .border = .{ .x = 1, .y = 1, .w = 0, .h = 0 } }));
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

        if (gui.Button(@src(), i, title, oo3.override(.{
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
        player();
    }
}

fn episodeSide(paned: *gui.PanedWidget) void {
    var box = gui.Box(@src(), 0, .vertical, .{ .expand = .both });
    defer box.deinit();

    if (paned.collapsed()) {
        var menu = gui.Menu(@src(), 0, .horizontal, .{ .expand = .horizontal });
        defer menu.deinit();

        if (gui.MenuItemLabel(@src(), 0, "Back", false, .{})) |rr| {
            _ = rr;
            paned.showOther();
        }
    }

    var scroll = gui.ScrollArea(@src(), 0, null, .{ .expand = .both, .background = false });
    defer scroll.deinit();

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var tl = gui.TextLayout(@src(), i, .{ .expand = .horizontal });

        var cbox = gui.Box(@src(), 0, .vertical, gui.Options{ .gravity = .upright });

        _ = gui.ButtonIcon(@src(), 0, 18, "play", gui.icons.papirus.actions.media_playback_start_symbolic, .{ .padding = gui.Rect.all(6) });
        _ = gui.ButtonIcon(@src(), 0, 18, "more", gui.icons.papirus.actions.view_more_symbolic, .{ .padding = gui.Rect.all(6) });

        cbox.deinit();

        var f = gui.ThemeGet().font_heading;
        f.line_skip_factor = 1.3;
        tl.addText("Episode Title\n", .{ .font_style = .custom, .font_custom = f });
        const lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.";
        tl.addText(lorem, .{});
        tl.deinit();
    }
}

fn player() void {
    const oo = gui.Options{
        .expand = .horizontal,
        .color_style = .content,
    };

    var box2 = gui.Box(@src(), 0, .vertical, oo.override(.{ .background = true }));
    defer box2.deinit();

    gui.Label(@src(), 0, "Title of the playing episode", .{}, oo.override(.{
        .margin = gui.Rect{ .x = 8, .y = 4, .w = 8, .h = 4 },
        .font_style = .heading,
    }));

    var box3 = gui.Box(@src(), 0, .horizontal, oo.override(.{ .padding = .{ .x = 4, .y = 0, .w = 4, .h = 4 } }));
    defer box3.deinit();

    const oo2 = gui.Options{ .expand = .horizontal, .gravity = .center };

    _ = gui.ButtonIcon(@src(), 0, 20, "back", gui.icons.papirus.actions.media_seek_backward_symbolic, oo2);

    gui.Label(@src(), 0, "0.00%", .{}, oo2.override(.{ .color_style = .content }));

    _ = gui.ButtonIcon(@src(), 0, 20, "forward", gui.icons.papirus.actions.media_seek_forward_symbolic, oo2);

    _ = gui.ButtonIcon(@src(), 0, 20, "play", gui.icons.papirus.actions.media_playback_start_symbolic, oo2);
}
