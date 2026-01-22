const std = @import("std");

const dvui = @import("dvui");
pub const zgl = @import("zgl");
pub const zglfw = @import("zglfw");

pub const kind: dvui.enums.Backend = .glfw_opengl3;

const log = std.log.scoped(.glfw_opengl3Backend);

vsync: bool,

gpa: std.mem.Allocator,
arena: std.heap.ArenaAllocator,

vao: zgl.VertexArray,
el_buf: zgl.Buffer,
vtx_buf: zgl.Buffer,
program: zgl.Program,
state: ?State,
fb: ?dvui.TextureTarget,
cursor: ?*zglfw.Cursor,

userKeyCallback: ?zglfw.KeyFn,
userCharCallback: ?zglfw.CharFn,
userMouseButtonCallback: ?zglfw.MouseButtonFn,
userCursorPosCallback: ?zglfw.CursorPosFn,
userFramebufferSizeCallback: ?zglfw.FramebufferSizeFn,
userScrollCallback: ?zglfw.ScrollFn,

framebuf_map: std.AutoHashMapUnmanaged(zgl.Texture, zgl.Framebuffer),

window: *zglfw.Window,

// Using vec4 for better compatability than vec3
const vertex_source =
    \\#version 330
    \\in vec2 vertexPosition;
    \\in vec2 vertexTexCoord;
    \\in vec4 vertexColor;
    \\out vec2 fragTexCoord;
    \\out vec4 fragColor;
    \\uniform mat4 mvp;
    \\void main()
    \\{
    \\    fragTexCoord = vec2(vertexTexCoord.x, vertexTexCoord.y);
    \\    fragColor = vertexColor / 255.0;
    \\    gl_Position = mvp*vec4(vertexPosition.xy, 0.0, 1.0);
    \\}
;

const frag_source =
    \\#version 330
    \\in vec2 fragTexCoord;
    \\in vec4 fragColor;
    \\out vec4 finalColor;
    \\uniform sampler2D texture0;
    \\uniform bool useTex;
    \\void main()
    \\{
    \\    if (useTex) {
    \\        finalColor = texture(texture0, fragTexCoord) * fragColor;
    \\    } else {
    \\        finalColor = fragColor;
    \\    }
    \\}
;

pub const State = struct {
    pub fn save(window: *zglfw.Window) State {
        _ = window;
        return .{};
    }

    pub fn restore(state: State) void {
        _ = state;
        return;
    }
};

pub const InitOptions = struct {
    /// allocator used for general backend bookkeeping
    gpa: std.mem.Allocator,
    /// The initial size of the application window
    size: dvui.Size,
    /// Set the minimum size of the window
    min_size: ?dvui.Size = null,
    /// Set the maximum size of the window
    max_size: ?dvui.Size = null,
    vsync: bool,
    /// The application title to display
    title: [:0]const u8,
    /// content of a PNG image (or any other format stb_image can load)
    /// tip: use @embedFile
    icon: ?[]const u8 = null,
};

/// Pass the window handle (pointer) to the glfw window
pub fn init(gpa: std.mem.Allocator, window_: *anyopaque) @This() {
    const window: *zglfw.Window = @ptrCast(window_);
    const vao = zgl.VertexArray.create();
    vao.enableVertexAttribute(0);
    vao.enableVertexAttribute(1);
    vao.enableVertexAttribute(2);
    vao.attribFormat(0, 2, .float, false, 0);
    vao.attribFormat(1, 2, .float, false, 0);
    vao.attribFormat(2, 4, .unsigned_byte, false, 0);
    vao.attribBinding(0, 0);
    vao.attribBinding(1, 1);
    vao.attribBinding(2, 2);

    const vtx_buf = zgl.Buffer.create();
    vao.vertexBuffer(0, vtx_buf, 0, 20);
    vao.vertexBuffer(1, vtx_buf, 8, 20);
    vao.vertexBuffer(2, vtx_buf, 16, 20);

    const el_buf = zgl.Buffer.create();
    vao.elementBuffer(el_buf);
    // Don't want our state changed by external code
    zgl.bindVertexArray(.invalid);

    const v_shader = zgl.Shader.create(.vertex);
    defer v_shader.delete();
    v_shader.source(1, &.{vertex_source});
    v_shader.compile();
    const f_shader = zgl.Shader.create(.fragment);
    defer f_shader.delete();
    f_shader.source(1, &.{frag_source});
    f_shader.compile();

    const program = zgl.Program.create();
    program.attach(v_shader);
    program.attach(f_shader);

    program.link();

    return .{
        .vsync = false,
        .window = window,
        .gpa = gpa,
        .arena = .init(gpa),
        .vao = vao,
        .vtx_buf = vtx_buf,
        .el_buf = el_buf,
        .program = program,
        .framebuf_map = .empty,
        .state = null,
        .fb = null,
        .cursor = null,
        .userKeyCallback = window.setKeyCallback(&glfwKeyCallback),
        .userCharCallback = window.setCharCallback(&glfwCharCallback),
        .userMouseButtonCallback = window.setMouseButtonCallback(&glfwMouseButtonCallback),
        .userCursorPosCallback = window.setCursorPosCallback(&glfwCursorPosCallback),
        .userFramebufferSizeCallback = window.setFramebufferSizeCallback(&glfwFramebufferSizeCallback),
        .userScrollCallback = window.setScrollCallback(&glfwScrollCallback),
    };
}

