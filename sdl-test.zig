const std = @import("std");
const dvui = @import("dvui");
const SDLBackend = @import("SDLBackend");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const window_icon_png = @embedFile("src/zig-favicon.png");

pub fn main() !void {
    defer _ = gpa_instance.deinit();

    var backend = try SDLBackend.init(.{
        .allocator = gpa,
        .size = .{ .w = 800.0, .h = 600.0 },
        .vsync = false,
        .title = "DVUI SDL test",
    });
    defer backend.deinit();
    backend.setIconFromFileContent(window_icon_png);

    var win = try dvui.Window.init(@src(), 0, gpa, backend.backend());
    defer win.deinit();

    win.debug_touch_simulate_events = false;

    var buttons: [3][6]bool = undefined;
    for (&buttons) |*b| {
        b.* = [_]bool{true} ** 6;
    }

    var floats: [6]bool = [_]bool{false} ** 6;
    var scale_val: f32 = 1.0;
    var scale_mod: dvui.enums.Mod = .none;
    var dropdown_choice: usize = 1;
    var num_windows: usize = 0;

    //var rng = std.rand.DefaultPrng.init(0);

    main_loop: while (true) {
        const nstime = win.beginWait(backend.hasEvent());
        try win.begin(nstime);
        backend.clear();

        const quit = try backend.addAllEvents(&win);
        if (quit) break :main_loop;

        _ = try dvui.Examples.demo();

        {
            var overlay = try dvui.overlay(@src(), .{ .expand = .both });
            defer overlay.deinit();

            const scale = try dvui.scale(@src(), scale_val, .{ .expand = .both });
            defer {
                const evts = dvui.events();
                for (evts) |*e| {
                    switch (e.evt) {
                        .key => |ke| {
                            scale_mod = ke.mod;
                            //std.debug.print("mod = {d}\n", .{scale_mod});
                        },
                        else => {},
                    }

                    if (!dvui.eventMatch(e, .{ .id = scale.wd.id, .r = scale.wd.borderRectScale().r }))
                        continue;

                    switch (e.evt) {
                        .mouse => |me| {
                            if (me.action == .wheel_y and scale_mod.controlCommand()) {
                                e.handled = true;
                                const base: f32 = 1.01;
                                const zs = @exp(@log(base) * me.data.wheel_y);
                                if (zs != 1.0) {
                                    scale_val *= zs;
                                    dvui.refresh(null, @src(), scale.wd.id);
                                }
                            }
                        },
                        else => {},
                    }
                }

                scale.deinit();
            }

            const context = try dvui.context(@src(), .{ .expand = .both });
            defer context.deinit();

            if (context.activePoint()) |cp| {
                //std.debug.print("context.rect {}\n", .{context.rect});
                var fw2 = try dvui.floatingMenu(@src(), dvui.Rect.fromPoint(cp), .{});
                defer fw2.deinit();

                _ = try dvui.menuItemLabel(@src(), "Cut", .{}, .{ .expand = .horizontal });
                if ((dvui.menuItemLabel(@src(), "Close", .{}, .{ .expand = .horizontal }) catch unreachable) != null) {
                    dvui.menuGet().?.close();
                }
                _ = try dvui.menuItemLabel(@src(), "Paste", .{}, .{ .expand = .horizontal });
            }

            {
                var win_scroll = try dvui.scrollArea(@src(), .{}, .{ .expand = .both, .color_fill = .{ .name = .fill_window } });
                defer win_scroll.deinit();

                {
                    const entries = [_][]const u8{
                        "First 1",
                        "First 2",
                        "First 3",
                        "First 4",
                        "First 5",
                        "Second 1",
                        "Second 2",
                        "Second 3",
                        "Second 4",
                        "Second 5",
                        "Third 1",
                        "Third 2",
                        "Third 3",
                        "Third 4",
                        "Third 5",
                    };

                    _ = try dvui.dropdown(@src(), &entries, &dropdown_choice, .{ .min_size_content = .{ .w = 120 } });
                }

                {
                    if (try dvui.button(@src(), "Stroke Test", .{}, .{})) {
                        StrokeTest.show_dialog = !StrokeTest.show_dialog;
                    }

                    if (StrokeTest.show_dialog) {
                        try show_stroke_test_window();
                    }
                }

                {
                    var box = try dvui.box(@src(), .horizontal, .{});
                    defer box.deinit();

                    if (try dvui.button(@src(), "content_scale + .1", .{}, .{})) {
                        win.content_scale += 0.1;
                    }

                    if (try dvui.button(@src(), "content_scale - .1", .{}, .{})) {
                        win.content_scale -= 0.1;
                        win.content_scale = @max(0.1, win.content_scale);
                    }

                    try dvui.label(@src(), "content_scale {d}", .{win.content_scale}, .{});
                }

                {
                    try dvui.label(@src(), "Theme: {s}", .{dvui.themeGet().name}, .{});

                    if (try dvui.button(@src(), "Toggle Theme", .{}, .{})) {
                        if (dvui.themeGet() == &dvui.Adwaita.light) {
                            dvui.themeSet(&dvui.Adwaita.dark);
                        } else {
                            dvui.themeSet(&dvui.Adwaita.light);
                        }
                    }

                    if (try dvui.button(@src(), if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window", .{}, .{})) {
                        dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
                    }
                }

                {
                    if (try dvui.button(@src(), "add window", .{}, .{})) {
                        num_windows += 10;
                    }

                    for (0..num_windows) |i| {
                        var open: bool = true;
                        //var nwin = try dvui.floatingWindow(@src(), .{ .open_flag = &open, .window_avoid = .nudge }, .{ .id_extra = i, .color_style = .window, .min_size_content = .{ .w = 200, .h = 60 } });
                        var nwin = try dvui.floatingWindow(@src(), .{ .open_flag = &open }, .{ .id_extra = i, .min_size_content = .{ .w = 200, .h = 60 } });
                        //var nwin = dvui.FloatingWindowWidget.init(@src(), .{
                        //    .open_flag = &open,
                        //}, .{ .id_extra = i, .color_style = .window, .min_size_content = .{ .w = 200, .h = 60 } });

                        //if (dvui.firstFrame(nwin.wd.id)) {
                        //    dvui.dataSet(null, nwin.wd.id, "randomize", true);
                        //} else if (dvui.dataGet(null, nwin.wd.id, "randomize", bool) != null) {
                        //    dvui.dataRemove(null, nwin.wd.id, "randomize");

                        //    var prng = std.rand.DefaultPrng.init(@truncate(std.math.absCast(dvui.frameTimeNS())));
                        //    var rand = prng.random();
                        //    nwin.wd.rect.x = rand.float(f32) * (dvui.windowRect().w - 24);
                        //    nwin.wd.rect.y = rand.float(f32) * (dvui.windowRect().h - 24);
                        //}

                        //try nwin.install(.{});

                        defer nwin.deinit();

                        try dvui.windowHeader("Modal Dialog", "", &open);

                        if (try dvui.button(@src(), "add window", .{}, .{})) {
                            num_windows += 3;
                        }

                        if (!open) {
                            num_windows = 0;
                        }
                    }
                }

                {
                    const glob = struct {
                        var strings = [_][]const u8{ "one", "two", "three", "four", "five", "six" };
                        //var strings = [_][]const u8{"one"};
                    };

                    //var down_idx: ?usize = null;

                    var vbox = try dvui.box(@src(), .vertical, .{ .min_size_content = .{ .w = 300 }, .background = true, .border = dvui.Rect.all(1), .padding = dvui.Rect.all(4) });
                    defer vbox.deinit();

                    var reorder = try dvui.reorder(@src(), .{});

                    var reorderable: dvui.Reorderable = undefined;

                    var removed_idx: ?usize = null;
                    var insert_before_idx: ?usize = null;

                    var seen_non_floating = false;
                    for (glob.strings, 0..) |s, i| {
                        reorderable = dvui.Reorderable.init(@src(), reorder, .{}, .{ .id_extra = i, .expand = .horizontal });

                        if (!reorderable.floating()) {
                            if (seen_non_floating) {
                                try dvui.separator(@src(), .{ .id_extra = i, .expand = .horizontal, .margin = dvui.Rect.all(10) });
                            } else {
                                seen_non_floating = true;
                            }
                        }

                        try reorderable.install();

                        if (reorderable.removed()) {
                            removed_idx = i;
                        } else if (reorderable.insertBefore()) {
                            insert_before_idx = i;
                        }

                        if (reorderable.targetRectScale()) |rs| {
                            // user is dragging a reorderable over this rect
                            try dvui.pathAddRect(rs.r, .{});
                            try dvui.pathFillConvex(.{ .r = 0, .g = 255, .b = 0 });

                            // reset to use next space
                            try dvui.separator(@src(), .{ .expand = .horizontal, .margin = dvui.Rect.all(10) });
                            try reorderable.reinstall();
                        }

                        var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .horizontal, .border = dvui.Rect.all(1), .background = true, .color_fill = .{ .name = .fill_window } });

                        try dvui.label(@src(), "String : {s}", .{s}, .{});

                        try dvui.ReorderWidget.draggable(@src(), &reorderable, .{ .expand = .vertical, .gravity_x = 1.0, .min_size_content = dvui.Size.all(22), .gravity_y = 0.5 });

                        //if (try dvui.button(@src(), "down", .{}, .{ .gravity_x = 1.0 })) {
                        //    if (i < glob.strings.len - 1) {
                        //        down_idx = i;
                        //    }
                        //}

                        hbox.deinit();
                        reorderable.deinit();
                    }

                    if (reorder.needFinalSlot()) {
                        if (seen_non_floating) {
                            try dvui.separator(@src(), .{ .expand = .horizontal, .margin = dvui.Rect.all(10) });
                        }
                        reorderable = dvui.Reorderable.init(@src(), reorder, .{ .last_slot = true }, .{});
                        try reorderable.install();
                        if (reorderable.insertBefore()) {
                            insert_before_idx = glob.strings.len;
                        }
                        if (reorderable.targetRectScale()) |rs| {
                            // user is dragging a reorderable over this rect
                            try dvui.pathAddRect(rs.r, .{});
                            try dvui.pathFillConvex(.{ .r = 0, .g = 255, .b = 0 });
                        }
                        reorderable.deinit();
                    }

                    reorder.deinit();

                    if (removed_idx) |ri| {
                        if (insert_before_idx) |ibi| {
                            // remove this index
                            const removed = glob.strings[ri];
                            if (ri < ibi) {
                                // moving down, shift others up
                                for (ri..ibi - 1) |i| {
                                    glob.strings[i] = glob.strings[i + 1];
                                }
                                glob.strings[ibi - 1] = removed;
                            } else {
                                // moving up, shift others down
                                for (ibi..ri, 0..) |_, i| {
                                    glob.strings[ri - i] = glob.strings[ri - i - 1];
                                }
                                glob.strings[ibi] = removed;
                            }
                        }
                    }

                    //if (down_idx) |di| {
                    //    const str = glob.strings[di + 1];
                    //    glob.strings[di + 1] = glob.strings[di];
                    //    glob.strings[di] = str;
                    //}
                }

                //{
                //    var hbox = try dvui.box(@src(), .horizontal, .{});
                //    defer hbox.deinit();
                //    const buf = dvui.dataGetSlice(null, hbox.wd.id, "data_key", [:0]u8) orelse blk: {
                //        dvui.dataSetSlice(null, hbox.wd.id, "data_key", "hello\n" ** 10);
                //        break :blk dvui.dataGetSlice(null, hbox.wd.id, "data_key", [:0]u8).?;
                //    };

                //    //var te = try dvui.textEntry(@src(), .{
                //    var te = dvui.TextEntryWidget.init(@src(), .{
                //        .text = buf,
                //        .multiline = true,
                //        .scroll_vertical = false,
                //        .scroll_horizontal = false,
                //    }, .{});
                //    try te.install();
                //    _ = try dvui.button(@src(), "upleft", .{}, .{});
                //    _ = try dvui.button(@src(), "upright", .{}, .{ .gravity_x = 1.0 });
                //    _ = try dvui.button(@src(), "downleft", .{}, .{ .gravity_y = 1.0 });
                //    _ = try dvui.button(@src(), "downright", .{}, .{ .gravity_x = 1.0, .gravity_y = 1.0 });
                //    te.processEvents();
                //    try te.draw();
                //    te.deinit();

                //    var tl = dvui.TextLayoutWidget.init(@src(), .{}, .{});
                //    try tl.install(.{});

                //    _ = try dvui.button(@src(), "upleft", .{}, .{});
                //    _ = try dvui.button(@src(), "upright", .{}, .{ .gravity_x = 1.0 });
                //    _ = try dvui.button(@src(), "downleft", .{}, .{ .gravity_y = 1.0 });
                //    _ = try dvui.button(@src(), "downright", .{}, .{ .gravity_x = 1.0, .gravity_y = 1.0 });

                //    if (try tl.touchEditing()) |floating_widget| {
                //        defer floating_widget.deinit();
                //        try tl.touchEditingMenu();
                //    }

                //    tl.processEvents();

                //    try tl.addText(std.mem.sliceTo(buf, 0), .{});

                //    tl.deinit();
                //}

                //{
                //    const Sel = struct {
                //        var sel = dvui.TextLayoutWidget.Selection{};
                //    };
                //    {
                //        var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
                //        defer hbox.deinit();
                //        try dvui.label(@src(), "{d} {d} : {d}", .{ Sel.sel.start, Sel.sel.end, Sel.sel.cursor }, .{});
                //        if (try dvui.button(@src(), "Inc Start", .{}, .{})) {
                //            Sel.sel.incStart();
                //        }
                //        if (try dvui.button(@src(), "Dec Start", .{}, .{})) {
                //            Sel.sel.decStart();
                //        }
                //        if (try dvui.button(@src(), "Inc End", .{}, .{})) {
                //            Sel.sel.incEnd();
                //        }
                //        if (try dvui.button(@src(), "Dec End", .{}, .{})) {
                //            Sel.sel.decEnd();
                //        }
                //        if (try dvui.button(@src(), "Inc Cur", .{}, .{})) {
                //            Sel.sel.incCursor();
                //        }
                //        if (try dvui.button(@src(), "Dec Cur", .{}, .{})) {
                //            Sel.sel.decCursor();
                //        }
                //    }
                //    var scroll = try dvui.scrollArea(@src(), .{ .horizontal = .auto }, .{ .min_size_content = .{ .w = 150, .h = 100 }, .margin = dvui.Rect.all(4) });
                //    var tl = try dvui.textLayout(@src(), .{ .selection = &Sel.sel, .break_lines = false }, .{});
                //    const lorem1 =
                //        \\Lorem € ipsum dolor sit amet, consectetur adipiscing elit,
                //        \\sed do eiusmod tempor incididunt ut labore et dolore
                //        \\magna
                //    ;
                //    const lorem2 =
                //        \\. Ut enim ad minim veniam, quis nostrud
                //        \\exercitation ullamco laboris nisi ut aliquip ex ea
                //        \\commodo consequat. Duis aute irure dolor in
                //        \\reprehenderit in voluptate velit esse cillum dolore
                //        \\eu fugiat nulla pariatur. Excepteur sint occaecat
                //        \\cupidatat non proident, sunt in culpa qui officia
                //        \\deserunt mollit anim id est laborum.
                //    ;
                //    try tl.addText(lorem1, .{});
                //    if (try tl.addTextClick("aliqua", .{ .color_text = .{ .color = .{ .r = 0x35, .g = 0x84, .b = 0xe4 } } })) {
                //        std.debug.print("clicked\n", .{});
                //    }
                //    try tl.addText(lorem2, .{});
                //    try tl.addTextDone(.{});
                //    tl.deinit();
                //    scroll.deinit();
                //}
            }

            const fps = dvui.FPS();
            try dvui.label(@src(), "fps {d:4.2}", .{fps}, .{ .gravity_x = 1.0, .min_size_content = .{ .w = 100 } });

            {
                const FloatingWindowTest = struct {
                    var show: bool = false;
                    var rect = dvui.Rect{ .x = 300, .y = 200, .w = 300, .h = 200 };
                };

                var start_closing: bool = false;

                if (try dvui.button(@src(), "Floating Window", .{}, .{ .gravity_x = 1.0, .gravity_y = 1.0, .margin = dvui.Rect.all(10) })) {
                    if (FloatingWindowTest.show) {
                        start_closing = true;
                    } else {
                        FloatingWindowTest.show = true;
                    }
                }

                if (FloatingWindowTest.show) {
                    var fwin = animatingWindow(@src(), false, &FloatingWindowTest.rect, &FloatingWindowTest.show, start_closing, .{});
                    //var fwin = dvui.FloatingWindowWidget.init(@src(), false, &FloatingWindowTest.rect, &FloatingWindowTest.show, .{});

                    try fwin.install();
                    fwin.processEventsBefore();
                    try fwin.drawBackground();
                    defer fwin.deinit();
                    try dvui.labelNoFmt(@src(), "Floating Window", .{ .gravity_x = 0.5, .gravity_y = 0.5 });

                    try dvui.label(@src(), "Pretty Cool", .{}, .{ .font = .{ .name = "VeraMono", .ttf_bytes = dvui.bitstream_vera.VeraMono, .size = 20 } });

                    if (try dvui.button(@src(), "button", .{}, .{})) {
                        floats[0] = true;
                    }

                    for (&floats, 0..) |*f, fi| {
                        if (f.*) {
                            const modal = if (fi % 2 == 0) true else false;
                            var name: []const u8 = "";
                            if (modal) {
                                name = "Modal";
                            }
                            var buf = std.mem.zeroes([100]u8);
                            const buf_slice = std.fmt.bufPrintZ(&buf, "{d} {s} Dialog", .{ fi, name }) catch unreachable;
                            var fw2 = try dvui.floatingWindow(@src(), .{ .modal = modal, .open_flag = f }, .{ .id_extra = fi, .min_size_content = .{ .w = 150, .h = 100 } });
                            defer fw2.deinit();
                            try dvui.labelNoFmt(@src(), buf_slice, .{ .gravity_x = 0.5, .gravity_y = 0.5 });

                            try dvui.label(@src(), "Asking a Question", .{}, .{});

                            const oo = dvui.Options{ .margin = dvui.Rect.all(4), .expand = .horizontal };
                            var box = try dvui.box(@src(), .horizontal, oo);

                            if (try dvui.button(@src(), "Yes", .{}, oo)) {
                                std.debug.print("Yes {d}\n", .{fi});
                                floats[fi + 1] = true;
                            }

                            if (try dvui.button(@src(), "No", .{}, oo)) {
                                std.debug.print("No {d}\n", .{fi});
                                fw2.close();
                            }

                            box.deinit();
                        }
                    }

                    var scroll = try dvui.scrollArea(@src(), .{}, .{ .expand = .both });
                    defer scroll.deinit();
                    var tl = dvui.TextLayoutWidget.init(@src(), .{}, .{ .expand = .horizontal });
                    try tl.install(.{});
                    {
                        if (try dvui.button(@src(), "Win Up .1", .{}, .{})) {
                            fwin.wd.rect.y -= 0.1;
                        }
                        if (try dvui.button(@src(), "Win Down .1", .{}, .{ .gravity_x = 1.0 })) {
                            fwin.wd.rect.y += 0.1;
                        }
                    }
                    if (try tl.touchEditing()) |floating_widget| {
                        defer floating_widget.deinit();
                        try tl.touchEditingMenu();
                    }
                    tl.processEvents();
                    const lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.";
                    //const lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore";
                    try tl.addText(lorem, .{});
                    //var it = std.mem.split(u8, lorem, " ");
                    //while (it.next()) |word| {
                    //  tl.addText(word);
                    //  tl.addText(" ");
                    //}
                    tl.deinit();
                }
            }
        }

        //window_box.deinit();
        //var window_box = try dvui.box(@src(), .vertical, .{ .expand = .both, .color_style = .window, .background = true });

        //var mx: c_int = 0;
        //var my: c_int = 0;
        //_ = SDLBackend.c.SDL_GetMouseState(&mx, &my);
        //try dvui.icon(@src(), "mouse", dvui.icons.papirus.actions.application_menu_symbolic, .{ .rect = dvui.Rect{ .x = @intToFloat(f32, mx), .y = @intToFloat(f32, my), .w = 10, .h = 10 } });

        const end_micros = try win.end(.{});

        backend.setCursor(win.cursorRequested());

        backend.renderPresent();

        const wait_event_micros = win.waitTime(end_micros, null);

        backend.waitEventTimeout(wait_event_micros);
    }
}

