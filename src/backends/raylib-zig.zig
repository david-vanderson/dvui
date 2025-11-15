const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
pub const raylib = @import("raylib");
pub const raygui = @import("raygui");
pub const zglfw = @import("zglfw");

pub const kind: dvui.enums.Backend = .raylib;

pub const RaylibBackend = @This();
pub const Context = *RaylibBackend;

const log = std.log.scoped(.RaylibBackend);

gpa: std.mem.Allocator,
we_own_window: bool = false,
shader: raylib.Shader,
VAO: u32,
arena: std.mem.Allocator = undefined,
log_events: bool = false,
pressed_keys: std.bit_set.ArrayBitSet(u32, 512) = std.bit_set.ArrayBitSet(u32, 512).initEmpty(),
pressed_modifier: dvui.enums.Mod = .none,
mouse_button_cache: [RaylibMouseButtons.len]bool = .{false} ** RaylibMouseButtons.len,
touch_position_cache: raylib.Vector2 = .{ .x = 0, .y = 0 },
dvui_consumed_events: bool = false,
cursor_last: dvui.enums.Cursor = .arrow,
frame_buffers: std.AutoArrayHashMap(u32, u32),
fb_width: ?c_int = null,
fb_height: ?c_int = null,
ak_should_initialized: bool = dvui.accesskit_enabled,
previous_time: f64 = 0,

const vertexSource =
    \\#version 330
    \\in vec3 vertexPosition;
    \\in vec2 vertexTexCoord;
    \\in vec4 vertexColor;
    \\out vec2 fragTexCoord;
    \\out vec4 fragColor;
    \\uniform mat4 mvp;
    \\void main()
    \\{
    \\    fragTexCoord = vertexTexCoord;
    \\    fragColor = vertexColor / 255.0;
    \\    gl_Position = mvp*vec4(vertexPosition, 1.0);
    \\}
;

const fragSource =
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

//==========WINDOW MANAGEMENT FUNCTIONALITY==========

//note:
//functions in this section can be ignored
//if window management is handled by the
//application

/// creates a window using raylib
pub fn createWindow(options: InitOptions) void {
    raylib.setConfigFlags(raylib.ConfigFlags{
        .window_resizable = true,
        .window_highdpi = false,
        .window_hidden = dvui.accesskit_enabled,
        .vsync_hint = options.vsync,
    });

    raylib.initWindow(@as(c_int, @intFromFloat(options.size.w)), @as(c_int, @intFromFloat(options.size.h)), options.title);

    if (options.icon) |image_bytes| {
        // C def used here because the zig binding contains IsImageValid() in the function
        const icon = raylib.cdef.LoadImageFromMemory(".png", image_bytes.ptr, @intCast(image_bytes.len));
        raylib.setWindowIcon(icon);
    }

    if (options.min_size) |min| {
        raylib.setWindowMinSize(@intFromFloat(min.w), @intFromFloat(min.h));
    }
    if (options.max_size) |max| {
        raylib.setWindowMaxSize(@intFromFloat(max.w), @intFromFloat(max.h));
    }
}

//==========DVUI MANAGEMENT FUNCTIONS==========

pub fn begin(self: *RaylibBackend, arena: std.mem.Allocator) void {
    self.arena = arena;
}

pub fn end(_: *RaylibBackend) void {}

pub fn clear(_: *RaylibBackend) void {
    // c.ClearBackground(c.BLANK);
    raylib.clearBackground(raylib.Color.blank);
}

/// initializes the raylib backend
/// options are required if dvui is the window_owner
pub fn initWindow(options: InitOptions) !RaylibBackend {
    try zglfw.init();
    createWindow(options);

    var back = init(options.gpa);
    back.we_own_window = true;
    return back;
}

pub fn init(gpa: std.mem.Allocator) RaylibBackend {
    // if (!c.IsWindowReady()) {
    if (!raylib.isWindowReady()) {
        @panic(
            \\OS Window must be created before initializing dvui raylib backend.
        );
    }

    return RaylibBackend{
        .gpa = gpa,
        .frame_buffers = std.AutoArrayHashMap(u32, u32).init(gpa),
        .shader = raylib.cdef.LoadShaderFromMemory(vertexSource, fragSource),
        .VAO = @intCast(raylib.gl.cdef.rlLoadVertexArray()),
    };
}

pub fn shouldBlockRaylibInput(self: *RaylibBackend) bool {
    return (dvui.currentWindow().dragging.state != .none or self.dvui_consumed_events);
}

pub fn deinit(self: *RaylibBackend) void {
    self.frame_buffers.deinit();
    raylib.unloadShader(self.shader);
    raylib.gl.rlUnloadVertexArray(self.VAO);

    if (self.we_own_window) {
        raylib.closeWindow();
    }
    self.* = undefined;
    zglfw.terminate();
}

