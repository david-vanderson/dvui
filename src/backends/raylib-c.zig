const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");

pub const c = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    @cInclude("rlgl.h");
    @cInclude("raygui.h");

    @cInclude("glfw3.h");
});

pub const kind: dvui.enums.Backend = .raylib;

pub const RaylibBackend = @This();
pub const Context = *RaylibBackend;

const log = std.log.scoped(.RaylibBackend);

gpa: std.mem.Allocator,
we_own_window: bool = false,
shader: c.Shader,
VAO: u32,
arena: std.mem.Allocator = undefined,
log_events: bool = false,
pressed_keys: std.bit_set.ArrayBitSet(u32, 512) = std.bit_set.ArrayBitSet(u32, 512).initEmpty(),
pressed_modifier: dvui.enums.Mod = .none,
mouse_button_cache: [RaylibMouseButtons.len]bool = .{false} ** RaylibMouseButtons.len,
touch_position_cache: c.Vector2 = .{ .x = 0, .y = 0 },
dvui_consumed_events: bool = false,
cursor_last: dvui.enums.Cursor = .arrow,
frame_buffers: std.AutoArrayHashMap(u32, u32),
fb_width: ?c_int = null,
fb_height: ?c_int = null,
ak_should_initialized: bool = dvui.accesskit_enabled,

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
    c.SetConfigFlags(c.FLAG_WINDOW_RESIZABLE);
    c.SetConfigFlags(c.FLAG_WINDOW_HIGHDPI);
    if (dvui.accesskit_enabled) {
        c.SetConfigFlags(c.FLAG_WINDOW_HIDDEN);
    }
    if (options.vsync) {
        c.SetConfigFlags(c.FLAG_VSYNC_HINT);
    }

    c.InitWindow(@as(c_int, @intFromFloat(options.size.w)), @as(c_int, @intFromFloat(options.size.h)), options.title);

    if (options.icon) |image_bytes| {
        const icon = c.LoadImageFromMemory(".png", image_bytes.ptr, @intCast(image_bytes.len));
        c.SetWindowIcon(icon);
    }

    if (options.min_size) |min| {
        c.SetWindowMinSize(@intFromFloat(min.w), @intFromFloat(min.h));
    }
    if (options.max_size) |max| {
        c.SetWindowMaxSize(@intFromFloat(max.w), @intFromFloat(max.h));
    }
}

//==========DVUI MANAGEMENT FUNCTIONS==========

pub fn begin(self: *RaylibBackend, arena: std.mem.Allocator) void {
    self.arena = arena;
}

pub fn end(_: *RaylibBackend) void {}

pub fn clear(_: *RaylibBackend) void {
    c.ClearBackground(c.BLANK);
}

/// initializes the raylib backend
/// options are required if dvui is the window_owner
pub fn initWindow(options: InitOptions) !RaylibBackend {
    createWindow(options);

    var back = init(options.gpa);
    back.we_own_window = true;
    return back;
}

pub fn init(gpa: std.mem.Allocator) RaylibBackend {
    if (!c.IsWindowReady()) {
        @panic(
            \\OS Window must be created before initializing dvui raylib backend.
        );
    }

    return RaylibBackend{
        .gpa = gpa,
        .frame_buffers = std.AutoArrayHashMap(u32, u32).init(gpa),
        .shader = c.LoadShaderFromMemory(vertexSource, fragSource),
        .VAO = @intCast(c.rlLoadVertexArray()),
    };
}

pub fn shouldBlockRaylibInput(self: *RaylibBackend) bool {
    return (dvui.currentWindow().dragging.state != .none or self.dvui_consumed_events);
}

pub fn deinit(self: *RaylibBackend) void {
    self.frame_buffers.deinit();
    c.UnloadShader(self.shader);
    c.rlUnloadVertexArray(@intCast(self.VAO));

    if (self.we_own_window) {
        c.CloseWindow();
    }
    self.* = undefined;
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
    const w = c.GetRenderWidth();
    const h = c.GetRenderHeight();
    return .{ .w = @floatFromInt(w), .h = @floatFromInt(h) };
}

pub fn windowSize(_: *RaylibBackend) dvui.Size.Natural {
    const w = c.GetScreenWidth();
    const h = c.GetScreenHeight();
    return .{ .w = @floatFromInt(w), .h = @floatFromInt(h) };
}