pub fn deinit(ctx: *@This()) void {
    ctx.vao.delete();
    ctx.program.delete();
    ctx.vtx_buf.delete();
    ctx.el_buf.delete();
    var it = ctx.framebuf_map.iterator();
    while (it.next()) |kv| {
        kv.key_ptr.delete();
        kv.value_ptr.delete();
    }
    ctx.framebuf_map.clearAndFree(ctx.gpa);
    ctx.arena.deinit();
}

pub fn begin(ctx: *@This(), _: std.mem.Allocator) !void {
    ctx.state = State.save(ctx.window);
}

pub fn end(ctx: *@This()) !void {
    if (ctx.state) |s| {
        s.restore();
    } else {
        log.err("Begin has not been called before end!", .{});
        return error.BackendError;
    }
}

pub fn pixelSize(ctx: *@This()) dvui.Size.Physical {
    const w, const h = ctx.window.getFramebufferSize();
    if (w < 0 or h < 0) log.warn("Window reports negative framebuffer size!", .{});
    return .{
        .h = @floatFromInt(@max(0, h)),
        .w = @floatFromInt(@max(0, w)),
    };
}

pub fn windowSize(ctx: *@This()) dvui.Size.Natural {
    var w: c_int, var h: c_int = .{ undefined, undefined };
    zglfw.getWindowSize(ctx.window, &w, &h);
    if (w < 0 or h < 0) log.warn("Window reports negative size!", .{});
    return .{
        .h = @floatFromInt(@max(0, h)),
        .w = @floatFromInt(@max(0, w)),
    };
}

// TODO: Investigate this a bit more, compare to dx11 backend
pub fn contentScale(ctx: *@This()) f32 {
    const scale = ctx.window.getContentScale();
    _ = scale;
    return 1;
}

