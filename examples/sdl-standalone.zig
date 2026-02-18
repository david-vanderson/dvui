const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const SDLBackend = @import("sdl-backend");

comptime {
    std.debug.assert(@hasDecl(SDLBackend, "SDLBackend"));
}

const window_icon_png = @embedFile("zig-favicon.png");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const vsync = true;
const show_demo = false;
var scale_val: f32 = 1.0;

var show_dialog_outside_frame: bool = false;
var g_backend: ?SDLBackend = null;
var g_win: ?*dvui.Window = null;

/// This example shows how to use the dvui for a normal application:
/// - dvui renders the whole application
/// - render frames only when needed
///
pub fn main() !void {
    if (@import("builtin").os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
        dvui.Backend.Common.windowsAttachConsole() catch {};
    }
    SDLBackend.enableSDLLogging();
    std.log.info("SDL version: {f}", .{SDLBackend.getSDLVersion()});

    dvui.Examples.show_demo_window = show_demo;

    defer if (gpa_instance.deinit() != .ok) @panic("Memory leak on exit!");

    // init SDL backend (creates and owns OS window)
    var backend = try SDLBackend.initWindow(.{
        .allocator = gpa,
        .size = .{ .w = 800.0, .h = 600.0 },
        .min_size = .{ .w = 250.0, .h = 350.0 },
        .vsync = vsync,
        .title = "DVUI SDL Standalone Example",
        .icon = window_icon_png, // can also call setIconFromFileContent()
    });
    g_backend = backend;
    defer backend.deinit();

    _ = SDLBackend.c.SDL_EnableScreenSaver();

    // init dvui Window (maps onto a single OS window)
    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{
        // you can set the default theme here in the init options
        .theme = switch (backend.preferredColorScheme() orelse .light) {
            .light => dvui.Theme.builtin.adwaita_light,
            .dark => dvui.Theme.builtin.adwaita_dark,
        },
    });
    defer win.deinit();

    var interrupted = false;

    main_loop: while (true) {
        // beginWait coordinates with waitTime below to run frames only when needed
        const nstime = win.beginWait(interrupted);

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(nstime);

        // send all SDL events to dvui for processing
        try backend.addAllEvents(&win);

        // if dvui widgets might not cover the whole window, then need to clear
        // the previous frame's render
        _ = SDLBackend.c.SDL_SetRenderDrawColor(backend.renderer, 0, 0, 0, 0);
        _ = SDLBackend.c.SDL_RenderClear(backend.renderer);

        const keep_running = gui_frame();
        if (!keep_running) break :main_loop;

        // marks end of dvui frame, don't call dvui functions after this
        // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
        const end_micros = try win.end(.{});

        // cursor management
        try backend.setCursor(win.cursorRequested());
        try backend.textInputRect(win.textInputRequested());

        // render frame to OS
        try backend.renderPresent();

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = win.waitTime(end_micros);
        interrupted = try backend.waitEventTimeout(wait_event_micros);

        // Example of how to show a dialog from another thread (outside of win.begin/win.end)
        if (show_dialog_outside_frame) {
            show_dialog_outside_frame = false;
            dvui.dialog(@src(), .{}, .{ .window = &win, .modal = false, .title = "Dialog from Outside", .message = "This is a non modal dialog that was created outside win.begin()/win.end(), usually from another thread." });
        }
    }
}

