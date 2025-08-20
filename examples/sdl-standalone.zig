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
const show_demo = true;
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
    std.log.info("SDL version: {}", .{SDLBackend.getSDLVersion()});

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
        const quit = try backend.addAllEvents(&win);
        if (quit) break :main_loop;

        // if dvui widgets might not cover the whole window, then need to clear
        // the previous frame's render
        _ = SDLBackend.c.SDL_SetRenderDrawColor(backend.renderer, 0, 0, 0, 255);
        _ = SDLBackend.c.SDL_RenderClear(backend.renderer);

        const keep_running = true;
        gui_frame();
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
    }
    if (!first_change) {
        gpa.free(testStruct.slice5);
    }
}

const C1 = struct {
    value: usize = 0,
};

const C2 = struct {
    value2: f32 = 0,
};

const TestUnion = union(enum) {
    c1: C1,
    c2: C2,
};

var c1: C1 = .{};

const TestStruct = struct {
    int1: i32 = 42,
    oint1: ?i32 = 43,
    uint2: usize = 38,
    rect3: dvui.Rect = .all(2),
    union4: TestUnion = .{ .c2 = .{ .value2 = 44 } },
    slice5: []const u8 = "ABCDEF",
    slice7: []u8 = &test_buf,
    arr_ptr9: *[20]u8 = &test_buf,
    array8: [13]u8 = @splat('y'),
    slice_opt10: ?[]u8 = &test_buf,
    struct_ptr_11: *C1 = &c1, // TODO: FIX
    struct_slice: []TestStruct = &array_of_struct,

    pub const structui_options: dvui.struct_ui.StructOptions(TestStruct) = .init(.{
        .int1 = .{ .number = .{ .min = 5, .max = 50, .widget_type = .slider } },
        .slice7 = .{ .text = .{ .display = .read_only } },
        .uint2 = .{ .number = .{ .display = .none } },
    });
};

var array_of_struct: [3]TestStruct = .{ .{}, .{}, .{} };

// All possible runtime basic types.
const BasicTypes = struct {
    var static_int: usize = 44;
    i8: i8 = 1,
    u8: u8 = 2,
    i16: i16 = 3,
    u16: u16 = 4,
    i32: i32 = 5,
    u32: u32 = 6,
    i64: i64 = 7,
    u64: u64 = 8,
    i128: i128 = 9,
    u128: u128 = 10,
    isize: isize = 11,
    usize: usize = 12,
    c_char: c_char = 'b',
    c_short: c_short = 13,
    c_ushort: c_ushort = 14,
    c_int: c_int = 15,
    c_uint: c_uint = 16,
    c_long: c_long = 17,
    c_ulong: c_ulong = 18,
    c_longlong: c_longlong = 19,
    c_ulonglong: c_ulonglong = 20,
    f16: f16 = 1.1,
    f32: f32 = 2.2,
    f64: f64 = 3.3,
    f80: f80 = 4.4,
    f128: f128 = 5.5,
    bool: bool = true,
    void: void = {}, // The only possible value for `void`
    anyerror: anyerror = error.DefaultError, // Initialized to a specific error
};

const S1 = struct {
    a: usize = 42,
};

const Enum = enum { x, y, z };

const U1 = union(enum) {
    a: S1,
    b2: enum { one, two, three },
    b: f32,
    c: Enum,
    d: ?S1,
};

var test_buf: [20]u8 = @splat('z');
var testStruct: TestStruct = .{};
var dvui_opts: dvui.Options = .{ .expand = .horizontal, .rect = dvui.Rect.all(5), .name = "abcdef" };
var first_change: bool = true;

var basic_types_var: BasicTypes = .{};
const basic_types_const: BasicTypes = .{};

const StructOfUnion1 = struct { u: U1 = .{ .a = .{} } };
var struct_of_union1: StructOfUnion1 = .{};

var ts: TestStruct = .{};

