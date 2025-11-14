const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");

pub const kind: dvui.enums.Backend = .web;

pub const WebBackend = @This();
pub const Context = *WebBackend;

const log = std.log.scoped(.WebBackend);

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

pub var win: dvui.Window = undefined;
pub var win_ok = false;
var arena: std.mem.Allocator = undefined;
var touchPoints: [10]?dvui.Point = [_]?dvui.Point{null} ** 10;
var have_event = false;

cursor_last: dvui.enums.Cursor = .wait,
force_new_window: bool = true,

const EventTemp = struct {
    kind: u8,
    int1: u32,
    int2: u32,
    float1: f32,
    float2: f32,
};

// pub var event_temps = std.ArrayList(EventTemp).init(gpa);

pub const wasm = if (!builtin.is_test) struct {
    pub extern "dvui" fn wasm_about_webgl2() u8;

    pub extern "dvui" fn wasm_panic(ptr: [*]const u8, len: usize) void;
    pub extern "dvui" fn wasm_console_drain(ptr: [*]const u8, len: usize) void;
    pub extern "dvui" fn wasm_console_flush(log_level: u8) void;

    pub extern "dvui" fn wasm_now() f64;
    pub extern "dvui" fn wasm_sleep(ms: u32) void;
    pub extern "dvui" fn wasm_refresh() void;

    pub extern "dvui" fn wasm_pixel_width() f32;
    pub extern "dvui" fn wasm_pixel_height() f32;
    pub extern "dvui" fn wasm_canvas_width() f32;
    pub extern "dvui" fn wasm_canvas_height() f32;

    pub extern "dvui" fn wasm_frame_buffer() u8;
    pub extern "dvui" fn wasm_textureCreate(pixels: [*]const u8, width: u32, height: u32, interp: u8) u32;
    pub extern "dvui" fn wasm_textureCreateTarget(width: u32, height: u32, interp: u8) u32;
    pub extern "dvui" fn wasm_textureRead(texture: u32, pixels_out: [*]u8, width: u32, height: u32) void;
    pub extern "dvui" fn wasm_renderTarget(u32) void;
    pub extern "dvui" fn wasm_textureDestroy(u32) void;
    pub extern "dvui" fn wasm_renderGeometry(texture: u32, index_ptr: [*]const u8, index_len: usize, vertex_ptr: [*]const u8, vertex_len: usize, sizeof_vertex: u8, offset_pos: u8, offset_col: u8, offset_uv: u8, clip: u8, x: i32, y: i32, w: i32, h: i32) void;

    pub extern "dvui" fn wasm_cursor(name: [*]const u8, name_len: usize) void;
    pub extern "dvui" fn wasm_text_input(x: f32, y: f32, w: f32, h: f32) void;
    pub extern "dvui" fn wasm_open_url(ptr: [*]const u8, len: usize, new_window: bool) void;
    pub extern "dvui" fn wasm_preferred_color_scheme() u8;
    pub extern "dvui" fn wasm_download_data(name_ptr: [*]const u8, name_len: usize, data_ptr: [*]const u8, data_len: usize) void;
    pub extern "dvui" fn wasm_clipboardTextSet(ptr: [*]const u8, len: usize) void;

    // NOTE: bool in extern becomes 0 and 1 in js, which is falsy and truthy respectively
    pub extern "dvui" fn wasm_open_file_picker(id: u64, accept_ptr: [*]const u8, accept_len: usize, multiple: bool) void;
    pub extern "dvui" fn wasm_get_number_of_files_available(id: u64) usize;
    pub extern "dvui" fn wasm_get_file_name(id: u64, file_index: usize) [*:0]u8;
    pub extern "dvui" fn wasm_get_file_size(id: u64, file_index: usize) isize;
    pub extern "dvui" fn wasm_read_file_data(id: u64, file_index: usize, data: [*]u8) void;

    pub extern "dvui" fn wasm_add_noto_font() void;
} else struct { // Mock api for testing that this backend is semantically correct, cannot test behaviour
    pub fn wasm_about_webgl2() u8 {
        return undefined;
    }

    pub fn wasm_panic(_: [*]const u8, _: usize) void {}
    pub fn wasm_console_drain(_: [*]const u8, _: usize) void {}
    pub fn wasm_console_flush(_: u8) void {}

    pub fn wasm_now() f64 {
        return undefined;
    }
    pub fn wasm_sleep(_: u32) void {}
    pub fn wasm_refresh() void {}

    pub fn wasm_pixel_width() f32 {
        return undefined;
    }
    pub fn wasm_pixel_height() f32 {
        return undefined;
    }
    pub fn wasm_canvas_width() f32 {
        return undefined;
    }
    pub fn wasm_canvas_height() f32 {
        return undefined;
    }

    pub fn wasm_frame_buffer() u8 {
        return undefined;
    }
    pub fn wasm_textureCreate(_: [*]const u8, _: u32, _: u32, _: u8) u32 {
        return undefined;
    }
    pub fn wasm_textureCreateTarget(_: u32, _: u32, _: u8) u32 {
        return undefined;
    }
    pub fn wasm_textureRead(_: u32, _: [*]u8, _: u32, _: u32) void {}
    pub fn wasm_renderTarget(_: u32) void {}
    pub fn wasm_textureDestroy(_: u32) void {}
    pub fn wasm_renderGeometry(_: u32, _: [*]const u8, _: usize, _: [*]const u8, _: usize, _: u8, _: u8, _: u8, _: u8, _: u8, _: i32, _: i32, _: i32, _: i32) void {}

    pub fn wasm_cursor(_: [*]const u8, _: usize) void {}
    pub fn wasm_text_input(_: f32, _: f32, _: f32, _: f32) void {}
    pub fn wasm_open_url(_: [*]const u8, _: usize, _: bool) void {}
    pub fn wasm_preferred_color_scheme() u8 {
        return undefined;
    }
    pub fn wasm_download_data(_: [*]const u8, _: usize, _: [*]const u8, _: usize) void {}
    pub fn wasm_clipboardTextSet(_: [*]const u8, _: usize) void {}

    pub fn wasm_open_file_picker(_: u64, _: [*]const u8, _: usize, _: bool) void {}
    pub fn wasm_get_number_of_files_available(_: u64) usize {
        return undefined;
    }
    pub fn wasm_get_file_name(_: u64, _: usize) [*:0]u8 {
        return undefined;
    }
    pub fn wasm_get_file_size(_: u64, _: usize) isize {
        return undefined;
    }
    pub fn wasm_read_file_data(_: u64, _: usize, _: [*]u8) void {}

    pub fn wasm_add_noto_font() void {}
};

