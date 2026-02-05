//! ![demo](Examples-demo.png)

pub const zig_favicon = @embedFile("zig-favicon.png");
pub const zig_svg = @embedFile("zig-mark.svg");

pub var show_demo_window: bool = false;
pub var icon_browser_show: bool = false;
var source_code_show: bool = false;
var source_code_rect: dvui.Rect = undefined;
var frame_counter: u64 = 0;
pub var show_dialog: bool = false;
var scale_val: f32 = 1.0;

pub const demoKind = enum {
    basic_widgets,
    calculator,
    text_entry,
    styling,
    theming,
    layout,
    text_layout,
    plots,
    reorder_tree,
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
            .theming => "Theming",
            .layout => "Layout",
            .text_layout => "Text Layout",
            .plots => "Plots",
            .reorder_tree => "Reorder / Tree",
            .menus => "Menus / Focus",
            .scrolling => "Scrolling",
            .scroll_canvas => "Scroll Canvas",
            .dialogs => "Dialogs / Toasts",
            .animations => "Animations",
            .struct_ui => "Struct UI",
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
            .theming => .{ .scale = 0.35, .offset = .{} },
            .layout => .{ .scale = 0.45, .offset = .{ .x = -50 } },
            .text_layout => .{ .scale = 0.45, .offset = .{} },
            .plots => .{ .scale = 0.45, .offset = .{} },
            .reorder_tree => .{ .scale = 0.45, .offset = .{} },
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

pub fn floatRetainClear(ptr: *anyopaque) void {
    const id: dvui.Id = @as(*dvui.Id, @ptrCast(@alignCast(ptr))).*;
    dvui.retainClear(id);
}

pub fn demo() void {
    if (!show_demo_window) {
        return;
    }

    const width = 600;

    var float = dvui.floatingWindow(@src(), .{ .open_flag = &show_demo_window }, .{ .min_size_content = .{ .w = width, .h = 400 }, .max_size_content = .width(width), .tag = demo_window_tag });
    defer float.deinit();

    _ = dvui.dataGet(null, float.data().id, "retain", dvui.Id) orelse {
        dvui.dataSet(null, float.data().id, "retain", float.data().id);
        dvui.dataSetDeinitFunction(null, float.data().id, "retain", &floatRetainClear);
    };

    // pad the fps label so that it doesn't trigger refresh when the number
    // changes widths
    var buf: [100]u8 = undefined;
    const fps_str = std.fmt.bufPrint(&buf, "{d:0>3.0} fps | frame no {d}", .{ dvui.FPS(), frame_counter }) catch unreachable;
    frame_counter += 1;
    float.dragAreaSet(dvui.windowHeader("DVUI Demo", fps_str, &show_demo_window));

    dvui.toastsShow(float.data().id, .cast(float.data().rect));

    var scaler = dvui.scale(@src(), .{ .scale = &scale_val }, .{ .expand = .both });
    defer scaler.deinit();

    var paned = dvui.paned(@src(), .{ .direction = .horizontal, .collapsed_size = width + 1 }, .{ .expand = .both, .background = false, .min_size_content = .{ .h = 100 } });
    //if (dvui.firstFrame(paned.data().id)) {
    //    paned.split_ratio = 0;
    //}
    if (paned.showFirst()) {
        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .style = .content });
        defer scroll.deinit();

        var invalidate: bool = false;
        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer hbox.deinit();
            if (dvui.button(@src(), "Debug Window", .{}, .{})) {
                dvui.toggleDebugWindow();
            }

            if (dvui.Theme.picker(@src(), &dvui.Theme.builtins, .{})) {
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

        var fbox = dvui.flexbox(@src(), .{}, .{ .expand = .both, .min_size_content = .width(width), .corner_radius = .{ .w = 5, .h = 5 } });
        defer fbox.deinit();

        inline for (0..@typeInfo(demoKind).@"enum".fields.len) |i| {
            const e = @as(demoKind, @enumFromInt(i));
            var bw: dvui.ButtonWidget = undefined;
            bw.init(@src(), .{}, .{
                .id_extra = i,
                .border = Rect.all(1),
                .background = true,
                .min_size_content = dvui.Size.all(120),
                .max_size_content = .size(dvui.Size.all(120)),
                .margin = Rect.all(5),
                .style = .content,
                .tag = "demo_button_" ++ @tagName(e),
                .label = .{ .text = e.name() },
            });
            bw.processEvents();
            bw.drawBackground();

            const use_cache = true;
            var cache: *dvui.CacheWidget = undefined;
            if (use_cache) {
                cache = dvui.cache(@src(), .{ .invalidate = invalidate, .retain = float.data().id }, .{ .expand = .both });
            }
            if (!use_cache or cache.uncached()) {
                const box = dvui.box(@src(), .{}, .{ .expand = .both });
                defer box.deinit();

                var options: dvui.Options = .{ .gravity_x = 0.5, .gravity_y = 1.0 };
                if (dvui.captured(bw.data().id)) options = options.override(.{ .color_text = options.color(.text_press) });

                dvui.label(@src(), "{s}", .{e.name()}, options);

                var s = e.scaleOffset().scale;
                const demo_scaler = dvui.scale(@src(), .{ .scale = &s }, .{ .expand = .both });
                defer demo_scaler.deinit();

                const oldclip = dvui.clip(demo_scaler.data().contentRectScale().r);
                defer dvui.clipSet(oldclip);

                const box2 = dvui.box(@src(), .{}, .{ .rect = dvui.Rect.fromPoint(e.scaleOffset().offset).toSize(.{ .w = 400, .h = 1000 }) });
                defer box2.deinit();

                switch (e) {
                    .basic_widgets => basicWidgets(),
                    .calculator => calculator(),
                    .text_entry => textEntryWidgets(float.data().id),
                    .styling => styling(),
                    .theming => theming(),
                    .layout => layout(),
                    .text_layout => layoutText(),
                    .plots => plots(),
                    .reorder_tree => reorderLists(),
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
        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
            defer hbox.deinit();

            if (paned.collapsed() and dvui.button(@src(), "Back to Demos", .{}, .{ .min_size_content = .{ .h = 30 }, .tag = "dvui_demo_window_back" })) {
                paned.animateSplit(1.0);
            }

            dvui.label(@src(), "{s}", .{demo_active.name()}, .{ .font = dvui.Font.theme(.title), .gravity_y = 0.5 });
            if (dvui.labelClick(@src(), "View source code", .{}, .{}, .{ .gravity_x = 1.0, .gravity_y = 0.5, .color_text = dvui.themeGet().focus })) {
                const window_rect = dvui.currentWindow().data().contentRect();
                source_code_rect = .{ .x = window_rect.x + window_rect.w / 2, .y = window_rect.y, .h = window_rect.h, .w = window_rect.w / 2 };
                source_code_show = true;
            }
        }

        var scroll: ?*dvui.ScrollAreaWidget = null;
        if (demo_active != .grid) {
            scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .background = false });
        }
        defer if (scroll) |s| s.deinit();

        var vbox = dvui.box(@src(), .{}, .{ .padding = dvui.Rect.all(4), .expand = .both });
        defer vbox.deinit();

        switch (demo_active) {
            .basic_widgets => basicWidgets(),
            .calculator => calculator(),
            .text_entry => textEntryWidgets(float.data().id),
            .styling => styling(),
            .theming => theming(),
            .layout => layout(),
            .text_layout => layoutText(),
            .plots => plots(),
            .reorder_tree => reorderLists(),
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

    if (source_code_show) {
        switch (demo_active) {
            inline else => |demo_name| {
                const source_code = if (dvui.useTreeSitter) @embedFile("Examples/" ++ @tagName(demo_name) ++ ".zig") else "";
                displayZigSourceCode(@tagName(demo_name) ++ ".zig", source_code, &source_code_show, &source_code_rect);
            },
        }
    }
}

pub fn dialogDirect() void {
    const uniqueId = dvui.parentGet().extendId(@src(), 0);
    const allow_resize = dvui.dataGetPtrDefault(null, uniqueId, "allow_resize", bool, true);

    var dialog_win = dvui.floatingWindow(@src(), .{ .modal = false, .open_flag = &show_dialog, .resize = if (allow_resize.*) .all else .none }, .{ .max_size_content = .width(500), .background = false, .border = .all(0) });
    defer dialog_win.deinit();

    const extra_stuff: *bool = dvui.dataGetPtrDefault(null, dialog_win.data().id, "extra_stuff", bool, false);
    const render_offscreen: *bool = dvui.dataGetPtrDefault(null, dialog_win.data().id, "render_offscreen", bool, true);
    const alpha: *f32 = dvui.dataGetPtrDefault(null, dialog_win.data().id, "alpha", f32, 1.0);

    var pic: ?dvui.Picture = null;
    if (render_offscreen.*) {
        // Render contents to buffer so the alpha is applied a single time to the
        // whole thing
        pic = dvui.Picture.start(dialog_win.data().rectScale().r);
    } else {
        dvui.alphaSet(alpha.*);
    }

    // background for dialog_win (since it has background false)
    var back = dvui.box(@src(), .{}, .{ .expand = .both, .style = .window, .background = true, .border = .all(1), .corner_radius = .all(5) });
    defer back.deinit();

    dialog_win.dragAreaSet(dvui.windowHeader("Dialog", "", &show_dialog));
    dvui.label(@src(), "Asking a Question", .{}, .{ .font = .theme(.title), .gravity_x = 0.5 });
    dvui.label(@src(), "This dialog is directly called by user code.", .{}, .{ .gravity_x = 0.5 });

    _ = dvui.checkbox(@src(), allow_resize, "Allow Resizing", .{});

    {
        var box = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer box.deinit();
        _ = dvui.checkbox(@src(), render_offscreen, "Render Offscreen", .{});
        _ = dvui.sliderEntry(@src(), "alpha: {d:0.2}", .{ .value = alpha, .min = 0, .max = 1, .interval = 0.01 }, .{});
    }

    {
        var box = dvui.box(@src(), .{}, .{ .min_size_content = .all(100), .background = true, .color_fill = .green });
        defer box.deinit();

        var box2 = dvui.box(@src(), .{}, .{ .min_size_content = .all(80), .background = true, .color_fill = .blue });
        defer box2.deinit();

        var box3 = dvui.box(@src(), .{}, .{ .min_size_content = .all(60), .background = true, .color_fill = .red });
        defer box3.deinit();
    }

    if (dvui.button(@src(), "Toggle extra stuff and fit window", .{}, .{ .tab_index = 1 })) {
        extra_stuff.* = !extra_stuff.*;
        dialog_win.autoSize();
    }

    if (extra_stuff.*) {
        dvui.label(@src(), "This is some extra stuff\nwith a multi-line label\nthat has 3 lines", .{}, .{ .margin = .{ .x = 4 } });

        var tl = dvui.textLayout(@src(), .{}, .{});
        tl.addText("Here is a textLayout with a bunch of text in it that would overflow the right edge but the dialog has a max_size_content", .{});
        tl.deinit();
    }

    {
        _ = dvui.spacer(@src(), .{ .expand = .vertical });
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .gravity_x = 1.0 });
        defer hbox.deinit();

        const gravx: f32, const tindex: u16 = switch (dvui.currentWindow().button_order) {
            .cancel_ok => .{ 1.0, 4 },
            .ok_cancel => .{ 0.0, 2 },
        };

        if (dvui.button(@src(), "Yes", .{}, .{ .gravity_x = gravx, .tab_index = tindex })) {
            dialog_win.close(); // can close the dialog this way
        }

        if (dvui.button(@src(), "No", .{}, .{ .tab_index = 3 })) {
            show_dialog = false; // can close by not running this code anymore
        }
    }

    if (pic) |*p| {
        p.stop();
        dvui.alphaSet(alpha.*);

        // here is where the picture is rendered to the screen
        p.deinit();
    }

    dvui.alphaSet(1.0);
}

