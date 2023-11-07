const std = @import("std");
const dvui = @import("dvui.zig");

const DialogCallAfterFn = dvui.DialogCallAfterFn;
const Error = dvui.Error;
const Options = dvui.Options;
const Point = dvui.Point;
const Rect = dvui.Rect;
const ScrollInfo = dvui.ScrollInfo;
const Size = dvui.Size;
const entypo = dvui.entypo;
const Adwaita = dvui.Adwaita;

const enums = dvui.enums;

const zig_favicon = @embedFile("zig-favicon.png");

// TODO: Split
const FloatingWindowWidget = dvui.FloatingWindowWidget;
const TextLayoutWidget = dvui.TextLayoutWidget;
const ButtonWidget = dvui.ButtonWidget;
const LabelWidget = dvui.LabelWidget;

pub var show_demo_window: bool = false;
var checkbox_bool: bool = false;
var icon_image_size_extra: f32 = 0;
var icon_image_rotation: f32 = 0;
var slider_val: f32 = 0.0;
var text_entry_buf = std.mem.zeroes([30]u8);
var text_entry_password_buf = std.mem.zeroes([30]u8);
var text_entry_password_buf_obf_enable: bool = true;
var text_entry_multiline_buf = std.mem.zeroes([500]u8);
var dropdown_val: usize = 1;
var show_dialog: bool = false;
var scale_val: f32 = 1.0;
var line_height_factor: f32 = 1.0;
var animating_window_show: bool = false;
var animating_window_closing: bool = false;
var animating_window_rect = Rect{ .x = 300, .y = 200, .w = 300, .h = 200 };

var progress_mutex = std.Thread.Mutex{};
var progress_val: f32 = 0.0;

const IconBrowser = struct {
    var show: bool = false;
    var rect = Rect{};
    var row_height: f32 = 0;
};

const AnimatingDialog = struct {
    pub fn dialogDisplay(id: u32) !void {
        const modal = dvui.dataGet(null, id, "_modal", bool) orelse unreachable;
        const title = dvui.dataGetSlice(null, id, "_title", []const u8) orelse unreachable;
        const message = dvui.dataGetSlice(null, id, "_message", []const u8) orelse unreachable;
        const callafter = dvui.dataGet(null, id, "_callafter", DialogCallAfterFn);

        // once we record a response, refresh it until we close
        _ = dvui.dataGet(null, id, "response", enums.DialogResponse);

        var win = FloatingWindowWidget.init(@src(), .{ .modal = modal }, .{ .id_extra = id });
        const first_frame = dvui.firstFrame(win.data().id);

        // On the first frame the window size will be 0 so you won't see
        // anything, but we need the scaleval to be 1 so the window will
        // calculate its min_size correctly.
        var scaleval: f32 = 1.0;

        // To animate a window, we need both a percent and a target window
        // size (see calls to animate below).
        if (dvui.animationGet(win.data().id, "rect_percent")) |a| {
            if (dvui.dataGet(null, win.data().id, "window_size", Size)) |target_size| {
                scaleval = a.lerp();

                // since the window is animating, calculate the center to
                // animate around that
                var r = win.data().rect;
                r.x += r.w / 2;
                r.y += r.h / 2;

                const dw = target_size.w * scaleval;
                const dh = target_size.h * scaleval;
                r.x -= dw / 2;
                r.w = dw;
                r.y -= dh / 2;
                r.h = dh;

                win.data().rect = r;

                if (a.done() and a.end_val == 0) {
                    win.close();
                    dvui.dialogRemove(id);

                    if (callafter) |ca| {
                        const response = dvui.dataGet(null, id, "response", enums.DialogResponse) orelse {
                            std.debug.print("Error: no response for dialog {x}\n", .{id});
                            return;
                        };
                        try ca(id, response);
                    }

                    return;
                }
            }
        }

        try win.install();
        win.processEventsBefore();
        try win.drawBackground();

        var scaler = try dvui.scale(@src(), scaleval, .{ .expand = .horizontal });

        var vbox = try dvui.box(@src(), .vertical, .{ .expand = .horizontal });

        var closing: bool = false;

        var header_openflag = true;
        try dvui.windowHeader(title, "", &header_openflag);
        if (!header_openflag) {
            closing = true;
            dvui.dataSet(null, id, "response", enums.DialogResponse.closed);
        }

        var tl = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false });
        try tl.addText(message, .{});
        tl.deinit();

        if (try dvui.button(@src(), "Ok", .{ .gravity_x = 0.5, .gravity_y = 0.5, .tab_index = 1 })) {
            closing = true;
            dvui.dataSet(null, id, "response", enums.DialogResponse.ok);
        }

        vbox.deinit();
        scaler.deinit();
        win.deinit();

        if (first_frame) {
            // On the first frame, scaler will have a scale value of 1 so
            // the min size of the window is our target, which is why we do
            // this after win.deinit so the min size will be available
            dvui.animation(win.wd.id, "rect_percent", .{ .start_val = 0, .end_val = 1.0, .end_time = 300_000 });
            dvui.dataSet(null, win.data().id, "window_size", win.data().min_size);
        }

        if (closing) {
            // If we are closing, start from our current size
            dvui.animation(win.wd.id, "rect_percent", .{ .start_val = 1.0, .end_val = 0, .end_time = 300_000 });
            dvui.dataSet(null, win.data().id, "window_size", win.data().rect.size());
        }
    }

    pub fn after(id: u32, response: enums.DialogResponse) Error!void {
        _ = id;
        std.debug.print("You clicked \"{s}\"\n", .{@tagName(response)});
    }
};