// both dvui and SDL drawing
// return false if user wants to exit the app
fn gui_frame() bool {
    dvui.struct_ui.defaults.display_expanded = true;
    //dvui.currentWindow().debug.open = true;
    if (true) {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both, .background = true });
        defer hbox.deinit();
        {
            var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .vertical });
            defer scroll.deinit();
            var tree = dvui.TreeWidget.tree(@src(), .{ .enable_reordering = false }, .{});
            defer tree.deinit();
            for (widget_hierarchy, 0..) |widget, i| {
                const branch = tree.branch(@src(), .{ .expanded = true }, .{ .id_extra = i, .expand = .horizontal });
                defer branch.deinit();
                dvui.label(@src(), "{s}", .{widget.name}, .{ .expand = .horizontal });

                if (widget.children != null) {
                    _ = dvui.icon(
                        @src(),
                        "DropIcon",
                        if (branch.expanded) dvui.entypo.triangle_down else dvui.entypo.triangle_right,
                        .{},
                        .{
                            .gravity_y = 0.5,
                            .gravity_x = 1.0,
                        },
                    );
                } else if (branch.button.clicked()) {
                    currentDisplayFn = widget.displayFn;
                    reset_widget = true;
                }

                if (branch.expander(@src(), .{ .indent = 30 }, .{ .expand = .horizontal })) {
                    if (widget.children) |children| {
                        for (children, 0..) |child, j| {
                            const branch_child = tree.branch(@src(), .{ .expanded = true }, .{ .id_extra = j, .expand = .horizontal });
                            defer branch_child.deinit();
                            dvui.labelNoFmt(@src(), child.name, .{}, .{ .expand = .horizontal });
                            if (branch_child.button.clicked()) {
                                currentDisplayFn = child.displayFn;
                                reset_widget = true;
                            }
                        }
                    }
                }
            }
        }
        {
            var vbox = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .padding = dvui.Rect.all(6) });
            defer vbox.deinit();
            currentDisplayFn();
            reset_widget = false;
        }
    }
    if (false) {
        const backend = g_backend orelse return false;

        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .style = .window, .background = true, .expand = .horizontal, .name = "main" });
            defer hbox.deinit();

            var m = dvui.menu(@src(), .horizontal, .{});
            defer m.deinit();

            if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{})) |r| {
                var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
                defer fw.deinit();

                if (dvui.menuItemLabel(@src(), "Close Menu", .{}, .{ .expand = .horizontal }) != null) {
                    m.close();
                }

                if (dvui.menuItemLabel(@src(), "Exit", .{}, .{ .expand = .horizontal }) != null) {
                    return false;
                }
            }

            if (dvui.menuItemLabel(@src(), "Edit", .{ .submenu = true }, .{})) |r| {
                var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
                defer fw.deinit();
                _ = dvui.menuItemLabel(@src(), "Dummy", .{}, .{ .expand = .horizontal });
                _ = dvui.menuItemLabel(@src(), "Dummy Long", .{}, .{ .expand = .horizontal });
                _ = dvui.menuItemLabel(@src(), "Dummy Super Long", .{}, .{ .expand = .horizontal });
            }
        }

        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
        defer scroll.deinit();

        var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font = .theme(.title) });
        const lorem = "This example shows how to use dvui in a normal application.";
        tl.addText(lorem, .{});
        tl.deinit();

        var tl2 = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
        tl2.addText(
            \\DVUI
            \\- paints the entire window
            \\- can show floating windows and dialogs
            \\- example menu at the top of the window
            \\- rest of the window is a scroll area
            \\
            \\
        , .{});
        tl2.addText("Framerate is variable and adjusts as needed for input events and animations.\n\n", .{});
        if (vsync) {
            tl2.addText("Framerate is capped by vsync.\n", .{});
        } else {
            tl2.addText("Framerate is uncapped.\n", .{});
        }
        tl2.addText("\n", .{});
        tl2.addText("Cursor is always being set by dvui.\n\n", .{});
        if (dvui.useFreeType) {
            tl2.addText("Fonts are being rendered by FreeType 2.", .{});
        } else {
            tl2.addText("Fonts are being rendered by stb_truetype.", .{});
        }
        tl2.deinit();

        const label = if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window";
        if (dvui.button(@src(), label, .{}, .{})) {
            dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
        }

        if (dvui.button(@src(), "Debug Window", .{}, .{})) {
            dvui.toggleDebugWindow();
        }

        {
            var scaler = dvui.scale(@src(), .{ .scale = &scale_val }, .{ .expand = .horizontal });
            defer scaler.deinit();

            {
                var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
                defer hbox.deinit();

                if (dvui.button(@src(), "Zoom In", .{}, .{})) {
                    scale_val = @round(dvui.themeGet().font_body.size * scale_val + 1.0) / dvui.themeGet().font_body.size;
                }

                if (dvui.button(@src(), "Zoom Out", .{}, .{})) {
                    scale_val = @round(dvui.themeGet().font_body.size * scale_val - 1.0) / dvui.themeGet().font_body.size;
                }
            }

            dvui.labelNoFmt(@src(), "Below is drawn directly by the backend, not going through DVUI.", .{}, .{ .margin = .{ .x = 4 } });

            var box = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .min_size_content = .{ .h = 40 }, .background = true, .margin = .{ .x = 8, .w = 8 } });
            defer box.deinit();

            // Here is some arbitrary drawing that doesn't have to go through DVUI.
            // It can be interleaved with DVUI drawing.
            // NOTE: This only works in the main window (not floating subwindows
            // like dialogs).

            // get the screen rectangle for the box
            const rs = box.data().contentRectScale();

            // rs.r is the pixel rectangle, rs.s is the scale factor (like for
            // hidpi screens or display scaling)
            var rect: if (SDLBackend.sdl3) SDLBackend.c.SDL_FRect else SDLBackend.c.SDL_Rect = undefined;
            if (SDLBackend.sdl3) rect = .{
                .x = (rs.r.x + 4 * rs.s),
                .y = (rs.r.y + 4 * rs.s),
                .w = (20 * rs.s),
                .h = (20 * rs.s),
            } else rect = .{
                .x = @intFromFloat(rs.r.x + 4 * rs.s),
                .y = @intFromFloat(rs.r.y + 4 * rs.s),
                .w = @intFromFloat(20 * rs.s),
                .h = @intFromFloat(20 * rs.s),
            };
            _ = SDLBackend.c.SDL_SetRenderDrawColor(backend.renderer, 255, 0, 0, 255);
            _ = SDLBackend.c.SDL_RenderFillRect(backend.renderer, &rect);

            rect.x += if (SDLBackend.sdl3) 24 * rs.s else @intFromFloat(24 * rs.s);
            _ = SDLBackend.c.SDL_SetRenderDrawColor(backend.renderer, 0, 255, 0, 255);
            _ = SDLBackend.c.SDL_RenderFillRect(backend.renderer, &rect);

            rect.x += if (SDLBackend.sdl3) 24 * rs.s else @intFromFloat(24 * rs.s);
            _ = SDLBackend.c.SDL_SetRenderDrawColor(backend.renderer, 0, 0, 255, 255);
            _ = SDLBackend.c.SDL_RenderFillRect(backend.renderer, &rect);

            _ = SDLBackend.c.SDL_SetRenderDrawColor(backend.renderer, 255, 0, 255, 255);

            if (SDLBackend.sdl3)
                _ = SDLBackend.c.SDL_RenderLine(backend.renderer, (rs.r.x + 4 * rs.s), (rs.r.y + 30 * rs.s), (rs.r.x + rs.r.w - 8 * rs.s), (rs.r.y + 30 * rs.s))
            else
                _ = SDLBackend.c.SDL_RenderDrawLine(backend.renderer, @intFromFloat(rs.r.x + 4 * rs.s), @intFromFloat(rs.r.y + 30 * rs.s), @intFromFloat(rs.r.x + rs.r.w - 8 * rs.s), @intFromFloat(rs.r.y + 30 * rs.s));
        }

        if (dvui.button(@src(), "Show Dialog From\nOutside Frame", .{}, .{})) {
            show_dialog_outside_frame = true;
        }

        // look at demo() for examples of dvui widgets, shows in a floating window
        dvui.Examples.demo();
    }
    // check for quitting
    for (dvui.events()) |*e| {
        // assume we only have a single window
        if (e.evt == .window and e.evt.window.action == .close) return false;
        if (e.evt == .app and e.evt.app.action == .quit) return false;
    }

    return true;
}

