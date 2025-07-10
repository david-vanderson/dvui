//! ![demo](Examples-demo.png)

const builtin = @import("builtin");
const std = @import("std");
const dvui = @import("dvui.zig");

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

const basicWidgets = @import("Examples/basic_widgets.zig").basicWidgets;
const calculator = @import("Examples/calculator.zig").calculator;
const textEntryWidgets = @import("Examples/text_entry.zig").textEntryWidgets;
const styling = @import("Examples/styling.zig").styling;
const layout = @import("Examples/layout.zig").layout;
const layoutText = @import("Examples/text_layout.zig").layoutText;
const plots = @import("Examples/plots.zig").plots;
const reorderLists = @import("Examples/reorder_tree.zig").reorderLists;
const menus = @import("Examples/menus.zig").menus;
const scrolling = @import("Examples/scrolling.zig").scrolling;
const scrollCanvas = @import("Examples/scroll_canvas.zig").scrollCanvas;
const dialogs = @import("Examples/dialogs.zig").dialogs;
const animations = @import("Examples/animations.zig").animations;

pub const zig_favicon = @embedFile("zig-favicon.png");
pub const zig_svg = @embedFile("zig-mark.svg");

pub var show_demo_window: bool = false;
pub var icon_browser_show: bool = false;
var frame_counter: u64 = 0;
var checkbox_bool: bool = false;
var dropdown_val: usize = 1;
pub var show_dialog: bool = false;
var scale_val: f32 = 1.0;
var line_height_factor: f32 = 1.2;
var paned_collapsed_width: f32 = 400;

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
                    .grid => grids(),
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
        var vbox = dvui.box(@src(), .vertical, .{ .expand = .both });
        defer vbox.deinit();

        {
            var hbox = dvui.box(@src(), .horizontal, .{});
            defer hbox.deinit();

            if (paned.collapsed() and dvui.button(@src(), "Back to Demos", .{}, .{ .min_size_content = .{ .h = 30 }, .tag = "dvui_demo_window_back" })) {
                paned.animateSplit(1.0);
            }

            dvui.label(@src(), "{s}", .{demo_active.name()}, .{ .font_style = .title_2, .gravity_y = 0.5 });
        }

        var scroll: ?*dvui.ScrollAreaWidget = null;
        if (demo_active != .grid) {
            scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .background = false, .padding = Rect.all(4) });
        }
        defer if (scroll) |s| s.deinit();

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
            .grid => grids(),
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

    // This broke when I added Options.data_out, and I don't know why
    //if (dvui.expander(@src(), "Edit Current Theme", .{}, .{ .expand = .horizontal })) {
    //    themeEditor();
    //}
}

/// ![image](Examples-themeEditor.png)
//pub fn themeEditor() void {
//    var b2 = dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
//    defer b2.deinit();
//
//    const color_field_options = dvui.StructFieldOptions(dvui.Color){ .fields = .{
//        .r = .{ .min = 0, .max = 255, .widget_type = .slider },
//        .g = .{ .min = 0, .max = 255, .widget_type = .slider },
//        .b = .{ .min = 0, .max = 255, .widget_type = .slider },
//        .a = .{ .disabled = true },
//    } };
//
//    dvui.structEntryEx(@src(), "dvui.Theme", dvui.Theme, dvui.themeGet(), .{
//        .use_expander = false,
//        .label_override = "",
//        .fields = .{
//            .name = .{ .disabled = true },
//            .dark = .{ .widget_type = .toggle },
//            .style_err = .{ .disabled = true },
//            .style_accent = .{ .disabled = true },
//            .font_body = .{ .disabled = true },
//            .font_heading = .{ .disabled = true },
//            .font_caption = .{ .disabled = true },
//            .font_caption_heading = .{ .disabled = true },
//            .font_title = .{ .disabled = true },
//            .font_title_1 = .{ .disabled = true },
//            .font_title_2 = .{ .disabled = true },
//            .font_title_3 = .{ .disabled = true },
//            .font_title_4 = .{ .disabled = true },
//            .color_accent = color_field_options,
//            .color_err = color_field_options,
//            .color_text = color_field_options,
//            .color_text_press = color_field_options,
//            .color_fill = color_field_options,
//            .color_fill_window = color_field_options,
//            .color_fill_control = color_field_options,
//            .color_fill_hover = color_field_options,
//            .color_fill_press = color_field_options,
//            .color_border = color_field_options,
//        },
//    });
//}

