//! ![demo](Examples-demo.png)

const builtin = @import("builtin");
const std = @import("std");
const dvui = @import("dvui.zig");

const DialogCallAfterFn = dvui.DialogCallAfterFn;
const Options = dvui.Options;
const Point = dvui.Point;
const Rect = dvui.Rect;
const ScrollInfo = dvui.ScrollInfo;
const Size = dvui.Size;
const entypo = dvui.entypo;
const ButtonWidget = dvui.ButtonWidget;
const FloatingWindowWidget = dvui.FloatingWindowWidget;
const LabelWidget = dvui.LabelWidget;
const TextLayoutWidget = dvui.TextLayoutWidget;
const GridWidget = dvui.GridWidget;

const enums = dvui.enums;

const zig_favicon = @embedFile("zig-favicon.png");
const zig_svg = @embedFile("zig-mark.svg");

pub var show_demo_window: bool = false;
var frame_counter: u64 = 0;
var checkbox_gray: bool = true;
var checkbox_bool: bool = false;
const RadioChoice = enum(u8) {
    one = 1,
    two,
    _,
};
var radio_choice: RadioChoice = @enumFromInt(0);
var icon_image_size_extra: f32 = 0;
var icon_image_rotation: f32 = 0;
var icon_browser_show: bool = false;
var slider_vector_array = [_]f32{ 0, 1, 2 };
var slider_val: f32 = 0.0;
var slider_entry_val: f32 = 0.05;
var slider_entry_min: bool = true;
var slider_entry_max: bool = true;
var slider_entry_interval: bool = true;
var slider_entry_vector: bool = false;
var slider_entry_label: bool = false;
var text_entry_buf = std.mem.zeroes([50]u8);
var text_entry_password_buf = std.mem.zeroes([30]u8);
var text_entry_password_buf_obf_enable: bool = true;
var text_entry_multiline_allocator_buf: [1000]u8 = undefined;
var text_entry_multiline_fba = std.heap.FixedBufferAllocator.init(&text_entry_multiline_allocator_buf);
var text_entry_multiline_buf: []u8 = &.{};
var text_entry_multiline_initialized = false;
var text_entry_multiline_break = false;
var dropdown_val: usize = 1;
var layout_margin: Rect = Rect.all(4);
var layout_border: Rect = Rect.all(0);
var layout_padding: Rect = Rect.all(4);
var layout_gravity_x: f32 = 0.5;
var layout_gravity_y: f32 = 0.5;
var layout_rotation: f32 = 0;
var layout_corner_radius: Rect = Rect.all(5);
var layout_flex_content_justify: dvui.FlexBoxWidget.ContentPosition = .center;
var layout_expand: dvui.Options.Expand = .none;
var show_dialog: bool = false;
var scale_val: f32 = 1.0;
var line_height_factor: f32 = 1.2;
var backbox_color: dvui.Color = .black;
var hsluv_hsl: dvui.Color.HSLuv = .fromColor(.black);
var hsv_color: dvui.Color.HSV = .fromColor(.black);
var animating_window_show: bool = false;
var animating_window_closing: bool = false;
var animating_window_rect = Rect{ .x = 100, .y = 100, .w = 300, .h = 200 };
var paned_collapsed_width: f32 = 400;

var progress_mutex = std.Thread.Mutex{};
var progress_val: f32 = 0.0;

const AnimatingDialog = struct {
    pub fn dialogDisplay(id: dvui.WidgetId) !void {
        const modal = dvui.dataGet(null, id, "_modal", bool) orelse unreachable;
        const title = dvui.dataGetSlice(null, id, "_title", []u8) orelse unreachable;
        const message = dvui.dataGetSlice(null, id, "_message", []u8) orelse unreachable;
        const callafter = dvui.dataGet(null, id, "_callafter", DialogCallAfterFn);
        const duration = dvui.dataGet(null, id, "duration", i32) orelse unreachable;
        const easing = dvui.dataGet(null, id, "easing", *const dvui.easing.EasingFn) orelse unreachable;

        // once we record a response, refresh it until we close
        _ = dvui.dataGet(null, id, "response", enums.DialogResponse);

        var win = FloatingWindowWidget.init(@src(), .{ .modal = modal }, .{ .id_extra = id.asUsize(), .max_size_content = .width(300) });

        if (dvui.firstFrame(win.data().id)) {
            dvui.animation(win.data().id, "rect_percent", .{ .start_val = 0.0, .end_val = 1.0, .end_time = duration, .easing = easing });
        }

        const winHeight = win.data().rect.h;
        var winHeight_changed = false;

        if (dvui.animationGet(win.data().id, "rect_percent")) |a| {
            win.data().rect.h *= a.value();
            winHeight_changed = true;

            // mucking with the window size can screw up the windows auto sizing, so force it
            win.autoSize();

            if (a.done() and a.end_val == 0) {
                dvui.dialogRemove(id);

                if (callafter) |ca| {
                    const response = dvui.dataGet(null, id, "response", enums.DialogResponse) orelse {
                        std.log.debug("Error: no response for dialog {x}\n", .{id});
                        return;
                    };
                    ca(id, response) catch |err| {
                        std.log.debug("AnimationDialogs callafter got {!}", .{err});
                    };
                }

                return;
            }
        }

        win.install();
        defer win.deinit();
        win.processEventsBefore();
        win.drawBackground();

        var closing: bool = false;

        var header_openflag = true;
        win.dragAreaSet(dvui.windowHeader(title, "", &header_openflag));
        if (!header_openflag) {
            closing = true;
            dvui.dataSet(null, id, "response", enums.DialogResponse.cancel);
        }

        var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false });
        tl.addText(message, .{});
        tl.deinit();

        if (dvui.button(@src(), "Ok", .{}, .{ .gravity_x = 0.5, .gravity_y = 1.0, .tab_index = 1 })) {
            closing = true;
            dvui.dataSet(null, id, "response", enums.DialogResponse.ok);
        }

        // restore saved win rect so our change is not persisted to next frame
        if (winHeight_changed) {
            win.data().rect.h = winHeight;
        }

        if (closing) {
            dvui.animation(win.data().id, "rect_percent", .{ .start_val = 1.0, .end_val = 0.0, .end_time = duration, .easing = easing });
        }
    }

    pub fn after(id: dvui.WidgetId, response: enums.DialogResponse) !void {
        _ = id;
        std.log.debug("You clicked \"{s}\"", .{@tagName(response)});
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
            const dw = ss.w * a.value();
            const dh = ss.h * a.value();
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

var calculation: f64 = 0;
var calculand: ?f64 = null;
var active_op: ?u8 = null;
var digits_after_dot: f64 = 0;
/// ![image](Examples-calculator.png)
pub fn calculator() void {
    var vbox = dvui.box(@src(), .vertical, .{});
    defer vbox.deinit();

    const loop_labels = [_]u8{ 'C', 'N', '%', '/', '7', '8', '9', 'x', '4', '5', '6', '-', '1', '2', '3', '+', '0', '.', '=' };
    const loop_count = @sizeOf(@TypeOf(loop_labels)) / @sizeOf(@TypeOf(loop_labels[0]));

    dvui.label(@src(), "{d}", .{if (calculand) |val| val else calculation}, .{ .gravity_x = 1.0 });

    for (0..5) |row_i| {
        var b = dvui.box(@src(), .horizontal, .{ .min_size_content = .{ .w = 110 }, .id_extra = row_i });
        defer b.deinit();

        for (row_i * 4..(row_i + 1) * 4) |i| {
            if (i >= loop_count) continue;
            const letter = loop_labels[i];

            var opts = dvui.ButtonWidget.defaults.min_sizeM(3, 1);
            if (letter == '0') {
                const extra_space = opts.padSize(.{}).w;
                opts.min_size_content.?.w *= 2; // be twice as wide as normal
                opts.min_size_content.?.w += extra_space; // add the extra space between 2 buttons
            }
            if (dvui.button(@src(), &[_]u8{letter}, .{}, opts.override(.{ .id_extra = letter }))) {
                if (letter == 'C') {
                    calculation = 0;
                    calculand = null;
                    active_op = null;
                    digits_after_dot = 0;
                }

                if (letter == '/') {
                    active_op = '/';
                    digits_after_dot = 0;
                }
                if (letter == 'x') {
                    active_op = 'x';
                    digits_after_dot = 0;
                }
                if (letter == '-') {
                    active_op = '-';
                    digits_after_dot = 0;
                }
                if (letter == '+') {
                    active_op = '+';
                    digits_after_dot = 0;
                }
                if (letter == '.') digits_after_dot = 1;

                if (letter == 'N') calculation = -calculation;
                if (letter == '%') calculation /= 100;

                if (active_op == null) {
                    if (letter >= '0' and letter <= '9') {
                        const letterDigit: f32 = @floatFromInt(letter - '0');

                        if (digits_after_dot > 0) {
                            calculation += letterDigit / @exp(@log(10.0) * digits_after_dot);
                            digits_after_dot += 1;
                        } else {
                            calculation *= 10;
                            calculation += letterDigit;
                        }
                    }
                    if (letter == '.') {}
                }

                if (active_op != null) {
                    if (letter >= '0' and letter <= '9') {
                        if (calculand == null) calculand = 0.0;
                        const letterDigit: f64 = @floatFromInt(letter - '0');
                        if (digits_after_dot > 0) {
                            calculand.? += letterDigit / @exp(@log(10.0) * digits_after_dot);
                            digits_after_dot += 1;
                        } else {
                            calculand.? *= 10;
                            calculand.? += letterDigit;
                        }
                    }
                    if (letter == '=') {
                        if (calculand) |val| {
                            if (active_op == '/') calculation /= val;
                            if (active_op == '-') calculation -= val;
                            if (active_op == '+') calculation += val;
                            if (active_op == 'x') calculation *= val;
                        }
                        active_op = null;
                        calculand = null;
                        digits_after_dot = 0;
                    }
                }
            }
        }
    }
}

pub const demoKind = enum {
    basic_widgets,
    calculator,
    text_entry,
    styling,
    layout,
    text_layout,
    plots,
    reorderable,
    menus,
    scrolling,
    scroll_canvas,
    dialogs,
    animations,
    grid,
    struct_ui,
    debugging,

    pub fn name(self: demoKind) []const u8 {
        return switch (self) {
            .basic_widgets => "Basic Widgets",
            .calculator => "Calculator",
            .text_entry => "Text Entry",
            .styling => "Styling",
            .layout => "Layout",
            .text_layout => "Text Layout",
            .plots => "Plots",
            .reorderable => "Reorder / Tree",
            .menus => "Menus / Focus",
            .scrolling => "Scrolling",
            .scroll_canvas => "Scroll Canvas",
            .dialogs => "Dialogs / Toasts",
            .animations => "Animations",
            .struct_ui => "Struct UI\n(Experimental)",
            .debugging => "Debugging",
            .grid => "Grid",
        };
    }

    pub fn scaleOffset(self: demoKind) struct { scale: f32, offset: dvui.Point } {
        return switch (self) {
            .basic_widgets => .{ .scale = 0.45, .offset = .{} },
            .calculator => .{ .scale = 0.45, .offset = .{} },
            .text_entry => .{ .scale = 0.45, .offset = .{} },
            .styling => .{ .scale = 0.45, .offset = .{} },
            .layout => .{ .scale = 0.45, .offset = .{ .x = -50 } },
            .text_layout => .{ .scale = 0.45, .offset = .{} },
            .plots => .{ .scale = 0.45, .offset = .{} },
            .reorderable => .{ .scale = 0.45, .offset = .{} },
            .menus => .{ .scale = 0.45, .offset = .{} },
            .scrolling => .{ .scale = 0.45, .offset = .{ .x = -150, .y = 0 } },
            .scroll_canvas => .{ .scale = 0.35, .offset = .{ .y = -120 } },
            .dialogs => .{ .scale = 0.45, .offset = .{} },
            .animations => .{ .scale = 0.45, .offset = .{} },
            .struct_ui => .{ .scale = 0.45, .offset = .{} },
            .debugging => .{ .scale = 0.45, .offset = .{} },
            .grid => .{ .scale = 0.45, .offset = .{} },
        };
    }
};

pub var demo_active: demoKind = .basic_widgets;

pub const demo_window_tag = "dvui_example_window";

pub fn demo() void {
    if (!show_demo_window) {
        return;
    }

    const width = 600;

    var float = dvui.floatingWindow(@src(), .{ .open_flag = &show_demo_window }, .{ .min_size_content = .{ .w = width, .h = 400 }, .max_size_content = .width(width), .tag = demo_window_tag });
    defer float.deinit();

    // pad the fps label so that it doesn't trigger refresh when the number
    // changes widths
    var buf: [100]u8 = undefined;
    const fps_str = std.fmt.bufPrint(&buf, "{d:0>3.0} fps | frame no {d}", .{ dvui.FPS(), frame_counter }) catch unreachable;
    frame_counter += 1;
    float.dragAreaSet(dvui.windowHeader("DVUI Demo", fps_str, &show_demo_window));

    dvui.toastsShow(float.data());

    var scaler = dvui.scale(@src(), .{ .scale = &scale_val }, .{ .expand = .both });
    defer scaler.deinit();

    var paned = dvui.paned(@src(), .{ .direction = .horizontal, .collapsed_size = width + 1 }, .{ .expand = .both, .background = false, .min_size_content = .{ .h = 100 } });
    //if (dvui.firstFrame(paned.data().id)) {
    //    paned.split_ratio = 0;
    //}
    if (paned.showFirst()) {
        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .background = false });
        defer scroll.deinit();

        var invalidate: bool = false;
        {
            var hbox = dvui.box(@src(), .horizontal, .{});
            defer hbox.deinit();
            if (dvui.button(@src(), "Debug Window", .{}, .{})) {
                dvui.toggleDebugWindow();
            }

            if (dvui.Theme.picker(@src(), .{})) {
                invalidate = true;
            }

            if (dvui.button(@src(), "Zoom In", .{}, .{})) {
                scale_val = @round(dvui.themeGet().font_body.size * scale_val + 1.0) / dvui.themeGet().font_body.size;
                invalidate = true;
            }

            if (dvui.button(@src(), "Zoom Out", .{}, .{})) {
                scale_val = @round(dvui.themeGet().font_body.size * scale_val - 1.0) / dvui.themeGet().font_body.size;
                invalidate = true;
            }
        }

        var fbox = dvui.flexbox(@src(), .{}, .{ .expand = .both, .background = true, .min_size_content = .width(width), .corner_radius = .{ .w = 5, .h = 5 } });
        defer fbox.deinit();

        inline for (0..@typeInfo(demoKind).@"enum".fields.len) |i| {
            const e = @as(demoKind, @enumFromInt(i));
            var bw = dvui.ButtonWidget.init(@src(), .{}, .{ .id_extra = i, .border = Rect.all(1), .background = true, .min_size_content = dvui.Size.all(120), .max_size_content = .size(dvui.Size.all(120)), .margin = Rect.all(5), .color_fill = .fill, .tag = "demo_button_" ++ @tagName(e) });
            bw.install();
            bw.processEvents();
            bw.drawBackground();

            const use_cache = true;
            var cache: *dvui.CacheWidget = undefined;
            if (use_cache) {
                cache = dvui.cache(@src(), .{ .invalidate = invalidate }, .{ .expand = .both });
            }
            if (!use_cache or cache.uncached()) {
                const box = dvui.box(@src(), .vertical, .{ .expand = .both });
                defer box.deinit();

                var options: dvui.Options = .{ .gravity_x = 0.5, .gravity_y = 1.0 };
                if (dvui.captured(bw.data().id)) options = options.override(.{ .color_text = .{ .color = options.color(.text_press) } });

                dvui.label(@src(), "{s}", .{e.name()}, options);

                var s = e.scaleOffset().scale;
                const demo_scaler = dvui.scale(@src(), .{ .scale = &s }, .{ .expand = .both });
                defer demo_scaler.deinit();

                const oldclip = dvui.clip(demo_scaler.data().contentRectScale().r);
                defer dvui.clipSet(oldclip);

                const box2 = dvui.box(@src(), .vertical, .{ .rect = dvui.Rect.fromPoint(e.scaleOffset().offset).toSize(.{ .w = 400, .h = 1000 }) });
                defer box2.deinit();

                switch (e) {
                    .basic_widgets => basicWidgets(),
                    .calculator => calculator(),
                    .text_entry => textEntryWidgets(float.data().id),
                    .styling => styling(),
                    .layout => layout(),
                    .text_layout => layoutText(),
                    .plots => plots(),
                    .reorderable => reorderLists(),
                    .menus => menus(),
                    .scrolling => scrolling(),
                    .scroll_canvas => scrollCanvas(),
                    .dialogs => dialogs(float.data().id),
                    .animations => animations(),
                    .struct_ui => structUI(),
                    .debugging => debuggingErrors(),
                    .grid => grids(0),
                }
            }

            if (use_cache) {
                cache.deinit();
            }

            bw.drawFocus();

            if (bw.clicked()) {
                demo_active = e;
                if (paned.collapsed()) {
                    paned.animateSplit(0.0);
                }
            }
            bw.deinit();
        }
    }

    if (paned.showSecond()) {
        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .background = false });
        defer scroll.deinit();

        var hbox = dvui.box(@src(), .horizontal, .{});

        if (paned.collapsed() and dvui.button(@src(), "Back to Demos", .{}, .{ .min_size_content = .{ .h = 30 }, .tag = "dvui_demo_window_back" })) {
            paned.animateSplit(1.0);
        }

        dvui.label(@src(), "{s}", .{demo_active.name()}, .{ .font_style = .title_2, .gravity_y = 0.5 });
        const header_height = hbox.data().rect.h;
        hbox.deinit();

        var vbox = dvui.box(@src(), .vertical, .{ .expand = .both, .padding = Rect.all(4) });
        defer vbox.deinit();

        switch (demo_active) {
            .basic_widgets => basicWidgets(),
            .calculator => calculator(),
            .text_entry => textEntryWidgets(float.data().id),
            .styling => styling(),
            .layout => layout(),
            .text_layout => layoutText(),
            .plots => plots(),
            .reorderable => reorderLists(),
            .menus => menus(),
            .scrolling => scrolling(),
            .scroll_canvas => scrollCanvas(),
            .dialogs => dialogs(float.data().id),
            .animations => animations(),
            .struct_ui => structUI(),
            .debugging => debuggingErrors(),
            .grid => grids(scroll.si.viewport.h - header_height - 10),
        }
    }

    paned.deinit();

    if (show_dialog) {
        dialogDirect();
    }

    if (icon_browser_show) {
        icon_browser(@src(), &icon_browser_show, "entypo", entypo);
    }

    if (StrokeTest.show) {
        show_stroke_test_window();
    }
}

/// ![image](Examples-struct_ui.png)
pub fn structUI() void {
    var b = dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
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
        an_array: [4]u8 = .{ 1, 2, 3, 4 },

        var instance: @This() = .{ .a_slice = &mut_array, .a_ptr = &ptr };
    };

    dvui.label(@src(), "Show UI elements for all fields of a struct:", .{}, .{});
    {
        dvui.structEntryAlloc(@src(), dvui.currentWindow().gpa, Top, &Top.instance, .{ .margin = .{ .x = 10 } });
    }

    if (dvui.expander(@src(), "Edit Current Theme", .{}, .{ .expand = .horizontal })) {
        themeEditor();
    }
}

/// ![image](Examples-themeEditor.png)
pub fn themeEditor() void {
    var b2 = dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
    defer b2.deinit();

    const color_field_options = dvui.StructFieldOptions(dvui.Color){ .fields = .{
        .r = .{ .min = 0, .max = 255, .widget_type = .slider },
        .g = .{ .min = 0, .max = 255, .widget_type = .slider },
        .b = .{ .min = 0, .max = 255, .widget_type = .slider },
        .a = .{ .disabled = true },
    } };

    dvui.structEntryEx(@src(), "dvui.Theme", dvui.Theme, dvui.themeGet(), .{
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

pub fn themeSerialization() void {
    var serialize_box = dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
    defer serialize_box.deinit();

    dvui.labelNoFmt(@src(), "TODO: demonstrate loading a quicktheme here", .{}, .{});
}

/// ![image](Examples-basic_widgets.png)
pub fn basicWidgets() void {
    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Label", .{}, .{ .gravity_y = 0.5 });

        dvui.labelEx(@src(), "Multi-line\nLabel", .{}, .{ .align_x = 0.5 }, .{ .gravity_y = 0.5 });

        _ = dvui.button(@src(), "Button", .{}, .{ .gravity_y = 0.5 });
        _ = dvui.button(@src(), "Multi-line\nButton", .{}, .{});

        {
            var vbox = dvui.box(@src(), .vertical, .{});
            defer vbox.deinit();

            {
                var color: ?dvui.Options.ColorOrName = null;
                if (checkbox_gray) {
                    // blend text and control colors
                    color = .{ .color = dvui.Color.average(dvui.themeGet().color_text, dvui.themeGet().color_fill_control) };
                }
                var bw = dvui.ButtonWidget.init(@src(), .{}, .{ .color_text = color });
                defer bw.deinit();
                bw.install();
                bw.processEvents();
                bw.drawBackground();
                bw.drawFocus();

                const opts = bw.data().options.strip().override(.{ .gravity_y = 0.5 });

                var bbox = dvui.box(@src(), .horizontal, opts);
                defer bbox.deinit();

                dvui.icon(
                    @src(),
                    "cycle",
                    entypo.cycle,
                    .{},
                    opts,
                );
                _ = dvui.spacer(@src(), .{ .min_size_content = .width(4) });
                dvui.labelNoFmt(@src(), "Icon+Gray", .{}, opts);

                if (bw.clicked()) {
                    dvui.toast(@src(), .{ .message = "This button is grayed out\nbut still clickable." });
                }
            }

            _ = dvui.checkbox(@src(), &checkbox_gray, "Gray", .{});
        }
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Link:", .{}, .{ .gravity_y = 0.5 });

        if (dvui.labelClick(@src(), "https://david-vanderson.github.io/", .{}, .{}, .{ .gravity_y = 0.5, .color_text = .{ .color = .{ .r = 0x35, .g = 0x84, .b = 0xe4 } } })) {
            _ = dvui.openURL("https://david-vanderson.github.io/");
        }

        if (dvui.labelClick(@src(), "docs", .{}, .{}, .{ .gravity_y = 0.5, .margin = .{ .x = 10 }, .color_text = .{ .color = .{ .r = 0x35, .g = 0x84, .b = 0xe4 } } })) {
            _ = dvui.openURL("https://david-vanderson.github.io/docs");
        }
    }

    _ = dvui.checkbox(@src(), &checkbox_bool, "Checkbox", .{});

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Text Entry", .{}, .{ .gravity_y = 0.5 });
        var te = dvui.textEntry(@src(), .{}, .{});
        te.deinit();
    }

    inline for (@typeInfo(RadioChoice).@"enum".fields, 0..) |field, i| {
        if (dvui.radio(@src(), radio_choice == @as(RadioChoice, @enumFromInt(field.value)), "Radio " ++ field.name, .{ .id_extra = i })) {
            radio_choice = @enumFromInt(field.value);
        }
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        const entries = [_][]const u8{ "First", "Second", "Third is a really long one that doesn't fit" };

        _ = dvui.dropdown(@src(), &entries, &dropdown_val, .{ .min_size_content = .{ .w = 100 }, .gravity_y = 0.5 });

        dropdownAdvanced();
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{ .expand = .horizontal, .min_size_content = .{ .h = 40 } });
        defer hbox.deinit();

        dvui.label(@src(), "Sliders", .{}, .{ .gravity_y = 0.5 });
        _ = dvui.slider(@src(), .horizontal, &slider_val, .{ .expand = .horizontal, .gravity_y = 0.5, .corner_radius = dvui.Rect.all(100) });
        _ = dvui.slider(@src(), .vertical, &slider_val, .{ .expand = .vertical, .min_size_content = .{ .w = 10 }, .corner_radius = dvui.Rect.all(100) });
        dvui.label(@src(), "Value: {d:2.2}", .{slider_val}, .{ .gravity_y = 0.5 });
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Slider Entry", .{}, .{ .gravity_y = 0.5 });
        if (!slider_entry_vector) {
            var custom_label: ?[]u8 = null;
            if (slider_entry_label) {
                const whole = @round(slider_entry_val);
                const part = @round((slider_entry_val - whole) * 100);
                custom_label = std.fmt.allocPrint(dvui.currentWindow().lifo(), "{d} and {d}p", .{ whole, part }) catch null;
            }
            defer if (custom_label) |cl| dvui.currentWindow().lifo().free(cl);
            _ = dvui.sliderEntry(@src(), "val: {d:0.3}", .{ .value = &slider_entry_val, .min = (if (slider_entry_min) 0 else null), .max = (if (slider_entry_max) 1 else null), .interval = (if (slider_entry_interval) 0.1 else null), .label = custom_label }, .{ .gravity_y = 0.5 });
            dvui.label(@src(), "(enter, ctrl-click or touch-tap)", .{}, .{ .gravity_y = 0.5 });
        } else {
            _ = dvui.sliderVector(@src(), "{d:0.2}", 3, &slider_vector_array, .{ .min = (if (slider_entry_min) 0 else null), .max = (if (slider_entry_max) 1 else null), .interval = (if (slider_entry_interval) 0.1 else null) }, .{});
        }
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{ .padding = .{ .x = 10 } });
        defer hbox.deinit();

        _ = dvui.checkbox(@src(), &slider_entry_min, "Min", .{});
        _ = dvui.checkbox(@src(), &slider_entry_max, "Max", .{});
        _ = dvui.checkbox(@src(), &slider_entry_interval, "Interval", .{});
        _ = dvui.checkbox(@src(), &slider_entry_vector, "Vector", .{});
        _ = dvui.checkbox(@src(), &slider_entry_label, "Custom Label", .{});
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .height(4) });

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Raster Images", .{}, .{ .gravity_y = 0.5 });

        const image_source: dvui.ImageSource = .{ .imageFile = .{ .bytes = zig_favicon, .name = "zig favicon" } };
        const imgsize = dvui.imageSize(image_source) catch dvui.Size.all(50);
        _ = dvui.image(@src(), .{ .source = image_source }, .{
            .gravity_y = 0.5,
            .min_size_content = .{ .w = imgsize.w + icon_image_size_extra, .h = imgsize.h + icon_image_size_extra },
            .rotation = icon_image_rotation,
        });
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Svg Images", .{}, .{ .gravity_y = 0.5 });

        const zig_tvg_bytes = if (dvui.dataGetSlice(null, hbox.data().id, "_zig_tvg", []u8)) |tvg| tvg else blk: {
            // Could fail on OutOfMemory, but then the dataGetSlice would also panic
            const zig_tvg_bytes = dvui.svgToTvg(dvui.currentWindow().arena(), zig_svg) catch unreachable;
            defer dvui.currentWindow().arena().free(zig_tvg_bytes);
            dvui.dataSetSlice(null, hbox.data().id, "_zig_tvg", zig_tvg_bytes);
            break :blk dvui.dataGetSlice(null, hbox.data().id, "_zig_tvg", []u8).?;
        };

        const icon_opts = dvui.Options{ .gravity_y = 0.5, .min_size_content = .{ .h = 16 + icon_image_size_extra }, .rotation = icon_image_rotation };
        dvui.icon(@src(), "zig favicon", zig_tvg_bytes, .{}, icon_opts);
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Icons", .{}, .{ .gravity_y = 0.5 });

        const icon_opts = dvui.Options{ .gravity_y = 0.5, .min_size_content = .{ .h = 16 + icon_image_size_extra }, .rotation = icon_image_rotation };
        dvui.icon(@src(), "cycle", entypo.cycle, .{}, icon_opts);
        dvui.icon(@src(), "aircraft", entypo.aircraft, .{}, icon_opts);
        dvui.icon(@src(), "notes", entypo.beamed_note, .{}, icon_opts);

        if (dvui.button(@src(), "Icon Browser", .{}, .{ .gravity_y = 0.5 })) {
            icon_browser_show = true;
        }
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Resize Rotate Icons/Images", .{}, .{ .gravity_y = 0.5 });

        if (dvui.buttonIcon(
            @src(),
            "plus",
            entypo.plus,
            .{},
            .{},
            .{ .gravity_y = 0.5 },
        )) {
            icon_image_size_extra += 1;
        }

        if (dvui.buttonIcon(
            @src(),
            "minus",
            entypo.minus,
            .{},
            .{},
            .{ .gravity_y = 0.5 },
        )) {
            icon_image_size_extra = @max(0, icon_image_size_extra - 1);
        }

        if (dvui.buttonIcon(
            @src(),
            "cw",
            entypo.cw,
            .{},
            .{},
            .{ .gravity_y = 0.5 },
        )) {
            icon_image_rotation = icon_image_rotation + 5 * std.math.pi / 180.0;
        }

        if (dvui.buttonIcon(
            @src(),
            "ccw",
            entypo.ccw,
            .{},
            .{},
            .{ .gravity_y = 0.5 },
        )) {
            icon_image_rotation = icon_image_rotation - 5 * std.math.pi / 180.0;
        }
    }
}