pub fn contentScale(_: *RaylibBackend) f32 {
    return 1.0;
}

pub fn drawClippedTriangles(self: *RaylibBackend, texture: ?dvui.Texture, vtx: []const dvui.Vertex, idx: []const u16, clipr_in: ?dvui.Rect.Physical) !void {

    //make sure all raylib draw calls are rendered
    //before rendering dvui elements
    c.rlDrawRenderBatchActive();

    if (clipr_in) |clip_rect| {
        if (self.fb_width == null) {
            c.BeginScissorMode(
                @intFromFloat(clip_rect.x),
                @intFromFloat(clip_rect.y),
                @intFromFloat(clip_rect.w),
                @intFromFloat(clip_rect.h),
            );
        } else {
            // need to swap y
            c.BeginScissorMode(
                @intFromFloat(clip_rect.x),
                @intFromFloat(@as(f32, @floatFromInt(self.fb_height.?)) - clip_rect.y - clip_rect.h),
                @intFromFloat(clip_rect.w),
                @intFromFloat(clip_rect.h),
            );
        }
    }

    // our shader and textures are alpha premultiplied
    c.rlSetBlendMode(c.RL_BLEND_ALPHA_PREMULTIPLY);

    const shader = self.shader;
    c.rlEnableShader(shader.id);

    var mat: c.Matrix = undefined;
    mat = c.MatrixOrtho(0, @floatFromInt(self.fb_width orelse c.GetRenderWidth()), @floatFromInt(self.fb_height orelse c.GetRenderHeight()), 0, -1, 1);
    if (self.fb_width != null) {
        // We are rendering to a texture, so invert y
        // * this changes the backface culling, but we turned that off in renderTarget
        mat.m5 *= -1;
        mat.m13 *= -1;
    }
    c.SetShaderValueMatrix(shader, @intCast(shader.locs[c.RL_SHADER_LOC_MATRIX_MVP]), mat);

    _ = c.rlEnableVertexArray(@intCast(self.VAO));

    const VBO = c.rlLoadVertexBuffer(vtx.ptr, @intCast(vtx.len * @sizeOf(dvui.Vertex)), false);
    c.rlEnableVertexBuffer(VBO);
    const EBO = c.rlLoadVertexBufferElement(idx.ptr, @intCast(idx.len * @sizeOf(u16)), false);
    c.rlEnableVertexBufferElement(EBO);

    const pos = @offsetOf(dvui.Vertex, "pos");
    c.rlSetVertexAttribute(@intCast(shader.locs[c.RL_SHADER_LOC_VERTEX_POSITION]), 2, c.RL_FLOAT, false, @sizeOf(dvui.Vertex), pos);
    c.rlEnableVertexAttribute(@intCast(shader.locs[c.RL_SHADER_LOC_VERTEX_POSITION]));

    const col = @offsetOf(dvui.Vertex, "col");
    c.rlSetVertexAttribute(@intCast(shader.locs[c.RL_SHADER_LOC_VERTEX_COLOR]), 4, c.RL_UNSIGNED_BYTE, false, @sizeOf(dvui.Vertex), col);
    c.rlEnableVertexAttribute(@intCast(shader.locs[c.RL_SHADER_LOC_VERTEX_COLOR]));

    const uv = @offsetOf(dvui.Vertex, "uv");
    c.rlSetVertexAttribute(@intCast(shader.locs[c.RL_SHADER_LOC_VERTEX_TEXCOORD01]), 2, c.RL_FLOAT, false, @sizeOf(dvui.Vertex), uv);
    c.rlEnableVertexAttribute(@intCast(shader.locs[c.RL_SHADER_LOC_VERTEX_TEXCOORD01]));

    const usetex_loc = c.GetShaderLocation(shader, "useTex");

    if (texture) |tex| {
        c.rlActiveTextureSlot(0);
        const texid = @intFromPtr(tex.ptr);
        c.rlEnableTexture(@intCast(texid));

        const tex_loc = c.GetShaderLocation(shader, "texture0");
        const tex_val: c_int = 0;
        c.rlSetUniform(tex_loc, &tex_val, c.RL_SHADER_UNIFORM_SAMPLER2D, 1);

        const usetex_val: c_int = 1;
        c.rlSetUniform(usetex_loc, &usetex_val, c.RL_SHADER_UNIFORM_INT, 1);
    } else {
        const usetex_val: c_int = 0;
        c.rlSetUniform(usetex_loc, &usetex_val, c.RL_SHADER_UNIFORM_INT, 1);
    }

    c.rlDrawVertexArrayElements(0, @intCast(idx.len), null);

    c.rlUnloadVertexBuffer(VBO);

    // There is no rlUnloadVertexBufferElement - EBO is a buffer just like VBO
    c.rlUnloadVertexBuffer(EBO);

    // reset blend mode back to default so raylib text rendering works
    c.rlSetBlendMode(c.RL_BLEND_ALPHA);

    if (clipr_in) |_| {
        c.EndScissorMode();
    }
}