export fn dvui_c_alloc(size: usize) ?*anyopaque {
    const buffer = gpa.alignedAlloc(u8, .@"8", size + 8) catch {
        //log.debug("dvui_c_alloc {d} failed", .{size});
        return null;
    };
    std.mem.writeInt(u64, buffer[0..@sizeOf(u64)], buffer.len, builtin.cpu.arch.endian());
    //log.debug("dvui_c_alloc {*} {d}", .{ buffer.ptr + 8, size });
    return buffer.ptr + 8;
}

pub export fn dvui_c_free(ptr: ?*anyopaque) void {
    const buffer = @as([*]align(8) u8, @ptrCast(@alignCast(ptr orelse return))) - 8;
    const len = std.mem.readInt(u64, buffer[0..@sizeOf(u64)], builtin.cpu.arch.endian());
    //log.debug("dvui_c_free {?*} {d}", .{ ptr, len - 8 });

    gpa.free(buffer[0..@intCast(len)]);
}

export fn dvui_c_realloc_sized(ptr: ?*anyopaque, oldsize: usize, newsize: usize) ?*anyopaque {
    //_ = oldsize;
    //log.debug("dvui_c_realloc_sized {d} {d}", .{ oldsize, newsize });

    if (ptr == null) {
        return dvui_c_alloc(newsize);
    }

    //const buffer = @as([*]u8, @ptrCast(ptr.?)) - 8;
    //const len = std.mem.readInt(u64, buffer[0..@sizeOf(u64)], builtin.cpu.arch.endian());

    //const slice = buffer[0..@intCast(len)];
    //log.debug("dvui_c_realloc_sized buffer {*} {d}", .{ ptr, len });

    //_ = gpa.resize(slice, newsize + 16);
    const newptr = dvui_c_alloc(newsize);
    const newbuf = @as([*]u8, @ptrCast(newptr));
    @memcpy(newbuf[0..oldsize], @as([*]u8, @ptrCast(ptr))[0..oldsize]);
    dvui_c_free(ptr);
    return newptr;

    //std.mem.writeInt(usize, slice[0..@sizeOf(usize)], slice.len, builtin.cpu.arch.endian());
    //return slice.ptr + 16;
}

export fn dvui_c_panic(msg: [*c]const u8) noreturn {
    wasm.wasm_panic(msg, std.mem.len(msg));
    unreachable;
}

export fn dvui_c_sqrt(x: f64) f64 {
    return @sqrt(x);
}

export fn dvui_c_pow(x: f64, y: f64) f64 {
    return @exp(@log(x) * y);
}

export fn dvui_c_ldexp(x: f64, n: c_int) f64 {
    return x * @exp2(@as(f64, @floatFromInt(n)));
}

export fn dvui_c_floor(x: f64) f64 {
    return @floor(x);
}

export fn dvui_c_ceil(x: f64) f64 {
    return @ceil(x);
}

export fn dvui_c_fmod(x: f64, y: f64) f64 {
    return @mod(x, y);
}

export fn dvui_c_cos(x: f64) f64 {
    return @cos(x);
}

export fn dvui_c_acos(x: f64) f64 {
    return std.math.acos(x);
}

export fn dvui_c_fabs(x: f64) f64 {
    return @abs(x);
}