pub fn drawClippedTriangles(
    ctx: *@This(),
    texture: ?dvui.Texture,
    vtx: []const dvui.Vertex,
    idx: []const u16,
    clipr_in: ?dvui.Rect.Physical,
) !void {
    if (clipr_in) |clip_rect| {
        zgl.enable(.scissor_test);
        const sz = ctx.pixelSize();
        const clip_y = if (ctx.fb == null) sz.h - clip_rect.y - clip_rect.h else clip_rect.y;
        zgl.scissor(
            @intFromFloat(clip_rect.x),
            @intFromFloat(clip_y),
            @intFromFloat(clip_rect.w),
            @intFromFloat(clip_rect.h),
        );
    }
    zgl.blendFunc(.src_alpha, .one_minus_src_alpha);
    zgl.enable(.blend);
    ctx.vao.bind();
    const aa = ctx.arena.allocator();

    const BYTES_PER_VERTEX = 20;
    const vertex_buffer = try aa.alloc(u8, BYTES_PER_VERTEX * vtx.len);
    defer aa.free(vertex_buffer);
    for (vtx, 0..) |v, index| {
        const i = index * BYTES_PER_VERTEX;
        vertex_buffer[i..][0..4].* = @bitCast(v.pos.x);
        vertex_buffer[i..][4..8].* = @bitCast(v.pos.y);
        vertex_buffer[i..][8..16].* = @bitCast(v.uv);
        vertex_buffer[i..][16..20].* = @bitCast(v.col);
    }
    ctx.vtx_buf.data(u8, vertex_buffer, .stream_draw);
    ctx.el_buf.data(u16, idx, .stream_draw);

    const usetex_loc = ctx.program.uniformLocation("useTex");
    ctx.program.uniform1ui(usetex_loc, if (texture) |_| 1 else 0);
    if (texture) |tex| {
        const txt: zgl.Texture = @enumFromInt(@intFromPtr(tex.ptr));
        txt.bindTo(0);
        zgl.activeTexture(.texture_0);
        const tex_loc = ctx.program.uniformLocation("texture0") orelse blk: {
            log.err("Couldn't find uniform location!", .{});
            break :blk null;
        };
        ctx.program.uniform1i(tex_loc, 0);
    }

    const sz: dvui.Size.Physical = if (ctx.fb) |fb_tex| .{ .h = @floatFromInt(fb_tex.height), .w = @floatFromInt(fb_tex.width) } else ctx.pixelSize();
    const sgn: f32 = if (ctx.fb) |_| -1.0 else 1.0;
    const mat = [4][4]f32{
        .{ 2 / sz.w, 0, 0, 0 },
        .{ 0, -sgn * 2 / sz.h, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ -1, sgn, 0, 1 },
    };

    const mat_loc = ctx.program.uniformLocation("mvp");
    ctx.program.uniformMatrix4(mat_loc, false, &.{mat});
    ctx.program.use();
    zgl.drawElements(.triangles, idx.len, .unsigned_short, 0);
    zgl.disable(.scissor_test);
}

pub fn textureCreate(
    _: *@This(),
    pixels: [*]const u8,
    width: u32,
    height: u32,
    interpolation: dvui.enums.TextureInterpolation,
) !dvui.Texture {
    const tex = zgl.Texture.create(.@"2d");
    tex.bind(.@"2d");
    tex.parameter(.min_filter, if (interpolation == .nearest) .nearest else .linear);
    tex.parameter(.mag_filter, if (interpolation == .nearest) .nearest else .linear);
    zgl.textureImage2D(.@"2d", 0, .rgba8, width, height, .rgba, .unsigned_int_8_8_8_8, pixels);
    return .{
        .ptr = @ptrFromInt(@intFromEnum(tex)),
        .height = height,
        .width = width,
    };
}

pub fn textureUpdate(_: *@This(), texture: dvui.Texture, pixels: [*]const u8) !void {
    const tex: zgl.Texture = @enumFromInt(@intFromPtr(texture.ptr));
    tex.subImage2D(0, 0, 0, texture.width, texture.height, .rgba, .unsigned_int_8_8_8_8, pixels);
}

pub fn textureCreateTarget(
    ctx: *@This(),
    width: u32,
    height: u32,
    interpolation: dvui.enums.TextureInterpolation,
) !dvui.TextureTarget {
    const tex = zgl.Texture.create(.@"2d");
    tex.bind(.@"2d");
    tex.parameter(.min_filter, if (interpolation == .nearest) .nearest else .linear);
    tex.parameter(.mag_filter, if (interpolation == .nearest) .nearest else .linear);
    tex.parameter(.wrap_s, .clamp_to_border);
    tex.parameter(.wrap_t, .clamp_to_border);
    zgl.textureImage2D(.@"2d", 0, .rgba8, width, height, .rgba, .unsigned_int_8_8_8_8, null);
    const framebuf = zgl.Framebuffer.create();
    framebuf.texture2D(.draw_buffer, .color0, .@"2d", tex, 0);
    ctx.framebuf_map.put(ctx.gpa, tex, framebuf) catch |err| {
        tex.delete();
        framebuf.delete();
        return err;
    };
    framebuf.bind(.draw_buffer);
    zgl.clearColor(0, 0, 0, 0);
    zgl.clear(.{ .color = true });
    zgl.bindFramebuffer(.invalid, .draw_buffer);
    return .{
        .ptr = @ptrFromInt(@intFromEnum(tex)),
        .height = height,
        .width = width,
    };
}