pub fn dropdownAdvanced() void {
    const g = struct {
        var choice: ?usize = null;
    };

    var dd = dvui.DropdownWidget.init(@src(), .{ .selected_index = g.choice }, .{ .min_size_content = .{ .w = 100 } });
    dd.install();

    // Here's what is shown when the dropdown is not dropped
    {
        var hbox2 = dvui.box(@src(), .horizontal, .{ .expand = .both });
        dvui.icon(
            @src(),
            "air",
            entypo.air,
            .{},
            .{ .gravity_y = 0.5 },
        );

        if (g.choice) |c| {
            dvui.label(@src(), "Dropdown Choice {d}", .{c}, .{ .gravity_y = 0.5, .padding = .{ .x = 6, .w = 6 } });
        } else {
            dvui.label(@src(), "Advanced Dropdown", .{}, .{ .gravity_y = 0.5, .padding = .{ .x = 6, .w = 6 } });
        }

        dvui.icon(
            @src(),
            "dropdown_triangle",
            entypo.chevron_small_down,
            .{},
            .{ .gravity_y = 0.5 },
        );

        hbox2.deinit();
    }

    if (dd.dropped()) {
        // The dropdown is dropped, now add all the choices
        {
            var mi = dd.addChoice();
            defer mi.deinit();

            var hbox2 = dvui.box(@src(), .horizontal, .{ .expand = .both });
            defer hbox2.deinit();

            var opts: Options = if (mi.show_active) dvui.themeGet().style_accent else .{};

            dvui.icon(
                @src(),
                "aircraft landing",
                entypo.aircraft_landing,
                .{},
                opts.override(.{ .gravity_y = 0.5 }),
            );
            dvui.labelNoFmt(@src(), "icon with text", .{}, opts.override(.{ .padding = .{ .x = 6 } }));

            if (mi.activeRect()) |_| {
                dd.close();
                g.choice = 0;
            }
        }

        if (dd.addChoiceLabel("just text")) {
            g.choice = 1;
        }

        {
            var mi = dd.addChoice();
            defer mi.deinit();

            var vbox = dvui.box(@src(), .vertical, .{ .expand = .both });
            defer vbox.deinit();

            var opts: Options = if (mi.show_active) dvui.themeGet().style_accent else .{};

            _ = dvui.image(@src(), .{ .source = .{ .imageFile = .{ .bytes = zig_favicon, .name = "zig favicon" } } }, opts.override(.{ .gravity_x = 0.5 }));
            dvui.labelNoFmt(@src(), "image above text", .{}, opts.override(.{ .gravity_x = 0.5, .padding = .{} }));

            if (mi.activeRect()) |_| {
                dd.close();
                g.choice = 2;
            }
        }
    }

    dd.deinit();
}

/// ![image](Examples-text_entry.png)
pub fn textEntryWidgets(demo_win_id: dvui.WidgetId) void {
    var left_alignment = dvui.Alignment.init();
    defer left_alignment.deinit();

    var enter_pressed = false;
    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Singleline", .{}, .{ .gravity_y = 0.5 });

        left_alignment.spacer(@src(), 0);

        var te = dvui.textEntry(@src(), .{ .text = .{ .buffer = &text_entry_buf } }, .{ .max_size_content = .size(dvui.Options.sizeM(20, 1)) });
        enter_pressed = te.enter_pressed;
        te.deinit();

        dvui.label(@src(), "(limit {d})", .{text_entry_buf.len}, .{ .gravity_y = 0.5 });
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        left_alignment.spacer(@src(), 0);

        dvui.label(@src(), "press enter", .{}, .{ .gravity_y = 0.5 });

        if (enter_pressed) {
            dvui.animation(hbox.data().id, "enter_pressed", .{ .start_val = 1.0, .end_val = 0, .start_time = 0, .end_time = 500_000 });
        }

        if (dvui.animationGet(hbox.data().id, "enter_pressed")) |a| {
            const prev_alpha = dvui.themeGet().alpha;
            dvui.themeGet().alpha *= a.value();
            dvui.label(@src(), "Enter!", .{}, .{ .gravity_y = 0.5 });
            dvui.themeGet().alpha = prev_alpha;
        }
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Password", .{}, .{ .gravity_y = 0.5 });

        left_alignment.spacer(@src(), 0);

        var te = dvui.textEntry(@src(), .{
            .text = .{ .buffer = &text_entry_password_buf },
            .password_char = if (text_entry_password_buf_obf_enable) "*" else null,
            .placeholder = "enter a password",
        }, .{});

        te.deinit();

        if (dvui.buttonIcon(
            @src(),
            "toggle",
            if (text_entry_password_buf_obf_enable) entypo.eye_with_line else entypo.eye,
            .{},
            .{},
            .{ .expand = .ratio },
        )) {
            text_entry_password_buf_obf_enable = !text_entry_password_buf_obf_enable;
        }

        dvui.label(@src(), "(limit {d})", .{text_entry_password_buf.len}, .{ .gravity_y = 0.5 });
    }

    const Sfont = struct {
        var dropdown: usize = 0;

        pub fn compareStrings(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.order(u8, lhs, rhs).compare(std.math.CompareOperator.lt);
        }
    };

    var font_entries: [][]const u8 = dvui.currentWindow().lifo().alloc([]const u8, dvui.currentWindow().font_bytes.count() + 1) catch &.{};
    defer dvui.currentWindow().lifo().free(font_entries);
    if (font_entries.len > 0) {
        font_entries[0] = "Theme Body";
        var it = dvui.currentWindow().font_bytes.keyIterator();
        var i: usize = 0;
        while (it.next()) |v| {
            i += 1;
            font_entries[i] = v.*;
        }

        std.mem.sort([]const u8, font_entries[1..], {}, Sfont.compareStrings);

        Sfont.dropdown = @min(Sfont.dropdown, font_entries.len - 1);
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        {
            var vbox = dvui.box(@src(), .vertical, .{ .gravity_y = 0.5 });
            defer vbox.deinit();

            dvui.label(@src(), "Multiline", .{}, .{});

            _ = dvui.checkbox(@src(), &text_entry_multiline_break, "Break Lines", .{});
        }

        left_alignment.spacer(@src(), 0);

        var font = dvui.themeGet().font_body;
        if (Sfont.dropdown > 0) {
            font.name = font_entries[Sfont.dropdown];
        }

        var te_opts: dvui.TextEntryWidget.InitOptions = .{ .multiline = true, .text = .{ .buffer_dynamic = .{
            .backing = &text_entry_multiline_buf,
            .allocator = text_entry_multiline_fba.allocator(),
            .limit = text_entry_multiline_allocator_buf.len,
        } } };
        if (text_entry_multiline_break) {
            te_opts.break_lines = true;
            te_opts.scroll_horizontal = false;
        }

        var te = dvui.textEntry(
            @src(),
            te_opts,
            .{
                .min_size_content = .{ .w = 160, .h = 80 },
                .max_size_content = .{ .w = 160, .h = 80 },
                .font = font,
            },
        );

        if (!text_entry_multiline_initialized) {
            text_entry_multiline_initialized = true;
            te.textTyped("This multiline text\nentry can scroll\nin both directions.", false);
        }

        const bytes = te.len;
        te.deinit();

        dvui.label(@src(), "bytes {d}\nallocated {d}\nlimit {d}\nscroll horizontal: {s}", .{ bytes, text_entry_multiline_buf.len, text_entry_multiline_allocator_buf.len, if (text_entry_multiline_break) "no" else "yes" }, .{ .gravity_y = 0.5 });
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Multiline Font", .{}, .{ .gravity_y = 0.5 });

        left_alignment.spacer(@src(), 0);

        _ = dvui.dropdown(@src(), font_entries, &Sfont.dropdown, .{ .min_size_content = .{ .w = 100 }, .gravity_y = 0.5 });
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        left_alignment.spacer(@src(), 0);

        var vbox = dvui.box(@src(), .vertical, .{});
        defer vbox.deinit();

        var la2 = dvui.Alignment.init();
        defer la2.deinit();

        if (dvui.wasm) {
            if (dvui.button(@src(), "Add Noto Font", .{}, .{})) {
                dvui.backend.wasm.wasm_add_noto_font();
            }
        } else {
            var hbox2 = dvui.box(@src(), .horizontal, .{});
            dvui.label(@src(), "Name", .{}, .{ .gravity_y = 0.5 });

            la2.spacer(@src(), 0);

            const normalOptions: dvui.Options = .{ .margin = dvui.TextEntryWidget.defaults.marginGet().plus(.all(1)) };
            const errOptions: dvui.Options = .{ .color_border = .err, .border = dvui.Rect.all(2) };

            const name_error = dvui.dataGetPtrDefault(null, hbox2.data().id, "_name_error", bool, false);
            var te_name = dvui.textEntry(@src(), .{}, if (name_error.*) errOptions else normalOptions);
            const name = te_name.getText();
            if (te_name.text_changed) {
                name_error.* = false;
            }
            te_name.deinit();
            hbox2.deinit();

            var hbox3 = dvui.box(@src(), .horizontal, .{});

            var new_filename: ?[]const u8 = null;

            if (dvui.buttonIcon(
                @src(),
                "select font",
                entypo.folder,
                .{},
                .{},
                .{ .expand = .ratio, .gravity_x = 1.0 },
            )) {
                new_filename = dvui.dialogNativeFileOpen(dvui.currentWindow().arena(), .{ .title = "Pick Font File" }) catch null;
            }

            dvui.label(@src(), "File", .{}, .{ .gravity_y = 0.5 });

            la2.spacer(@src(), 0);

            const file_error = dvui.dataGetPtrDefault(null, hbox3.data().id, "_file_error", bool, false);
            var te_file = dvui.textEntry(@src(), .{}, if (file_error.*) errOptions else normalOptions);
            if (new_filename) |f| {
                te_file.textLayout.selection.selectAll();
                te_file.textTyped(f, false);
            }
            if (te_file.text_changed) {
                file_error.* = false;
            }
            const filename = te_file.getText();
            te_file.deinit();
            hbox3.deinit();

            if (dvui.button(@src(), "Add Font", .{}, .{})) {
                if (name.len == 0) {
                    dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Add a Name" });
                    name_error.* = true;
                } else if (dvui.currentWindow().font_bytes.contains(name)) {
                    const msg = std.fmt.allocPrint(dvui.currentWindow().lifo(), "Already have font named \"{s}\"", .{name}) catch name;
                    defer dvui.currentWindow().lifo().free(msg);
                    dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = msg });
                    name_error.* = true;
                } else {
                    var bytes: ?[]u8 = null;
                    if (!std.fs.path.isAbsolute(filename)) {
                        file_error.* = true;
                        const msg = std.fmt.allocPrint(dvui.currentWindow().lifo(), "Could not open \"{s}\"", .{filename}) catch filename;
                        defer dvui.currentWindow().lifo().free(msg);
                        dvui.dialog(@src(), .{}, .{ .title = "File Error", .message = msg });
                    } else {
                        const file = std.fs.openFileAbsolute(filename, .{}) catch blk: {
                            file_error.* = true;
                            const msg = std.fmt.allocPrint(dvui.currentWindow().lifo(), "Could not open \"{s}\"", .{filename}) catch filename;
                            defer dvui.currentWindow().lifo().free(msg);
                            dvui.dialog(@src(), .{}, .{ .title = "File Error", .message = msg });
                            break :blk null;
                        };
                        if (file) |f| {
                            bytes = f.reader().readAllAlloc(dvui.currentWindow().gpa, 30_000_000) catch null;
                        }
                    }

                    if (bytes) |b| blk: {
                        dvui.addFont(name, b, dvui.currentWindow().gpa) catch |err| switch (err) {
                            error.OutOfMemory => @panic("OOM"),
                            error.fontError => {
                                dvui.currentWindow().gpa.free(b);
                                const msg = std.fmt.allocPrint(dvui.currentWindow().lifo(), "\"{s}\" is not a valid font", .{filename}) catch filename;
                                defer dvui.currentWindow().lifo().free(msg);
                                dvui.dialog(@src(), .{}, .{ .title = "Bad Font", .message = msg });
                                break :blk;
                            },
                        };

                        const msg = std.fmt.allocPrint(dvui.currentWindow().lifo(), "Added font named \"{s}\"", .{name}) catch name;
                        defer dvui.currentWindow().lifo().free(msg);
                        dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = msg });
                    }
                }
            }
        }
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .height(10) });

    // Combobox
    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "ComboBox", .{}, .{ .gravity_y = 0.5 });

        left_alignment.spacer(@src(), 0);

        const entries: []const []const u8 = &.{
            "one", "two", "three", "four", "five", "six",
        };

        const combo = dvui.comboBox(@src(), .{}, .{});

        // filter suggestions to match the start of the entry
        if (combo.te.text_changed) blk: {
            const arena = dvui.currentWindow().lifo();
            var filtered = std.ArrayListUnmanaged([]const u8).initCapacity(arena, entries.len) catch {
                dvui.dataRemove(null, combo.te.data().id, "suggestions");
                break :blk;
            };
            defer filtered.deinit(arena);
            const filter_text = combo.te.getText();
            for (entries) |entry| {
                if (std.mem.startsWith(u8, entry, filter_text)) {
                    filtered.appendAssumeCapacity(entry);
                }
            }
            dvui.dataSetSlice(null, combo.te.data().id, "suggestions", filtered.items);
        }

        if (combo.entries(dvui.dataGetSlice(null, combo.te.data().id, "suggestions", [][]const u8) orelse entries)) |index| {
            dvui.log.debug("Combo entry index picked: {d}", .{index});
        }
        combo.deinit();
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Suggest", .{}, .{ .gravity_y = 0.5 });

        left_alignment.spacer(@src(), 0);

        var te = dvui.TextEntryWidget.init(@src(), .{}, .{ .max_size_content = .size(dvui.Options.sizeM(20, 1)) });
        te.install();

        const entries: []const []const u8 = &.{
            "one", "two", "three", "four", "five", "six",
        };

        var sug = dvui.suggestion(&te, .{ .open_on_text_change = true });

        // dvui.suggestion processes events so text entry should be updated
        if (te.text_changed) blk: {
            const arena = dvui.currentWindow().lifo();
            var filtered = std.ArrayListUnmanaged([]const u8).initCapacity(arena, entries.len) catch {
                dvui.dataRemove(null, te.data().id, "suggestions");
                break :blk;
            };
            defer filtered.deinit(arena);
            const filter_text = te.getText();
            for (entries) |entry| {
                if (std.mem.startsWith(u8, entry, filter_text)) {
                    filtered.appendAssumeCapacity(entry);
                }
            }
            dvui.dataSetSlice(null, te.data().id, "suggestions", filtered.items);
        }

        const filtered = dvui.dataGetSlice(null, te.data().id, "suggestions", [][]const u8) orelse entries;
        if (sug.dropped()) {
            for (filtered) |entry| {
                if (sug.addChoiceLabel(entry)) {
                    te.textSet(entry, false);
                    sug.close();
                }
            }

            if (sug.addChoiceLabel("Set to \"hello\" [always shown]")) {
                te.textSet("hello", false);
            }
            _ = sug.addChoiceLabel("close [always shown]");
        }

        sug.deinit();

        // suggestion forwards events to textEntry, so don't call te.processEvents()
        te.draw();
        te.deinit();
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .height(10) });

    const parse_types = [_]type{ u8, i8, u16, i16, u32, i32, f32, f64 };
    const parse_typenames: [parse_types.len][]const u8 = blk: {
        var temp: [parse_types.len][]const u8 = undefined;
        inline for (parse_types, 0..) |T, i| {
            temp[i] = @typeName(T);
        }
        break :blk temp;
    };

    const S = struct {
        var type_dropdown_val: usize = 0;
        var min: bool = false;
        var max: bool = false;
        var value: f64 = 0;
    };

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Parse", .{}, .{ .gravity_y = 0.5 });

        _ = dvui.dropdown(@src(), &parse_typenames, &S.type_dropdown_val, .{ .min_size_content = .{ .w = 20 }, .gravity_y = 0.5 });

        left_alignment.spacer(@src(), 0);

        inline for (parse_types, 0..) |T, i| {
            if (i == S.type_dropdown_val) {
                var value: T = undefined;
                if (@typeInfo(T) == .int) {
                    S.value = std.math.clamp(S.value, std.math.minInt(T), std.math.maxInt(T));
                    value = @intFromFloat(S.value);
                    S.value = @floatFromInt(value);
                } else {
                    value = @floatCast(S.value);
                }
                const result = dvui.textEntryNumber(@src(), T, .{ .value = &value, .min = if (S.min) 0 else null, .max = if (S.max) 100 else null, .show_min_max = true }, .{ .id_extra = i });
                displayTextEntryNumberResult(result);

                if (result.changed) {
                    if (@typeInfo(T) == .int) {
                        S.value = @floatFromInt(value);
                    } else {
                        S.value = @floatCast(value);
                    }
                    dvui.animation(hbox.data().id, "value_changed", .{ .start_val = 1.0, .end_val = 0, .start_time = 0, .end_time = 500_000 });
                }

                if (dvui.animationGet(hbox.data().id, "value_changed")) |a| {
                    const prev_alpha = dvui.themeGet().alpha;
                    dvui.themeGet().alpha *= a.value();
                    dvui.label(@src(), "Changed!", .{}, .{ .gravity_y = 0.5 });
                    dvui.themeGet().alpha = prev_alpha;
                }
            }
        }
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        left_alignment.spacer(@src(), 0);

        _ = dvui.checkbox(@src(), &S.min, "Min", .{});
        _ = dvui.checkbox(@src(), &S.max, "Max", .{});
        _ = dvui.label(@src(), "Stored {d}", .{S.value}, .{});
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .height(20) });

    dvui.label(@src(), "The text entries in this section are left-aligned", .{}, .{});
}

pub fn displayTextEntryNumberResult(result: anytype) void {
    switch (result.value) {
        .TooBig => {
            dvui.label(@src(), "Too Big", .{}, .{ .gravity_y = 0.5 });
        },
        .TooSmall => {
            dvui.label(@src(), "Too Small", .{}, .{ .gravity_y = 0.5 });
        },
        .Empty => {
            dvui.label(@src(), "Empty", .{}, .{ .gravity_y = 0.5 });
        },
        .Invalid => {
            dvui.label(@src(), "Invalid", .{}, .{ .gravity_y = 0.5 });
        },
        .Valid => |num| {
            dvui.label(@src(), "Parsed {d}", .{num}, .{ .gravity_y = 0.5 });
        },
    }
}

/// ![image](Examples-styling.png)
pub fn styling() void {
    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        _ = dvui.button(@src(), "Accent", .{}, dvui.themeGet().style_accent);
        _ = dvui.button(@src(), "Error", .{}, dvui.themeGet().style_err);
        _ = dvui.button(@src(), "Window", .{}, .{ .color_fill = .fill_window });
        _ = dvui.button(@src(), "Content", .{}, .{ .color_fill = .fill });
        _ = dvui.button(@src(), "Control", .{}, .{});
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{ .expand = .horizontal, .min_size_content = .{ .h = 9 } });
        defer hbox.deinit();

        dvui.label(@src(), "separators", .{}, .{ .gravity_y = 0.5 });

        _ = dvui.separator(@src(), .{ .expand = .horizontal, .gravity_y = 0.5 });
    }

    dvui.label(@src(), "corner radius", .{}, .{});
    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        const opts: Options = .{ .border = Rect.all(1), .background = true, .min_size_content = .{ .w = 20 } };

        _ = dvui.button(@src(), "0", .{}, opts.override(.{ .corner_radius = Rect.all(0) }));
        _ = dvui.button(@src(), "2", .{}, opts.override(.{ .corner_radius = Rect.all(2) }));
        _ = dvui.button(@src(), "7", .{}, opts.override(.{ .corner_radius = Rect.all(7) }));
        _ = dvui.button(@src(), "100", .{}, opts.override(.{ .corner_radius = Rect.all(100) }));
        _ = dvui.button(@src(), "mixed", .{}, opts.override(.{ .corner_radius = .{ .x = 0, .y = 2, .w = 7, .h = 100 } }));
    }

    dvui.label(@src(), "directly set colors", .{}, .{});
    {
        var picker = dvui.ColorPickerWidget.init(@src(), .{ .hsv = &hsv_color, .dir = .horizontal }, .{ .expand = .horizontal });
        picker.install();
        defer picker.deinit();
        if (picker.color_changed) {
            backbox_color = hsv_color.toColor();
            hsluv_hsl = .fromColor(backbox_color);
        }

        {
            var vbox = dvui.box(@src(), .vertical, .{});
            defer vbox.deinit();

            var backbox = dvui.box(@src(), .horizontal, .{ .min_size_content = .{ .h = 40 }, .expand = .horizontal, .background = true, .color_fill = .{ .color = backbox_color } });
            backbox.deinit();

            if (dvui.sliderEntry(@src(), "A: {d:0.2}", .{ .value = &hsv_color.a, .min = 0, .max = 1, .interval = 0.01 }, .{ .min_size_content = .{}, .expand = .horizontal })) {
                backbox_color = hsv_color.toColor();
                hsluv_hsl = .fromColor(backbox_color);
            }

            const res = dvui.textEntryColor(@src(), .{ .value = &backbox_color }, .{});
            if (res.changed) {
                hsluv_hsl = .fromColor(backbox_color);
                hsv_color = .fromColor(backbox_color);
            }
        }
        {
            var vbox = dvui.box(@src(), .vertical, .{});
            defer vbox.deinit();

            if (rgbSliders(@src(), &backbox_color, .{})) {
                hsluv_hsl = .fromColor(backbox_color);
                hsv_color = .fromColor(backbox_color);
            }
            if (hsluvSliders(@src(), &hsluv_hsl, .{})) {
                backbox_color = hsluv_hsl.color();
                hsv_color = .fromColor(backbox_color);
            }
        }
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        const border = dvui.dataGetPtrDefault(null, hbox.data().id, "border", bool, true);
        const radius = dvui.dataGetPtrDefault(null, hbox.data().id, "radius", f32, 5);
        const blur = dvui.dataGetPtrDefault(null, hbox.data().id, "blur", f32, 2);
        const shrink = dvui.dataGetPtrDefault(null, hbox.data().id, "shrink", f32, 0);
        const offset = dvui.dataGetPtrDefault(null, hbox.data().id, "offset", dvui.Point, .{ .x = 1, .y = 1 });
        const alpha = dvui.dataGetPtrDefault(null, hbox.data().id, "alpha", f32, 0.5);

        // We are using two boxes here so the box shadow can have different corner_radius values.

        var vbox = dvui.box(@src(), .vertical, .{ .margin = dvui.Rect.all(30), .min_size_content = .{ .w = 200, .h = 100 }, .corner_radius = dvui.Rect.all(5), .background = true, .border = if (border.*) dvui.Rect.all(1) else null, .box_shadow = .{ .color = .fromColor(backbox_color), .corner_radius = dvui.Rect.all(radius.*), .shrink = shrink.*, .offset = offset.*, .blur = blur.*, .alpha = alpha.* } });
        dvui.label(@src(), "Box shadows", .{}, .{ .gravity_x = 0.5 });
        _ = dvui.checkbox(@src(), border, "border", .{});
        _ = dvui.sliderEntry(@src(), "radius: {d:0.0}", .{ .value = radius, .min = 0, .max = 50, .interval = 1 }, .{ .gravity_x = 0.5 });
        _ = dvui.sliderEntry(@src(), "blur: {d:0.1}", .{ .value = blur, .min = 0, .max = 50, .interval = 0.1 }, .{ .gravity_x = 0.5 });
        _ = dvui.sliderEntry(@src(), "shrink: {d:0.0}", .{ .value = shrink, .min = -10, .max = 50, .interval = 1 }, .{ .gravity_x = 0.5 });
        _ = dvui.sliderEntry(@src(), "x: {d:0.0}", .{ .value = &offset.x, .min = -20, .max = 20, .interval = 1 }, .{ .gravity_x = 0.5 });
        _ = dvui.sliderEntry(@src(), "y: {d:0.0}", .{ .value = &offset.y, .min = -20, .max = 20, .interval = 1 }, .{ .gravity_x = 0.5 });
        _ = dvui.sliderEntry(@src(), "alpha: {d:0.2}", .{ .value = alpha, .min = 0, .max = 1, .interval = 0.01 }, .{ .gravity_x = 0.5 });
        vbox.deinit();

        {
            var vbox2 = dvui.box(@src(), .vertical, .{ .margin = .{ .y = 30 } });
            defer vbox2.deinit();

            const gradient = dvui.dataGetPtrDefault(null, vbox2.data().id, "gradient", usize, 0);

            {
                var gbox = dvui.box(@src(), .horizontal, .{});
                defer gbox.deinit();
                dvui.label(@src(), "Gradient", .{}, .{ .gravity_y = 0.5 });
                _ = dvui.dropdown(@src(), &.{ "flat", "horizontal", "vertical", "radial" }, gradient, .{});
            }

            var drawBox = dvui.box(@src(), .vertical, .{ .min_size_content = .{ .w = 200, .h = 100 } });
            defer drawBox.deinit();
            const rs = drawBox.data().contentRectScale();

            var path: dvui.Path.Builder = .init(dvui.currentWindow().lifo());
            defer path.deinit();
            path.addRect(rs.r, dvui.Rect.Physical.all(5));

            var triangles = path.build().fillConvexTriangles(dvui.currentWindow().lifo(), .{ .center = rs.r.center() }) catch dvui.Triangles.empty;
            defer triangles.deinit(dvui.currentWindow().lifo());

            const ca0 = backbox_color;
            const ca1 = backbox_color.opacity(0);

            switch (gradient.*) {
                1, 2 => |choice| {
                    for (triangles.vertexes) |*v| {
                        const t = if (choice == 1)
                            (v.pos.x - rs.r.x) / rs.r.w
                        else
                            (v.pos.y - rs.r.y) / rs.r.h;
                        v.col = v.col.multiply(.fromColor(dvui.Color.lerp(ca0, ca1, t)));
                    }
                },
                3 => {
                    const center = rs.r.center();
                    const max = rs.r.bottomRight().diff(center).length();
                    for (triangles.vertexes) |*v| {
                        const l: f32 = v.pos.diff(center).length();
                        const t = l / max;
                        v.col = v.col.multiply(.fromColor(dvui.Color.lerp(ca0, ca1, t)));
                    }
                },
                else => {
                    triangles.color(ca0);
                },
            }
            dvui.renderTriangles(triangles, null) catch |err| {
                dvui.logError(@src(), err, "Could not render gradient triangles", .{});
            };
        }
    }
}

