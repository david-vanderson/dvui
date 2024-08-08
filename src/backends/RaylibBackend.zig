const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");

pub const c = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    @cInclude("rlgl.h");
    @cInclude("GLES3/gl3.h");
});

const RaylibBackend = @This();

shader: c.Shader = undefined,
arena: std.mem.Allocator = undefined,
log_events: bool = false,
key_press_cache: std.ArrayList(c_int) = undefined,

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
    \\    fragColor.rgb *= fragColor.a;
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
    //"uniform vec4 colDiffuse;           \n"
    //"void main()                        \n"
    //"{                                  \n"
    //"    vec4 texelColor = texture(texture0, fragTexCoord);   \n"
    //"    finalColor = texelColor*colDiffuse*fragColor;        \n"
    //"}                                  \n";
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
    /// The allocator used for temporary allocations used during init()
    allocator: std.mem.Allocator,
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

pub fn init(options: InitOptions) !RaylibBackend {
    // TODO: implement all InitOptions
    c.SetConfigFlags(c.FLAG_WINDOW_RESIZABLE);
    if (options.vsync) {
        c.SetConfigFlags(c.FLAG_VSYNC_HINT);
    }

    c.InitWindow(@as(c_int, @intFromFloat(options.size.w)), @as(c_int, @intFromFloat(options.size.h)), options.title);

    if (options.min_size) |min| {
        c.SetWindowMinSize(@intFromFloat(min.w), @intFromFloat(min.h));
    }
    if (options.max_size) |max| {
        c.SetWindowMaxSize(@intFromFloat(max.w), @intFromFloat(max.h));
    }

    var back = RaylibBackend{};
    back.shader = c.LoadShaderFromMemory(vertexSource, fragSource);
    back.key_press_cache = std.ArrayList(c_int).init(options.allocator);
    return back;
}

pub fn deinit(self: *RaylibBackend) void {
    self.key_press_cache.deinit();
    c.CloseWindow();
}

pub fn backend(self: *RaylibBackend) dvui.Backend {
    return dvui.Backend.init(self, @This());
}

pub fn nanoTime(self: *RaylibBackend) i128 {
    _ = self;
    return std.time.nanoTimestamp();
}

pub fn sleep(self: *RaylibBackend, ns: u64) void {
    _ = self;
    std.time.sleep(ns);
}

pub fn begin(self: *RaylibBackend, arena: std.mem.Allocator) void {
    self.arena = arena;
    c.BeginDrawing();
}

pub fn end(_: *RaylibBackend) void {
    c.EndDrawing();
}

pub fn pixelSize(_: *RaylibBackend) dvui.Size {
    const w = c.GetRenderWidth();
    const h = c.GetRenderHeight();
    return dvui.Size{ .w = @floatFromInt(w), .h = @floatFromInt(h) };
}

pub fn windowSize(_: *RaylibBackend) dvui.Size {
    const w = c.GetScreenWidth();
    const h = c.GetScreenHeight();
    return dvui.Size{ .w = @floatFromInt(w), .h = @floatFromInt(h) };
}

pub fn contentScale(_: *RaylibBackend) f32 {
    return 1.0;
}

