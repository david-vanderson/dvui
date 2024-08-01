const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");

pub const c = @cImport({
    @cInclude("raylib.h");
    @cInclude("rlgl.h");
    @cInclude("GLES3/gl3.h");
});

const RaylibBackend = @This();

shader: c.Shader = undefined,
arena: std.mem.Allocator = undefined,

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
    //\\    fragColor.rgb *= fragColor.a;
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
    \\    if (useTex)
    \\        finalColor = texture(texture0, fragTexCoord) * fragColor;
    \\    else
    \\        finalColor = fragColor;
    //\\        finalColor = fragColor;
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
    return back;
}

pub fn deinit(_: *RaylibBackend) void {
    c.CloseWindow();
}

pub fn backend(self: *RaylibBackend) dvui.Backend {
    return dvui.Backend.init(self, nanoTime, sleep, begin, end, pixelSize, windowSize, contentScale, renderGeometry, textureCreate, textureDestroy, clipboardText, clipboardTextSet, openURL, refresh);
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

pub fn renderGeometry(self: *RaylibBackend, texture: ?*anyopaque, vtx: []const dvui.Vertex, idx: []const u32) void {
    // TODO: scissor
    // TODO: texture

    var mat: c.Matrix = undefined; // = c.GetCameraMatrix2D(camera);
    mat.m0 = 2.0 / @as(f32, @floatFromInt(c.GetRenderWidth()));
    mat.m1 = 0.0;
    mat.m2 = 0.0;
    mat.m3 = 0.0;
    mat.m4 = 0.0;
    mat.m5 = -2.0 / @as(f32, @floatFromInt(c.GetRenderHeight()));
    mat.m6 = 0.0;
    mat.m7 = 0.0;
    mat.m8 = 0.0;
    mat.m9 = 0.0;
    mat.m10 = 1.0;
    mat.m11 = 0.0;
    mat.m12 = -1.0;
    mat.m13 = 1.0;
    mat.m14 = 0.0;
    mat.m15 = 1.0;

    const shader = self.shader;
    c.SetShaderValueMatrix(shader, @intCast(shader.locs[c.RL_SHADER_LOC_MATRIX_MVP]), mat);

    const VAO = c.rlLoadVertexArray();
    _ = c.rlEnableVertexArray(VAO);

    const VBO = c.rlLoadVertexBuffer(vtx.ptr, @intCast(vtx.len * @sizeOf(dvui.Vertex)), false);
    _ = VBO;
    const EBO = c.rlLoadVertexBufferElement(idx.ptr, @intCast(idx.len * @sizeOf(u32)), false);
    _ = EBO;

    c.rlSetVertexAttribute(@intCast(shader.locs[c.RL_SHADER_LOC_VERTEX_POSITION]), 2, c.RL_FLOAT, false, @sizeOf(dvui.Vertex), @offsetOf(dvui.Vertex, "pos"));
    c.rlEnableVertexAttribute(@intCast(shader.locs[c.RL_SHADER_LOC_VERTEX_POSITION]));

    c.rlSetVertexAttribute(@intCast(shader.locs[c.RL_SHADER_LOC_VERTEX_COLOR]), 4, c.RL_UNSIGNED_BYTE, false, @sizeOf(dvui.Vertex), @offsetOf(dvui.Vertex, "col"));
    c.rlEnableVertexAttribute(@intCast(shader.locs[c.RL_SHADER_LOC_VERTEX_COLOR]));

    c.rlSetVertexAttribute(@intCast(shader.locs[c.RL_SHADER_LOC_VERTEX_TEXCOORD01]), 2, c.RL_FLOAT, false, @sizeOf(dvui.Vertex), @offsetOf(dvui.Vertex, "uv"));
    c.rlEnableVertexAttribute(@intCast(shader.locs[c.RL_SHADER_LOC_VERTEX_TEXCOORD01]));

    c.rlEnableShader(shader.id);

    const tex_coord_loc = c.GetShaderLocationAttrib(shader, "vertexTexCoord");
    //std.debug.print("tex_coord_loc {d}\n", .{tex_coord_loc});
    c.rlSetVertexAttribute(@intCast(tex_coord_loc), 2, c.RL_FLOAT, false, @sizeOf(dvui.Vertex), @offsetOf(dvui.Vertex, "uv"));
    c.rlEnableVertexAttribute(@intCast(tex_coord_loc));

    //c.glUniform1i(@intCast(shader.locs[c.RL_SHADER_LOC_MAP_DIFFUSE]), 0); // Active default sampler2D: texture0

    if (texture) |tex| {
        c.glUniform1i(c.GetShaderLocation(shader, "texture0"), 0);
        c.glActiveTexture(c.GL_TEXTURE0);
        //c.rlActiveTextureSlot(2);

        const texid = @intFromPtr(tex);
        c.glBindTexture(c.GL_TEXTURE_2D, @intCast(texid));
        //c.rlEnableTexture(@intCast(texid));

        c.glUniform1i(2, 1);
    } else {
        c.glUniform1i(2, 0);
    }

    c.glDrawElements(c.GL_TRIANGLES, @intCast(idx.len), c.GL_UNSIGNED_INT, null);

    c.rlDisableTexture();
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
    //c.ClearBackground(c.BLACK);
    c.ClearBackground(c.BLANK);
}