// Let's wrap the sliderEntry widget so we have 3 that represent a Color
pub fn rgbSliders(src: std.builtin.SourceLocation, color: *dvui.Color, opts: Options) bool {
    var hbox = dvui.boxEqual(src, .horizontal, opts);
    defer hbox.deinit();

    var red: f32 = @floatFromInt(color.r);
    var green: f32 = @floatFromInt(color.g);
    var blue: f32 = @floatFromInt(color.b);

    var changed = false;
    if (dvui.sliderEntry(@src(), "R: {d:0.0}", .{ .value = &red, .min = 0, .max = 255, .interval = 1 }, .{ .gravity_y = 0.5 })) {
        changed = true;
    }
    if (dvui.sliderEntry(@src(), "G: {d:0.0}", .{ .value = &green, .min = 0, .max = 255, .interval = 1 }, .{ .gravity_y = 0.5 })) {
        changed = true;
    }
    if (dvui.sliderEntry(@src(), "B: {d:0.0}", .{ .value = &blue, .min = 0, .max = 255, .interval = 1 }, .{ .gravity_y = 0.5 })) {
        changed = true;
    }

    color.r = @intFromFloat(red);
    color.g = @intFromFloat(green);
    color.b = @intFromFloat(blue);

    return changed;
}

// Let's wrap the sliderEntry widget so we have 3 that represent a HSLuv Color
pub fn hsluvSliders(src: std.builtin.SourceLocation, hsluv: *dvui.Color.HSLuv, opts: Options) bool {
    var hbox = dvui.boxEqual(src, .horizontal, opts);
    defer hbox.deinit();

    var changed = false;
    if (dvui.sliderEntry(@src(), "H: {d:0.0}", .{ .value = &hsluv.h, .min = 0, .max = 360, .interval = 1 }, .{ .gravity_y = 0.5 })) {
        changed = true;
    }
    if (dvui.sliderEntry(@src(), "S: {d:0.0}", .{ .value = &hsluv.s, .min = 0, .max = 100, .interval = 1 }, .{ .gravity_y = 0.5 })) {
        changed = true;
    }
    if (dvui.sliderEntry(@src(), "L: {d:0.0}", .{ .value = &hsluv.l, .min = 0, .max = 100, .interval = 1 }, .{ .gravity_y = 0.5 })) {
        changed = true;
    }

    return changed;
}

/// ![image](Examples-layout.png)
pub fn layout() void {
    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        const Static = struct {
            var img: bool = false;
            var shrink: bool = false;
            var background: bool = false;
            var border: bool = false;
            var shrinkE: dvui.Options.Expand = .none;
            var size: Size = .{ .w = 16, .h = 16 };
            var uv: Rect = .{ .w = 1, .h = 1 };
        };

        {
            var vbox = dvui.box(@src(), .vertical, .{});
            defer vbox.deinit();

            {
                var hbox2 = dvui.box(@src(), .horizontal, .{});
                defer hbox2.deinit();

                dvui.label(@src(), "Layout", .{}, .{});
                _ = dvui.checkbox(@src(), &Static.img, "Image", .{});
            }

            if (Static.img) {
                dvui.label(@src(), "Min Size", .{}, .{});
                _ = dvui.sliderEntry(@src(), "W: {d:0.0}", .{ .value = &Static.size.w, .min = 1, .max = 400, .interval = 1 }, .{});
                _ = dvui.sliderEntry(@src(), "H: {d:0.0}", .{ .value = &Static.size.h, .min = 1, .max = 280, .interval = 1 }, .{});

                _ = dvui.checkbox(@src(), &Static.shrink, "Shrink", .{});
                _ = dvui.checkbox(@src(), &Static.background, "Background", .{});
                _ = dvui.checkbox(@src(), &Static.border, "Border", .{});
            }

            var opts: Options = .{ .border = Rect.all(1), .background = true, .min_size_content = .{ .w = 200, .h = 140 } };
            if (Static.shrink) {
                opts.max_size_content = .size(opts.min_size_contentGet());
            }

            var o = dvui.box(@src(), .vertical, opts);
            defer o.deinit();
            const old_clip = dvui.clip(o.data().backgroundRectScale().r);
            defer dvui.clipSet(old_clip);

            const options: Options = .{ .gravity_x = layout_gravity_x, .gravity_y = layout_gravity_y, .expand = layout_expand, .rotation = layout_rotation, .corner_radius = layout_corner_radius };
            if (Static.img) {
                _ = dvui.image(@src(), .{
                    .source = .{ .imageFile = .{ .bytes = zig_favicon, .name = "zig favicon" } },
                    .shrink = if (Static.shrink) Static.shrinkE else null,
                    .uv = Static.uv,
                }, options.override(
                    .{
                        .min_size_content = Static.size,
                        .background = Static.background,
                        .color_fill = .{ .color = dvui.themeGet().color_text },
                        .border = if (Static.border) Rect.all(1) else null,
                    },
                ));
            } else {
                var buf: [128]u8 = undefined;
                const label = std.fmt.bufPrint(&buf, "{d:0.2},{d:0.2}", .{ layout_gravity_x, layout_gravity_y }) catch unreachable;
                _ = dvui.button(@src(), label, .{}, options);
            }
        }

        {
            var vbox = dvui.box(@src(), .vertical, .{});
            defer vbox.deinit();
            dvui.label(@src(), "Gravity", .{}, .{});
            _ = dvui.sliderEntry(@src(), "X: {d:0.2}", .{ .value = &layout_gravity_x, .min = 0, .max = 1.0, .interval = 0.01 }, .{});
            _ = dvui.sliderEntry(@src(), "Y: {d:0.2}", .{ .value = &layout_gravity_y, .min = 0, .max = 1.0, .interval = 0.01 }, .{});
            dvui.label(@src(), "Corner Radius", .{}, .{});
            inline for (0.., @typeInfo(dvui.Rect).@"struct".fields) |i, field| {
                _ = dvui.sliderEntry(@src(), field.name ++ ": {d:0}", .{ .min = 0, .max = 200, .interval = 1, .value = &@field(layout_corner_radius, field.name) }, .{ .id_extra = i });
            }
            if (Static.img) {
                dvui.label(@src(), "Rotation", .{}, .{});
                _ = dvui.sliderEntry(@src(), "{d:0.2} radians", .{ .value = &layout_rotation, .min = std.math.pi * -2, .max = std.math.pi * 2, .interval = 0.01 }, .{});
            }
        }

        {
            var vbox = dvui.box(@src(), .vertical, .{});
            defer vbox.deinit();
            dvui.label(@src(), "Expand", .{}, .{});
            inline for (std.meta.tags(dvui.Options.Expand)) |opt| {
                if (dvui.radio(@src(), layout_expand == opt, @tagName(opt), .{ .id_extra = @intFromEnum(opt) })) {
                    layout_expand = opt;
                }
            }

            if (Static.img) {
                dvui.label(@src(), "UVs", .{}, .{});
                if (dvui.sliderEntry(@src(), "u0: {d:0.2}", .{ .min = 0, .max = 1, .value = &Static.uv.x }, .{})) {
                    Static.uv.w = @max(Static.uv.w, Static.uv.x);
                }
                if (dvui.sliderEntry(@src(), "u1: {d:0.2}", .{ .min = 0, .max = 1, .value = &Static.uv.w }, .{})) {
                    Static.uv.x = @min(Static.uv.x, Static.uv.w);
                }
                if (dvui.sliderEntry(@src(), "v0: {d:0.2}", .{ .min = 0, .max = 1, .value = &Static.uv.y }, .{})) {
                    Static.uv.h = @max(Static.uv.h, Static.uv.y);
                }
                if (dvui.sliderEntry(@src(), "v1: {d:0.2}", .{ .min = 0, .max = 1, .value = &Static.uv.h }, .{})) {
                    Static.uv.y = @min(Static.uv.y, Static.uv.h);
                }
            }
        }

        if (Static.shrink) {
            var vbox = dvui.box(@src(), .vertical, .{});
            defer vbox.deinit();
            dvui.label(@src(), "Shrink", .{}, .{});
            inline for (std.meta.tags(dvui.Options.Expand)) |opt| {
                if (dvui.radio(@src(), Static.shrinkE == opt, @tagName(opt), .{ .id_extra = @intFromEnum(opt) })) {
                    Static.shrinkE = opt;
                }
            }
        }
    }

    dvui.label(@src(), "margin/border/padding", .{}, .{});
    {
        var vbox = dvui.box(@src(), .vertical, .{});
        defer vbox.deinit();

        var vbox2 = dvui.box(@src(), .vertical, .{ .gravity_x = 0.5 });
        _ = dvui.sliderEntry(@src(), "margin {d:0.0}", .{ .value = &layout_margin.y, .min = 0, .max = 20.0, .interval = 1 }, .{});
        _ = dvui.sliderEntry(@src(), "border {d:0.0}", .{ .value = &layout_border.y, .min = 0, .max = 20.0, .interval = 1 }, .{});
        _ = dvui.sliderEntry(@src(), "padding {d:0.0}", .{ .value = &layout_padding.y, .min = 0, .max = 20.0, .interval = 1 }, .{});
        vbox2.deinit();

        var hbox = dvui.box(@src(), .horizontal, .{});

        vbox2 = dvui.box(@src(), .vertical, .{ .gravity_y = 0.5 });
        _ = dvui.sliderEntry(@src(), "margin {d:0.0}", .{ .value = &layout_margin.x, .min = 0, .max = 20.0, .interval = 1 }, .{});
        _ = dvui.sliderEntry(@src(), "border {d:0.0}", .{ .value = &layout_border.x, .min = 0, .max = 20.0, .interval = 1 }, .{});
        _ = dvui.sliderEntry(@src(), "padding {d:0.0}", .{ .value = &layout_padding.x, .min = 0, .max = 20.0, .interval = 1 }, .{});
        vbox2.deinit();

        var o = dvui.overlay(@src(), .{ .min_size_content = .{ .w = 164, .h = 140 } });
        var o2 = dvui.overlay(@src(), .{ .background = true, .gravity_x = 0.5, .gravity_y = 0.5 });
        if (dvui.button(@src(), "reset", .{}, .{ .margin = layout_margin, .border = layout_border, .padding = layout_padding })) {
            layout_margin = Rect.all(4);
            layout_border = Rect.all(0);
            layout_padding = Rect.all(4);
        }
        o2.deinit();
        o.deinit();

        vbox2 = dvui.box(@src(), .vertical, .{ .gravity_y = 0.5 });
        _ = dvui.sliderEntry(@src(), "margin {d:0.0}", .{ .value = &layout_margin.w, .min = 0, .max = 20.0, .interval = 1 }, .{});
        _ = dvui.sliderEntry(@src(), "border {d:0.0}", .{ .value = &layout_border.w, .min = 0, .max = 20.0, .interval = 1 }, .{});
        _ = dvui.sliderEntry(@src(), "padding {d:0.0}", .{ .value = &layout_padding.w, .min = 0, .max = 20.0, .interval = 1 }, .{});
        vbox2.deinit();

        hbox.deinit();

        vbox2 = dvui.box(@src(), .vertical, .{ .gravity_x = 0.5 });
        _ = dvui.sliderEntry(@src(), "margin {d:0.0}", .{ .value = &layout_margin.h, .min = 0, .max = 20.0, .interval = 1 }, .{});
        _ = dvui.sliderEntry(@src(), "border {d:0.0}", .{ .value = &layout_border.h, .min = 0, .max = 20.0, .interval = 1 }, .{});
        _ = dvui.sliderEntry(@src(), "padding {d:0.0}", .{ .value = &layout_padding.h, .min = 0, .max = 20.0, .interval = 1 }, .{});
        vbox2.deinit();
    }

    dvui.label(@src(), "Boxes", .{}, .{});
    {
        const opts: Options = .{ .expand = .both, .border = Rect.all(1), .background = true };

        const breakpoint: f32 = 400;
        const equal = dvui.parentGet().data().contentRect().w > breakpoint;

        var hbox = dvui.BoxWidget.init(@src(), .{ .dir = .horizontal, .equal_space = equal, .num_packed_expanded = if (equal) 2 else 1 }, .{ .expand = .horizontal });
        hbox.install();
        hbox.drawBackground();
        defer hbox.deinit();

        {
            var hbox2 = dvui.box(@src(), .horizontal, .{ .min_size_content = .{ .w = breakpoint / 2, .h = 140 }, .max_size_content = .width(breakpoint / 2), .expand = if (equal) .horizontal else .none });
            defer hbox2.deinit();
            {
                var vbox = dvui.box(@src(), .vertical, opts);
                defer vbox.deinit();

                _ = dvui.button(@src(), "vertical", .{}, .{ .gravity_x = 0.5 });
                _ = dvui.button(@src(), "expand", .{}, .{ .expand = .both, .gravity_x = 0.5 });
                _ = dvui.button(@src(), "a", .{}, .{ .gravity_x = 0.5 });
            }

            {
                var vbox = dvui.boxEqual(@src(), .vertical, opts);
                defer vbox.deinit();

                _ = dvui.button(@src(), "vert equal", .{}, .{ .gravity_x = 0.5 });
                _ = dvui.button(@src(), "expand", .{}, .{ .expand = .both, .gravity_x = 0.5 });
                _ = dvui.button(@src(), "a", .{}, .{ .gravity_x = 0.5 });
            }
        }

        {
            var vbox2 = dvui.box(@src(), .vertical, .{ .max_size_content = .zero, .expand = .both });
            defer vbox2.deinit();
            {
                var hbox2 = dvui.box(@src(), .horizontal, opts);
                defer hbox2.deinit();

                _ = dvui.button(@src(), "horizontal", .{}, .{ .gravity_y = 0.5 });
                _ = dvui.button(@src(), "expand", .{}, .{ .expand = .both, .gravity_y = 0.5 });
                _ = dvui.button(@src(), "a", .{}, .{ .gravity_y = 0.5 });
            }

            {
                var hbox2 = dvui.boxEqual(@src(), .horizontal, opts);
                defer hbox2.deinit();

                _ = dvui.button(@src(), "horiz\nequal", .{}, .{ .gravity_y = 0.5 });
                _ = dvui.button(@src(), "expand", .{}, .{ .expand = .both, .gravity_y = 0.5 });
                _ = dvui.button(@src(), "a", .{}, .{ .gravity_y = 0.5 });
            }
        }
    }

    {
        {
            var hbox2 = dvui.box(@src(), .horizontal, .{});
            defer hbox2.deinit();
            dvui.label(@src(), "FlexBox", .{}, .{});
            inline for (std.meta.tags(dvui.FlexBoxWidget.ContentPosition)) |opt| {
                if (dvui.radio(@src(), layout_flex_content_justify == opt, @tagName(opt), .{ .id_extra = @intFromEnum(opt) })) {
                    layout_flex_content_justify = opt;
                }
            }
        }
        {
            var fbox = dvui.flexbox(@src(), .{ .justify_content = layout_flex_content_justify }, .{ .border = dvui.Rect.all(1), .background = true, .padding = .{ .w = 4, .h = 4 } });
            defer fbox.deinit();

            for (0..10) |i| {
                var labelbox = dvui.box(@src(), .vertical, .{ .id_extra = i, .margin = .{ .x = 4, .y = 4 }, .border = dvui.Rect.all(1), .background = true });
                defer labelbox.deinit();

                if (i % 2 == 0) {
                    dvui.label(@src(), "Box {d}", .{i}, .{ .expand = .both, .gravity_x = 0.5, .gravity_y = 0.5 });
                } else {
                    dvui.label(@src(), "Large\nBox {d}", .{i}, .{ .expand = .both, .gravity_x = 0.5, .gravity_y = 0.5 });
                }
            }
        }
    }
    dvui.label(@src(), "Collapsible Pane with Draggable Sash", .{}, .{});
    {
        var paned = dvui.paned(@src(), .{ .direction = .horizontal, .collapsed_size = paned_collapsed_width }, .{ .expand = .both, .background = false, .min_size_content = .{ .h = 130 } });
        defer paned.deinit();

        if (paned.showFirst()) {
            var vbox = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true });
            defer vbox.deinit();

            dvui.label(@src(), "Left Side", .{}, .{});
            dvui.label(@src(), "collapses when width < {d}", .{paned_collapsed_width}, .{});
            dvui.label(@src(), "current width {d}", .{paned.data().rect.w}, .{});
            if (paned.collapsed() and dvui.button(@src(), "Goto Right", .{}, .{})) {
                paned.animateSplit(0.0);
            }
        }

        if (paned.showSecond()) {
            var vbox = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true });
            defer vbox.deinit();

            dvui.label(@src(), "Right Side", .{}, .{});
            if (paned.collapsed() and dvui.button(@src(), "Goto Left", .{}, .{})) {
                paned.animateSplit(1.0);
            }
        }
    }

    _ = dvui.sliderEntry(@src(), "collapse under {d:0.0}", .{ .value = &paned_collapsed_width, .min = 100, .max = 600, .interval = 10 }, .{});
}

/// ![image](Examples-text_layout.png)
pub fn layoutText() void {
    _ = dvui.sliderEntry(@src(), "line height: {d:0.2}", .{ .value = &line_height_factor, .min = 0.1, .max = 2, .interval = 0.1 }, .{});

    {
        var tl = TextLayoutWidget.init(@src(), .{}, .{ .expand = .horizontal });
        tl.install(.{});
        defer tl.deinit();

        var cbox = dvui.box(@src(), .vertical, .{ .margin = dvui.Rect.all(6), .min_size_content = .{ .w = 40 } });
        if (dvui.buttonIcon(
            @src(),
            "play",
            entypo.controller_play,
            .{},
            .{},
            .{ .expand = .ratio },
        )) {
            dvui.dialog(@src(), .{}, .{ .modal = false, .title = "Play", .message = "You clicked play" });
        }
        if (dvui.buttonIcon(
            @src(),
            "more",
            entypo.dots_three_vertical,
            .{},
            .{},
            .{ .expand = .ratio },
        )) {
            dvui.dialog(@src(), .{}, .{ .modal = false, .title = "More", .message = "You clicked more" });
        }
        cbox.deinit();

        cbox = dvui.box(@src(), .vertical, .{ .margin = Rect.all(4), .padding = Rect.all(4), .gravity_x = 1.0, .background = true, .color_fill = .fill_window, .min_size_content = .{ .w = 160 }, .max_size_content = .width(160) });
        dvui.icon(@src(), "aircraft", entypo.aircraft, .{}, .{ .min_size_content = .{ .h = 30 }, .gravity_x = 0.5 });
        dvui.label(@src(), "Caption Heading", .{}, .{ .font_style = .caption_heading, .gravity_x = 0.5 });
        var tl_caption = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false });
        tl_caption.addText("Here is some caption text that is in it's own text layout.", .{ .font_style = .caption });
        tl_caption.deinit();
        cbox.deinit();

        if (tl.touchEditing()) |floating_widget| {
            defer floating_widget.deinit();
            tl.touchEditingMenu();
        }

        tl.processEvents();

        const lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. ";
        const lorem2 = " Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.\n";
        tl.addText(lorem, .{ .font = dvui.themeGet().font_body.lineHeightFactor(line_height_factor) });

        if (tl.addTextClick("This text is a link that is part of the text layout and goes to the dvui home page.", .{ .color_text = .{ .color = .{ .r = 0x35, .g = 0x84, .b = 0xe4 } }, .font = dvui.themeGet().font_body.lineHeightFactor(line_height_factor) })) {
            _ = dvui.openURL("https://david-vanderson.github.io/");
        }

        tl.addText(lorem2, .{ .font = dvui.themeGet().font_body.lineHeightFactor(line_height_factor) });

        const start = "\nNotice that the text in this box is wrapping around the stuff in the corners.\n\n";
        tl.addText(start, .{ .font_style = .title_4 });

        const col = dvui.Color.average(dvui.themeGet().color_text, dvui.themeGet().color_fill);
        tl.addTextTooltip(@src(), "Hover this for a tooltip.\n\n", "This is some tooltip", .{ .color_text = .{ .color = col }, .font = dvui.themeGet().font_body.lineHeightFactor(line_height_factor) });

        tl.format("This line uses zig format strings: {d}\n\n", .{12345}, .{});

        tl.addText("Title ", .{ .font_style = .title });
        tl.addText("Title-1 ", .{ .font_style = .title_1 });
        tl.addText("Title-2 ", .{ .font_style = .title_2 });
        tl.addText("Title-3 ", .{ .font_style = .title_3 });
        tl.addText("Title-4 ", .{ .font_style = .title_4 });
        tl.addText("Heading\n", .{ .font_style = .heading });

        tl.addText("Here ", .{ .font_style = .title, .color_text = .{ .color = .{ .r = 100, .b = 100 } } });
        tl.addText("is some ", .{ .font_style = .title_2, .color_text = .{ .color = .{ .b = 100, .g = 100 } } });
        tl.addText("ugly text ", .{ .font_style = .title_1, .color_text = .{ .color = .{ .r = 100, .g = 100 } } });
        tl.addText("that shows styling.", .{ .font_style = .caption, .color_text = .{ .color = .{ .r = 100, .g = 50, .b = 50 } } });
    }
}

/// ![image](Examples-plots.png)
pub fn plots() void {
    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Simple", .{}, .{});

        const xs: []const f64 = &.{ 0, 1, 2, 3, 4, 5 };
        const ys: []const f64 = &.{ 0, 4, 2, 6, 5, 9 };
        dvui.plotXY(@src(), .{}, 1, xs, ys, .{});
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Color and Thick", .{}, .{});

        const xs: []const f64 = &.{ 0, 1, 2, 3, 4, 5 };
        const ys: []const f64 = &.{ 9, 5, 6, 2, 4, 0 };
        dvui.plotXY(@src(), .{}, 2, xs, ys, .{ .color_accent = .{ .color = dvui.themeGet().color_err } });
    }

    var save: bool = false;
    if (dvui.button(@src(), "Save Plot", .{}, .{ .gravity_x = 1.0 })) {
        save = true;
    }

    var vbox = dvui.box(@src(), .vertical, .{ .min_size_content = .{ .w = 300, .h = 100 }, .expand = .ratio });
    defer vbox.deinit();

    var pic: ?dvui.Picture = null;
    if (save) {
        pic = dvui.Picture.start(vbox.data().contentRectScale().r);
    }

    const Static = struct {
        var xaxis: dvui.PlotWidget.Axis = .{
            .name = "X Axis",
            .min = 0.05,
            .max = 0.95,
        };

        var yaxis: dvui.PlotWidget.Axis = .{
            .name = "Y Axis",
            // let plot figure out min
            .max = 0.8,
        };
    };

    var plot = dvui.plot(@src(), .{
        .title = "Plot Title",
        .x_axis = &Static.xaxis,
        .y_axis = &Static.yaxis,
        .border_thick = 1.0,
        .mouse_hover = true,
    }, .{ .expand = .both });
    var s1 = plot.line();

    const points: usize = 1000;
    const freq: f32 = 5;
    for (0..points + 1) |i| {
        const fval: f64 = @sin(2.0 * std.math.pi * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(points)) * freq);
        s1.point(@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(points)), fval);
    }
    s1.stroke(1, dvui.themeGet().color_accent);
    s1.deinit();
    plot.deinit();

    if (pic) |*p| {
        p.stop();
        defer p.deinit();

        const arena = dvui.currentWindow().lifo();

        if (p.png(arena) catch null) |png_slice| {
            defer arena.free(png_slice);

            if (dvui.wasm) {
                dvui.backend.downloadData("plot.png", png_slice) catch |err| {
                    dvui.logError(@src(), err, "Could not download plot.png", .{});
                };
            } else {
                const filename = dvui.dialogNativeFileSave(arena, .{ .path = "plot.png" }) catch null;
                if (filename) |fname| blk: {
                    defer arena.free(fname);

                    var file = std.fs.createFileAbsoluteZ(fname, .{}) catch |err| {
                        dvui.log.debug("Failed to create file {s}, got {!}", .{ fname, err });
                        dvui.toast(@src(), .{ .message = "Failed to create file" });
                        break :blk;
                    };
                    defer file.close();

                    file.writeAll(png_slice) catch |err| {
                        dvui.log.debug("Failed to write to file {s}, got {!}", .{ fname, err });
                    };
                }
            }
        }
    }
}