pub fn drawClippedTriangles(self: *RaylibBackend, texture: ?*anyopaque, vtx: []const dvui.Vertex, idx: []const u32, clipr: dvui.Rect) void {
    _ = clipr;
    // TODO: scissor
    // TODO: texture

    const shader = self.shader;
    c.rlEnableShader(shader.id);

    const mat = c.MatrixOrtho(0, @floatFromInt(c.GetRenderWidth()), @floatFromInt(c.GetRenderHeight()), 0, -1, 1);
    c.SetShaderValueMatrix(shader, @intCast(shader.locs[c.RL_SHADER_LOC_MATRIX_MVP]), mat);

    const VAO = c.rlLoadVertexArray();
    _ = c.rlEnableVertexArray(VAO);

    const VBO = c.rlLoadVertexBuffer(vtx.ptr, @intCast(vtx.len * @sizeOf(dvui.Vertex)), false);
    c.rlEnableVertexBuffer(VBO);
    const EBO = c.rlLoadVertexBufferElement(idx.ptr, @intCast(idx.len * @sizeOf(u32)), false);
    c.rlEnableVertexBufferElement(EBO);

    c.rlSetVertexAttribute(@intCast(shader.locs[c.RL_SHADER_LOC_VERTEX_POSITION]), 2, c.RL_FLOAT, false, @sizeOf(dvui.Vertex), @ptrFromInt(@offsetOf(dvui.Vertex, "pos")));
    c.rlEnableVertexAttribute(@intCast(shader.locs[c.RL_SHADER_LOC_VERTEX_POSITION]));

    c.rlSetVertexAttribute(@intCast(shader.locs[c.RL_SHADER_LOC_VERTEX_COLOR]), 4, c.RL_UNSIGNED_BYTE, false, @sizeOf(dvui.Vertex), @ptrFromInt(@offsetOf(dvui.Vertex, "col")));
    c.rlEnableVertexAttribute(@intCast(shader.locs[c.RL_SHADER_LOC_VERTEX_COLOR]));

    c.rlSetVertexAttribute(@intCast(shader.locs[c.RL_SHADER_LOC_VERTEX_TEXCOORD01]), 2, c.RL_FLOAT, false, @sizeOf(dvui.Vertex), @ptrFromInt(@offsetOf(dvui.Vertex, "uv")));
    c.rlEnableVertexAttribute(@intCast(shader.locs[c.RL_SHADER_LOC_VERTEX_TEXCOORD01]));

    const usetex_loc = c.GetShaderLocation(shader, "useTex");

    if (texture) |tex| {
        c.glActiveTexture(c.GL_TEXTURE0);
        const texid = @intFromPtr(tex);
        c.glBindTexture(c.GL_TEXTURE_2D, @intCast(texid));

        const tex_loc = c.GetShaderLocation(shader, "texture0");
        c.glUniform1i(tex_loc, 0);

        c.glUniform1i(usetex_loc, 1);
    } else {
        c.glUniform1i(usetex_loc, 0);
    }

    c.glDrawElements(c.GL_TRIANGLES, @intCast(idx.len), c.GL_UNSIGNED_INT, null);
}

pub fn textureCreate(_: *RaylibBackend, pixels: [*]u8, width: u32, height: u32) *anyopaque {
    // TODO: do we need to convert to premultiplied alpha?
    const texid = c.rlLoadTexture(pixels, @intCast(width), @intCast(height), c.PIXELFORMAT_UNCOMPRESSED_R8G8B8A8, 1);
    return @ptrFromInt(texid);
}

pub fn textureDestroy(_: *RaylibBackend, texture: *anyopaque) void {
    const texid = @intFromPtr(texture);
    c.rlUnloadTexture(@intCast(texid));
}

pub fn clipboardText(_: *RaylibBackend) ![]const u8 {
    return std.mem.sliceTo(c.GetClipboardText(), 0);
}

pub fn clipboardTextSet(self: *RaylibBackend, text: []const u8) !void {
    //TODO can I free this memory??
    const c_text = try self.arena.dupeZ(u8, text);
    c.SetClipboardText(c_text.ptr);
}

pub fn openURL(self: *RaylibBackend, url: []const u8) !void {
    const c_url = try self.arena.dupeZ(u8, url);
    c.SetClipboardText(c_url.ptr);
}

pub fn refresh(_: *RaylibBackend) void {}

pub fn clear(_: *RaylibBackend) void {
    c.ClearBackground(c.BLACK);
}