pub fn textureFromTarget(ctx: *@This(), texture: dvui.TextureTarget) !dvui.Texture {
    const tex: zgl.Texture = @enumFromInt(@intFromPtr(texture.ptr));
    if (ctx.framebuf_map.fetchRemove(tex)) |kv| {
        kv.value.delete();
    }
    return .{
        .ptr = texture.ptr,
        .height = texture.height,
        .width = texture.width,
    };
}

pub fn textureReadTarget(_: *@This(), texture: dvui.TextureTarget, pixels_out: [*]u8) !void {
    const tex: zgl.Texture = @enumFromInt(@intFromPtr(texture.ptr));
    tex.bind(.@"2d");
    zgl.getTexImage(.@"2d", 0, .rgba, .unsigned_int_8_8_8_8, pixels_out);
}

pub fn renderTarget(ctx: *@This(), texture: ?dvui.TextureTarget) !void {
    if (texture == null) {
        zgl.bindFramebuffer(.invalid, .draw_buffer);
        const sz = ctx.pixelSize();
        zgl.viewport(0, 0, @intFromFloat(sz.w), @intFromFloat(sz.h));
        ctx.fb = null;
        return;
    }
    const tex: zgl.Texture = @enumFromInt(@intFromPtr(texture.?.ptr));
    const fb = ctx.framebuf_map.get(tex) orelse return error.BackendError;
    fb.bind(.draw_buffer);
    zgl.viewport(0, 0, texture.?.width, texture.?.height);
    ctx.fb = texture;
}

pub fn textureDestroy(ctx: *@This(), texture: dvui.Texture) void {
    const tex: zgl.Texture = @enumFromInt(@intFromPtr(texture.ptr));
    tex.delete();
    if (ctx.framebuf_map.fetchRemove(tex)) |kv| {
        kv.value.delete();
    }
}
/// Get clipboard content (text only)
pub fn clipboardText(ctx: *@This()) ![]const u8 {
    const text = ctx.window.getClipboardString() orelse {
        log.warn("Failed get clipboard string!", .{});
        return error.BackendError;
    };
    return text[0 .. text.len - 2];
}

/// Set clipboard content (text only)
pub fn clipboardTextSet(ctx: *@This(), text: []const u8) !void {
    const textZ = try ctx.gpa.dupeZ(u8, text);
    zglfw.setClipboardString(ctx.window, textZ);
    ctx.gpa.free(textZ);
}

/// Open URL in system browser.  If using the web backend, new_window controls
/// whether to navigate the current page to the url or open in a new window/tab.
pub fn openURL(_: *@This(), _: []const u8, _: bool) !void {
    return;
}

pub fn setCursor(ctx: *@This(), cursor: dvui.enums.Cursor) void {
    // Initialize all different types of cursors at start
    // of dvui, and then simply turn different ones on.

    if (cursor == .hidden) return ctx.window.setInputMode(.cursor, .hidden) catch error.BackendError;
    ctx.window.setInputMode(.cursor, .normal) catch return error.BackendError;

    if (ctx.cursor) |cur| cur.destroy();
    const shape: zglfw.Cursor.Shape = switch (cursor) {
        .arrow => .arrow,
        .arrow_all => .resize_all,
        .arrow_n_s => .resize_ns,
        .arrow_ne_sw => .resize_nesw,
        .arrow_nw_se => .resize_nwse,
        .arrow_w_e => .resize_ew,
        .bad => .not_allowed,
        .crosshair => .crosshair,
        .hand => .hand,
        .ibeam => .ibeam,
        .wait => .arrow, //TODO: Make a more sensible choice

        .hidden => unreachable,
    };
    ctx.cursor = zglfw.createStandardCursor(shape) catch return error.BackendError;
    ctx.window.setCursor(ctx.cursor.?);
}

/// Get the preferredColorScheme if available
pub fn preferredColorScheme(_: *@This()) ?dvui.enums.ColorScheme {
    return null;
}

pub fn nanoTime(_: *@This()) i128 {
    return std.time.nanoTimestamp();
}

pub fn sleep(_: *@This(), ns: u64) void {
    std.Thread.sleep(ns);
}

/// Called by `dvui.refresh` when it is called from a background
/// thread.  Used to wake up the gui thread.  It only has effect if you
/// are using `dvui.Window.waitTime` or some other method of waiting until
/// a new event comes in.
pub fn refresh(_: *@This()) void {
    return;
}