export fn dvui_c_strlen(x: [*c]const u8) usize {
    return std.mem.len(x);
}

export fn gpa_u8(len: usize) [*c]u8 {
    const buf = gpa.alloc(u8, len) catch return @ptrFromInt(0);
    return buf.ptr;
}

export fn gpa_free(ptr: [*c]u8, len: usize) void {
    gpa.free(ptr[0..len]);
}

export fn arena_u8(len: usize) [*c]u8 {
    const buf = arena.alloc(u8, len) catch return @ptrFromInt(0);
    return buf.ptr;
}

export fn new_font(ptr: [*c]u8, len: usize) void {
    if (win_ok) {
        win.fonts.database.put(win.gpa, .Noto, .{ .name = @tagName(dvui.Font.FontId.Noto), .bytes = ptr[0..len], .allocator = gpa }) catch unreachable;
    }
}

export fn add_event(which: u8, int1: u32, int2: u32, float1: f32, float2: f32) void {
    if (win_ok) {
        add_event_raw(&win, which, int1, int2, float1, float2) catch |err| {
            log.err("add_event_raw returned {any}", .{err});
        };
    }
}

fn add_event_raw(w: *dvui.Window, which: u8, int1: u32, int2: u32, float1: f32, float2: f32) !void {
    have_event = true;
    //event_temps.append(.{
    //    .which = which,
    //    .int1 = int1,
    //    .int2 = int2,
    //    .float1 = float1,
    //    .float2 = float2,
    //}) catch |err| {
    //    const msg = std.fmt.allocPrint(gpa, "{any}", .{err}) catch "allocPrint OOM";
    //    wasm.wasm_panic(msg.ptr, msg.len);
    //};
    switch (which) {
        1 => _ = try w.addEventMouseMotion(.{ .pt = .{ .x = float1, .y = float2 } }),
        2 => _ = try w.addEventMouseButton(buttonFromJS(int1), .press),
        3 => _ = try w.addEventMouseButton(buttonFromJS(int1), .release),
        4 => _ = try w.addEventMouseWheel(float1 * dvui.scroll_speed, if (int1 > 0) .vertical else .horizontal),
        5 => {
            const str = @as([*]u8, @ptrFromInt(int1))[0..int2];
            _ = try w.addEventKey(.{
                .action = if (float1 > 0) .repeat else .down,
                .code = web_key_code_to_dvui(str),
                .mod = web_mod_code_to_dvui(@intFromFloat(float2)),
            });
        },
        6 => {
            const str = @as([*]u8, @ptrFromInt(int1))[0..int2];
            _ = try w.addEventKey(.{
                .action = .up,
                .code = web_key_code_to_dvui(str),
                .mod = web_mod_code_to_dvui(@intFromFloat(float2)),
            });
        },
        7 => {
            const str = @as([*]u8, @ptrFromInt(int1))[0..int2];
            _ = try w.addEventText(.{ .text = str });
        },
        8 => {
            const touch: dvui.enums.Button = @enumFromInt(@intFromEnum(dvui.enums.Button.touch0) + int1);
            _ = try w.addEventPointer(.{ .button = touch, .action = .press, .xynorm = .{ .x = float1, .y = float2 } });
            touchPoints[int1] = .{ .x = float1, .y = float2 };
        },
        9 => {
            const touch: dvui.enums.Button = @enumFromInt(@intFromEnum(dvui.enums.Button.touch0) + int1);
            _ = try w.addEventPointer(.{ .button = touch, .action = .release, .xynorm = .{ .x = float1, .y = float2 } });
            touchPoints[int1] = null;
        },
        10 => {
            const touch: dvui.enums.Button = @enumFromInt(@intFromEnum(dvui.enums.Button.touch0) + int1);
            var dx: f32 = 0;
            var dy: f32 = 0;
            if (touchPoints[int1]) |p| {
                dx = float1 - p.x;
                dy = float2 - p.y;
            }
            _ = try w.addEventTouchMotion(touch, float1, float2, dx, dy);
            touchPoints[int1] = .{ .x = float1, .y = float2 };
        },
        else => log.debug("addAllEvents unknown event {d}", .{which}),
    }
}

// returns whether an event has come in since last frame (otherwise we are
// doing a frame based on an animation or timer)
pub fn hasEvent(_: *WebBackend) bool {
    //return event_temps.items.len > 0;
    return have_event;
}

fn buttonFromJS(jsButton: u32) dvui.enums.Button {
    return switch (jsButton) {
        0 => .left,
        1 => .middle,
        2 => .right,
        3 => .four,
        4 => .five,
        else => .six,
    };
}

fn hashKeyCode(str: []const u8) u32 {
    var fnv = std.hash.Fnv1a_32.init();
    fnv.update(str);
    return fnv.final();
}