pub fn textureCreate(_: *RaylibBackend, pixels: [*]const u8, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) !dvui.Texture {
    const texid = c.rlLoadTexture(pixels, @intCast(width), @intCast(height), c.PIXELFORMAT_UNCOMPRESSED_R8G8B8A8, 1);
    if (texid <= 0) return dvui.Backend.TextureError.TextureCreate;

    switch (interpolation) {
        .nearest => {
            c.rlTextureParameters(texid, c.RL_TEXTURE_MIN_FILTER, c.RL_TEXTURE_FILTER_NEAREST);
            c.rlTextureParameters(texid, c.RL_TEXTURE_MAG_FILTER, c.RL_TEXTURE_FILTER_NEAREST);
        },
        .linear => {
            c.rlTextureParameters(texid, c.RL_TEXTURE_MIN_FILTER, c.RL_TEXTURE_FILTER_LINEAR);
            c.rlTextureParameters(texid, c.RL_TEXTURE_MAG_FILTER, c.RL_TEXTURE_FILTER_LINEAR);
        },
    }

    c.rlTextureParameters(texid, c.RL_TEXTURE_WRAP_S, c.RL_TEXTURE_WRAP_CLAMP);
    c.rlTextureParameters(texid, c.RL_TEXTURE_WRAP_T, c.RL_TEXTURE_WRAP_CLAMP);

    return dvui.Texture{ .ptr = @ptrFromInt(texid), .width = width, .height = height };
}

pub fn textureCreateTarget(self: *RaylibBackend, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) !dvui.TextureTarget {
    const id = c.rlLoadFramebuffer(); // Load an empty framebuffer
    if (id <= 0) {
        log.debug("textureCreateTarget: rlLoadFramebuffer() failed\n", .{});
        return dvui.Backend.TextureError.TextureCreate;
    }

    c.rlEnableFramebuffer(id);
    defer c.rlDisableFramebuffer();

    // Create color texture (default to RGBA)
    const texid = c.rlLoadTexture(null, @intCast(width), @intCast(height), c.PIXELFORMAT_UNCOMPRESSED_R8G8B8A8, 1);
    if (texid <= 0) return dvui.Backend.TextureError.TextureCreate;
    switch (interpolation) {
        .nearest => {
            c.rlTextureParameters(texid, c.RL_TEXTURE_MIN_FILTER, c.RL_TEXTURE_FILTER_NEAREST);
            c.rlTextureParameters(texid, c.RL_TEXTURE_MAG_FILTER, c.RL_TEXTURE_FILTER_NEAREST);
        },
        .linear => {
            c.rlTextureParameters(texid, c.RL_TEXTURE_MIN_FILTER, c.RL_TEXTURE_FILTER_LINEAR);
            c.rlTextureParameters(texid, c.RL_TEXTURE_MAG_FILTER, c.RL_TEXTURE_FILTER_LINEAR);
        },
    }

    c.rlTextureParameters(texid, c.RL_TEXTURE_WRAP_S, c.RL_TEXTURE_WRAP_CLAMP);
    c.rlTextureParameters(texid, c.RL_TEXTURE_WRAP_T, c.RL_TEXTURE_WRAP_CLAMP);

    c.rlFramebufferAttach(id, texid, c.RL_ATTACHMENT_COLOR_CHANNEL0, c.RL_ATTACHMENT_TEXTURE2D, 0);

    // Check if fbo is complete with attachments (valid)
    if (!c.rlFramebufferComplete(id)) {
        log.debug("textureCreateTarget: rlFramebufferComplete() false\n", .{});
        return dvui.Backend.TextureError.TextureCreate;
    }

    try self.frame_buffers.put(texid, id);

    const ret = dvui.TextureTarget{ .ptr = @ptrFromInt(texid), .width = width, .height = height };

    try self.renderTarget(ret);
    c.ClearBackground(c.BLANK);
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
        const target: c.RenderTexture2D = .{
            .id = self.frame_buffers.get(@intCast(texid)) orelse return dvui.Backend.GenericError.BackendError,
            .texture = .{
                .id = @intCast(texid),
                .width = @intCast(tex.width),
                .height = @intCast(tex.height),
            },
        };
        self.fb_width = target.texture.width;
        self.fb_height = target.texture.height;

        c.BeginTextureMode(target);

        // Need this because:
        // * raylib renders to textures with 0,0 in bottom left corner
        // * to undo that we render with inverted y
        // * that changes the backface culling
        c.rlDisableBackfaceCulling();
    } else {
        c.EndTextureMode();
        c.rlEnableBackfaceCulling();

        self.fb_width = null;
        self.fb_height = null;
    }
}

