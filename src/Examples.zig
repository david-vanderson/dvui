const builtin = @import("builtin");
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
const ButtonWidget = dvui.ButtonWidget;
const FloatingWindowWidget = dvui.FloatingWindowWidget;
const LabelWidget = dvui.LabelWidget;
const TextLayoutWidget = dvui.TextLayoutWidget;

const enums = dvui.enums;

const zig_favicon = @embedFile("zig-favicon.png");

pub var show_demo_window: bool = false;
var checkbox_bool: bool = false;
const RadioChoice = enum(u8) {
    one = 1,
    two,
    _,
};
var radio_choice: RadioChoice = @enumFromInt(0);
var icon_image_size_extra: f32 = 0;
var icon_image_rotation: f32 = 0;
var slider_vector_array = [_]f32{ 0, 1, 2 };
var slider_val: f32 = 0.0;
var slider_entry_val: f32 = 0.05;
var slider_entry_min: bool = true;
var slider_entry_max: bool = true;
var slider_entry_interval: bool = true;
var slider_entry_vector: bool = false;
var text_entry_buf = std.mem.zeroes([30]u8);
var text_entry_password_buf = std.mem.zeroes([30]u8);
var text_entry_password_buf_obf_enable: bool = true;
var text_entry_multiline_allocator_buf: [1000]u8 = undefined;
var text_entry_multiline_fba = std.heap.FixedBufferAllocator.init(&text_entry_multiline_allocator_buf);
var text_entry_multiline_buf: []u8 = &.{};
var text_entry_multiline_initialized = false;
var dropdown_val: usize = 1;
var layout_margin: Rect = Rect.all(4);
var layout_border: Rect = Rect.all(0);
var layout_padding: Rect = Rect.all(4);
var layout_gravity_x: f32 = 0.5;
var layout_gravity_y: f32 = 0.5;
var layout_expand_horizontal: bool = false;
var layout_expand_vertical: bool = false;
var show_dialog: bool = false;
var scale_val: f32 = 1.0;
var line_height_factor: f32 = 1.0;
var backbox_color: dvui.Color = .{};
var hsluv_hsl: dvui.Color.HSLuv = .{ .l = 50 };
var hsluv_rgb: dvui.Color = .{};
var animating_window_show: bool = false;
var animating_window_closing: bool = false;
var animating_window_rect = Rect{ .x = 100, .y = 100, .w = 300, .h = 200 };
var paned_collapsed_width: f32 = 400;

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
        const title = dvui.dataGetSlice(null, id, "_title", []u8) orelse unreachable;
        const message = dvui.dataGetSlice(null, id, "_message", []u8) orelse unreachable;
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
                    dvui.dialogRemove(id);

                    if (callafter) |ca| {
                        const response = dvui.dataGet(null, id, "response", enums.DialogResponse) orelse {
                            std.log.debug("Error: no response for dialog {x}\n", .{id});
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
            dvui.dataSet(null, id, "response", enums.DialogResponse.cancel);
        }

        var tl = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false });
        try tl.addText(message, .{});
        tl.deinit();

        if (try dvui.button(@src(), "Ok", .{}, .{ .gravity_x = 0.5, .gravity_y = 0.5, .tab_index = 1 })) {
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
        std.log.debug("You clicked \"{s}\"\n", .{@tagName(response)});
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
        var toast_win = FloatingWindowWidget.init(@src(), .{ .stay_above_parent_window = true, .process_events_in_deinit = false }, .{ .background = false, .border = .{} });
        defer toast_win.deinit();

        toast_win.data().rect = dvui.placeIn(float.data().rect, toast_win.data().rect.size(), .none, .{ .x = 0.5, .y = 0.7 });
        toast_win.autoSize(.{});
        try toast_win.install();
        try toast_win.drawBackground();

        var vbox = try dvui.box(@src(), .vertical, .{});
        defer vbox.deinit();

        while (it.next()) |t| {
            try t.display(t.id);
        }
    }

    var scaler = try dvui.scale(@src(), scale_val, .{ .expand = .both });
    defer scaler.deinit();

    var scroll = try dvui.scrollArea(@src(), .{}, .{ .expand = .both, .background = false });
    defer scroll.deinit();

    var vbox = try dvui.box(@src(), .vertical, .{ .expand = .horizontal });
    defer vbox.deinit();

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();
        if (try dvui.button(@src(), "Debug Window", .{}, .{})) {
            dvui.toggleDebugWindow();
        }

        try dvui.Theme.picker(@src(), .{});
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        if (try dvui.button(@src(), "Zoom In", .{}, .{})) {
            scale_val = @round(dvui.themeGet().font_body.size * scale_val + 1.0) / dvui.themeGet().font_body.size;
        }

        if (try dvui.button(@src(), "Zoom Out", .{}, .{})) {
            scale_val = @round(dvui.themeGet().font_body.size * scale_val - 1.0) / dvui.themeGet().font_body.size;
        }
    }

    if (try dvui.expander(@src(), "Basic Widgets", .{}, .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        try basicWidgets();
    }

    if (try dvui.expander(@src(), "Text Entry", .{}, .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        try textEntryWidgets();
    }

    if (try dvui.expander(@src(), "Styling", .{}, .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        try styling();
    }

    if (try dvui.expander(@src(), "Layout", .{}, .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        try layout();
    }

    if (try dvui.expander(@src(), "Text Layout", .{}, .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        try layoutText();
    }

    if (try dvui.expander(@src(), "Reorderable Lists", .{}, .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        try reorderLists();
    }

    if (try dvui.expander(@src(), "Menus", .{}, .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        try menus();
    }

    if (try dvui.expander(@src(), "Focus", .{}, .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        try focus();
    }

    if (try dvui.expander(@src(), "Scrolling", .{}, .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        try scrolling();
    }

    if (try dvui.expander(@src(), "Dialogs and Toasts", .{}, .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        try dialogs(float.data().id);
    }

    if (try dvui.expander(@src(), "Animations", .{}, .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        try animations();
    }

    if (try dvui.expander(@src(), "Theme Parsing", .{}, .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        try themeSerialization();
    }

    if (try dvui.expander(@src(), "Struct UI Widget (Experimental)", .{}, .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();

        const Top = struct {
            const TopChild = struct {
                a_dir: dvui.enums.Direction = undefined,
            };

            const init_data = [_]TopChild{ .{ .a_dir = .vertical }, .{ .a_dir = .horizontal } };
            var mut_array = init_data;
            var ptr: TopChild = TopChild{ .a_dir = .horizontal };

            a_u8: u8 = 1,
            a_f32: f32 = 2.0,
            a_i8: i8 = 1,
            a_f64: f64 = 2.0,
            a_bool: bool = false,
            a_ptr: *TopChild = undefined,
            a_struct: TopChild = .{ .a_dir = .vertical },
            a_str: []const u8 = &[_]u8{0} ** 20,
            a_slice: []TopChild = undefined,

            var instance: @This() = .{ .a_slice = &mut_array, .a_ptr = &ptr };
        };

        try dvui.label(@src(), "Show UI elements for all fields of a struct:", .{}, .{});
        {
            try dvui.structEntryAlloc(@src(), dvui.currentWindow().gpa, Top, &Top.instance, .{ .margin = .{ .x = 10 } });
        }

        if (try dvui.expander(@src(), "Edit Current Theme", .{}, .{ .expand = .horizontal })) {
            var b2 = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
            defer b2.deinit();

            const color_field_options = .{ .fields = .{
                .r = .{ .min = 0, .max = 255, .widget_type = .slider },
                .g = .{ .min = 0, .max = 255, .widget_type = .slider },
                .b = .{ .min = 0, .max = 255, .widget_type = .slider },
                .a = .{ .disabled = true },
            } };

            try dvui.structEntryEx(@src(), "dvui.Theme", dvui.Theme, dvui.themeGet(), .{
                .use_expander = false,
                .label_override = "",
                .fields = .{
                    .name = .{ .disabled = true },
                    .dark = .{ .widget_type = .toggle },
                    .style_err = .{ .disabled = true },
                    .style_accent = .{ .disabled = true },
                    .font_body = .{ .disabled = true },
                    .font_heading = .{ .disabled = true },
                    .font_caption = .{ .disabled = true },
                    .font_caption_heading = .{ .disabled = true },
                    .font_title = .{ .disabled = true },
                    .font_title_1 = .{ .disabled = true },
                    .font_title_2 = .{ .disabled = true },
                    .font_title_3 = .{ .disabled = true },
                    .font_title_4 = .{ .disabled = true },
                    .color_accent = color_field_options,
                    .color_err = color_field_options,
                    .color_text = color_field_options,
                    .color_text_press = color_field_options,
                    .color_fill = color_field_options,
                    .color_fill_window = color_field_options,
                    .color_fill_control = color_field_options,
                    .color_fill_hover = color_field_options,
                    .color_fill_press = color_field_options,
                    .color_border = color_field_options,
                },
            });
        }
    }

    if (try dvui.expander(@src(), "Debugging and Errors", .{}, .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        try debuggingErrors();
    }

    if (show_dialog) {
        try dialogDirect();
    }

    if (IconBrowser.show) {
        try icon_browser();
    }
}

pub fn themeSerialization() !void {
    var serialize_box = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
    defer serialize_box.deinit();

    try dvui.labelNoFmt(@src(), "TODO: demonstrate loading a quicktheme here", .{});
}

pub fn basicWidgets() !void {
    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.label(@src(), "Label", .{}, .{ .gravity_y = 0.5 });
        try dvui.label(@src(), "Multi-line\nLabel", .{}, .{ .gravity_x = 0.5, .gravity_y = 0.5 });
        _ = try dvui.button(@src(), "Button", .{}, .{ .gravity_y = 0.5 });
        _ = try dvui.button(@src(), "Multi-line\nButton", .{}, .{});
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.label(@src(), "Link:", .{}, .{ .gravity_y = 0.5 });

        if (try dvui.labelClick(@src(), "https://github.com/david-vanderson/dvui", .{}, .{ .gravity_y = 0.5, .color_text = .{ .color = .{ .r = 0x35, .g = 0x84, .b = 0xe4 } } })) {
            try dvui.openURL("https://github.com/david-vanderson/dvui");
        }

        if (try dvui.labelClick(@src(), "docs", .{}, .{ .gravity_y = 0.5, .margin = .{ .x = 10 }, .color_text = .{ .color = .{ .r = 0x35, .g = 0x84, .b = 0xe4 } } })) {
            try dvui.openURL("https://david-vanderson.github.io/docs");
        }
    }

    _ = try dvui.checkbox(@src(), &checkbox_bool, "Checkbox", .{});

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.label(@src(), "Text Entry", .{}, .{ .gravity_y = 0.5 });
        var te = try dvui.textEntry(@src(), .{}, .{});
        te.deinit();
    }

    inline for (@typeInfo(RadioChoice).Enum.fields, 0..) |field, i| {
        if (try dvui.radio(@src(), radio_choice == @as(RadioChoice, @enumFromInt(field.value)), "Radio " ++ field.name, .{ .id_extra = i })) {
            radio_choice = @enumFromInt(field.value);
        }
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        const entries = [_][]const u8{ "First", "Second", "Third is a really long one that doesn't fit" };

        _ = try dvui.dropdown(@src(), &entries, &dropdown_val, .{ .min_size_content = .{ .w = 100 }, .gravity_y = 0.5 });

        try dropdownAdvanced();
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
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.label(@src(), "Slider Entry", .{}, .{ .gravity_y = 0.5 });
        if (!slider_entry_vector) {
            _ = try dvui.sliderEntry(@src(), "val: {d:0.3}", .{ .value = &slider_entry_val, .min = (if (slider_entry_min) 0 else null), .max = (if (slider_entry_max) 1 else null), .interval = (if (slider_entry_interval) 0.1 else null) }, .{ .gravity_y = 0.5 });
            try dvui.label(@src(), "(enter or ctrl-click)", .{}, .{ .gravity_y = 0.5 });
        } else {
            _ = try dvui.sliderVector(@src(), "{d:0.2}", 3, &slider_vector_array, .{ .min = (if (slider_entry_min) 0 else null), .max = (if (slider_entry_max) 1 else null), .interval = (if (slider_entry_interval) 0.1 else null) }, .{});
        }
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{ .padding = .{ .x = 10 } });
        defer hbox.deinit();

        _ = try dvui.checkbox(@src(), &slider_entry_min, "Min", .{});
        _ = try dvui.checkbox(@src(), &slider_entry_max, "Max", .{});
        _ = try dvui.checkbox(@src(), &slider_entry_interval, "Interval", .{});
        _ = try dvui.checkbox(@src(), &slider_entry_vector, "Vector", .{});
    }

    _ = try dvui.spacer(@src(), .{ .h = 4 }, .{});

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

        try dvui.label(@src(), "Icons", .{}, .{ .gravity_y = 0.5 });

        const icon_opts = dvui.Options{ .gravity_y = 0.5, .min_size_content = .{ .h = 12 + icon_image_size_extra }, .rotation = icon_image_rotation };
        try dvui.icon(@src(), "cycle", entypo.cycle, icon_opts);
        try dvui.icon(@src(), "aircraft", entypo.aircraft, icon_opts);
        try dvui.icon(@src(), "notes", entypo.beamed_note, icon_opts);

        if (try dvui.button(@src(), "Icon Browser", .{}, .{ .gravity_y = 0.5 })) {
            IconBrowser.show = true;
        }
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.label(@src(), "Resize Rotate Icons/Images", .{}, .{ .gravity_y = 0.5 });

        if (try dvui.buttonIcon(@src(), "plus", entypo.plus, .{}, .{ .gravity_y = 0.5 })) {
            icon_image_size_extra += 1;
        }

        if (try dvui.buttonIcon(@src(), "minus", entypo.minus, .{}, .{ .gravity_y = 0.5 })) {
            icon_image_size_extra = @max(0, icon_image_size_extra - 1);
        }

        if (try dvui.buttonIcon(@src(), "cc", entypo.cc, .{}, .{ .gravity_y = 0.5 })) {
            icon_image_rotation = icon_image_rotation + 5 * std.math.pi / 180.0;
        }

        if (try dvui.buttonIcon(@src(), "ccw", entypo.ccw, .{}, .{ .gravity_y = 0.5 })) {
            icon_image_rotation = icon_image_rotation - 5 * std.math.pi / 180.0;
        }
    }
}

pub fn dropdownAdvanced() !void {
    const g = struct {
        var choice: ?usize = null;
    };

    var dd = dvui.DropdownWidget.init(@src(), .{ .selected_index = g.choice }, .{ .min_size_content = .{ .w = 100 } });
    try dd.install();

    // Here's what is shown when the dropdown is not dropped
    {
        var hbox2 = try dvui.box(@src(), .horizontal, .{ .expand = .both });
        try dvui.icon(@src(), "air", entypo.air, .{ .gravity_y = 0.5 });

        var lw: LabelWidget = undefined;
        if (g.choice) |c| {
            lw = try LabelWidget.init(@src(), "Dropdown Choice {d}", .{c}, .{ .gravity_y = 0.5 });
        } else {
            lw = try LabelWidget.init(@src(), "Advanced Dropdown", .{}, .{ .gravity_y = 0.5 });
        }

        try lw.install();
        try lw.draw();
        lw.deinit();
        try dvui.icon(@src(), "dropdown_triangle", entypo.chevron_small_down, .{ .gravity_y = 0.5 });

        hbox2.deinit();
    }

    if (try dd.dropped()) {
        // The dropdown is dropped, now add all the choices
        {
            var mi = try dd.addChoice();
            defer mi.deinit();

            var hbox2 = try dvui.box(@src(), .horizontal, .{ .expand = .both });
            defer hbox2.deinit();

            var opts: Options = if (mi.show_active) dvui.themeGet().style_accent else .{};

            try dvui.icon(@src(), "aircraft landing", entypo.aircraft_landing, opts.override(.{ .gravity_y = 0.5 }));
            try dvui.labelNoFmt(@src(), "icon with text", opts);

            if (mi.activeRect()) |_| {
                dd.close();
                g.choice = 0;
            }
        }

        if (try dd.addChoiceLabel("just text")) {
            g.choice = 1;
        }

        {
            var mi = try dd.addChoice();
            defer mi.deinit();

            var vbox = try dvui.box(@src(), .vertical, .{ .expand = .both });
            defer vbox.deinit();

            var opts: Options = if (mi.show_active) dvui.themeGet().style_accent else .{};

            try dvui.image(@src(), "zig favicon", zig_favicon, opts.override(.{ .gravity_x = 0.5 }));
            try dvui.labelNoFmt(@src(), "image above text", opts.override(.{ .gravity_x = 0.5 }));

            if (mi.activeRect()) |_| {
                dd.close();
                g.choice = 2;
            }
        }
    }

    dd.deinit();
}

pub fn textEntryWidgets() !void {
    var left_alignment = dvui.Alignment.init();
    defer left_alignment.deinit();

    var enter_pressed = false;
    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.label(@src(), "Singleline", .{}, .{ .gravity_y = 0.5 });

        // align text entry
        var hbox_aligned = try dvui.box(@src(), .horizontal, .{ .margin = left_alignment.margin(hbox.data().id) });
        defer hbox_aligned.deinit();
        left_alignment.record(hbox.data().id, hbox_aligned.data());

        var te = try dvui.textEntry(@src(), .{ .text = .{ .buffer = &text_entry_buf } }, .{});
        enter_pressed = te.enter_pressed;
        te.deinit();

        try dvui.label(@src(), "(limit {d})", .{text_entry_buf.len}, .{ .gravity_y = 0.5 });
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        // align to text entries
        var hbox_aligned = try dvui.box(@src(), .horizontal, .{ .margin = left_alignment.margin(hbox.data().id) });
        defer hbox_aligned.deinit();
        left_alignment.record(hbox.data().id, hbox_aligned.data());

        try dvui.label(@src(), "press enter", .{}, .{ .gravity_y = 0.5 });

        if (enter_pressed) {
            dvui.animation(hbox.data().id, "enter_pressed", .{ .start_val = 1.0, .end_val = 0, .start_time = 0, .end_time = 500_000 });
        }

        if (dvui.animationGet(hbox.data().id, "enter_pressed")) |a| {
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

        // align text entry
        var hbox_aligned = try dvui.box(@src(), .horizontal, .{ .margin = left_alignment.margin(hbox.data().id) });
        defer hbox_aligned.deinit();
        left_alignment.record(hbox.data().id, hbox_aligned.data());

        var te = try dvui.textEntry(@src(), .{
            .text = .{ .buffer = &text_entry_password_buf },
            .password_char = if (text_entry_password_buf_obf_enable) "*" else null,
        }, .{});

        te.deinit();

        if (try dvui.buttonIcon(
            @src(),
            "toggle",
            if (text_entry_password_buf_obf_enable) entypo.eye_with_line else entypo.eye,
            .{},
            .{ .gravity_y = 0.5, .min_size_content = .{ .h = 12 } },
        )) {
            text_entry_password_buf_obf_enable = !text_entry_password_buf_obf_enable;
        }

        try dvui.label(@src(), "(limit {d})", .{text_entry_password_buf.len}, .{ .gravity_y = 0.5 });
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.label(@src(), "Multiline", .{}, .{ .gravity_y = 0.5 });

        // align text entry
        var hbox_aligned = try dvui.box(@src(), .horizontal, .{ .margin = left_alignment.margin(hbox.data().id) });
        defer hbox_aligned.deinit();
        left_alignment.record(hbox.data().id, hbox_aligned.data());

        var te = try dvui.textEntry(
            @src(),
            .{ .multiline = true, .text = .{ .buffer_dynamic = .{ .backing = &text_entry_multiline_buf, .allocator = text_entry_multiline_fba.allocator() } } },
            .{
                .min_size_content = .{ .w = 150, .h = 80 },
            },
        );

        if (!text_entry_multiline_initialized) {
            text_entry_multiline_initialized = true;
            te.textTyped("This multiline text\nentry can scroll\nin both directions.");
        }

        const bytes = te.len;
        te.deinit();

        try dvui.label(@src(), "bytes {d}\nallocated {d}\nlimit {d}", .{ bytes, text_entry_multiline_buf.len, text_entry_multiline_allocator_buf.len }, .{ .gravity_y = 0.5 });
    }

    const S = struct {
        var type_dropdown_val: usize = 0;
        var min: bool = false;
        var max: bool = false;
    };
    const parse_types = [_]type{ u8, i8, u16, i16, u32, i32, f32, f64 };
    const parse_typenames: [parse_types.len][]const u8 = blk: {
        var temp: [parse_types.len][]const u8 = undefined;
        inline for (parse_types, 0..) |T, i| {
            temp[i] = @typeName(T);
        }
        break :blk temp;
    };

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.label(@src(), "Parse", .{}, .{ .gravity_y = 0.5 });

        _ = try dvui.dropdown(@src(), &parse_typenames, &S.type_dropdown_val, .{ .min_size_content = .{ .w = 20 }, .gravity_y = 0.5 });

        // align text entry
        var hbox_aligned = try dvui.box(@src(), .horizontal, .{ .margin = left_alignment.margin(hbox.data().id) });
        defer hbox_aligned.deinit();
        left_alignment.record(hbox.data().id, hbox_aligned.data());

        inline for (parse_types, 0..) |T, i| {
            if (i == S.type_dropdown_val) {
                const result = try dvui.textEntryNumber(@src(), T, .{ .min = if (S.min) 0 else null, .max = if (S.max) 100 else null, .show_min_max = true }, .{});
                try displayTextEntryNumberResult(result);
            }
        }
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        // align with text entries
        var hbox_aligned = try dvui.box(@src(), .horizontal, .{ .margin = left_alignment.margin(hbox.data().id) });
        defer hbox_aligned.deinit();
        left_alignment.record(hbox.data().id, hbox_aligned.data());

        _ = try dvui.checkbox(@src(), &S.min, "Min", .{});
        _ = try dvui.checkbox(@src(), &S.max, "Max", .{});
    }

    try dvui.label(@src(), "The text entries in this section are left-aligned", .{}, .{});
}

pub fn displayTextEntryNumberResult(result: anytype) !void {
    switch (result.value) {
        .TooBig => {
            try dvui.label(@src(), "Too Big", .{}, .{ .gravity_y = 0.5 });
        },
        .TooSmall => {
            try dvui.label(@src(), "Too Small", .{}, .{ .gravity_y = 0.5 });
        },
        .Empty => {
            try dvui.label(@src(), "Empty", .{}, .{ .gravity_y = 0.5 });
        },
        .Invalid => {
            try dvui.label(@src(), "Invalid", .{}, .{ .gravity_y = 0.5 });
        },
        .Valid => |num| {
            try dvui.label(@src(), "{d}", .{num}, .{ .gravity_y = 0.5 });
        },
    }
}

pub fn styling() !void {
    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        _ = try dvui.button(@src(), "Accent", .{}, dvui.themeGet().style_accent);
        _ = try dvui.button(@src(), "Error", .{}, dvui.themeGet().style_err);
        _ = try dvui.button(@src(), "Window", .{}, .{ .color_fill = .{ .name = .fill_window } });
        _ = try dvui.button(@src(), "Content", .{}, .{ .color_fill = .{ .name = .fill } });
        _ = try dvui.button(@src(), "Control", .{}, .{});
    }

    try dvui.label(@src(), "separators", .{}, .{});
    {
        var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .horizontal, .min_size_content = .{ .h = 9 } });
        defer hbox.deinit();

        const opts: Options = .{ .margin = dvui.Rect.all(2), .gravity_y = 0.5 };

        try dvui.separator(@src(), opts.override(.{ .expand = .vertical }));
        try dvui.separator(@src(), opts.override(.{ .expand = .vertical, .min_size_content = .{ .w = 3 } }));
        try dvui.separator(@src(), opts.override(.{ .expand = .vertical, .min_size_content = .{ .w = 5 } }));

        var vbox = try dvui.box(@src(), .vertical, .{ .expand = .horizontal });
        defer vbox.deinit();

        try dvui.separator(@src(), opts.override(.{ .expand = .horizontal }));
        try dvui.separator(@src(), opts.override(.{ .expand = .horizontal, .min_size_content = .{ .h = 3 } }));
        try dvui.separator(@src(), opts.override(.{ .expand = .horizontal, .min_size_content = .{ .h = 5 } }));
    }

    try dvui.label(@src(), "corner radius", .{}, .{});
    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        const opts: Options = .{ .border = Rect.all(1), .background = true, .min_size_content = .{ .w = 20 } };

        _ = try dvui.button(@src(), "0", .{}, opts.override(.{ .corner_radius = Rect.all(0) }));
        _ = try dvui.button(@src(), "2", .{}, opts.override(.{ .corner_radius = Rect.all(2) }));
        _ = try dvui.button(@src(), "7", .{}, opts.override(.{ .corner_radius = Rect.all(7) }));
        _ = try dvui.button(@src(), "100", .{}, opts.override(.{ .corner_radius = Rect.all(100) }));
        _ = try dvui.button(@src(), "mixed", .{}, opts.override(.{ .corner_radius = .{ .x = 0, .y = 2, .w = 7, .h = 100 } }));
    }

    try dvui.label(@src(), "directly set colors", .{}, .{});
    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        var backbox = try dvui.box(@src(), .horizontal, .{ .min_size_content = .{ .w = 30, .h = 20 }, .background = true, .color_fill = .{ .color = backbox_color }, .gravity_y = 0.5 });
        backbox.deinit();

        _ = try rgbSliders(@src(), &backbox_color, .{ .gravity_y = 0.5 });
    }

    try dvui.label(@src(), "HSLuv support", .{}, .{});
    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        var backbox = try dvui.box(@src(), .horizontal, .{ .min_size_content = .{ .w = 30, .h = 20 }, .background = true, .color_fill = .{ .color = hsluv_rgb }, .gravity_y = 0.5 });
        backbox.deinit();

        try hsluvSliders(@src(), &hsluv_hsl, &hsluv_rgb, .{ .gravity_y = 0.5 });
    }
}

// Let's wrap the sliderEntry widget so we have 3 that represent a Color
pub fn rgbSliders(src: std.builtin.SourceLocation, color: *dvui.Color, opts: Options) !void {
    var hbox = try dvui.box(src, .horizontal, opts);
    defer hbox.deinit();

    var red: f32 = @floatFromInt(color.r);
    var green: f32 = @floatFromInt(color.g);
    var blue: f32 = @floatFromInt(color.b);

    _ = try dvui.sliderEntry(@src(), "R: {d:0.0}", .{ .value = &red, .min = 0, .max = 255, .interval = 1 }, .{ .gravity_y = 0.5 });
    _ = try dvui.sliderEntry(@src(), "G: {d:0.0}", .{ .value = &green, .min = 0, .max = 255, .interval = 1 }, .{ .gravity_y = 0.5 });
    _ = try dvui.sliderEntry(@src(), "B: {d:0.0}", .{ .value = &blue, .min = 0, .max = 255, .interval = 1 }, .{ .gravity_y = 0.5 });

    color.r = @intFromFloat(red);
    color.g = @intFromFloat(green);
    color.b = @intFromFloat(blue);
}

// Let's wrap the sliderEntry widget so we have 3 that represent a HSLuv Color
pub fn hsluvSliders(src: std.builtin.SourceLocation, hsluv: *dvui.Color.HSLuv, color_out: *dvui.Color, opts: Options) !void {
    var hbox = try dvui.box(src, .horizontal, opts);
    defer hbox.deinit();

    var changed = false;
    if (try dvui.sliderEntry(@src(), "H: {d:0.0}", .{ .value = &hsluv.h, .min = 0, .max = 360, .interval = 1 }, .{ .gravity_y = 0.5 })) {
        changed = true;
    }
    if (try dvui.sliderEntry(@src(), "S: {d:0.0}", .{ .value = &hsluv.s, .min = 0, .max = 100, .interval = 1 }, .{ .gravity_y = 0.5 })) {
        changed = true;
    }
    if (try dvui.sliderEntry(@src(), "L: {d:0.0}", .{ .value = &hsluv.l, .min = 0, .max = 100, .interval = 1 }, .{ .gravity_y = 0.5 })) {
        changed = true;
    }

    if (changed) {
        color_out.* = hsluv.color();
    }
}

pub fn layout() !void {
    const opts: Options = .{ .border = Rect.all(1), .background = true, .min_size_content = .{ .w = 200, .h = 140 } };

    try dvui.label(@src(), "gravity/expand", .{}, .{});
    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        var o = try dvui.overlay(@src(), opts);
        var buf: [128]u8 = undefined;
        const label = try std.fmt.bufPrint(&buf, "{d:0.2},{d:0.2}", .{ layout_gravity_x, layout_gravity_y });
        var e: dvui.Options.Expand = .none;
        if (layout_expand_horizontal and layout_expand_vertical) {
            e = .both;
        } else if (layout_expand_horizontal) {
            e = .horizontal;
        } else if (layout_expand_vertical) {
            e = .vertical;
        }

        _ = try dvui.button(@src(), label, .{}, .{ .gravity_x = layout_gravity_x, .gravity_y = layout_gravity_y, .expand = e });
        o.deinit();

        var vbox = try dvui.box(@src(), .vertical, .{});
        try dvui.label(@src(), "Gravity", .{}, .{});
        _ = try dvui.sliderEntry(@src(), "X: {d:0.2}", .{ .value = &layout_gravity_x, .min = 0, .max = 1.0, .interval = 0.01 }, .{});
        _ = try dvui.sliderEntry(@src(), "Y: {d:0.2}", .{ .value = &layout_gravity_y, .min = 0, .max = 1.0, .interval = 0.01 }, .{});
        _ = try dvui.checkbox(@src(), &layout_expand_horizontal, "Expand Horizontal", .{});
        _ = try dvui.checkbox(@src(), &layout_expand_vertical, "Expand Vertical", .{});
        vbox.deinit();
    }

    try dvui.label(@src(), "margin/border/padding", .{}, .{});
    {
        var vbox = try dvui.box(@src(), .vertical, .{});
        defer vbox.deinit();

        var vbox2 = try dvui.box(@src(), .vertical, .{ .gravity_x = 0.5 });
        _ = try dvui.sliderEntry(@src(), "margin {d:0.0}", .{ .value = &layout_margin.y, .min = 0, .max = 20.0, .interval = 1 }, .{});
        _ = try dvui.sliderEntry(@src(), "border {d:0.0}", .{ .value = &layout_border.y, .min = 0, .max = 20.0, .interval = 1 }, .{});
        _ = try dvui.sliderEntry(@src(), "padding {d:0.0}", .{ .value = &layout_padding.y, .min = 0, .max = 20.0, .interval = 1 }, .{});
        vbox2.deinit();

        var hbox = try dvui.box(@src(), .horizontal, .{});

        vbox2 = try dvui.box(@src(), .vertical, .{ .gravity_y = 0.5 });
        _ = try dvui.sliderEntry(@src(), "margin {d:0.0}", .{ .value = &layout_margin.x, .min = 0, .max = 20.0, .interval = 1 }, .{});
        _ = try dvui.sliderEntry(@src(), "border {d:0.0}", .{ .value = &layout_border.x, .min = 0, .max = 20.0, .interval = 1 }, .{});
        _ = try dvui.sliderEntry(@src(), "padding {d:0.0}", .{ .value = &layout_padding.x, .min = 0, .max = 20.0, .interval = 1 }, .{});
        vbox2.deinit();

        var o = try dvui.overlay(@src(), .{ .min_size_content = .{ .w = 164, .h = 140 } });
        var o2 = try dvui.overlay(@src(), .{ .background = true, .gravity_x = 0.5, .gravity_y = 0.5 });
        if (try dvui.button(@src(), "reset", .{}, .{ .margin = layout_margin, .border = layout_border, .padding = layout_padding })) {
            layout_margin = Rect.all(4);
            layout_border = Rect.all(0);
            layout_padding = Rect.all(4);
        }
        o2.deinit();
        o.deinit();

        vbox2 = try dvui.box(@src(), .vertical, .{ .gravity_y = 0.5 });
        _ = try dvui.sliderEntry(@src(), "margin {d:0.0}", .{ .value = &layout_margin.w, .min = 0, .max = 20.0, .interval = 1 }, .{});
        _ = try dvui.sliderEntry(@src(), "border {d:0.0}", .{ .value = &layout_border.w, .min = 0, .max = 20.0, .interval = 1 }, .{});
        _ = try dvui.sliderEntry(@src(), "padding {d:0.0}", .{ .value = &layout_padding.w, .min = 0, .max = 20.0, .interval = 1 }, .{});
        vbox2.deinit();

        hbox.deinit();

        vbox2 = try dvui.box(@src(), .vertical, .{ .gravity_x = 0.5 });
        _ = try dvui.sliderEntry(@src(), "margin {d:0.0}", .{ .value = &layout_margin.h, .min = 0, .max = 20.0, .interval = 1 }, .{});
        _ = try dvui.sliderEntry(@src(), "border {d:0.0}", .{ .value = &layout_border.h, .min = 0, .max = 20.0, .interval = 1 }, .{});
        _ = try dvui.sliderEntry(@src(), "padding {d:0.0}", .{ .value = &layout_padding.h, .min = 0, .max = 20.0, .interval = 1 }, .{});
        vbox2.deinit();
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

                _ = try dvui.button(@src(), "vertical", .{}, grav);
                _ = try dvui.button(@src(), "expand", .{}, grav.override(.{ .expand = .vertical }));
                _ = try dvui.button(@src(), "a", .{}, grav);
            }

            {
                var vbox = try dvui.boxEqual(@src(), .vertical, opts.override(.{ .expand = .both, .min_size_content = .{} }));
                defer vbox.deinit();

                _ = try dvui.button(@src(), "vert equal", .{}, grav);
                _ = try dvui.button(@src(), "expand", .{}, grav.override(.{ .expand = .vertical }));
                _ = try dvui.button(@src(), "a", .{}, grav);
            }
        }

        {
            var vbox2 = try dvui.box(@src(), .vertical, .{ .min_size_content = .{ .w = 200, .h = 140 } });
            defer vbox2.deinit();
            {
                var hbox2 = try dvui.box(@src(), .horizontal, opts.override(.{ .expand = .both, .min_size_content = .{} }));
                defer hbox2.deinit();

                _ = try dvui.button(@src(), "horizontal", .{}, grav);
                _ = try dvui.button(@src(), "expand", .{}, grav.override(.{ .expand = .horizontal }));
                _ = try dvui.button(@src(), "a", .{}, grav);
            }

            {
                var hbox2 = try dvui.boxEqual(@src(), .horizontal, opts.override(.{ .expand = .both, .min_size_content = .{} }));
                defer hbox2.deinit();

                _ = try dvui.button(@src(), "horz\nequal", .{}, grav);
                _ = try dvui.button(@src(), "expand", .{}, grav.override(.{ .expand = .horizontal }));
                _ = try dvui.button(@src(), "a", .{}, grav);
            }
        }
    }

    try dvui.label(@src(), "Collapsible Pane with Draggable Sash", .{}, .{});
    {
        var paned = try dvui.paned(@src(), .{ .direction = .horizontal, .collapsed_size = paned_collapsed_width }, .{ .expand = .both, .background = false, .min_size_content = .{ .h = 100 } });
        defer paned.deinit();

        {
            var vbox = try dvui.box(@src(), .vertical, .{ .expand = .both, .background = true });
            defer vbox.deinit();

            try dvui.label(@src(), "Left Side", .{}, .{});
            try dvui.label(@src(), "collapses when width < {d}", .{paned_collapsed_width}, .{});
            try dvui.label(@src(), "current width {d}", .{paned.wd.rect.w}, .{});
            if (paned.collapsed() and try dvui.button(@src(), "Goto Right", .{}, .{})) {
                paned.animateSplit(0.0);
            }
        }

        {
            var vbox = try dvui.box(@src(), .vertical, .{ .expand = .both, .background = true });
            defer vbox.deinit();

            try dvui.label(@src(), "Right Side", .{}, .{});
            if (paned.collapsed() and try dvui.button(@src(), "Goto Left", .{}, .{})) {
                paned.animateSplit(1.0);
            }
        }
    }

    _ = try dvui.sliderEntry(@src(), "collapse under {d:0.0}", .{ .value = &paned_collapsed_width, .min = 100, .max = 600, .interval = 10 }, .{});
}