fn web_key_code_to_dvui(code: []u8) dvui.enums.Key {
    @setEvalBranchQuota(2000);
    var fnv = std.hash.Fnv1a_32.init();
    fnv.update(code);
    return switch (fnv.final()) {
        hashKeyCode("a"), hashKeyCode("A") => .a,
        hashKeyCode("b"), hashKeyCode("B") => .b,
        hashKeyCode("c"), hashKeyCode("C") => .c,
        hashKeyCode("d"), hashKeyCode("D") => .d,
        hashKeyCode("e"), hashKeyCode("E") => .e,
        hashKeyCode("f"), hashKeyCode("F") => .f,
        hashKeyCode("g"), hashKeyCode("G") => .g,
        hashKeyCode("h"), hashKeyCode("H") => .h,
        hashKeyCode("i"), hashKeyCode("I") => .i,
        hashKeyCode("j"), hashKeyCode("J") => .j,
        hashKeyCode("k"), hashKeyCode("K") => .k,
        hashKeyCode("l"), hashKeyCode("L") => .l,
        hashKeyCode("m"), hashKeyCode("M") => .m,
        hashKeyCode("n"), hashKeyCode("N") => .n,
        hashKeyCode("o"), hashKeyCode("O") => .o,
        hashKeyCode("p"), hashKeyCode("P") => .p,
        hashKeyCode("q"), hashKeyCode("Q") => .q,
        hashKeyCode("r"), hashKeyCode("R") => .r,
        hashKeyCode("s"), hashKeyCode("S") => .s,
        hashKeyCode("t"), hashKeyCode("T") => .t,
        hashKeyCode("u"), hashKeyCode("U") => .u,
        hashKeyCode("v"), hashKeyCode("V") => .v,
        hashKeyCode("w"), hashKeyCode("W") => .w,
        hashKeyCode("x"), hashKeyCode("X") => .x,
        hashKeyCode("y"), hashKeyCode("Y") => .y,
        hashKeyCode("z"), hashKeyCode("Z") => .z,

        hashKeyCode("0") => .zero,
        hashKeyCode("1") => .one,
        hashKeyCode("2") => .two,
        hashKeyCode("3") => .three,
        hashKeyCode("4") => .four,
        hashKeyCode("5") => .five,
        hashKeyCode("6") => .six,
        hashKeyCode("7") => .seven,
        hashKeyCode("8") => .eight,
        hashKeyCode("9") => .nine,

        hashKeyCode(")") => .zero,
        hashKeyCode("!") => .one,
        hashKeyCode("@") => .two,
        hashKeyCode("#") => .three,
        hashKeyCode("$") => .four,
        hashKeyCode("%") => .five,
        hashKeyCode("^") => .six,
        hashKeyCode("&") => .seven,
        hashKeyCode("*") => .eight,
        hashKeyCode("(") => .nine,

        hashKeyCode("F1") => .f1,
        hashKeyCode("F2") => .f2,
        hashKeyCode("F3") => .f3,
        hashKeyCode("F4") => .f4,
        hashKeyCode("F5") => .f5,
        hashKeyCode("F6") => .f6,
        hashKeyCode("F7") => .f7,
        hashKeyCode("F8") => .f8,
        hashKeyCode("F9") => .f9,
        hashKeyCode("F10") => .f10,
        hashKeyCode("F11") => .f11,
        hashKeyCode("F12") => .f12,

        hashKeyCode("Enter") => .enter,
        hashKeyCode("Escape") => .escape,
        hashKeyCode("Tab") => .tab,
        hashKeyCode("Shift") => .left_shift,
        //hashKeyCode("ShiftRight") => .right_shift,
        hashKeyCode("Control") => .left_control,
        //hashKeyCode("ControlRight") => .right_control,
        hashKeyCode("Alt") => .left_alt,
        //hashKeyCode("AltRight") => .right_alt,
        hashKeyCode("Meta") => .left_command,
        //hashKeyCode("MetaRight") => .right_command,
        hashKeyCode("ContextMenu") => .menu,
        hashKeyCode("NumLock") => .num_lock,
        hashKeyCode("CapsLock") => .caps_lock,
        //c.SDLK_PRINTSCREEN => .print,  // can we get this?
        hashKeyCode("ScrollLock") => .scroll_lock,
        hashKeyCode("Pause") => .pause,

        hashKeyCode("Delete") => .delete,
        hashKeyCode("Home") => .home,
        hashKeyCode("End") => .end,
        hashKeyCode("PageUp") => .page_up,
        hashKeyCode("PageDown") => .page_down,
        hashKeyCode("Insert") => .insert,
        hashKeyCode("ArrowLeft") => .left,
        hashKeyCode("ArrowRight") => .right,
        hashKeyCode("ArrowUp") => .up,
        hashKeyCode("ArrowDown") => .down,
        hashKeyCode("Backspace") => .backspace,
        hashKeyCode(" ") => .space,
        hashKeyCode("-") => .minus,
        hashKeyCode("=") => .equal,
        hashKeyCode("["), hashKeyCode("{") => .left_bracket,
        hashKeyCode("]"), hashKeyCode("}") => .right_bracket,
        hashKeyCode("\\"), hashKeyCode("|") => .backslash,
        hashKeyCode(";"), hashKeyCode(":") => .semicolon,
        hashKeyCode("'"), hashKeyCode("\"") => .apostrophe,
        hashKeyCode(","), hashKeyCode("<") => .comma,
        hashKeyCode("."), hashKeyCode(">") => .period,
        hashKeyCode("/"), hashKeyCode("?") => .slash,
        hashKeyCode("`"), hashKeyCode("~") => .grave,

        else => blk: {
            log.debug("web_key_code_to_dvui unknown key code {s}\n", .{code});
            break :blk .unknown;
        },
    };
}