pub fn addAllEvents(self: *RaylibBackend, win: *dvui.Window) !bool {
    //TODO mouse scrollwheel support
    //TODO touch support

    //check for key releases
    for (self.key_press_cache.items) |key| {
        if (c.IsKeyUp(key)) {}
    }

    //self.key_press_cache.clearRetainingCapacity();

    //get key presses
    while (true) {
        const event = c.GetKeyPressed();
        if (event == 0) break;

        try self.key_press_cache.append(event);

        //const code = raylibKeyToDvui(event);

        //@field(key_state_cache, @tagname(event))

        //check if keymod is pressed
        //if (isKeymod(raylibKeyToDvui(event))) {

        //    //TODO account for multiple modifier keys
        //    //maybe make this into its own function?
        //    const mod = raylibKeymodToDvui(event);
        //    const char = c.GetKeyPressed();
        //    if (char == 0) break;
        //    const code = raylibKeyToDvui(char);
        //    _ = try win.addEventKey(.{ .code = code, .mod = mod, .action = .down });
        //    _ = try win.addEventKey(.{ .code = code, .mod = mod, .action = .up });

        //    if (self.log_events) {
        //        std.debug.print("raylib event key {} with modifier {}\n", .{ code, mod });
        //    }

        //    //skip text entry if keymod is used
        //    continue;
        //}

        //normal alphabet char entry
        if (event >= c.KEY_A and event <= c.KEY_Z) {
            const char: u8 = @intCast(event);
            const shifted = if (isShiftDown()) char else std.ascii.toLower(char);
            const string: []const u8 = &.{shifted};
            if (self.log_events) {
                std.debug.print("raylib event text entry {s}\n", .{string});
            }
            _ = try win.addEventText(string);

            //non-alphabet ascii keys (these need to be separate because of
            //different shifted defaults rules
        } else if (isAsciiKey(event)) {
            const char: u8 = @intCast(event);
            const shifted = if (isShiftDown()) std.ascii.toUpper(char) else char;
            const string: []const u8 = &.{shifted};
            if (self.log_events) {
                std.debug.print("raylib event text entry {s}\n", .{string});
            }
            _ = try win.addEventText(string);
        }

        //TODO need to handle key modifiers here. Probably need to create some sort of
        //modifier queue whenever a modifier key is detected, then keep requesting more
        //keys until a non-modifier key is found
    }

    const mouse_move = c.GetMouseDelta();
    if (mouse_move.x != 0 or mouse_move.y != 0) {
        const mouse_pos = c.GetMousePosition();
        _ = try win.addEventMouseMotion(mouse_pos.x, mouse_pos.y);
        if (self.log_events) {
            //std.debug.print("raylib event Mouse Moved\n", .{});
        }
    }

    const Static = struct {
        var mouse_button_cache: [RaylibMouseButtons.len]bool = .{false} ** RaylibMouseButtons.len;
    };

    inline for (RaylibMouseButtons, 0..) |button, i| {
        if (c.IsMouseButtonDown(button)) {
            if (Static.mouse_button_cache[i] != true) {
                _ = try win.addEventMouseButton(raylibMouseButtonToDvui(button), .press);
                Static.mouse_button_cache[i] = true;
                if (self.log_events) {
                    std.debug.print("raylib event Mouse Button Pressed {}\n", .{raylibMouseButtonToDvui(button)});
                }
            }
        }
        if (c.IsMouseButtonUp(button)) {
            if (Static.mouse_button_cache[i] != false) {
                _ = try win.addEventMouseButton(raylibMouseButtonToDvui(button), .release);
                Static.mouse_button_cache[i] = false;

                if (self.log_events) {
                    std.debug.print("raylib event Mouse Button Released {}\n", .{raylibMouseButtonToDvui(button)});
                }
            }
        }
    }

    return c.WindowShouldClose();
}

const RaylibMouseButtons = .{
    c.MOUSE_BUTTON_LEFT,
    c.MOUSE_BUTTON_RIGHT,
    c.MOUSE_BUTTON_MIDDLE,
};

fn isShiftDown() bool {
    return c.IsKeyDown(c.KEY_LEFT_SHIFT) or c.IsKeyDown(c.KEY_RIGHT_SHIFT);
}

pub fn raylibMouseButtonToDvui(button: c_int) dvui.enums.Button {
    return switch (button) {
        c.MOUSE_BUTTON_LEFT => .left,
        c.MOUSE_BUTTON_MIDDLE => .middle,
        c.MOUSE_BUTTON_RIGHT => .right,
        //c.MOUSE_BUTTON_FORWARD => .four,
        //c.MOUSE_BUTTON_BACK => .five,
        else => blk: {
            dvui.log.debug("Raylib unknown button {}\n", .{button});
            break :blk .six;
        },
    };
}

