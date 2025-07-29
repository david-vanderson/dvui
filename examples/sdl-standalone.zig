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
        const wait_event_micros = win.waitTime(end_micros, null);
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
    //arr_ptr9: *[20]u8 = &test_buf,
    array8: [13]u8 = @splat('y'),
    slice_opt10: ?[]u8 = &test_buf,
    //struct_ptr_11: *C1 = &c1, // TODO: FIX
};

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

var test_buf: [20]u8 = @splat('z');
var testStruct: TestStruct = .{};
var dvui_opts: dvui.Options = .{ .expand = .horizontal, .rect = dvui.Rect.all(5) };
var first_change: bool = true;

var basic_types_var: BasicTypes = .{};
const basic_types_const: BasicTypes = .{};

// both dvui and SDL drawing
fn gui_frame() void {
    //dvui.currentWindow().debug_window_show = true;
    {
        var m = dvui.menu(@src(), .horizontal, .{ .background = true, .expand = .horizontal });
        defer m.deinit();

        if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{ .expand = .none })) |r| {
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
    }
    {
        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
        defer scroll.deinit();
        var al = dvui.Alignment.init(@src(), 0);
        defer al.deinit();
        var ooo: dvui.se.StructOptions(BasicTypes) = .init(.{ .u8 = .{ .number = .{ .display = .none } } });
        ooo.options.put(.u8, .{ .number = .{ .display = .none } });
        ooo.options.put(.i8, .{ .number = .{ .min = 0, .max = 5, .widget_type = .slider } });
        wholeStruct(@src(), "basic_types_var", &basic_types_var, 0, .{ooo});

        //sliceFieldWidget2(@src(), "slice7", &testStruct.slice7, .{}, &al);
        //dvui.se.intFieldWidget2(@src(), "int1", &testStruct.int1, .{}, &al);
        //dvui.se.intFieldWidget2(@src(), "uint2", &testStruct.uint2, .{}, &al);
        //var buf = gpa.alloc(u8, 50) catch return;
        //buf = dvui.se.textFieldWidgetBuf(@src(), "slice5", &testStruct.slice5, .{}, buf, &al);
        //if (!first_change) {
        //    gpa.free(buf);
        //} else {
        //    first_change = false;
        //}
        //processWidget(@src(), "slice7", &testStruct.slice7, &al);
        //if (dvui.se.optionalFieldWidget2(@src(), "slice_opt10", &testStruct.slice_opt10, .{}, &al)) |optional_box| {
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
    {
        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
        defer scroll.deinit();
        var al = dvui.Alignment.init(@src(), 0);
        defer al.deinit();
        var max_size_opts: dvui.se.StructOptions(dvui.Options.MaxSize) = .initDefaults(.{ .h = 100, .w = 100 });
        max_size_opts.options.put(.w, .{ .number = .{ .min = 0, .max = dvui.max_float_safe } });
        max_size_opts.options.put(.h, .{ .number = .{ .min = 0, .max = dvui.max_float_safe } });

        const font_opts: dvui.se.StructOptions(dvui.Font) = .initDefaults(.{ .size = 10, .name = "Nope" });

        wholeStruct(@src(), "dvui.Options", &dvui_opts, 1, .{ max_size_opts, font_opts });
        //wholeStruct(@src(), "opts", &opts, 1);
        //        wholeStruct(@src(), "test_struct", &testStruct, 1);
    }
}

// Note there is also StructField.default value. But .{} should be fine?
pub fn defaultValue(T: type, options: anytype) ?T {
    //@compileLog("DEFAULT VALUE");
    //@compileLog("Default Value", T, options);
    switch (@typeInfo(T)) {
        inline .bool => return false,
        inline .int => return 0,
        inline .float => return 0.0,
        inline .@"struct" => |si| {
            comptime var default_found = false;
            inline for (options) |opt| {
                //          @compileLog(T, @TypeOf(opt).StructT);
                if (@TypeOf(opt).StructT == T) { //} and opt.default_value != null) {
                    default_found = true;
                    return opt.default_value;
                }
            }
            if (!default_found) {
                //          @compileLog("NO MATCH FOR ", T);

                inline for (si.fields) |field| {
                    if (field.defaultValue() == null) {
                        @compileError(std.fmt.comptimePrint("field {s} for struct {s} does not support default initialization", .{ field.name, @typeName(T) }));
                    }
                }
            }
            return .{};
        },
        inline .@"enum" => |e| return @enumFromInt(e.fields[0].value),
        inline else => return null,
    }
}