pub fn animatingWindowRect(src: std.builtin.SourceLocation, rect: *Rect, show_flag: *bool, closing: *bool, opts: Options) FloatingWindowWidget {
    const fwin_id = dvui.parentGet().extendId(src, opts.idExtra());

    if (dvui.firstFrame(fwin_id)) {
        dvui.animation(fwin_id, "rect_percent", .{ .start_val = 0, .end_val = 1.0, .start_time = 0, .end_time = 300_000 });
        dvui.dataSet(null, fwin_id, "size", rect.*.size());
    }

    if (closing.*) {
        closing.* = false;
        dvui.animation(fwin_id, "rect_percent", .{ .start_val = 1.0, .end_val = 0, .start_time = 0, .end_time = 300_000 });
        dvui.dataSet(null, fwin_id, "size", rect.*.size());
    }

    var fwin: FloatingWindowWidget = undefined;

    if (dvui.animationGet(fwin_id, "rect_percent")) |a| {
        if (dvui.dataGet(null, fwin_id, "size", Size)) |ss| {
            var r = rect.*;
            const dw = ss.w * a.lerp();
            const dh = ss.h * a.lerp();
            r.x = r.x + (r.w / 2) - (dw / 2);
            r.w = dw;
            r.y = r.y + (r.h / 2) - (dh / 2);
            r.h = dh;

            // don't pass rect so our animating rect doesn't get saved back
            fwin = FloatingWindowWidget.init(src, .{ .open_flag = show_flag }, opts.override(.{ .rect = r }));

            if (a.done() and r.empty()) {
                // done with closing animation
                fwin.close();
            }
        }
    } else {
        fwin = FloatingWindowWidget.init(src, .{ .rect = rect, .open_flag = show_flag }, opts);
    }

    return fwin;
}