const WidgetHeirachy = struct {
    name: []const u8,
    children: ?[]const WidgetHeirachy = null,
    displayFn: *const fn () void,
};

var currentDisplayFn: *const fn () void = displayDropDownEnum;

fn displayEmpty() void {
    std.debug.print("DisplayFN called\n", .{});
}

const widget_hierarchy = [_]WidgetHeirachy{
    .{ .name = "animate", .displayFn = displayEmpty, .children = null },
    .{ .name = "box", .displayFn = displayBox, .children = null },

    .{ .name = "button", .displayFn = displayEmpty, .children = &.{
        .{ .name = "button", .displayFn = displayEmpty, .children = null },
        .{ .name = "buttonIcon", .displayFn = displayEmpty, .children = null },
        .{ .name = "buttonLabelAndIcon", .displayFn = displayEmpty, .children = null },
    } },

    .{ .name = "cache", .displayFn = displayEmpty, .children = null },
    .{ .name = "checkbox", .displayFn = displayEmpty, .children = null },
    .{ .name = "colorPicker", .displayFn = displayEmpty, .children = null },
    .{ .name = "comboBox", .displayFn = displayEmpty, .children = null },
    .{ .name = "context", .displayFn = displayEmpty, .children = null },
    .{ .name = "dialog", .displayFn = displayEmpty, .children = null },
    .{ .name = "dropdown", .displayFn = displayEmpty, .children = null },
    .{ .name = "dropdownEnum", .displayFn = displayDropDownEnum, .children = null },
    .{ .name = "expander", .displayFn = displayEmpty, .children = null },
    .{ .name = "flexbox", .displayFn = displayEmpty, .children = null },
    .{ .name = "floatingMenu", .displayFn = displayEmpty, .children = null },

    .{ .name = "floatingWindow", .displayFn = displayEmpty, .children = &.{
        .{ .name = "floatingWindow", .displayFn = displayEmpty, .children = null },
        .{ .name = "windowHeader", .displayFn = displayEmpty, .children = null },
    } },

    .{ .name = "focusGroup", .displayFn = displayEmpty, .children = null },

    .{ .name = "grid", .displayFn = displayEmpty, .children = &.{
        .{ .name = "grid", .displayFn = displayEmpty, .children = null },
        .{ .name = "gridHeading", .displayFn = displayEmpty, .children = null },
        .{ .name = "columnLayoutProportional", .displayFn = displayEmpty, .children = null },
        .{ .name = "gridHeadingCheckbox", .displayFn = displayEmpty, .children = null },
        .{ .name = "gridHeadingSeparator", .displayFn = displayEmpty, .children = null },
        .{ .name = "gridHeadingSortable", .displayFn = displayEmpty, .children = null },
    } },

    .{ .name = "groupBox", .displayFn = displayGroupBox, .children = null },
    .{ .name = "icon", .displayFn = displayEmpty, .children = null },
    .{ .name = "image", .displayFn = displayEmpty, .children = null },

    .{ .name = "label", .displayFn = displayEmpty, .children = &.{
        .{ .name = "label", .displayFn = displayEmpty, .children = null },
        .{ .name = "labelClick", .displayFn = displayEmpty, .children = null },
        .{ .name = "labelEx", .displayFn = displayEmpty, .children = null },
        .{ .name = "labelNoFmt", .displayFn = displayEmpty, .children = null },
    } },

    .{ .name = "link", .displayFn = displayEmpty, .children = null },

    .{ .name = "menu", .displayFn = displayEmpty, .children = &.{
        .{ .name = "menu", .displayFn = displayEmpty, .children = null },
        .{ .name = "menuItem", .displayFn = displayEmpty, .children = null },
        .{ .name = "menuItemIcon", .displayFn = displayEmpty, .children = null },
        .{ .name = "menuItemLabel", .displayFn = displayEmpty, .children = null },
    } },

    .{ .name = "paned", .displayFn = displayEmpty, .children = null },

    .{ .name = "plot", .displayFn = displayEmpty, .children = &.{
        .{ .name = "plot", .displayFn = displayEmpty, .children = null },
        .{ .name = "plotXY", .displayFn = displayEmpty, .children = null },
    } },

    .{ .name = "progress", .displayFn = displayEmpty, .children = null },
    .{ .name = "radio", .displayFn = displayEmpty, .children = null },
    .{ .name = "radioGroup", .displayFn = displayEmpty, .children = null },
    .{ .name = "reorder", .displayFn = displayEmpty, .children = null },
    .{ .name = "scale", .displayFn = displayEmpty, .children = null },
    .{ .name = "scrollArea", .displayFn = displayEmpty, .children = null },
    .{ .name = "separator", .displayFn = displayEmpty, .children = null },

    .{ .name = "slider", .displayFn = displayEmpty, .children = &.{
        .{ .name = "slider", .displayFn = displayEmpty, .children = null },
        .{ .name = "sliderEntry", .displayFn = displayEmpty, .children = null },
        .{ .name = "sliderVector", .displayFn = displayEmpty, .children = null },
    } },

    .{ .name = "spacer", .displayFn = displayEmpty, .children = null },
    .{ .name = "spinner", .displayFn = displayEmpty, .children = null },
    .{ .name = "suggestion", .displayFn = displayEmpty, .children = null },
    .{ .name = "tabs", .displayFn = displayEmpty, .children = null },

    .{ .name = "textEntry", .displayFn = displayEmpty, .children = &.{
        .{ .name = "textEntry", .displayFn = displayEmpty, .children = null },
        .{ .name = "textEntryColor", .displayFn = displayEmpty, .children = null },
        .{ .name = "textEntryNumber", .displayFn = displayTextEntryNumber, .children = null },
    } },

    .{ .name = "textLayout", .displayFn = displayEmpty, .children = null },
    .{ .name = "toast", .displayFn = displayEmpty, .children = null },
    .{ .name = "tooltip", .displayFn = displayEmpty, .children = null },
};