pub fn accessKitShouldInitialize(self: *RaylibBackend) bool {
    return self.ak_should_initialized;
}

pub fn accessKitInitInBegin(self: *RaylibBackend) !void {
    std.debug.assert(self.ak_should_initialized);
    dvui.backend.c.ClearWindowState(dvui.backend.c.FLAG_WINDOW_HIDDEN);
    self.ak_should_initialized = false;
}

pub fn backend(self: *RaylibBackend) dvui.Backend {
    return dvui.Backend.init(self);
}

pub fn nanoTime(self: *RaylibBackend) i128 {
    _ = self;
    return std.time.nanoTimestamp();
}

pub fn sleep(_: *RaylibBackend, ns: u64) void {
    std.Thread.sleep(ns);
}

pub fn pixelSize(_: *RaylibBackend) dvui.Size.Physical {
    const w = raylib.getRenderWidth();
    const h = raylib.getRenderHeight();
    return .{ .w = @floatFromInt(w), .h = @floatFromInt(h) };
}

pub fn windowSize(_: *RaylibBackend) dvui.Size.Natural {
    const w = raylib.getScreenWidth();
    const h = raylib.getScreenHeight();
    return .{ .w = @floatFromInt(w), .h = @floatFromInt(h) };
}

pub fn contentScale(_: *RaylibBackend) f32 {
    return 1.0;
}

pub fn drawClippedTriangles(self: *RaylibBackend, texture: ?dvui.Texture, vtx: []const dvui.Vertex, idx: []const u16, clipr_in: ?dvui.Rect.Physical) !void {

    //make sure all raylib draw calls are rendered
    //before rendering dvui elements
    // c.rlDrawRenderBatchActive();
    raylib.gl.rlDrawRenderBatchActive();

    if (clipr_in) |clip_rect| {
        if (self.fb_width == null) {
            raylib.beginScissorMode(
                @intFromFloat(clip_rect.x),
                @intFromFloat(clip_rect.y),
                @intFromFloat(clip_rect.w),
                @intFromFloat(clip_rect.h),
            );
        } else {
            // need to swap y
            raylib.beginScissorMode(
                @intFromFloat(clip_rect.x),
                @intFromFloat(@as(f32, @floatFromInt(self.fb_height.?)) - clip_rect.y - clip_rect.h),
                @intFromFloat(clip_rect.w),
                @intFromFloat(clip_rect.h),
            );
        }
    }

    // our shader and textures are alpha premultiplied
    raylib.gl.rlSetBlendMode(@intFromEnum(raylib.gl.rlBlendMode.rl_blend_alpha_premultiply));

    const shader = self.shader;
    raylib.gl.rlEnableShader(shader.id);

    const slidx = raylib.gl.rlShaderLocationIndex;
    var mat: raylib.Matrix = undefined;
    mat = raylib.Matrix.ortho(0, @floatFromInt(self.fb_width orelse raylib.getRenderWidth()), @floatFromInt(self.fb_height orelse raylib.getRenderHeight()), 0, -1, 1);
    if (self.fb_width != null) {
        // We are rendering to a texture, so invert y
        // * this changes the backface culling, but we turned that off in renderTarget
        mat.m5 *= -1;
        mat.m13 *= -1;
    }
    // Some of the shader code will use C def instead to reduce to amount of unnecessary castings
    raylib.cdef.SetShaderValueMatrix(shader, shader.locs[@intFromEnum(slidx.rl_shader_loc_matrix_mvp)], mat);

    _ = raylib.gl.rlEnableVertexArray(self.VAO);

    const VBO = raylib.gl.rlLoadVertexBuffer(vtx.ptr, @intCast(vtx.len * @sizeOf(dvui.Vertex)), false);
    raylib.gl.rlEnableVertexBuffer(VBO);
    const EBO = raylib.gl.rlLoadVertexBufferElement(idx.ptr, @intCast(idx.len * @sizeOf(u16)), false);
    raylib.gl.rlEnableVertexBufferElement(EBO);

    const pos = @offsetOf(dvui.Vertex, "pos");
    raylib.gl.rlSetVertexAttribute(@intCast(shader.locs[@intFromEnum(slidx.rl_shader_loc_vertex_position)]), 2, raylib.gl.rl_float, false, @sizeOf(dvui.Vertex), pos);
    raylib.gl.rlEnableVertexAttribute(@intCast(shader.locs[@intFromEnum(slidx.rl_shader_loc_vertex_position)]));

    const col = @offsetOf(dvui.Vertex, "col");
    raylib.gl.rlSetVertexAttribute(@intCast(shader.locs[@intFromEnum(slidx.rl_shader_loc_vertex_color)]), 4, raylib.gl.rl_unsigned_byte, false, @sizeOf(dvui.Vertex), col);
    raylib.gl.rlEnableVertexAttribute(@intCast(shader.locs[@intFromEnum(slidx.rl_shader_loc_vertex_color)]));

    const uv = @offsetOf(dvui.Vertex, "uv");
    raylib.gl.rlSetVertexAttribute(@intCast(shader.locs[@intFromEnum(slidx.rl_shader_loc_vertex_texcoord01)]), 2, raylib.gl.rl_float, false, @sizeOf(dvui.Vertex), uv);
    raylib.gl.rlEnableVertexAttribute(@intCast(shader.locs[@intFromEnum(slidx.rl_shader_loc_vertex_texcoord01)]));

    const usetex_loc = raylib.getShaderLocation(shader, "useTex");

    const suni = raylib.gl.rlShaderUniformDataType;
    if (texture) |tex| {
        raylib.gl.rlActiveTextureSlot(0);
        const texid: u32 = @intCast(@intFromPtr(tex.ptr));
        raylib.gl.rlEnableTexture(texid);

        const tex_loc = raylib.getShaderLocation(shader, "texture0");
        const tex_val: c_int = 0;
        raylib.gl.rlSetUniform(tex_loc, &tex_val, @intFromEnum(suni.rl_shader_uniform_sampler2d), 1);

        const usetex_val: c_int = 1;
        raylib.gl.rlSetUniform(usetex_loc, &usetex_val, @intFromEnum(suni.rl_shader_uniform_int), 1);
    } else {
        const usetex_val: c_int = 0;
        raylib.gl.rlSetUniform(usetex_loc, &usetex_val, @intFromEnum(suni.rl_shader_uniform_int), 1);
    }

    raylib.gl.rlDrawVertexArrayElements(0, @intCast(idx.len), null);

    raylib.gl.rlUnloadVertexBuffer(VBO);

    // There is no rlUnloadVertexBufferElement - EBO is a buffer just like VBO
    raylib.gl.rlUnloadVertexBuffer(EBO);

    // reset blend mode back to default so raylib text rendering works
    raylib.gl.rlSetBlendMode(@intFromEnum(raylib.gl.rlBlendMode.rl_blend_alpha));

    if (clipr_in) |_| {
        raylib.endScissorMode();
    }
}