pub fn glfwCodeToDvuiCode(key: zglfw.Key) dvui.enums.Key {
    //TODO: Consider using scancode instead
    return switch (key) {
        .a => .a,
        .b => .b,
        .c => .c,
        .d => .d,
        .e => .e,
        .f => .f,
        .g => .g,
        .h => .h,
        .i => .i,
        .j => .j,
        .k => .k,
        .l => .l,
        .m => .m,
        .n => .n,
        .o => .o,
        .p => .p,
        .q => .q,
        .r => .r,
        .s => .s,
        .t => .t,
        .u => .u,
        .v => .v,
        .w => .w,
        .x => .x,
        .y => .y,
        .z => .z,

        .zero => .zero,
        .one => .one,
        .two => .two,
        .three => .three,
        .four => .four,
        .five => .five,
        .six => .six,
        .seven => .seven,
        .eight => .eight,
        .nine => .nine,

        .F1 => .f1,
        .F2 => .f2,
        .F3 => .f3,
        .F4 => .f4,
        .F5 => .f5,
        .F6 => .f6,
        .F7 => .f7,
        .F8 => .f7,
        .F9 => .f7,
        .F10 => .f7,
        .F11 => .f7,
        .F12 => .f7,
        .F13 => .f7,
        .F14 => .f14,
        .F15 => .f15,
        .F16 => .f16,
        .F17 => .f17,
        .F18 => .f18,
        .F19 => .f19,
        .F20 => .f20,
        .F21 => .f21,
        .F22 => .f22,
        .F23 => .f23,
        .F24 => .f24,
        .F25 => .f25,

        .kp_divide => .kp_divide,
        .kp_multiply => .kp_multiply,
        .kp_subtract => .kp_subtract,
        .kp_add => .kp_add,
        .kp_0 => .kp_0,
        .kp_1 => .kp_1,
        .kp_2 => .kp_2,
        .kp_3 => .kp_3,
        .kp_4 => .kp_4,
        .kp_5 => .kp_5,
        .kp_6 => .kp_6,
        .kp_7 => .kp_7,
        .kp_8 => .kp_8,
        .kp_9 => .kp_9,
        .kp_decimal => .kp_decimal,
        .kp_equal => .kp_equal,
        .kp_enter => .kp_enter,

        .enter => .enter,
        .escape => .escape,
        .tab => .tab,
        .left_shift => .left_shift,
        .right_shift => .right_shift,
        .left_control => .left_control,
        .right_control => .right_control,
        .left_alt => .left_alt,
        .right_alt => .right_alt,
        .left_super => .left_command,
        .right_super => .right_command,
        .menu => .menu,
        .num_lock => .num_lock,
        .caps_lock => .caps_lock,
        .print_screen => .print,
        .scroll_lock => .scroll_lock,
        .pause => .pause,
        .delete => .delete,
        .home => .home,
        .end => .end,
        .page_up => .page_up,
        .page_down => .page_down,
        .insert => .insert,
        .left => .left,
        .right => .right,
        .up => .up,
        .down => .down,
        .backspace => .backspace,
        .space => .space,
        .minus => .minus,
        .equal => .equal,
        .left_bracket => .left_bracket,
        .right_bracket => .right_bracket,
        .backslash => .backslash,
        .semicolon => .semicolon,
        .apostrophe => .apostrophe,
        .comma => .comma,
        .period => .period,
        .slash => .slash,
        .grave_accent => .grave,

        else => .unknown,
    };
}

pub fn glfwKeyCallback(
    window: *zglfw.Window,
    key: zglfw.Key,
    scancode: c_int,
    action: zglfw.Action,
    mods: zglfw.Mods,
) callconv(.c) void {
    const dvui_window = dvui.currentWindow();
    const ctx: *@This() = dvui_window.backend.impl;
    const dvui_action: @FieldType(dvui.Event.Key, "action") = switch (action) {
        .press => .down,
        .release => .up,
        .repeat => .repeat,
    };
    const dvui_key = glfwCodeToDvuiCode(key);
    const dvui_mod = blk: {
        const Mod = dvui.enums.Mod;
        var mod = Mod.none;
        mod.combine(if (mods.shift) .lshift else .none);
        mod.combine(if (mods.alt) .lalt else .none);
        mod.combine(if (mods.control) .lcontrol else .none);
        mod.combine(if (mods.super) .lcommand else .none);
        break :blk mod;
    };
    if (!(dvui_window.addEventKey(.{ .action = dvui_action, .code = dvui_key, .mod = dvui_mod }) catch |err| {
        log.err("Encountered error when adding event! Err: {}", .{err});
        return;
    })) {
        if (ctx.userKeyCallback) |callback| callback(window, key, scancode, action, mods);
    }
}