pub fn layoutText() !void {
    _ = try dvui.sliderEntry(@src(), "line height: {d:0.2}", .{ .value = &line_height_factor, .min = 0.1, .max = 2, .interval = 0.1 }, .{});

    {
        var tl = TextLayoutWidget.init(@src(), .{}, .{ .expand = .horizontal });
        try tl.install(.{});
        defer tl.deinit();

        var cbox = try dvui.box(@src(), .vertical, .{ .padding = .{ .w = 4 } });
        if (try dvui.buttonIcon(@src(), "play", entypo.controller_play, .{}, .{ .padding = Rect.all(6), .min_size_content = .{ .h = 18 } })) {
            try dvui.dialog(@src(), .{ .modal = false, .title = "Ok Dialog", .message = "You clicked play" });
        }
        if (try dvui.buttonIcon(@src(), "more", entypo.dots_three_vertical, .{}, .{ .padding = Rect.all(6), .min_size_content = .{ .h = 18 } })) {
            try dvui.dialog(@src(), .{ .modal = false, .title = "Ok Dialog", .message = "You clicked more" });
        }
        cbox.deinit();

        cbox = try dvui.box(@src(), .vertical, .{ .margin = Rect.all(4), .padding = Rect.all(4), .gravity_x = 1.0, .background = true, .color_fill = .{ .name = .fill_window }, .min_size_content = .{ .w = 120 } });
        try dvui.icon(@src(), "aircraft", entypo.aircraft, .{ .min_size_content = .{ .h = 30 }, .gravity_x = 0.5 });
        try dvui.label(@src(), "Caption Heading", .{}, .{ .font_style = .caption_heading, .gravity_x = 0.5 });
        var tl_caption = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .min_size_content = .{ .w = 10 }, .background = false });
        try tl_caption.addText("Here is some caption text that is in it's own text layout.", .{ .font_style = .caption });
        tl_caption.deinit();
        cbox.deinit();

        if (try tl.touchEditing()) |floating_widget| {
            defer floating_widget.deinit();
            try tl.touchEditingMenu();
        }

        tl.processEvents();

        const lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. ";
        const lorem2 = " Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.\n";
        try tl.addText(lorem, .{ .font = dvui.themeGet().font_body.lineHeightFactor(line_height_factor) });

        if (try tl.addTextClick("This text is a link that is part of the text layout and goes to the dvui home page.", .{ .color_text = .{ .color = .{ .r = 0x35, .g = 0x84, .b = 0xe4 } }, .font = dvui.themeGet().font_body.lineHeightFactor(line_height_factor) })) {
            try dvui.openURL("https://github.com/david-vanderson/dvui");
        }

        try tl.addText(lorem2, .{ .font = dvui.themeGet().font_body.lineHeightFactor(line_height_factor) });

        const start = "\nNotice that the text in this box is wrapping around the stuff in the corners.\n\n";
        try tl.addText(start, .{ .font_style = .title_4 });

        try tl.addText("Title ", .{ .font_style = .title });
        try tl.addText("Title-1 ", .{ .font_style = .title_1 });
        try tl.addText("Title-2 ", .{ .font_style = .title_2 });
        try tl.addText("Title-3 ", .{ .font_style = .title_3 });
        try tl.addText("Title-4 ", .{ .font_style = .title_4 });
        try tl.addText("Heading\n", .{ .font_style = .heading });

        try tl.addText("Here ", .{ .font_style = .title, .color_text = .{ .color = .{ .r = 100, .b = 100 } } });
        try tl.addText("is some ", .{ .font_style = .title_2, .color_text = .{ .color = .{ .b = 100, .g = 100 } } });
        try tl.addText("ugly text ", .{ .font_style = .title_1, .color_text = .{ .color = .{ .r = 100, .g = 100 } } });
        try tl.addText("that shows styling.", .{ .font_style = .caption, .color_text = .{ .color = .{ .r = 100, .g = 50, .b = 50 } } });
    }
}

