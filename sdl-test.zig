const std = @import("std");
const gui = @import("gui");
const SDLBackend = @import("SDLBackend");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

pub fn main() !void {
    var win_backend = try SDLBackend.init(.{
        .width = 800,
        .height = 600,
        .vsync = false,
        .title = "GUI SDL test",
    });
    defer win_backend.deinit();

    var win = try gui.Window.init(@src(), 0, gpa, win_backend.guiBackend());
    defer win.deinit();

    var buttons: [3][6]bool = undefined;
    for (&buttons) |*b| {
        b.* = [_]bool{true} ** 6;
    }

    var maxz: usize = 20;
    var floats: [6]bool = [_]bool{false} ** 6;
    var scale_val: f32 = 1.0;

    //var rng = std.rand.DefaultPrng.init(0);

    main_loop: while (true) {
        var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena_allocator.deinit();
        const arena = arena_allocator.allocator();

        var nstime = win.beginWait(win_backend.hasEvent());
        try win.begin(arena, nstime);
        win_backend.clear();

        const quit = try win_backend.addAllEvents(&win);
        if (quit) break :main_loop;

        _ = try gui.examples.demo();

        var window_box = try gui.box(@src(), .vertical, .{ .expand = .both, .color_style = .window, .background = true });

        {
            const oo = gui.Options{ .expand = .both };
            var overlay = try gui.overlay(@src(), oo);
            defer overlay.deinit();

            const scale = try gui.scale(@src(), scale_val, oo);
            defer {
                var iter = gui.EventIterator.init(scale.wd.id, scale.wd.borderRectScale().r, null);
                while (iter.next()) |e| {
                    switch (e.evt) {
                        .mouse => |me| {
                            if (me.kind == .wheel_y) {
                                e.handled = true;
                                var base: f32 = 1.01;
                                const zs = @exp(@log(base) * me.kind.wheel_y);
                                if (zs != 1.0) {
                                    scale_val *= zs;
                                    gui.refresh();
                                }
                            }
                        },
                        else => {},
                    }
                }

                scale.deinit();
            }

            const context = try gui.context(@src(), oo);
            defer context.deinit();

            if (context.activePoint()) |cp| {
                //std.debug.print("context.rect {}\n", .{context.rect});
                var fw2 = try gui.popup(@src(), gui.Rect.fromPoint(cp), .{});
                defer fw2.deinit();

                _ = try gui.menuItemLabel(@src(), "Cut", false, .{});
                if ((gui.menuItemLabel(@src(), "Close", false, .{}) catch unreachable) != null) {
                    gui.menuGet().?.close();
                }
                _ = try gui.menuItemLabel(@src(), "Paste", false, .{});
            }

            {
                var layout = try gui.box(@src(), .vertical, .{});
                defer layout.deinit();

                //{
                //  //const e2 = gui.Expand(.horizontal);
                //  //defer _ = gui.Expand(e2);

                //  var margin = gui.Margin(gui.Rect{.x = 20, .y = 20, .w = 20, .h = 20});
                //  defer _ = gui.Margin(margin);

                //  var box = gui.Box(@src(), .horizontal);
                //  defer box.deinit();
                //
                //  for (buttons) |*buttoncol, k| {
                //    if (k != 0) {
                //      gui.Spacer(@src(), k, 6);
                //    }
                //    if (buttoncol[0]) {
                //      var margin2 = gui.Margin(gui.Rect{.x = 4, .y = 4, .w = 4, .h = 4});
                //      defer _ = gui.Margin(margin2);

                //      var box2 = gui.Box(@src(), k, .vertical);
                //      defer box2.deinit();

                //      for (buttoncol) |b, i| {
                //        if (b) {
                //          if (i != 0) {
                //            gui.Spacer(@src(), i, 6);
                //            //gui.Label(@src(), i, "Label", .{});
                //          }
                //          var buf: [100:0]u8 = undefined;
                //          if (k == 0) {
                //            _ = std.fmt.bufPrintZ(&buf, "HELLO {d}", .{i}) catch unreachable;
                //          }
                //          else if (k == 1) {
                //            _ = std.fmt.bufPrintZ(&buf, "middle {d}", .{i}) catch unreachable;
                //          }
                //          else {
                //            _ = std.fmt.bufPrintZ(&buf, "bye {d}", .{i}) catch unreachable;
                //          }
                //          if (gui.Button(@src(), i, &buf)) {
                //            if (i == 0) {
                //              buttoncol[0] = false;
                //            }
                //            else if (i == 5) {
                //              buttons[k+1][0] = true;
                //            }
                //            else if (i % 2 == 0) {
                //              std.debug.print("Adding {d}\n", .{i + 1});
                //              buttoncol[i+1] = true;
                //            }
                //            else {
                //              std.debug.print("Removing {d}\n", .{i});
                //              buttoncol[i] = false;
                //            }
                //          }
                //        }
                //      }
                //    }
                //  }
                //}

                {
                    var scroll = try gui.scrollArea(@src(), .{}, .{ .min_size_content = .{ .w = 50, .h = 100 } });
                    defer scroll.deinit();

                    var vbox = try gui.box(@src(), .vertical, .{ .expand = .both });
                    defer vbox.deinit();

                    var buf: [100]u8 = undefined;
                    var z: usize = 0;
                    while (z < maxz) : (z += 1) {
                        const buf_slice = std.fmt.bufPrint(&buf, "Button {d:0>2}", .{z}) catch unreachable;
                        if (try gui.button(@src(), buf_slice, .{ .id_extra = z, .gravity_x = 0.5, .gravity_y = 1.0 })) {
                            if (z % 2 == 0) {
                                maxz += 1;
                            } else {
                                maxz -= 1;
                            }
                        }
                    }
                }

                {
                    if (try gui.button(@src(), "Stroke Test", .{})) {
                        StrokeTest.show_dialog = !StrokeTest.show_dialog;
                    }

                    if (StrokeTest.show_dialog) {
                        try show_stroke_test_window();
                    }
                }

                {
                    // FIXME
                    //const TextEntryText = struct {
                    //    //var text = array(u8, 100, "abcdefghijklmnopqrstuvwxyz");
                    //    var text1 = array(u8, 100, "abc");
                    //    var text2 = array(u8, 100, "abc");
                    //    fn array(comptime T: type, comptime size: usize, items: ?[]const T) [size]T {
                    //        var output = std.mem.zeroes([size]T);
                    //        if (items) |slice| std.mem.copy(T, &output, slice);
                    //        return output;
                    //    }
                    //};

                    //const msize = gui.TextEntryWidget.defaults.fontGet().textSize("M") catch unreachable;
                    //try gui.textEntry(@src(), &TextEntryText.text1, .{ .min_size_content = .{ .w = msize.w * 26.0, .h = msize.h } });
                    //try gui.textEntry(@src(), &TextEntryText.text2, .{ .min_size_content = .{ .w = msize.w * 26.0, .h = msize.h } });
                }

                {
                    var box = try gui.box(@src(), .horizontal, .{});

                    _ = try gui.button(@src(), "Accent", .{ .color_style = .accent });
                    _ = try gui.button(@src(), "Success", .{ .color_style = .success });
                    _ = try gui.button(@src(), "Error", .{ .color_style = .err });

                    box.deinit();

                    try gui.label(@src(), "Theme: {s}", .{gui.themeGet().name}, .{});

                    if (try gui.button(@src(), "Toggle Theme", .{})) {
                        if (gui.themeGet() == &gui.Adwaita.light) {
                            gui.themeSet(&gui.Adwaita.dark);
                        } else {
                            gui.themeSet(&gui.Adwaita.light);
                        }
                    }

                    if (try gui.button(@src(), if (gui.examples.show_demo_window) "Hide Demo Window" else "Show Demo Window", .{})) {
                        gui.examples.show_demo_window = !gui.examples.show_demo_window;
                    }
                }

                {
                    const Sel = struct {
                        var sel = gui.TextLayoutWidget.Selection{};
                        var text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.";
                        var buf = std.mem.zeroes([256]u8);
                    };
                    {
                        var hbox = try gui.box(@src(), .horizontal, .{ .expand = .horizontal });
                        defer hbox.deinit();
                        try gui.label(@src(), "{d} {d} : {d}", .{ Sel.sel.start, Sel.sel.end, Sel.sel.cursor }, .{});
                        if (try gui.button(@src(), "Inc Start", .{})) {
                            Sel.sel.start += 1;
                        }
                        if (try gui.button(@src(), "Dec Start", .{})) {
                            Sel.sel.start -= 1;
                        }
                        if (try gui.button(@src(), "Inc End", .{})) {
                            Sel.sel.end += 1;
                        }
                        if (try gui.button(@src(), "Dec End", .{})) {
                            Sel.sel.end -= 1;
                        }
                        if (try gui.button(@src(), "Inc Cur", .{})) {
                            Sel.sel.cursor += 1;
                        }
                        if (try gui.button(@src(), "Dec Cur", .{})) {
                            Sel.sel.cursor -= 1;
                        }
                    }
                    var scroll = try gui.scrollArea(@src(), .{ .horizontal = .auto }, .{ .min_size_content = .{ .w = 150, .h = 100 } });
                    var tl = try gui.textLayout(@src(), .{ .selection = &Sel.sel, .break_lines = false }, .{ .expand = .both });
                    {
                        //if (try gui.button(@src(), "Win Up .1", .{})) {
                        //    fwin.wd.rect.y -= 0.1;
                        //}
                        //if (try gui.button(@src(), "Win Down .1", .{ .gravity_x = 1.0 })) {
                        //    fwin.wd.rect.y += 0.1;
                        //}
                    }
                    const lorem =
                        \\Lorem ipsum dolor sit amet, consectetur adipiscing elit,
                        \\sed do eiusmod tempor incididunt ut labore et dolore
                        \\magna aliqua. Ut enim ad minim veniam, quis nostrud
                        \\exercitation ullamco laboris nisi ut aliquip ex ea
                        \\commodo consequat. Duis aute irure dolor in
                        \\reprehenderit in voluptate velit esse cillum dolore
                        \\eu fugiat nulla pariatur. Excepteur sint occaecat
                        \\cupidatat non proident, sunt in culpa qui officia
                        \\deserunt mollit anim id est laborum."
                    ;
                    try tl.addText(lorem, .{});
                    //const lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore";
                    //try tl.addText(Sel.text, .{});
                    //var it = std.mem.split(u8, lorem, " ");
                    //while (it.next()) |word| {
                    //  tl.addText(word);
                    //  tl.addText(" ");
                    //}
                    try tl.addTextDone(.{});
                    tl.deinit();
                    scroll.deinit();

                    try gui.textEntry(@src(), .{ .text = &Sel.buf, .scroll_horizontal = false }, .{ .min_size_content = .{ .w = 150, .h = 130 } });
                }
            }

            const fps = gui.FPS();
            //std.debug.print("fps {d}\n", .{@round(fps)});
            //gui.render_text = true;
            try gui.label(@src(), "fps {d:4.2}", .{fps}, .{ .gravity_x = 1.0 });
            //gui.render_text = false;
        }

        {
            const FloatingWindowTest = struct {
                var show: bool = false;
                var rect = gui.Rect{ .x = 300, .y = 200, .w = 300, .h = 200 };
            };

            var start_closing: bool = false;

            if (try gui.button(@src(), "Floating Window", .{})) {
                if (FloatingWindowTest.show) {
                    start_closing = true;
                } else {
                    FloatingWindowTest.show = true;
                }
            }

            if (FloatingWindowTest.show) {
                var fwin = animatingWindow(@src(), false, &FloatingWindowTest.rect, &FloatingWindowTest.show, start_closing, .{});
                //var fwin = gui.FloatingWindowWidget.init(@src(), false, &FloatingWindowTest.rect, &FloatingWindowTest.show, .{});

                try fwin.install(.{});
                defer fwin.deinit();
                try gui.labelNoFmt(@src(), "Floating Window", .{ .gravity_x = 0.5, .gravity_y = 0.5 });

                try gui.label(@src(), "Pretty Cool", .{}, .{ .font = .{ .name = "VeraMono", .ttf_bytes = gui.fonts.bitstream_vera.VeraMono, .size = 20 } });

                if (try gui.button(@src(), "button", .{})) {
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
                        var buf_slice = std.fmt.bufPrintZ(&buf, "{d} {s} Dialog", .{ fi, name }) catch unreachable;
                        var fw2 = try gui.floatingWindow(@src(), .{ .modal = modal, .open_flag = f }, .{ .id_extra = fi, .color_style = .window, .min_size_content = .{ .w = 150, .h = 100 } });
                        defer fw2.deinit();
                        try gui.labelNoFmt(@src(), buf_slice, .{ .gravity_x = 0.5, .gravity_y = 0.5 });

                        try gui.label(@src(), "Asking a Question", .{}, .{});

                        const oo = gui.Options{ .margin = gui.Rect.all(4), .expand = .horizontal };
                        var box = try gui.box(@src(), .horizontal, oo);

                        if (try gui.button(@src(), "Yes", oo)) {
                            std.debug.print("Yes {d}\n", .{fi});
                            floats[fi + 1] = true;
                        }

                        if (try gui.button(@src(), "No", oo)) {
                            std.debug.print("No {d}\n", .{fi});
                            fw2.close();
                        }

                        box.deinit();
                    }
                }

                var scroll = try gui.scrollArea(@src(), .{}, .{ .expand = .both });
                defer scroll.deinit();
                var tl = gui.TextLayoutWidget.init(@src(), .{}, .{ .expand = .both });
                try tl.install(.{ .process_events = false });
                {
                    if (try gui.button(@src(), "Win Up .1", .{})) {
                        fwin.wd.rect.y -= 0.1;
                    }
                    if (try gui.button(@src(), "Win Down .1", .{ .gravity_x = 1.0 })) {
                        fwin.wd.rect.y += 0.1;
                    }
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

        window_box.deinit();

        //var mx: c_int = 0;
        //var my: c_int = 0;
        //_ = SDLBackend.c.SDL_GetMouseState(&mx, &my);
        //try gui.icon(@src(), "mouse", gui.icons.papirus.actions.application_menu_symbolic, .{ .rect = gui.Rect{ .x = @intToFloat(f32, mx), .y = @intToFloat(f32, my), .w = 10, .h = 10 } });

        const end_micros = try win.end();

        win_backend.setCursor(win.cursorRequested());

        win_backend.renderPresent();

        const wait_event_micros = win.waitTime(end_micros, null);

        win_backend.waitEventTimeout(wait_event_micros);
    }
}

fn animatingWindow(src: std.builtin.SourceLocation, modal: bool, rect: *gui.Rect, openflag: *bool, start_closing: bool, opts: gui.Options) gui.FloatingWindowWidget {
    const fwin_id = gui.parentGet().extendID(src, opts.idExtra());

    if (gui.firstFrame(fwin_id)) {
        gui.animation(fwin_id, "rect_percent", gui.Animation{ .start_val = 0, .end_val = 1.0, .start_time = 0, .end_time = 100_000 });
        gui.dataSet(null, fwin_id, "size", rect.*.size());
    }

    if (start_closing) {
        gui.animation(fwin_id, "rect_percent", gui.Animation{ .start_val = 1.0, .end_val = 0, .start_time = 0, .end_time = 100_000 });
        gui.dataSet(null, fwin_id, "size", rect.*.size());
    }

    var fwin: gui.FloatingWindowWidget = undefined;

    if (gui.animationGet(fwin_id, "rect_percent")) |a| {
        if (gui.dataGet(null, fwin_id, "size", gui.Size)) |ss| {
            var r = rect.*;
            const dw = ss.w * a.lerp();
            const dh = ss.h * a.lerp();
            r.x = r.x + (r.w / 2) - (dw / 2);
            r.w = dw;
            r.y = r.y + (r.h / 2) - (dh / 2);
            r.h = dh;

            // don't pass rect so our animating rect doesn't get saved back
            fwin = gui.FloatingWindowWidget.init(src, .{ .modal = modal, .open_flag = openflag }, opts.override(.{ .rect = r }));

            if (a.done() and r.empty()) {
                // done with closing animation
                fwin.close();
            }
        }
    } else {
        fwin = gui.FloatingWindowWidget.init(src, .{ .modal = modal, .rect = rect, .open_flag = openflag }, opts);
    }

    return fwin;
}

fn show_stroke_test_window() !void {
    var win = try gui.floatingWindow(@src(), .{ .rect = &StrokeTest.show_rect, .open_flag = &StrokeTest.show_dialog }, .{});
    defer win.deinit();
    try gui.windowHeader("Stroke Test", "", &StrokeTest.show_dialog);

    //var scale = gui.scale(@src(), 1, .{.expand = .both});
    //defer scale.deinit();

    var st = StrokeTest{};
    try st.install(@src(), .{ .min_size_content = .{ .w = 400, .h = 400 }, .expand = .both });
}

pub const StrokeTest = struct {
    const Self = @This();
    var show_dialog: bool = false;
    var show_rect = gui.Rect{};
    var pointsArray: [10]gui.Point = [1]gui.Point{.{}} ** 10;
    var points: []gui.Point = pointsArray[0..0];
    var dragi: ?usize = null;
    var thickness: f32 = 1.0;

    wd: gui.WidgetData = undefined,

    pub fn install(self: *Self, src: std.builtin.SourceLocation, options: gui.Options) !void {
        self.wd = gui.WidgetData.init(src, options);
        gui.debug("{x} StrokeTest {}", .{ self.wd.id, self.wd.rect });

        _ = gui.captureMouseMaintain(self.wd.id);

        var iter = gui.EventIterator.init(self.data().id, self.data().borderRectScale().r, null);
        while (iter.next()) |e| {
            self.processEvent(e, false);
        }

        try self.wd.borderAndBackground(.{});

        _ = gui.parentSet(self.widget());

        const rs = self.wd.contentRectScale();
        const fill_color = gui.Color{ .r = 200, .g = 200, .b = 200, .a = 255 };
        for (points, 0..) |p, i| {
            var rect = gui.Rect.fromPoint(p.plus(.{ .x = -10, .y = -10 })).toSize(.{ .w = 20, .h = 20 });
            const rsrect = rect.scale(rs.s).offset(rs.r);
            try gui.pathAddRect(rsrect, gui.Rect.all(1));
            try gui.pathFillConvex(fill_color);

            _ = i;
            //_ = try gui.button(@src(), i, "Floating", .{ .rect = gui.Rect.fromPoint(p) });
        }

        for (points) |p| {
            const rsp = rs.pointToScreen(p);
            try gui.pathAddPoint(rsp);
        }

        const stroke_color = gui.Color{ .r = 0, .g = 0, .b = 255, .a = 150 };
        try gui.pathStroke(false, rs.s * thickness, .square, stroke_color);

        self.wd.minSizeSetAndRefresh();
        self.wd.minSizeReportToParent();
        _ = gui.parentSet(self.wd.parent);
    }

    pub fn widget(self: *Self) gui.Widget {
        return gui.Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
    }

    pub fn data(self: *Self) *gui.WidgetData {
        return &self.wd;
    }

    pub fn rectFor(self: *Self, id: u32, min_size: gui.Size, e: gui.Options.Expand, g: gui.Options.Gravity) gui.Rect {
        return gui.placeIn(self.wd.contentRect().justSize(), gui.minSize(id, min_size), e, g);
    }

    pub fn screenRectScale(self: *Self, r: gui.Rect) gui.RectScale {
        const rs = self.wd.contentRectScale();
        return gui.RectScale{ .r = r.scale(rs.s).offset(rs.r), .s = rs.s };
    }

    pub fn minSizeForChild(self: *Self, s: gui.Size) void {
        self.wd.minSizeMax(self.wd.padSize(s));
    }

    pub fn processEvent(self: *Self, e: *gui.Event, bubbling: bool) void {
        _ = bubbling;
        switch (e.evt) {
            .mouse => |me| {
                const rs = self.wd.contentRectScale();
                const mp = me.p.inRectScale(rs);
                switch (me.kind) {
                    .press => |button| {
                        if (button == .left) {
                            e.handled = true;
                            dragi = null;

                            for (points, 0..) |p, i| {
                                const dp = gui.Point.diff(p, mp);
                                if (@fabs(dp.x) < 5 and @fabs(dp.y) < 5) {
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
                                _ = gui.captureMouse(self.wd.id);
                                gui.dragPreStart(me.p, .crosshair, .{});
                            }
                        }
                    },
                    .release => |button| {
                        if (button == .left) {
                            e.handled = true;
                            _ = gui.captureMouse(null);
                            gui.dragEnd();
                        }
                    },
                    .motion => {
                        e.handled = true;
                        if (gui.dragging(me.p)) |dps| {
                            const dp = dps.scale(1 / rs.s);
                            points[dragi.?].x += dp.x;
                            points[dragi.?].y += dp.y;
                            gui.refresh();
                        }
                    },
                    .wheel_y => |ticks| {
                        e.handled = true;
                        var base: f32 = 1.05;
                        const zs = @exp(@log(base) * ticks);
                        if (zs != 1.0) {
                            thickness *= zs;
                            gui.refresh();
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
