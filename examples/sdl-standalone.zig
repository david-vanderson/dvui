const std = @import("std");
const dvui = @import("dvui");
comptime {
    std.debug.assert(dvui.backend_kind == .sdl);
}
const Backend = dvui.backend;

const window_icon_png = @embedFile("zig-favicon.png");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const vsync = true;

/// This example shows how to use the dvui for a normal application:
/// - dvui renders the whole application
/// - render frames only when needed
pub fn main() !void {
    defer _ = gpa_instance.deinit();

    // init SDL backend (creates and owns OS window)
    var backend = try Backend.initWindow(.{
        .allocator = gpa,
        .size = .{ .w = 800.0, .h = 600.0 },
        .min_size = .{ .w = 250.0, .h = 350.0 },
        .vsync = vsync,
        .title = "DVUI SDL Standalone Example",
        .icon = window_icon_png, // can also call setIconFromFileContent()
    });
    defer backend.deinit();

    // init dvui Window (maps onto a single OS window)
    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{});
    defer win.deinit();

    main_loop: while (true) {

        // beginWait coordinates with waitTime below to run frames only when needed
        const nstime = win.beginWait(backend.hasEvent());


        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(nstime);

        // send all SDL events to dvui for processing
        const quit = try backend.addAllEvents(&win);
        if (quit) break :main_loop;

        // if dvui widgets might not cover the whole window, then need to clear
        // the previous frame's render
        _ = Backend.c.SDL_SetRenderDrawColor(backend.renderer, 0, 0, 0, 255);
        _ = Backend.c.SDL_RenderClear(backend.renderer);

        // both dvui and SDL drawing
        try gui_frame(backend);

        // marks end of dvui frame, don't call dvui functions after this
        // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
        const end_micros = try win.end(.{});

        // cursor management
        backend.setCursor(win.cursorRequested());

        // render frame to OS
        backend.renderPresent();

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = win.waitTime(end_micros, null);
        backend.waitEventTimeout(wait_event_micros);
    }
}

const Rect = dvui.Rect;
const demo_box_size = 120; // size of demo image, obviously
const demo_pad      = 5;   // space between demos


const DemoFn = *const fn() anyerror!void;
const Demo = struct{
    ui_fn: DemoFn,
    label: [] const u8
};

fn demoButton(src: std.builtin.SourceLocation, demo: Demo) !bool {
    // initialize widget and get rectangle from parent
    var bw = dvui.ButtonWidget.init(src, .{}, .{ .id_extra = @intFromPtr(demo.ui_fn), .margin = .{}, .padding = .{} });

    // make ourselves the new parent
    try bw.install();

    // process events (mouse and keyboard)
    bw.processEvents();

    // use pressed text color if desired
    const click = bw.clicked();
    var options: dvui.Options = .{ .gravity_x = 0.5, .gravity_y = 0.5 };

    if (dvui.captured(bw.wd.id)) options = options.override(.{ .color_text = .{ .color = options.color(.text_press) } });

    // this child widget:
    // - has bw as parent
    // - gets a rectangle from bw
    // - draws itself
    // - reports its min size to bw
    {
        var demo_box = try dvui.box(
            @src(),
            .vertical,
            .{
                .border = Rect.all(1),
                .min_size_content = .{ .w = demo_box_size, .h = demo_box_size },
                .margin = Rect.all(demo_pad),
                .color_fill = .{ .name = if (bw.hover) .fill_hover else .fill }
            }
        );
        defer demo_box.deinit();

        const zig_favicon = @embedFile("zig-favicon.png");
        try dvui.image(@src(), "zig favicon", zig_favicon, .{
            .gravity_x = 0.5,
            .gravity_y = 0.5,
            .expand = .both,
            .min_size_content = .{ .w = 100, .h = 100 },
            .rotation = 0,
        });

        try dvui.labelNoFmt(@src(), demo.label, .{
            .margin = .{ .x = 4, .w = 4 },
            .gravity_x = 0.5,
            .font_style = .title_4
        });
    }

    // draw focus
    try bw.drawFocus();

    // restore previous parent
    // send our min size to parent
    bw.deinit();

    return click;
}