pub fn reorderLists() !void {
    const g = struct {
        var dir_entry: usize = 0;
    };

    if (try dvui.expander(@src(), "Simple", .{}, .{ .expand = .horizontal })) {
        const dir: dvui.enums.Direction = if (g.dir_entry == 0) .vertical else .horizontal;

        var vbox = try dvui.box(@src(), .vertical, .{ .margin = .{ .x = 10 } });
        defer vbox.deinit();

        {
            var hbox2 = try dvui.box(@src(), .horizontal, .{});
            defer hbox2.deinit();

            const entries = [_][]const u8{ "Vertical", "Horizontal" };
            for (0..2) |i| {
                if (try dvui.radio(@src(), g.dir_entry == i, entries[i], .{ .id_extra = i })) {
                    g.dir_entry = i;
                }
            }
        }

        {
            var hbox2 = try dvui.box(@src(), .horizontal, .{});
            defer hbox2.deinit();
            try dvui.label(@src(), "Drag", .{}, .{});
            try dvui.icon(@src(), "drag_icon", dvui.entypo.menu, .{ .min_size_content = .{ .h = 22 } });
            try dvui.label(@src(), "to reorder.", .{}, .{});
        }

        try reorderListsSimple(dir);
    }

    if (try dvui.expander(@src(), "Advanced", .{}, .{ .expand = .horizontal })) {
        var vbox = try dvui.box(@src(), .vertical, .{ .margin = .{ .x = 10 } });
        defer vbox.deinit();

        try dvui.label(@src(), "Drag off list to remove.", .{}, .{});
        try reorderListsAdvanced();
    }
}