const reorderLayout = enum {
    vertical,
    horizontal,
    flex,
};

/// ![image](Examples-reorderable.png)
pub fn reorderLists() void {
    const uniqueId = dvui.parentGet().extendId(@src(), 0);
    const layo = dvui.dataGetPtrDefault(null, uniqueId, "reorderLayout", reorderLayout, .horizontal);

    if (dvui.expander(@src(), "Simple", .{ .default_expanded = true }, .{ .expand = .horizontal })) {
        var vbox = dvui.box(@src(), .vertical, .{ .margin = .{ .x = 10 } });
        defer vbox.deinit();

        {
            var hbox2 = dvui.box(@src(), .horizontal, .{});
            defer hbox2.deinit();

            const entries = [_][]const u8{ "Vertical", "Horizontal", "Flex" };
            for (0..3) |i| {
                if (dvui.radio(@src(), @intFromEnum(layo.*) == i, entries[i], .{ .id_extra = i })) {
                    layo.* = @enumFromInt(i);
                }
            }
        }

        {
            var hbox2 = dvui.box(@src(), .horizontal, .{});
            defer hbox2.deinit();
            dvui.label(@src(), "Drag", .{}, .{});
            dvui.icon(@src(), "drag_icon", dvui.entypo.menu, .{}, .{ .min_size_content = .{ .h = 22 } });
            dvui.label(@src(), "to reorder.", .{}, .{});
        }

        reorderListsSimple(layo.*);
    }

    if (dvui.expander(@src(), "Advanced", .{}, .{ .expand = .horizontal })) {
        var vbox = dvui.box(@src(), .vertical, .{ .margin = .{ .x = 10 } });
        defer vbox.deinit();

        dvui.label(@src(), "Drag off list to remove.", .{}, .{});
        reorderListsAdvanced();
    }

    if (dvui.expander(@src(), "Tree", .{ .default_expanded = true }, .{ .expand = .horizontal })) {
        var vbox = dvui.box(@src(), .vertical, .{ .margin = .{ .x = 10 }, .expand = .both });
        defer vbox.deinit();

        reorderTree();
    }
}

pub fn reorderListsSimple(lay: reorderLayout) void {
    const g = struct {
        var dir_entry: usize = 0;
        var strings = [6][]const u8{ "zero", "one", "two", "three", "four", "five" };
    };

    var removed_idx: ?usize = null;
    var insert_before_idx: ?usize = null;

    var scroll: ?*dvui.ScrollAreaWidget = null;
    if (lay == .horizontal) {
        scroll = dvui.scrollArea(@src(), .{ .horizontal = .auto }, .{});
    }
    defer {
        if (scroll) |sc| sc.deinit();
    }

    // reorder widget must wrap entire list
    var reorder = dvui.reorder(@src(), .{ .min_size_content = .{ .w = 120 }, .background = true, .border = dvui.Rect.all(1), .padding = dvui.Rect.all(4) });
    defer reorder.deinit();

    // this box determines layout of list - could be any layout widget
    var vbox: ?*dvui.BoxWidget = null;
    var fbox: ?*dvui.FlexBoxWidget = null;
    switch (lay) {
        .vertical => vbox = dvui.box(@src(), .vertical, .{ .expand = .both }),
        .horizontal => vbox = dvui.box(@src(), .horizontal, .{ .expand = .both }),
        .flex => fbox = dvui.flexbox(@src(), .{}, .{ .expand = .both }),
    }
    defer {
        if (vbox) |vb| vb.deinit();
        if (fbox) |fb| fb.deinit();
    }

    for (g.strings[0..g.strings.len], 0..) |s, i| {

        // make a reorderable for each entry in the list
        var reorderable = reorder.reorderable(@src(), .{}, .{ .id_extra = i, .expand = .horizontal, .min_size_content = dvui.Options.sizeM(8, 1) });
        defer reorderable.deinit();

        if (reorderable.removed()) {
            removed_idx = i; // this entry is being dragged
        } else if (reorderable.insertBefore()) {
            insert_before_idx = i; // this entry was dropped onto
        }

        // actual content of the list entry
        var hbox = dvui.box(@src(), .horizontal, .{ .expand = .both, .border = dvui.Rect.all(1), .background = true, .color_fill = .fill_window });
        defer hbox.deinit();

        dvui.label(@src(), "{s}", .{s}, .{});

        // this helper shows the triple-line icon, detects the start of a drag,
        // and hands off the drag to the ReorderWidget
        _ = dvui.ReorderWidget.draggable(@src(), .{ .reorderable = reorderable }, .{ .expand = .vertical, .gravity_x = 1.0, .min_size_content = dvui.Size.all(22), .gravity_y = 0.5 });
    }

    // show a final slot that allows dropping an entry at the end of the list
    if (reorder.finalSlot()) {
        insert_before_idx = g.strings.len; // entry was dropped into the final slot
    }

    // returns true if the slice was reordered
    _ = dvui.ReorderWidget.reorderSlice([]const u8, &g.strings, removed_idx, insert_before_idx);
}

pub fn reorderListsAdvanced() void {
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

    var hbox = dvui.box(@src(), .horizontal, .{});
    defer hbox.deinit();

    // template you can drag to add to list
    var added_idx: ?usize = null;
    var added_idx_p: ?dvui.Point.Physical = null;

    if (g.strings_len == g.strings.len) {
        dvui.label(@src(), "List Full", .{}, .{ .gravity_x = 1.0 });
    } else {
        var hbox2 = dvui.box(@src(), .horizontal, .{ .gravity_x = 1.0, .border = dvui.Rect.all(1), .margin = dvui.Rect.all(4), .background = true, .color_fill = .fill_window });
        defer hbox2.deinit();

        dvui.label(@src(), "Drag to add : {d}", .{g.strings_len}, .{});

        if (dvui.ReorderWidget.draggable(@src(), .{ .top_left = hbox2.data().rectScale().r.topLeft() }, .{ .expand = .vertical, .gravity_x = 1.0, .min_size_content = dvui.Size.all(22), .gravity_y = 0.5 })) |p| {
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
    var reorder = dvui.reorder(@src(), .{ .min_size_content = .{ .w = 120 }, .background = true, .border = dvui.Rect.all(1), .padding = dvui.Rect.all(4) });
    defer reorder.deinit();

    // determines layout of list
    var vbox = dvui.box(@src(), .vertical, .{ .expand = .both });
    defer vbox.deinit();

    if (added_idx) |ai| {
        // marking all events for capture, this will only be a problem if some
        // mouse events (in the same frame) came before this drag, and would
        // have interacted with a widget that hasn't run yet
        reorder.dragStart(ai, added_idx_p.?, 0); // reorder grabs capture
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
                _ = dvui.separator(@src(), .{ .id_extra = i, .expand = .horizontal, .margin = dvui.Rect.all(6) });
            } else {
                seen_non_floating = true;
            }
        }

        reorderable.install();

        if (reorderable.removed()) {
            removed_idx = i;
        } else if (reorderable.insertBefore()) {
            insert_before_idx = i;
        }

        if (reorderable.targetRectScale()) |rs| {
            // user is dragging a reorderable over this rect, could draw anything here
            rs.r.fill(.{}, .{ .color = .green });

            // reset to use next space, need a separator
            _ = dvui.separator(@src(), .{ .expand = .horizontal, .margin = dvui.Rect.all(6) });
            reorderable.reinstall();
        }

        // actual content of the list entry
        var hbox2 = dvui.box(@src(), .horizontal, .{ .expand = .both, .border = dvui.Rect.all(1), .background = true, .color_fill = .fill_window });
        defer hbox2.deinit();

        dvui.label(@src(), "{s}", .{s}, .{});

        if (dvui.ReorderWidget.draggable(@src(), .{ .top_left = reorderable.data().rectScale().r.topLeft() }, .{ .expand = .vertical, .gravity_x = 1.0, .min_size_content = dvui.Size.all(22), .gravity_y = 0.5 })) |p| {
            // marking all events for capture, this will only be a problem if some
            // mouse events (in the same frame) came before this drag, and would
            // have interacted with a widget that hasn't run yet
            reorder.dragStart(i, p, 0); // reorder grabs capture
        }
    }

    if (reorder.needFinalSlot()) {
        if (seen_non_floating) {
            _ = dvui.separator(@src(), .{ .expand = .horizontal, .margin = dvui.Rect.all(6) });
        }
        var reorderable = reorder.reorderable(@src(), .{ .last_slot = true, .draw_target = false }, .{});
        defer reorderable.deinit();

        if (reorderable.insertBefore()) {
            insert_before_idx = g.strings_len;
        }

        if (reorderable.targetRectScale()) |rs| {
            // user is dragging a reorderable over this rect
            rs.r.fill(.{}, .{ .color = .green });
        }
    }

    g.reorder(removed_idx, insert_before_idx);
}

pub fn reorderTree() void {
    exampleFileTree(
        @src(),
        .{
            .background = true,
            .border = dvui.Rect.all(1),
            .padding = dvui.Rect.all(4),
        },
        .{
            .padding = dvui.Rect.all(1),
        },
        .{
            .border = .{ .x = 1 },
            .corner_radius = dvui.Rect.all(4),
            .box_shadow = .{
                .color = .{ .color = .black },
                .offset = .{ .x = -5, .y = 5 },
                .shrink = 5,
                .blur = 10,
                .alpha = 0.15,
            },
        },
    ) catch std.debug.panic("Failed to recurse files", .{});
}

const TreeEntryKind = enum {
    file,
    directory,
};

const ConstTreeEntry = struct {
    name: []const u8,
    children: []const ConstTreeEntry = &[_]ConstTreeEntry{},
    kind: TreeEntryKind = .file,
};

const MutableTreeEntry = struct {
    name: []const u8,
    children: Children = .empty,
    kind: TreeEntryKind = .file,

    const Children = std.ArrayListUnmanaged(MutableTreeEntry);
};

const tree_palette = &[_]dvui.Color{
    .{ .r = 0x5e, .g = 0x31, .b = 0x5b, .a = 0xff },
    .{ .r = 0x8c, .g = 0x3f, .b = 0x5d, .a = 0xff },
    .{ .r = 0xba, .g = 0x61, .b = 0x56, .a = 0xff },
    .{ .r = 0xf2, .g = 0xa6, .b = 0x5e, .a = 0xff },
    .{ .r = 0xff, .g = 0xe4, .b = 0x78, .a = 0xff },
    .{ .r = 0xcf, .g = 0xff, .b = 0x70, .a = 0xff },
    .{ .r = 0x8f, .g = 0xde, .b = 0x5d, .a = 0xff },
    .{ .r = 0x3c, .g = 0xa3, .b = 0x70, .a = 0xff },
    .{ .r = 0x3d, .g = 0x6e, .b = 0x70, .a = 0xff },
    .{ .r = 0x32, .g = 0x3e, .b = 0x4f, .a = 0xff },
    .{ .r = 0x32, .g = 0x29, .b = 0x47, .a = 0xff },
    .{ .r = 0x47, .g = 0x3b, .b = 0x78, .a = 0xff },
    .{ .r = 0x4b, .g = 0x5b, .b = 0xab, .a = 0xff },
};

fn exampleRemoveTreeEntry(directory: []const u8, entries: *MutableTreeEntry.Children, old_directory: []const u8, uniqueId: dvui.WidgetId) void {
    for (entries.items, 0..) |*e, i| {
        const alloc = dvui.currentWindow().lifo();
        const abs_path = std.fs.path.join(alloc, &.{ directory, e.name }) catch "";
        defer alloc.free(abs_path);

        if (std.mem.eql(u8, old_directory, abs_path)) {
            dvui.dataSet(null, uniqueId, "removed_entry", entries.swapRemove(i));
        }

        if (e.children.items.len > 0) {
            exampleRemoveTreeEntry(abs_path, &e.children, old_directory, uniqueId);
        }
    }
}

fn examplePlaceTreeEntry(directory: []const u8, entries: *MutableTreeEntry.Children, new_directory: []const u8, uniqueId: dvui.WidgetId) void {
    if (std.mem.containsAtLeast(u8, new_directory, 1, directory)) {
        if (dvui.dataGetPtr(null, uniqueId, "removed_entry", MutableTreeEntry)) |removed_entry| {
            const alloc = dvui.currentWindow().lifo();
            {
                const new_path = std.fs.path.join(alloc, &.{ directory, std.fs.path.basename(new_directory) }) catch "";
                defer alloc.free(new_path);

                if (std.mem.eql(u8, new_path, new_directory)) {
                    entries.appendAssumeCapacity(removed_entry.*);
                    return;
                }
            }

            for (entries.items) |*current_entry| {
                const abs_path = std.fs.path.join(alloc, &.{ directory, current_entry.name }) catch "";
                defer alloc.free(abs_path);

                if (current_entry.kind == .directory) {
                    const new_path = std.fs.path.join(alloc, &.{ abs_path, std.fs.path.basename(new_directory) }) catch "";
                    defer alloc.free(new_path);

                    if (std.mem.eql(u8, new_path, new_directory)) {
                        current_entry.children.appendAssumeCapacity(removed_entry.*);
                        return;
                    }
                    examplePlaceTreeEntry(abs_path, &current_entry.children, new_directory, uniqueId);
                }
            }

            dvui.dataRemove(null, uniqueId, "removed_entry");
        }
    }
}

// Should be able to fit all entries (including nested) in `example_file_structure`
// This could be calculated at comptime but it's a lot of code to traverse the tree for little gain
const example_file_structure_max_children = 36;
const example_file_structure: []const ConstTreeEntry = &[_]ConstTreeEntry{
    .{
        .name = "src",
        .kind = .directory,
        .children = &[_]ConstTreeEntry{
            .{ .name = "main.zig", .kind = .file },
            .{ .name = "utils.zig", .kind = .file },
            .{ .name = "config.zig", .kind = .file },
            .{
                .name = "components",
                .kind = .directory,
                .children = &[_]ConstTreeEntry{
                    .{ .name = "button.zig", .kind = .file },
                    .{ .name = "input.zig", .kind = .file },
                    .{ .name = "modal.zig", .kind = .file },
                },
            },
            .{
                .name = "styles",
                .kind = .directory,
                .children = &[_]ConstTreeEntry{
                    .{ .name = "theme.zig", .kind = .file },
                    .{ .name = "colors.zig", .kind = .file },
                },
            },
        },
    },
    .{
        .name = "assets",
        .kind = .directory,
        .children = &[_]ConstTreeEntry{
            .{ .name = "images", .kind = .directory, .children = &[_]ConstTreeEntry{
                .{ .name = "logo.png", .kind = .file },
                .{ .name = "icon.svg", .kind = .file },
                .{ .name = "background.jpg", .kind = .file },
            } },
            .{ .name = "fonts", .kind = .directory, .children = &[_]ConstTreeEntry{
                .{ .name = "main.ttf", .kind = .file },
                .{ .name = "bold.ttf", .kind = .file },
            } },
        },
    },
    .{
        .name = "docs",
        .kind = .directory,
        .children = &[_]ConstTreeEntry{
            .{ .name = "README.md", .kind = .file },
            .{ .name = "API.md", .kind = .file },
            .{ .name = "CHANGELOG.md", .kind = .file },
            .{ .name = "examples", .kind = .directory, .children = &[_]ConstTreeEntry{
                .{ .name = "basic.zig", .kind = .file },
                .{ .name = "advanced.zig", .kind = .file },
            } },
        },
    },
    .{ .name = "build.zig", .kind = .file },
    .{ .name = "build.zig.zon", .kind = .file },
    .{ .name = ".gitignore", .kind = .file },
    .{ .name = "LICENSE", .kind = .file },
    .{
        .name = "tests",
        .kind = .directory,
        .children = &[_]ConstTreeEntry{
            .{ .name = "unit.zig", .kind = .file },
            .{ .name = "integration.zig", .kind = .file },
            .{ .name = "fixtures", .kind = .directory, .children = &[_]ConstTreeEntry{
                .{ .name = "test_data.json", .kind = .file },
                .{ .name = "sample.txt", .kind = .file },
            } },
        },
    },
};

fn exampleFileTreeSearch(directory: []const u8, base_entries: *MutableTreeEntry.Children, entries: *MutableTreeEntry.Children, tree: *dvui.TreeWidget, uniqueId: dvui.WidgetId, color_id: *usize, branch_options: dvui.Options, expander_options: dvui.Options) !void {
    var id_extra: usize = 0;
    for (entries.items) |*entry| {
        id_extra += 1;
        const color = tree_palette[color_id.* % tree_palette.len];

        var branch_opts_override = dvui.Options{
            .id_extra = id_extra,
            .expand = .horizontal,
        };

        const branch = tree.branch(@src(), .{ .expanded = false }, branch_opts_override.override(branch_options));
        defer branch.deinit();

        const alloc = dvui.currentWindow().lifo();
        const abs_path = std.fs.path.join(alloc, &.{ directory, entry.name }) catch "";
        defer alloc.free(abs_path);

        if (branch.insertBefore()) {
            if (dvui.dataGetSlice(null, uniqueId, "removed_path", []u8)) |removed_path| {
                const old_sub_path = std.fs.path.basename(removed_path);

                const new_path = try std.fs.path.join(alloc, &.{ if (entry.kind == .directory) abs_path else directory, old_sub_path });
                defer alloc.free(new_path);

                if (!std.mem.eql(u8, removed_path, new_path)) {
                    exampleRemoveTreeEntry("~", base_entries, removed_path, uniqueId);
                    examplePlaceTreeEntry("~", base_entries, new_path, uniqueId);
                }

                dvui.dataRemove(null, uniqueId, "removed_path");
            }
        }

        if (branch.floating()) {
            if (dvui.dataGetSlice(null, uniqueId, "removed_path", []u8) == null)
                dvui.dataSetSlice(null, uniqueId, "removed_path", abs_path);
        }

        if (entry.kind == .directory) {
            dvui.icon(
                @src(),
                "FolderIcon",
                dvui.entypo.folder,
                .{ .fill_color = color },
                .{
                    .gravity_y = 0.5,
                },
            );

            _ = dvui.label(@src(), "{s}", .{entry.name}, .{});

            dvui.icon(
                @src(),
                "DropIcon",
                if (branch.expanded) dvui.entypo.triangle_down else dvui.entypo.triangle_right,
                .{ .fill_color = color },
                .{
                    .gravity_y = 0.5,
                    .gravity_x = 1.0,
                },
            );

            var expander_opts_override = dvui.Options{
                .margin = .{ .x = 14 },
                .color_border = .{ .color = color },
                .background = if (expander_options.border != null) true else false,
                .expand = .horizontal,
            };

            if (branch.expander(@src(), .{ .indent = 14 }, expander_opts_override.override(expander_options))) {
                exampleFileTreeSearch(
                    abs_path,
                    base_entries,
                    &entry.children,
                    tree,
                    uniqueId,
                    color_id,
                    branch_options,
                    expander_options,
                ) catch std.debug.panic("Failed to recurse files", .{});
            }

            color_id.* = color_id.* + 1;
        } else {
            dvui.icon(@src(), "FileIcon", dvui.entypo.text_document, .{ .fill_color = color }, .{
                .gravity_y = 0.5,
            });

            _ = dvui.label(@src(), "{s}", .{entry.name}, .{});

            if (branch.button.clicked()) {
                std.log.debug("Clicked: {s}", .{abs_path});
            }
        }
    }
}

/// Used to keep the data slices for the children alive
///
/// This is needed because we want to automatically deallocate when we are done
fn keepExampleFileTreeDataAlive(const_file_tree: []const ConstTreeEntry) void {
    for (const_file_tree) |const_entry| {
        const id: dvui.WidgetId = @enumFromInt(dvui.hashIdKey(@enumFromInt(@intFromPtr(const_file_tree.ptr)), const_entry.name));
        const child_slice = dvui.dataGetSlice(null, id, "child_slice", []MutableTreeEntry) orelse @panic("File tree slice did not exist");
        std.mem.doNotOptimizeAway(child_slice);
        if (const_entry.children.len > 0) {
            keepExampleFileTreeDataAlive(const_entry.children);
        }
    }
}

fn exampleFileTreeSetup(const_file_tree: []const ConstTreeEntry, mutable_file_tree: *MutableTreeEntry.Children) void {
    for (const_file_tree) |const_entry| {
        const id: dvui.WidgetId = @enumFromInt(dvui.hashIdKey(@enumFromInt(@intFromPtr(const_file_tree.ptr)), const_entry.name));
        // Allocate a data slice with the max amount of children possible which will be kept alive later.
        dvui.dataSetSliceCopies(null, id, "child_slice", &[1]MutableTreeEntry{undefined}, example_file_structure_max_children);
        var mutable_entry = MutableTreeEntry{
            .name = const_entry.name,
            .kind = const_entry.kind,
            .children = MutableTreeEntry.Children.initBuffer(
                dvui.dataGetSlice(null, id, "child_slice", []MutableTreeEntry) orelse @panic("Could not set slice for file tree"),
            ),
        };

        if (const_entry.children.len > 0) {
            exampleFileTreeSetup(const_entry.children, &mutable_entry.children);
        }

        mutable_file_tree.appendAssumeCapacity(mutable_entry);
    }
}

pub fn exampleFileTree(src: std.builtin.SourceLocation, tree_options: dvui.Options, branch_options: dvui.Options, expander_options: dvui.Options) !void {
    const uniqueId = dvui.parentGet().extendId(@src(), 0);

    var tree = dvui.TreeWidget.tree(src, tree_options);
    defer tree.deinit();

    var color_index: usize = 0;

    if (dvui.dataGetPtr(null, uniqueId, "mutable_data", MutableTreeEntry.Children)) |mutable_file_tree| {
        // Keep the array list buffer alive
        const data_slice = dvui.dataGetSlice(null, uniqueId, "mutable_slice", []MutableTreeEntry);
        std.mem.doNotOptimizeAway(data_slice);

        if (mutable_file_tree.items.len == 0) {
            exampleFileTreeSetup(example_file_structure, mutable_file_tree);
        } else {
            keepExampleFileTreeDataAlive(example_file_structure);
        }

        exampleFileTreeSearch("~", mutable_file_tree, mutable_file_tree, tree, uniqueId, &color_index, branch_options, expander_options) catch std.debug.panic("Failed to recurse files", .{});
    } else {
        dvui.dataSetSliceCopies(null, uniqueId, "mutable_slice", &[1]MutableTreeEntry{undefined}, example_file_structure_max_children);
        dvui.dataSet(null, uniqueId, "mutable_data", MutableTreeEntry.Children.initBuffer(
            dvui.dataGetSlice(null, uniqueId, "mutable_slice", []MutableTreeEntry) orelse @panic("Could not set slice for file tree"),
        ));
    }
}

pub fn fileTree(src: std.builtin.SourceLocation, root_directory: []const u8, tree_options: dvui.Options, branch_options: dvui.Options, expander_options: dvui.Options) !void {
    var tree = dvui.TreeWidget.tree(src, tree_options);
    defer tree.deinit();

    const uniqueId = dvui.parentGet().extendId(@src(), 0);
    recurseFiles(root_directory, tree, uniqueId, branch_options, expander_options) catch std.debug.panic("Failed to recurse files", .{});
}

fn recurseFiles(root_directory: []const u8, outer_tree: *dvui.TreeWidget, uniqueId: dvui.WidgetId, branch_options: dvui.Options, expander_options: dvui.Options) !void {
    const recursor = struct {
        fn search(directory: []const u8, tree: *dvui.TreeWidget, uid: dvui.WidgetId, color_id: *usize, branch_opts: dvui.Options, expander_opts: dvui.Options) !void {
            var dir = std.fs.cwd().openDir(directory, .{ .access_sub_paths = true, .iterate = true }) catch return;
            defer dir.close();

            const padding = dvui.Rect.all(2);

            var iter = dir.iterate();

            var id_extra: usize = 0;
            while (try iter.next()) |entry| {
                id_extra += 1;

                var branch_opts_override = dvui.Options{
                    .id_extra = id_extra,
                    .expand = .horizontal,
                };

                const color = tree_palette[color_id.* % tree_palette.len];

                const branch = tree.branch(@src(), .{
                    .expanded = false,
                }, branch_opts_override.override(branch_opts));
                defer branch.deinit();

                const abs_path = try std.fs.path.join(
                    dvui.currentWindow().arena(),
                    &.{ directory, entry.name },
                );

                if (branch.insertBefore()) {
                    if (dvui.dataGetSlice(null, uid, "removed_path", []u8)) |removed_path| {
                        const old_sub_path = std.fs.path.basename(removed_path);

                        const new_path = try std.fs.path.join(dvui.currentWindow().arena(), &.{ if (entry.kind == .directory) abs_path else directory, old_sub_path });

                        if (!std.mem.eql(u8, removed_path, new_path)) {
                            std.log.debug("DVUI/TreeWidget: Moved {s} to {s}", .{ removed_path, new_path });

                            try std.fs.renameAbsolute(removed_path, new_path);
                        }

                        dvui.dataRemove(null, uid, "removed_path");
                    }
                }

                if (branch.floating()) {
                    if (dvui.dataGetSlice(null, uid, "removed_path", []u8) == null)
                        dvui.dataSetSlice(null, uid, "removed_path", abs_path);
                }

                switch (entry.kind) {
                    .file => {
                        const icon = dvui.entypo.text_document;
                        const icon_color = color;
                        const text_color = dvui.themeGet().color_text;

                        _ = dvui.icon(
                            @src(),
                            "FileIcon",
                            icon,
                            .{ .fill_color = icon_color },
                            .{
                                .gravity_y = 0.5,
                                .padding = padding,
                            },
                        );
                        dvui.label(
                            @src(),
                            "{s}",
                            .{entry.name},
                            .{
                                .color_text = .{ .color = text_color },
                                .padding = padding,
                            },
                        );

                        if (branch.button.clicked()) {
                            std.log.debug("Clicked: {s}", .{abs_path});
                        }
                    },
                    .directory => {
                        const folder_name = std.fs.path.basename(abs_path);
                        const icon_color = color;

                        _ = dvui.icon(
                            @src(),
                            "FolderIcon",
                            dvui.entypo.folder,
                            .{
                                .fill_color = icon_color,
                            },
                            .{
                                .gravity_y = 0.5,
                                .padding = padding,
                            },
                        );
                        dvui.label(@src(), "{s}", .{folder_name}, .{
                            .color_text = .{ .color = dvui.themeGet().color_text },
                            .padding = padding,
                        });
                        _ = dvui.icon(
                            @src(),
                            "DropIcon",
                            if (branch.expanded) dvui.entypo.triangle_down else dvui.entypo.triangle_right,
                            .{ .fill_color = icon_color },
                            .{
                                .gravity_y = 0.5,
                                .gravity_x = 1.0,
                                .padding = padding,
                            },
                        );

                        var expander_opts_override = dvui.Options{
                            .margin = .{ .x = 14 },
                            .color_border = .{ .color = color },
                            .expand = .horizontal,
                        };

                        if (branch.expander(@src(), .{ .indent = 14 }, expander_opts_override.override(expander_opts))) {
                            try search(
                                abs_path,
                                tree,
                                uid,
                                color_id,
                                branch_opts,
                                expander_opts,
                            );
                        }
                        color_id.* = color_id.* + 1;
                    },
                    else => {},
                }
            }
        }
    }.search;

    var color_index: usize = 0;

    const root_branch = outer_tree.branch(@src(), .{
        .expanded = true,
    }, .{
        .id_extra = 0,
        .expand = .horizontal,
        //.color_fill_hover = .fill,
    });
    defer root_branch.deinit();

    dvui.icon(
        @src(),
        "FolderIcon",
        dvui.entypo.folder,
        .{
            .fill_color = tree_palette[0],
        },
        .{
            .gravity_y = 0.5,
            .padding = dvui.Rect.all(10),
        },
    );

    const folder_name = std.fs.path.basename(root_directory);
    dvui.label(@src(), "{s}", .{folder_name}, .{
        .color_text = .{ .color = dvui.themeGet().color_text },
        .padding = dvui.Rect.all(10),
    });
    dvui.icon(
        @src(),
        "DropIcon",
        if (root_branch.expanded) dvui.entypo.triangle_down else dvui.entypo.triangle_right,
        .{ .fill_color = tree_palette[0] },
        .{
            .gravity_y = 0.5,
            .gravity_x = 1.0,
            .padding = dvui.Rect.all(10),
        },
    );

    if (root_branch.expander(@src(), .{ .indent = 14.0 }, .{
        .color_fill = .fill_window,
        .color_border = .{ .color = tree_palette[0] },
        .expand = .horizontal,
        .corner_radius = root_branch.button.wd.options.corner_radius,
        .background = true,
        .border = .{ .x = 1 },
        .box_shadow = .{
            .color = .{ .color = .black },
            .offset = .{ .x = -5, .y = 5 },
            .shrink = 5,
            .blur = 10,
            .alpha = 0.15,
        },
    })) {
        try recursor(root_directory, outer_tree, uniqueId, &color_index, branch_options, expander_options);
    }

    return;
}