fn web_mod_code_to_dvui(wmod: u8) dvui.enums.Mod {
    if (wmod == 0) return .none;

    var m: u16 = 0;
    if (wmod & 0b0001 > 0) m |= @intFromEnum(dvui.enums.Mod.lshift);
    if (wmod & 0b0010 > 0) m |= @intFromEnum(dvui.enums.Mod.lcontrol);
    if (wmod & 0b0100 > 0) m |= @intFromEnum(dvui.enums.Mod.lalt);
    if (wmod & 0b1000 > 0) m |= @intFromEnum(dvui.enums.Mod.lcommand);

    return @as(dvui.enums.Mod, @enumFromInt(m));
}

//pub fn addAllEvents(self: *WebBackend, win: *dvui.Window) !void {
//    for (event_temps.items) |e| {
//        switch (e.kind) {
//            1 => _ = try win.addEventMouseMotion(e.float1, e.float2),
//            2 => _ = try win.addEventMouseButton(buttonFromJS(e.int1), .press),
//            3 => _ = try win.addEventMouseButton(buttonFromJS(e.int1), .release),
//            4 => _ = try win.addEventMouseWheel(if (e.float1 > 0) -20 else 20, .vertical),
//            5 => {
//                const str = @as([*]u8, @ptrFromInt(e.int1))[0..e.int2];
//                _ = try win.addEventKey(.{
//                    .action = if (e.float1 > 0) .repeat else .down,
//                    .code = web_key_code_to_dvui(str),
//                    .mod = web_mod_code_to_dvui(@intFromFloat(e.float2)),
//                });
//            },
//            6 => {
//                const str = @as([*]u8, @ptrFromInt(e.int1))[0..e.int2];
//                _ = try win.addEventKey(.{
//                    .action = .up,
//                    .code = web_key_code_to_dvui(str),
//                    .mod = web_mod_code_to_dvui(@intFromFloat(e.float2)),
//                });
//            },
//            7 => {
//                const str = @as([*]u8, @ptrFromInt(e.int1))[0..e.int2];
//                _ = try win.addEventText(str);
//            },
//            8 => {
//                const touch: dvui.enums.Button = @enumFromInt(@intFromEnum(dvui.enums.Button.touch0) + e.int1);
//                _ = try win.addEventPointer(touch, .press, .{ .x = e.float1, .y = e.float2 });
//                self.touchPoints[e.int1] = .{ .x = e.float1, .y = e.float2 };
//            },
//            9 => {
//                const touch: dvui.enums.Button = @enumFromInt(@intFromEnum(dvui.enums.Button.touch0) + e.int1);
//                _ = try win.addEventPointer(touch, .release, .{ .x = e.float1, .y = e.float2 });
//                self.touchPoints[e.int1] = null;
//            },
//            10 => {
//                const touch: dvui.enums.Button = @enumFromInt(@intFromEnum(dvui.enums.Button.touch0) + e.int1);
//                var dx: f32 = 0;
//                var dy: f32 = 0;
//                if (self.touchPoints[e.int1]) |p| {
//                    dx = e.float1 - p.x;
//                    dy = e.float2 - p.y;
//                }
//                _ = try win.addEventTouchMotion(touch, e.float1, e.float2, dx, dy);
//                self.touchPoints[e.int1] = .{ .x = e.float1, .y = e.float2 };
//            },
//            else => log.debug("addAllEvents unknown event kind {d}", .{e.kind}),
//        }
//    }
//
//    event_temps.clearRetainingCapacity();
//}

pub fn init() !WebBackend {
    const ret: WebBackend = .{};
    return ret;
}

pub fn deinit(self: *WebBackend) void {
    self.* = undefined;
}

pub fn backend(self: *WebBackend) dvui.Backend {
    return dvui.Backend.init(self);
}

pub fn nanoTime(_: *WebBackend) i128 {
    return @as(i128, @intFromFloat(wasm.wasm_now())) * 1_000_000;
}

pub fn sleep(_: *WebBackend, ns: u64) void {
    wasm.wasm_sleep(@intCast(@divTrunc(ns, 1_000_000)));
}

pub fn begin(_: *WebBackend, arena_in: std.mem.Allocator) !void {
    arena = arena_in;
}

pub fn end(_: *WebBackend) !void {
    have_event = false;
}