pub fn reorderListsSimple(dir: dvui.enums.Direction) !void {
    const g = struct {
        var dir_entry: usize = 0;
        var strings = [6][]const u8{ "zero", "one", "two", "three", "four", "five" };
    };

    var removed_idx: ?usize = null;
    var insert_before_idx: ?usize = null;

    // reorder widget must wrap entire list
    var reorder = try dvui.reorder(@src(), .{ .min_size_content = .{ .w = 120 }, .background = true, .border = dvui.Rect.all(1), .padding = dvui.Rect.all(4) });
    defer reorder.deinit();

    // this box determines layout of list - could be any layout widget
    var vbox = try dvui.box(@src(), dir, .{ .expand = .both });
    defer vbox.deinit();

    for (g.strings[0..g.strings.len], 0..) |s, i| {

        // make a reorderable for each entry in the list
        var reorderable = try reorder.reorderable(@src(), .{}, .{ .id_extra = i, .expand = .horizontal });
        defer reorderable.deinit();

        if (reorderable.removed()) {
            removed_idx = i; // this entry is being dragged
        } else if (reorderable.insertBefore()) {
            insert_before_idx = i; // this entry was dropped onto
        }

        // actual content of the list entry
        var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .both, .border = dvui.Rect.all(1), .background = true, .color_fill = .{ .name = .fill_window } });
        defer hbox.deinit();

        try dvui.label(@src(), "{s}", .{s}, .{});

        // this helper shows the triple-line icon, detects the start of a drag,
        // and hands off the drag to the ReorderWidget
        _ = try dvui.ReorderWidget.draggable(@src(), .{ .reorderable = reorderable }, .{ .expand = .vertical, .gravity_x = 1.0, .min_size_content = dvui.Size.all(22), .gravity_y = 0.5 });
    }

    // show a final slot that allows dropping an entry at the end of the list
    if (try reorder.finalSlot()) {
        insert_before_idx = g.strings.len; // entry was dropped into the final slot
    }

    // returns true if the slice was reordered
    _ = dvui.ReorderWidget.reorderSlice([]const u8, &g.strings, removed_idx, insert_before_idx);
}