fn isKeymod(key: dvui.enums.Key) bool {
    return key == .left_alt or key == .left_shift or key == .left_command or key == .left_control or
        key == .right_alt or key == .right_shift or key == .right_command or key == .right_control;
}

pub fn raylibKeymodToDvui(keymod: c_int) dvui.enums.Mod {
    if (keymod == c.KEY_NULL) return dvui.enums.Mod.none;

    var m: u16 = 0;
    if (keymod & c.KEY_LEFT_SHIFT > 0) m |= @intFromEnum(dvui.enums.Mod.lshift);
    if (keymod & c.KEY_RIGHT_SHIFT > 0) m |= @intFromEnum(dvui.enums.Mod.rshift);
    if (keymod & c.KEY_LEFT_CONTROL > 0) m |= @intFromEnum(dvui.enums.Mod.lcontrol);
    if (keymod & c.KEY_RIGHT_CONTROL > 0) m |= @intFromEnum(dvui.enums.Mod.rcontrol);
    if (keymod & c.KEY_LEFT_ALT > 0) m |= @intFromEnum(dvui.enums.Mod.lalt);
    if (keymod & c.KEY_RIGHT_ALT > 0) m |= @intFromEnum(dvui.enums.Mod.ralt);
    if (keymod & c.KEY_LEFT_SUPER > 0) m |= @intFromEnum(dvui.enums.Mod.lcommand);
    if (keymod & c.KEY_RIGHT_SUPER > 0) m |= @intFromEnum(dvui.enums.Mod.rcommand);

    return @as(dvui.enums.Mod, @enumFromInt(m));
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
        //c.KEY_MENU => .menu, //it appears menu and r use the same keycode ??
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
            dvui.log.debug("raylibKeymodToDvui unknown key{}\n", .{key});
            break :blk .unknown;
        },
    };
}

fn isAsciiKey(key: c_int) bool {
    return switch (key) {
        c.KEY_A,
        c.KEY_B,
        c.KEY_C,
        c.KEY_D,
        c.KEY_E,
        c.KEY_F,
        c.KEY_G,
        c.KEY_H,
        c.KEY_I,
        c.KEY_J,
        c.KEY_K,
        c.KEY_L,
        c.KEY_M,
        c.KEY_N,
        c.KEY_O,
        c.KEY_P,
        c.KEY_Q,
        c.KEY_R,
        c.KEY_S,
        c.KEY_T,
        c.KEY_U,
        c.KEY_V,
        c.KEY_W,
        c.KEY_X,
        c.KEY_Y,
        c.KEY_Z,
        c.KEY_ZERO,
        c.KEY_ONE,
        c.KEY_TWO,
        c.KEY_THREE,
        c.KEY_FOUR,
        c.KEY_FIVE,
        c.KEY_SIX,
        c.KEY_SEVEN,
        c.KEY_EIGHT,
        c.KEY_NINE,
        c.KEY_SPACE,
        c.KEY_MINUS,
        c.KEY_EQUAL,
        c.KEY_LEFT_BRACKET,
        c.KEY_RIGHT_BRACKET,
        c.KEY_BACKSLASH,
        c.KEY_SEMICOLON,
        c.KEY_APOSTROPHE,
        c.KEY_COMMA,
        c.KEY_PERIOD,
        c.KEY_SLASH,
        c.KEY_BACK,
        => true,

        else => false,
    };
}