const basic_options: dvui.struct_ui.StructOptions(dvui.Options) = .init(.{
    .min_size_content = .default,
    .max_size_content = .default,
    .expand = .default,
    .box_shadow = .default,
    .margin = .default,
    .border = .default,
    .padding = .default,
    .corner_radius = .default,
    .background = .defaultBool,
    .color_fill = .default,
    .color_border = .default,
}, .{
    .min_size_content = .{ .w = 100, .h = 100 },
    .max_size_content = .{ .w = 100, .h = 100 },
    .border = dvui.Rect.all(1),
    .background = true,
});

const color_options: dvui.struct_ui.StructOptions(dvui.Color) = .initWithDisplayFn(displayOptionColors, .{ .a = 255, .r = 128, .g = 128, .b = 128 });

// If set at type level, then don't need to deal with displaying the optional
const type_level = true;
fn displayOptionColors(field_name: []const u8, ptr: *anyopaque, read_only: bool, alignment: *dvui.Alignment) void {
    if (read_only) return;
    const field_value_ptr: *?dvui.Color = @ptrCast(@alignCast(ptr));

    if (type_level or dvui.struct_ui.optionalFieldWidget(@src(), field_name, field_value_ptr, .{ .standard = .{} }, alignment)) {
        var box = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer box.deinit();

        dvui.label(@src(), "{s}", .{field_name}, .{});
        var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
        defer hbox_aligned.deinit();
        alignment.record(box.data().id, hbox_aligned.data());

        var hsv_color: dvui.Color.HSV = if (field_value_ptr.*) |color| .fromColor(color) else .{ .h = 180, .s = 0.5, .v = 0.5, .a = 1.0 };
        _ = dvui.colorPicker(@src(), .{ .hsv = &hsv_color }, .{});
        field_value_ptr.* = hsv_color.toColor();
    } else {
        field_value_ptr.* = null;
    }
}