pub fn reorderListsAdvanced() !void {
    const g = struct {
        var strings_template = [6][]const u8{ "zero", "one", "two", "three", "four", "five" };
        var strings = [6][]const u8{ "zero", "one", "two", "three", "", "" };
        var strings_len: usize = 4;

        pub fn reorder(removed_idx: ?usize, insert_before_idx: ?usize) void {
            if (removed_idx) |ri| {
                if (insert_before_idx) |ibi| {
                    // save this index
                    const removed = strings[ri];
                    if (ri < ibi) {
                        // moving down, shift others up
                        for (ri..ibi - 1) |i| {
                            strings[i] = strings[i + 1];
                        }
                        strings[ibi - 1] = removed;
                    } else {
                        // moving up, shift others down
                        for (ibi..ri, 0..) |_, i| {
                            strings[ri - i] = strings[ri - i - 1];
                        }
                        strings[ibi] = removed;
                    }
                } else {
                    // just removing, shift others up
                    for (ri..strings_len - 1) |i| {
                        strings[i] = strings[i + 1];
                    }
                    strings_len -= 1;
                }
            }
        }
    };

    var hbox = try dvui.box(@src(), .horizontal, .{});
    defer hbox.deinit();

    // template you can drag to add to list
    var added_idx: ?usize = null;
    var added_idx_p: ?dvui.Point = null;

    if (g.strings_len == g.strings.len) {
        try dvui.label(@src(), "List Full", .{}, .{ .gravity_x = 1.0 });
    } else {
        var hbox2 = try dvui.box(@src(), .horizontal, .{ .gravity_x = 1.0, .border = dvui.Rect.all(1), .margin = dvui.Rect.all(4), .background = true, .color_fill = .{ .name = .fill_window } });
        defer hbox2.deinit();

        try dvui.label(@src(), "Drag to add : {d}", .{g.strings_len}, .{});

        if (try dvui.ReorderWidget.draggable(@src(), .{ .top_left = hbox2.wd.rectScale().r.topLeft() }, .{ .expand = .vertical, .gravity_x = 1.0, .min_size_content = dvui.Size.all(22), .gravity_y = 0.5 })) |p| {
            // add to list, but will be removed if not dropped onto a list slot
            g.strings[g.strings_len] = g.strings_template[g.strings_len];
            added_idx = g.strings_len;
            added_idx_p = p;
            g.strings_len += 1;
        }
    }

    var removed_idx: ?usize = null;
    var insert_before_idx: ?usize = null;

    // reorder widget must wrap entire list
    var reorder = try dvui.reorder(@src(), .{ .min_size_content = .{ .w = 120 }, .background = true, .border = dvui.Rect.all(1), .padding = dvui.Rect.all(4) });
    defer reorder.deinit();

    // determines layout of list
    var vbox = try dvui.box(@src(), .vertical, .{ .expand = .both });
    defer vbox.deinit();

    if (added_idx) |ai| {
        reorder.dragStart(ai, added_idx_p.?); // reorder grabs capture
    }

    var seen_non_floating = false;
    for (g.strings[0..g.strings_len], 0..) |s, i| {
        // overriding the reorder id used so that it doesn't use the widget ids
        // (this allows adding a list element above without making a widget)
        var reorderable = dvui.Reorderable.init(@src(), reorder, .{ .reorder_id = i, .draw_target = false, .reinstall = false }, .{ .id_extra = i, .expand = .horizontal });
        defer reorderable.deinit();

        if (!reorderable.floating()) {
            if (seen_non_floating) {
                // we've had a non floating one already, and we are non floating, so add a separator
                try dvui.separator(@src(), .{ .id_extra = i, .expand = .horizontal, .margin = dvui.Rect.all(6) });
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
            // user is dragging a reorderable over this rect, could draw anything here
            try dvui.pathAddRect(rs.r, .{});
            try dvui.pathFillConvex(.{ .r = 0, .g = 255, .b = 0 });

            // reset to use next space, need a separator
            try dvui.separator(@src(), .{ .expand = .horizontal, .margin = dvui.Rect.all(6) });
            try reorderable.reinstall();
        }

        // actual content of the list entry
        var hbox2 = try dvui.box(@src(), .horizontal, .{ .expand = .both, .border = dvui.Rect.all(1), .background = true, .color_fill = .{ .name = .fill_window } });
        defer hbox2.deinit();

        try dvui.label(@src(), "{s}", .{s}, .{});

        if (try dvui.ReorderWidget.draggable(@src(), .{ .top_left = reorderable.wd.rectScale().r.topLeft() }, .{ .expand = .vertical, .gravity_x = 1.0, .min_size_content = dvui.Size.all(22), .gravity_y = 0.5 })) |p| {
            reorder.dragStart(i, p); // reorder grabs capture
        }
    }

    if (reorder.needFinalSlot()) {
        if (seen_non_floating) {
            try dvui.separator(@src(), .{ .expand = .horizontal, .margin = dvui.Rect.all(6) });
        }
        var reorderable = try reorder.reorderable(@src(), .{ .last_slot = true, .draw_target = false }, .{});
        defer reorderable.deinit();

        if (reorderable.insertBefore()) {
            insert_before_idx = g.strings_len;
        }

        if (reorderable.targetRectScale()) |rs| {
            // user is dragging a reorderable over this rect
            try dvui.pathAddRect(rs.r, .{});
            try dvui.pathFillConvex(.{ .r = 0, .g = 255, .b = 0 });
        }
    }

    g.reorder(removed_idx, insert_before_idx);
}

pub fn menus() !void {
    const ctext = try dvui.context(@src(), .{ .expand = .horizontal });
    defer ctext.deinit();

    if (ctext.activePoint()) |cp| {
        var fw2 = try dvui.floatingMenu(@src(), Rect.fromPoint(cp), .{});
        defer fw2.deinit();

        _ = try dvui.menuItemLabel(@src(), "Dummy", .{}, .{ .expand = .horizontal });
        _ = try dvui.menuItemLabel(@src(), "Dummy Long", .{}, .{ .expand = .horizontal });
        if ((try dvui.menuItemLabel(@src(), "Close Menu", .{}, .{ .expand = .horizontal })) != null) {
            fw2.close();
        }
    }

    var vbox = try dvui.box(@src(), .vertical, .{});
    defer vbox.deinit();

    {
        var m = try dvui.menu(@src(), .horizontal, .{});
        defer m.deinit();

        if (try dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{ .expand = .horizontal })) |r| {
            var fw = try dvui.floatingMenu(@src(), Rect.fromPoint(Point{ .x = r.x, .y = r.y + r.h }), .{});
            defer fw.deinit();

            try submenus();

            _ = try dvui.checkbox(@src(), &checkbox_bool, "Checkbox", .{});

            if (try dvui.menuItemLabel(@src(), "Dialog", .{}, .{ .expand = .horizontal }) != null) {
                fw.close();
                show_dialog = true;
            }

            if (try dvui.menuItemLabel(@src(), "Close Menu", .{}, .{ .expand = .horizontal }) != null) {
                fw.close();
            }
        }

        if (try dvui.menuItemLabel(@src(), "Edit", .{ .submenu = true }, .{ .expand = .horizontal })) |r| {
            var fw = try dvui.floatingMenu(@src(), Rect.fromPoint(Point{ .x = r.x, .y = r.y + r.h }), .{});
            defer fw.deinit();
            _ = try dvui.menuItemLabel(@src(), "Dummy", .{}, .{ .expand = .horizontal });
            _ = try dvui.menuItemLabel(@src(), "Dummy Long", .{}, .{ .expand = .horizontal });
            _ = try dvui.menuItemLabel(@src(), "Dummy Super Long", .{}, .{ .expand = .horizontal });
        }
    }

    try dvui.labelNoFmt(@src(), "Right click for a context menu", .{});
}