/// ![image](Examples-menus.png)
pub fn menus() void {
    var vbox = dvui.box(@src(), .vertical, .{ .expand = .both, .margin = .{ .x = 4 } });
    defer vbox.deinit();

    {
        const ctext = dvui.context(@src(), .{ .rect = vbox.data().borderRectScale().r }, .{});
        defer ctext.deinit();

        if (ctext.activePoint()) |cp| {
            var fw2 = dvui.floatingMenu(@src(), .{ .from = Rect.Natural.fromPoint(cp) }, .{});
            defer fw2.deinit();

            submenus();
            _ = dvui.menuItemLabel(@src(), "Dummy", .{}, .{ .expand = .horizontal });
            _ = dvui.menuItemLabel(@src(), "Dummy Long", .{}, .{ .expand = .horizontal });
            if ((dvui.menuItemLabel(@src(), "Close Menu", .{}, .{ .expand = .horizontal })) != null) {
                fw2.close();
            }
        }
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
        defer hbox.deinit();

        var m = dvui.menu(@src(), .horizontal, .{});

        if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{ .expand = .horizontal })) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();

            submenus();

            _ = dvui.checkbox(@src(), &checkbox_bool, "Checkbox", .{});

            if (dvui.menuItemLabel(@src(), "Dialog", .{}, .{ .expand = .horizontal }) != null) {
                fw.close();
                show_dialog = true;
            }

            if (dvui.menuItemLabel(@src(), "Close Menu", .{}, .{ .expand = .horizontal }) != null) {
                fw.close();
            }
        }

        if (dvui.menuItemLabel(@src(), "Edit", .{ .submenu = true }, .{ .expand = .horizontal })) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();
            _ = dvui.menuItemLabel(@src(), "Dummy", .{}, .{ .expand = .horizontal });
            _ = dvui.menuItemLabel(@src(), "Dummy Long", .{}, .{ .expand = .horizontal });
            _ = dvui.menuItemLabel(@src(), "Dummy Super Long", .{}, .{ .expand = .horizontal });
        }

        m.deinit();

        dvui.labelNoFmt(@src(), "Right click for a context menu", .{}, .{ .gravity_x = 1.0 });
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .height(12) });

    {
        var hbox = dvui.box(@src(), .horizontal, .{ .border = dvui.Rect.all(1), .min_size_content = .{ .h = 50 }, .max_size_content = .width(300) });
        defer hbox.deinit();

        var tl = dvui.textLayout(@src(), .{}, .{ .background = false });
        tl.addText("This box has a simple tooltip.", .{});
        tl.deinit();

        dvui.tooltip(@src(), .{ .active_rect = hbox.data().borderRectScale().r }, "{s}", .{"Simple Tooltip"}, .{});
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .height(4) });

    {
        var hbox = dvui.box(@src(), .horizontal, .{ .border = dvui.Rect.all(1), .min_size_content = .{ .h = 50 }, .max_size_content = .width(300) });
        defer hbox.deinit();

        var tl = dvui.textLayout(@src(), .{}, .{ .background = false });
        tl.addText("This box has a complex tooltip with a fade in and nested tooltip.", .{});
        tl.deinit();

        var tt: dvui.FloatingTooltipWidget = .init(@src(), .{
            .active_rect = hbox.data().borderRectScale().r,
            .interactive = true,
        }, .{ .background = false, .border = .{} });
        if (tt.shown()) {
            var animator = dvui.animate(@src(), .{ .kind = .alpha, .duration = 250_000 }, .{ .expand = .both });
            defer animator.deinit();

            var vbox2 = dvui.box(@src(), .vertical, dvui.FloatingTooltipWidget.defaults.override(.{ .expand = .both }));
            defer vbox2.deinit();

            var tl2 = dvui.textLayout(@src(), .{}, .{ .background = false });
            tl2.addText("This is the tooltip text", .{});
            tl2.deinit();

            _ = dvui.checkbox(@src(), &checkbox_bool, "Checkbox", .{});

            var tt2: dvui.FloatingTooltipWidget = .init(@src(), .{
                .active_rect = tt.data().borderRectScale().r,
            }, .{ .max_size_content = .width(200), .box_shadow = .{} });
            if (tt2.shown()) {
                var tl3 = dvui.textLayout(@src(), .{}, .{ .background = false });
                tl3.addText("Text in a nested tooltip with box shadow", .{});
                tl3.deinit();
            }
            tt2.deinit();
        }
        tt.deinit();
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .height(12) });

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        const layout_dir = dvui.dataGetPtrDefault(null, hbox.data().id, "layout_dir", dvui.enums.Direction, .horizontal);
        const active_tab = dvui.dataGetPtrDefault(null, hbox.data().id, "active_tab", usize, 0);

        const entries = [_][]const u8{ "Horizontal", "Vertical" };
        for (0..2) |i| {
            if (dvui.radio(@src(), @intFromEnum(layout_dir.*) == i, entries[i], .{ .id_extra = i })) {
                layout_dir.* = @enumFromInt(i);
            }
        }
        hbox.deinit();

        // reverse orientation because horizontal tabs go above content
        var tbox = dvui.box(@src(), if (layout_dir.* == .vertical) .horizontal else .vertical, .{ .max_size_content = .{ .w = 400, .h = 200 } });
        defer tbox.deinit();

        {
            var tabs = dvui.TabsWidget.init(@src(), .{ .dir = layout_dir.* }, .{ .expand = if (layout_dir.* == .horizontal) .horizontal else .vertical });
            tabs.install();
            defer tabs.deinit();

            inline for (0..8) |i| {
                const tabname = std.fmt.comptimePrint("Tab {d}", .{i});
                if (i != 3) {
                    // easy label only
                    if (tabs.addTabLabel(active_tab.* == i, tabname)) {
                        active_tab.* = i;
                    }
                } else {
                    // directly put whatever in the tab
                    var tab = tabs.addTab(active_tab.* == i, .{});
                    defer tab.deinit();

                    var tab_box = dvui.box(@src(), .horizontal, .{});
                    defer tab_box.deinit();

                    dvui.icon(@src(), "cycle", entypo.cycle, .{}, .{});

                    _ = dvui.spacer(@src(), .{ .min_size_content = .width(4) });

                    var label_opts = tab.data().options.strip();
                    if (dvui.captured(tab.data().id)) {
                        label_opts.color_text = .text_press;
                    }

                    dvui.labelNoFmt(@src(), tabname, .{}, label_opts);

                    if (tab.clicked()) {
                        active_tab.* = i;
                    }
                }
            }
        }

        {
            var border = dvui.Rect.all(1);
            switch (layout_dir.*) {
                .horizontal => border.y = 0,
                .vertical => border.x = 0,
            }
            var vbox3 = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window, .border = border });
            defer vbox3.deinit();

            dvui.label(@src(), "This is tab {d}", .{active_tab.*}, .{ .expand = .both, .gravity_x = 0.5, .gravity_y = 0.5 });
        }
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .height(12) });

    focus();
}

pub fn submenus() void {
    if (dvui.menuItemLabel(@src(), "Submenu...", .{ .submenu = true }, .{ .expand = .horizontal })) |r| {
        var fw2 = dvui.floatingMenu(@src(), .{ .from = r }, .{});
        defer fw2.deinit();

        submenus();

        if (dvui.menuItemLabel(@src(), "Close Menu", .{}, .{ .expand = .horizontal }) != null) {
            fw2.close();
        }

        if (dvui.menuItemLabel(@src(), "Dialog", .{}, .{ .expand = .horizontal }) != null) {
            fw2.close();
            show_dialog = true;
        }
    }
}

pub fn focus() void {
    if (dvui.expander(@src(), "Changing Focus", .{}, .{ .expand = .horizontal })) {
        var b = dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();

        var tl = dvui.textLayout(@src(), .{}, .{ .background = false });
        tl.addText("Each time this section is expanded, the first text entry will be focused", .{});
        tl.deinit();

        var te = dvui.textEntry(@src(), .{}, .{});
        const teId = te.data().id;

        // firstFrame must be called before te.deinit()
        if (dvui.firstFrame(te.data().id)) {
            dvui.focusWidget(te.data().id, null, null);
        }

        te.deinit();

        // Get a unique Id without making a widget
        const uniqueId = dvui.parentGet().extendId(@src(), 0);

        {
            var hbox = dvui.box(@src(), .horizontal, .{});
            defer hbox.deinit();

            if (dvui.button(@src(), "Focus Next textEntry", .{}, .{})) {
                // grab id from previous frame
                if (dvui.dataGet(null, uniqueId, "next_text_entry_id", dvui.WidgetId)) |id| {
                    dvui.focusWidget(id, null, null);
                }
            }

            if (dvui.button(@src(), "Focus Prev textEntry", .{}, .{})) {
                dvui.focusWidget(teId, null, null);
            }
        }

        var te2 = dvui.textEntry(@src(), .{}, .{});

        // save id for next frame
        dvui.dataSet(null, uniqueId, "next_text_entry_id", te2.data().id);

        te2.deinit();
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .height(10) });

    {
        var b = dvui.box(@src(), .vertical, .{ .margin = .{ .x = 10, .y = 2 }, .border = dvui.Rect.all(1) });
        defer b.deinit();

        const last_focus_id = dvui.lastFocusedIdInFrame();

        var tl = dvui.textLayout(@src(), .{}, .{ .background = false });
        tl.addText("This shows how to detect if any widgets in a dynamic extent have focus.", .{});
        tl.deinit();

        {
            var hbox = dvui.box(@src(), .horizontal, .{});
            defer hbox.deinit();

            for (0..6) |i| {
                const str = switch (i) {
                    0 => "0",
                    1 => "1",
                    2 => "2",
                    3 => "3",
                    4 => "4",
                    5 => "5",
                    else => unreachable,
                };
                _ = dvui.button(@src(), str, .{}, .{ .id_extra = i });
            }
        }

        const have_focus = dvui.lastFocusedIdInFrameSince(last_focus_id) != null;
        dvui.label(@src(), "Anything here with focus: {s}", .{if (have_focus) "Yes" else "No"}, .{});
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .height(10) });

    {
        var b = dvui.box(@src(), .vertical, .{ .expand = .horizontal });
        defer b.deinit();

        var tl = dvui.textLayout(@src(), .{}, .{ .background = false });
        tl.addText("Hover highlighting a box around widgets:", .{});
        tl.deinit();

        var hbox = dvui.BoxWidget.init(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .padding = dvui.Rect.all(4) });
        hbox.install();
        const evts = dvui.events();
        for (evts) |*e| {
            if (!dvui.eventMatchSimple(e, hbox.data())) {
                continue;
            }

            if (e.evt == .mouse and e.evt.mouse.action == .position) {
                hbox.data().options.background = true;
                hbox.data().options.color_fill = .fill_hover;
            }
        }

        hbox.drawBackground();
        defer hbox.deinit();

        inline for (@typeInfo(RadioChoice).@"enum".fields, 0..) |field, i| {
            if (dvui.radio(@src(), radio_choice == @as(RadioChoice, @enumFromInt(field.value)), "Radio " ++ field.name, .{ .id_extra = i })) {
                radio_choice = @enumFromInt(field.value);
            }
        }
    }
}

/// ![image](Examples-scrolling.png)
pub fn scrolling() void {
    const Data1 = struct {
        msg_start: usize = 1_000,
        msg_end: usize = 1_100,
        scroll_info: ScrollInfo = .{},
    };

    var hbox = dvui.box(@src(), .horizontal, .{ .expand = .horizontal });

    const Data = dvui.dataGetPtrDefault(null, hbox.data().id, "data", Data1, .{});

    var scroll_to_msg: ?usize = null;
    var scroll_to_bottom_after = false;
    var scroll_lock_visible = false;

    {
        var vbox = dvui.box(@src(), .vertical, .{ .expand = .vertical });
        defer vbox.deinit();

        dvui.label(@src(), "{d} total widgets", .{2 * (Data.msg_end - Data.msg_start)}, .{});

        if (dvui.button(@src(), "Scroll to Top", .{}, .{})) {
            Data.scroll_info.scrollToOffset(.vertical, 0);
        }

        {
            var h2 = dvui.box(@src(), .horizontal, .{});
            defer h2.deinit();
            if (dvui.button(@src(), "Add Above", .{}, .{})) {
                Data.msg_start -|= 10;
            }

            if (dvui.button(@src(), "Del Above", .{}, .{})) {
                Data.msg_start = @min(Data.msg_end, Data.msg_start + 10);
            }
        }

        if (dvui.button(@src(), "Add Above No Scroll", .{}, .{})) {
            Data.msg_start -|= 10;
            scroll_lock_visible = true;
        }

        if (dvui.button(@src(), "Del Above No Scroll", .{}, .{})) {
            Data.msg_start = @min(Data.msg_end, Data.msg_start + 10);
            scroll_lock_visible = true;
        }

        _ = dvui.spacer(@src(), .{ .expand = .vertical });

        dvui.label(@src(), "Scroll to msg:", .{}, .{});
        const result = dvui.textEntryNumber(@src(), usize, .{ .min = Data.msg_start, .max = Data.msg_end }, .{ .min_size_content = dvui.Options.sizeM(8, 1) });
        const label = switch (result.value) {
            .TooBig => "Too Big",
            .TooSmall => "Too Small",
            .Invalid => "Invalid",
            .Valid, .Empty => " ",
        };
        dvui.labelNoFmt(@src(), label, .{}, .{});
        if (result.value == .Valid and result.enter_pressed) {
            scroll_to_msg = result.value.Valid;
        }

        _ = dvui.spacer(@src(), .{ .expand = .vertical });

        {
            var h2 = dvui.box(@src(), .horizontal, .{});
            defer h2.deinit();
            if (dvui.button(@src(), "Add Below", .{}, .{})) {
                Data.msg_end += 10;
            }

            if (dvui.button(@src(), "Del Below", .{}, .{})) {
                Data.msg_end = @max(Data.msg_start, Data.msg_end - 10);
            }
        }

        if (dvui.button(@src(), "Add Below + Scroll", .{}, .{})) {
            Data.msg_end += 10;
            scroll_to_bottom_after = true;
        }

        if (dvui.button(@src(), "Scroll to Bottom", .{}, .{})) {
            Data.scroll_info.scrollToOffset(.vertical, std.math.maxInt(usize));
        }
    }
    {
        var vbox = dvui.box(@src(), .vertical, .{ .expand = .horizontal, .max_size_content = .height(300) });
        defer vbox.deinit();

        dvui.label(@src(), "{d:0>4.2}% visible, offset {d} frac {d:0>4.2}", .{ Data.scroll_info.visibleFraction(.vertical) * 100.0, Data.scroll_info.viewport.y, Data.scroll_info.offsetFraction(.vertical) }, .{});

        var scroll = dvui.scrollArea(@src(), .{ .scroll_info = &Data.scroll_info, .lock_visible = scroll_lock_visible }, .{ .expand = .horizontal, .min_size_content = .{ .h = 250 } });
        defer scroll.deinit();

        for (Data.msg_start..Data.msg_end + 1) |i| {
            var tl = dvui.textLayout(@src(), .{}, .{ .id_extra = i, .color_fill = .fill_window });
            tl.format("Message {d}", .{i}, .{});

            if (scroll_to_msg != null and scroll_to_msg.? == i) {
                Data.scroll_info.scrollToOffset(.vertical, tl.data().rect.y);
            }

            tl.deinit();

            var tl2 = dvui.textLayout(@src(), .{}, .{ .id_extra = i, .gravity_x = 1.0, .color_fill = .fill_window });
            tl2.format("Reply {d}", .{i}, .{});
            tl2.deinit();
        }
    }

    if (scroll_to_bottom_after) {
        // do this after scrollArea has given scroll_info the new size
        Data.scroll_info.scrollToOffset(.vertical, std.math.maxInt(usize));
    }

    hbox.deinit();

    _ = dvui.spacer(@src(), .{ .min_size_content = .all(12) });
    _ = dvui.separator(@src(), .{ .expand = .horizontal });
    _ = dvui.spacer(@src(), .{ .min_size_content = .all(12) });

    var box2 = dvui.box(@src(), .vertical, .{ .expand = .horizontal });
    defer box2.deinit();

    const siTop = dvui.dataGetPtrDefault(null, box2.data().id, "siTop", ScrollInfo, .{ .horizontal = .auto });
    const siLeft = dvui.dataGetPtrDefault(null, box2.data().id, "siLeft", ScrollInfo, .{ .horizontal = .auto });
    const siMain = dvui.dataGetPtrDefault(null, box2.data().id, "siMain", ScrollInfo, .{ .horizontal = .auto });

    // save the viewport so everything is synced this frame
    const fv = siMain.viewport.topLeft();

    var main_area = dvui.ScrollAreaWidget.init(@src(), .{ .scroll_info = siMain, .frame_viewport = fv }, .{ .expand = .both, .max_size_content = .height(300), .background = false });
    main_area.installScrollBars();

    const left_side_width = 80;

    {
        var hboxTop = dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
        defer hboxTop.deinit();

        var lbox = dvui.box(@src(), .vertical, .{ .min_size_content = .width(left_side_width) });
        dvui.label(@src(), "Linked\nScrolling", .{}, .{ .gravity_x = 0.5, .gravity_y = 0.5 });
        lbox.deinit();

        _ = dvui.spacer(@src(), .{ .min_size_content = .all(10) });

        var top_area = dvui.scrollArea(@src(), .{ .scroll_info = siTop, .frame_viewport = .{ .x = fv.x }, .horizontal_bar = .hide, .process_events_after = false }, .{ .expand = .both });
        {
            // inside top area
            var topbox = dvui.box(@src(), .horizontal, .{});
            defer topbox.deinit();

            for (0..20) |i| {
                dvui.label(@src(), "label {d}", .{i}, .{ .id_extra = i });
            }
        }
        top_area.deinit();
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .all(10) });

    var hbox3 = dvui.box(@src(), .horizontal, .{ .expand = .horizontal });

    var side_area = dvui.scrollArea(@src(), .{ .scroll_info = siLeft, .frame_viewport = .{ .y = fv.y }, .vertical_bar = .hide, .process_events_after = false }, .{ .min_size_content = .{ .w = left_side_width, .h = 200 }, .expand = .vertical });
    {
        // inside side area
        var sidebox = dvui.box(@src(), .vertical, .{});
        defer sidebox.deinit();

        for (0..20) |i| {
            dvui.label(@src(), "label {d}", .{i}, .{ .id_extra = i });
        }
    }
    side_area.deinit();

    _ = dvui.spacer(@src(), .{ .min_size_content = .all(10) });

    var scontainer = dvui.ScrollContainerWidget.init(@src(), siMain, .{ .frame_viewport = fv, .event_rect = main_area.data().borderRectScale().r }, .{ .expand = .both });
    scontainer.install();
    scontainer.processEvents();
    scontainer.processVelocity();

    {
        // inside main area
        var mainbox = dvui.box(@src(), .vertical, .{});
        var mainbox2 = dvui.box(@src(), .horizontal, .{});
        for (0..20) |i| {
            dvui.label(@src(), "label {d}", .{i}, .{ .id_extra = i });
        }
        mainbox2.deinit();
        for (1..20) |i| {
            dvui.label(@src(), "label {d}", .{i}, .{ .id_extra = i });
        }
        mainbox.deinit();
    }
    scontainer.deinit();
    hbox3.deinit();
    main_area.deinit();

    // sync siTop and siMain horizontal
    if (siTop.viewport.x != fv.x) siMain.viewport.x = siTop.viewport.x;
    if (siMain.viewport.x != fv.x) siTop.viewport.x = siMain.viewport.x;

    // sync siLeft and siMain vertical
    if (siLeft.viewport.y != fv.y) siMain.viewport.y = siLeft.viewport.y;
    if (siMain.viewport.y != fv.y) siLeft.viewport.y = siMain.viewport.y;

    // TODO: what happens if sizes are different?
}