pub fn textureCreate(_: *RaylibBackend, pixels: [*]const u8, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) !dvui.Texture {
    const texid = raylib.gl.rlLoadTexture(pixels, @intCast(width), @intCast(height), @intFromEnum(raylib.PixelFormat.uncompressed_r8g8b8a8), 1);
    if (texid <= 0) return dvui.Backend.TextureError.TextureCreate;

    switch (interpolation) {
        .nearest => {
            raylib.gl.rlTextureParameters(texid, raylib.gl.rl_texture_min_filter, raylib.gl.rl_texture_filter_nearest);
            raylib.gl.rlTextureParameters(texid, raylib.gl.rl_texture_mag_filter, raylib.gl.rl_texture_filter_nearest);
        },
        .linear => {
            raylib.gl.rlTextureParameters(texid, raylib.gl.rl_texture_min_filter, raylib.gl.rl_texture_filter_linear);
            raylib.gl.rlTextureParameters(texid, raylib.gl.rl_texture_mag_filter, raylib.gl.rl_texture_filter_linear);
        },
    }

    raylib.gl.rlTextureParameters(texid, raylib.gl.rl_texture_wrap_s, raylib.gl.rl_texture_wrap_clamp);
    raylib.gl.rlTextureParameters(texid, raylib.gl.rl_texture_wrap_t, raylib.gl.rl_texture_wrap_clamp);

    return dvui.Texture{ .ptr = @ptrFromInt(texid), .width = width, .height = height };
}

pub fn textureCreateTarget(self: *RaylibBackend, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) !dvui.TextureTarget {
    const id = raylib.gl.rlLoadFramebuffer();
    if (id <= 0) {
        log.debug("textureCreateTarget: rlLoadFramebuffer() failed\n", .{});
        return dvui.Backend.TextureError.TextureCreate;
    }

    raylib.gl.rlEnableFramebuffer(id);
    defer raylib.gl.rlDisableFramebuffer();

    // Create color texture (default to RGBA)
    const texid = raylib.gl.rlLoadTexture(null, @intCast(width), @intCast(height), @intFromEnum(raylib.PixelFormat.uncompressed_r8g8b8a8), 1);
    if (texid <= 0) return dvui.Backend.TextureError.TextureCreate;
    switch (interpolation) {
        .nearest => {
            raylib.gl.rlTextureParameters(texid, raylib.gl.rl_texture_min_filter, raylib.gl.rl_texture_filter_nearest);
            raylib.gl.rlTextureParameters(texid, raylib.gl.rl_texture_mag_filter, raylib.gl.rl_texture_filter_nearest);
        },
        .linear => {
            raylib.gl.rlTextureParameters(texid, raylib.gl.rl_texture_min_filter, raylib.gl.rl_texture_filter_linear);
            raylib.gl.rlTextureParameters(texid, raylib.gl.rl_texture_mag_filter, raylib.gl.rl_texture_filter_linear);
        },
    }

    raylib.gl.rlTextureParameters(texid, raylib.gl.rl_texture_wrap_s, raylib.gl.rl_texture_wrap_clamp);
    raylib.gl.rlTextureParameters(texid, raylib.gl.rl_texture_wrap_t, raylib.gl.rl_texture_wrap_clamp);

    raylib.gl.rlFramebufferAttach(id, texid, @intFromEnum(raylib.gl.rlFramebufferAttachType.rl_attachment_color_channel0), @intFromEnum(raylib.gl.rlFramebufferAttachTextureType.rl_attachment_texture2d), 0);

    if (!raylib.gl.rlFramebufferComplete(id)) {
        log.debug("textureCreateTarget: rlFramebufferComplete() false\n", .{});
        return dvui.Backend.TextureError.TextureCreate;
    }

    try self.frame_buffers.put(texid, id);

    const ret = dvui.TextureTarget{ .ptr = @ptrFromInt(texid), .width = width, .height = height };

    try self.renderTarget(ret);
    raylib.clearBackground(raylib.Color.blank);
    try self.renderTarget(null);

    return ret;
}