fn animatingWindow(src: std.builtin.SourceLocation, modal: bool, rect: *dvui.Rect, openflag: *bool, start_closing: bool, opts: dvui.Options) dvui.FloatingWindowWidget {
    const fwin_id = dvui.parentGet().extendId(src, opts.idExtra());

    if (dvui.firstFrame(fwin_id)) {
        dvui.animation(fwin_id, "rect_percent", dvui.Animation{ .start_val = 0, .end_val = 1.0, .start_time = 0, .end_time = 100_000 });
        dvui.dataSet(null, fwin_id, "size", rect.*.size());
    }

    if (start_closing) {
        dvui.animation(fwin_id, "rect_percent", dvui.Animation{ .start_val = 1.0, .end_val = 0, .start_time = 0, .end_time = 100_000 });
        dvui.dataSet(null, fwin_id, "size", rect.*.size());
    }

    var fwin: dvui.FloatingWindowWidget = undefined;

    if (dvui.animationGet(fwin_id, "rect_percent")) |a| {
        if (dvui.dataGet(null, fwin_id, "size", dvui.Size)) |ss| {
            var r = rect.*;
            const dw = ss.w * a.lerp();
            const dh = ss.h * a.lerp();
            r.x = r.x + (r.w / 2) - (dw / 2);
            r.w = dw;
            r.y = r.y + (r.h / 2) - (dh / 2);
            r.h = dh;

            // don't pass rect so our animating rect doesn't get saved back
            fwin = dvui.FloatingWindowWidget.init(src, .{ .modal = modal, .open_flag = openflag }, opts.override(.{ .rect = r }));

            if (a.done() and r.empty()) {
                // done with closing animation
                fwin.close();
            }
        }
    } else {
        fwin = dvui.FloatingWindowWidget.init(src, .{ .modal = modal, .rect = rect, .open_flag = openflag }, opts);
    }

    return fwin;
}