pub fn displayBox() void {
    const defaults = struct {
        const nr_boxes = 10;
        const expand: dvui.Options.Expand = .none;
        const init_opts: dvui.BoxWidget.InitOptions = .{};
        const options: dvui.Options = .{ .expand = .both };
        //.{ .margin = dvui.Rect.all(6), .border = dvui.Rect.all(1) };
    };
    const state = struct {
        var test_options: struct {
            nr_boxes: usize = defaults.nr_boxes,
            expand: dvui.Options.Expand = defaults.expand,
        } = .{};
        var init_opts: dvui.BoxWidget.InitOptions = defaults.init_opts;
        var options: dvui.Options = defaults.options;
    };

    if (reset_widget) {
        state.test_options.nr_boxes = defaults.nr_boxes;
        state.test_options.expand = defaults.expand;
        state.init_opts = defaults.init_opts;
        state.options = defaults.options;
    }
    const size_content: dvui.Size = .{ .w = 250, .h = 250 };
    var gbox = dvui.groupBox(@src(), "box()", .{ .expand = .both });
    defer gbox.deinit();
    var wd: dvui.WidgetData = undefined;
    {
        var outer_hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{
            .expand = .horizontal,
            //.padding = dvui.Rect.all(6),
            .min_size_content = .cast(size_content),
            .max_size_content = .cast(size_content),
            .border = dvui.Rect.all(1),
            .corner_radius = dvui.Rect.all(3),
        });
        defer outer_hbox.deinit();
        var box = dvui.box(@src(), state.init_opts, state.options.override(.{ .data_out = &wd }));
        defer box.deinit();
        for (0..state.test_options.nr_boxes) |i| {
            var b = dvui.box(@src(), .{}, .{
                .min_size_content = .{ .h = 10, .w = 10 },
                .border = dvui.Rect.all(1),
                .id_extra = i,
                .expand = state.test_options.expand,
            });
            b.deinit();
        }
    }
    var scroll = dvui.scrollArea(@src(), .{}, .{});
    defer scroll.deinit();
    dvui.structUI(@src(), "test options", &state.test_options, 1, .{}, .{});
    dvui.structUI(@src(), "init_opts", &state.init_opts, 1, .{}, .{});
    //    dvui.structUI(@src(), "options", &state.options, 2, .{ basic_options, color_options }, .{});
    if (dvui.expander(@src(), "Options editor", .{}, .{ .expand = .horizontal })) {
        _ = dvui.Debug.optionsEditor(&state.options, &wd);
    }
}