var demo_active: ?Demo = null;
fn gui_frame(_: Backend) !void {

    var scroll = try dvui.scrollArea(@src(), .{}, .{ .expand = .both });
    defer scroll.deinit();

    if (demo_active) |demo| {
        {
            var b = try dvui.box(@src(), .horizontal, .{});
            defer b.deinit();

            if (try dvui.button(@src(), "<", .{}, .{ .gravity_y = 0.5 })) {
                demo_active = null;
            }
            try dvui.labelNoFmt(@src(), demo.label, .{ .margin = .{ .x = 4, .y = 4, .w = 4 }, .font_style = .title_1 });
        }

        try demo.ui_fn();
    } else {
        try dvui.labelNoFmt(@src(), "DVUI Demos", .{ .margin = .{ .x = 4, .y = 12, .w = 4 }, .font_style = .title_1, .gravity_x = 0.5 });

        var demo_area_pad = try dvui.box(
            @src(),
            .horizontal,
            .{
                .padding = Rect.all(5),
                .expand = .both,
            }
        );
        defer demo_area_pad.deinit();
        var demo_area = try dvui.box(
            @src(),
            .vertical,
            .{
                .padding = Rect.all(5),
                .expand = .both,
            }
        );
        defer demo_area.deinit();

        const demos = [_]Demo{
            .{ .ui_fn = dvui.Examples.incrementor,        .label = "Incrementor" },
            .{ .ui_fn = dvui.Examples.calculator,         .label = "Calculator" },

            .{ .ui_fn = dvui.Examples.basicWidgets,       .label = "Basic Widgets" },
            .{ .ui_fn = dvui.Examples.textEntryWidgets,   .label = "Text Entry" },

            .{ .ui_fn = dvui.Examples.reorderLists,       .label = "Reorderables" },
            .{ .ui_fn = dvui.Examples.menus,              .label = "Menus" },
            .{ .ui_fn = dvui.Examples.focus,              .label = "Focus" },

            .{ .ui_fn = dvui.Examples.scrolling,          .label = "Scrolling" },
            .{ .ui_fn = dvui.Examples.animations,         .label = "Animations" },

            .{ .ui_fn = dvui.Examples.themeEditor,        .label = "Theme Editor" },
            .{ .ui_fn = dvui.Examples.themeSerialization, .label = "Save Theme" },

            .{ .ui_fn = dvui.Examples.layout,             .label = "Layout" },
            .{ .ui_fn = dvui.Examples.layoutText,         .label = "Text Layout" },
            .{ .ui_fn = dvui.Examples.styling,            .label = "Styling" },


            // TODO: toasts requires a window to point at ...
            // TODO: "auto-widget from struct" requires factoring into function

            .{ .ui_fn = dvui.Examples.debuggingErrors,    .label = "Debugging" },
        };
        const demo_area_space = @max(demo_area.childRect.w, demo_pad*2 + 1);
        const demos_per_row: usize = @intFromFloat(@floor((demo_area_space - demo_pad*2) / (demo_box_size + 2*demo_pad)));
        const demo_row_full_size: f32 = @floatFromInt(demo_pad*2 + demos_per_row * (demo_box_size + 2*demo_pad));

        var demo_i: usize = 0;
        for (0..(1 + demos.len / @max(1, demos_per_row))) |row_i| {
            var demo_row = try dvui.box(
                @src(),
                .horizontal,
                .{
                    .id_extra = row_i,
                    .gravity_x = 0.5,
                    .min_size_content = .{ .w = demo_row_full_size }
                }
            );
            defer demo_row.deinit();

            for (0..demos_per_row) |_| {
                if (demo_i >= demos.len) continue;

                const demo = demos[demo_i];
                defer demo_i += 1;

                if (try demoButton(@src(), demo)) {
                    demo_active = demo;
                }
            }
        }
    }
}