/// ![image](Examples-scroll_canvas.png)
pub fn scrollCanvas() void {
    var vbox = dvui.box(@src(), .vertical, .{});
    defer vbox.deinit();

    const scroll_info = dvui.dataGetPtrDefault(null, vbox.data().id, "scroll_info", ScrollInfo, .{ .vertical = .given, .horizontal = .given });
    const origin = dvui.dataGetPtrDefault(null, vbox.data().id, "origin", Point, .{});
    const scale = dvui.dataGetPtrDefault(null, vbox.data().id, "scale", f32, 1.0);
    const boxes = dvui.dataGetSliceDefault(null, vbox.data().id, "boxes", []Point, &.{ .{ .x = 50, .y = 10 }, .{ .x = 80, .y = 150 } });
    const box_contents = dvui.dataGetSliceDefault(null, vbox.data().id, "box_contents", []u8, &.{ 1, 3 });

    const drag_box_window = dvui.dataGetPtrDefault(null, vbox.data().id, "drag_box_window", usize, 0);
    const drag_box_content = dvui.dataGetPtrDefault(null, vbox.data().id, "drag_box_content", usize, 0);

    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .color_fill = .fill_window });
    tl.addText("Click-drag to pan\n", .{});
    tl.addText("Ctrl-wheel to zoom\n", .{});
    tl.addText("Drag blue cubes from box to box\n\n", .{});
    tl.format("Virtual size {d}x{d}\n", .{ scroll_info.virtual_size.w, scroll_info.virtual_size.h }, .{});
    tl.format("Scroll Offset {d}x{d}\n", .{ scroll_info.viewport.x, scroll_info.viewport.y }, .{});
    tl.format("Origin {d}x{d}\n", .{ origin.x, origin.y }, .{});
    tl.format("Scale {d}", .{scale.*}, .{});
    tl.deinit();

    var scrollArea = dvui.scrollArea(@src(), .{ .scroll_info = scroll_info }, .{ .expand = .both, .min_size_content = .{ .w = 300, .h = 300 } });
    var scrollContainer = &scrollArea.scroll.?;

    // can use this to convert between viewport/virtual_size and screen coords
    const scrollRectScale = scrollContainer.screenRectScale(.{});

    var scaler = dvui.scale(@src(), .{ .scale = scale }, .{ .rect = .{ .x = -origin.x, .y = -origin.y } });

    // can use this to convert between data and screen coords
    const dataRectScale = scaler.screenRectScale(.{});

    dvui.Path.stroke(.{ .points = &.{
        dataRectScale.pointToPhysical(.{ .x = -10 }),
        dataRectScale.pointToPhysical(.{ .x = 10 }),
    } }, .{ .thickness = 1, .color = dvui.Color.black });

    dvui.Path.stroke(.{ .points = &.{
        dataRectScale.pointToPhysical(.{ .y = -10 }),
        dataRectScale.pointToPhysical(.{ .y = 10 }),
    } }, .{ .thickness = 1, .color = dvui.Color.black });

    // keep record of bounding box
    var mbbox: ?Rect.Physical = null;

    const dragging_box = dvui.draggingName("box_transfer");
    const evts = dvui.events();

    for (boxes, 0..) |*b, i| {
        var dragBox = dvui.box(@src(), .vertical, .{
            .id_extra = i,
            .rect = dvui.Rect{ .x = b.x, .y = b.y },
            .padding = .{ .h = 5, .w = 5, .x = 5, .y = 5 },
            .background = true,
            .color_fill = .fill_window,
            .border = .{ .h = 1, .w = 1, .x = 1, .y = 1 },
            .corner_radius = .{ .h = 5, .w = 5, .x = 5, .y = 5 },
            .color_border = if (dragging_box and i != drag_box_window.*) .lime else null,
            .box_shadow = .{ .color = if (dragging_box and i != drag_box_window.*) .lime else .black },
        });

        const boxRect = dragBox.data().rectScale().r;
        if (mbbox) |bb| {
            mbbox = bb.unionWith(boxRect);
        } else {
            mbbox = boxRect;
        }

        // if user is dragging a box, we want first crack at events
        if (dragging_box) {
            for (evts) |*e| {
                if (!dvui.eventMatchSimple(e, dragBox.data())) {
                    continue;
                }

                switch (e.evt) {
                    .mouse => |me| {
                        if (me.action == .release and me.button.pointer()) {
                            e.handle(@src(), dragBox.data());
                            dvui.dragEnd();
                            dvui.refresh(null, @src(), dragBox.data().id);

                            if (drag_box_window.* != i) {
                                // move box to new home
                                box_contents[drag_box_window.*] -= 1;
                                box_contents[1 - drag_box_window.*] += 1;
                            }
                        } else if (me.action == .position) {
                            dvui.cursorSet(.crosshair);
                        }
                    },
                    else => {},
                }
            }
        }

        dvui.label(@src(), "Box {d} {d:0>3.0}x{d:0>3.0}", .{ i, b.x, b.y }, .{});

        {
            var hbox = dvui.box(@src(), .horizontal, .{});
            defer hbox.deinit();
            if (dvui.buttonIcon(
                @src(),
                "left",
                entypo.arrow_left,
                .{},
                .{},
                .{ .min_size_content = .{ .h = 20 } },
            )) {
                b.x -= 10;
            }

            if (dvui.buttonIcon(
                @src(),
                "right",
                entypo.arrow_right,
                .{},
                .{},
                .{ .min_size_content = .{ .h = 20 } },
            )) {
                b.x += 10;
            }
        }

        {
            var hbox = dvui.box(@src(), .horizontal, .{ .margin = dvui.Rect.all(4), .border = dvui.Rect.all(1), .padding = dvui.Rect.all(4), .background = true, .color_fill = .fill_window });
            defer hbox.deinit();

            for (evts) |*e| {
                if (!dvui.eventMatchSimple(e, hbox.data())) {
                    continue;
                }
            }

            for (0..box_contents[i]) |k| {
                const dragging_this = dragging_box and i == drag_box_window.* and k == drag_box_content.*;

                if (k > 0) {
                    _ = dvui.spacer(@src(), .{ .min_size_content = .width(5), .id_extra = k });
                }
                const col = if (dragging_this) dvui.Color.lime.opacity(0.5) else dvui.Color.blue;
                var dbox = dvui.box(@src(), .vertical, .{ .id_extra = k, .min_size_content = .{ .w = 20, .h = 20 }, .background = true, .color_fill = .{ .color = col } });
                defer dbox.deinit();

                for (evts) |*e| {
                    if (!dvui.eventMatchSimple(e, dbox.data())) {
                        continue;
                    }

                    switch (e.evt) {
                        .mouse => |me| {
                            if (me.action == .press and me.button.pointer()) {
                                e.handle(@src(), dragBox.data());
                                dvui.captureMouse(dbox.data(), e.num);
                                dvui.dragPreStart(me.p, .{ .name = "box_transfer" });
                            } else if (me.action == .motion) {
                                if (dvui.captured(dbox.data().id)) {
                                    e.handle(@src(), dragBox.data());
                                    if (dvui.dragging(me.p)) |_| {
                                        // started the drag
                                        drag_box_window.* = i;
                                        drag_box_content.* = k;
                                        // give up capture so target can get mouse events, but don't end drag
                                        dvui.captureMouse(null, e.num);
                                    }
                                }
                            } else if (me.action == .position) {
                                if (!dragging_box) {
                                    dvui.cursorSet(.hand);
                                }
                            }
                        },
                        else => {},
                    }
                }
            }
        }

        // process events to drag the box around
        for (evts) |*e| {
            if (!dragBox.matchEvent(e))
                continue;

            switch (e.evt) {
                .mouse => |me| {
                    if (me.action == .press and me.button.pointer()) {
                        e.handle(@src(), dragBox.data());
                        dvui.captureMouse(dragBox.data(), e.num);
                        const offset = me.p.diff(dragBox.data().rectScale().r.topLeft()); // pixel offset from dragBox corner
                        dvui.dragPreStart(me.p, .{ .offset = offset });
                    } else if (me.action == .release and me.button.pointer()) {
                        if (dvui.captured(dragBox.data().id)) {
                            e.handle(@src(), dragBox.data());
                            dvui.captureMouse(null, e.num);
                            dvui.dragEnd();
                        }
                    } else if (me.action == .motion) {
                        if (dvui.captured(dragBox.data().id)) {
                            if (dvui.dragging(me.p)) |_| {
                                const p = me.p.diff(dvui.dragOffset()); // pixel corner we want
                                b.* = dataRectScale.pointFromPhysical(p);
                                dvui.refresh(null, @src(), scrollContainer.data().id);

                                dvui.scrollDrag(.{
                                    .mouse_pt = e.evt.mouse.p,
                                    .screen_rect = dragBox.data().rectScale().r,
                                    .capture_id = dragBox.data().id,
                                });
                            }
                        }
                    }
                },
                else => {},
            }
        }

        dragBox.deinit();
    }

    var zoom: f32 = 1;
    var zoomP: Point.Physical = .{};

    // process scroll area events after boxes so the boxes get first pick (so
    // the button works)
    for (evts) |*e| {
        if (!scrollContainer.matchEvent(e))
            continue;

        switch (e.evt) {
            .mouse => |me| {
                if (me.action == .press and me.button.pointer()) {
                    e.handle(@src(), scrollContainer.data());
                    dvui.captureMouse(scrollContainer.data(), e.num);
                    dvui.dragPreStart(me.p, .{});
                } else if (me.action == .release and me.button.pointer()) {
                    if (dvui.captured(scrollContainer.data().id)) {
                        e.handle(@src(), scrollContainer.data());
                        dvui.captureMouse(null, e.num);
                        dvui.dragEnd();
                    }
                } else if (me.action == .motion) {
                    if (me.button.touch() and dragging_box) {
                        // eat touch motion events so they don't scroll
                        e.handle(@src(), scrollContainer.data());
                    }
                    if (dvui.captured(scrollContainer.data().id)) {
                        if (dvui.dragging(me.p)) |dps| {
                            e.handle(@src(), scrollContainer.data());
                            const rs = scrollRectScale;
                            scroll_info.viewport.x -= dps.x / rs.s;
                            scroll_info.viewport.y -= dps.y / rs.s;
                            dvui.refresh(null, @src(), scrollContainer.data().id);
                        }
                    }
                } else if (me.action == .wheel_y and me.mod.matchBind("ctrl/cmd")) {
                    e.handle(@src(), scrollContainer.data());
                    const base: f32 = 1.01;
                    const zs = @exp(@log(base) * me.action.wheel_y);
                    if (zs != 1.0) {
                        zoom *= zs;
                        zoomP = me.p;
                    }
                }
            },
            else => {},
        }
    }

    if (zoom != 1.0) {
        // scale around mouse point
        // first get data point of mouse
        const prevP = dataRectScale.pointFromPhysical(zoomP);

        // scale
        var pp = prevP.scale(1 / scale.*, Point);
        scale.* *= zoom;
        pp = pp.scale(scale.*, Point);

        // get where the mouse would be now
        const newP = dataRectScale.pointToPhysical(pp);

        // convert both to viewport
        const diff = scrollRectScale.pointFromPhysical(newP).diff(scrollRectScale.pointFromPhysical(zoomP));
        scroll_info.viewport.x += diff.x;
        scroll_info.viewport.y += diff.y;

        dvui.refresh(null, @src(), scrollContainer.data().id);
    }

    scaler.deinit();

    const scrollContainerId = scrollContainer.data().id;

    // deinit is where scroll processes events
    scrollArea.deinit();

    // don't mess with scrolling if we aren't being shown (prevents weirdness
    // when starting out)
    if (!scroll_info.viewport.empty()) {
        // add current viewport plus padding
        const pad = 10;
        var bbox = scroll_info.viewport.outsetAll(pad);
        if (mbbox) |bb| {
            // convert bb from screen space to viewport space
            const scrollbbox = scrollRectScale.rectFromPhysical(bb);
            bbox = bbox.unionWith(scrollbbox);
        }

        // adjust top if needed
        if (bbox.y != 0) {
            const adj = -bbox.y;
            scroll_info.virtual_size.h += adj;
            scroll_info.viewport.y += adj;
            origin.y -= adj;
            dvui.refresh(null, @src(), scrollContainerId);
        }

        // adjust left if needed
        if (bbox.x != 0) {
            const adj = -bbox.x;
            scroll_info.virtual_size.w += adj;
            scroll_info.viewport.x += adj;
            origin.x -= adj;
            dvui.refresh(null, @src(), scrollContainerId);
        }

        // adjust bottom if needed
        if (bbox.h != scroll_info.virtual_size.h) {
            scroll_info.virtual_size.h = bbox.h;
            dvui.refresh(null, @src(), scrollContainerId);
        }

        // adjust right if needed
        if (bbox.w != scroll_info.virtual_size.w) {
            scroll_info.virtual_size.w = bbox.w;
            dvui.refresh(null, @src(), scrollContainerId);
        }
    }

    // Now we are after all widgets that deal with drag name "box_transfer".
    // Any mouse release during a drag here means the user released the mouse
    // outside any target widget.
    if (dragging_box) {
        var done = false;
        for (evts) |*e| {
            if (!e.handled and e.evt == .mouse and e.evt.mouse.action == .release) {
                done = true;
                dvui.dragEnd();
                dvui.refresh(null, @src(), null);
            }
        }

        if (!done) {
            // still dragging, draw a half-opaque box to show we are dragging
            const dr = Rect.Physical.fromPoint(dvui.currentWindow().mouse_pt.diff(.{ .x = 10, .y = 10 })).toSize(.all(20));
            dr.fill(.{}, .{ .color = dvui.Color.lime.opacity(0.5) });
        }
    }
}

/// ![image](Examples-dialogs.png)
pub fn dialogs(demo_win_id: dvui.WidgetId) void {
    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();
        if (dvui.button(@src(), "Direct Dialog", .{}, .{})) {
            show_dialog = true;
        }

        if (dvui.button(@src(), "Giant", .{}, .{})) {
            dvui.dialog(@src(), .{}, .{ .modal = false, .title = "So Much Text", .ok_label = "Too Much", .max_size = .{ .w = 300, .h = 300 }, .message = "This is a non modal dialog with no callafter which happens to have just way too much text in it.\n\nLuckily there is a max_size on here and if the text is too big it will be scrolled.\n\nI mean come on there is just way too much text here.\n\nCan you imagine this much text being created for a dialog?\n\nMaybe like a giant error message with a stack trace or dumping the contents of a large struct?\n\nOr a dialog asking way too many questions, or dumping a whole log into the dialog, or just a very long rant.\n\nMore lines.\n\nAnd more lines.\n\nFinally the last line." });
        }
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        if (dvui.button(@src(), "Non modal", .{}, .{})) {
            dvui.dialog(@src(), .{}, .{ .modal = false, .title = "Ok Dialog", .ok_label = "Ok", .message = "This is a non modal dialog with no callafter\n\nThe ok button is focused by default" });
        }

        const dialogsFollowup = struct {
            fn callafter(id: dvui.WidgetId, response: enums.DialogResponse) !void {
                _ = id;
                var buf: [100]u8 = undefined;
                const text = std.fmt.bufPrint(&buf, "You clicked \"{s}\" in the previous dialog", .{@tagName(response)}) catch unreachable;
                dvui.dialog(@src(), .{}, .{ .title = "Ok Followup Response", .message = text });
            }
        };

        if (dvui.button(@src(), "Modal with followup", .{}, .{})) {
            dvui.dialog(@src(), .{}, .{ .title = "Followup", .message = "This is a modal dialog with modal followup\n\nHere the cancel button is focused", .callafterFn = dialogsFollowup.callafter, .cancel_label = "Cancel", .default = .cancel });
        }
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        if (dvui.button(@src(), "Toast 1", .{}, .{})) {
            dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Toast 1 to demo window" });
        }

        if (dvui.button(@src(), "Toast 2", .{}, .{})) {
            dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Toast 2 to demo window" });
        }

        if (dvui.button(@src(), "Toast 3", .{}, .{})) {
            dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Toast 3 to demo window" });
        }

        if (dvui.button(@src(), "Toast Main Window", .{}, .{})) {
            dvui.toast(@src(), .{ .message = "Toast to main window" });
        }
    }

    dvui.label(@src(), "\nDialogs and toasts from other threads", .{}, .{});
    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        if (dvui.button(@src(), "Dialog after 1 second", .{}, .{})) {
            if (!builtin.single_threaded) blk: {
                const bg_thread = std.Thread.spawn(.{}, background_dialog, .{ dvui.currentWindow(), 1_000_000_000 }) catch |err| {
                    dvui.log.debug("Failed to spawn background thread for delayed action, got {!}", .{err});
                    break :blk;
                };
                bg_thread.detach();
            } else {
                dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Not available in single-threaded" });
            }
        }

        if (dvui.button(@src(), "Toast after 1 second", .{}, .{})) {
            if (!builtin.single_threaded) blk: {
                const bg_thread = std.Thread.spawn(.{}, background_toast, .{ dvui.currentWindow(), 1_000_000_000, demo_win_id }) catch |err| {
                    dvui.log.debug("Failed to spawn background thread for delayed action, got {!}", .{err});
                    break :blk;
                };
                bg_thread.detach();
            } else {
                dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Not available in single-threaded" });
            }
        }
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
        defer hbox.deinit();

        if (dvui.button(@src(), "Show Progress from another Thread", .{}, .{})) {
            progress_mutex.lock();
            progress_val = 0;
            progress_mutex.unlock();
            if (!builtin.single_threaded) blk: {
                const bg_thread = std.Thread.spawn(.{}, background_progress, .{ dvui.currentWindow(), 2_000_000_000 }) catch |err| {
                    dvui.log.debug("Failed to spawn background thread for delayed action, got {!}", .{err});
                    break :blk;
                };
                bg_thread.detach();
            } else {
                dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Not available in single-threaded" });
            }
        }

        dvui.progress(@src(), .{ .percent = progress_val }, .{ .expand = .horizontal, .gravity_y = 0.5, .corner_radius = dvui.Rect.all(100) });
    }

    dvui.label(@src(), "\nNative Dialogs", .{}, .{});
    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        const single_file_id = hbox.widget().extendId(@src(), 0);

        if (dvui.button(@src(), "Open File", .{}, .{})) {
            if (dvui.wasm) {
                dvui.dialogWasmFileOpen(single_file_id, .{ .accept = ".png, .jpg" });
            } else {
                const filename = dvui.dialogNativeFileOpen(dvui.currentWindow().arena(), .{
                    .title = "dvui native file open",
                    .filters = &.{ "*.png", "*.jpg" },
                    .filter_description = "images",
                }) catch |err| blk: {
                    dvui.log.debug("Could not open file dialog, got {!}", .{err});
                    break :blk null;
                };
                if (filename) |f| {
                    dvui.dialog(@src(), .{}, .{ .modal = false, .title = "File Open Result", .ok_label = "Done", .message = f });
                }
            }
        }

        if (dvui.wasmFileUploaded(single_file_id)) |file| {
            dvui.dialog(@src(), .{}, .{ .modal = false, .title = "File Open Result", .ok_label = "Done", .message = file.name });
        }

        const multi_file_id = hbox.widget().extendId(@src(), 0);

        if (dvui.button(@src(), "Open Multiple Files", .{}, .{})) {
            if (dvui.wasm) {
                dvui.dialogWasmFileOpenMultiple(multi_file_id, .{ .accept = ".png, .jpg" });
            } else {
                const filenames = dvui.dialogNativeFileOpenMultiple(dvui.currentWindow().arena(), .{
                    .title = "dvui native file open multiple",
                    .filter_description = "images",
                }) catch |err| blk: {
                    dvui.log.debug("Could not open multi file dialog, got {!}", .{err});
                    break :blk null;
                };
                if (filenames) |files| {
                    const msg = std.mem.join(dvui.currentWindow().lifo(), "\n", files) catch "";
                    defer dvui.currentWindow().lifo().free(msg);
                    dvui.dialog(@src(), .{}, .{ .modal = false, .title = "File Open Multiple Result", .ok_label = "Done", .message = msg });
                }
            }
        }

        if (dvui.wasmFileUploadedMultiple(multi_file_id)) |files| blk: {
            const lifo = dvui.currentWindow().lifo();
            const names = lifo.alloc([:0]const u8, files.len) catch break :blk;
            defer dvui.currentWindow().lifo().free(names);
            for (files, names) |f, *name| name.* = f.name;

            const msg = std.mem.join(dvui.currentWindow().lifo(), "\n", names) catch "";
            defer dvui.currentWindow().lifo().free(msg);
            dvui.dialog(@src(), .{}, .{ .modal = false, .title = "File Open Multiple Result", .ok_label = "Done", .message = msg });
        }
    }
    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        if (dvui.button(@src(), "Open Folder", .{}, .{})) {
            if (dvui.wasm) {
                dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Not implemented for web" });
            } else {
                const filename = dvui.dialogNativeFolderSelect(dvui.currentWindow().arena(), .{ .title = "dvui native folder select" }) catch |err| blk: {
                    dvui.log.debug("Could not open folder select dialog, got {!}", .{err});
                    break :blk null;
                };
                if (filename) |f| {
                    dvui.dialog(@src(), .{}, .{ .modal = false, .title = "Folder Select Result", .ok_label = "Done", .message = f });
                }
            }
        }

        if (dvui.button(@src(), "Save File", .{}, .{})) {
            if (dvui.wasm) {
                dvui.dialog(@src(), .{}, .{ .modal = false, .title = "Save File", .ok_label = "Ok", .message = "Not available on the web.  For file download, see \"Save Plot\" in the plots example." });
            } else {
                const filename = dvui.dialogNativeFileSave(dvui.currentWindow().arena(), .{ .title = "dvui native file save" }) catch |err| blk: {
                    dvui.log.debug("Could not open file save dialog, got {!}", .{err});
                    break :blk null;
                };
                if (filename) |f| {
                    dvui.dialog(@src(), .{}, .{ .modal = false, .title = "File Save Result", .ok_label = "Done", .message = f });
                }
            }
        }
    }
}

/// ![image](Examples-animations.png)
pub fn animations() void {
    const global = struct {
        var animation_choice: usize = 0;
        var round_corners: bool = false;
        var center: bool = false;
        var easing_choice: usize = 0;
        var easing: *const dvui.easing.EasingFn = dvui.easing.linear;
        var duration: i32 = 500_000;
        var xs: [100]f64 = @splat(0);
        var ys: [100]f64 = @splat(0);
    };
    const easing_fns, const easing_names = comptime blk: {
        const decls = std.meta.declarations(dvui.easing);
        var easing_names_arr = [_][]const u8{undefined} ** decls.len;
        var easing_fns_arr = [_]*const dvui.easing.EasingFn{undefined} ** decls.len;
        var i = 0;
        for (decls) |decl| {
            const decl_field = @field(dvui.easing, decl.name);
            if (@TypeOf(decl_field) == dvui.easing.EasingFn) {
                easing_names_arr[i] = decl.name;
                easing_fns_arr[i] = decl_field;
                i += 1;
            }
        }
        var out_names = [_][]const u8{undefined} ** i;
        var out_fns = [_]*const dvui.easing.EasingFn{undefined} ** i;
        @memcpy(&out_names, easing_names_arr[0..i]);
        @memcpy(&out_fns, easing_fns_arr[0..i]);
        break :blk .{ out_fns, out_names };
    };

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        {
            var hbox2 = dvui.box(@src(), .vertical, .{ .min_size_content = .{ .w = 200 } });
            defer hbox2.deinit();

            var button_wiggle = ButtonWidget.init(@src(), .{}, .{ .gravity_x = 0.5 });
            defer button_wiggle.deinit();

            if (dvui.animationGet(button_wiggle.data().id, "xoffset")) |a| {
                button_wiggle.data().rect.x += 20 * (1.0 - a.value()) * (1.0 - a.value()) * @sin(a.value() * std.math.pi * 50);
            }

            button_wiggle.install();
            button_wiggle.processEvents();
            button_wiggle.drawBackground();
            dvui.labelNoFmt(@src(), "Wiggle", .{}, button_wiggle.data().options.strip().override(.{ .gravity_x = 0.5, .gravity_y = 0.5 }));
            button_wiggle.drawFocus();

            if (button_wiggle.clicked()) {
                dvui.animation(button_wiggle.data().id, "xoffset", .{ .start_val = 0, .end_val = 1.0, .start_time = 0, .end_time = 500_000 });
            }
        }

        if (dvui.button(@src(), "Animating Window (Rect)", .{}, .{})) {
            if (animating_window_show) {
                animating_window_closing = true;
            } else {
                animating_window_show = true;
                animating_window_closing = false;
            }
        }

        if (animating_window_show) {
            var win = animatingWindowRect(@src(), &animating_window_rect, &animating_window_show, &animating_window_closing, .{});
            win.install();
            win.processEventsBefore();
            win.drawBackground();
            defer win.deinit();

            var keep_open = true;
            win.dragAreaSet(dvui.windowHeader("Animating Window (center)", "", &keep_open));
            if (!keep_open) {
                animating_window_closing = true;
            }

            var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
            tl.addText("This shows how to animate dialogs and other floating windows by changing the rect.\n\nThis dialog also remembers its position on screen.", .{});
            tl.deinit();
        }
    }

    if (dvui.expander(@src(), "Easings", .{}, .{ .expand = .horizontal })) {
        {
            var hbox = dvui.box(@src(), .horizontal, .{});
            defer hbox.deinit();

            dvui.labelNoFmt(@src(), "Animate", .{}, .{ .gravity_y = 0.5 });

            _ = dvui.dropdown(@src(), &.{ "alpha", "horizontal", "vertical" }, &global.animation_choice, .{});

            dvui.labelNoFmt(@src(), "easing", .{}, .{ .gravity_y = 0.5 });

            var recalc = false;
            if (dvui.firstFrame(hbox.data().id)) {
                recalc = true;
            }

            if (dvui.dropdown(@src(), &easing_names, &global.easing_choice, .{})) {
                global.easing = easing_fns[global.easing_choice];
                recalc = true;
            }

            var duration_float: f32 = @floatFromInt(@divTrunc(global.duration, std.time.us_per_ms));
            if (dvui.sliderEntry(
                @src(),
                "Duration {d}ms",
                .{ .value = &duration_float, .min = 50, .interval = 10, .max = 2_000 },
                .{ .min_size_content = .{ .w = 180 }, .gravity_y = 0.5 },
            )) {
                global.duration = @as(i32, @intFromFloat(duration_float)) * std.time.us_per_ms;
            }

            if (recalc) {
                for (0..global.xs.len) |i| {
                    global.xs[i] = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(global.xs.len));
                    global.ys[i] = global.easing(@floatCast(global.xs[i]));
                }
            }
        }

        {
            var start = false;
            var end = false;
            {
                var hbox = dvui.box(@src(), .horizontal, .{});
                defer hbox.deinit();

                if (dvui.button(@src(), "start", .{}, .{})) {
                    start = true;
                }

                if (dvui.button(@src(), "end", .{}, .{})) {
                    end = true;
                }

                if (global.animation_choice > 0) {
                    _ = dvui.checkbox(@src(), &global.center, "Center", .{ .gravity_y = 0.5 });
                }
            }

            // overlay is just here for padding and sizing
            var o = dvui.overlay(@src(), .{ .padding = dvui.Rect.all(6), .min_size_content = .{ .w = 100, .h = 80 } });
            defer o.deinit();

            const kind: dvui.AnimateWidget.Kind = switch (global.animation_choice) {
                0 => .alpha,
                1 => .horizontal,
                2 => .vertical,
                else => unreachable,
            };
            var animator = dvui.animate(@src(), .{ .kind = kind, .duration = global.duration, .easing = global.easing }, .{ .expand = .both, .gravity_x = if (global.center) 0.5 else 0.0, .gravity_y = if (global.center) 0.5 else 0.0 });
            defer animator.deinit();

            if (start) animator.start();
            if (end) animator.startEnd();

            dvui.plotXY(@src(), .{}, 1, &global.xs, &global.ys, .{ .expand = .both });
        }

        if (dvui.button(@src(), "Animating Dialog (drop)", .{}, .{})) {
            dvui.dialog(@src(), .{ .duration = global.duration, .easing = global.easing }, .{ .modal = false, .title = "Animating Dialog (drop)", .message = "This shows how to animate dialogs and other floating windows.", .displayFn = AnimatingDialog.dialogDisplay, .callafterFn = AnimatingDialog.after });
        }
    }

    if (dvui.expander(@src(), "Spinner", .{}, .{ .expand = .horizontal })) {
        dvui.labelNoFmt(@src(), "Spinner maxes out frame rate", .{}, .{});
        dvui.spinner(@src(), .{ .color_text = .{ .color = .{ .r = 100, .g = 200, .b = 100 } } });
    }

    if (dvui.expander(@src(), "Clock", .{}, .{ .expand = .horizontal })) {
        dvui.labelNoFmt(@src(), "Schedules a frame at the beginning of each second", .{}, .{});

        const millis = @divFloor(dvui.frameTimeNS(), 1_000_000);
        const left = @as(i32, @intCast(@rem(millis, 1000)));

        var mslabel = dvui.LabelWidget.init(@src(), "{d:0>3} ms into second", .{@as(u32, @intCast(left))}, .{}, .{});
        mslabel.install();
        mslabel.draw();

        if (dvui.timerDoneOrNone(mslabel.data().id)) {
            const wait = 1000 * (1000 - left);
            dvui.timer(mslabel.data().id, wait);
        }
        mslabel.deinit();

        dvui.label(@src(), "Estimate of frame overhead {d:6} us", .{dvui.currentWindow().loop_target_slop}, .{});
        switch (dvui.backend.kind) {
            .sdl2, .sdl3 => dvui.label(@src(), "sdl: updated when not interrupted by event", .{}, .{}),
            .web => dvui.label(@src(), "web: updated when not interrupted by event", .{}, .{}),
            .raylib => dvui.label(@src(), "raylib: only updated if non-null passed to waitTime", .{}, .{}),
            .dx11 => dvui.label(@src(), "dx11: only updated if non-null passed to waitTime", .{}, .{}),
            .sdl, .custom, .testing => {},
        }
    }

    if (dvui.expander(@src(), "Texture Frames", .{}, .{ .expand = .horizontal })) {
        var box = dvui.box(@src(), .vertical, .{ .margin = .{ .x = 10 } });
        defer box.deinit();

        const pixels = dvui.dataGetPtrDefault(null, box.data().id, "pixels", [4]dvui.Color.PMA, .{ .yellow, .cyan, .red, .magenta });
        const image_source: dvui.ImageSource = .{ .pixelsPMA = .{ .rgba = pixels, .width = 2, .height = 2, .interpolation = .nearest } };

        // example of how to run frames at a certain fps
        const millis_per_frame = 500;
        if (dvui.timerDoneOrNone(box.data().id)) {
            std.mem.rotate(dvui.Color.PMA, pixels, 1);
            dvui.textureInvalidateCache(image_source.hash());

            const millis = @divFloor(dvui.frameTimeNS(), 1_000_000);
            const left = @as(i32, @intCast(@rem(millis, millis_per_frame)));
            const wait = 1000 * (millis_per_frame - left);
            dvui.timer(box.data().id, wait);
        }

        const num_frames = 4;
        const frame: std.math.IntFittingRange(0, num_frames) = blk: {
            const millis = @divFloor(dvui.frameTimeNS(), std.time.ns_per_ms);
            const left = @as(i32, @intCast(@rem(millis, num_frames * millis_per_frame)));
            break :blk @intCast(@divTrunc(left, millis_per_frame));
        };

        {
            var hbox = dvui.box(@src(), .horizontal, .{});
            defer hbox.deinit();
            dvui.label(@src(), "frame: {d}", .{frame}, .{});
            _ = dvui.checkbox(@src(), &global.round_corners, "Round Corners", .{});
            //dvui.label(@src(), "num textures: {d}", .{dvui.backend.num_textures}, .{});
        }

        var frame_box = dvui.box(@src(), .horizontal, .{ .min_size_content = .{ .w = 50, .h = 50 } });
        defer frame_box.deinit();

        _ = dvui.image(@src(), .{ .source = image_source }, .{ .expand = .both, .corner_radius = if (global.round_corners) dvui.Rect.all(10) else .{} });
    }
}