pub fn dvuiKeyToRaylib(key: dvui.enums.Key) c_int {
    return switch (key) {
        .a => c.KEY_A,
        .b => c.KEY_B,
        .c => c.KEY_C,
        .d => c.KEY_D,
        .e => c.KEY_E,
        .f => c.KEY_F,
        .g => c.KEY_G,
        .h => c.KEY_H,
        .i => c.KEY_I,
        .j => c.KEY_J,
        .k => c.KEY_K,
        .l => c.KEY_L,
        .m => c.KEY_M,
        .n => c.KEY_N,
        .o => c.KEY_O,
        .p => c.KEY_P,
        .q => c.KEY_Q,
        .r => c.KEY_R,
        .s => c.KEY_S,
        .t => c.KEY_T,
        .u => c.KEY_U,
        .v => c.KEY_V,
        .w => c.KEY_W,
        .x => c.KEY_X,
        .y => c.KEY_Y,
        .z => c.KEY_Z,

        .zero => c.KEY_ZERO,
        .one => c.KEY_ONE,
        .two => c.KEY_TWO,
        .three => c.KEY_THREE,
        .four => c.KEY_FOUR,
        .five => c.KEY_FIVE,
        .six => c.KEY_SIX,
        .seven => c.KEY_SEVEN,
        .eight => c.KEY_EIGHT,
        .nine => c.KEY_NINE,

        .f1 => c.KEY_F1,
        .f2 => c.KEY_F2,
        .f3 => c.KEY_F3,
        .f4 => c.KEY_F4,
        .f5 => c.KEY_F5,
        .f6 => c.KEY_F6,
        .f7 => c.KEY_F7,
        .f8 => c.KEY_F8,
        .f9 => c.KEY_F9,
        .f10 => c.KEY_F10,
        .f11 => c.KEY_F11,
        .f12 => c.KEY_F12,

        .kp_divide => c.KEY_KP_DIVIDE,
        .kp_multiply => c.KEY_KP_MULTIPLY,
        .kp_subtract => c.KEY_KP_SUBTRACT,
        .kp_add => c.KEY_KP_ADD,
        .kp_enter => c.KEY_KP_ENTER,
        .kp_0 => c.KEY_KP_0,
        .kp_1 => c.KEY_KP_1,
        .kp_2 => c.KEY_KP_2,
        .kp_3 => c.KEY_KP_3,
        .kp_4 => c.KEY_KP_4,
        .kp_5 => c.KEY_KP_5,
        .kp_6 => c.KEY_KP_6,
        .kp_7 => c.KEY_KP_7,
        .kp_8 => c.KEY_KP_8,
        .kp_9 => c.KEY_KP_9,
        .kp_decimal => c.KEY_KP_DECIMAL,

        .enter => c.KEY_ENTER,
        .escape => c.KEY_ESCAPE,
        .tab => c.KEY_TAB,
        .left_shift => c.KEY_LEFT_SHIFT,
        .right_shift => c.KEY_RIGHT_SHIFT,
        .left_control => c.KEY_LEFT_CONTROL,
        .right_control => c.KEY_RIGHT_CONTROL,
        .left_alt => c.KEY_LEFT_ALT,
        .right_alt => c.KEY_RIGHT_ALT,
        .left_command => c.KEY_LEFT_SUPER,
        .right_command => c.KEY_RIGHT_SUPER,
        .num_lock => c.KEY_NUM_LOCK,
        .caps_lock => c.KEY_CAPS_LOCK,
        .print => c.KEY_PRINT_SCREEN,
        .scroll_lock => c.KEY_SCROLL_LOCK,
        .pause => c.KEY_PAUSE,
        .delete => c.KEY_DELETE,
        .home => c.KEY_HOME,
        .end => c.KEY_END,
        .page_up => c.KEY_PAGE_UP,
        .page_down => c.KEY_PAGE_DOWN,
        .insert => c.KEY_INSERT,
        .left => c.KEY_LEFT,
        .right => c.KEY_RIGHT,
        .up => c.KEY_UP,
        .down => c.KEY_DOWN,
        .backspace => c.KEY_BACKSPACE,
        .space => c.KEY_SPACE,
        .minus => c.KEY_MINUS,
        .equal => c.KEY_EQUAL,
        .left_bracket => c.KEY_LEFT_BRACKET,
        .right_bracket => c.KEY_RIGHT_BRACKET,
        .backslash => c.KEY_BACKSLASH,
        .semicolon => c.KEY_SEMICOLON,
        .apostrophe => c.KEY_APOSTROPHE,
        .comma => c.KEY_COMMA,
        .period => c.KEY_PERIOD,
        .slash => c.KEY_SLASH,
        .grave => c.KEY_BACK,
        .menu => c.KEY_MENU,

        else => blk: {
            dvui.log.debug("dvuiKeyToRaylib unknown key{}\n", .{key});
            break :blk -1; // Return an invalid keycode for unknown keys
        },
    };
}