pub fn demo() !void {
    if (!show_demo_window) {
        return;
    }

    var float = try dvui.floatingWindow(@src(), .{ .open_flag = &show_demo_window }, .{ .min_size_content = .{ .w = 440, .h = 400 } });
    defer float.deinit();

    // pad the fps label so that it doesn't trigger refresh when the number
    // changes widths
    var buf: [100]u8 = undefined;
    const fps_str = std.fmt.bufPrint(&buf, "{d:0>4.0} fps", .{dvui.FPS()}) catch unreachable;
    try dvui.windowHeader("DVUI Demo", fps_str, &show_demo_window);

    var ti = dvui.toastsFor(float.data().id);
    if (ti) |*it| {
        var toast_win = FloatingWindowWidget.init(@src(), .{ .stay_above_parent = true, .process_events_in_deinit = false }, .{ .background = false, .border = .{} });
        defer toast_win.deinit();

        toast_win.data().rect = dvui.placeIn(float.data().rect, toast_win.data().rect.size(), .none, .{ .x = 0.5, .y = 0.7 });
        toast_win.autoSize();
        try toast_win.install();
        try toast_win.drawBackground();

        var vbox = try dvui.box(@src(), .vertical, .{});
        defer vbox.deinit();

        while (it.next()) |t| {
            try t.display(t.id);
        }
    }

    var scroll = try dvui.scrollArea(@src(), .{}, .{ .expand = .both, .background = false });
    defer scroll.deinit();

    var scaler = try dvui.scale(@src(), scale_val, .{ .expand = .horizontal });
    defer scaler.deinit();

    var vbox = try dvui.box(@src(), .vertical, .{ .expand = .horizontal });
    defer vbox.deinit();

    if (try dvui.button(@src(), "Toggle Debug Window", .{})) {
        dvui.toggleDebugWindow();
    }

    if (try dvui.expander(@src(), "Basic Widgets", .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        try basicWidgets();
    }

    if (try dvui.expander(@src(), "Text Entry", .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        try textEntryWidgets();
    }

    if (try dvui.expander(@src(), "Styling", .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        try styling();
    }

    if (try dvui.expander(@src(), "Layout", .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        try layout();
    }

    if (try dvui.expander(@src(), "Text Layout", .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        try layoutText();
    }

    if (try dvui.expander(@src(), "Menus", .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        try menus();
    }

    if (try dvui.expander(@src(), "Dialogs and Toasts", .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        try dialogs(float.data().id);
    }

    if (try dvui.expander(@src(), "Animations", .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        try animations();
    }

    if (try dvui.button(@src(), "Toggle Theme", .{})) {
        if (dvui.themeGet() == &Adwaita.light) {
            dvui.themeSet(&Adwaita.dark);
        } else {
            dvui.themeSet(&Adwaita.light);
        }
    }

    if (try dvui.button(@src(), "Zoom In", .{})) {
        scale_val = @round(dvui.themeGet().font_body.size * scale_val + 1.0) / dvui.themeGet().font_body.size;

        //std.debug.print("scale {d} {d}\n", .{ scale_val, scale_val * dvui.themeGet().font_body.size });
    }

    if (try dvui.button(@src(), "Zoom Out", .{})) {
        scale_val = @round(dvui.themeGet().font_body.size * scale_val - 1.0) / dvui.themeGet().font_body.size;

        //std.debug.print("scale {d} {d}\n", .{ scale_val, scale_val * dvui.themeGet().font_body.size });
    }

    try dvui.checkbox(@src(), &dvui.currentWindow().snap_to_pixels, "Snap to Pixels (see window title)", .{});

    if (try dvui.expander(@src(), "Show Font Atlases", .{ .expand = .horizontal })) {
        try dvui.debugFontAtlases(@src(), .{});
    }

    if (show_dialog) {
        try dialogDirect();
    }

    if (IconBrowser.show) {
        try icon_browser();
    }
}

pub fn basicWidgets() !void {
    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.label(@src(), "Label", .{}, .{ .gravity_y = 0.5 });
        try dvui.label(@src(), "Multi-line\nLabel", .{}, .{ .gravity_x = 0.5, .gravity_y = 0.5 });
        _ = try dvui.button(@src(), "Button", .{ .gravity_y = 0.5 });
        _ = try dvui.button(@src(), "Multi-line\nButton", .{});
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.label(@src(), "Link:", .{}, .{ .gravity_y = 0.5 });

        if (try dvui.labelClick(@src(), "https://github.com/david-vanderson/dvui", .{}, .{ .gravity_y = 0.5, .color_text = .{ .r = 0x35, .g = 0x84, .b = 0xe4 } })) {
            try dvui.openURL("https://github.com/david-vanderson/dvui");
        }
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .horizontal, .min_size_content = .{ .h = 40 } });
        defer hbox.deinit();

        try dvui.label(@src(), "Sliders", .{}, .{ .gravity_y = 0.5 });
        _ = try dvui.slider(@src(), .horizontal, &slider_val, .{ .expand = .horizontal, .gravity_y = 0.5, .corner_radius = dvui.Rect.all(100) });
        _ = try dvui.slider(@src(), .vertical, &slider_val, .{ .expand = .vertical, .min_size_content = .{ .w = 10 }, .corner_radius = dvui.Rect.all(100) });
        try dvui.label(@src(), "Value: {d:2.2}", .{slider_val}, .{ .gravity_y = 0.5 });
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .horizontal, .min_size_content = .{ .h = 40 } });
        defer hbox.deinit();

        try dvui.label(@src(), "Slider Entry", .{}, .{ .gravity_y = 0.5 });
        _ = try dvui.sliderEntry(@src(), "R: {d:0.2}", &slider_val, .{ .gravity_y = 0.5 });
    }

    try dvui.checkbox(@src(), &checkbox_bool, "Checkbox", .{});

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.label(@src(), "Text Entry", .{}, .{ .gravity_y = 0.5 });
        var te = try dvui.textEntry(@src(), .{ .text = &text_entry_buf }, .{});
        te.deinit();
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.label(@src(), "Dropdown", .{}, .{ .gravity_y = 0.5 });

        const entries = [_][]const u8{ "First", "Second", "Third is a really long one that doesn't fit" };

        _ = try dvui.dropdown(@src(), &entries, &dropdown_val, .{ .min_size_content = .{ .w = 120 } });
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.label(@src(), "Icons", .{}, .{ .gravity_y = 0.5 });

        const icon_opts = dvui.Options{ .gravity_y = 0.5, .min_size_content = .{ .h = 12 + icon_image_size_extra }, .rotation = icon_image_rotation };
        try dvui.icon(@src(), "cycle", entypo.cycle, icon_opts);
        try dvui.icon(@src(), "aircraft", entypo.aircraft, icon_opts);
        try dvui.icon(@src(), "notes", entypo.beamed_note, icon_opts);

        if (try dvui.button(@src(), "Icon Browser", .{ .gravity_y = 0.5 })) {
            IconBrowser.show = true;
        }
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.label(@src(), "Raster Images", .{}, .{ .gravity_y = 0.5 });

        const imgsize = try dvui.imageSize("zig favicon", zig_favicon);
        try dvui.image(@src(), "zig favicon", zig_favicon, .{
            .gravity_y = 0.5,
            .min_size_content = .{ .w = imgsize.w + icon_image_size_extra, .h = imgsize.h + icon_image_size_extra },
            .rotation = icon_image_rotation,
        });
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.label(@src(), "Resize Rotate Icons/Images", .{}, .{ .gravity_y = 0.5 });

        if (try dvui.buttonIcon(@src(), "plus", entypo.plus, .{ .gravity_y = 0.5 })) {
            icon_image_size_extra += 1;
        }

        if (try dvui.buttonIcon(@src(), "minus", entypo.minus, .{ .gravity_y = 0.5 })) {
            icon_image_size_extra = @max(0, icon_image_size_extra - 1);
        }

        if (try dvui.buttonIcon(@src(), "cc", entypo.cc, .{ .gravity_y = 0.5 })) {
            icon_image_rotation = icon_image_rotation + 5 * std.math.pi / 180.0;
        }

        if (try dvui.buttonIcon(@src(), "ccw", entypo.ccw, .{ .gravity_y = 0.5 })) {
            icon_image_rotation = icon_image_rotation - 5 * std.math.pi / 180.0;
        }
    }
}

pub fn textEntryWidgets() !void {
    var left_alignment = dvui.Alignment.init();
    defer left_alignment.deinit();
    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.label(@src(), "Singleline", .{}, .{ .gravity_y = 0.5 });

        var te = dvui.TextEntryWidget.init(@src(), .{ .text = &text_entry_buf }, .{ .margin = dvui.TextEntryWidget.defaults.marginGet().add(left_alignment.margin(hbox.data().id)) });
        left_alignment.record(hbox.data().id, te.data());

        const teid = te.data().id;
        try te.install();

        var enter_pressed = false;
        for (dvui.events()) |*e| {
            if (!te.matchEvent(e))
                continue;

            if (e.evt == .key and e.evt.key.code == .enter and e.evt.key.action == .down) {
                e.handled = true;
                enter_pressed = true;
            }

            if (!e.handled) {
                te.processEvent(e, false);
            }
        }

        try te.draw();
        te.deinit();

        try dvui.label(@src(), "(press enter)", .{}, .{ .gravity_y = 0.5 });

        if (enter_pressed) {
            dvui.animation(teid, "enter_pressed", .{ .start_val = 1.0, .end_val = 0, .start_time = 0, .end_time = 500_000 });
        }

        if (dvui.animationGet(teid, "enter_pressed")) |a| {
            const prev_alpha = dvui.themeGet().alpha;
            dvui.themeGet().alpha *= a.lerp();
            try dvui.label(@src(), "Enter!", .{}, .{ .gravity_y = 0.5 });
            dvui.themeGet().alpha = prev_alpha;
        }
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.label(@src(), "Password", .{}, .{ .gravity_y = 0.5 });

        var te = try dvui.textEntry(@src(), .{
            .text = &text_entry_password_buf,
            .password_char = if (text_entry_password_buf_obf_enable) "*" else null,
        }, .{ .margin = dvui.TextEntryWidget.defaults.marginGet().add(left_alignment.margin(hbox.data().id)) });

        left_alignment.record(hbox.data().id, te.data());

        te.deinit();

        if (try dvui.buttonIcon(
            @src(),
            "toggle",
            if (text_entry_password_buf_obf_enable) entypo.eye_with_line else entypo.eye,
            .{ .gravity_y = 0.5, .min_size_content = .{ .h = 12 } },
        )) {
            text_entry_password_buf_obf_enable = !text_entry_password_buf_obf_enable;
        }
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        var buf = dvui.dataGetSlice(null, hbox.wd.id, "buffer", []u8) orelse blk: {
            dvui.dataSetSlice(null, hbox.wd.id, "buffer", &[_]u8{0} ** 30);
            break :blk dvui.dataGetSlice(null, hbox.wd.id, "buffer", []u8).?;
        };
        var filter_buf = dvui.dataGetSlice(null, hbox.wd.id, "filter_buffer", []u8) orelse blk: {
            dvui.dataSetSlice(null, hbox.wd.id, "filter_buffer", &[_]u8{0} ** 30);
            break :blk dvui.dataGetSlice(null, hbox.wd.id, "filter_buffer", []u8).?;
        };

        try dvui.label(@src(), "Filtered", .{}, .{ .gravity_y = 0.5 });
        var te = dvui.TextEntryWidget.init(@src(), .{ .text = buf }, .{ .margin = dvui.TextEntryWidget.defaults.marginGet().add(left_alignment.margin(hbox.data().id)) });
        left_alignment.record(hbox.data().id, te.data());

        try te.install();
        te.processEvents();

        // filter before drawing
        for (std.mem.sliceTo(filter_buf, 0), 0..) |_, i| {
            te.filterOut(filter_buf[i..][0..1]);
        }

        try te.draw();
        te.deinit();

        try dvui.label(@src(), "Filter", .{}, .{ .gravity_y = 0.5 });
        var te2 = try dvui.textEntry(@src(), .{
            .text = filter_buf,
        }, .{});
        te2.deinit();
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.label(@src(), "Multiline", .{}, .{ .gravity_y = 0.5 });
        var te = try dvui.textEntry(@src(), .{ .text = &text_entry_multiline_buf, .multiline = true }, .{ .min_size_content = .{ .w = 150, .h = 80 }, .margin = dvui.TextEntryWidget.defaults.marginGet().add(left_alignment.margin(hbox.data().id)) });
        left_alignment.record(hbox.data().id, te.data());
        te.deinit();
    }
}

pub fn styling() !void {
    try dvui.label(@src(), "color style:", .{}, .{});
    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        _ = try dvui.button(@src(), "Accent", .{ .color_style = .accent });
        _ = try dvui.button(@src(), "Success", .{ .color_style = .success });
        _ = try dvui.button(@src(), "Error", .{ .color_style = .err });
        _ = try dvui.button(@src(), "Window", .{ .color_style = .window });
        _ = try dvui.button(@src(), "Content", .{ .color_style = .content });
        _ = try dvui.button(@src(), "Control", .{ .color_style = .control });
    }

    try dvui.label(@src(), "margin/border/padding:", .{}, .{});
    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        const opts: Options = .{ .color_style = .content, .border = Rect.all(1), .background = true, .gravity_y = 0.5 };

        var o = try dvui.overlay(@src(), opts);
        _ = try dvui.button(@src(), "default", .{});
        o.deinit();

        o = try dvui.overlay(@src(), opts);
        _ = try dvui.button(@src(), "+border", .{ .border = Rect.all(2) });
        o.deinit();

        o = try dvui.overlay(@src(), opts);
        _ = try dvui.button(@src(), "+padding 10", .{ .border = Rect.all(2), .padding = Rect.all(10) });
        o.deinit();

        o = try dvui.overlay(@src(), opts);
        _ = try dvui.button(@src(), "+margin 10", .{ .border = Rect.all(2), .margin = Rect.all(10), .padding = Rect.all(10) });
        o.deinit();
    }

    try dvui.label(@src(), "corner radius:", .{}, .{});
    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        const opts: Options = .{ .border = Rect.all(1), .background = true, .min_size_content = .{ .w = 20 } };

        _ = try dvui.button(@src(), "0", opts.override(.{ .corner_radius = Rect.all(0) }));
        _ = try dvui.button(@src(), "2", opts.override(.{ .corner_radius = Rect.all(2) }));
        _ = try dvui.button(@src(), "7", opts.override(.{ .corner_radius = Rect.all(7) }));
        _ = try dvui.button(@src(), "100", opts.override(.{ .corner_radius = Rect.all(100) }));
        _ = try dvui.button(@src(), "mixed", opts.override(.{ .corner_radius = .{ .x = 0, .y = 2, .w = 7, .h = 100 } }));
    }
}

