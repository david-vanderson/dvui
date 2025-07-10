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
const structUI = @import("Examples/struct_ui.zig").structUI;
const debuggingErrors = @import("Examples/debugging.zig").debuggingErrors;
const grid_examples = @import("Examples/grid.zig");
const gridStyling = grid_examples.gridStyling;
const gridLayouts = grid_examples.gridLayouts;
const gridVirtualScrolling = grid_examples.gridVirtualScrolling;
const gridVariableRowHeights = grid_examples.gridVariableRowHeights;
const gridSelection = grid_examples.gridSelection;
const gridNavigation = grid_examples.gridNavigation;
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

var stroke_test_closed: bool = false;

pub const StrokeTest = struct {
    pub const Self = @This();
    pub var show: bool = false;
    pub var show_rect = dvui.Rect{};
    pub var pointsArray: [10]dvui.Point = [1]dvui.Point{.{}} ** 10;
    pub var points: []dvui.Point = pointsArray[0..0];
    pub var dragi: ?usize = null;
    pub var thickness: f32 = 1.0;
    pub var endcap_style: dvui.Path.StrokeOptions.EndCapStyle = .none;

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