pub fn pixelSize(_: *WebBackend) dvui.Size.Physical {
    return .{ .w = wasm.wasm_pixel_width(), .h = wasm.wasm_pixel_height() };
}

pub fn windowSize(_: *WebBackend) dvui.Size.Natural {
    return .{ .w = wasm.wasm_canvas_width(), .h = wasm.wasm_canvas_height() };
}

pub fn contentScale(_: *WebBackend) f32 {
    return 1.0;
}

pub fn drawClippedTriangles(_: *WebBackend, texture: ?dvui.Texture, vtx: []const dvui.Vertex, idx: []const u16, maybe_clipr: ?dvui.Rect.Physical) !void {
    var x: i32 = std.math.maxInt(i32);
    var w: i32 = std.math.maxInt(i32);
    var y: i32 = std.math.maxInt(i32);
    var h: i32 = std.math.maxInt(i32);

    if (maybe_clipr) |clipr| {
        x = @intFromFloat(clipr.x);
        w = @intFromFloat(clipr.w);
        h = @intFromFloat(clipr.h);

        if (wasm.wasm_frame_buffer() == 0) {
            // y needs to be converted to 0 at bottom first
            const ry: f32 = wasm.wasm_pixel_height() - clipr.y - clipr.h;
            y = @intFromFloat(ry);
        } else {
            y = @intFromFloat(clipr.y);
        }
    }

    //log.debug("drawClippedTriangles pixels {} clipr {?} clip {d} {d} {d} {d}", .{ dvui.windowRectPixels(), maybe_clipr, x, y, w, h });

    const index_slice = std.mem.sliceAsBytes(idx);
    const vertex_slice = std.mem.sliceAsBytes(vtx);

    wasm.wasm_renderGeometry(
        if (texture) |t| @intCast(@intFromPtr(t.ptr)) else 0,
        index_slice.ptr,
        index_slice.len,
        vertex_slice.ptr,
        vertex_slice.len,
        @sizeOf(dvui.Vertex),
        @offsetOf(dvui.Vertex, "pos"),
        @offsetOf(dvui.Vertex, "col"),
        @offsetOf(dvui.Vertex, "uv"),
        if (maybe_clipr == null) 0 else 1,
        x,
        y,
        w,
        h,
    );
}

pub fn textureCreate(_: *WebBackend, pixels: [*]const u8, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) !dvui.Texture {
    const wasm_interp: u8 = switch (interpolation) {
        .nearest => 0,
        .linear => 1,
    };

    const id = wasm.wasm_textureCreate(pixels, width, height, wasm_interp);
    return dvui.Texture{ .ptr = @ptrFromInt(id), .width = width, .height = height };
}

pub fn textureCreateTarget(_: *WebBackend, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) !dvui.TextureTarget {
    const wasm_interp: u8 = switch (interpolation) {
        .nearest => 0,
        .linear => 1,
    };

    const id = wasm.wasm_textureCreateTarget(width, height, wasm_interp);
    return dvui.TextureTarget{ .ptr = @ptrFromInt(id), .width = width, .height = height };
}

pub fn textureFromTarget(_: *WebBackend, texture: dvui.TextureTarget) !dvui.Texture {
    return .{ .ptr = texture.ptr, .width = texture.width, .height = texture.height };
}

pub fn renderTarget(_: *WebBackend, texture: ?dvui.TextureTarget) !void {
    if (texture) |tex| {
        wasm.wasm_renderTarget(@intCast(@intFromPtr(tex.ptr)));
    } else {
        wasm.wasm_renderTarget(0);
    }
}

pub fn textureReadTarget(_: *WebBackend, texture: dvui.TextureTarget, pixels_out: [*]u8) !void {
    wasm.wasm_textureRead(@intCast(@intFromPtr(texture.ptr)), pixels_out, texture.width, texture.height);
}

pub fn textureDestroy(_: *WebBackend, texture: dvui.Texture) void {
    wasm.wasm_textureDestroy(@intCast(@intFromPtr(texture.ptr)));
}

pub fn textInputRect(_: *WebBackend, rect: ?dvui.Rect.Natural) void {
    if (rect) |r| {
        wasm.wasm_text_input(r.x, r.y, r.w, r.h);
    } else {
        wasm.wasm_text_input(0, 0, 0, 0);
    }
}

pub fn clipboardText(_: *WebBackend) ![]const u8 {
    // Current strategy is to return nothing:
    // - let the browser continue with the paste operation
    // - puts the text into the hidden_input
    // - fires the "beforeinput" event
    // - we see as normal text input
    //
    // Problem is that we can't initiate a paste, so our touch popup menu paste
    // will do nothing.  I think this could be fixed in the future once
    // browsers are all implementing the navigator.Clipboard.readText()
    // function.
    return "";
}

pub fn clipboardTextSet(_: *WebBackend, text: []const u8) !void {
    wasm.wasm_clipboardTextSet(text.ptr, text.len);
    return;
}