pub fn fieldOptions(T: type, options: anytype, field: dvui.se.StructOptions(T).StructOptionsT.Key) dvui.se.FieldOptions {
    for (options) |opt| {
        if (opt.StructT == T) {
            return opt.options.get(field);
        }
    }
    return dvui.se.StructOptions(T).defaultFieldOption(@FieldType(T, @tagName(field)));
}

pub fn wholeStruct(src: std.builtin.SourceLocation, name: []const u8, container: anytype, comptime depth: usize, options: anytype) void {
    _ = name;
    var vbox = dvui.box(src, .vertical, .{ .expand = .both });
    defer vbox.deinit();

    var al = dvui.Alignment.init(@src(), 0);
    defer al.deinit();

    // TODO: This is where the field names and field enums meet. Need to sort this out somehow...
    const opts: dvui.se.StructOptions(@TypeOf(container.*)) = opts: {
        inline for (options) |opt| {
            //@compileLog(@TypeOf(opt).StructT, @TypeOf(container.*));

            if (@TypeOf(opt).StructT == @TypeOf(container.*)) {
                //@compileLog("equal");
                break :opts opt;
            }
        }
        break :opts .initDefaults(null);
    };
    inline for (opts.options.values, 0..) |field_option, i| {
        const key = comptime @TypeOf(opts.options).Indexer.keyForIndex(i); // TODO There must be a way to iterate both? One is just the enum fields?
        // But how to guarantee ordering?

        //    }
        //    inline for (std.meta.fields(@TypeOf(container.*)), 0..) |field, i| {
        //        comptime if (std.mem.eql(u8, field.name, "max_size_content")) continue; // TODO: Needs to 1) Have exclusions and 2) Be able to specify defaults.
        //        comptime if (std.mem.eql(u8, field.name, "font")) continue;

        //@compileLog(field.name, field.type);
        var box = dvui.box(src, .vertical, .{ .id_extra = i });
        defer box.deinit();
        switch (@typeInfo(@TypeOf(@field(container, @tagName(key))))) {
            .int, .float, .@"enum", .bool => processWidget(@src(), @tagName(key), &@field(container, @tagName(key)), &al, field_option),
            inline .@"struct" => {
                if (depth > 0) {
                    if (dvui.expander(@src(), @tagName(key), .{}, .{ .expand = .horizontal })) {
                        wholeStruct(@src(), @tagName(key), &@field(container, @tagName(key)), depth - 1, options);
                    }
                }
            },
            inline .optional => |opt| {
                if (dvui.se.optionalFieldWidget2(@src(), @tagName(key), &@field(container, @tagName(key)), .{}, &al)) |hbox| {
                    defer hbox.deinit();
                    if (@field(container, @tagName(key)) == null) {
                        @field(container, @tagName(key)) = defaultValue(opt.child, options); // If there is no default value, it will remain null.
                    }
                    if (@field(container, @tagName(key)) != null) {
                        switch (@typeInfo(opt.child)) {
                            inline .@"struct" => {
                                if (depth > 0) {
                                    if (dvui.expander(@src(), @tagName(key), .{}, .{ .expand = .horizontal })) {
                                        wholeStruct(@src(), @tagName(key), &@field(container, @tagName(key)).?, depth - 1, options);
                                    }
                                }
                            },
                            else => processWidget(@src(), @tagName(key), &@field(container, @tagName(key)).?, &al, field_option),
                        }
                    }
                } else {
                    @field(container, @tagName(key)) = null;
                    dvui.label(@src(), "{s} is null", .{@tagName(key)}, .{ .id_extra = i }); // TODO: Make this nicer formatting.
                }
            },
            inline .pointer => |ptr| {
                if (ptr.size == .slice and ptr.child == u8) {
                    processWidget(src, @tagName(key), &@field(container, @tagName(key)), &al, field_option);
                } else if (ptr.size == .slice) {
                    sliceFieldWidget2(src, @tagName(key), @field(container, @tagName(key)), &al);
                } else if (ptr.size == .one) {
                    dvui.label(@src(), "{s} is a single item pointer", .{@tagName(key)}, .{ .id_extra = i }); // TODO: Make this nicer formatting.
                    switch (@typeInfo(ptr.child)) {
                        .@"struct" => {
                            if (dvui.expander(@src(), @tagName(key), .{}, .{ .expand = .horizontal })) {
                                wholeStruct(@src(), @tagName(key), &@field(container, @tagName(key)), depth - 1, options);
                            }
                        },
                        else => processWidget(src, @tagName(key), @field(container, @tagName(key)), &al, field_option),
                    }
                } else if (ptr.size == .c or ptr.size == .many) {
                    @compileError("structEntry does not support *C or Many pointers");
                } else {
                    switch (@typeInfo(ptr.child)) {
                        inline .int, .float, .@"enum" => processWidget(@src(), @tagName(key), @field(container, @tagName(key)), &al, field_option),
                        inline .@"struct" => {
                            if (depth > 0) {
                                if (dvui.expander(@src(), @tagName(key), .{}, .{ .expand = .horizontal })) {
                                    wholeStruct(@src(), @tagName(key), &@field(container, @tagName(key)), depth - 1, options);
                                }
                            }
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }
}

pub fn processWidget(
    src: std.builtin.SourceLocation,
    comptime field_name: []const u8,
    field: anytype,
    alignment: *dvui.Alignment,
    options: dvui.se.FieldOptions,
) void {
    switch (@typeInfo(@TypeOf(field.*))) {
        inline .int => dvui.se.numberFieldWidget2(src, field_name, field, options.number, alignment),
        inline .float => dvui.se.numberFieldWidget2(src, field_name, field, options.number, alignment),
        inline .@"enum" => dvui.se.enumFieldWidget2(src, field_name, field, options.standard, alignment),
        inline .bool => dvui.se.boolFieldWidget2(src, field_name, field, options.standard, alignment),
        inline .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                dvui.se.textFieldWidget2(src, field_name, field, options.standard, alignment);
            }
        },
        inline .@"union" => {}, // BIG TODO!
        else => @compileError(std.fmt.comptimePrint("Type {s} for field {s} not yet supported\n", .{ @typeName(@TypeOf(field.*)), field_name })),
    }
}

//const SliceFieldWidget = struct {
//    action: enum { none, add, remove },
//    insert_before_idx: ?usize,
//    reorder: *dvui.ReorderWidget,
//    vbox: *dvui.BoxWidget,
//
//    pub fn deinit(self: SliceFieldWidget) void {
//        // show a final slot that allows dropping an entry at the end of the list
//        if (self.reorder.finalSlot()) {
//            self.insert_before_idx = field_ptr.*.len; // entry was dropped into the final slot
//        }
//
//        // returns true if the slice was reordered
//        _ = dvui.ReorderWidget.reorderSlice(Child, field_ptr.*, removed_idx, insert_before_idx);
//
//        self.vbox.deinit();
//        self.reorder.deinit();
//    }
//};
//

// TODO: So I think this should just display the data vertically. I don't really get what the "re-ordering does".

// Re-ordering / add and remove are advanced options? Just default to displaying / edit in place?
pub fn sliceFieldWidget2(
    comptime src: std.builtin.SourceLocation,
    comptime field_name: []const u8,
    field_ptr: anytype,
    opt: dvui.se.SliceFieldOptions,
    alignment: *dvui.Alignment,
) void {
    if (@typeInfo(@TypeOf(field_ptr.*)).pointer.size != .slice) @compileError("must be called with slice");

    //const Child = @typeInfo(@TypeOf(field_ptr.*)).pointer.child;

    //const ProvidedPointerTreatment = enum {
    //    mutate_value_in_place_only,
    //    display_only,
    //};

    //    const treatment: ProvidedPointerTreatment = if (@typeInfo(@TypeOf(field_ptr.*)).pointer.is_const) .display_only else .mutate_value_in_place_only;
    //
    //    var removed_idx: ?usize = null;
    //    var insert_before_idx: ?usize = null;

    var vbox = dvui.box(src, .vertical, .{ .expand = .horizontal });
    dvui.label(@src(), "{s}", .{opt.label_override orelse field_name}, .{});

    for (field_ptr.*, 0..) |_, i| {
        var hbox = dvui.box(@src(), .horizontal, .{
            .expand = .horizontal,
            .border = dvui.Rect.all(1),
            .background = true,
            .color_fill = .{ .name = .fill_window },
            .id_extra = i,
        });
        defer hbox.deinit();
        var buf: [128]u8 = undefined;
        const name = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return;
        processWidget(@src(), name, &(field_ptr.*)[i], alignment);
    }

    vbox.deinit();
}