pub fn layout() !void {
    const opts: Options = .{ .color_style = .content, .border = Rect.all(1), .background = true, .min_size_content = .{ .w = 200, .h = 140 } };

    try dvui.label(@src(), "Gravity", .{}, .{});
    {
        var o = try dvui.overlay(@src(), opts);
        defer o.deinit();

        var buf: [128]u8 = undefined;

        inline for ([3]f32{ 0.0, 0.5, 1.0 }, 0..) |horz, hi| {
            inline for ([3]f32{ 0.0, 0.5, 1.0 }, 0..) |vert, vi| {
                _ = try dvui.button(@src(), try std.fmt.bufPrint(&buf, "{d},{d}", .{ horz, vert }), .{ .id_extra = hi * 3 + vi, .gravity_x = horz, .gravity_y = vert });
            }
        }
    }

    try dvui.label(@src(), "Expand", .{}, .{});
    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();
        {
            var vbox = try dvui.box(@src(), .vertical, opts);
            defer vbox.deinit();

            _ = try dvui.button(@src(), "none", .{ .expand = .none });
            _ = try dvui.button(@src(), "horizontal", .{ .expand = .horizontal });
            _ = try dvui.button(@src(), "vertical", .{ .expand = .vertical });
        }
        {
            var vbox = try dvui.box(@src(), .vertical, opts);
            defer vbox.deinit();

            _ = try dvui.button(@src(), "both", .{ .expand = .both });
        }
    }

    try dvui.label(@src(), "Boxes", .{}, .{});
    {
        const grav: Options = .{ .gravity_x = 0.5, .gravity_y = 0.5 };

        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();
        {
            var hbox2 = try dvui.box(@src(), .horizontal, .{ .min_size_content = .{ .w = 200, .h = 140 } });
            defer hbox2.deinit();
            {
                var vbox = try dvui.box(@src(), .vertical, opts.override(.{ .expand = .both, .min_size_content = .{} }));
                defer vbox.deinit();

                _ = try dvui.button(@src(), "vertical", grav);
                _ = try dvui.button(@src(), "expand", grav.override(.{ .expand = .vertical }));
                _ = try dvui.button(@src(), "a", grav);
            }

            {
                var vbox = try dvui.boxEqual(@src(), .vertical, opts.override(.{ .expand = .both, .min_size_content = .{} }));
                defer vbox.deinit();

                _ = try dvui.button(@src(), "vert equal", grav);
                _ = try dvui.button(@src(), "expand", grav.override(.{ .expand = .vertical }));
                _ = try dvui.button(@src(), "a", grav);
            }
        }

        {
            var vbox2 = try dvui.box(@src(), .vertical, .{ .min_size_content = .{ .w = 200, .h = 140 } });
            defer vbox2.deinit();
            {
                var hbox2 = try dvui.box(@src(), .horizontal, opts.override(.{ .expand = .both, .min_size_content = .{} }));
                defer hbox2.deinit();

                _ = try dvui.button(@src(), "horizontal", grav);
                _ = try dvui.button(@src(), "expand", grav.override(.{ .expand = .horizontal }));
                _ = try dvui.button(@src(), "a", grav);
            }

            {
                var hbox2 = try dvui.boxEqual(@src(), .horizontal, opts.override(.{ .expand = .both, .min_size_content = .{} }));
                defer hbox2.deinit();

                _ = try dvui.button(@src(), "horz\nequal", grav);
                _ = try dvui.button(@src(), "expand", grav.override(.{ .expand = .horizontal }));
                _ = try dvui.button(@src(), "a", grav);
            }
        }
    }

    try dvui.label(@src(), "Collapsible Pane with Draggable Sash", .{}, .{});
    {
        const collapse_width: f32 = 400;
        var paned = try dvui.paned(@src(), .horizontal, collapse_width, .{ .expand = .both, .background = false, .min_size_content = .{ .h = 100 } });
        defer paned.deinit();
        const collapsed = paned.collapsed();

        {
            var vbox = try dvui.box(@src(), .vertical, .{ .expand = .both, .background = true });
            defer vbox.deinit();

            try dvui.label(@src(), "Left Side", .{}, .{});
            try dvui.label(@src(), "collapses when width < {d}", .{collapse_width}, .{});
            try dvui.label(@src(), "current width {d}", .{paned.wd.rect.w}, .{});
            if (collapsed and try dvui.button(@src(), "Goto Right", .{})) {
                paned.animateSplit(0.0);
            }
        }

        {
            var vbox = try dvui.box(@src(), .vertical, .{ .expand = .both, .background = true });
            defer vbox.deinit();

            try dvui.label(@src(), "Right Side", .{}, .{});
            if (collapsed and try dvui.button(@src(), "Goto Left", .{})) {
                paned.animateSplit(1.0);
            }
        }
    }
}