pub fn textureFromTarget(_: *RaylibBackend, texture: dvui.TextureTarget) dvui.Texture {
    return .{ .ptr = texture.ptr, .width = texture.width, .height = texture.height };
}

/// Render future drawClippedTriangles() to the passed texture (or screen
/// if null).
pub fn renderTarget(self: *RaylibBackend, texture: ?dvui.TextureTarget) !void {
    if (texture) |tex| {
        const texid = @intFromPtr(tex.ptr);
        const target: raylib.RenderTexture2D = .{
            .id = self.frame_buffers.get(@intCast(texid)) orelse return dvui.Backend.GenericError.BackendError,
            .texture = .{
                .id = @intCast(texid),
                .width = @intCast(tex.width),
                .height = @intCast(tex.height),
                .mipmaps = 1,
                .format = raylib.PixelFormat.uncompressed_r8g8b8a8,
            },
            // Not a good idea, but since the original c implementation doesn't use it, I give undefined a try.
            .depth = undefined,
        };

        self.fb_width = target.texture.width;
        self.fb_height = target.texture.height;

        raylib.beginTextureMode(target);

        // Need this because:
        // * raylib renders to textures with 0,0 in bottom left corner
        // * to undo that we render with inverted y
        // * that changes the backface culling
        raylib.gl.rlDisableBackfaceCulling();
    } else {
        raylib.endTextureMode();
        raylib.gl.rlEnableBackfaceCulling();

        self.fb_width = null;
        self.fb_height = null;
    }
}

pub fn textureReadTarget(_: *RaylibBackend, texture: dvui.TextureTarget, pixels_out: [*]u8) !void {
    const t: raylib.Texture2D = .{
        .id = @intCast(@intFromPtr(texture.ptr)),
        .width = @intCast(texture.width),
        .height = @intCast(texture.height),
        .mipmaps = 1,
        .format = raylib.PixelFormat.uncompressed_r8g8b8a8,
    };

    const img = raylib.cdef.LoadImageFromTexture(t);
    defer raylib.unloadImage(img);
    if (raylib.isImageValid(img)) return dvui.Backend.TextureError.TextureRead;

    const imgData: [*]u8 = @ptrCast(img.data);
    for (0..@intCast(t.width * t.height * 4)) |i| {
        pixels_out[i] = imgData[i];
    }
}

pub fn textureDestroy(self: *RaylibBackend, texture: dvui.Texture) void {
    const texid = @intFromPtr(texture.ptr);
    raylib.gl.rlUnloadTexture(@intCast(texid));

    if (self.frame_buffers.fetchSwapRemove(@intCast(texid))) |kv| {
        raylib.gl.rlUnloadFramebuffer(kv.value);
    }
}

pub fn clipboardText(_: *RaylibBackend) ![]const u8 {
    return raylib.getClipboardText();
}

pub fn clipboardTextSet(self: *RaylibBackend, text: []const u8) !void {
    const c_text = try self.arena.dupeZ(u8, text);
    defer self.arena.free(c_text);
    raylib.setClipboardText(c_text);
}

pub fn openURL(self: *RaylibBackend, url: []const u8, _: bool) !void {
    const c_url = try self.arena.dupeZ(u8, url);
    defer self.arena.free(c_url);
    raylib.openURL(c_url);
}