pub fn displayTextEntryNumber() void {
    const NumberType = i64;

    const state = struct {
        var init_opts: dvui.TextEntryNumberInitOptions(NumberType) = .{};
        var options: dvui.Options = .{ .gravity_y = 0.5 };
        var value: NumberType = -789;
    };
    const init_opts_defaults: dvui.TextEntryNumberInitOptions(NumberType) = .{ .value = &state.value, .placeholder = "Enter a number", .text = "", .min = -100, .max = 100 };

    const size_content: dvui.Size = .{ .w = 250, .h = 250 };
    var gbox = dvui.groupBox(@src(), "textEntryNumber()", .{ .expand = .both });
    defer gbox.deinit();
    var text_entry_wd: dvui.WidgetData = undefined;
    {
        var outer_hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{
            .expand = .horizontal,
            .margin = dvui.Rect.all(6),
        });
        defer outer_hbox.deinit();
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .min_size_content = .cast(size_content), .max_size_content = .cast(size_content), .border = dvui.Rect.all(1) });
        const result = dvui.textEntryNumber(@src(), NumberType, state.init_opts, state.options.override(.{ .data_out = &text_entry_wd }));
        hbox.deinit();
        dvui.structUI(@src(), "result", &result, 99, .{
            dvui.struct_ui.StructOptions(dvui.TextEntryNumberResult(NumberType)).initWithDefaults(.{
                .changed = .{ .boolean = .{ .manual_reset = true } },
                .enter_pressed = .{ .boolean = .{ .manual_reset = true } },
            }, null),
        }, .{ .gravity_x = 1.0 });
    }
    var scroll = dvui.scrollArea(@src(), .{}, .{ .corner_radius = dvui.Rect.all(3), .border = dvui.Rect.all(1), .padding = dvui.Rect.all(6), .expand = .horizontal, .margin = dvui.Rect.all(6), .background = false });
    defer scroll.deinit();
    dvui.structUI(@src(), "init_opts", &state.init_opts, 1, .{
        dvui.struct_ui.StructOptions(dvui.TextEntryNumberInitOptions(NumberType)).initWithDefaults(.{
            .text = .{ .text = .{ .display = .read_write } },
            .placeholder = .{ .text = .{ .display = .read_write } },
        }, init_opts_defaults),
    }, .{});
    if (dvui.expander(@src(), "Options editor", .{}, .{ .expand = .horizontal })) {
        _ = dvui.Debug.optionsEditor(&state.options, &text_entry_wd);
    }
}

var reset_widget: bool = false;