pub fn layoutText() !void {
    try dvui.label(@src(), "Title", .{}, .{ .font_style = .title });
    try dvui.label(@src(), "Title-1", .{}, .{ .font_style = .title_1 });
    try dvui.label(@src(), "Title-2", .{}, .{ .font_style = .title_2 });
    try dvui.label(@src(), "Title-3", .{}, .{ .font_style = .title_3 });
    try dvui.label(@src(), "Title-4", .{}, .{ .font_style = .title_4 });
    try dvui.label(@src(), "Heading", .{}, .{ .font_style = .heading });
    try dvui.label(@src(), "Caption-Heading", .{}, .{ .font_style = .caption_heading });
    try dvui.label(@src(), "Caption", .{}, .{ .font_style = .caption });
    try dvui.label(@src(), "Body", .{}, .{});

    {
        var tl = TextLayoutWidget.init(@src(), .{}, .{ .expand = .horizontal });
        try tl.install();
        defer tl.deinit();

        var cbox = try dvui.box(@src(), .vertical, .{ .padding = .{ .w = 4 } });
        if (try dvui.buttonIcon(@src(), "play", entypo.controller_play, .{ .padding = Rect.all(6), .min_size_content = .{ .h = 18 } })) {
            try dvui.dialog(@src(), .{ .modal = false, .title = "Ok Dialog", .message = "You clicked play" });
        }
        if (try dvui.buttonIcon(@src(), "more", entypo.dots_three_vertical, .{ .padding = Rect.all(6), .min_size_content = .{ .h = 18 } })) {
            try dvui.dialog(@src(), .{ .modal = false, .title = "Ok Dialog", .message = "You clicked more" });
        }
        cbox.deinit();

        tl.processEvents();

        const start = "Notice that the text in this box is wrapping around the buttons in the corners.\n";
        try tl.addText(start, .{ .font_style = .title_4 });

        const lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.";
        try tl.addText(lorem, .{ .font = dvui.themeGet().font_body.lineHeightFactor(line_height_factor) });
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.label(@src(), "line height factor: {d:0.2}", .{line_height_factor}, .{ .gravity_y = 0.5 });

        if (try dvui.button(@src(), "inc", .{})) {
            line_height_factor += 0.1;
            line_height_factor = @min(10, line_height_factor);
        }

        if (try dvui.button(@src(), "dec", .{})) {
            line_height_factor -= 0.1;
            line_height_factor = @max(0.1, line_height_factor);
        }
    }
}