pub fn setCursor(self: *RaylibBackend, cursor: dvui.enums.Cursor) void {
    if (cursor == self.cursor_last) return;
    defer self.cursor_last = cursor;
    const new_shown_state = if (cursor == .hidden) false else if (self.cursor_last == .hidden) true else null;
    if (new_shown_state) |new_state| {
        if (self.cursorShow(new_state) == new_state) {
            log.err("Cursor shown state was out of sync", .{});
        }
        // Return early if we are hiding
        if (new_state == false) return;
    }

    const raylib_cursor = switch (cursor) {
        .arrow => raylib.MouseCursor.arrow,
        .ibeam => raylib.MouseCursor.ibeam,
        .wait => raylib.MouseCursor.default, // raylib doesn't have this
        .wait_arrow => raylib.MouseCursor.default, // raylib doesn't have this
        .crosshair => raylib.MouseCursor.crosshair,
        .arrow_nw_se => raylib.MouseCursor.resize_nwse,
        .arrow_ne_sw => raylib.MouseCursor.resize_nesw,
        .arrow_w_e => raylib.MouseCursor.resize_ew,
        .arrow_n_s => raylib.MouseCursor.resize_ns,
        .arrow_all => raylib.MouseCursor.resize_all,
        .bad => raylib.MouseCursor.not_allowed,
        .hand => raylib.MouseCursor.pointing_hand,
        .hidden => unreachable,
    };

    raylib.setMouseCursor(raylib_cursor);
}

pub fn preferredColorScheme(_: *RaylibBackend) ?dvui.enums.ColorScheme {
    if (builtin.target.os.tag == .windows) {
        return dvui.Backend.Common.windowsGetPreferredColorScheme();
    }
    return null;
}

pub fn cursorShow(_: *RaylibBackend, value: ?bool) bool {
    const prev = !raylib.isCursorOnScreen();
    if (value) |val| {
        if (val) {
            // c.ShowCursor();
            raylib.showCursor();
        } else {
            // c.HideCursor();
            raylib.showCursor();
        }
    }
    return prev;
}

//TODO implement this function
pub fn refresh(_: *RaylibBackend) void {}