pub fn submenus() !void {
    if (try dvui.menuItemLabel(@src(), "Submenu...", .{ .submenu = true }, .{ .expand = .horizontal })) |r| {
        var menu_rect = r;
        menu_rect.x += menu_rect.w;
        var fw2 = try dvui.floatingMenu(@src(), menu_rect, .{});
        defer fw2.deinit();

        try submenus();

        if (try dvui.menuItemLabel(@src(), "Close Menu", .{}, .{ .expand = .horizontal }) != null) {
            fw2.close();
        }

        if (try dvui.menuItemLabel(@src(), "Dialog", .{}, .{ .expand = .horizontal }) != null) {
            fw2.close();
            show_dialog = true;
        }
    }
}

pub fn focus() !void {
    var tl = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .color_fill = .{ .name = .fill_window } });
    try tl.addText("Each time this section is expanded, this text entry will be focused", .{});
    tl.deinit();

    var te = try dvui.textEntry(@src(), .{}, .{});

    // firstFrame must be called before te.deinit()
    if (dvui.firstFrame(te.data().id)) {
        dvui.focusWidget(te.data().id, null, null);
    }

    te.deinit();

    // Get a unique Id without making a widget
    const uniqueId = dvui.parentGet().extendId(@src(), 0);

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        if (try dvui.button(@src(), "Focus Next textEntry", .{}, .{})) {
            // grab id from previous frame
            if (dvui.dataGet(null, uniqueId, "next_text_entry_id", u32)) |id| {
                dvui.focusWidget(id, null, null);
            }
        }

        if (try dvui.button(@src(), "Focus Prev textEntry", .{}, .{})) {
            dvui.focusWidget(te.data().id, null, null);
        }
    }

    var te2 = try dvui.textEntry(@src(), .{}, .{});

    // save id for next frame
    dvui.dataSet(null, uniqueId, "next_text_entry_id", te2.data().id);

    te2.deinit();
}

pub fn scrolling() !void {
    const Data = struct {
        var msg_start: usize = 1_000;
        var msg_end: usize = 1_100;
        var scroll_info: ScrollInfo = .{};
    };

    var scroll_to_msg: ?usize = null;
    var scroll_to_bottom_after = false;
    var scroll_lock_visible = false;

    var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
    defer hbox.deinit();
    {
        var vbox = try dvui.box(@src(), .vertical, .{ .expand = .vertical });
        defer vbox.deinit();

        if (try dvui.button(@src(), "Scroll to Top", .{}, .{})) {
            Data.scroll_info.scrollToOffset(.vertical, 0);
        }

        {
            var h2 = try dvui.box(@src(), .horizontal, .{});
            defer h2.deinit();
            if (try dvui.button(@src(), "Add Above", .{}, .{})) {
                Data.msg_start -|= 10;
            }

            if (try dvui.button(@src(), "Del Above", .{}, .{})) {
                Data.msg_start = @min(Data.msg_end, Data.msg_start + 10);
            }
        }

        if (try dvui.button(@src(), "Add Above No Scroll", .{}, .{})) {
            Data.msg_start -|= 10;
            scroll_lock_visible = true;
        }

        if (try dvui.button(@src(), "Del Above No Scroll", .{}, .{})) {
            Data.msg_start = @min(Data.msg_end, Data.msg_start + 10);
            scroll_lock_visible = true;
        }

        _ = try dvui.spacer(@src(), .{}, .{ .expand = .vertical });

        try dvui.label(@src(), "Scroll to msg:", .{}, .{});
        const result = try dvui.textEntryNumber(@src(), usize, .{ .min = Data.msg_start, .max = Data.msg_end }, dvui.Options.sizeM(8, 1));
        const label = switch (result.value) {
            .TooBig => "Too Big",
            .TooSmall => "Too Small",
            .Invalid => "Invalid",
            .Valid, .Empty => " ",
        };
        try dvui.labelNoFmt(@src(), label, .{});
        if (result.value == .Valid and result.enter_pressed) {
            scroll_to_msg = result.value.Valid;
        }

        _ = try dvui.spacer(@src(), .{}, .{ .expand = .vertical });

        {
            var h2 = try dvui.box(@src(), .horizontal, .{});
            defer h2.deinit();
            if (try dvui.button(@src(), "Add Below", .{}, .{})) {
                Data.msg_end += 10;
            }

            if (try dvui.button(@src(), "Del Below", .{}, .{})) {
                Data.msg_end = @max(Data.msg_start, Data.msg_end - 10);
            }
        }

        if (try dvui.button(@src(), "Add Below + Scroll", .{}, .{})) {
            Data.msg_end += 10;
            scroll_to_bottom_after = true;
        }

        if (try dvui.button(@src(), "Scroll to Bottom", .{}, .{})) {
            Data.scroll_info.scrollToOffset(.vertical, std.math.maxInt(usize));
        }
    }
    {
        var vbox = try dvui.box(@src(), .vertical, .{ .expand = .horizontal });
        defer vbox.deinit();

        try dvui.label(@src(), "{d:0>4.2}% visible, offset {d} frac {d:0>4.2}", .{ Data.scroll_info.visibleFraction(.vertical) * 100.0, Data.scroll_info.viewport.y, Data.scroll_info.offsetFraction(.vertical) }, .{});

        var scroll = try dvui.scrollArea(@src(), .{ .scroll_info = &Data.scroll_info, .lock_visible = scroll_lock_visible }, .{ .expand = .horizontal, .min_size_content = .{ .h = 250 } });
        defer scroll.deinit();

        for (Data.msg_start..Data.msg_end + 1) |i| {
            var tl = try dvui.textLayout(@src(), .{}, .{ .id_extra = i, .color_fill = .{ .name = .fill_window } });
            try tl.format("Message {d}", .{i}, .{});

            if (scroll_to_msg != null and scroll_to_msg.? == i) {
                Data.scroll_info.scrollToOffset(.vertical, tl.data().rect.y);
            }

            tl.deinit();

            var tl2 = try dvui.textLayout(@src(), .{}, .{ .id_extra = i, .gravity_x = 1.0, .color_fill = .{ .name = .fill_window }, .min_size_content = .{} });
            try tl2.format("Reply {d}", .{i}, .{});
            tl2.deinit();
        }

        //const visibleRect = scroll.si.viewport;
    }

    if (scroll_to_bottom_after) {
        // do this after scrollArea has given scroll_info the new size
        Data.scroll_info.scrollToOffset(.vertical, std.math.maxInt(usize));
    }

    // todo: add button to show icon browser with note about how that works

}