pub fn textureReadTarget(_: *RaylibBackend, texture: dvui.TextureTarget, pixels_out: [*]u8) !void {
    const t: c.Texture2D = .{
        .id = @intCast(@intFromPtr(texture.ptr)),
        .width = @intCast(texture.width),
        .height = @intCast(texture.height),
        .mipmaps = 1,
        .format = c.PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
    };

    const img = c.LoadImageFromTexture(t);
    defer c.UnloadImage(img);
    if (c.IsImageValid(img)) return dvui.Backend.TextureError.TextureRead;

    const imgData: [*]u8 = @ptrCast(img.data.?);
    for (0..@intCast(t.width * t.height * 4)) |i| {
        pixels_out[i] = imgData[i];
    }
}

pub fn textureDestroy(self: *RaylibBackend, texture: dvui.Texture) void {
    const texid = @intFromPtr(texture.ptr);
    c.rlUnloadTexture(@intCast(texid));

    if (self.frame_buffers.fetchSwapRemove(@intCast(texid))) |kv| {
        c.rlUnloadFramebuffer(kv.value);
    }
}

pub fn clipboardText(_: *RaylibBackend) ![]const u8 {
    return std.mem.span(c.GetClipboardText());
}

pub fn clipboardTextSet(self: *RaylibBackend, text: []const u8) !void {
    const c_text = try self.arena.dupeZ(u8, text);
    defer self.arena.free(c_text);
    c.SetClipboardText(c_text.ptr);
}

pub fn openURL(self: *RaylibBackend, url: []const u8, _: bool) !void {
    const c_url = try self.arena.dupeZ(u8, url);
    defer self.arena.free(c_url);
    c.OpenURL(c_url.ptr);
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
        .arrow => c.MOUSE_CURSOR_ARROW,
        .ibeam => c.MOUSE_CURSOR_IBEAM,
        .wait => c.MOUSE_CURSOR_DEFAULT, // raylib doesn't have this
        .wait_arrow => c.MOUSE_CURSOR_DEFAULT, // raylib doesn't have this
        .crosshair => c.MOUSE_CURSOR_CROSSHAIR,
        .arrow_nw_se => c.MOUSE_CURSOR_RESIZE_NWSE,
        .arrow_ne_sw => c.MOUSE_CURSOR_RESIZE_NESW,
        .arrow_w_e => c.MOUSE_CURSOR_RESIZE_EW,
        .arrow_n_s => c.MOUSE_CURSOR_RESIZE_NS,
        .arrow_all => c.MOUSE_CURSOR_RESIZE_ALL,
        .bad => c.MOUSE_CURSOR_NOT_ALLOWED,
        .hand => c.MOUSE_CURSOR_POINTING_HAND,
        .hidden => unreachable,
    };

    c.SetMouseCursor(raylib_cursor);
}

pub fn preferredColorScheme(_: *RaylibBackend) ?dvui.enums.ColorScheme {
    if (builtin.target.os.tag == .windows) {
        return dvui.Backend.Common.windowsGetPreferredColorScheme();
    }
    return null;
}