pub fn addAllEvents(self: *RaylibBackend, win: *dvui.Window) !void {
    var disable_raylib_input: bool = false;

    const wasm = (builtin.target.cpu.arch == .wasm32 or builtin.target.cpu.arch == .wasm64);
    if (!wasm and raylib.windowShouldClose()) {
        try win.addEventApp(.{ .action = .quit });
    }

    const shift = raylib.isKeyDown(raylib.KeyboardKey.left_shift) or raylib.isKeyDown(raylib.KeyboardKey.right_shift);
    const capslock = raylib.isKeyDown(raylib.KeyboardKey.caps_lock);

    //check for key releases
    var iter = self.pressed_keys.iterator(.{});
    while (iter.next()) |keycode| {
        const keyenum: raylib.KeyboardKey = @enumFromInt(keycode);
        if (raylib.isKeyUp(keyenum)) {
            self.pressed_keys.unset(keycode);

            //update pressed_modifier
            if (isKeymod(keyenum)) {
                self.pressed_modifier.unset(raylibKeymodToDvui(keyenum));
            }

            //send key release event
            const code = raylibKeyToDvui(keyenum);
            if (try win.addEventKey(.{ .code = code, .mod = self.pressed_modifier, .action = .up })) disable_raylib_input = true;

            if (self.log_events) {
                std.debug.print("raylib event key up: {}\n", .{raylibKeyToDvui(keyenum)});
            }
        } else if (raylib.isKeyPressedRepeat(keyenum)) {
            if (try win.addEventKey(.{ .code = raylibKeyToDvui(keyenum), .mod = self.pressed_modifier, .action = .repeat })) disable_raylib_input = true;
            if (self.log_events) {
                std.debug.print("raylib event key repeat: {}\n", .{raylibKeyToDvui(keyenum)});
            }
        }
    }

    //get key presses
    while (true) {
        const event_enum = raylib.getKeyPressed();
        const event = @intFromEnum(event_enum);
        if (event == 0) break;

        //update list of set keys
        self.pressed_keys.set(@intCast(event));

        //calculate code
        const code = raylibKeyToDvui(event_enum);

        //text input
        if ((self.pressed_modifier.shiftOnly() or self.pressed_modifier == .none) and event < std.math.maxInt(u8) and std.ascii.isPrint(@intCast(event))) {
            const char: u8 = @intCast(event);

            const lowercase_alpha = std.ascii.toLower(char);
            const shifted = if (shift or (capslock and std.ascii.isAlphabetic(lowercase_alpha))) shiftAscii(lowercase_alpha) else lowercase_alpha;
            const string: []const u8 = &.{shifted};
            if (self.log_events) {
                std.debug.print("raylib event text entry {s}\n", .{string});
            }
            if (try win.addEventText(.{ .text = string })) disable_raylib_input = true;
        }

        //check if keymod
        if (isKeymod(event_enum)) {
            const keymod = raylibKeymodToDvui(event_enum);
            self.pressed_modifier.combine(keymod);

            if (self.log_events) {
                std.debug.print("raylib modifier key down: .{}\n", .{code});
            }
        } else {
            //add eventKey
            if (self.log_events) {
                std.debug.print("raylib event key down: {}\n", .{code});
            }
        }
        if (try win.addEventKey(.{ .code = code, .mod = self.pressed_modifier, .action = .down })) disable_raylib_input = true;
    }

    //account for key repeat
    iter = self.pressed_keys.iterator(.{});
    while (iter.next()) |keycode| {
        if (raylib.isKeyPressed(@enumFromInt(keycode)) and
            (self.pressed_modifier.shiftOnly() or self.pressed_modifier.has(.none)) and
            keycode < std.math.maxInt(u8) and std.ascii.isPrint(@intCast(keycode)))
        {
            const char: u8 = @intCast(keycode);

            const lowercase_alpha = std.ascii.toLower(char);
            const shifted = if (shift or (capslock and std.ascii.isAlphabetic(lowercase_alpha))) shiftAscii(lowercase_alpha) else lowercase_alpha;
            const string: []const u8 = &.{shifted};
            if (self.log_events) {
                std.debug.print("raylib event text entry {s}\n", .{string});
            }
            if (try win.addEventText(.{ .text = string })) disable_raylib_input = true;
        }
    }

    const mouse_move = raylib.getMouseDelta();
    if (mouse_move.x != 0 or mouse_move.y != 0) {
        const mouse_pos = raylib.getMousePosition();

        // raylib gives us mouse coords in "window coords" which is kind of
        // like natural coords but ignores content scaling
        const scale = self.pixelSize().w / self.windowSize().w;

        if (try win.addEventMouseMotion(.{ .pt = .{ .x = mouse_pos.x * scale, .y = mouse_pos.y * scale } })) disable_raylib_input = true;
        if (self.log_events) {
            //std.debug.print("raylib event Mouse Moved\n", .{});
        }
    }

    inline for (RaylibMouseButtons, 0..) |button, i| {
        if (raylib.isMouseButtonDown(button)) {
            if (self.mouse_button_cache[i] != true) {
                if (try win.addEventMouseButton(raylibMouseButtonToDvui(button), .press)) disable_raylib_input = true;
                self.mouse_button_cache[i] = true;
                if (self.log_events) {
                    std.debug.print("raylib event Mouse Button Pressed {}\n", .{raylibMouseButtonToDvui(button)});
                }
            }
        }
        if (raylib.isMouseButtonUp(button)) {
            if (self.mouse_button_cache[i] != false) {
                if (try win.addEventMouseButton(raylibMouseButtonToDvui(button), .release)) disable_raylib_input = true;
                self.mouse_button_cache[i] = false;

                if (self.log_events) {
                    std.debug.print("raylib event Mouse Button Released {}\n", .{raylibMouseButtonToDvui(button)});
                }
            }
        }
    }

    //scroll wheel movement
    const scroll_wheel = raylib.getMouseWheelMoveV();
    if (scroll_wheel.x != 0) {
        if (try win.addEventMouseWheel(-scroll_wheel.x * dvui.scroll_speed, .horizontal)) disable_raylib_input = true;

        if (self.log_events) {
            std.debug.print("raylib event Mouse Wheel: {}\n", .{scroll_wheel});
        }
    }
    if (scroll_wheel.y != 0) {
        if (try win.addEventMouseWheel(scroll_wheel.y * dvui.scroll_speed, .vertical)) disable_raylib_input = true;

        if (self.log_events) {
            std.debug.print("raylib event Mouse Wheel: {}\n", .{scroll_wheel});
        }
    }

    //TODO fix touch impl
    //const touch = c.GetTouchPosition(0);
    //if (touch.x != self.touch_position_cache.x or touch.y != self.touch_position_cache.y) {
    //    self.touch_position_cache = touch;
    //    _ = try win.addEventTouchMotion(.touch0, touch.x, touch.y, 1, 1);

    //    if (self.log_events) {
    //        std.debug.print("raylib event Touch: {}\n", .{touch});
    //    }
    //}

    self.dvui_consumed_events = disable_raylib_input;
}

const RaylibMouseButtons = .{
    raylib.MouseButton.left,
    raylib.MouseButton.right,
    raylib.MouseButton.middle,
};
pub fn raylibMouseButtonToDvui(button: raylib.MouseButton) dvui.enums.Button {
    return switch (button) {
        raylib.MouseButton.left => .left,
        raylib.MouseButton.middle => .middle,
        raylib.MouseButton.right => .right,
        else => blk: {
            log.debug("unknown button {}\n", .{button});
            break :blk .six;
        },
    };
}

fn isKeymod(key: raylib.KeyboardKey) bool {
    return raylibKeymodToDvui(key) != .none;
}