pub fn menus() !void {
    const ctext = try dvui.context(@src(), .{ .expand = .horizontal });
    defer ctext.deinit();

    if (ctext.activePoint()) |cp| {
        var fw2 = try dvui.popup(@src(), Rect.fromPoint(cp), .{});
        defer fw2.deinit();

        _ = try dvui.menuItemLabel(@src(), "Cut", .{}, .{ .expand = .horizontal });
        if ((try dvui.menuItemLabel(@src(), "Close", .{}, .{ .expand = .horizontal })) != null) {
            dvui.menuGet().?.close();
        }
        _ = try dvui.menuItemLabel(@src(), "Paste", .{}, .{ .expand = .horizontal });
    }

    var vbox = try dvui.box(@src(), .vertical, .{});
    defer vbox.deinit();

    {
        var m = try dvui.menu(@src(), .horizontal, .{});
        defer m.deinit();

        if (try dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{ .expand = .horizontal })) |r| {
            var fw = try dvui.popup(@src(), Rect.fromPoint(Point{ .x = r.x, .y = r.y + r.h }), .{});
            defer fw.deinit();

            try submenus();

            if (try dvui.menuItemLabel(@src(), "Close", .{}, .{ .expand = .horizontal }) != null) {
                dvui.menuGet().?.close();
            }

            try dvui.checkbox(@src(), &checkbox_bool, "Checkbox", .{});

            if (try dvui.menuItemLabel(@src(), "Dialog", .{}, .{ .expand = .horizontal }) != null) {
                dvui.menuGet().?.close();
                show_dialog = true;
            }
        }

        if (try dvui.menuItemLabel(@src(), "Edit", .{ .submenu = true }, .{ .expand = .horizontal })) |r| {
            var fw = try dvui.popup(@src(), Rect.fromPoint(Point{ .x = r.x, .y = r.y + r.h }), .{});
            defer fw.deinit();
            _ = try dvui.menuItemLabel(@src(), "Cut", .{}, .{ .expand = .horizontal });
            _ = try dvui.menuItemLabel(@src(), "Copy", .{}, .{ .expand = .horizontal });
            _ = try dvui.menuItemLabel(@src(), "Paste", .{}, .{ .expand = .horizontal });
        }
    }

    try dvui.labelNoFmt(@src(), "Right click for a context menu", .{});
}

pub fn submenus() !void {
    if (try dvui.menuItemLabel(@src(), "Submenu...", .{ .submenu = true }, .{ .expand = .horizontal })) |r| {
        var menu_rect = r;
        menu_rect.x += menu_rect.w;
        var fw2 = try dvui.popup(@src(), menu_rect, .{});
        defer fw2.deinit();

        try submenus();

        if (try dvui.menuItemLabel(@src(), "Close", .{}, .{ .expand = .horizontal }) != null) {
            dvui.menuGet().?.close();
        }

        if (try dvui.menuItemLabel(@src(), "Dialog", .{}, .{ .expand = .horizontal }) != null) {
            dvui.menuGet().?.close();
            show_dialog = true;
        }
    }
}

