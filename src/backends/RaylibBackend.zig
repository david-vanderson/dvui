pub const RaylibBackend = @This();
const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const ray = @cImport({
    @cInclude("raylib.h");
});
pub const c = @cImport({
    @cInclude("raylib.h");
    @cInclude("rlgl.h");
    @cInclude("GLES3/gl3.h");
});

const conversion_factor = 1000000000;

initial_scale: f32 = 1.0,
arena: std.mem.Allocator,

pub fn nanoTime(self: *RaylibBackend) i128 {
    _ = self;
    return @intFromFloat(ray.GetTime() * conversion_factor); // Get elapsed time in seconds since InitWindow()
}

pub fn sleep(self: *RaylibBackend, ns: u64) void {
    _ = self; // autofix
    const seconds: f64 = @floatFromInt(ns / conversion_factor);
    ray.WaitTime(seconds);
}

pub fn begin(self: *RaylibBackend, arena: std.mem.Allocator) void {
    ray.BeginDrawing();
    _ = self; // autofix
    _ = arena; // autofix
}

pub fn end(self: *RaylibBackend) void {
    _ = self; // autofix
    ray.EndDrawing();
}

pub fn pixelSize(self: *RaylibBackend) dvui.Size {
    _ = self; // autofix
    return dvui.Size{
        .w = @as(f32, @floatFromInt(ray.GetRenderWidth())),
        .h = @as(f32, @floatFromInt(ray.GetRenderHeight())),
    };
}

pub fn windowSize(self: *RaylibBackend) dvui.Size {
    _ = self; // autofix
    return dvui.Size{
        .w = @as(f32, @floatFromInt(ray.GetScreenWidth())),
        .h = @as(f32, @floatFromInt(ray.GetScreenHeight())),
    };
}

pub fn contentScale(self: *RaylibBackend) f32 {
    return self.initial_scale;
}

//TODO implement
pub fn renderGeometry(self: *RaylibBackend, texture: ?*anyopaque, vtx: []const dvui.Vertex, idx: []const u32) void {
    // TODO: scissor
    // TODO: texture
    _ = self;
    _ = texture;

    const vertexSource =
        \\#version 330
        \\in vec3 vertexPosition;
        //"in vec2 vertexTexCoord;            \n"
        \\in vec4 vertexColor;
        //"out vec2 fragTexCoord;             \n"
        \\out vec4 fragColor;
        \\uniform mat4 mvp;
        \\void main()
        \\{
        //"    fragTexCoord = vertexTexCoord; \n"
        \\    fragColor = vertexColor / 255.0;
        //\\    fragColor.rgb *= fragColor.a;
        \\    gl_Position = mvp*vec4(vertexPosition, 1.0);
        //\\    gl_Position = vec4(vertexPosition, 1.0);
        \\}
    ;

    const fragSource =
        \\#version 330
        //"in vec2 fragTexCoord;              \n"
        \\in vec4 fragColor;
        \\out vec4 finalColor;
        //"uniform sampler2D texture0;        \n"
        //"uniform vec4 colDiffuse;           \n"
        //"void main()                        \n"
        //"{                                  \n"
        //"    vec4 texelColor = texture(texture0, fragTexCoord);   \n"
        //"    finalColor = texelColor*colDiffuse*fragColor;        \n"
        //"}                                  \n";
        \\void main()
        \\{
        \\    finalColor = fragColor;
        \\}
    ;

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

    const shader = c.LoadShaderFromMemory(vertexSource, fragSource);

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

    c.rlEnableShader(shader.id);

    c.glDrawElements(c.GL_TRIANGLES, @intCast(idx.len), c.GL_UNSIGNED_INT, null);
}

pub fn textureCreate(self: *RaylibBackend, pixels: [*]u8, width: u32, height: u32) *anyopaque {
    const texture = self.arena.create(ray.RenderTexture) catch @panic("out of memory");
    texture.* = ray.LoadRenderTexture(@intCast(width), @intCast(height));
    ray.UpdateTexture(texture.texture, pixels);
    return texture;
}

pub fn textureDestroy(self: *RaylibBackend, texture: *anyopaque) void {
    const ptr: *ray.RenderTexture = @alignCast(@ptrCast(texture));
    ray.UnloadRenderTexture(ptr.*);
    self.arena.destroy(ptr);
}

pub fn clipboardText(self: *RaylibBackend) error{OutOfMemory}![]const u8 {
    _ = self; // autofix
    return std.mem.sliceTo(ray.GetClipboardText(), 0);
}

pub fn clipboardTextSet(self: *RaylibBackend, text: []const u8) error{OutOfMemory}!void {
    //TODO can I free this memory??
    const c_text = try self.arena.dupeZ(u8, text);
    ray.SetClipboardText(c_text.ptr);
}

pub fn openURL(self: *RaylibBackend, url: []const u8) error{OutOfMemory}!void {
    const c_url = try self.arena.dupeZ(u8, url);
    ray.SetClipboardText(c_url.ptr);
}

pub fn refresh(self: *RaylibBackend) void {
    _ = self; // autofix
    //ray.EndDrawing();
    //ray.BeginDrawing();
}

pub fn backend(self: *RaylibBackend) dvui.Backend {
    return dvui.Backend.init(self, nanoTime, sleep, begin, end, pixelSize, windowSize, contentScale, renderGeometry, textureCreate, textureDestroy, clipboardText, clipboardTextSet, openURL, refresh);
}

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
    ray.SetConfigFlags(ray.FLAG_WINDOW_RESIZABLE);
    if (options.vsync) {
        ray.SetConfigFlags(ray.FLAG_VSYNC_HINT);
    }
    ray.InitWindow(@intFromFloat(options.size.w), @intFromFloat(options.size.h), options.title);

    if (options.min_size) |min| {
        ray.SetWindowMinSize(min.intWidth(), min.intHeight());
    }
    if (options.max_size) |max| {
        ray.SetWindowMinSize(max.intWidth(), max.intHeight());
    }

    //TODO implement icon
    return RaylibBackend{
        .initial_scale = 1.0,
        .arena = options.allocator,
    };
}

pub fn deinit(self: *RaylibBackend) void {
    _ = self; // autofix
    ray.CloseWindow();
}

pub fn setIconFromFileContent(self: *RaylibBackend, file_content: []const u8) void {
    _ = self; // autofix
    _ = file_content; // autofix
    //TODO implement
}

pub fn hasEvent(self: *RaylibBackend) bool {
    _ = self; // autofix
    // TODO implement
    return false;
}

pub fn clear(self: *RaylibBackend) void {
    _ = self; // autofix
}

pub fn addAllEvents(self: *RaylibBackend, win: *dvui.Window) !bool {
    _ = self; // autofix
    _ = win; // autofix

    //TODO implement
    return false;
}

pub fn setCursor(self: *RaylibBackend, cursor: dvui.enums.Cursor) void {
    _ = self; // autofix
    _ = cursor; // autofix
    //TODO implement
}

pub fn renderPresent(self: *RaylibBackend) void {
    _ = self; // autofix
}

pub fn waitEventTimeout(self: *RaylibBackend, ms: u32) void {
    _ = self; // autofix
    _ = ms; // autofix

}