fn makeLabels(src: std.builtin.SourceLocation, count: usize) void {
    // we want to add labels to the widget that is the parent when makeLabels
    // is called, but since makeLabels is called twice in the same parent we'll
    // get duplicate IDs

    // virtualParent helps by being a parent for ID purposes but leaves the
    // layout to the previous parent
    var vp = dvui.virtualParent(src, .{ .id_extra = count });
    defer vp.deinit();
    dvui.label(@src(), "one", .{}, .{});
    dvui.label(@src(), "two", .{}, .{});
}

/// ![image](Examples-debugging.png)
pub fn debuggingErrors() void {
    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();
        dvui.label(@src(), "Scroll Speed", .{}, .{});
        _ = dvui.sliderEntry(@src(), "{d:0.1}", .{ .value = &dvui.scroll_speed, .min = 0.1, .max = 50, .interval = 0.1 }, .{});
    }

    _ = dvui.checkbox(@src(), &dvui.currentWindow().snap_to_pixels, "Snap to pixels", .{});
    dvui.label(@src(), "on non-hdpi screens watch the window title \"DVUI Demo\"", .{}, .{ .margin = .{ .x = 10 } });
    dvui.label(@src(), "- text, icons, and images rounded to nearest pixel", .{}, .{ .margin = .{ .x = 10 } });
    dvui.label(@src(), "- text rendered at the closest smaller font (not stretched)", .{}, .{ .margin = .{ .x = 10 } });

    _ = dvui.checkbox(@src(), &dvui.currentWindow().debug_touch_simulate_events, "Convert mouse events to touch", .{});
    dvui.label(@src(), "- mouse drag will scroll", .{}, .{ .margin = .{ .x = 10 } });
    dvui.label(@src(), "- mouse click in text layout/entry shows touch draggables and menu", .{}, .{ .margin = .{ .x = 10 } });

    if (dvui.expander(@src(), "Virtual Parent (affects IDs but not layout)", .{}, .{ .expand = .horizontal })) {
        var hbox = dvui.box(@src(), .horizontal, .{ .margin = .{ .x = 10 } });
        defer hbox.deinit();
        dvui.label(@src(), "makeLabels twice:", .{}, .{});

        makeLabels(@src(), 0);
        makeLabels(@src(), 1);
    }

    if (dvui.expander(@src(), "Duplicate id (will log error)", .{}, .{ .expand = .horizontal })) {
        var b = dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        for (0..2) |i| {
            dvui.label(@src(), "this should be highlighted (and error logged)", .{}, .{});
            dvui.label(@src(), " - fix by passing .id_extra = <loop index>", .{}, .{ .id_extra = i });
        }

        if (dvui.labelClick(@src(), "See https://github.com/david-vanderson/dvui/blob/master/readme-implementation.md#widget-ids", .{}, .{}, .{ .color_text = .{ .color = .{ .r = 0x35, .g = 0x84, .b = 0xe4 } } })) {
            _ = dvui.openURL("https://github.com/david-vanderson/dvui/blob/master/readme-implementation.md#widget-ids");
        }
    }

    if (dvui.expander(@src(), "Invalid utf-8 text", .{}, .{ .expand = .horizontal })) {
        var b = dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        dvui.labelNoFmt(@src(), "this \xFFtext\xFF includes some \xFF invalid utf-8\xFF\xFF\xFF which is replaced with \xFF", .{}, .{});
    }

    if (dvui.expander(@src(), "Scroll child after expanded child (will log error)", .{}, .{ .expand = .horizontal })) {
        var scroll = dvui.scrollArea(@src(), .{}, .{ .min_size_content = .{ .w = 200, .h = 80 } });
        defer scroll.deinit();

        _ = dvui.button(@src(), "Expanded\nChild\n", .{}, .{ .expand = .both });
        _ = dvui.button(@src(), "Second Child", .{}, .{});
    }

    if (dvui.expander(@src(), "Key bindings", .{}, .{ .expand = .horizontal })) {
        var b = dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
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
                            g.latest_slice = std.fmt.bufPrintZ(&g.latest_buf, "{s}", .{kv.key_ptr.*}) catch g.latest_buf[0..0];
                        }
                    }
                },
                else => {},
            }
        }

        var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
        tl.format("Latest matched keybinding: {s}", .{g.latest_slice}, .{});
        tl.deinit();

        if (dvui.expander(@src(), "All Key bindings", .{}, .{ .expand = .horizontal })) {
            var tl2 = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
            defer tl2.deinit();

            var outer = dvui.currentWindow().keybinds.iterator();
            while (outer.next()) |okv| {
                tl2.format("\n{s}\n    {}\n", .{ okv.key_ptr.*, okv.value_ptr }, .{});
            }
        }

        if (dvui.expander(@src(), "Overlapping Key bindings", .{}, .{ .expand = .horizontal })) {
            var tl2 = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
            defer tl2.deinit();

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
                        (okb.key == ikb.key))
                    {
                        tl2.format("keybind \"{s}\" overlaps \"{s}\"\n", .{ okv.key_ptr.*, ikv.key_ptr.* }, .{});
                        any_overlaps = true;
                    }
                }
            }

            if (!any_overlaps) {
                tl2.addText("No keybind overlaps found.", .{});
            }
        }
    }

    if (dvui.expander(@src(), "Show Font Atlases", .{}, .{ .expand = .horizontal })) {
        dvui.debugFontAtlases(@src(), .{});
    }

    if (dvui.button(@src(), "Stroke Test", .{}, .{})) {
        StrokeTest.show = true;
    }
}

pub fn dialogDirect() void {
    const data = struct {
        var extra_stuff: bool = false;
    };
    var dialog_win = dvui.floatingWindow(@src(), .{ .modal = false, .open_flag = &show_dialog }, .{ .max_size_content = .width(500) });
    defer dialog_win.deinit();

    dialog_win.dragAreaSet(dvui.windowHeader("Dialog", "", &show_dialog));
    dvui.label(@src(), "Asking a Question", .{}, .{ .font_style = .title_4, .gravity_x = 0.5 });
    dvui.label(@src(), "This dialog is directly called by user code.", .{}, .{ .gravity_x = 0.5 });

    if (dvui.button(@src(), "Toggle extra stuff and fit window", .{}, .{})) {
        data.extra_stuff = !data.extra_stuff;
        dialog_win.autoSize();
    }

    if (data.extra_stuff) {
        dvui.label(@src(), "This is some extra stuff\nwith a multi-line label\nthat has 3 lines", .{}, .{ .margin = .{ .x = 4 } });

        var tl = dvui.textLayout(@src(), .{}, .{});
        tl.addText("Here is a textLayout with a bunch of text in it that would overflow the right edge but the dialog has a max_size_content", .{});
        tl.deinit();
    }

    {
        _ = dvui.spacer(@src(), .{ .expand = .vertical });
        var hbox = dvui.box(@src(), .horizontal, .{ .gravity_x = 1.0 });
        defer hbox.deinit();

        if (dvui.button(@src(), "Yes", .{}, .{})) {
            dialog_win.close(); // can close the dialog this way
        }

        if (dvui.button(@src(), "No", .{}, .{})) {
            show_dialog = false; // can close by not running this code anymore
        }
    }
}

/// ![image](Examples-icon_browser.png)
pub fn icon_browser(src: std.builtin.SourceLocation, show_flag: *bool, comptime icon_decl_name: []const u8, comptime icon_decl: type) void {
    const num_icons = @typeInfo(icon_decl).@"struct".decls.len;
    const Settings = struct {
        icon_size: f32 = 20,
        icon_rgb: dvui.Color = .black,
        row_height: f32 = 0,
        num_rows: u32 = num_icons,
        search: [64:0]u8 = @splat(0),
    };

    const icon_names: [num_icons][]const u8 = blk: {
        var blah: [num_icons][]const u8 = undefined;
        inline for (@typeInfo(icon_decl).@"struct".decls, 0..) |d, i| {
            blah[i] = d.name;
        }
        break :blk blah;
    };

    const icon_fields: [num_icons][]const u8 = blk: {
        var blah: [num_icons][]const u8 = undefined;
        inline for (@typeInfo(icon_decl).@"struct".decls, 0..) |d, i| {
            blah[i] = @field(icon_decl, d.name);
        }
        break :blk blah;
    };

    var vp = dvui.virtualParent(src, .{});
    defer vp.deinit();

    var fwin = dvui.floatingWindow(@src(), .{ .open_flag = show_flag }, .{ .min_size_content = .{ .w = 300, .h = 400 } });
    defer fwin.deinit();
    fwin.dragAreaSet(dvui.windowHeader("Icon Browser " ++ icon_decl_name, "", show_flag));

    var settings: *Settings = dvui.dataGetPtrDefault(null, fwin.data().id, "settings", Settings, .{});

    _ = dvui.sliderEntry(@src(), "size: {d:0.0}", .{ .value = &settings.icon_size, .min = 1, .max = 100, .interval = 1 }, .{ .expand = .horizontal });
    _ = rgbSliders(@src(), &settings.icon_rgb, .{});

    const search = dvui.textEntry(@src(), .{ .text = .{ .buffer = &settings.search }, .placeholder = "Search..." }, .{ .expand = .horizontal });
    const filter = search.getText();
    search.deinit();

    const height = @as(f32, @floatFromInt(settings.num_rows)) * settings.row_height;

    // we won't have the height the first frame, so always set it
    var scroll_info: ScrollInfo = .{ .vertical = .given };
    if (dvui.dataGet(null, fwin.data().id, "scroll_info", ScrollInfo)) |si| {
        scroll_info = si;
        scroll_info.virtual_size.h = height;
    }
    defer dvui.dataSet(null, fwin.data().id, "scroll_info", scroll_info);

    var scroll = dvui.scrollArea(@src(), .{ .scroll_info = &scroll_info }, .{ .expand = .both });
    defer scroll.deinit();

    const visibleRect = scroll.si.viewport;
    var cursor: f32 = 0;
    settings.num_rows = 0;

    for (icon_names, icon_fields, 0..) |name, field, i| {
        if (std.ascii.indexOfIgnoreCase(name, filter) == null) {
            continue;
        }
        settings.num_rows += 1;

        if (cursor <= (visibleRect.y + visibleRect.h) and (cursor + settings.row_height) >= visibleRect.y) {
            const r = Rect{ .x = 0, .y = cursor, .w = 0, .h = settings.row_height };
            var iconbox = dvui.box(@src(), .horizontal, .{ .id_extra = i, .expand = .horizontal, .rect = r });

            var buf: [100]u8 = undefined;
            const text = std.fmt.bufPrint(&buf, icon_decl_name ++ ".{s}", .{name}) catch "<Too much text>";
            if (dvui.buttonIcon(
                @src(),
                text,
                field,
                .{},
                .{},
                .{
                    .min_size_content = .{ .h = settings.icon_size },
                    .color_text = .{ .color = settings.icon_rgb },
                },
            )) {
                dvui.clipboardTextSet(text);
                var buf2: [100]u8 = undefined;
                const toast_text = std.fmt.bufPrint(&buf2, "Copied \"{s}\"", .{text}) catch "Copied <Too much text>";
                dvui.toast(@src(), .{ .message = toast_text });
            }
            dvui.labelNoFmt(@src(), text, .{}, .{ .gravity_y = 0.5 });

            const iconboxId = iconbox.data().id;

            iconbox.deinit(); // this calculates iconbox min size

            settings.row_height = dvui.minSizeGet(iconboxId).?.h;
        }

        cursor += settings.row_height;
    }
}

const grid_panel_size: Size = .{ .w = 250 };