pub fn displayDropDownEnum() void {
    const defaults = struct {
        const init_opts: dvui.DropdownInitOptions = .{};
        const options: dvui.Options = .{ .gravity_y = 0.5 };
        const nullable = false;
    };
    const state = struct {
        var init_opts: dvui.DropdownInitOptions = defaults.init_opts;
        var options: dvui.Options = defaults.options;
        var results: struct {
            return_value: bool = false,
            choice: dvui.DropdownChoice(dvui.Options.Expand) = .{ .choice = &expand },
        } = .{};
        // Enum values to display
        var expand: dvui.Options.Expand = .none;
        var expand_maybe: ?dvui.Options.Expand = null;

        // Defaults for when fields are set to non-null
        const default_init_opts: dvui.DropdownInitOptions = .{
            .null_selectable = false,
            .placeholder = "Select something",
        };

        var test_options: struct {
            nullable: bool = defaults.nullable,
        } = .{};
    };

    if (reset_widget) {
        state.options = defaults.options;
        state.init_opts = defaults.init_opts;
        state.test_options.nullable = defaults.nullable;
    }

    const size_content: dvui.Size = .{ .w = 250, .h = 250 };
    var gbox = dvui.groupBox(@src(), "dropDownEnum()", .{ .expand = .both });
    defer gbox.deinit();
    var dropdown_wd: dvui.WidgetData = undefined;
    {
        var outer_hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .margin = dvui.Rect.all(6) });
        defer outer_hbox.deinit();
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .min_size_content = .cast(size_content), .max_size_content = .cast(size_content), .border = dvui.Rect.all(1), .corner_radius = dvui.Rect.all(3) });
        state.results.return_value = dvui.dropdownEnum(@src(), dvui.Options.Expand, state.results.choice, state.init_opts, state.options.override(.{ .data_out = &dropdown_wd }));
        hbox.deinit();
        const display_results = state.results; // Make a read-only version.
        dvui.structUI(@src(), "results", &display_results, 3, .{dvui.struct_ui.StructOptions(@TypeOf(state.results)).init(.{
            .return_value = .{ .boolean = .{ .manual_reset = true } },
            .choice = .default,
        }, null)}, .{ .gravity_x = 1.0, .border = dvui.Rect.all(1), .corner_radius = dvui.Rect.all(3), .expand = .both, .margin = .{ .x = 6 } });
    }
    {
        var scroll = dvui.scrollArea(@src(), .{}, .{ .corner_radius = dvui.Rect.all(3), .border = dvui.Rect.all(1), .padding = dvui.Rect.all(6), .expand = .horizontal, .margin = dvui.Rect.all(6), .background = false });
        defer scroll.deinit();
        dvui.structUI(@src(), "test_options", &state.test_options, 1, .{}, .{});
        if (state.test_options.nullable) {
            if (state.results.choice != .choice_nullable) {
                state.results.choice = .{ .choice_nullable = &state.expand_maybe };
            }
        } else if (state.results.choice != .choice) {
            state.results.choice = .{ .choice = &state.expand };
        }

        dvui.structUI(@src(), "init_opts", &state.init_opts, 1, .{dvui.struct_ui.StructOptions(dvui.DropdownInitOptions).initWithDefaults(.{
            .placeholder = .defaultText,
        }, state.default_init_opts)}, .{});

        if (dvui.expander(@src(), "Options editor", .{}, .{ .expand = .horizontal })) {
            _ = dvui.Debug.optionsEditor(&state.options, &dropdown_wd);
        }
    }
}

pub fn displayGroupBox() void {
    const defaults = struct {
        const options: dvui.Options = .{ .expand = .both };
        const label_short = "Shipping:";
        const label_long = "This is a really long label that will get truncated if it is long enough to span the width of the groupbox.";
    };
    const state = struct {
        var options: dvui.Options = defaults.options;
        var label = defaults.label_short;
        var test_options: struct {
            long_label: bool = false,
        } = .{};
    };

    if (reset_widget) {
        state.options = defaults.options;
        state.test_options.long_label = false;
    }

    const size_content: dvui.Size = .{ .w = 250, .h = 250 };
    var gbox = dvui.groupBox(@src(), "dropDownEnum()", .{ .expand = .both });
    defer gbox.deinit();
    var wd: dvui.WidgetData = undefined;
    {
        var outer_hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{
            .expand = .horizontal,
            .margin = dvui.Rect.all(6),
            .min_size_content = .cast(size_content),
            .max_size_content = .cast(size_content),
        });
        defer outer_hbox.deinit();
        var test_box = dvui.groupBox(@src(), if (state.test_options.long_label) defaults.label_long else defaults.label_short, state.options.override(.{ .data_out = &wd }));
        defer test_box.deinit();
        dvui.labelNoFmt(@src(), "Name:", .{}, .{});
        var te = dvui.textEntry(@src(), .{}, .{});
        te.deinit();
        dvui.labelNoFmt(@src(), "Address:", .{}, .{});
        te = dvui.textEntry(@src(), .{}, .{});
        te.deinit();
    }
    {
        var scroll = dvui.scrollArea(@src(), .{}, .{ .corner_radius = dvui.Rect.all(3), .border = dvui.Rect.all(1), .padding = dvui.Rect.all(6), .expand = .horizontal, .margin = dvui.Rect.all(6), .background = false });
        defer scroll.deinit();
        dvui.structUI(@src(), "test_options", &state.test_options, 1, .{}, .{});

        if (dvui.expander(@src(), "Options editor", .{}, .{ .expand = .horizontal })) {
            _ = dvui.Debug.optionsEditor(&state.options, &wd);
        }
    }
}