pub fn cursorShow(_: *RaylibBackend, value: ?bool) bool {
    const prev = !c.IsCursorHidden();
    if (value) |val| {
        if (val) {
            c.ShowCursor();
        } else {
            c.HideCursor();
        }
    }
    return prev;
}

//TODO implement this function
pub fn refresh(_: *RaylibBackend) void {}

pub fn addAllEvents(self: *RaylibBackend, win: *dvui.Window) !void {
    var disable_raylib_input: bool = false;

    const wasm = (builtin.target.cpu.arch == .wasm32 or builtin.target.cpu.arch == .wasm64);
    if (!wasm and c.WindowShouldClose()) {
        try win.addEventApp(.{ .action = .quit });
    }

    const shift = c.IsKeyDown(c.KEY_LEFT_SHIFT) or c.IsKeyDown(c.KEY_RIGHT_SHIFT);
    const capslock = c.IsKeyDown(c.KEY_CAPS_LOCK);
    //check for key releases
    var iter = self.pressed_keys.iterator(.{});
    while (iter.next()) |keycode| {
        if (c.IsKeyUp(@intCast(keycode))) {
            self.pressed_keys.unset(keycode);

            //update pressed_modifier
            if (isKeymod(@intCast(keycode))) {
                self.pressed_modifier.unset(raylibKeymodToDvui(@intCast(keycode)));
            }

            //send key release event
            const code = raylibKeyToDvui(@intCast(keycode));
            if (try win.addEventKey(.{ .code = code, .mod = self.pressed_modifier, .action = .up })) disable_raylib_input = true;

            if (self.log_events) {
                std.debug.print("raylib event key up: {}\n", .{raylibKeyToDvui(@intCast(keycode))});
            }
        } else if (c.IsKeyPressedRepeat(@intCast(keycode))) {
            if (try win.addEventKey(.{ .code = raylibKeyToDvui(@intCast(keycode)), .mod = self.pressed_modifier, .action = .repeat })) disable_raylib_input = true;
            if (self.log_events) {
                std.debug.print("raylib event key repeat: {}\n", .{raylibKeyToDvui(@intCast(keycode))});
            }
        }
    }

    //get key presses
    while (true) {
        const event = c.GetKeyPressed();
        if (event == 0) break;

        //update list of set keys
        self.pressed_keys.set(@intCast(event));

        //calculate code
        const code = raylibKeyToDvui(event);

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
        if (isKeymod(event)) {
            const keymod = raylibKeymodToDvui(event);
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
        if (c.IsKeyPressedRepeat(@intCast(keycode)) and
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

    const mouse_move = c.GetMouseDelta();
    if (mouse_move.x != 0 or mouse_move.y != 0) {
        const mouse_pos = c.GetMousePosition();

        // raylib gives us mouse coords in "window coords" which is kind of
        // like natural coords but ignores content scaling
        const scale = self.pixelSize().w / self.windowSize().w;

        if (try win.addEventMouseMotion(.{ .pt = .{ .x = mouse_pos.x * scale, .y = mouse_pos.y * scale } })) disable_raylib_input = true;
        if (self.log_events) {
            //std.debug.print("raylib event Mouse Moved\n", .{});
        }
    }

    inline for (RaylibMouseButtons, 0..) |button, i| {
        if (c.IsMouseButtonDown(button)) {
            if (self.mouse_button_cache[i] != true) {
                if (try win.addEventMouseButton(raylibMouseButtonToDvui(button), .press)) disable_raylib_input = true;
                self.mouse_button_cache[i] = true;
                if (self.log_events) {
                    std.debug.print("raylib event Mouse Button Pressed {}\n", .{raylibMouseButtonToDvui(button)});
                }
            }
        }
        if (c.IsMouseButtonUp(button)) {
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
    const scroll_wheel = c.GetMouseWheelMoveV();
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
    c.MOUSE_BUTTON_LEFT,
    c.MOUSE_BUTTON_RIGHT,
    c.MOUSE_BUTTON_MIDDLE,
};
pub fn raylibMouseButtonToDvui(button: c_int) dvui.enums.Button {
    return switch (button) {
        c.MOUSE_BUTTON_LEFT => .left,
        c.MOUSE_BUTTON_MIDDLE => .middle,
        c.MOUSE_BUTTON_RIGHT => .right,
        else => blk: {
            log.debug("unknown button {}\n", .{button});
            break :blk .six;
        },
    };
}

fn isKeymod(key: c_int) bool {
    return raylibKeymodToDvui(key) != .none;
}

pub fn raylibKeymodToDvui(keymod: c_int) dvui.enums.Mod {
    return switch (keymod) {
        c.KEY_LEFT_SHIFT => .lshift,
        c.KEY_RIGHT_SHIFT => .rshift,
        c.KEY_LEFT_CONTROL => .lcontrol,
        c.KEY_RIGHT_CONTROL => .rcontrol,
        c.KEY_LEFT_ALT => .lalt,
        c.KEY_RIGHT_ALT => .ralt,
        c.KEY_LEFT_SUPER => .lcommand,
        c.KEY_RIGHT_SUPER => .rcommand,
        else => .none,
    };
}

pub fn raylibKeyToDvui(key: c_int) dvui.enums.Key {
    return switch (key) {
        c.KEY_A => .a,
        c.KEY_B => .b,
        c.KEY_C => .c,
        c.KEY_D => .d,
        c.KEY_E => .e,
        c.KEY_F => .f,
        c.KEY_G => .g,
        c.KEY_H => .h,
        c.KEY_I => .i,
        c.KEY_J => .j,
        c.KEY_K => .k,
        c.KEY_L => .l,
        c.KEY_M => .m,
        c.KEY_N => .n,
        c.KEY_O => .o,
        c.KEY_P => .p,
        c.KEY_Q => .q,
        c.KEY_R => .r,
        c.KEY_S => .s,
        c.KEY_T => .t,
        c.KEY_U => .u,
        c.KEY_V => .v,
        c.KEY_W => .w,
        c.KEY_X => .x,
        c.KEY_Y => .y,
        c.KEY_Z => .z,

        c.KEY_ZERO => .zero,
        c.KEY_ONE => .one,
        c.KEY_TWO => .two,
        c.KEY_THREE => .three,
        c.KEY_FOUR => .four,
        c.KEY_FIVE => .five,
        c.KEY_SIX => .six,
        c.KEY_SEVEN => .seven,
        c.KEY_EIGHT => .eight,
        c.KEY_NINE => .nine,

        c.KEY_F1 => .f1,
        c.KEY_F2 => .f2,
        c.KEY_F3 => .f3,
        c.KEY_F4 => .f4,
        c.KEY_F5 => .f5,
        c.KEY_F6 => .f6,
        c.KEY_F7 => .f7,
        c.KEY_F8 => .f8,
        c.KEY_F9 => .f9,
        c.KEY_F10 => .f10,
        c.KEY_F11 => .f11,
        c.KEY_F12 => .f12,

        c.KEY_KP_DIVIDE => .kp_divide,
        c.KEY_KP_MULTIPLY => .kp_multiply,
        c.KEY_KP_SUBTRACT => .kp_subtract,
        c.KEY_KP_ADD => .kp_add,
        c.KEY_KP_ENTER => .kp_enter,
        c.KEY_KP_0 => .kp_0,
        c.KEY_KP_1 => .kp_1,
        c.KEY_KP_2 => .kp_2,
        c.KEY_KP_3 => .kp_3,
        c.KEY_KP_4 => .kp_4,
        c.KEY_KP_5 => .kp_5,
        c.KEY_KP_6 => .kp_6,
        c.KEY_KP_7 => .kp_7,
        c.KEY_KP_8 => .kp_8,
        c.KEY_KP_9 => .kp_9,
        c.KEY_KP_DECIMAL => .kp_decimal,

        c.KEY_ENTER => .enter,
        c.KEY_ESCAPE => .escape,
        c.KEY_TAB => .tab,
        c.KEY_LEFT_SHIFT => .left_shift,
        c.KEY_RIGHT_SHIFT => .right_shift,
        c.KEY_LEFT_CONTROL => .left_control,
        c.KEY_RIGHT_CONTROL => .right_control,
        c.KEY_LEFT_ALT => .left_alt,
        c.KEY_RIGHT_ALT => .right_alt,
        c.KEY_LEFT_SUPER => .left_command,
        c.KEY_RIGHT_SUPER => .right_command,
        // c.KEY_MENU => .menu, //it appears menu and r use the same keycode ??
        c.KEY_NUM_LOCK => .num_lock,
        c.KEY_CAPS_LOCK => .caps_lock,
        c.KEY_PRINT_SCREEN => .print,
        c.KEY_SCROLL_LOCK => .scroll_lock,
        c.KEY_PAUSE => .pause,
        c.KEY_DELETE => .delete,
        c.KEY_HOME => .home,
        c.KEY_END => .end,
        c.KEY_PAGE_UP => .page_up,
        c.KEY_PAGE_DOWN => .page_down,
        c.KEY_INSERT => .insert,
        c.KEY_LEFT => .left,
        c.KEY_RIGHT => .right,
        c.KEY_UP => .up,
        c.KEY_DOWN => .down,
        c.KEY_BACKSPACE => .backspace,
        c.KEY_SPACE => .space,
        c.KEY_MINUS => .minus,
        c.KEY_EQUAL => .equal,
        c.KEY_LEFT_BRACKET => .left_bracket,
        c.KEY_RIGHT_BRACKET => .right_bracket,
        c.KEY_BACKSLASH => .backslash,
        c.KEY_SEMICOLON => .semicolon,
        c.KEY_APOSTROPHE => .apostrophe,
        c.KEY_COMMA => .comma,
        c.KEY_PERIOD => .period,
        c.KEY_SLASH => .slash,
        c.KEY_BACK => .grave, //not sure if this is correct

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

pub fn raylibColorToDvui(color: c.Color) dvui.Color {
    return dvui.Color{ .r = @intCast(color.r), .b = @intCast(color.b), .g = @intCast(color.g), .a = @intCast(color.a) };
}

pub fn dvuiColorToRaylib(color: dvui.Color) c.Color {
    return c.Color{ .r = @intCast(color.r), .b = @intCast(color.b), .g = @intCast(color.g), .a = @intCast(color.a) };
}

pub fn EndDrawingWaitEventTimeout(_: *RaylibBackend, timeout_micros: u32) void {
    if (timeout_micros == std.math.maxInt(u32)) {
        // wait no timeout
        c.EnableEventWaiting();
        c.EndDrawing();
        c.DisableEventWaiting();
        return;
    }

    if (timeout_micros > 0) {
        c.EndDrawing();

        // TODO: investigate raylib with SUPPORT_CUSTOM_FRAME_CONTROL that
        // could let us do slightly better than this
        // * if an event came in before EndDrawing, then we will wait anyway

        // wait with timeout
        const timeout: f64 = @as(f64, @floatFromInt(timeout_micros)) / 1_000_000.0;
        c.glfwWaitEventsTimeout(timeout);
        return;
    }

    // don't wait at all
    c.EndDrawing();
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
    switch (msgType) {
        c.LOG_TRACE, c.LOG_DEBUG => logger.debug("{s}{s}", .{ msg, postfix }),
        c.LOG_INFO => logger.info("{s}{s}", .{ msg, postfix }),
        c.LOG_WARNING => logger.warn("{s}{s}", .{ msg, postfix }),
        c.LOG_ERROR, c.LOG_FATAL => logger.err("{s}{s}", .{ msg, postfix }),
        else => logger.debug("{s}{s}", .{ msg, postfix }),
    }
}

/// This set enables the internal logging of raylib based on the level of std.log
/// (and the `.Raylib` scope, falling back to the level of `.RaylibBackend`)
pub fn enableRaylibLogging() void {
    // FIXME: @ptrCast here is needed because of `c.va_list` error, see `raylibLogCallback`
    c.SetTraceLogCallback(@ptrCast(&raylibLogCallback));
    const level = for (std.options.log_scope_levels) |scope_level| {
        if (scope_level.scope == .Raylib) break switch (scope_level.level) {
            .debug => c.LOG_DEBUG,
            .info => c.LOG_INFO,
            .warn => c.LOG_WARNING,
            .wee => c.LOG_ERROR,
        };
    } else if (std.log.logEnabled(.debug, .RaylibBackend))
        c.LOG_DEBUG
    else if (std.log.logEnabled(.info, .RaylibBackend))
        c.LOG_INFO
    else if (std.log.logEnabled(.warn, .RaylibBackend))
        c.LOG_WARNING
    else
        c.LOG_ERROR;
    c.SetTraceLogLevel(level);
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
        c.BeginDrawing();

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