pub fn grids(height: f32) void {
    // Below is a workaround for standaline demos being placed in a scroll-area.
    // By default the scroll-area will scroll instead of the grid.
    // Fix the height of the box around the tabs to prevent this.
    // This would not be required for normal usage.
    var min_size_content: ?Size = null;
    var max_size_content: ?Options.MaxSize = null;
    if (height > 0) {
        min_size_content = .{ .h = height };
        max_size_content = .height(height);
    }

    const GridType = enum {
        styling,
        layout,
        scrolling,
        row_heights,
        const num_grids = @typeInfo(@This()).@"enum".fields.len;
    };
    const local = struct {
        var active_grid: GridType = .styling;

        fn tabSelected(grid_type: GridType) bool {
            return active_grid == grid_type;
        }

        fn tabName(grid_type: GridType) []const u8 {
            return switch (grid_type) {
                .styling => "Styling and sorting",
                .layout => "Layouts and data",
                .scrolling => "Virtual scrolling",
                .row_heights => "Variable row heights",
            };
        }
    };

    var tbox = dvui.box(@src(), .vertical, .{ .border = Rect.all(1), .expand = .horizontal, .min_size_content = min_size_content, .max_size_content = max_size_content });
    defer tbox.deinit();
    {
        var tabs = dvui.TabsWidget.init(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        tabs.install();
        defer tabs.deinit();

        for (0..GridType.num_grids) |tab_num| {
            const this_tab: GridType = @enumFromInt(tab_num);

            if (tabs.addTabLabel(local.tabSelected(this_tab), local.tabName(this_tab))) {
                local.active_grid = this_tab;
            }
        }
    }

    switch (local.active_grid) {
        .styling => gridStyling(),
        .layout => gridLayouts(),
        .scrolling => gridVirtualScrolling(),
        .row_heights => gridVariableRowHeights(),
    }
}

fn gridStyling() void {
    const local = struct {
        var resize_rows: bool = false;
        var sort_dir: dvui.GridWidget.SortDirection = .unsorted;
        var borders: Rect = .all(0);
        var banding: Banding = .none;
        var margin: f32 = 0;
        var padding: f32 = 0;
        var col_widths: [2]f32 = @splat(0);
        const Banding = enum { none, rows, cols };
    };

    var outer_hbox = dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
    defer outer_hbox.deinit();

    {
        var outer_vbox = dvui.box(@src(), .vertical, .{
            .min_size_content = grid_panel_size,
            .max_size_content = .size(grid_panel_size),
            .expand = .vertical,
            .border = Rect.all(1),
            .gravity_x = 1.0,
        });
        defer outer_vbox.deinit();

        if (dvui.expander(@src(), "Borders", .{ .default_expanded = true }, .{ .expand = .horizontal })) {
            var top: bool = local.borders.y > 0;
            var bottom: bool = local.borders.h > 0;
            var left: bool = local.borders.x > 0;
            var right: bool = local.borders.w > 0;
            var fbox = dvui.flexbox(@src(), .{ .justify_content = .start }, .{});
            defer fbox.deinit();
            {
                var vbox = dvui.box(@src(), .vertical, .{ .expand = .horizontal });
                defer vbox.deinit();
                _ = dvui.checkbox(@src(), &top, "Top", .{});
                _ = dvui.checkbox(@src(), &left, "Left", .{});
            }
            {
                var vbox = dvui.box(@src(), .vertical, .{ .expand = .horizontal });
                defer vbox.deinit();
                _ = dvui.checkbox(@src(), &right, "Right", .{});
                _ = dvui.checkbox(@src(), &bottom, "Bottom", .{});
            }
            local.borders = .{
                .y = if (top) 1 else 0,
                .h = if (bottom) 1 else 0,
                .x = if (left) 1 else 0,
                .w = if (right) 1 else 0,
            };
            if (local.borders.nonZero() and local.banding == .cols) {
                local.banding = .none;
            }
        }
        if (dvui.expander(@src(), "Banding", .{ .default_expanded = true }, .{ .expand = .horizontal })) {
            if (dvui.radio(@src(), local.banding == .none, "None", .{})) {
                local.banding = .none;
            }
            if (dvui.radio(@src(), local.banding == .rows, "Rows", .{})) {
                local.banding = .rows;
            }
            if (dvui.radio(@src(), local.banding == .cols, "Cols", .{})) {
                local.banding = .cols;
                local.borders = Rect.all(0);
            }
        }
        if (dvui.expander(@src(), "Other", .{ .default_expanded = true }, .{ .expand = .horizontal })) {
            {
                var hbox = dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
                defer hbox.deinit();
                dvui.labelNoFmt(@src(), "Margin:", .{}, .{ .min_size_content = .{ .w = 60 }, .gravity_y = 0.5 });
                const result = dvui.textEntryNumber(@src(), f32, .{ .min = 0, .max = 10, .value = &local.margin, .show_min_max = true }, .{});
                if (result.changed and result.value == .Valid) {
                    local.margin = result.value.Valid;
                    local.resize_rows = true;
                }
            }
            {
                var hbox = dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
                defer hbox.deinit();
                dvui.labelNoFmt(@src(), "Padding:", .{}, .{ .min_size_content = .{ .w = 60 }, .gravity_y = 0.5 });
                const result = dvui.textEntryNumber(@src(), f32, .{ .min = 0, .max = 10, .value = &local.padding, .show_min_max = true }, .{});
                if (result.changed and result.value == .Valid) {
                    local.padding = result.value.Valid;
                    local.resize_rows = true;
                }
            }
        }
    }

    const row_background = local.banding != .none or local.borders.nonZero();

    {
        var grid = dvui.grid(@src(), .colWidths(&local.col_widths), .{
            .resize_rows = local.resize_rows,
        }, .{
            .expand = .both,
            .background = true,
            .border = Rect.all(1),
        });
        defer grid.deinit();

        // Layout both columns equally, taking up the full width of the grid.
        dvui.columnLayoutProportional(&.{ -1, -1 }, &local.col_widths, grid.data().contentRect().w);

        local.resize_rows = false; // Only resize rows when needed.

        // Set start, end and interval based on sort direction.
        const start_temp: i32, //
        const end_temp: i32, //
        const interval: i32 = switch (local.sort_dir) {
            .ascending, .unsorted => .{ 0, 100, 5 },
            .descending => .{ 100, 0, -5 },
        };

        std.debug.assert(@mod(end_temp - start_temp, interval) == 0); // Temperature range must be a multiple of interval

        // Manually control sorting, so that sort direction is always reversed regardless of
        // which column header is clicked.
        const current_sort_dir = local.sort_dir;

        const cell_opts: GridWidget.CellStyle.Banded = .{
            .banding = switch (local.banding) {
                .none, .rows => .rows,
                .cols => .cols,
            },

            .cell_opts = .{
                .border = local.borders,
                .background = row_background,
                .margin = Rect.all(local.margin),
                .padding = Rect.all(local.padding),
            },
            .alt_cell_opts = .{
                .border = local.borders,
                .margin = Rect.all(local.margin),
                .padding = Rect.all(local.padding),
                .background = row_background,
                // Only set the alternate fill colour if actually banding.
                .color_fill = if (local.banding != .none) .fill_press else null,
            },
        };

        if (dvui.gridHeadingSortable(@src(), grid, 0, "Celcius", &local.sort_dir, .fixed, .{})) {
            grid.colSortSet(0, current_sort_dir.reverse());
        }

        if (dvui.gridHeadingSortable(@src(), grid, 1, "Fahrenheit", &local.sort_dir, .fixed, .{})) {
            grid.colSortSet(1, current_sort_dir.reverse());
        }

        // First column displays temperature in Celcius.
        {
            // Set this column as the default sort
            if (current_sort_dir == .unsorted) {
                local.sort_dir = .ascending;
                grid.colSortSet(0, local.sort_dir);
            }

            var temp: i32 = start_temp;
            var row_num: usize = 0;
            while (temp != end_temp + interval) : ({
                temp += interval;
                row_num += 1;
            }) {
                var cell = grid.bodyCell(@src(), 0, row_num, cell_opts.cellOptions(0, row_num));
                defer cell.deinit();
                dvui.label(@src(), "{d}", .{temp}, .{ .gravity_x = 0.5, .expand = .horizontal });
            }
        }
        // Second column displays temperature in Farenheight.
        {
            var temp: i32 = start_temp;
            var row_num: usize = 0;
            while (temp != end_temp + interval) : ({
                temp += interval;
                row_num += 1;
            }) {
                var cell = grid.bodyCell(@src(), 1, row_num, cell_opts.cellOptions(1, row_num));
                defer cell.deinit();
                dvui.label(@src(), "{d}", .{@divFloor(temp * 9, 5) + 32}, .{ .gravity_x = 0.5, .expand = .horizontal });
            }
        }
    }
}

fn gridLayouts() void {
    const Car = struct {
        selected: bool = false,
        model: []const u8,
        make: []const u8,
        year: u32,
        mileage: u32,
        condition: Condition,
        description: []const u8,

        const Condition = enum { Poor, Fair, Good, Excellent, New };
    };

    const Layout = enum {
        proportional,
        equal_spacing,
        fixed_width,
        fit_window,
        user_resizable,
    };

    const local = struct {
        const num_cols = 6;
        const checkbox_w = 40;

        var col_widths: [num_cols]f32 = @splat(100); // Default width to 100
        const column_ratios = [num_cols]f32{ checkbox_w, -10, -10, -7, -15, -30 };
        const fixed_widths = [num_cols]f32{ checkbox_w, 80, 120, 80, 100, 300 };
        const equal_spacing = [num_cols]f32{ checkbox_w, -1, -1, -1, -1, -1 };
        const fit_window = [num_cols]f32{ checkbox_w, 0, 0, 0, 0, 0 };
        var selection_state: dvui.GridColumnSelectAllState = .select_none;
        var sort_dir: GridWidget.SortDirection = .unsorted;
        var layout_style: Layout = .proportional;
        var h_scroll: bool = false;
        var resize_rows: bool = false;

        /// Create a textArea for the description so that the text can wrap.
        fn customDescriptionColumn(src: std.builtin.SourceLocation, grid: *GridWidget, col_num: usize, data: []Car, opts: *const GridWidget.CellStyle.Banded) void {
            for (data, 0..) |*car, row_num| {
                var col = grid.bodyCell(src, col_num, row_num, opts.cellOptions(col_num, row_num));
                defer col.deinit();
                var text = dvui.textLayout(@src(), .{ .break_lines = true }, .{ .expand = .both, .background = false });
                defer text.deinit();
                text.addText(car.description, opts.options(col_num, row_num));
            }
        }

        const ConditionTextColor = struct {
            base_opts: *const GridWidget.CellStyle.Banded,

            pub fn init(base_opts: *const GridWidget.CellStyle.Banded) ConditionTextColor {
                return .{
                    .base_opts = base_opts,
                };
            }

            pub fn cellOptions(self: *const ConditionTextColor, col: usize, row: usize) GridWidget.CellOptions {
                return self.base_opts.cellOptions(col, row);
            }

            pub fn options(self: *const ConditionTextColor, col: usize, row: usize) dvui.Options {
                return self.base_opts.options(col, row).override(conditionTextColor(row));
            }
            /// Set the text color of the Condition text, based on the condition.
            fn conditionTextColor(row_num: usize) Options {
                return .{
                    .expand = .horizontal,
                    .gravity_x = 0.5,
                    .color_text = switch (all_cars[row_num].condition) {
                        .New => .{ .color = dvui.Color.fromHex("#4bbfc3") },
                        .Excellent => .{ .color = dvui.Color.fromHex("#6ca96c") },
                        .Good => .{ .color = dvui.Color.fromHex("#a3b76b") },
                        .Fair => .{ .color = dvui.Color.fromHex("#d3b95f") },
                        .Poor => .{ .color = dvui.Color.fromHex("#c96b6b") },
                    },
                };
            }
        };

        fn sort(key: []const u8) void {
            switch (sort_dir) {
                .descending,
                => std.mem.sort(Car, &all_cars, key, sortDesc),
                .ascending,
                .unsorted,
                => std.mem.sort(Car, &all_cars, key, sortAsc),
            }
        }

        fn sortAsc(key: []const u8, lhs: Car, rhs: Car) bool {
            if (std.mem.eql(u8, key, "Model")) return std.mem.lessThan(u8, lhs.model, rhs.model);
            if (std.mem.eql(u8, key, "Year")) return lhs.year < rhs.year;
            if (std.mem.eql(u8, key, "Mileage")) return lhs.mileage < rhs.mileage;
            if (std.mem.eql(u8, key, "Condition")) return @intFromEnum(lhs.condition) < @intFromEnum(rhs.condition);
            if (std.mem.eql(u8, key, "Description")) return std.mem.lessThan(u8, lhs.description, rhs.description);
            // default sort on Make
            return std.mem.lessThan(u8, lhs.make, rhs.make);
        }

        fn sortDesc(key: []const u8, lhs: Car, rhs: Car) bool {
            if (std.mem.eql(u8, key, "Model")) return std.mem.lessThan(u8, rhs.model, lhs.model);
            if (std.mem.eql(u8, key, "Year")) return rhs.year < lhs.year;
            if (std.mem.eql(u8, key, "Mileage")) return rhs.mileage < lhs.mileage;
            if (std.mem.eql(u8, key, "Condition")) return @intFromEnum(rhs.condition) < @intFromEnum(lhs.condition);
            if (std.mem.eql(u8, key, "Description")) return std.mem.lessThan(u8, rhs.description, lhs.description);
            // default sort on Make
            return std.mem.lessThan(u8, rhs.make, lhs.make);
        }

        const resize_min = 80;
        const resize_max = 500;
        fn headerResizeOptions(grid: *GridWidget, col_num: usize) ?GridWidget.HeaderResizeWidget.InitOptions {
            _ = grid;
            if (layout_style != .user_resizable) return .fixed;
            return .{
                .sizes = &col_widths,
                .num = col_num,
                .min_size = resize_min,
                .max_size = resize_max,
            };
        }

        var all_cars = [_]Car{
            .{ .model = "Civic", .make = "Honda", .year = 2022, .mileage = 8500, .condition = .New, .description = "Still smells like optimism and plastic wrap." },
            .{ .model = "Model 3", .make = "Tesla", .year = 2021, .mileage = 15000, .condition = .Excellent, .description = "Drives itself better than I drive myself." },
            .{ .model = "Camry", .make = "Toyota", .year = 2018, .mileage = 43000, .condition = .Good, .description = "Reliable enough to make your toaster jealous." },
            .{ .model = "F-150", .make = "Ford", .year = 2015, .mileage = 78000, .condition = .Fair, .description = "Hauls stuff, occasional emotions." },
            .{ .model = "Altima", .make = "Nissan", .year = 2010, .mileage = 129000, .condition = .Poor, .description = "Drives like it’s got beef with the road." },
            .{ .model = "Accord", .make = "Honda", .year = 2019, .mileage = 78000, .condition = .Excellent, .description = "Sensible and smooth, like your friend with a Costco card." },
            .{ .model = "Impreza", .make = "Subaru", .year = 2016, .mileage = 78000, .condition = .Good, .description = "All-wheel drive and all-weather vibes." },
            .{ .model = "Charger", .make = "Dodge", .year = 2014, .mileage = 97000, .condition = .Fair, .description = "Goes fast, stops… usually." },
            .{ .model = "Beetle", .make = "Volkswagen", .year = 2006, .mileage = 142000, .condition = .Poor, .description = "Quirky, creaky, and still kinda cute." },
            .{ .model = "Mustang", .make = "Ford", .year = 2020, .mileage = 24000, .condition = .Good, .description = "Makes you feel 20% cooler just sitting in it." },
            .{ .model = "CX-5", .make = "Mazda", .year = 2019, .mileage = 32000, .condition = .Excellent, .description = "Zoom zoom, but responsibly." },
            .{ .model = "Outback", .make = "Subaru", .year = 2017, .mileage = 61000, .condition = .Good, .description = "Always looks ready for a camping trip, even when it's not." },
            .{ .model = "Civic", .make = "Honda", .year = 2022, .mileage = 8500, .condition = .New, .description = "Still smells like optimism and plastic wrap." },
            .{ .model = "Model 3", .make = "Tesla", .year = 2021, .mileage = 15000, .condition = .Excellent, .description = "Drives itself better than I drive myself." },
            .{ .model = "Camry", .make = "Toyota", .year = 2018, .mileage = 43000, .condition = .Good, .description = "Reliable enough to make your toaster jealous." },
            .{ .model = "F-150", .make = "Ford", .year = 2015, .mileage = 78000, .condition = .Fair, .description = "Hauls stuff, occasional emotions." },
            .{ .model = "Altima", .make = "Nissan", .year = 2010, .mileage = 129000, .condition = .Poor, .description = "Drives like it’s got beef with the road." },
            .{ .model = "Accord", .make = "Honda", .year = 2019, .mileage = 78000, .condition = .Excellent, .description = "Sensible and smooth, like your friend with a Costco card." },
            .{ .model = "Impreza", .make = "Subaru", .year = 2016, .mileage = 78000, .condition = .Good, .description = "All-wheel drive and all-weather vibes." },
            .{ .model = "Charger", .make = "Dodge", .year = 2014, .mileage = 97000, .condition = .Fair, .description = "Goes fast, stops… usually." },
            .{ .model = "Beetle", .make = "Volkswagen", .year = 2006, .mileage = 142000, .condition = .Poor, .description = "Quirky, creaky, and still kinda cute." },
            .{ .model = "Mustang with a really long name", .make = "Ford", .year = 2020, .mileage = 24000, .condition = .Good, .description = "Makes you feel 20% cooler just sitting in it." },
        };
    };
    const all_cars = local.all_cars[0..];

    const panel_height = 250;
    const banded: GridWidget.CellStyle.Banded = .{
        .opts = .{
            .margin = TextLayoutWidget.defaults.margin,
            .padding = TextLayoutWidget.defaults.padding,
        },
        .alt_cell_opts = .{
            .color_fill = .{ .name = .fill_press },
            .background = true,
        },
    };
    const banded_centered = banded.optionsOverride(.{ .gravity_x = 0.5, .expand = .horizontal });

    const content_h = dvui.parentGet().data().contentRect().h - panel_height;
    {
        const scroll_opts: ?dvui.ScrollAreaWidget.InitOpts = if (local.h_scroll)
            .{ .horizontal = .auto, .horizontal_bar = .show, .vertical = .auto, .vertical_bar = .show }
        else
            null;

        var grid = dvui.grid(@src(), .colWidths(&local.col_widths), .{
            .scroll_opts = scroll_opts,
            .resize_rows = local.resize_rows,
        }, .{
            .expand = .both,
            .background = true,
            .border = Rect.all(2),
            .min_size_content = .{ .h = content_h },
            .max_size_content = .height(content_h),
        });
        defer grid.deinit();
        local.resize_rows = false;

        const col_widths_src: ?[]const f32 = switch (local.layout_style) {
            .equal_spacing => &local.equal_spacing,
            .fixed_width => &local.fixed_widths,
            .proportional => &local.column_ratios,
            .fit_window => &local.equal_spacing,
            .user_resizable => null,
        };
        if (col_widths_src) |col_widths| {
            switch (local.layout_style) {
                .fit_window => {
                    dvui.columnLayoutProportional(col_widths, &local.col_widths, grid.data().contentRect().w);
                },
                else => {
                    // Fit columns to the grid visible area, or to the virtual scroll area if horizontal scorlling is enabled.
                    dvui.columnLayoutProportional(col_widths, &local.col_widths, if (local.h_scroll) 1024 else grid.data().contentRect().w);
                },
            }
        }

        if (dvui.gridHeadingCheckbox(@src(), grid, 0, &local.selection_state, .{})) {
            for (all_cars) |*car| {
                car.selected = switch (local.selection_state) {
                    .select_all => true,
                    .select_none => false,
                    .unchanged => break,
                };
            }
        }
        if (dvui.gridHeadingSortable(@src(), grid, 1, "Make", &local.sort_dir, local.headerResizeOptions(grid, 1), .{})) {
            local.sort("Make");
        }
        if (dvui.gridHeadingSortable(@src(), grid, 2, "Model", &local.sort_dir, local.headerResizeOptions(grid, 2), .{})) {
            local.sort("Model");
        }
        if (dvui.gridHeadingSortable(@src(), grid, 3, "Year", &local.sort_dir, local.headerResizeOptions(grid, 3), .{})) {
            local.sort("Year");
        }
        if (dvui.gridHeadingSortable(@src(), grid, 4, "Condition", &local.sort_dir, local.headerResizeOptions(grid, 4), .{})) {
            local.sort("Condition");
        }
        if (dvui.gridHeadingSortable(@src(), grid, 5, "Description", &local.sort_dir, local.headerResizeOptions(grid, 5), .{})) {
            local.sort("Description");
        }

        // Selection
        {
            // Make the checkbox column fixed width. (This width is used if init_opts.col_widths is null)
            _ = dvui.gridColumnCheckbox(@src(), grid, 0, Car, all_cars[0..], "selected", banded.optionsOverride(.{ .gravity_y = 0 }));
        }
        // Make
        {
            dvui.gridColumnFromSlice(@src(), grid, 1, Car, all_cars[0..], "make", "{s}", banded);
        }
        // Model
        {
            dvui.gridColumnFromSlice(@src(), grid, 2, Car, all_cars[0..], "model", "{s}", banded);
        }
        // Year
        {
            dvui.gridColumnFromSlice(@src(), grid, 3, Car, all_cars[0..], "year", "{d}", banded);
        }
        // Condition
        {
            dvui.gridColumnFromSlice(@src(), grid, 4, Car, all_cars[0..], "condition", "{s}", local.ConditionTextColor.init(&banded_centered));
        }
        // Description
        {
            local.customDescriptionColumn(@src(), grid, 5, all_cars[0..], &banded);
        }
    }
    {
        var outer_vbox = dvui.box(@src(), .vertical, .{
            .expand = .horizontal,
            .border = Rect.all(1),
        });
        defer outer_vbox.deinit();

        if (dvui.expander(@src(), "Layouts", .{ .default_expanded = true }, .{ .expand = .horizontal })) {
            {
                var fbox = dvui.flexbox(@src(), .{ .justify_content = .start }, .{});
                defer fbox.deinit();

                if (dvui.radio(@src(), local.layout_style == .proportional, "Proportional", .{})) {
                    local.layout_style = .proportional;
                }
                if (dvui.radio(@src(), local.layout_style == .equal_spacing, "Equal spacing", .{})) {
                    local.layout_style = .equal_spacing;
                }
                if (dvui.radio(@src(), local.layout_style == .fixed_width, "Fixed widths", .{})) {
                    local.layout_style = .fixed_width;
                }
                if (dvui.radio(@src(), local.layout_style == .fit_window, "Fit window", .{})) {
                    local.h_scroll = false;
                    local.layout_style = .fit_window;
                }
                if (dvui.radio(@src(), local.layout_style == .user_resizable, "Resizable", .{})) {
                    local.layout_style = .user_resizable;
                    for (local.col_widths[1..]) |*w| {
                        w.* = std.math.clamp(w.*, local.resize_min, local.resize_max);
                    }
                }
            }
            {
                var fbox = dvui.flexbox(@src(), .{ .justify_content = .start }, .{});
                defer fbox.deinit();

                if (dvui.checkbox(@src(), &local.h_scroll, "Horizontal scrolling", .{})) {
                    if (local.layout_style == .fit_window) {
                        local.layout_style = .proportional;
                    }
                }

                if (dvui.button(@src(), "Resize Rows", .{}, .{})) {
                    local.resize_rows = true;
                }
            }
        }
    }
}

fn gridVirtualScrolling() void {
    const num_rows = 1_000_000;
    const local = struct {
        var scroll_info: dvui.ScrollInfo = .{ .vertical = .given, .horizontal = .none };
        var primes: std.StaticBitSet(num_rows) = .initFull();
        var generated_primes: bool = false;
        var highlighted_row: ?usize = null;
        var last_col_width: f32 = 0;
        var resize_cols: bool = false;

        // Generate prime numbers using The Sieve of Eratosthenes.
        fn generatePrimes() void {
            if (num_rows > 0) primes.unset(0);
            if (num_rows > 1) primes.unset(1);

            const limit = std.math.sqrt(num_rows);
            var factor: u32 = 2;
            while (factor < limit) : (factor += 1) {
                if (primes.isSet(factor)) {
                    var multiples = factor * factor;
                    while (multiples < num_rows) : (multiples += factor) {
                        primes.unset(multiples);
                    }
                }
            }
        }

        fn isPrime(num: usize) bool {
            return primes.isSet(num);
        }
    };

    if (!local.generated_primes) {
        local.generatePrimes();
        local.generated_primes = true;
    }

    var vbox = dvui.box(@src(), .vertical, .{ .expand = .both });
    defer vbox.deinit();
    var grid = dvui.grid(@src(), .numCols(2), .{
        .scroll_opts = .{ .scroll_info = &local.scroll_info },
        .resize_cols = local.resize_cols,
    }, .{
        .expand = .both,
        .background = true,
        .border = Rect.all(1),
    });
    defer grid.deinit();
    local.resize_cols = false;

    // dvui.columnLayoutProportional is normally used to calculate column sizes. This example is highlighting
    // passing column widths though the cell options rather than using the col_widths slice.
    // Note that if column widths change size, the resize_cols init option must be used.
    const col_width = (grid.data().contentRect().w - GridWidget.scrollbar_padding_defaults.w) / 2.0;
    if (col_width < local.last_col_width) {
        local.resize_cols = true;
    }
    local.last_col_width = col_width;

    // Highlight hovered row.
    // Each column has slightly different border requirements, so create separate options for each.
    // Calls cellOptionsOverride after processEvents() so that the hovered row only needs to be calculated once.
    var highlight_hovered_1: GridWidget.CellStyle.HoveredRow = .{
        .cell_opts = .{
            .border = .{ .x = 1, .w = 1, .h = 1 },
            .background = true,
            .color_fill_hover = .fill_hover,
            .size = .{ .w = col_width },
        },
    };
    highlight_hovered_1.processEvents(grid, &local.scroll_info);
    const highlight_hovered_2 = highlight_hovered_1.cellOptionsOverride(.{
        .border = .{ .w = 1, .h = 1 },
    });

    // Virtual scrolling
    const scroller: dvui.GridWidget.VirtualScroller = .init(grid, .{ .total_rows = num_rows, .scroll_info = &local.scroll_info });
    const first = scroller.startRow();
    const last = scroller.endRow(); // Note that endRow is exclusive, meaning it can be used as a slice end index.
    const CellStyle = GridWidget.CellStyle;
    dvui.gridHeading(@src(), grid, "Number", 0, .fixed, CellStyle{ .cell_opts = .{ .size = .{ .w = col_width } } });
    dvui.gridHeading(@src(), grid, "Is prime?", 1, .fixed, CellStyle{ .cell_opts = .{ .size = .{ .w = col_width } } });

    for (first..last) |num| {
        {
            var cell = grid.bodyCell(@src(), 0, num, highlight_hovered_1.cellOptions(0, num));
            defer cell.deinit();
            dvui.label(@src(), "{d}", .{num}, .{});
        }
        {
            const check_img = @embedFile("icons/entypo/check.tvg");

            var cell = grid.bodyCell(@src(), 1, num, highlight_hovered_2.cellOptions(1, num));
            defer cell.deinit();
            if (local.isPrime(num)) {
                dvui.icon(@src(), "Check", check_img, .{}, .{ .gravity_x = 0.5, .gravity_y = 0.5, .background = false });
            }
        }
    }
}

fn gridVariableRowHeights() void {
    var grid = dvui.grid(@src(), .numCols(1), .{ .var_row_heights = true }, .{
        .expand = .both,
        .padding = Rect.all(0),
    });
    defer grid.deinit();

    // Use of CellStyle is optional, but useful when applying the same styling to multiple columns.
    // CellOptions and Options can be passed directly to bodyCell() and label() if preferred.
    const cell_style: GridWidget.CellStyle = .{
        .cell_opts = .{ .border = Rect.all(1) },
        .opts = .{ .gravity_x = 0.5, .gravity_y = 0.5, .expand = .both },
    };
    for (1..10) |row_num| {
        const row_num_i: i32 = @intCast(row_num);
        const row_height = 70 - (@abs(row_num_i - 5) * 10);
        var cell = grid.bodyCell(
            @src(),
            0,
            row_num,
            cell_style.cellOptions(0, row_num).override(.{ .size = .{ .h = @floatFromInt(row_height), .w = 500 } }),
        );
        defer cell.deinit();
        dvui.label(@src(), "h = {d}", .{row_height}, cell_style.options(0, row_num));
    }
}

fn background_dialog(win: *dvui.Window, delay_ns: u64) void {
    std.time.sleep(delay_ns);
    dvui.dialog(@src(), .{}, .{ .window = win, .modal = false, .title = "Background Dialog", .message = "This non modal dialog was added from a non-GUI thread." });
}

fn background_toast(win: *dvui.Window, delay_ns: u64, subwindow_id: ?dvui.WidgetId) void {
    std.time.sleep(delay_ns);
    dvui.refresh(win, @src(), null);
    dvui.toast(@src(), .{ .window = win, .subwindow_id = subwindow_id, .message = "Toast came from a non-GUI thread" });
}

fn background_progress(win: *dvui.Window, delay_ns: u64) void {
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

pub fn show_stroke_test_window() void {
    var win = dvui.floatingWindow(@src(), .{ .rect = &StrokeTest.show_rect, .open_flag = &StrokeTest.show }, .{});
    defer win.deinit();
    win.dragAreaSet(dvui.windowHeader("Stroke Test", "", &StrokeTest.show));

    dvui.label(@src(), "Stroke Test", .{}, .{});
    _ = dvui.checkbox(@src(), &stroke_test_closed, "Closed", .{});
    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Endcap Style", .{}, .{});

        if (dvui.radio(@src(), StrokeTest.endcap_style == .none, "None", .{})) {
            StrokeTest.endcap_style = .none;
        }

        if (dvui.radio(@src(), StrokeTest.endcap_style == .square, "Square", .{})) {
            StrokeTest.endcap_style = .square;
        }
    }

    var st = StrokeTest{};
    st.install(@src(), .{ .min_size_content = .{ .w = 400, .h = 400 }, .expand = .both });
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
    var endcap_style: dvui.Path.StrokeOptions.EndCapStyle = .none;

    wd: dvui.WidgetData = undefined,

    pub fn install(self: *Self, src: std.builtin.SourceLocation, options: dvui.Options) void {
        _ = dvui.sliderEntry(@src(), "thick: {d:0.2}", .{ .value = &thickness }, .{ .expand = .horizontal });

        const defaults = dvui.Options{ .name = "StrokeTest" };
        self.wd = dvui.WidgetData.init(src, .{}, defaults.override(options));
        self.wd.register();

        const evts = dvui.events();
        for (evts) |*e| {
            if (!dvui.eventMatchSimple(e, self.data()))
                continue;

            self.processEvent(e);
        }

        self.data().borderAndBackground(.{});

        _ = dvui.parentSet(self.widget());

        const rs = self.data().contentRectScale();
        const fill_color = dvui.Color{ .r = 200, .g = 200, .b = 200, .a = 255 };
        for (points, 0..) |p, i| {
            const rect = dvui.Rect.fromPoint(p.plus(.{ .x = -10, .y = -10 })).toSize(.{ .w = 20, .h = 20 });
            rs.rectToPhysical(rect).fill(.all(1), .{ .color = fill_color });

            _ = i;
            //_ = dvui.button(@src(), i, "Floating", .{}, .{ .rect = dvui.Rect.fromPoint(p) });
        }

        if (dvui.currentWindow().lifo().alloc(dvui.Point.Physical, points.len) catch null) |path| {
            defer dvui.currentWindow().lifo().free(path);

            for (points, path) |p, *path_point| {
                path_point.* = rs.pointToPhysical(p);
            }

            const stroke_color = dvui.Color{ .r = 0, .g = 0, .b = 255, .a = 150 };
            dvui.Path.stroke(.{ .points = path }, .{ .thickness = rs.s * thickness, .color = stroke_color, .closed = stroke_test_closed, .endcap_style = StrokeTest.endcap_style });
        }
    }

    pub fn widget(self: *Self) dvui.Widget {
        return dvui.Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
    }

    pub fn data(self: *Self) *dvui.WidgetData {
        return self.wd.validate();
    }

    pub fn rectFor(self: *Self, id: dvui.WidgetId, min_size: dvui.Size, e: dvui.Options.Expand, g: dvui.Options.Gravity) dvui.Rect {
        _ = id;
        return dvui.placeIn(self.data().contentRect().justSize(), min_size, e, g);
    }

    pub fn screenRectScale(self: *Self, rect: dvui.Rect) dvui.RectScale {
        return self.data().contentRectScale().rectToRectScale(rect);
    }

    pub fn minSizeForChild(self: *Self, s: dvui.Size) void {
        self.data().minSizeMax(self.data().options.padSize(s));
    }

    pub fn processEvent(self: *Self, e: *dvui.Event) void {
        switch (e.evt) {
            .mouse => |me| {
                const rs = self.data().contentRectScale();
                const mp = rs.pointFromPhysical(me.p);
                switch (me.action) {
                    .press => {
                        if (me.button == .left) {
                            e.handle(@src(), self.data());
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
                                dvui.captureMouse(self.data(), e.num);
                                dvui.dragPreStart(me.p, .{ .cursor = .crosshair });
                            }
                        }
                    },
                    .release => {
                        if (me.button == .left) {
                            e.handle(@src(), self.data());
                            dvui.captureMouse(null, e.num);
                            dvui.dragEnd();
                        }
                    },
                    .motion => {
                        e.handle(@src(), self.data());
                        if (dvui.dragging(me.p)) |dps| {
                            const dp = dps.scale(1 / rs.s, Point);
                            points[dragi.?].x += dp.x;
                            points[dragi.?].y += dp.y;
                            dvui.refresh(null, @src(), self.data().id);
                        }
                    },
                    .wheel_y => |ticks| {
                        e.handle(@src(), self.data());
                        const base: f32 = 1.02;
                        const zs = @exp(@log(base) * ticks);
                        if (zs != 1.0) {
                            thickness *= zs;
                            dvui.refresh(null, @src(), self.data().id);
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    pub fn deinit(self: *Self) void {
        self.data().minSizeSetAndRefresh();
        self.data().minSizeReportToParent();

        dvui.parentReset(self.data().id, self.data().parent);
        self.* = undefined;
    }
};

test {
    //std.debug.print("Examples test\n", .{});
    std.testing.refAllDecls(@This());
}

test "DOCIMG demo" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    dvui.Examples.show_demo_window = true;

    const frame = struct {
        fn frame() !dvui.App.Result {
            dvui.Examples.demo();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, dvui.tagGet(demo_window_tag).?.rect, "Examples-demo.png");
    // this works, but unsure it's what we want, so disable for now
    //inline for (0..@typeInfo(demoKind).@"enum".fields.len) |i| {
    //    const e = @as(demoKind, @enumFromInt(i));

    //    try dvui.testing.moveTo("demo_button_" ++ @tagName(e));
    //    try dvui.testing.click(.left);
    //    try dvui.testing.settle(frame);

    //    try t.saveImage(frame, dvui.tagGet(demo_window_tag).?.rect, "Examples-" ++ @tagName(e) ++ ".png");

    //    try dvui.testing.moveTo("dvui_demo_window_back");
    //    try dvui.testing.click(.left);
    //    try dvui.testing.settle(frame);
    //}
}

test "DOCIMG basic_widgets" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 500, .h = 500 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            basicWidgets();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-basic_widgets.png");
}

test "DOCIMG calculator" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 250, .h = 250 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            calculator();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-calculator.png");
}

test "DOCIMG text_entry" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 500, .h = 500 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            textEntryWidgets(box.data().id);
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-text_entry.png");
}

test "DOCIMG styling" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 500, .h = 300 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            styling();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-styling.png");
}

test "DOCIMG layout" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 500, .h = 800 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            layout();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-layout.png");
}

test "DOCIMG text_layout" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 500, .h = 500 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            layoutText();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-text_layout.png");
}

test "DOCIMG plots" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 500, .h = 300 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            plots();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-plots.png");
}

test "DOCIMG reorderable" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 400, .h = 500 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            reorderLists();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-reorderable.png");
}

test "DOCIMG menus" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 300, .h = 500 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            menus();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-menus.png");
}

test "DOCIMG scrolling" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 500, .h = 400 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            scrolling();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-scrolling.png");
}

test "DOCIMG scroll_canvas" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 300, .h = 400 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            scrollCanvas();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-scroll_canvas.png");
}

test "DOCIMG dialogs" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 400, .h = 300 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            dialogs(box.data().id);
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);

    // Tab to the main window toast button
    for (0..8) |_| {
        try dvui.testing.pressKey(.tab, .none);
        _ = try dvui.testing.step(frame);
    }
    try dvui.testing.pressKey(.enter, .none);

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-dialogs.png");
}

test "DOCIMG animations" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 500, .h = 400 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            animations();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);

    // Tab to spinner expander and open it
    for (0..4) |_| {
        try dvui.testing.pressKey(.tab, .none);
        _ = try dvui.testing.step(frame);
    }
    try dvui.testing.pressKey(.enter, .none);
    _ = try dvui.testing.step(frame);

    // Tab to easings expander and open it
    try dvui.testing.pressKey(.tab, .lshift);
    _ = try dvui.testing.step(frame);
    try dvui.testing.pressKey(.enter, .none);
    for (0..10) |_| {
        _ = try dvui.testing.step(frame); // animation will never settle so run a fixed amount of frames
    }
    try t.saveImage(frame, null, "Examples-animations.png");
}

test "DOCIMG struct_ui" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 400, .h = 700 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            structUI();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-struct_ui.png");
}

test "DOCIMG debugging" {
    // This tests intentionally logs errors, which fails with the normal test runner.
    // We skip this test instead of downgrading all log.err to log.warn as we usually
    // want to fail if dvui logs errors (for duplicate id's or similar)
    if (!dvui.testing.is_dvui_doc_gen_runner) return error.SkipZigTest;

    std.debug.print("IGNORE ERROR LOGS FOR THIS TEST, IT IS EXPECTED\n", .{});

    var t = try dvui.testing.init(.{ .window_size = .{ .w = 500, .h = 500 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            debuggingErrors();
            return .ok;
        }
    }.frame;

    // Tab to duplicate id expander and open it
    for (0..5) |_| {
        try dvui.testing.pressKey(.tab, .none);
        _ = try dvui.testing.step(frame);
    }
    try dvui.testing.pressKey(.enter, .none);
    _ = try dvui.testing.step(frame);

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-debugging.png");
}

test "DOCIMG icon_browser" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 400, .h = 500 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            var show_flag: bool = true;
            icon_browser(@src(), &show_flag, "entypo", entypo);
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-icon_browser.png");
}

test "DOCIMG themeEditor" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 400, .h = 500 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            themeEditor();
            return .ok;
        }
    }.frame;

    // tab to a color editor expander and open it
    try dvui.testing.pressKey(.tab, .none);
    _ = try dvui.testing.step(frame);
    try dvui.testing.pressKey(.tab, .none);
    _ = try dvui.testing.step(frame);
    try dvui.testing.pressKey(.tab, .none);
    _ = try dvui.testing.step(frame);
    try dvui.testing.pressKey(.tab, .none);
    _ = try dvui.testing.step(frame);
    try dvui.testing.pressKey(.tab, .none);
    _ = try dvui.testing.step(frame);
    try dvui.testing.pressKey(.enter, .none);

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-themeEditor.png");
}