pub fn glfwCharCallback(window: *zglfw.Window, codepoint: u32) callconv(.c) void {
    const dvui_window = dvui.currentWindow();
    const ctx: *@This() = dvui_window.backend.impl;
    if (!(dvui_window.addEventText(.{ .text = @as([4]u8, @bitCast(codepoint))[0..] }) catch |err| {
        log.err("Encountered error when adding event! Err: {}", .{err});
        if (ctx.userCharCallback) |callback| callback(window, codepoint);
        return;
    })) {
        if (ctx.userCharCallback) |callback| callback(window, codepoint);
    }
}

pub fn glfwCursorPosCallback(window: *zglfw.Window, xpos: f64, ypos: f64) callconv(.c) void {
    const dvui_window = dvui.currentWindow();
    const ctx: *@This() = dvui_window.backend.impl;
    const scale = ctx.window.getContentScale();

    const physical: dvui.Point.Physical = .{
        .x = @floatCast(xpos * scale[0]),
        .y = @floatCast(ypos * scale[1]),
    };
    log.info("Triggered a cursor pos event!", .{});
    if (!(dvui_window.addEventMouseMotion(.{ .pt = physical }) catch |err| {
        log.err("Encountered error when adding event! Err: {}", .{err});
        if (ctx.userCursorPosCallback) |callback| callback(window, xpos, ypos);
        return;
    })) {
        if (ctx.userCursorPosCallback) |callback| callback(window, xpos, ypos);
    }
}

pub fn glfwMouseButtonCallback(
    window: *zglfw.Window,
    button: zglfw.MouseButton,
    action: zglfw.Action,
    mods: zglfw.Mods,
) callconv(.c) void {
    const dvui_window = dvui.currentWindow();
    const ctx: *@This() = dvui_window.backend.impl;
    const dvui_button: dvui.enums.Button = switch (button) {
        .left => .left,
        .right => .right,
        .middle => .middle,
        .four => .four,
        .five => .five,
        .six => .six,
        .seven => .seven,
        .eight => .eight,
    };
    const dvui_action: dvui.Event.Mouse.Action = switch (action) {
        .press => .press,
        .release => .release,
        else => unreachable,
    };
    if (!(dvui_window.addEventMouseButton(dvui_button, dvui_action) catch |err| {
        log.err("Encountered error when adding event! Err: {}", .{err});
        if (ctx.userMouseButtonCallback) |callback| callback(window, button, action, mods);
        return;
    })) {
        if (ctx.userMouseButtonCallback) |callback| callback(window, button, action, mods);
    }
}

pub fn glfwScrollCallback(window: *zglfw.Window, xrel: f64, yrel: f64) callconv(.c) void {
    const dvui_window = dvui.currentWindow();
    const ctx: *@This() = dvui_window.backend.impl;
    const scrollx: f32 = @floatCast(-xrel * dvui.scroll_speed);
    const scrolly: f32 = @floatCast(yrel * dvui.scroll_speed);
    const consumed_x = dvui_window.addEventMouseWheel(scrollx, .horizontal) catch |err| {
        log.err("Encountered error when adding event! Err: {}", .{err});
        if (ctx.userScrollCallback) |callback| callback(window, xrel, yrel);
        return;
    };
    const consumed_y = dvui_window.addEventMouseWheel(scrolly, .vertical) catch |err| {
        log.err("Encountered error when adding event! Err: {}", .{err});
        if (ctx.userScrollCallback) |callback| callback(window, xrel, yrel);
        return;
    };

    if (!(consumed_x and consumed_y)) {
        if (ctx.userScrollCallback) |callback| callback(
            window,
            if (consumed_x) 0 else xrel,
            if (consumed_y) 0 else yrel,
        );
    }
}
pub fn glfwFramebufferSizeCallback(
    _: *zglfw.Window,
    width: c_int,
    height: c_int,
) callconv(.c) void {
    zgl.viewport(0, 0, @intCast(width), @intCast(height));
}