pub fn openURL(self: *WebBackend, url: []const u8, new_window: bool) !void {
    wasm.wasm_open_url(url.ptr, url.len, self.force_new_window or new_window);
}

pub fn preferredColorScheme(_: *WebBackend) ?dvui.enums.ColorScheme {
    return switch (wasm.wasm_preferred_color_scheme()) {
        1 => .dark,
        2 => .light,
        else => null,
    };
}

pub fn downloadData(name: []const u8, data: []const u8) !void {
    wasm.wasm_download_data(name.ptr, name.len, data.ptr, data.len);
}

/// This can be used to request a new frame directly.
///
/// If you need to request a frame from the JavaScript side, use
/// `dvui_instance.requestRender()`
pub fn refresh(_: *WebBackend) void {
    wasm.wasm_refresh();
}

pub fn setCursor(self: *WebBackend, cursor: dvui.enums.Cursor) void {
    if (cursor == self.cursor_last) return;
    defer self.cursor_last = cursor;

    const name: []const u8 = switch (cursor) {
        .arrow => "default",
        .ibeam => "text",
        .wait => "wait",
        .wait_arrow => "progress",
        .crosshair => "crosshair",
        .arrow_nw_se => "nwse-resize",
        .arrow_ne_sw => "nesw-resize",
        .arrow_w_e => "ew-resize",
        .arrow_n_s => "ns-resize",
        .arrow_all => "move",
        .bad => "not-allowed",
        .hand => "pointer",
        .hidden => "none",
    };
    wasm.wasm_cursor(name.ptr, name.len);
}

pub fn openFilePicker(id: dvui.Id, accept: ?[]const u8, multiple: bool) void {
    const accept_final = accept orelse "";
    wasm.wasm_open_file_picker(id.asU64(), accept_final.ptr, accept_final.len, multiple);
}

pub fn getFileName(id: dvui.Id, file_index: usize) ?[:0]const u8 {
    const ptr = wasm.wasm_get_file_name(id.asU64(), file_index);
    if (@intFromPtr(ptr) <= 0) return null;
    return std.mem.sliceTo(ptr, 0);
}

pub fn getFileSize(id: dvui.Id, file_index: usize) ?usize {
    const size: isize = wasm.wasm_get_file_size(id.asU64(), file_index);
    if (size <= 0) return null;
    return @intCast(size);
}

pub fn readFileData(id: dvui.Id, file_index: usize, data: [*]u8) void {
    wasm.wasm_read_file_data(id.asU64(), file_index, data);
}

pub fn getNumberOfFilesAvailable(id: dvui.Id) usize {
    return wasm.wasm_get_number_of_files_available(id.asU64());
}

/// A `std.Io.Writer` wrapper for interacting with the JavaScript console.
///
/// The drain function is infallible, meaning that using `catch unreachable`
/// on the writer functions should be safe (unless the `std.Io.Writer`
/// implementation can throw an error explicitly)
///
/// IMPORTANT: All instances of `Console` drain to the same buffer on the
/// Javascript side! To avoid you message getting clobbered, always write
/// everything in full at one time and call `flushAtLevel` immediately.
pub const Console = struct {
    writer: std.Io.Writer,

    /// The minimum recommended buffer size.
    pub const min_buffer_size: usize = 128;

    /// Assserts that `buffer.len >= Console.min_buffer_size`
    pub fn init(buffer: []u8) Console {
        std.debug.assert(buffer.len >= Console.min_buffer_size);
        return .{ .writer = .{
            .buffer = buffer,
            .vtable = &.{
                .drain = &Console.drain,
                .flush = &Console.flush,
            },
        } };
    }

    /// A simple drain function that only writes what it can into the buffer
    /// and only flushes it when the buffer is completely full. This should
    /// give optimal buffering at the cost of more vtable calls as it does
    /// not loop over all data slices in this function.
    pub fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        // If the unused slice gets filled up, we can return this value
        // as it was the total amount of bytes available to fill
        const unused_capacity = w.unusedCapacityLen();
        var unused = w.unusedCapacitySlice();
        if (unused.len == 0) {
            try Console.flush(w);
            return unused_capacity;
        }

        const slice = data[0 .. data.len - 1];
        for (slice) |buf| {
            const min_len = @min(unused.len, buf.len);
            @memcpy(unused[0..min_len], buf[0..min_len]);
            w.end += min_len;
            unused = w.unusedCapacitySlice();
            if (unused.len == 0) {
                try Console.flush(w);
                return unused_capacity;
            }
        }

        const final = data[data.len - 1];
        switch (final.len) {
            0 => {},
            1 => {
                const min_len = @min(unused.len, splat);
                @memset(unused[0..min_len], final[0]);
                w.end += min_len;
                unused = w.unusedCapacitySlice();
                if (unused.len == 0) {
                    try Console.flush(w);
                    return unused_capacity;
                }
            },
            else => for (0..splat) |_| {
                const min_len = @min(unused.len, final.len);
                @memcpy(unused[0..min_len], final[0..min_len]);
                w.end += min_len;
                unused = w.unusedCapacitySlice();
                if (unused.len == 0) {
                    try Console.flush(w);
                    return unused_capacity;
                }
            },
        }
        return unused_capacity - w.unusedCapacityLen();
    }

    pub fn flush(w: *std.Io.Writer) std.Io.Writer.Error!void {
        if (w.end == 0) return;
        wasm.wasm_console_drain(w.buffer.ptr, w.end);
        w.end = 0;
    }

    /// If `level` is `null`, the generic `console.log` will be used,
    /// otherwise the approtiare `console.LEVEL` function will be used.
    pub fn flushAtLevel(self: *Console, level: ?std.log.Level) void {
        // Drain all data to the JavaScript side.
        Console.flush(&self.writer) catch unreachable;
        // Show the console message with the appropriate log level
        wasm.wasm_console_flush(if (level) |l| switch (l) {
            .err => 9,
            .warn => 7,
            .info => 5,
            .debug => 3,
        } else 1);
    }
};