pub fn dialogs(demo_win_id: u32) !void {
    if (try dvui.button(@src(), "Direct Dialog", .{})) {
        show_dialog = true;
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        if (try dvui.button(@src(), "Ok Dialog", .{})) {
            try dvui.dialog(@src(), .{ .modal = false, .title = "Ok Dialog", .message = "This is a non modal dialog with no callafter" });
        }

        const dialogsFollowup = struct {
            fn callafter(id: u32, response: enums.DialogResponse) Error!void {
                _ = id;
                var buf: [100]u8 = undefined;
                const text = std.fmt.bufPrint(&buf, "You clicked \"{s}\"", .{@tagName(response)}) catch unreachable;
                try dvui.dialog(@src(), .{ .title = "Ok Followup Response", .message = text });
            }
        };

        if (try dvui.button(@src(), "Ok Followup", .{})) {
            try dvui.dialog(@src(), .{ .title = "Ok Followup", .message = "This is a modal dialog with modal followup", .callafterFn = dialogsFollowup.callafter });
        }
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        if (try dvui.button(@src(), "Toast 1", .{})) {
            try dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Toast 1 to demo window" });
        }

        if (try dvui.button(@src(), "Toast 2", .{})) {
            try dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Toast 2 to demo window" });
        }

        if (try dvui.button(@src(), "Toast 3", .{})) {
            try dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Toast 3 to demo window" });
        }

        if (try dvui.button(@src(), "Toast Main Window", .{})) {
            try dvui.toast(@src(), .{ .message = "Toast to main window" });
        }
    }

    try dvui.label(@src(), "Example of how to show a dialog/toast from another thread", .{}, .{});
    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        if (try dvui.button(@src(), "Dialog after 1 second", .{})) {
            const bg_thread = try std.Thread.spawn(.{}, background_dialog, .{ dvui.currentWindow(), 1_000_000_000 });
            bg_thread.detach();
        }

        if (try dvui.button(@src(), "Toast after 1 second", .{})) {
            const bg_thread = try std.Thread.spawn(.{}, background_toast, .{ dvui.currentWindow(), 1_000_000_000, demo_win_id });
            bg_thread.detach();
        }
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
        defer hbox.deinit();

        if (try dvui.button(@src(), "Show Progress from another Thread", .{})) {
            progress_mutex.lock();
            progress_val = 0;
            progress_mutex.unlock();
            const bg_thread = try std.Thread.spawn(.{}, background_progress, .{ dvui.currentWindow(), 2_000_000_000 });
            bg_thread.detach();
        }

        try dvui.progress(@src(), .{ .percent = progress_val }, .{ .expand = .horizontal, .gravity_y = 0.5, .corner_radius = dvui.Rect.all(100) });
    }
}

pub fn animations() !void {
    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        _ = dvui.spacer(@src(), .{ .w = 20 }, .{});
        var button_wiggle = ButtonWidget.init(@src(), .{}, .{ .tab_index = 10 });
        defer button_wiggle.deinit();

        if (dvui.animationGet(button_wiggle.data().id, "xoffset")) |a| {
            button_wiggle.data().rect.x += 20 * (1.0 - a.lerp()) * (1.0 - a.lerp()) * @sin(a.lerp() * std.math.pi * 50);
        }

        try button_wiggle.install();
        button_wiggle.processEvents();
        try dvui.labelNoFmt(@src(), "Wiggle", button_wiggle.data().options.strip().override(.{ .gravity_x = 0.5, .gravity_y = 0.5 }));
        try button_wiggle.drawFocus();

        if (button_wiggle.clicked()) {
            dvui.animation(button_wiggle.data().id, "xoffset", .{ .start_val = 0, .end_val = 1.0, .start_time = 0, .end_time = 500_000 });
        }
    }

    if (try dvui.button(@src(), "Animating Dialog (Scale)", .{})) {
        try dvui.dialog(@src(), .{ .modal = false, .title = "Animating Dialog (Scale)", .message = "This shows how to animate dialogs and other floating windows by changing the scale", .displayFn = AnimatingDialog.dialogDisplay, .callafterFn = AnimatingDialog.after });
    }

    if (try dvui.button(@src(), "Animating Window (Rect)", .{})) {
        if (animating_window_show) {
            animating_window_closing = true;
        } else {
            animating_window_show = true;
            animating_window_closing = false;
        }
    }

    if (animating_window_show) {
        var win = animatingWindowRect(@src(), &animating_window_rect, &animating_window_show, &animating_window_closing, .{});
        try win.install();
        win.processEventsBefore();
        try win.drawBackground();
        defer win.deinit();

        var keep_open = true;
        try dvui.windowHeader("Animating Window (Rect)", "", &keep_open);
        if (!keep_open) {
            animating_window_closing = true;
        }

        var tl = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
        try tl.addText("This shows how to animate dialogs and other floating windows by changing the rect", .{});
        tl.deinit();
    }

    if (try dvui.expander(@src(), "Spinner", .{ .expand = .horizontal })) {
        try dvui.labelNoFmt(@src(), "Spinner maxes out frame rate", .{});
        try dvui.spinner(@src(), .{ .color_text = .{ .r = 100, .g = 200, .b = 100 } });
    }

    if (try dvui.expander(@src(), "Clock", .{ .expand = .horizontal })) {
        try dvui.labelNoFmt(@src(), "Schedules a frame at the beginning of each second", .{});

        const millis = @divFloor(dvui.frameTimeNS(), 1_000_000);
        const left = @as(i32, @intCast(@rem(millis, 1000)));

        var mslabel = try dvui.LabelWidget.init(@src(), "{d:0>3} ms into second", .{@as(u32, @intCast(left))}, .{});
        try mslabel.install();
        mslabel.processEvents();
        try mslabel.draw();
        mslabel.deinit();

        try dvui.label(@src(), "Estimate of frame overhead {d:6} us", .{dvui.currentWindow().loop_target_slop}, .{});

        if (dvui.timerDone(mslabel.wd.id) or !dvui.timerExists(mslabel.wd.id)) {
            const wait = 1000 * (1000 - left);
            try dvui.timer(mslabel.wd.id, wait);
        }
    }
}

