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
var last_touch_enum: dvui.enums.Button = .none;
var touchPoints: [10]?dvui.Point = [_]?dvui.Point{null} ** 10;
var have_event = false;

cursor_last: dvui.enums.Cursor = .wait,

const EventTemp = struct {
    kind: u8,
    int1: u32,
    int2: u32,
    float1: f32,
    float2: f32,
};

pub var event_temps = std.ArrayList(EventTemp).init(gpa);

pub const wasm = if (!builtin.is_test) struct {
    pub extern "dvui" fn wasm_about_webgl2() u8;

    pub extern "dvui" fn wasm_panic(ptr: [*]const u8, len: usize) void;
    pub extern "dvui" fn wasm_log_write(ptr: [*]const u8, len: usize) void;
    pub extern "dvui" fn wasm_log_flush() void;

    pub extern "dvui" fn wasm_now() f64;
    pub extern "dvui" fn wasm_sleep(ms: u32) void;

    pub extern "dvui" fn wasm_pixel_width() f32;
    pub extern "dvui" fn wasm_pixel_height() f32;
    pub extern "dvui" fn wasm_canvas_width() f32;
    pub extern "dvui" fn wasm_canvas_height() f32;

    pub extern "dvui" fn wasm_frame_buffer() u8;
    pub extern "dvui" fn wasm_textureCreate(pixels: [*]u8, width: u32, height: u32, interp: u8) u32;
    pub extern "dvui" fn wasm_textureCreateTarget(width: u32, height: u32, interp: u8) u32;
    pub extern "dvui" fn wasm_textureRead(texture: u32, pixels_out: [*]u8, width: u32, height: u32) void;
    pub extern "dvui" fn wasm_renderTarget(u32) void;
    pub extern "dvui" fn wasm_textureDestroy(u32) void;
    pub extern "dvui" fn wasm_renderGeometry(texture: u32, index_ptr: [*]const u8, index_len: usize, vertex_ptr: [*]const u8, vertex_len: usize, sizeof_vertex: u8, offset_pos: u8, offset_col: u8, offset_uv: u8, clip: u8, x: i32, y: i32, w: i32, h: i32) void;

    pub extern "dvui" fn wasm_cursor(name: [*]const u8, name_len: usize) void;
    pub extern "dvui" fn wasm_text_input(x: f32, y: f32, w: f32, h: f32) void;
    pub extern "dvui" fn wasm_open_url(ptr: [*]const u8, len: usize) void;
    pub extern "dvui" fn wasm_download_data(name_ptr: [*]const u8, name_len: usize, data_ptr: [*]const u8, data_len: usize) void;
    pub extern "dvui" fn wasm_clipboardTextSet(ptr: [*]const u8, len: usize) void;

    // NOTE: bool in extern becomes 0 and 1 in js, which is falsy and truthy respectively
    pub extern "dvui" fn wasm_open_file_picker(id: u32, accept_ptr: [*]const u8, accept_len: usize, multiple: bool) void;
    pub extern "dvui" fn wasm_get_number_of_files_available(id: u32) usize;
    pub extern "dvui" fn wasm_get_file_name(id: u32, file_index: usize) [*:0]u8;
    pub extern "dvui" fn wasm_get_file_size(id: u32, file_index: usize) isize;
    pub extern "dvui" fn wasm_read_file_data(id: u32, file_index: usize, data: [*]u8) void;

    pub extern "dvui" fn wasm_add_noto_font() void;
} else struct { // Mock api for testing that this backend is semantically correct, cannot test behaviour
    pub fn wasm_about_webgl2() u8 {
        return undefined;
    }

    pub fn wasm_panic(_: [*]const u8, _: usize) void {}
    pub fn wasm_log_write(_: [*]const u8, _: usize) void {}
    pub fn wasm_log_flush() void {}

    pub fn wasm_now() f64 {
        return undefined;
    }
    pub fn wasm_sleep(_: u32) void {}

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
    pub fn wasm_textureCreate(_: [*]u8, _: u32, _: u32, _: u8) u32 {
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
    pub fn wasm_open_url(_: [*]const u8, _: usize) void {}
    pub fn wasm_download_data(_: [*]const u8, _: usize, _: [*]const u8, _: usize) void {}
    pub fn wasm_clipboardTextSet(_: [*]const u8, _: usize) void {}

    pub fn wasm_open_file_picker(_: u32, _: [*]const u8, _: usize, _: bool) void {}
    pub fn wasm_get_number_of_files_available(_: u32) usize {
        return undefined;
    }
    pub fn wasm_get_file_name(_: u32, _: usize) [*:0]u8 {
        return undefined;
    }
    pub fn wasm_get_file_size(_: u32, _: usize) isize {
        return undefined;
    }
    pub fn wasm_read_file_data(_: u32, _: usize, _: [*]u8) void {}

    pub fn wasm_add_noto_font() void {}
};

export fn dvui_c_alloc(size: usize) ?*anyopaque {
    const buffer = gpa.alignedAlloc(u8, 8, size + 8) catch {
        //log.debug("dvui_c_alloc {d} failed", .{size});
        return null;
    };
    std.mem.writeInt(u64, buffer[0..@sizeOf(u64)], buffer.len, builtin.cpu.arch.endian());
    //log.debug("dvui_c_alloc {*} {d}", .{ buffer.ptr + 8, size });
    return buffer.ptr + 8;
}

pub export fn dvui_c_free(ptr: ?*anyopaque) void {
    const buffer = @as([*]align(8) u8, @alignCast(@ptrCast(ptr orelse return))) - 8;
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

export fn dvui_c_memcpy(dest: [*c]u8, src: [*c]const u8, n: usize) [*c]u8 {
    @memcpy(dest[0..n], src[0..n]);
    return dest;
}

export fn dvui_c_memmove(dest: [*c]u8, src: [*c]const u8, n: usize) [*c]u8 {
    //log.debug("dvui_c_memmove dest {*} src {*} {d}", .{ dest, src, n });
    const buf = dvui.currentWindow().arena().alloc(u8, n) catch unreachable;
    @memcpy(buf, src[0..n]);
    @memcpy(dest[0..n], buf);
    return dest;
}

export fn dvui_c_memset(dest: [*c]u8, x: u8, n: usize) [*c]u8 {
    @memset(dest[0..n], x);
    return dest;
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
        win.font_bytes.put("Noto", dvui.FontBytesEntry{ .ttf_bytes = ptr[0..len], .allocator = gpa }) catch unreachable;
    }
}

export fn add_event(which: u8, int1: u32, int2: u32, float1: f32, float2: f32) void {
    if (win_ok) {
        add_event_raw(&win, which, int1, int2, float1, float2) catch |err| {
            log.err("add_event_raw returned {!}", .{err});
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
    //    const msg = std.fmt.allocPrint(gpa, "{!}", .{err}) catch "allocPrint OOM";
    //    wasm.wasm_panic(msg.ptr, msg.len);
    //};
    switch (which) {
        1 => _ = try w.addEventMouseMotion(float1, float2),
        2 => _ = try w.addEventMouseButton(buttonFromJS(int1), .press),
        3 => _ = try w.addEventMouseButton(buttonFromJS(int1), .release),
        4 => _ = try w.addEventMouseWheel(if (float1 > 0) -20 else 20, if (int1 > 0) .vertical else .horizontal),
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
            _ = try w.addEventText(str);
        },
        8 => {
            const touch: dvui.enums.Button = @enumFromInt(@intFromEnum(dvui.enums.Button.touch0) + int1);
            last_touch_enum = touch;
            _ = try w.addEventPointer(touch, .press, .{ .x = float1, .y = float2 });
            touchPoints[int1] = .{ .x = float1, .y = float2 };
        },
        9 => {
            const touch: dvui.enums.Button = @enumFromInt(@intFromEnum(dvui.enums.Button.touch0) + int1);
            last_touch_enum = touch;
            _ = try w.addEventPointer(touch, .release, .{ .x = float1, .y = float2 });
            touchPoints[int1] = null;
        },
        10 => {
            const touch: dvui.enums.Button = @enumFromInt(@intFromEnum(dvui.enums.Button.touch0) + int1);
            last_touch_enum = touch;
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
//                self.last_touch_enum = touch;
//                _ = try win.addEventPointer(touch, .press, .{ .x = e.float1, .y = e.float2 });
//                self.touchPoints[e.int1] = .{ .x = e.float1, .y = e.float2 };
//            },
//            9 => {
//                const touch: dvui.enums.Button = @enumFromInt(@intFromEnum(dvui.enums.Button.touch0) + e.int1);
//                self.last_touch_enum = touch;
//                _ = try win.addEventPointer(touch, .release, .{ .x = e.float1, .y = e.float2 });
//                self.touchPoints[e.int1] = null;
//            },
//            10 => {
//                const touch: dvui.enums.Button = @enumFromInt(@intFromEnum(dvui.enums.Button.touch0) + e.int1);
//                self.last_touch_enum = touch;
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
    _ = self;
}

pub fn backend(self: *WebBackend) dvui.Backend {
    return dvui.Backend.init(self, @This());
}

pub fn nanoTime(self: *WebBackend) i128 {
    _ = self;
    return @as(i128, @intFromFloat(wasm.wasm_now())) * 1_000_000;
}

pub fn sleep(self: *WebBackend, ns: u64) void {
    _ = self;
    wasm.wasm_sleep(@intCast(@divTrunc(ns, 1_000_000)));
}

pub fn begin(self: *WebBackend, arena_in: std.mem.Allocator) void {
    _ = self;
    arena = arena_in;
}

pub fn end(_: *WebBackend) void {
    have_event = false;
}

pub fn pixelSize(_: *WebBackend) dvui.Size {
    return dvui.Size{ .w = wasm.wasm_pixel_width(), .h = wasm.wasm_pixel_height() };
}

pub fn windowSize(_: *WebBackend) dvui.Size {
    return dvui.Size{ .w = wasm.wasm_canvas_width(), .h = wasm.wasm_canvas_height() };
}

pub fn contentScale(_: *WebBackend) f32 {
    return 1.0;
}

pub fn drawClippedTriangles(_: *WebBackend, texture: ?dvui.Texture, vtx: []const dvui.Vertex, idx: []const u16, maybe_clipr: ?dvui.Rect) void {
    var x: i32 = std.math.maxInt(i32);
    var w: i32 = std.math.maxInt(i32);
    var y: i32 = std.math.maxInt(i32);
    var h: i32 = std.math.maxInt(i32);

    if (maybe_clipr) |clipr| {
        // figure out how much we are losing by truncating x and y, need to add that back to w and h
        x = @intFromFloat(clipr.x);
        w = @intFromFloat(@ceil(clipr.w + clipr.x - @floor(clipr.x)));

        if (wasm.wasm_frame_buffer() == 0) {
            // y needs to be converted to 0 at bottom first
            const ry: f32 = wasm.wasm_pixel_height() - clipr.y - clipr.h;
            y = @intFromFloat(ry);
            h = @intFromFloat(@ceil(clipr.h + ry - @floor(ry)));
        } else {
            y = @intFromFloat(clipr.y);
            h = @intFromFloat(@ceil(clipr.h + clipr.y - @floor(clipr.y)));
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

pub fn textureCreate(self: *WebBackend, pixels: [*]u8, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) dvui.Texture {
    _ = self;

    const wasm_interp: u8 = switch (interpolation) {
        .nearest => 0,
        .linear => 1,
    };

    const id = wasm.wasm_textureCreate(pixels, width, height, wasm_interp);
    return dvui.Texture{ .ptr = @ptrFromInt(id), .width = width, .height = height };
}

pub fn textureCreateTarget(self: *WebBackend, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) !dvui.TextureTarget {
    _ = self;
    const wasm_interp: u8 = switch (interpolation) {
        .nearest => 0,
        .linear => 1,
    };

    const id = wasm.wasm_textureCreateTarget(width, height, wasm_interp);
    return dvui.TextureTarget{ .ptr = @ptrFromInt(id), .width = width, .height = height };
}

pub fn textureFromTarget(_: *WebBackend, texture: dvui.TextureTarget) dvui.Texture {
    return .{ .ptr = texture.ptr, .width = texture.width, .height = texture.height };
}

pub fn renderTarget(self: *WebBackend, texture: ?dvui.TextureTarget) void {
    _ = self;
    if (texture) |tex| {
        wasm.wasm_renderTarget(@intCast(@intFromPtr(tex.ptr)));
    } else {
        wasm.wasm_renderTarget(0);
    }
}

pub fn textureReadTarget(_: *WebBackend, texture: dvui.TextureTarget, pixels_out: [*]u8) error{TextureRead}!void {
    wasm.wasm_textureRead(@intCast(@intFromPtr(texture.ptr)), pixels_out, texture.width, texture.height);
}

pub fn textureDestroy(_: *WebBackend, texture: dvui.Texture) void {
    wasm.wasm_textureDestroy(@intCast(@intFromPtr(texture.ptr)));
}

pub fn textInputRect(_: *WebBackend, rect: ?dvui.Rect) void {
    if (rect) |r| {
        wasm.wasm_text_input(r.x, r.y, r.w, r.h);
    } else {
        wasm.wasm_text_input(0, 0, 0, 0);
    }
}

pub fn clipboardText(self: *WebBackend) error{OutOfMemory}![]const u8 {
    _ = self;
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

pub fn clipboardTextSet(self: *WebBackend, text: []const u8) !void {
    _ = self;
    wasm.wasm_clipboardTextSet(text.ptr, text.len);
    return;
}

pub fn openURL(self: *WebBackend, url: []const u8) !void {
    wasm.wasm_open_url(url.ptr, url.len);
    _ = self;
}

pub fn downloadData(name: []const u8, data: []const u8) !void {
    wasm.wasm_download_data(name.ptr, name.len, data.ptr, data.len);
}

pub fn refresh(self: *WebBackend) void {
    _ = self;
}

pub fn setCursor(self: *WebBackend, cursor: dvui.enums.Cursor) void {
    if (cursor != self.cursor_last) {
        self.cursor_last = cursor;

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
        };
        wasm.wasm_cursor(name.ptr, name.len);
    }
}

pub fn openFilePicker(id: u32, accept: ?[]const u8, multiple: bool) void {
    const accept_final = accept orelse "";
    wasm.wasm_open_file_picker(id, accept_final.ptr, accept_final.len, multiple);
}

pub fn getFileName(id: u32, file_index: usize) ?[:0]const u8 {
    const ptr = wasm.wasm_get_file_name(id, file_index);
    if (@intFromPtr(ptr) <= 0) return null;
    return std.mem.sliceTo(ptr, 0);
}

pub fn getFileSize(id: u32, file_index: usize) ?usize {
    const size: isize = wasm.wasm_get_file_size(id, file_index);
    if (size <= 0) return null;
    return @intCast(size);
}

pub fn readFileData(id: u32, file_index: usize, data: [*]u8) void {
    wasm.wasm_read_file_data(id, file_index, data);
}

pub fn getNumberOfFilesAvailable(id: u32) usize {
    return wasm.wasm_get_number_of_files_available(id);
}

// dvui_app stuff
comptime {
    if (dvui.App.get() != null) {
        @export(&dvui_init, .{ .name = "dvui_init" });
        @export(&dvui_deinit, .{ .name = "dvui_deinit" });
        @export(&dvui_update, .{ .name = "dvui_update" });
    }
}

const WriteError = error{};
const LogWriter = std.io.Writer(void, WriteError, writeLog);

fn writeLog(_: void, msg: []const u8) WriteError!usize {
    WebBackend.wasm.wasm_log_write(msg.ptr, msg.len);
    return msg.len;
}

pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = switch (message_level) {
        .err => "error",
        .warn => "warning",
        .info => "info",
        .debug => "debug",
    };
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    const msg = level_txt ++ prefix2 ++ format ++ "\n";

    (LogWriter{ .context = {} }).print(msg, args) catch return;
    WebBackend.wasm.wasm_log_flush();
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
    const init_opts = app.config.get();
    // TODO: Allow web backend to set title of browser tab via init_opts
    // TODO: Respect min size (maybe max size?) via css on the canvas element
    // TODO: Use the icon to set the browser tab icon (if possible considering size requirements)
    _ = init_opts;

    const platform = platform_ptr[0..platform_len];
    log.debug("platform: {s}", .{platform});
    const mac = if (std.mem.indexOf(u8, platform, "Mac") != null) true else false;

    back = WebBackend.init() catch {
        return 1;
    };
    win = dvui.Window.init(@src(), gpa, back.backend(), .{ .keybinds = if (mac) .mac else .windows }) catch {
        return 2;
    };

    win_ok = true;

    if (app.initFn) |initFn| initFn(&win);

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
        std.debug.panic("{!}", .{err});
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

    const wait_event_micros = win.waitTime(end_micros, null);
    return @intCast(@divTrunc(wait_event_micros, 1000));
}

test {
    //std.debug.print("web backend test\n", .{});
    std.testing.refAllDecls(@This());
}