pub fn raylibKeymodToDvui(keymod: raylib.KeyboardKey) dvui.enums.Mod {
    return switch (keymod) {
        .left_shift => .lshift,
        .right_shift => .rshift,
        .left_control => .lcontrol,
        .right_control => .rcontrol,
        .left_alt => .lalt,
        .right_alt => .ralt,
        .left_super => .lcommand,
        .right_super => .rcommand,
        else => .none,
    };
}

pub fn raylibKeyToDvui(key: raylib.KeyboardKey) dvui.enums.Key {
    return switch (@as(raylib.KeyboardKey, key)) {
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

        .f1 => .f1,
        .f2 => .f2,
        .f3 => .f3,
        .f4 => .f4,
        .f5 => .f5,
        .f6 => .f6,
        .f7 => .f7,
        .f8 => .f8,
        .f9 => .f9,
        .f10 => .f10,
        .f11 => .f11,
        .f12 => .f12,

        .kp_divide => .kp_divide,
        .kp_multiply => .kp_multiply,
        .kp_subtract => .kp_subtract,
        .kp_add => .kp_add,
        .kp_enter => .kp_enter,
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
        // c.KEY_MENU => .menu, //it appears menu and r use the same keycode ??
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
        .grave => .grave, //not sure if this is correct

        else => blk: {
            log.debug("raylibKeymodToDvui unknown key{}\n", .{key});
            break :blk .unknown;
        },
    };
}

fn shiftAscii(ascii: u8) u8 {
    return switch (ascii) {
        // Map lowercase letters to uppercase
        'a'...'z' => ascii - 32,

        // Map numbers to their corresponding shifted symbols
        '1' => '!',
        '2' => '@',
        '3' => '#',
        '4' => '$',
        '5' => '%',
        '6' => '^',
        '7' => '&',
        '8' => '*',
        '9' => '(',
        '0' => ')',

        // Map other relevant symbols to their shifted counterparts
        '`' => '~',
        '-' => '_',
        '=' => '+',
        '[' => '{',
        ']' => '}',
        '\\' => '|',
        ';' => ':',
        '\'' => '"',
        ',' => '<',
        '.' => '>',
        '/' => '?',

        // Return the original character if no shift mapping exists
        else => ascii,
    };
}

// pub fn raylibColorToDvui(color: c.Color) dvui.Color {
pub fn raylibColorToDvui(color: raylib.Color) dvui.Color {
    return dvui.Color{ .r = @intCast(color.r), .b = @intCast(color.b), .g = @intCast(color.g), .a = @intCast(color.a) };
}

// pub fn dvuiColorToRaylib(color: dvui.Color) c.Color {
pub fn dvuiColorToRaylib(color: dvui.Color) raylib.Color {
    // return c.Color{ .r = @intCast(color.r), .b = @intCast(color.b), .g = @intCast(color.g), .a = @intCast(color.a) };
    return raylib.Color{ .r = @intCast(color.r), .b = @intCast(color.b), .g = @intCast(color.g), .a = @intCast(color.a) };
}

pub fn EndDrawingWaitEventTimeout(_: *RaylibBackend, timeout_micros: u32) void {
    if (timeout_micros == std.math.maxInt(u32)) {
        // wait no timeout
        raylib.enableEventWaiting();
        raylib.endDrawing();
        raylib.disableEventWaiting();
        return;
    }

    if (timeout_micros > 0) {
        // c.EndDrawing();
        raylib.endDrawing();

        // TODO: investigate raylib with SUPPORT_CUSTOM_FRAME_CONTROL that
        // could let us do slightly better than this
        // * if an event came in before EndDrawing, then we will wait anyway

        // wait with timeout
        const timeout: f64 = @as(f64, @floatFromInt(timeout_micros)) / 1_000_000.0;
        zglfw.waitEventsTimeout(timeout);
        return;
    }

    // don't wait at all
    raylib.endDrawing();
    return;
}

// I believe this is included through raylib.h that in turn includes <stdio.h>
extern "c" fn vsnprintf(
    str: [*c]u8,
    size: isize,
    format: [*c]const u8,
    /// FIXME: This should be `c.va_list` but compilation fails because of invalid parameter for the calling convention
    args: ?*anyopaque,
) c_int;

extern "c" fn SetTraceLogCallback(callback: *anyopaque) void;