pub fn dialogDirect() !void {
    const data = struct {
        var extra_stuff: bool = false;
    };
    var dialog_win = try dvui.floatingWindow(@src(), .{ .stay_above_parent = true, .modal = false, .open_flag = &show_dialog }, .{});
    defer dialog_win.deinit();

    try dvui.windowHeader("Modal Dialog", "", &show_dialog);
    try dvui.label(@src(), "Asking a Question", .{}, .{ .font_style = .title_4 });
    try dvui.label(@src(), "This dialog is being shown in a direct style, controlled entirely in user code.", .{}, .{});

    if (try dvui.button(@src(), "Toggle extra stuff and fit window", .{})) {
        data.extra_stuff = !data.extra_stuff;
        dialog_win.autoSize();
    }

    if (data.extra_stuff) {
        try dvui.label(@src(), "This is some extra stuff\nwith a multi-line label\nthat has 3 lines", .{}, .{ .background = true });
    }

    {
        _ = dvui.spacer(@src(), .{}, .{ .expand = .vertical });
        var hbox = try dvui.box(@src(), .horizontal, .{ .gravity_x = 1.0 });
        defer hbox.deinit();

        if (try dvui.button(@src(), "Yes", .{})) {
            dialog_win.close(); // can close the dialog this way
        }

        if (try dvui.button(@src(), "No", .{})) {
            show_dialog = false; // can close by not running this code anymore
        }
    }
}

pub fn icon_browser() !void {
    var fwin = try dvui.floatingWindow(@src(), .{ .rect = &IconBrowser.rect, .open_flag = &IconBrowser.show }, .{ .min_size_content = .{ .w = 300, .h = 400 } });
    defer fwin.deinit();
    try dvui.windowHeader("Icon Browser", "", &IconBrowser.show);

    const num_icons = @typeInfo(entypo).Struct.decls.len;
    const height = @as(f32, @floatFromInt(num_icons)) * IconBrowser.row_height;

    // we won't have the height the first frame, so always set it
    var scroll_info: ScrollInfo = .{ .vertical = .given };
    if (dvui.dataGet(null, fwin.wd.id, "scroll_info", ScrollInfo)) |si| {
        scroll_info = si;
        scroll_info.virtual_size.h = height;
    }
    defer dvui.dataSet(null, fwin.wd.id, "scroll_info", scroll_info);

    var scroll = try dvui.scrollArea(@src(), .{ .scroll_info = &scroll_info }, .{ .expand = .both });
    defer scroll.deinit();

    const visibleRect = scroll.si.viewport;
    var cursor: f32 = 0;

    inline for (@typeInfo(entypo).Struct.decls, 0..) |d, i| {
        if (cursor <= (visibleRect.y + visibleRect.h) and (cursor + IconBrowser.row_height) >= visibleRect.y) {
            const r = Rect{ .x = 0, .y = cursor, .w = 0, .h = IconBrowser.row_height };
            var iconbox = try dvui.box(@src(), .horizontal, .{ .id_extra = i, .expand = .horizontal, .rect = r });

            if (try dvui.buttonIcon(@src(), "entypo." ++ d.name, @field(entypo, d.name), .{ .min_size_content = .{ .h = 20 } })) {
                // TODO: copy full buttonIcon code line into clipboard and show toast
            }
            var tl = try dvui.textLayout(@src(), .{ .break_lines = false }, .{});
            try tl.addText("entypo." ++ d.name, .{});
            tl.deinit();

            iconbox.deinit();

            IconBrowser.row_height = iconbox.wd.min_size.h;
        }

        cursor += IconBrowser.row_height;
    }
}

fn background_dialog(win: *dvui.Window, delay_ns: u64) !void {
    std.time.sleep(delay_ns);
    try dvui.dialog(@src(), .{ .window = win, .modal = false, .title = "Background Dialog", .message = "This non modal dialog was added from a non-GUI thread." });
}

fn background_toast(win: *dvui.Window, delay_ns: u64, subwindow_id: ?u32) !void {
    std.time.sleep(delay_ns);
    dvui.refresh(win, @src(), null);
    try dvui.toast(@src(), .{ .window = win, .subwindow_id = subwindow_id, .message = "Toast came from a non-GUI thread" });
}

fn background_progress(win: *dvui.Window, delay_ns: u64) !void {
    const interval: u64 = 10_000_000;
    var total_sleep: u64 = 0;
    while (total_sleep < delay_ns) : (total_sleep += interval) {
        std.time.sleep(interval);
        progress_mutex.lock();
        progress_val = @as(f32, @floatFromInt(total_sleep)) / @as(f32, @floatFromInt(delay_ns));
        progress_mutex.unlock();
        dvui.refresh(win, @src(), null);
    }
}