// both dvui and SDL drawing
fn gui_frame() void {
    //dvui.currentWindow().debug_window_show = true;
    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .style = .window, .background = true, .expand = .horizontal });
        defer hbox.deinit();

        var m = dvui.menu(@src(), .horizontal, .{});
        defer m.deinit();

        if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{})) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();

            if (dvui.menuItemLabel(@src(), "Close Menu", .{}, .{ .expand = .horizontal }) != null) {
                m.close();
            }
        }
    }
    var hbox = dvui.box(@src(), .horizontal, .{ .color_fill = .fill_window, .background = true });
    defer hbox.deinit();

    {
        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
        defer scroll.deinit();
        var al = dvui.Alignment.init(@src(), 0);
        defer al.deinit();
        //wholeStruct(@src(), "basic_types_const", &basic_types_const, 0, .{});
        //        dvui.struct_ui.displayStruct("basic_types_const", &basic_types_const, 0, .{ .standard = .{} }, .{}, &al);
        //dvui.struct_ui.displayArray("array_of_struct", &array_of_struct, 1, .{ .standard = .{} }, .{}, &al);

        dvui.struct_ui.displayStruct("test_struct", &ts, 1, .{ .standard = .{} }, .{TestStruct.structui_options}, &al);
    }
    {
        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
        defer scroll.deinit();
        var al = dvui.Alignment.init(@src(), 0);
        defer al.deinit();

        //dvui.struct_ui.displayStruct("basic_types_var", &basic_types_var, 0, .{}, .{}, &al);
        //var ts: TestStruct = .{};
        //dvui.struct_ui.displayStruct("test_struct", &ts, 0, .{ .standard = .{} }, .{}, &al);

        //        const uo: dvui.struct_ui.StructOptions(U1) = .initDefaults(.{ .a = .{} });
        //        const so: dvui.struct_ui.StructOptions(StructOfUnion1) = .initDefaults(.{});
        //        dvui.struct_ui.displayStruct("struct_of_union1", &struct_of_union1, 1, .{ .standard = .{} }, .{ uo, so }, &al);
        //        }
        //
        //sliceFieldWidget2(@src(), "slice7", &testStruct.slice7, .{}, &al);
        //dvui.struct_ui.intFieldWidget2(@src(), "int1", &testStruct.int1, .{}, &al);
        //dvui.struct_ui.intFieldWidget2(@src(), "uint2", &testStruct.uint2, .{}, &al);
        //var buf = gpa.alloc(u8, 50) catch return;
        //buf = dvui.struct_ui.textFieldWidgetBuf(@src(), "slice5", &testStruct.slice5, .{}, buf, &al);
        //if (!first_change) {
        //    gpa.free(buf);
        //} else {
        //    first_change = false;
        //}
        //processWidget(@src(), "slice7", &testStruct.slice7, &al);
        //if (dvui.struct_ui.optionalFieldWidget2(@src(), "slice_opt10", &testStruct.slice_opt10, .{}, &al)) |optional_box| {
        //    defer optional_box.deinit();
        //    testStruct.slice_opt10 = testStruct.slice7;
        //    processWidget(@src(), "", &testStruct.slice_opt10.?, &al);
        //} else {
        //    testStruct.slice_opt10 = null;
        //}

        //std.debug.print("slice 5 = {s}\n", .{testStruct.slice5});
        //_ = dvui.separator(@src(), .{ .expand = .horizontal });
        //wholeStruct(@src(), &testStruct, 0);
        //_ = dvui.separator(@src(), .{ .expand = .horizontal });
        //wholeStruct(@src(), &testStruct, 1);
        //_ = dvui.separator(@src(), .{ .expand = .horizontal });
        //wholeStruct(@src(), &opts, 1);
        //_ = dvui.separator(@src(), .{ .expand = .horizontal });
    }
    if (false) {
        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
        defer scroll.deinit();
        var al = dvui.Alignment.init(@src(), 0);
        defer al.deinit();

        var max_size_opts: dvui.struct_ui.StructOptions(dvui.Options.MaxSize) = .initDefaults(.{ .h = 100, .w = 100 });
        //var max_size_opts: dvui.struct_ui.StructOptions(dvui.Options.MaxSize) = .initDefaults(null);
        max_size_opts.options.put(.w, .{ .number = .{ .min = -2, .max = dvui.max_float_safe } });
        max_size_opts.options.put(.h, .{ .number = .{ .min = -2, .max = dvui.max_float_safe } });

        const font_opts: dvui.struct_ui.StructOptions(dvui.Font) = .initDefaults(.{ .size = 10, .name = "Nope" });
        // const font_opts: dvui.struct_ui.StructOptions(dvui.Font) = .initDefaults(null);
        var options_options: dvui.struct_ui.StructOptions(dvui.Options) = .initDefaults(.{});
        options_options.options.put(.name, .{ .text = .{ .buffer = &name_buf } });

        const color_options: dvui.struct_ui.StructOptions(dvui.Color) = .initDefaults(.{});
        const con_options = dvui.struct_ui.StructOptions(dvui.Options.ColorOrName).initDefaults(.{ .color = .{} });
        dvui.struct_ui.displayStruct("dvui.Options", &dvui_opts, 1, .{ .standard = .{} }, .{ options_options, max_size_opts, font_opts, color_options, con_options }, &al);
        // wholeStruct(@src(), "dvui.Options", &dvui_opts, 1, .{ options_options, max_size_opts, font_opts, color_options, con_options });
        //wholeStruct(@src(), "opts", &opts, 1);
        //        wholeStruct(@src(), "test_struct", &testStruct, 1);
    }
}

var name_buf: [50]u8 = undefined;