fn show_stroke_test_window() !void {
    var win = try dvui.floatingWindow(@src(), .{ .rect = &StrokeTest.show_rect, .open_flag = &StrokeTest.show_dialog }, .{});
    defer win.deinit();
    try dvui.windowHeader("Stroke Test", "", &StrokeTest.show_dialog);

    //var scale = dvui.scale(@src(), 1, .{.expand = .both});
    //defer scale.deinit();

    var st = StrokeTest{};
    try st.install(@src(), .{ .min_size_content = .{ .w = 400, .h = 400 }, .expand = .both });
}

pub const StrokeTest = struct {
    const Self = @This();
    var show_dialog: bool = false;
    var show_rect = dvui.Rect{};
    var pointsArray: [10]dvui.Point = [1]dvui.Point{.{}} ** 10;
    var points: []dvui.Point = pointsArray[0..0];
    var dragi: ?usize = null;
    var thickness: f32 = 1.0;

    wd: dvui.WidgetData = undefined,

    pub fn install(self: *Self, src: std.builtin.SourceLocation, options: dvui.Options) !void {
        _ = try dvui.sliderEntry(@src(), "thick: {d:0.2}", .{ .value = &thickness }, .{ .expand = .horizontal });

        const defaults = dvui.Options{ .name = "StrokeTest" };
        self.wd = dvui.WidgetData.init(src, .{}, defaults.override(options));
        try self.wd.register();

        const evts = dvui.events();
        for (evts) |*e| {
            if (!dvui.eventMatch(e, .{ .id = self.data().id, .r = self.data().borderRectScale().r }))
                continue;

            self.processEvent(e, false);
        }

        try self.wd.borderAndBackground(.{});

        _ = dvui.parentSet(self.widget());

        const rs = self.wd.contentRectScale();
        const fill_color = dvui.Color{ .r = 200, .g = 200, .b = 200, .a = 255 };
        for (points, 0..) |p, i| {
            var rect = dvui.Rect.fromPoint(p.plus(.{ .x = -10, .y = -10 })).toSize(.{ .w = 20, .h = 20 });
            const rsrect = rect.scale(rs.s).offset(rs.r);
            try dvui.pathAddRect(rsrect, dvui.Rect.all(1));
            try dvui.pathFillConvex(fill_color);

            _ = i;
            //_ = try dvui.button(@src(), i, "Floating", .{}, .{ .rect = dvui.Rect.fromPoint(p) });
        }

        for (points) |p| {
            const rsp = rs.pointToScreen(p);
            try dvui.pathAddPoint(rsp);
        }

        const stroke_color = dvui.Color{ .r = 0, .g = 0, .b = 255, .a = 150 };
        try dvui.pathStroke(false, rs.s * thickness, .square, stroke_color);

        self.wd.minSizeSetAndRefresh();
        self.wd.minSizeReportToParent();
        _ = dvui.parentSet(self.wd.parent);
    }

    pub fn widget(self: *Self) dvui.Widget {
        return dvui.Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
    }

    pub fn data(self: *Self) *dvui.WidgetData {
        return &self.wd;
    }

    pub fn rectFor(self: *Self, id: u32, min_size: dvui.Size, e: dvui.Options.Expand, g: dvui.Options.Gravity) dvui.Rect {
        return dvui.placeIn(self.wd.contentRect().justSize(), dvui.minSize(id, min_size), e, g);
    }

    pub fn screenRectScale(self: *Self, r: dvui.Rect) dvui.RectScale {
        const rs = self.wd.contentRectScale();
        return dvui.RectScale{ .r = r.scale(rs.s).offset(rs.r), .s = rs.s };
    }

    pub fn minSizeForChild(self: *Self, s: dvui.Size) void {
        self.wd.minSizeMax(self.wd.padSize(s));
    }

    pub fn processEvent(self: *Self, e: *dvui.Event, bubbling: bool) void {
        _ = bubbling;
        switch (e.evt) {
            .mouse => |me| {
                const rs = self.wd.contentRectScale();
                const mp = rs.pointFromScreen(me.p);
                switch (me.action) {
                    .press => {
                        if (me.button == .left) {
                            e.handled = true;
                            dragi = null;

                            for (points, 0..) |p, i| {
                                const dp = dvui.Point.diff(p, mp);
                                if (@abs(dp.x) < 5 and @abs(dp.y) < 5) {
                                    dragi = i;
                                    break;
                                }
                            }

                            if (dragi == null and points.len < pointsArray.len) {
                                dragi = points.len;
                                points.len += 1;
                                points[dragi.?] = mp;
                            }

                            if (dragi != null) {
                                _ = dvui.captureMouse(self.wd.id);
                                dvui.dragPreStart(me.p, .crosshair, .{});
                            }
                        }
                    },
                    .release => {
                        if (me.button == .left) {
                            e.handled = true;
                            _ = dvui.captureMouse(null);
                            dvui.dragEnd();
                        }
                    },
                    .motion => {
                        e.handled = true;
                        if (dvui.dragging(me.p)) |dps| {
                            const dp = dps.scale(1 / rs.s);
                            points[dragi.?].x += dp.x;
                            points[dragi.?].y += dp.y;
                            dvui.refresh(null, @src(), self.wd.id);
                        }
                    },
                    .wheel_y => {
                        e.handled = true;
                        const base: f32 = 1.02;
                        const zs = @exp(@log(base) * me.data.wheel_y);
                        if (zs != 1.0) {
                            thickness *= zs;
                            dvui.refresh(null, @src(), self.wd.id);
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }

        if (e.bubbleable()) {
            self.wd.parent.processEvent(e, true);
        }
    }
};