// dvui_app stuff
comptime {
    if (dvui.App.get() != null) {
        @export(&dvui_init, .{ .name = "dvui_init" });
        @export(&dvui_deinit, .{ .name = "dvui_deinit" });
        @export(&dvui_update, .{ .name = "dvui_update" });
    }
}

var wasm_log_console_buffer: [512]u8 = undefined;
pub var js_console = Console.init(&wasm_log_console_buffer);

pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (scope != .default) {
        js_console.writer.print("({s}): ", .{@tagName(scope)}) catch unreachable;
    }
    js_console.writer.print(format, args) catch unreachable;
    js_console.flushAtLevel(message_level);
}

pub const panic = std.debug.FullPanic(struct {
    fn call(msg: []const u8, ret_addr: ?usize) noreturn {
        @branchHint(.cold);
        _ = ret_addr;
        wasm.wasm_panic(msg.ptr, msg.len);
        @trap();
    }
}.call);

pub var back: WebBackend = undefined;

fn dvui_init(platform_ptr: [*]const u8, platform_len: usize) callconv(.c) i32 {
    const app = dvui.App.get() orelse return 404;
    // TODO: Allow web backend to set title of browser tab via init_opts
    // TODO: Respect min size (maybe max size?) via css on the canvas element
    // TODO: Use the icon to set the browser tab icon (if possible considering size requirements)
    const init_opts = app.config.get();

    const platform = platform_ptr[0..platform_len];
    log.debug("platform: {s}", .{platform});
    const mac = if (std.mem.indexOf(u8, platform, "Mac") != null) true else false;
    const windows = if (std.mem.indexOf(u8, platform, "Win32") != null) true else false;

    back = WebBackend.init() catch {
        return 1;
    };

    var win_opts = init_opts.window_init_options;
    if (win_opts.button_order == null) {
        win_opts.button_order = if (windows) .ok_cancel else .cancel_ok;
    }
    if (win_opts.keybinds == null) {
        win_opts.keybinds = if (mac) .mac else .windows;
    }
    win = dvui.Window.init(@src(), gpa, back.backend(), win_opts) catch {
        return 2;
    };

    win_ok = true;

    if (app.initFn) |initFn| {
        win.begin(win.frame_time_ns) catch |err| {
            log.err("dvui.Window.begin failed: {any}", .{err});
            return 3;
        };

        initFn(&win) catch |err| {
            log.err("dvui.App.initFn failed: {any}", .{err});
            return 4;
        };

        _ = win.end(.{}) catch |err| {
            log.err("dvui.Window.end failed: {any}", .{err});
            return 5;
        };
    }

    return 0;
}

fn dvui_deinit() callconv(.c) void {
    const app = dvui.App.get() orelse return;
    if (app.deinitFn) |deinitFn| deinitFn();

    win.deinit();
    back.deinit();
}

// return number of micros to wait (interrupted by events) for next frame
// return -1 to quit
fn dvui_update() callconv(.c) i32 {
    return update() catch |err| {
        // The main loop is stopping, this is our last chance to deinit stuff
        dvui_deinit();
        std.debug.panic("{any}", .{err});
    };
}

fn update() !i32 {
    const app = dvui.App.get() orelse return error.DvuiAppNotDefined;

    const nstime = win.beginWait(back.hasEvent());

    try win.begin(nstime);

    // Instead of the backend saving the events and then calling this, the web
    // backend is directly sending the events to dvui
    //try backend.addAllEvents(&win);

    const res = try app.frameFn();

    const end_micros = try win.end(.{});

    back.setCursor(win.cursorRequested());
    back.textInputRect(win.textInputRequested());

    switch (res) {
        .ok => {},
        // TODO: Should web apps be allowed to close? What happens on a close?
        .close => return -1,
    }

    const wait_event_micros = win.waitTime(end_micros);
    return @intCast(@divTrunc(wait_event_micros, 1000));
}

test {
    //std.debug.print("web backend test\n", .{});
    std.testing.refAllDecls(@This());
}
