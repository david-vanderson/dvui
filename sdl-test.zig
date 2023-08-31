const std = @import("std");
const dvui = @import("dvui");
const SDLBackend = @import("SDLBackend");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

pub fn main() !void {
    var win_backend = try SDLBackend.init(.{
        .width = 800,
        .height = 600,
        .vsync = false,
        .title = "DVUI SDL test",
    });
    defer win_backend.deinit();

    var win = try dvui.Window.init(@src(), 0, gpa, win_backend.backend());
    win.content_scale = win_backend.initial_scale;
    defer win.deinit();

    const winSize = win_backend.windowSize();
    const pxSize = win_backend.pixelSize();
    std.debug.print("initial window logical {} pixels {} natural scale {d} initial content scale {d}\n", .{ winSize, pxSize, pxSize.w / winSize.w, win_backend.initial_scale });

    var buttons: [3][6]bool = undefined;
    for (&buttons) |*b| {
        b.* = [_]bool{true} ** 6;
    }

    var floats: [6]bool = [_]bool{false} ** 6;
    var scale_val: f32 = 1.0;
    var scale_mod: dvui.enums.Mod = .none;
    var dropdown_choice: usize = 1;

    //var rng = std.rand.DefaultPrng.init(0);

    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arena = arena_allocator.allocator();

    main_loop: while (true) {
        defer _ = arena_allocator.reset(.free_all);

        var nstime = win.beginWait(win_backend.hasEvent());
        try win.begin(arena, nstime);
        win_backend.clear();

        const quit = try win_backend.addAllEvents(&win);
        if (quit) break :main_loop;

        _ = try dvui.examples.demo();

        {
            var overlay = try dvui.overlay(@src(), .{ .expand = .both });
            defer overlay.deinit();

            const scale = try dvui.scale(@src(), scale_val, .{ .expand = .both });
            defer {
                var evts = dvui.events();
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
                            if (me.action == .wheel_y and scale_mod.ctrl()) {
                                e.handled = true;
                                var base: f32 = 1.01;
                                const zs = @exp(@log(base) * me.data.wheel_y);
                                if (zs != 1.0) {
                                    scale_val *= zs;
                                    dvui.refresh();
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
                var fw2 = try dvui.popup(@src(), dvui.Rect.fromPoint(cp), .{});
                defer fw2.deinit();

                _ = try dvui.menuItemLabel(@src(), "Cut", .{}, .{});
                if ((dvui.menuItemLabel(@src(), "Close", .{}, .{}) catch unreachable) != null) {
                    dvui.menuGet().?.close();
                }
                _ = try dvui.menuItemLabel(@src(), "Paste", .{}, .{});
            }

            {
                var win_scroll = try dvui.scrollArea(@src(), .{}, .{ .expand = .both, .color_style = .window });
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
                    if (try dvui.button(@src(), "Stroke Test", .{})) {
                        StrokeTest.show_dialog = !StrokeTest.show_dialog;
                    }

                    if (StrokeTest.show_dialog) {
                        try show_stroke_test_window();
                    }
                }

                {
                    var box = try dvui.box(@src(), .horizontal, .{});
                    defer box.deinit();

                    if (try dvui.button(@src(), "content_scale + .1", .{})) {
                        win.content_scale += 0.1;
                    }

                    if (try dvui.button(@src(), "content_scale - .1", .{})) {
                        win.content_scale -= 0.1;
                    }

                    try dvui.label(@src(), "content_scale {d}", .{win.content_scale}, .{});
                }

                {
                    try dvui.label(@src(), "Theme: {s}", .{dvui.themeGet().name}, .{});

                    if (try dvui.button(@src(), "Toggle Theme", .{})) {
                        if (dvui.themeGet() == &dvui.Adwaita.light) {
                            dvui.themeSet(&dvui.Adwaita.dark);
                        } else {
                            dvui.themeSet(&dvui.Adwaita.light);
                        }
                    }

                    if (try dvui.button(@src(), if (dvui.examples.show_demo_window) "Hide Demo Window" else "Show Demo Window", .{})) {
                        dvui.examples.show_demo_window = !dvui.examples.show_demo_window;
                    }
                }

                {
                    const Sel = struct {
                        var sel = dvui.TextLayoutWidget.Selection{};
                        var text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.";
                        var buf = std.mem.zeroes([256]u8);
                    };
                    {
                        var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
                        defer hbox.deinit();
                        try dvui.label(@src(), "{d} {d} : {d}", .{ Sel.sel.start, Sel.sel.end, Sel.sel.cursor }, .{});
                        if (try dvui.button(@src(), "Inc Start", .{})) {
                            Sel.sel.incStart();
                        }
                        if (try dvui.button(@src(), "Dec Start", .{})) {
                            Sel.sel.decStart();
                        }
                        if (try dvui.button(@src(), "Inc End", .{})) {
                            Sel.sel.incEnd();
                        }
                        if (try dvui.button(@src(), "Dec End", .{})) {
                            Sel.sel.decEnd();
                        }
                        if (try dvui.button(@src(), "Inc Cur", .{})) {
                            Sel.sel.incCursor();
                        }
                        if (try dvui.button(@src(), "Dec Cur", .{})) {
                            Sel.sel.decCursor();
                        }
                    }
                    var scroll = try dvui.scrollArea(@src(), .{ .horizontal = .auto }, .{ .min_size_content = .{ .w = 150, .h = 100 }, .margin = dvui.Rect.all(4) });
                    var tl = try dvui.textLayout(@src(), .{ .selection = &Sel.sel, .break_lines = false }, .{});
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
                    try tl.addTextDone(.{});
                    tl.deinit();
                    scroll.deinit();
                }
            }

            const fps = dvui.FPS();
            try dvui.label(@src(), "fps {d:4.2}", .{fps}, .{ .gravity_x = 1.0 });

            {
                const FloatingWindowTest = struct {
                    var show: bool = false;
                    var rect = dvui.Rect{ .x = 300, .y = 200, .w = 300, .h = 200 };
                };

                var start_closing: bool = false;

                if (try dvui.button(@src(), "Floating Window", .{ .gravity_x = 1.0, .gravity_y = 1.0, .margin = dvui.Rect.all(10) })) {
                    if (FloatingWindowTest.show) {
                        start_closing = true;
                    } else {
                        FloatingWindowTest.show = true;
                    }
                }

                if (FloatingWindowTest.show) {
                    var fwin = animatingWindow(@src(), false, &FloatingWindowTest.rect, &FloatingWindowTest.show, start_closing, .{});
                    //var fwin = dvui.FloatingWindowWidget.init(@src(), false, &FloatingWindowTest.rect, &FloatingWindowTest.show, .{});

                    try fwin.install(.{});
                    defer fwin.deinit();
                    try dvui.labelNoFmt(@src(), "Floating Window", .{ .gravity_x = 0.5, .gravity_y = 0.5 });

                    try dvui.label(@src(), "Pretty Cool", .{}, .{ .font = .{ .name = "VeraMono", .ttf_bytes = dvui.fonts.bitstream_vera.VeraMono, .size = 20 } });

                    if (try dvui.button(@src(), "button", .{})) {
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
                            var fw2 = try dvui.floatingWindow(@src(), .{ .modal = modal, .open_flag = f }, .{ .id_extra = fi, .color_style = .window, .min_size_content = .{ .w = 150, .h = 100 } });
                            defer fw2.deinit();
                            try dvui.labelNoFmt(@src(), buf_slice, .{ .gravity_x = 0.5, .gravity_y = 0.5 });

                            try dvui.label(@src(), "Asking a Question", .{}, .{});

                            const oo = dvui.Options{ .margin = dvui.Rect.all(4), .expand = .horizontal };
                            var box = try dvui.box(@src(), .horizontal, oo);

                            if (try dvui.button(@src(), "Yes", oo)) {
                                std.debug.print("Yes {d}\n", .{fi});
                                floats[fi + 1] = true;
                            }

                            if (try dvui.button(@src(), "No", oo)) {
                                std.debug.print("No {d}\n", .{fi});
                                fw2.close();
                            }

                            box.deinit();
                        }
                    }

                    var scroll = try dvui.scrollArea(@src(), .{}, .{ .expand = .both });
                    defer scroll.deinit();
                    var tl = dvui.TextLayoutWidget.init(@src(), .{}, .{ .expand = .horizontal });
                    try tl.install(.{ .process_events = false });
                    {
                        if (try dvui.button(@src(), "Win Up .1", .{})) {
                            fwin.wd.rect.y -= 0.1;
                        }
                        if (try dvui.button(@src(), "Win Down .1", .{ .gravity_x = 1.0 })) {
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
        }

        //window_box.deinit();
        //var window_box = try dvui.box(@src(), .vertical, .{ .expand = .both, .color_style = .window, .background = true });

        //var mx: c_int = 0;
        //var my: c_int = 0;
        //_ = SDLBackend.c.SDL_GetMouseState(&mx, &my);
        //try dvui.icon(@src(), "mouse", dvui.icons.papirus.actions.application_menu_symbolic, .{ .rect = dvui.Rect{ .x = @intToFloat(f32, mx), .y = @intToFloat(f32, my), .w = 10, .h = 10 } });

        const end_micros = try win.end(.{});

        win_backend.setCursor(win.cursorRequested());

        win_backend.renderPresent();

        const wait_event_micros = win.waitTime(end_micros, null);

        win_backend.waitEventTimeout(wait_event_micros);
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
        self.wd = dvui.WidgetData.init(src, .{}, options);
        dvui.debug("{x} StrokeTest {}", .{ self.wd.id, self.wd.rect });

        _ = dvui.captureMouseMaintain(self.wd.id);

        var evts = dvui.events();
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
            //_ = try dvui.button(@src(), i, "Floating", .{ .rect = dvui.Rect.fromPoint(p) });
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
                            dvui.refresh();
                        }
                    },
                    .wheel_y => {
                        e.handled = true;
                        var base: f32 = 1.05;
                        const zs = @exp(@log(base) * me.data.wheel_y);
                        if (zs != 1.0) {
                            thickness *= zs;
                            dvui.refresh();
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