pub fn show_stroke_test_window() void {
    var win = dvui.floatingWindow(@src(), .{ .rect = &StrokeTest.show_rect, .open_flag = &StrokeTest.show }, .{});
    defer win.deinit();
    win.dragAreaSet(dvui.windowHeader("Stroke Test", "", &StrokeTest.show));

    dvui.label(@src(), "Stroke Test", .{}, .{});
    _ = dvui.checkbox(@src(), &StrokeTest.stroke_test_closed, "Closed", .{});
    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
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

    var tbox = dvui.box(@src(), .{}, .{ .border = Rect.all(1), .expand = .both });
    defer tbox.deinit();
    {
        var tabs = dvui.tabs(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
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

fn displayZigSourceCode(filename: []const u8, source: []const u8, showing: *bool, rect: *Rect) void {
    if (dvui.useTreeSitter) {
        const fwin = dvui.floatingWindow(@src(), .{ .rect = rect, .open_flag = showing }, .{});
        defer fwin.deinit();
        fwin.dragAreaSet(dvui.windowHeader("View Zig Source", filename, showing));

        const global = struct {
            extern fn tree_sitter_zig() callconv(.c) *dvui.c.TSLanguage;
            var source_code: []const u8 = "";
        };

        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        const queries = @embedFile("Examples/tree_sitter_zig_queries.scm");

        const highlights: []const dvui.TextEntryWidget.SyntaxHighlight = &.{
            .{ .name = "comment", .opts = .{ .color_text = .fromHex("6A9955") } },
            .{ .name = "keyword", .opts = .{ .color_text = .fromHex("569CD6") } },
            .{ .name = "identifier", .opts = .{ .color_text = .fromHex("D4D4D4") } },
            .{ .name = "function", .opts = .{ .color_text = .fromHex("DCDCAA") } },
            .{ .name = "type", .opts = .{ .color_text = .fromHex("4EC9B0") } },
            .{ .name = "builtin", .opts = .{ .color_text = .fromHex("4EC9B0") } },
            .{ .name = "field", .opts = .{ .color_text = .fromHex("9CDCFE") } },
            .{ .name = "variable", .opts = .{ .color_text = .fromHex("9CDCFE") } },
            .{ .name = "constant", .opts = .{ .color_text = .fromHex("C586C0") } },
            .{ .name = "string", .opts = .{ .color_text = .fromHex("CE9178") } },
            .{ .name = "number", .opts = .{ .color_text = .fromHex("B5CEA8") } },
            .{ .name = "operator", .opts = .{ .color_text = .fromHex("D4D4D4") } },
            .{ .name = "error", .opts = .{ .color_text = .fromHex("F44747") } },
        };

        var te: dvui.TextEntryWidget = undefined;
        te.init(@src(), .{
            .multiline = true,
            .cache_layout = true,
            .text = .{ .internal = .{ .limit = 1_000_000 } },
            .tree_sitter = .{
                .language = global.tree_sitter_zig(),
                .queries = queries,
                .highlights = highlights,
                .log_captures = false,
            },
        }, .{
            .expand = .both,
        });
        defer te.deinit();

        if (dvui.firstFrame(te.data().id) or source.ptr != global.source_code.ptr) {
            te.textSet(source, false);
            te.textLayout.selection.moveCursor(0, false); // keep from scrolling to the bottom
            global.source_code = source;
        }

        // Don't process events. Read-only view.
        te.draw();
    } else {
        if (showing.*) {
            var url: std.io.Writer.Allocating = .init(dvui.currentWindow().arena());
            url.writer.print("https://github.com/david-vanderson/dvui/blob/main/src/Examples/{s}", .{filename}) catch return;
            _ = dvui.openURL(.{ .url = url.toOwnedSlice() catch return, .new_window = false });
            showing.* = false;
        }
    }
}

test {
    @import("std").testing.refAllDecls(@This());
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

const std = @import("std");
const dvui = @import("dvui.zig");
const StrokeTest = @import("Examples/StrokeTest.zig");
const Options = dvui.Options;
const Point = dvui.Point;
const Rect = dvui.Rect;
const Size = dvui.Size;
const entypo = dvui.entypo;

const basicWidgets = @import("Examples/basic_widgets.zig").basicWidgets;
const calculator = @import("Examples/calculator.zig").calculator;
const textEntryWidgets = @import("Examples/text_entry.zig").textEntryWidgets;
const styling = @import("Examples/styling.zig").styling;
const theming = @import("Examples/theming.zig").theming;
const layout = @import("Examples/layout.zig").layout;
const layoutText = @import("Examples/text_layout.zig").layoutText;
const plots = @import("Examples/plots.zig").plots;
const reorderLists = @import("Examples/reorder_tree.zig").reorderLists;
const menus = @import("Examples/menus.zig").menus;
const scrolling = @import("Examples/scrolling.zig").scrolling;
const scrollCanvas = @import("Examples/scroll_canvas.zig").scrollCanvas;
const dialogs = @import("Examples/dialogs.zig").dialogs;
const animations = @import("Examples/animations.zig").animations;
const structUI = @import("Examples/struct_ui.zig").structUI;
const debuggingErrors = @import("Examples/debugging.zig").debuggingErrors;
const icon_browser = @import("Examples/icon_browser.zig").iconBrowser;

const grid_examples = @import("Examples/grid.zig");
const gridStyling = grid_examples.gridStyling;
const gridLayouts = grid_examples.gridLayouts;
const gridVirtualScrolling = grid_examples.gridVirtualScrolling;
const gridVariableRowHeights = grid_examples.gridVariableRowHeights;
const gridSelection = grid_examples.gridSelection;
const gridNavigation = grid_examples.gridNavigation;
