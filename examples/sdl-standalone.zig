const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const Backend = dvui.backend;
comptime {
    std.debug.assert(@hasDecl(Backend, "SDLBackend"));
}

const window_icon_png = @embedFile("zig-favicon.png");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const vsync = true;
const show_demo = true;
var scale_val: f32 = 1.0;

var show_dialog_outside_frame: bool = false;
var g_backend: ?Backend = null;
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
    std.log.info("SDL version: {}", .{Backend.getSDLVersion()});

    dvui.Examples.show_demo_window = show_demo;

    defer if (gpa_instance.deinit() != .ok) @panic("Memory leak on exit!");

    // init SDL backend (creates and owns OS window)
    var backend = try Backend.initWindow(.{
        .allocator = gpa,
        .size = .{ .w = 800.0, .h = 600.0 },
        .min_size = .{ .w = 250.0, .h = 350.0 },
        .vsync = vsync,
        .title = "DVUI SDL Standalone Example",
        .icon = window_icon_png, // can also call setIconFromFileContent()
    });
    g_backend = backend;
    defer backend.deinit();

    _ = Backend.c.SDL_EnableScreenSaver();

    // init dvui Window (maps onto a single OS window)
    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{});
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
        _ = Backend.c.SDL_SetRenderDrawColor(backend.renderer, 0, 0, 0, 255);
        _ = Backend.c.SDL_RenderClear(backend.renderer);

        // The demos we pass in here show up under "Platform-specific demos"
        gui_frame();

        // marks end of dvui frame, don't call dvui functions after this
        // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
        const end_micros = try win.end(.{});

        // cursor management
        try backend.setCursor(win.cursorRequested());
        try backend.textInputRect(win.textInputRequested());

        // render frame to OS
        try backend.renderPresent();

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = win.waitTime(end_micros, null);
        interrupted = try backend.waitEventTimeout(wait_event_micros);

        // Example of how to show a dialog from another thread (outside of win.begin/win.end)
        if (show_dialog_outside_frame) {
            show_dialog_outside_frame = false;
            dvui.dialog(@src(), .{}, .{ .window = &win, .modal = false, .title = "Dialog from Outside", .message = "This is a non modal dialog that was created outside win.begin()/win.end(), usually from another thread." });
        }
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
};

var test_buf: [20]u8 = @splat('z');
var testStruct: TestStruct = .{};
var opts: dvui.Options = .{ .expand = .horizontal, .rect = dvui.Rect.all(5) };

// both dvui and SDL drawing
fn gui_frame() void {
    {
        var m = dvui.menu(@src(), .horizontal, .{ .background = true, .expand = .horizontal });
        defer m.deinit();

        if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{ .expand = .none })) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();

            if (dvui.menuItemLabel(@src(), "Close Menu", .{}, .{}) != null) {
                m.close();
            }
        }
    }
    var hbox = dvui.box(@src(), .horizontal, .{ .color_fill = .fill_window, .background = true });
    defer hbox.deinit();

    {
        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
        defer scroll.deinit();

        //dvui.structEntryEx(@src(), "", TestStruct, .{}, &testStruct, .{});
    }
    {
        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
        defer scroll.deinit();
        var al = dvui.Alignment.init();
        defer al.deinit();
        dvui.se.intFieldWidget2(@src(), "int1", &testStruct.int1, .{}, &al);
        dvui.se.intFieldWidget2(@src(), "uint2", &testStruct.uint2, .{}, &al);
        _ = dvui.separator(@src(), .{ .expand = .horizontal });
        wholeStruct(@src(), &testStruct, 0);
        _ = dvui.separator(@src(), .{ .expand = .horizontal });
        wholeStruct(@src(), &testStruct, 1);
        _ = dvui.separator(@src(), .{ .expand = .horizontal });
        wholeStruct(@src(), &opts, 1);
        _ = dvui.separator(@src(), .{ .expand = .horizontal });
    }
}

pub fn wholeStruct(src: std.builtin.SourceLocation, container: anytype, depth: usize) void {
    var al = dvui.Alignment.init();
    defer al.deinit();
    inline for (std.meta.fields(@TypeOf(container.*)), 0..) |field, i| {
        //@compileLog(field.name, field.type);
        var box = dvui.box(src, .vertical, .{ .id_extra = i });
        defer box.deinit();
        switch (@typeInfo(field.type)) {
            .int, .float, .@"enum" => processWidget(@src(), field.name, &@field(container, field.name), &al),
            inline .@"struct" => if (depth > 0) wholeStruct(@src(), &@field(container, field.name), depth - 1),
            inline .optional => |opt| {
                if (@field(container, field.name) == null) {
                    dvui.label(@src(), "{s} is null", .{field.name}, .{ .id_extra = i });
                } else {
                    dvui.label(@src(), "{s}", .{field.name}, .{ .id_extra = i });
                    //@compileLog(std.fmt.comptimePrint("child = {s} : {}", .{ @typeName(opt.child), @typeInfo(opt.child) }));
                    switch (@typeInfo(opt.child)) {
                        inline .int, .float, .@"enum" => processWidget(@src(), field.name, &@field(container, field.name).?, &al),
                        inline .@"struct" => if (depth > 0) wholeStruct(@src(), &@field(container, field.name).?, depth - 1),
                        else => {},
                    }
                }
            },
            else => {},
        }
    }
}

pub fn processWidget(src: std.builtin.SourceLocation, comptime field_name: []const u8, field: anytype, alignment: *dvui.Alignment) void {
    switch (@typeInfo(@TypeOf(field.*))) {
        inline .int => dvui.se.intFieldWidget2(src, field_name, field, .{}, alignment),
        inline .float => dvui.se.floatFieldWidget2(src, field_name, field, .{}, alignment),
        inline .@"enum" => dvui.se.enumFieldWidget2(src, field_name, field, .{}, alignment),
        else => |ti| @compileError(std.fmt.comptimePrint("Type {s} for field {s} not yet supported\n", .{ ti.type, field_name })),
    }
}