pub fn themeSerialization() void {
    var serialize_box = dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
    defer serialize_box.deinit();

    dvui.labelNoFmt(@src(), "TODO: demonstrate loading a quicktheme here", .{}, .{});
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

pub fn grids() void {
    const GridType = enum {
        styling,
        layout,
        scrolling,
        row_heights,
        selection,
        navigation,
        const num_grids = @typeInfo(@This()).@"enum".fields.len;
    };

    const local = struct {
        var active_grid: GridType = .styling;

        fn tabSelected(grid_type: GridType) bool {
            return active_grid == grid_type;
        }

        fn tabName(grid_type: GridType) []const u8 {
            return switch (grid_type) {
                .styling => "Styling and\nsorting",
                .layout => "Layouts and\ndata",
                .scrolling => "Virtual\nscrolling",
                .row_heights => "Variable row\nheights",
                .selection => "Selection\n ",
                .navigation => "Keyboard\nnavigation",
            };
        }
    };

    var tbox = dvui.box(@src(), .vertical, .{ .border = Rect.all(1), .expand = .both });
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
        .selection => gridSelection(),
        .navigation => gridNavigation(),
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
                var cell = grid.bodyCell(@src(), .colRow(0, row_num), cell_opts.cellOptions(.colRow(0, row_num)));
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
                var cell = grid.bodyCell(@src(), .colRow(1, row_num), cell_opts.cellOptions(.colRow(1, row_num)));
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
        var selection_state: dvui.selection.SelectAllState = .select_none;
        var sort_dir: GridWidget.SortDirection = .unsorted;
        var layout_style: Layout = .proportional;
        var h_scroll: bool = false;
        var resize_rows: bool = false;

        /// Create a textArea for the description so that the text can wrap.
        const ConditionTextColor = struct {
            base_opts: *const GridWidget.CellStyle.Banded,

            pub fn init(base_opts: *const GridWidget.CellStyle.Banded) ConditionTextColor {
                return .{
                    .base_opts = base_opts,
                };
            }

            pub fn cellOptions(self: *const ConditionTextColor, cell: GridWidget.Cell) GridWidget.CellOptions {
                return self.base_opts.cellOptions(cell);
            }

            pub fn options(self: *const ConditionTextColor, cell: GridWidget.Cell) dvui.Options {
                return self.base_opts.options(cell).override(conditionTextColor(cell.row_num));
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

        for (all_cars[0..], 0..) |*car, row_num| {
            var cell: GridWidget.Cell = .colRow(0, row_num);

            // Selection
            {
                defer cell.col_num += 1;
                var cell_box = grid.bodyCell(@src(), cell, banded.cellOptions(cell));
                defer cell_box.deinit();
                _ = dvui.checkbox(@src(), &car.selected, null, banded.options(cell).override(.{ .gravity_y = 0, .gravity_x = 0.5 }));
            }
            // Make
            {
                defer cell.col_num += 1;
                var cell_box = grid.bodyCell(@src(), cell, banded.cellOptions(cell));
                defer cell_box.deinit();
                dvui.labelNoFmt(@src(), car.make, .{}, banded.options(cell));
            }
            // Model
            {
                defer cell.col_num += 1;
                var cell_box = grid.bodyCell(@src(), cell, banded.cellOptions(cell));
                defer cell_box.deinit();
                dvui.labelNoFmt(@src(), car.model, .{}, banded.options(cell));
            }
            // Year
            {
                defer cell.col_num += 1;
                var cell_box = grid.bodyCell(@src(), cell, banded.cellOptions(cell));
                defer cell_box.deinit();
                dvui.label(@src(), "{d}", .{car.year}, banded.options(cell));
            }
            // Condition
            {
                defer cell.col_num += 1;
                var cell_box = grid.bodyCell(@src(), cell, banded.cellOptions(cell));
                defer cell_box.deinit();
                const cell_style = local.ConditionTextColor.init(&banded_centered);
                dvui.labelNoFmt(@src(), @tagName(car.condition), .{}, cell_style.options(cell));
            }
            // Description
            {
                defer cell.col_num += 1;
                var cell_box = grid.bodyCell(@src(), cell, banded.cellOptions(cell));
                defer cell_box.deinit();
                var text = dvui.textLayout(@src(), .{ .break_lines = true }, .{ .expand = .both, .background = false });
                defer text.deinit();
                text.addText(car.description, banded.options(cell));
            }
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

    // Demonstrates how to combine two cellstyles together, drawing borders and
    // highlighting the hovered row.
    const CellStyle = GridWidget.CellStyle;
    var highlight_hovered: CellStyle.HoveredRow = .{
        .cell_opts = .{
            .background = true,
            .color_fill_hover = .fill_hover,
            .size = .{ .w = col_width },
        },
    };
    highlight_hovered.processEvents(grid);

    var borders: CellStyle.Borders = .initBox(2, num_rows, 1, 1);
    borders.external.y = 0; // The grid border already does this side.

    const cell_style: CellStyle.Combine(CellStyle.HoveredRow, CellStyle.Borders) = .{
        .style1 = highlight_hovered,
        .style2 = borders,
    };

    // Virtual scrolling
    const scroller: dvui.GridWidget.VirtualScroller = .init(grid, .{ .total_rows = num_rows, .scroll_info = &local.scroll_info });
    const first = scroller.startRow();
    const last = scroller.endRow(); // Note that endRow is exclusive, meaning it can be used as a slice end index.
    dvui.gridHeading(@src(), grid, 0, "Number", .fixed, CellStyle{ .cell_opts = .{ .size = .{ .w = col_width } } });
    dvui.gridHeading(@src(), grid, 1, "Is prime?", .fixed, CellStyle{ .cell_opts = .{ .size = .{ .w = col_width } } });

    for (first..last) |num| {
        var cell_num: GridWidget.Cell = .colRow(0, num);
        {
            defer cell_num.col_num += 1;
            var cell = grid.bodyCell(@src(), cell_num, cell_style.cellOptions(cell_num));
            defer cell.deinit();
            dvui.label(@src(), "{d}", .{num}, .{});
        }
        {
            defer cell_num.col_num += 1;
            const check_img = @embedFile("icons/entypo/check.tvg");

            var cell = grid.bodyCell(@src(), cell_num, cell_style.cellOptions(cell_num));
            defer cell.deinit();
            if (local.isPrime(num)) {
                dvui.icon(@src(), "Check", check_img, .{}, .{ .gravity_x = 0.5, .gravity_y = 0.5, .background = false });
            }
        }
    }
}

fn gridVariableRowHeights() void {
    var grid = dvui.grid(@src(), .numCols(1), .{ .row_height_variable = true }, .{
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
        const cell_num: GridWidget.Cell = .colRow(0, row_num);
        const row_num_i: i32 = @intCast(row_num);
        const row_height = 70 - (@abs(row_num_i - 5) * 10);
        var cell = grid.bodyCell(
            @src(),
            cell_num,
            cell_style.cellOptions(cell_num).override(.{ .size = .{ .h = @floatFromInt(row_height), .w = 500 } }),
        );
        defer cell.deinit();
        dvui.label(@src(), "h = {d}", .{row_height}, cell_style.options(cell_num));
    }
}

const DirEntry = struct {
    name: []const u8,
    kind: std.fs.Dir.Entry.Kind,
    size: u65,
    mode: u32,
    mtime: i128,

    pub const Iterator = struct {
        idx: usize,
        slice: []const DirEntry,

        pub fn init(slice: []const DirEntry) Iterator {
            return .{
                .idx = 0,
                .slice = slice,
            };
        }

        pub fn next(self: *Iterator) ?*const DirEntry {
            if (self.idx < self.slice.len) {
                defer self.idx += 1;
                return &self.slice[self.idx];
            }
            return null;
        }
    };
};

fn gridSelection() void {
    const CellStyle = dvui.GridWidget.CellStyle;
    const local = struct {
        var initialized: bool = false;
        var selection_mode: enum { multi_select, single_select } = .multi_select;
        var row_select: bool = false;
        var filename_filter: []u8 = "";
        var multi_select: dvui.selection.MultiSelectMouse = .{};
        var kb_select: dvui.selection.SelectAllKeyboard = .{};
        var single_select: dvui.selection.SingleSelect = .{};
        var filtering: bool = false;
        var filtering_changed = false;
        var select_all_state: dvui.selection.SelectAllState = .select_none;
        var selection_info: dvui.selection.SelectionInfo = .{};
        var selections: std.StaticBitSet(directory_examples.len) = .initEmpty();
        var highlight_style: CellStyle.HoveredRow = .{ .cell_opts = .{ .color_fill_hover = .fill_hover, .background = true } };

        pub fn isFiltered(entry: *const DirEntry) bool {
            if (filename_filter.len > 0) {
                return std.mem.indexOf(u8, entry.name, filename_filter) == null;
            }
            return false;
        }

        pub fn selectAll(state: dvui.selection.SelectAllState) void {
            switch (state) {
                .select_all => {
                    selections = .initFull();
                    for (0..selections.capacity()) |i| {
                        if (isFiltered(&directory_examples[i])) {
                            selections.unset(i);
                        }
                    }
                },
                .select_none => selections = .initEmpty(),
            }
        }

        pub fn fromNsTimestamp(timestamp_ns: i128) struct { year: u16, month: u8, day: u8, hour: u8, minute: u8, second: u8 } {
            const days_per_400_years = 146_097;
            const days_per_100_years = 36_524;
            const days_per_4_years = 1_460;

            // Split into days and nanoseconds of the day
            const days_since_epoch: i128 = @divTrunc(timestamp_ns, std.time.ns_per_day);
            const nanos_of_day: i128 = @rem(timestamp_ns, std.time.ns_per_day);

            // Convert nanoseconds of the day to hours, minutes, seconds
            const hour: u8 = @intCast(@divTrunc(nanos_of_day, (std.time.ns_per_s * 3_600)));
            const minute: u8 = @intCast(@divTrunc((@mod(nanos_of_day, (std.time.ns_per_s * 3_600))), (std.time.ns_per_s * 60)));
            const second: u8 = @intCast(@divTrunc((@mod(nanos_of_day, (std.time.ns_per_s * 60))), std.time.ns_per_s));

            // Shift to Gregorian calendar
            const days_since_gregorian_epoch: i128 = days_since_epoch + 719_468; // Difference between unix epoch and gregorian epoch

            // 400-year eras
            const era: i128 = @divTrunc(days_since_gregorian_epoch, days_per_400_years);
            const day_of_era: i128 = days_since_gregorian_epoch - era * days_per_400_years;

            const year_of_era: i128 = @divTrunc(
                day_of_era - @divTrunc(day_of_era, days_per_4_years) + @divTrunc(day_of_era, days_per_100_years) - @divTrunc(day_of_era, days_per_400_years - 1),
                365,
            );
            const day_of_year: i128 = day_of_era - (365 * year_of_era + @divTrunc(year_of_era, 4) - @divTrunc(year_of_era, 100));

            const month_part: i128 = @divTrunc(5 * day_of_year + 2, 153);
            const day: u8 = @intCast(day_of_year - @divTrunc(153 * month_part + 2, 5) + 1);
            const month: u8 = @intCast(month_part + 3 - 12 * @divTrunc(month_part, 10));
            const year: u16 = @intCast(year_of_era + era * 400 + @divTrunc(month_part, 10));

            return .{
                .year = year, // year 65535 bug.
                .month = month,
                .day = day,
                .hour = hour,
                .minute = minute,
                .second = second,
            };
        }
    };
    var outer_vbox = dvui.box(@src(), .vertical, .{ .expand = .both });
    defer outer_vbox.deinit();
    {
        var top_controls = dvui.box(@src(), .horizontal, .{ .gravity_y = 0 });
        defer top_controls.deinit();
        dvui.labelNoFmt(@src(), "Filter (contains): ", .{}, .{ .margin = dvui.TextEntryWidget.defaults.margin });
        var text = dvui.textEntry(@src(), .{}, .{ .expand = .horizontal });
        if (text.text_changed) {
            local.filename_filter = text.getText();
            local.filtering_changed = true;
        } else {
            local.filtering_changed = false;
        }
        defer text.deinit();
    }
    {
        var vbox = dvui.box(@src(), .vertical, .{ .gravity_y = 1.0 });
        defer vbox.deinit();
        if (dvui.expander(@src(), "Options", .{ .default_expanded = true }, .{ .expand = .horizontal })) {
            var hbox = dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
            defer hbox.deinit();
            var selected = local.selection_mode == .multi_select;
            if (dvui.checkbox(@src(), &selected, "Multi-Select", .{ .margin = dvui.Rect.all(6) })) {
                local.selection_mode = if (selected) .multi_select else .single_select;
                if (local.selection_mode == .single_select) {
                    local.selectAll(.select_none);
                }
            }
            _ = dvui.checkbox(@src(), &local.row_select, "Row Select", .{ .margin = dvui.Rect.all(6) });
        }
    }
    {
        // This is sort of subtle. We need to reset the kb select before the grid is created, so that grid focus is included in select all
        local.kb_select.reset();

        var grid = dvui.grid(@src(), .numCols(6), .{ .scroll_opts = .{ .horizontal_bar = .auto } }, .{ .expand = .both, .background = true });
        defer grid.deinit();
        if (!local.initialized) {
            dvui.focusWidget(grid.data().id, null, null);
            local.initialized = true;
        }

        // Find out if any row was clicked on.
        const row_clicked: ?usize = blk: {
            if (!local.row_select) break :blk null;
            for (dvui.events()) |*e| {
                if (!dvui.eventMatchSimple(e, grid.data())) continue;
                if (e.evt != .mouse) continue;
                const me = e.evt.mouse;
                if (me.action != .press) continue;
                if (grid.pointToCell(me.p)) |cell| {
                    if (cell.col_num > 0) break :blk cell.row_num;
                }
            }
            break :blk null;
        };

        local.selection_info.reset();

        // Note: The extra check here is because I've chosen to unselect anything that was filtered.
        // If we were just doing selection it just needs multi_select.selectionChanged();
        // OR user might prefer to check if everything in the current filter is selected and
        // set the select_all state based on that. So this gives quite a bit more flexibility
        // than previous.
        if (local.filtering_changed or local.multi_select.selectionChanged()) {
            local.select_all_state = .select_none;
        }
        if (local.selection_mode == .multi_select) {
            if (dvui.gridHeadingCheckbox(@src(), grid, 0, &local.select_all_state, .{})) {
                local.selectAll(local.select_all_state);
            }
        }
        dvui.gridHeading(@src(), grid, 1, "Name", .fixed, .{});
        dvui.gridHeading(@src(), grid, 2, "Kind", .fixed, .{});
        dvui.gridHeading(@src(), grid, 3, "Size", .fixed, .{});
        dvui.gridHeading(@src(), grid, 4, "Mode", .fixed, .{});
        dvui.gridHeading(@src(), grid, 5, "MTime", .fixed, .{});

        if (local.row_select)
            local.highlight_style.processEvents(grid);

        {
            var itr: DirEntry.Iterator = .init(&directory_examples);
            var dir_num: usize = 0;
            var row_num: usize = 0;
            local.filtering = false;
            while (itr.next()) |entry| : (dir_num += 1) {
                if (local.isFiltered(entry)) {
                    local.filtering = true;
                    local.selections.unset(dir_num);
                    continue;
                }
                defer row_num += 1;
                var cell_num: dvui.GridWidget.Cell = .colRow(0, row_num);
                {
                    defer cell_num.col_num += 1;
                    var cell = grid.bodyCell(@src(), cell_num, local.highlight_style.cellOptions(cell_num));
                    defer cell.deinit();
                    var is_set = if (dir_num < local.selections.capacity()) local.selections.isSet(dir_num) else false;
                    _ = dvui.checkboxEx(@src(), &is_set, null, .{ .selection_id = dir_num, .selection_info = &local.selection_info }, .{ .gravity_x = 0.5 });
                    // If this is the row that the user clicked on, add a selection event for it.
                    if (row_num == row_clicked) {
                        local.selection_info.add(dir_num, !is_set, cell.data());
                    }
                }
                {
                    defer cell_num.col_num += 1;
                    var cell = grid.bodyCell(
                        @src(),
                        cell_num,
                        local.highlight_style.cellOptions(cell_num),
                    );
                    defer cell.deinit();
                    dvui.labelNoFmt(@src(), entry.name, .{}, .{});
                }
                {
                    defer cell_num.col_num += 1;
                    var cell = grid.bodyCell(@src(), cell_num, local.highlight_style.cellOptions(cell_num));
                    defer cell.deinit();
                    dvui.labelNoFmt(@src(), @tagName(entry.kind), .{}, .{});
                }
                if (entry.kind == .file) {
                    {
                        defer cell_num.col_num += 1;
                        var cell = grid.bodyCell(@src(), cell_num, local.highlight_style.cellOptions(cell_num));
                        defer cell.deinit();
                        dvui.label(@src(), "{d}", .{entry.size}, .{ .gravity_x = 1.0 });
                    }
                    {
                        defer cell_num.col_num += 1;
                        var cell = grid.bodyCell(@src(), cell_num, local.highlight_style.cellOptions(cell_num));
                        defer cell.deinit();
                        dvui.label(@src(), "{o}", .{entry.mode}, .{});
                    }
                    {
                        defer cell_num.col_num += 1;
                        var cell = grid.bodyCell(@src(), cell_num, local.highlight_style.cellOptions(cell_num));
                        defer cell.deinit();
                        dvui.label(@src(), "{[year]:0>4}-{[month]:0>2}-{[day]:0>2} {[hour]:0>2}:{[minute]:0>2}:{[second]:0>2}", local.fromNsTimestamp(entry.mtime), .{});
                    }
                } else {
                    const end_col = cell_num.col_num + 3;
                    while (cell_num.col_num != end_col) : (cell_num.col_num += 1) {
                        var cell = grid.bodyCell(@src(), cell_num, local.highlight_style.cellOptions(cell_num));
                        defer cell.deinit();
                    }
                }
            }
        }

        if (local.selection_mode == .multi_select) {
            local.kb_select.processEvents(&local.select_all_state, grid.data());
            if (local.kb_select.selectionChanged()) {
                local.selectAll(local.select_all_state);
            }

            local.multi_select.processEvents(&local.selection_info, grid.data());
            if (local.multi_select.selectionChanged()) {
                for (local.multi_select.selectionIdStart()..local.multi_select.selectionIdEnd() + 1) |row_num| {
                    local.selections.setValue(row_num, local.multi_select.should_select);
                }
            }
        } else {
            local.single_select.processEvents(&local.selection_info, grid.data());
            if (local.single_select.selectionChanged()) {
                if (local.single_select.id_to_unselect) |unselect_row| {
                    local.selections.unset(unselect_row);
                }
                if (local.single_select.id_to_select) |select_row| {
                    local.selections.set(select_row);
                }
            }
        }
    }
}

/// This example demonstrates an advanced usage of the keyboard navigation. The navigation maintains a virtual 8 column cursor
/// over the 5 columns grid. That is because the first 3 columns have 2 widgets that can get keyboard focus.
/// The 2 widgets in the first 3 columns are actually laid out vertically, even though the tab focus treats them as columns.
/// This allows the user to arrow-down and just jump through the text boxes in the column, or just jump through the sliders,
/// while still getting correct focus when tabbing through the widgets.
pub fn gridNavigation() void {
    const CellStyle = dvui.GridWidget.CellStyle;
    const local = struct {
        var keyboard_nav: dvui.GridWidget.KeyboardNavigation = .{ .num_cols = 8, .num_rows = 0, .wrap_cursor = true, .tab_out = true, .num_scroll = 5 };
        var initialized = false;
        var col_widths: [5]f32 = .{ 100, 100, 100, 35, 35 };
        var plot_title: []const u8 = "X vs Y";
        var x_axis_title: []const u8 = "X";
        var y_axis_title: []const u8 = "Y";
        var plot_buffer: [@sizeOf(Datum) * 100]u8 = undefined;
        var fba: std.heap.FixedBufferAllocator = .init(&plot_buffer);

        const CellStyleNav = struct {
            base: CellStyle,
            focus_cell: ?dvui.GridWidget.Cell,
            tab_index: ?u16 = null,

            // Internal
            widget_data_focused: ?*dvui.WidgetData = null,
            // Access via widget_data_focused preferred.
            wd_store: dvui.WidgetData = undefined,

            pub fn cellOptions(self: *const CellStyleNav, cell: dvui.GridWidget.Cell) dvui.GridWidget.CellOptions {
                return self.base.cellOptions(cell);
            }

            pub fn options(self: *CellStyleNav, cell: dvui.GridWidget.Cell) dvui.Options {
                if (self.focus_cell) |focus_cell| {
                    if (focus_cell.eq(cell)) {
                        self.widget_data_focused = &self.wd_store;
                        return self.base.options(cell).override(.{ .data_out = &self.wd_store, .tab_index = self.tab_index });
                    }
                }
                return self.base.options(cell).override(.{ .tab_index = 0 });
            }

            pub fn setFocus(self: *const CellStyleNav) void {
                if (self.widget_data_focused) |wd| {
                    dvui.focusWidget(wd.id, null, null);
                }
            }
        };

        /// The job of this function is to turn a screen position into a cell.
        /// If there were just 1 widget per cell, grid.pointToCell(p) could do this, but
        /// in this example there are two widgets in the cell. We simplify the logic slightly by
        /// always focusing the first widget (the text box) when the cell is clicked.
        /// The example is set up with a grid of 8 virtual columns, covering the 5 physical columns.
        /// So all it needs to do is map the clicked in grid column to the correct virtual focus column .
        pub fn pointToCellConverter(g: *dvui.GridWidget, p: dvui.Point.Physical) ?dvui.GridWidget.Cell {
            var result = g.pointToCell(p);
            if (result) |*r| {
                // This will always focus the text box on mouse click in the cell,
                // but still allow kb nav of the sliders.
                r.col_num = switch (r.col_num) {
                    0 => 0, // Col 0 contains 2 focus widgets
                    1 => 2, // Col 1 contains 2 focus widgets
                    2 => 4, // Col 2 contains 2 focus widgets
                    3 => 6, // Col 3 and 4 only have 1 widget.
                    4 => 7,
                    else => unreachable,
                };
            }
            return result;
        }

        pub fn maxVal(slice: []f64) f64 {
            var max: f64 = -std.math.floatMin(f64);
            for (slice) |v| {
                if (v > max) max = v;
            }
            return max;
        }

        pub fn minVal(slice: []f64) f64 {
            var min: f64 = std.math.floatMax(f64);
            for (slice) |v| {
                if (v < min) min = v;
            }
            return min;
        }

        const Datum = struct { x: f64, y1: f64, y2: f64 };

        var data: std.MultiArrayList(Datum) = .empty;

        fn initData() !void {
            plot_title = "X vs Y";
            x_axis_title = "X";
            y_axis_title = "Y";
            if (data.len == 0) {
                const alloc = fba.allocator();
                try data.append(alloc, .{ .x = 0, .y1 = -50, .y2 = 50 });
                try data.append(alloc, .{ .x = 25, .y1 = -25, .y2 = 25 });
                try data.append(alloc, .{ .x = 50, .y1 = 0, .y2 = 0 });
                try data.append(alloc, .{ .x = 75, .y1 = 25, .y2 = -25 });
                try data.append(alloc, .{ .x = 100, .y1 = 50, .y2 = -50 });
            }
        }
    };

    var main_box = dvui.box(@src(), .horizontal, .{ .expand = .both, .color_fill = .fill_window, .background = true, .border = dvui.Rect.all(1) });
    defer main_box.deinit();
    if (dvui.firstFrame(main_box.data().id)) {
        local.initialized = false;
        local.initData() catch |err| {
            dvui.logError(@src(), err, "Error initializing plot data", .{});
            return;
        };
    }
    {
        var vbox = dvui.box(@src(), .vertical, .{ .expand = .vertical, .border = dvui.Rect.all(1) });
        defer vbox.deinit();
        {
            var bottom_panel = dvui.box(@src(), .vertical, .{ .gravity_y = 1.0 });
            defer bottom_panel.deinit();
            {
                var hbox = dvui.box(@src(), .horizontal, .{});
                defer hbox.deinit();
                {
                    dvui.labelNoFmt(@src(), "X Axis:", .{}, .{ .margin = dvui.TextEntryWidget.defaults.margin });
                    var text = dvui.textEntry(@src(), .{}, .{
                        .tab_index = 3,
                        .max_size_content = .width(100),
                    });
                    defer text.deinit();
                    if (dvui.firstFrame(text.data().id)) {
                        text.textSet(local.x_axis_title, false);
                    }
                    local.x_axis_title = text.getText();
                }
                {
                    dvui.labelNoFmt(@src(), "Y Axis:", .{}, .{ .margin = dvui.TextEntryWidget.defaults.margin });
                    var text = dvui.textEntry(@src(), .{}, .{ .tab_index = 4, .max_size_content = .width(100) });
                    defer text.deinit();
                    if (dvui.firstFrame(text.data().id)) {
                        text.textSet(local.y_axis_title, false);
                    }
                    local.y_axis_title = text.getText();
                }
            }
            {
                {
                    var tl = dvui.textLayout(@src(), .{ .break_lines = true }, .{ .background = false });
                    defer tl.deinit();
                    tl.addText(
                        \\ This example demonstrates keyboard focus and 
                        \\        navigation. Use tab, shift-tab, up, down, 
                        \\ctrl/cmd-home, ctrl/cmd-end and pg up, pg down 
                        \\                   to navigate between cells.
                    , .{ .background = false, .gravity_x = 0.5 });
                }
            }
        }
        {
            var top_panel = dvui.box(@src(), .horizontal, .{ .gravity_y = 0 });
            defer top_panel.deinit();
            dvui.labelNoFmt(@src(), "Plot Title:", .{}, .{ .margin = dvui.TextEntryWidget.defaults.margin });
            var text = dvui.textEntry(@src(), .{}, .{ .tab_index = 1, .expand = .horizontal });
            defer text.deinit();

            if (dvui.firstFrame(text.data().id)) {
                text.textSet(local.plot_title, false);
            }
            local.plot_title = text.getText();
        }
        {
            var grid = dvui.grid(@src(), .{ .col_widths = &local.col_widths }, .{}, .{ .expand = .vertical, .border = dvui.Rect.all(1) });
            defer grid.deinit();

            local.keyboard_nav.num_scroll = dvui.GridWidget.KeyboardNavigation.numScrollDefault(grid);
            local.keyboard_nav.setLimits(8, local.data.len);
            local.keyboard_nav.processEventsCustom(grid, local.pointToCellConverter);
            const focused_cell = local.keyboard_nav.cellCursor();

            const style_base = CellStyle{ .opts = .{
                .tab_index = null,
                .expand = .horizontal,
            } };

            var style: local.CellStyleNav = .{ .base = style_base, .focus_cell = focused_cell, .tab_index = 2 };

            dvui.gridHeading(@src(), grid, 0, "X", .fixed, .{});
            dvui.gridHeading(@src(), grid, 1, "Y1", .fixed, .{});
            dvui.gridHeading(@src(), grid, 2, "Y2", .fixed, .{});
            var row_to_delete: ?usize = null;
            var row_to_add: ?usize = null;

            for (local.data.items(.x), local.data.items(.y1), local.data.items(.y2), 0..) |*x, *y1, *y2, row_num| {
                var cell_num: dvui.GridWidget.Cell = .colRow(0, row_num);
                var focus_cell: dvui.GridWidget.Cell = .colRow(0, row_num);
                // X Column
                {
                    defer cell_num.col_num += 1;
                    var cell = grid.bodyCell(@src(), cell_num, style.cellOptions(cell_num));
                    defer cell.deinit();
                    var cell_vbox = dvui.box(@src(), .vertical, .{ .expand = .both });
                    defer cell_vbox.deinit();

                    _ = dvui.textEntryNumber(@src(), f64, .{ .value = x, .min = 0, .max = 100, .show_min_max = true }, style.options(focus_cell).override(.{ .gravity_y = 0 }));
                    focus_cell.col_num += 1;

                    var fraction: f32 = @floatCast(x.*);
                    fraction /= 100;
                    if (dvui.slider(@src(), .horizontal, &fraction, style.options(focus_cell).override(.{ .gravity_y = 1 }))) {
                        x.* = fraction * 10000;
                        x.* = @round(x.*) / 100;
                    }
                    focus_cell.col_num += 1;
                }
                // Y1 Columnn
                {
                    defer cell_num.col_num += 1;
                    var cell = grid.bodyCell(@src(), cell_num, style.cellOptions(cell_num));
                    defer cell.deinit();
                    var cell_vbox = dvui.box(@src(), .vertical, .{ .expand = .both });
                    defer cell_vbox.deinit();

                    _ = dvui.textEntryNumber(@src(), f64, .{ .value = y1, .min = -100, .max = 100, .show_min_max = true }, style.options(focus_cell).override(.{ .color_text = .red }));
                    focus_cell.col_num += 1;

                    var fraction: f32 = @floatCast(y1.*);
                    fraction += 100;
                    fraction /= 200;
                    if (dvui.slider(@src(), .horizontal, &fraction, style.options(focus_cell).override(.{ .max_size_content = .width(50), .gravity_y = 1, .color_accent = .red }))) {
                        y1.* = fraction * 20000;
                        y1.* = @round((y1.* - 10000)) / 100;
                    }
                    focus_cell.col_num += 1;
                }
                // Y2 Column
                {
                    defer cell_num.col_num += 1;
                    var cell = grid.bodyCell(@src(), cell_num, style.cellOptions(cell_num));
                    defer cell.deinit();
                    var cell_vbox = dvui.box(@src(), .vertical, .{ .expand = .both });
                    defer cell_vbox.deinit();

                    _ = dvui.textEntryNumber(@src(), f64, .{ .value = y2, .min = -100, .max = 100, .show_min_max = true }, style.options(focus_cell).override(.{ .color_text = .blue }));
                    focus_cell.col_num += 1;

                    var fraction: f32 = @floatCast(y2.*);
                    fraction += 100;
                    fraction /= 200;
                    if (dvui.slider(@src(), .horizontal, &fraction, style.options(focus_cell).override(.{ .max_size_content = .width(50), .gravity_y = 1, .color_accent = .blue }))) {
                        y2.* = fraction * 20000;
                        y2.* = @round((y2.* - 10000)) / 100;
                    }
                    focus_cell.col_num += 1;
                }
                {
                    defer cell_num.col_num += 1;
                    defer focus_cell.col_num += 1;
                    var cell = grid.bodyCell(@src(), cell_num, style.cellOptions(cell_num));
                    defer cell.deinit();
                    if (dvui.buttonIcon(@src(), "Insert", dvui.entypo.add_to_list, .{}, .{}, style.options(focus_cell).override(.{ .expand = .horizontal }))) {
                        row_to_add = cell_num.row_num + 1;
                    }
                }
                {
                    defer cell_num.col_num += 1;
                    defer focus_cell.col_num += 1;
                    var cell = grid.bodyCell(@src(), cell_num, style.cellOptions(cell_num));
                    defer cell.deinit();
                    if (dvui.buttonIcon(@src(), "Delete", dvui.entypo.cross, .{}, .{}, style.options(focus_cell).override(.{ .expand = .horizontal }))) {
                        row_to_delete = cell_num.row_num;
                    }
                }
            }
            if (!local.initialized) {
                local.keyboard_nav.navigation_keys = .defaults();
                local.keyboard_nav.scrollTo(0, 0);
                local.keyboard_nav.is_focused = true; // We want the grid focused by default.
                local.initialized = true;
            }

            if (local.keyboard_nav.shouldFocus()) {
                style.setFocus();
            }
            local.keyboard_nav.gridEnd();
            if (row_to_add) |row_num| {
                local.data.insert(local.fba.allocator(), row_num, .{ .x = 50, .y1 = 0, .y2 = 0 }) catch {};
            }
            if (row_to_delete) |row_num| {
                if (local.data.len > 1)
                    local.data.orderedRemove(row_num)
                else
                    local.data.set(0, .{ .x = 0, .y1 = 0, .y2 = 0 });
            }
        }
    }
    {
        var vbox = dvui.box(@src(), .vertical, .{ .expand = .both, .border = dvui.Rect.all(1) });
        defer vbox.deinit();
        var x_axis: dvui.PlotWidget.Axis = .{ .name = local.x_axis_title, .min = 0, .max = 100 };
        var y_axis: dvui.PlotWidget.Axis = .{
            .name = local.y_axis_title,
            .min = @min(local.minVal(local.data.items(.y1)), local.minVal(local.data.items(.y2))),
            .max = @max(local.maxVal(local.data.items(.y1)), local.maxVal(local.data.items(.y2))),
        };
        var plot = dvui.plot(
            @src(),
            .{
                .title = local.plot_title,
                .x_axis = &x_axis,
                .y_axis = &y_axis,
                .mouse_hover = true,
            },
            .{
                .padding = .{},
                .expand = .both,
                .background = true,
                .min_size_content = .{ .w = 500 },
            },
        );
        defer plot.deinit();
        const thick = 2;
        {
            var s1 = plot.line();
            defer s1.deinit();
            for (local.data.items(.x), local.data.items(.y1)) |x, y| {
                s1.point(x, y);
            }
            s1.stroke(thick, .red);
        }
        {
            var s2 = plot.line();
            defer s2.deinit();
            for (local.data.items(.x), local.data.items(.y2)) |x, y| {
                s2.point(x, y);
            }
            s2.stroke(thick, .blue);
        }
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

//test "DOCIMG themeEditor" {
//    var t = try dvui.testing.init(.{ .window_size = .{ .w = 400, .h = 500 } });
//    defer t.deinit();
//
//    const frame = struct {
//        fn frame() !dvui.App.Result {
//            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
//            defer box.deinit();
//            themeEditor();
//            return .ok;
//        }
//    }.frame;
//
//    // tab to a color editor expander and open it
//    try dvui.testing.pressKey(.tab, .none);
//    _ = try dvui.testing.step(frame);
//    try dvui.testing.pressKey(.tab, .none);
//    _ = try dvui.testing.step(frame);
//    try dvui.testing.pressKey(.tab, .none);
//    _ = try dvui.testing.step(frame);
//    try dvui.testing.pressKey(.tab, .none);
//    _ = try dvui.testing.step(frame);
//    try dvui.testing.pressKey(.tab, .none);
//    _ = try dvui.testing.step(frame);
//    try dvui.testing.pressKey(.enter, .none);
//
//    try dvui.testing.settle(frame);
//    try t.saveImage(frame, null, "Examples-themeEditor.png");
//}

// Sample data for directory grid
const directory_examples = [_]DirEntry{
    .{ .name = "archive.zip", .kind = .file, .size = 5_242_880, .mode = 0o644, .mtime = 1_625_077_800_000_000_000 },
    .{ .name = "assets", .kind = .directory, .size = 0, .mode = 0o755, .mtime = 1_625_077_850_000_000_000 },
    .{ .name = "backup.tar", .kind = .file, .size = 15_728_640, .mode = 0o644, .mtime = 1_625_078_000_000_000_000 },
    .{ .name = "binfile.bin", .kind = .file, .size = 8_192, .mode = 0o644, .mtime = 1_625_078_200_000_000_000 },
    .{ .name = "build", .kind = .directory, .size = 0, .mode = 0o755, .mtime = 1_625_078_250_000_000_000 },
    .{ .name = "code.zig", .kind = .file, .size = 5_120, .mode = 0o644, .mtime = 1_625_078_400_000_000_000 },
    .{ .name = "config", .kind = .directory, .size = 0, .mode = 0o755, .mtime = 1_625_078_450_000_000_000 },
    .{ .name = "config.json", .kind = .file, .size = 2_048, .mode = 0o644, .mtime = 1_625_078_600_000_000_000 },
    .{ .name = "data", .kind = .directory, .size = 0, .mode = 0o755, .mtime = 1_625_078_700_000_000_000 },
    .{ .name = "data.csv", .kind = .file, .size = 3_072, .mode = 0o644, .mtime = 1_625_078_800_000_000_000 },
    .{ .name = "database.db", .kind = .file, .size = 10_485_760, .mode = 0o644, .mtime = 1_625_079_000_000_000_000 },
    .{ .name = "docs", .kind = .directory, .size = 0, .mode = 0o755, .mtime = 1_625_079_100_000_000_000 },
    .{ .name = "draft.docx", .kind = .file, .size = 40_960, .mode = 0o644, .mtime = 1_625_081_000_000_000_000 },
    .{ .name = "draft2.docx", .kind = .file, .size = 81_920, .mode = 0o644, .mtime = 1_625_081_200_000_000_000 },
    .{ .name = "dump.sql", .kind = .file, .size = 512_000, .mode = 0o644, .mtime = 1_625_081_400_000_000_000 },
    .{ .name = "example.zig", .kind = .file, .size = 2_048, .mode = 0o644, .mtime = 1_625_081_600_000_000_000 },
    .{ .name = "favicon.ico", .kind = .file, .size = 1_024, .mode = 0o644, .mtime = 1_625_081_800_000_000_000 },
    .{ .name = "file1.txt", .kind = .file, .size = 1_234, .mode = 0o644, .mtime = 1_625_082_000_000_000_000 },
    .{ .name = "file2.txt", .kind = .file, .size = 5_678, .mode = 0o644, .mtime = 1_625_082_200_000_000_000 },
    .{ .name = "file3.log", .kind = .file, .size = 4_321, .mode = 0o644, .mtime = 1_625_082_400_000_000_000 },
    .{ .name = "images", .kind = .directory, .size = 0, .mode = 0o755, .mtime = 1_625_082_500_000_000_000 },
    .{ .name = "header.h", .kind = .file, .size = 1_024, .mode = 0o644, .mtime = 1_625_082_600_000_000_000 },
    .{ .name = "image.png", .kind = .file, .size = 204_800, .mode = 0o644, .mtime = 1_625_082_800_000_000_000 },
    .{ .name = "index.html", .kind = .file, .size = 4_096, .mode = 0o644, .mtime = 1_625_083_000_000_000_000 },
    .{ .name = "lib", .kind = .directory, .size = 0, .mode = 0o755, .mtime = 1_625_083_100_000_000_000 },
    .{ .name = "logfile.log", .kind = .file, .size = 8_192, .mode = 0o644, .mtime = 1_625_083_200_000_000_000 },
    .{ .name = "Makefile", .kind = .file, .size = 512, .mode = 0o644, .mtime = 1_625_083_400_000_000_000 },
    .{ .name = "media", .kind = .directory, .size = 0, .mode = 0o755, .mtime = 1_625_083_500_000_000_000 },
    .{ .name = "music.mp3", .kind = .file, .size = 5_120_000, .mode = 0o644, .mtime = 1_625_083_600_000_000_000 },
    .{ .name = "notes.md", .kind = .file, .size = 2_048, .mode = 0o644, .mtime = 1_625_083_800_000_000_000 },
    .{ .name = "notes.txt", .kind = .file, .size = 1_024, .mode = 0o644, .mtime = 1_625_084_000_000_000_000 },
    .{ .name = "old_backup.tar.gz", .kind = .file, .size = 10_485_760, .mode = 0o644, .mtime = 1_625_084_200_000_000_000 },
    .{ .name = "photo.jpg", .kind = .file, .size = 307_200, .mode = 0o644, .mtime = 1_625_084_400_000_000_000 },
    .{ .name = "photos", .kind = .directory, .size = 0, .mode = 0o755, .mtime = 1_625_084_500_000_000_000 },
    .{ .name = "plan.docx", .kind = .file, .size = 20_480, .mode = 0o644, .mtime = 1_625_084_600_000_000_000 },
    .{ .name = "presentation.pptx", .kind = .file, .size = 2_097_152, .mode = 0o644, .mtime = 1_625_084_800_000_000_000 },
    .{ .name = "readme.txt", .kind = .file, .size = 1_024, .mode = 0o644, .mtime = 1_625_085_000_000_000_000 },
    .{ .name = "report.pdf", .kind = .file, .size = 524_288, .mode = 0o644, .mtime = 1_625_085_200_000_000_000 },
    .{ .name = "resources", .kind = .directory, .size = 0, .mode = 0o755, .mtime = 1_625_085_300_000_000_000 },
    .{ .name = "script.js", .kind = .file, .size = 4_096, .mode = 0o644, .mtime = 1_625_085_400_000_000_000 },
    .{ .name = "script.sh", .kind = .file, .size = 4_096, .mode = 0o755, .mtime = 1_625_085_600_000_000_000 },
    .{ .name = "settings.yaml", .kind = .file, .size = 3_072, .mode = 0o644, .mtime = 1_625_085_800_000_000_000 },
    .{ .name = "source.c", .kind = .file, .size = 5_120, .mode = 0o644, .mtime = 1_625_086_000_000_000_000 },
    .{ .name = "spreadsheet.xlsx", .kind = .file, .size = 1_048_576, .mode = 0o644, .mtime = 1_625_086_200_000_000_000 },
    .{ .name = "style.css", .kind = .file, .size = 2_048, .mode = 0o644, .mtime = 1_625_086_400_000_000_000 },
    .{ .name = "test.zig", .kind = .file, .size = 1_024, .mode = 0o644, .mtime = 1_625_086_600_000_000_000 },
    .{ .name = "thumbnail.jpg", .kind = .file, .size = 102_400, .mode = 0o644, .mtime = 1_625_086_800_000_000_000 },
    .{ .name = "todo.txt", .kind = .file, .size = 512, .mode = 0o644, .mtime = 1_625_087_000_000_000_000 },
    .{ .name = "video.mp4", .kind = .file, .size = 10_485_760, .mode = 0o644, .mtime = 1_625_087_200_000_000_000 },
};