pub fn dialogs(demo_win_id: u32) !void {
    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();
        if (try dvui.button(@src(), "Direct Dialog", .{}, .{})) {
            show_dialog = true;
        }

        if (try dvui.button(@src(), "Giant", .{}, .{})) {
            try dvui.dialog(@src(), .{ .modal = false, .title = "So Much Text", .ok_label = "Too Much", .max_size = .{ .w = 300, .h = 300 }, .message = "This is a non modal dialog with no callafter which happens to have just way too much text in it.\n\nLuckily there is a max_size on here and if the text is too big it will be scrolled.\n\nI mean come on there is just way too much text here.\n\nCan you imagine this much text being created for a dialog?\n\nMaybe like a giant error message with a stack trace or dumping the contents of a large struct?\n\nOr a dialog asking way too many questions, or dumping a whole log into the dialog, or just a very long rant." });
        }
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        if (try dvui.button(@src(), "Non modal", .{}, .{})) {
            try dvui.dialog(@src(), .{ .modal = false, .title = "Ok Dialog", .ok_label = "Done", .message = "This is a non modal dialog with no callafter" });
        }

        const dialogsFollowup = struct {
            fn callafter(id: u32, response: enums.DialogResponse) Error!void {
                _ = id;
                var buf: [100]u8 = undefined;
                const text = std.fmt.bufPrint(&buf, "You clicked \"{s}\" in the previous dialog", .{@tagName(response)}) catch unreachable;
                try dvui.dialog(@src(), .{ .title = "Ok Followup Response", .message = text });
            }
        };

        if (try dvui.button(@src(), "Modal with followup", .{}, .{})) {
            try dvui.dialog(@src(), .{ .title = "Followup", .message = "This is a modal dialog with modal followup", .callafterFn = dialogsFollowup.callafter, .cancel_label = "Cancel" });
        }
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        if (try dvui.button(@src(), "Toast 1", .{}, .{})) {
            try dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Toast 1 to demo window" });
        }

        if (try dvui.button(@src(), "Toast 2", .{}, .{})) {
            try dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Toast 2 to demo window" });
        }

        if (try dvui.button(@src(), "Toast 3", .{}, .{})) {
            try dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Toast 3 to demo window" });
        }

        if (try dvui.button(@src(), "Toast Main Window", .{}, .{})) {
            try dvui.toast(@src(), .{ .message = "Toast to main window" });
        }
    }

    if (!builtin.single_threaded) {
        try dvui.label(@src(), "Example of how to show a dialog/toast from another thread", .{}, .{});
        {
            var hbox = try dvui.box(@src(), .horizontal, .{});
            defer hbox.deinit();

            if (try dvui.button(@src(), "Dialog after 1 second", .{}, .{})) {
                const bg_thread = try std.Thread.spawn(.{}, background_dialog, .{ dvui.currentWindow(), 1_000_000_000 });
                bg_thread.detach();
            }

            if (try dvui.button(@src(), "Toast after 1 second", .{}, .{})) {
                const bg_thread = try std.Thread.spawn(.{}, background_toast, .{ dvui.currentWindow(), 1_000_000_000, demo_win_id });
                bg_thread.detach();
            }
        }

        {
            var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
            defer hbox.deinit();

            if (try dvui.button(@src(), "Show Progress from another Thread", .{}, .{})) {
                progress_mutex.lock();
                progress_val = 0;
                progress_mutex.unlock();
                const bg_thread = try std.Thread.spawn(.{}, background_progress, .{ dvui.currentWindow(), 2_000_000_000 });
                bg_thread.detach();
            }

            try dvui.progress(@src(), .{ .percent = progress_val }, .{ .expand = .horizontal, .gravity_y = 0.5, .corner_radius = dvui.Rect.all(100) });
        }
    }
}

pub fn animations() !void {
    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        _ = try dvui.spacer(@src(), .{ .w = 20 }, .{});
        var button_wiggle = ButtonWidget.init(@src(), .{}, .{ .tab_index = 10 });
        defer button_wiggle.deinit();

        if (dvui.animationGet(button_wiggle.data().id, "xoffset")) |a| {
            button_wiggle.data().rect.x += 20 * (1.0 - a.lerp()) * (1.0 - a.lerp()) * @sin(a.lerp() * std.math.pi * 50);
        }

        try button_wiggle.install();
        button_wiggle.processEvents();
        try button_wiggle.drawBackground();
        try dvui.labelNoFmt(@src(), "Wiggle", button_wiggle.data().options.strip().override(.{ .gravity_x = 0.5, .gravity_y = 0.5 }));
        try button_wiggle.drawFocus();

        if (button_wiggle.clicked()) {
            dvui.animation(button_wiggle.data().id, "xoffset", .{ .start_val = 0, .end_val = 1.0, .start_time = 0, .end_time = 500_000 });
        }
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.labelNoFmt(@src(), "Alpha", .{ .gravity_y = 0.5 });

        {
            var animator = try dvui.animate(@src(), .alpha, 500_000, .{});
            defer animator.deinit();

            var hbox2 = try dvui.box(@src(), .horizontal, .{});
            defer hbox2.deinit();

            if (try dvui.button(@src(), "starting", .{}, .{})) {
                animator.start();
            }

            if (try dvui.button(@src(), "ending", .{}, .{})) {
                animator.startEnd();
            }
        }
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.labelNoFmt(@src(), "Vertical", .{ .gravity_y = 0.5 });

        {
            var animator = try dvui.animate(@src(), .vertical, 500_000, .{});
            defer animator.deinit();

            var hbox2 = try dvui.box(@src(), .horizontal, .{});
            defer hbox2.deinit();

            if (try dvui.button(@src(), "starting", .{}, .{})) {
                animator.start();
            }

            if (try dvui.button(@src(), "ending", .{}, .{})) {
                animator.startEnd();
            }
        }
    }

    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.labelNoFmt(@src(), "Horizontal", .{ .gravity_y = 0.5 });

        {
            var animator = try dvui.animate(@src(), .horizontal, 500_000, .{});
            defer animator.deinit();

            var hbox2 = try dvui.box(@src(), .horizontal, .{});
            defer hbox2.deinit();

            if (try dvui.button(@src(), "starting", .{}, .{})) {
                animator.start();
            }

            if (try dvui.button(@src(), "ending", .{}, .{})) {
                animator.startEnd();
            }
        }
    }

    if (try dvui.button(@src(), "Animating Dialog (Scale)", .{}, .{})) {
        try dvui.dialog(@src(), .{ .modal = false, .title = "Animating Dialog (Scale)", .message = "This shows how to animate dialogs and other floating windows by changing the scale.", .displayFn = AnimatingDialog.dialogDisplay, .callafterFn = AnimatingDialog.after });
    }

    if (try dvui.button(@src(), "Animating Window (Rect)", .{}, .{})) {
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
        try tl.addText("This shows how to animate dialogs and other floating windows by changing the rect.\n\nThis dialog also remembers its position on screen.", .{});
        tl.deinit();
    }

    if (try dvui.expander(@src(), "Spinner", .{}, .{ .expand = .horizontal })) {
        try dvui.labelNoFmt(@src(), "Spinner maxes out frame rate", .{});
        try dvui.spinner(@src(), .{ .color_text = .{ .color = .{ .r = 100, .g = 200, .b = 100 } } });
    }

    if (try dvui.expander(@src(), "Clock", .{}, .{ .expand = .horizontal })) {
        try dvui.labelNoFmt(@src(), "Schedules a frame at the beginning of each second", .{});

        const millis = @divFloor(dvui.frameTimeNS(), 1_000_000);
        const left = @as(i32, @intCast(@rem(millis, 1000)));

        var mslabel = try dvui.LabelWidget.init(@src(), "{d:0>3} ms into second", .{@as(u32, @intCast(left))}, .{});
        try mslabel.install();
        mslabel.processEvents();
        try mslabel.draw();
        mslabel.deinit();

        try dvui.label(@src(), "Estimate of frame overhead {d:6} us", .{dvui.currentWindow().loop_target_slop}, .{});

        if (dvui.timerDoneOrNone(mslabel.wd.id)) {
            const wait = 1000 * (1000 - left);
            try dvui.timer(mslabel.wd.id, wait);
        }
    }

    if (try dvui.expander(@src(), "Texture Frames", .{}, .{ .expand = .horizontal })) {
        var box = try dvui.box(@src(), .vertical, .{ .margin = .{ .x = 10 } });
        defer box.deinit();

        const pixel_data = [_]u8{ 0xff, 0xff, 0x00, 0xff, 0x00, 0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0xff, 0xff, 0x00, 0xff, 0xff };
        var pixels = pixel_data;

        // example of how to run frames at a certain fps
        const millis_per_frame = 500;
        if (dvui.timerDoneOrNone(box.data().id)) {
            const millis = @divFloor(dvui.frameTimeNS(), 1_000_000);
            const left = @as(i32, @intCast(@rem(millis, millis_per_frame)));
            const wait = 1000 * (millis_per_frame - left);
            try dvui.timer(box.data().id, wait);
        }

        const num_frames = 4;
        const frame: i32 = blk: {
            const millis = @divFloor(dvui.frameTimeNS(), 1_000_000);
            const left = @as(i32, @intCast(@rem(millis, num_frames * millis_per_frame)));
            break :blk @divTrunc(left, millis_per_frame);
        };

        try dvui.label(@src(), "frame: {d}", .{frame}, .{});

        std.mem.rotate(u8, &pixels, @intCast(frame * 4));

        const tex = dvui.textureCreate((&pixels).ptr, 2, 2, .nearest);
        dvui.textureDestroyLater(tex);

        var frame_box = try dvui.box(@src(), .horizontal, .{ .min_size_content = .{ .w = 50, .h = 50 } });
        try dvui.renderTexture(tex, frame_box.data().contentRectScale(), 0, .{});
        frame_box.deinit();
    }
}

fn makeLabels(src: std.builtin.SourceLocation, count: usize) !void {
    // we want to add labels to the widget that is the parent when makeLabels
    // is called, but since makeLabels is called twice in the same parent we'll
    // get duplicate IDs

    // virtualParent helps by being a parent for ID purposes but leaves the
    // layout to the previous parent
    var vp = try dvui.virtualParent(src, .{ .id_extra = count });
    defer vp.deinit();
    try dvui.label(@src(), "one", .{}, .{});
    try dvui.label(@src(), "two", .{}, .{});
}