// TODO: Raylib Library doesn't support the SetTraceLogCallback, I am going to skip this
// part of the code for now until I have understood this callback and found a solution.
fn raylibLogCallback(
    msgType: c_int,
    text: [*c]const u8,
    /// FIXME: This should be `c.va_list` but compilation fails because of invalid parameter for the calling convention
    args: ?*anyopaque,
) callconv(.c) void {
    const logger = std.log.scoped(.Raylib);
    var buf: [255:0]u8 = undefined;
    const len = vsnprintf(&buf, buf.len + 1, text, args);
    const msg: [:0]const u8, const postfix = if (len < 0)
        .{ std.mem.span(text), " (PRINT ERRORED)" }
    else if (len > buf.len)
        .{ buf[0.. :0], "..." }
    else blk: {
        @branchHint(.likely);
        break :blk .{ buf[0..@intCast(len) :0], "" };
    };
    const msgTypeEnum: raylib.TraceLogLevel = @enumFromInt(msgType);
    switch (msgTypeEnum) {
        .trace, .debug => logger.debug("{s}{s}", .{ msg, postfix }),
        .info => logger.info("{s}{s}", .{ msg, postfix }),
        .warning => logger.warn("{s}{s}", .{ msg, postfix }),
        .err, .fatal => logger.err("{s}{s}", .{ msg, postfix }),
        else => logger.debug("{s}{s}", .{ msg, postfix }),
    }
}

/// This set enables the internal logging of raylib based on the level of std.log
/// (and the `.Raylib` scope, falling back to the level of `.RaylibBackend`)
pub fn enableRaylibLogging() void {

    // FIXME: @ptrCast here is needed because of `c.va_list` error, see `raylibLogCallback`
    SetTraceLogCallback(@constCast(&raylibLogCallback));
    const level = for (std.options.log_scope_levels) |scope_level| {
        if (scope_level.scope == .Raylib) break switch (scope_level.level) {
            // .debug => c.LOG_DEBUG,
            // .info => c.LOG_INFO,
            // .warn => c.LOG_WARNING,
            // .wee => c.LOG_ERROR,
            .debug => raylib.TraceLogLevel.debug,
            .info => raylib.TraceLogLevel.info,
            .warn => raylib.TraceLogLevel.warning,
            .wee => raylib.TraceLogLevel.err,
        };
    } else if (std.log.logEnabled(.debug, .RaylibBackend))
        // c.LOG_DEBUG
        raylib.TraceLogLevel.debug
    else if (std.log.logEnabled(.info, .RaylibBackend))
        // c.LOG_INFO
        raylib.TraceLogLevel.info
    else if (std.log.logEnabled(.warn, .RaylibBackend))
        // c.LOG_WARNING
        raylib.TraceLogLevel.warning
    else
        // c.LOG_ERROR;
        raylib.TraceLogLevel.err;

    // c.SetTraceLogLevel(level);
    raylib.setTraceLogLevel(level);
}

pub fn main() !void {
    const app = dvui.App.get() orelse return error.DvuiAppNotDefined;
    enableRaylibLogging();

    if (builtin.os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
        dvui.Backend.Common.windowsAttachConsole() catch {};
    }

    var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_instance.allocator();
    defer _ = gpa_instance.deinit();

    const init_opts = app.config.get();

    // init Raylib backend (creates OS window)
    // initWindow() means the backend calls CloseWindow for you in deinit()
    var b = try RaylibBackend.initWindow(.{
        .gpa = gpa,
        .size = init_opts.size,
        .min_size = init_opts.min_size,
        .max_size = init_opts.max_size,
        .vsync = init_opts.vsync,
        .title = init_opts.title,
        .icon = init_opts.icon,
    });
    defer b.deinit();
    b.log_events = true;

    // init dvui Window (maps onto a single OS window)
    var win = try dvui.Window.init(@src(), gpa, b.backend(), init_opts.window_init_options);
    defer win.deinit();

    if (app.initFn) |initFn| {
        try win.begin(win.frame_time_ns);
        try initFn(&win);
        _ = try win.end(.{});
    }
    defer if (app.deinitFn) |deinitFn| deinitFn();

    main_loop: while (true) {
        // c.BeginDrawing();
        raylib.beginDrawing();

        // beginWait coordinates with waitTime below to run frames only when needed
        //
        // Raylib does not directly support waiting with event interruption.
        // We assume raylib is using glfw, but glfwWaitEventsTimeout doesn't
        // tell you if it was interrupted or not. So always pass true.
        const nstime = win.beginWait(true);

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(nstime);

        // send all events to dvui for processing
        try b.addAllEvents(&win);

        // if dvui widgets might not cover the whole window, then need to clear
        // the previous frame's render
        b.clear();

        var res = try app.frameFn();

        // check for unhandled quit/close
        for (dvui.events()) |*e| {
            if (e.handled) continue;
            // assuming we only have a single window
            if (e.evt == .window and e.evt.window.action == .close) res = .close;
            if (e.evt == .app and e.evt.app.action == .quit) res = .close;
        }

        // marks end of dvui frame, don't call dvui functions after this
        // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
        const end_micros = try win.end(.{});

        // cursor management
        b.setCursor(win.cursorRequested());

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = win.waitTime(end_micros);
        b.EndDrawingWaitEventTimeout(wait_event_micros);

        if (res != .ok) break :main_loop;
    }
}

test {
    //std.debug.print("raylib backend test\n", .{});
    std.testing.refAllDecls(@This());
}