pub fn debuggingErrors() !void {
    _ = try dvui.checkbox(@src(), &dvui.currentWindow().snap_to_pixels, "Snap to pixels", .{});
    try dvui.label(@src(), "on non-hdpi screens watch the window title \"DVUI Demo\"", .{}, .{ .margin = .{ .x = 10 } });
    try dvui.label(@src(), "- text, icons, and images rounded to nearest pixel", .{}, .{ .margin = .{ .x = 10 } });
    try dvui.label(@src(), "- text rendered at the closest smaller font (not stretched)", .{}, .{ .margin = .{ .x = 10 } });

    _ = try dvui.checkbox(@src(), &dvui.currentWindow().debug_touch_simulate_events, "Convert mouse events to touch", .{});
    try dvui.label(@src(), "- mouse drag will scroll", .{}, .{ .margin = .{ .x = 10 } });
    try dvui.label(@src(), "- mouse click in text layout/entry shows touch draggables and menu", .{}, .{ .margin = .{ .x = 10 } });

    if (try dvui.expander(@src(), "Virtual Parent (affects IDs but not layout)", .{}, .{ .expand = .horizontal })) {
        var hbox = try dvui.box(@src(), .horizontal, .{ .margin = .{ .x = 10 } });
        defer hbox.deinit();
        try dvui.label(@src(), "makeLabels twice:", .{}, .{});

        try makeLabels(@src(), 0);
        try makeLabels(@src(), 1);
    }

    if (try dvui.expander(@src(), "Duplicate id (expanding will log error)", .{}, .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        for (0..2) |i| {
            try dvui.label(@src(), "this should be highlighted (and error logged)", .{}, .{});
            try dvui.label(@src(), " - fix by passing .id_extra = <loop index>", .{}, .{ .id_extra = i });
        }

        if (try dvui.labelClick(@src(), "See https://github.com/david-vanderson/dvui/blob/master/readme-implementation.md#widget-ids", .{}, .{ .gravity_y = 0.5, .color_text = .{ .color = .{ .r = 0x35, .g = 0x84, .b = 0xe4 } } })) {
            try dvui.openURL("https://github.com/david-vanderson/dvui/blob/master/readme-implementation.md#widget-ids");
        }
    }

    if (try dvui.expander(@src(), "Scroll child after expanded child (will log error)", .{}, .{ .expand = .horizontal })) {
        var scroll = try dvui.scrollArea(@src(), .{}, .{ .min_size_content = .{ .w = 200, .h = 80 } });
        defer scroll.deinit();

        _ = try dvui.button(@src(), "Expanded\nChild\n", .{}, .{ .expand = .both });
        _ = try dvui.button(@src(), "Second Child", .{}, .{});
    }

    if (try dvui.expander(@src(), "Debug key bindings", .{}, .{ .expand = .horizontal })) {
        var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();

        const g = struct {
            const empty = [1]u8{0} ** 100;
            var latest_buf = empty;
            var latest_slice: []u8 = &.{};
        };

        const evts = dvui.events();
        for (evts) |e| {
            switch (e.evt) {
                .key => |ke| {
                    var it = dvui.currentWindow().keybinds.iterator();
                    while (it.next()) |kv| {
                        if (ke.matchKeyBind(kv.value_ptr.*)) {
                            g.latest_slice = try std.fmt.bufPrintZ(&g.latest_buf, "{s}", .{kv.key_ptr.*});
                        }
                    }
                },
                else => {},
            }
        }

        var tl = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });

        try tl.format("Latest matched keybinding: {s}\n\n", .{g.latest_slice}, .{});

        var any_overlaps = false;
        var outer = dvui.currentWindow().keybinds.iterator();
        while (outer.next()) |okv| {
            var inner = outer;
            while (inner.next()) |ikv| {
                const okb = okv.value_ptr.*;
                const ikb = ikv.value_ptr.*;
                if ((okb.shift == ikb.shift or okb.shift == null or ikb.shift == null) and
                    (okb.control == ikb.control or okb.control == null or ikb.control == null) and
                    (okb.alt == ikb.alt or okb.alt == null or ikb.alt == null) and
                    (okb.command == ikb.command or okb.command == null or ikb.command == null) and
                    (okb.key == ikb.key or okb.key == null or ikb.key == null))
                {
                    try tl.format("keybind \"{s}\" overlaps \"{s}\"\n", .{ okv.key_ptr.*, ikv.key_ptr.* }, .{});
                    any_overlaps = true;
                }
            }
        }

        if (!any_overlaps) {
            try tl.addText("No keybind overlaps found.\n", .{});
        }

        try tl.addText("\nCurrent keybinds:\n", .{});
        outer = dvui.currentWindow().keybinds.iterator();
        while (outer.next()) |okv| {
            try tl.format("\n{s}\n    ", .{okv.key_ptr.*}, .{});
            if (okv.value_ptr.control) |ctrl| {
                try tl.format("{s}ctrl ", .{if (ctrl) "" else "!"}, .{});
            }
            if (okv.value_ptr.command) |command| {
                try tl.format("{s}cmd ", .{if (command) "" else "!"}, .{});
            }
            if (okv.value_ptr.alt) |alt| {
                try tl.format("{s}alt ", .{if (alt) "" else "!"}, .{});
            }
            if (okv.value_ptr.shift) |shift| {
                try tl.format("{s}shift ", .{if (shift) "" else "!"}, .{});
            }
            if (okv.value_ptr.key) |key| {
                try tl.format("{s}\n", .{@tagName(key)}, .{});
            } else {
                try tl.addText("\n", .{});
            }
        }
        tl.deinit();
    }

    if (try dvui.expander(@src(), "Show Font Atlases", .{}, .{ .expand = .horizontal })) {
        try dvui.debugFontAtlases(@src(), .{});
    }

    if (try dvui.button(@src(), "Stroke Test", .{}, .{})) {
        StrokeTest.show = true;
    }

    if (StrokeTest.show) {
        try show_stroke_test_window();
    }
}

pub fn dialogDirect() !void {
    const data = struct {
        var extra_stuff: bool = false;
    };
    var dialog_win = try dvui.floatingWindow(@src(), .{ .modal = false, .open_flag = &show_dialog, .initial_max_size = .{ .w = 500 } }, .{});
    defer dialog_win.deinit();

    try dvui.windowHeader("Dialog", "", &show_dialog);
    try dvui.label(@src(), "Asking a Question", .{}, .{ .font_style = .title_4 });
    try dvui.label(@src(), "This dialog is being shown in a direct style, controlled entirely in user code.", .{}, .{});

    if (try dvui.button(@src(), "Toggle extra stuff and fit window", .{}, .{})) {
        data.extra_stuff = !data.extra_stuff;
        dialog_win.autoSize(.{ .w = 500 });
    }

    if (data.extra_stuff) {
        try dvui.label(@src(), "This is some extra stuff\nwith a multi-line label\nthat has 3 lines", .{}, .{ .margin = .{ .x = 4 } });

        var tl = try dvui.textLayout(@src(), .{}, .{});
        try tl.addText("Here is a textLayout with a bunch of text in it that would overflow the right edge but we are calling autoSize() with a max width", .{});
        tl.deinit();
    }

    {
        _ = try dvui.spacer(@src(), .{}, .{ .expand = .vertical });
        var hbox = try dvui.box(@src(), .horizontal, .{ .gravity_x = 1.0 });
        defer hbox.deinit();

        if (try dvui.button(@src(), "Yes", .{}, .{})) {
            dialog_win.close(); // can close the dialog this way
        }

        if (try dvui.button(@src(), "No", .{}, .{})) {
            show_dialog = false; // can close by not running this code anymore
        }
    }
}

const icon_names: [@typeInfo(entypo).Struct.decls.len][]const u8 = blk: {
    var blah: [@typeInfo(entypo).Struct.decls.len][]const u8 = undefined;
    for (@typeInfo(entypo).Struct.decls, 0..) |d, i| {
        blah[i] = d.name;
    }
    break :blk blah;
};

const icon_fields: [@typeInfo(entypo).Struct.decls.len][]const u8 = blk: {
    var blah: [@typeInfo(entypo).Struct.decls.len][]const u8 = undefined;
    for (@typeInfo(entypo).Struct.decls, 0..) |d, i| {
        blah[i] = @field(entypo, d.name);
    }
    break :blk blah;
};

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

    for (icon_names, icon_fields, 0..) |name, field, i| {
        if (cursor <= (visibleRect.y + visibleRect.h) and (cursor + IconBrowser.row_height) >= visibleRect.y) {
            const r = Rect{ .x = 0, .y = cursor, .w = 0, .h = IconBrowser.row_height };
            var iconbox = try dvui.box(@src(), .horizontal, .{ .id_extra = i, .expand = .horizontal, .rect = r });

            var buf: [100]u8 = undefined;
            const text = try std.fmt.bufPrint(&buf, "entypo.{s}", .{name});
            if (try dvui.buttonIcon(@src(), text, field, .{}, .{ .min_size_content = .{ .h = 20 } })) {
                // TODO: copy full buttonIcon code line into clipboard and show toast
            }
            try dvui.labelNoFmt(@src(), text, .{ .gravity_y = 0.5 });

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

pub fn show_stroke_test_window() !void {
    var win = try dvui.floatingWindow(@src(), .{ .rect = &StrokeTest.show_rect, .open_flag = &StrokeTest.show }, .{});
    defer win.deinit();
    try dvui.windowHeader("Stroke Test", "", &StrokeTest.show);

    try dvui.label(@src(), "Stroke Test", .{}, .{});
    _ = try dvui.checkbox(@src(), &stroke_test_closed, "Closed", .{});
    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.label(@src(), "Endcap Style", .{}, .{});

        if (try dvui.radio(@src(), StrokeTest.endcap_style == .none, "None", .{})) {
            StrokeTest.endcap_style = .none;
        }

        if (try dvui.radio(@src(), StrokeTest.endcap_style == .square, "Square", .{})) {
            StrokeTest.endcap_style = .square;
        }
    }

    var st = StrokeTest{};
    try st.install(@src(), .{ .min_size_content = .{ .w = 400, .h = 400 }, .expand = .both });
    st.deinit();
}

var stroke_test_closed: bool = false;

pub const StrokeTest = struct {
    const Self = @This();
    var show: bool = false;
    var show_rect = dvui.Rect{};
    var pointsArray: [10]dvui.Point = [1]dvui.Point{.{}} ** 10;
    var points: []dvui.Point = pointsArray[0..0];
    var dragi: ?usize = null;
    var thickness: f32 = 1.0;
    var endcap_style: dvui.EndCapStyle = .none;

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
        try dvui.pathStroke(stroke_test_closed, rs.s * thickness, StrokeTest.endcap_style, stroke_color);
    }

    pub fn widget(self: *Self) dvui.Widget {
        return dvui.Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
    }

    pub fn data(self: *Self) *dvui.WidgetData {
        return &self.wd;
    }

    pub fn rectFor(self: *Self, id: u32, min_size: dvui.Size, e: dvui.Options.Expand, g: dvui.Options.Gravity) dvui.Rect {
        _ = id;
        return dvui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
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

    pub fn deinit(self: *Self) void {
        self.wd.minSizeSetAndRefresh();
        self.wd.minSizeReportToParent();

        dvui.parentReset(self.wd.id, self.wd.parent);
    }
};
