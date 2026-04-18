//! OpenGL 3.0+ renderer.
//!
//! After rendering, the following state will be changed:
//! - GL_CURRENT_PROGRAM
//! - GL_VERTEX_ARRAY_BINDING
//! - GL_VIEWPORT
//! - GL_ACTIVE_TEXTURE
//! - GL_TEXTURE_BINDING_2D
//! - GL_DRAW_FRAMEBUFFER_BINDING
//! - GL_BLEND
//! - GL_BLEND_SRC_RGB
//! - GL_BLEND_SRC_ALPHA
//! - GL_BLEND_DST_RGB
//! - GL_BLEND_DST_ALPHA
//! - GL_SCISSOR_TEST

const std = @import("std");
const dvui = @import("dvui");
const gl = @import("gl");
const log = std.log.scoped(.dvui_opengl);

pub const kind: dvui.enums.RenderBackend = .opengl;

allocator: std.mem.Allocator,
program: u32,
uniforms: struct {
    projection: i32,
    sampler: i32,
    use_sampler: i32,
},
vao: u32,
vbo: u32,
ebo: u32,
framebuffers: std.AutoHashMapUnmanaged(u32, u32) = .empty,
render_target_size: ?dvui.Size.Physical = null,

pub fn init(allocator: std.mem.Allocator, getProcAddress: anytype, comptime glsl_version: []const u8) !@This() {
    try gl.load(getProcAddress);

    const sources = shaderSources(glsl_version);

    const vertex_shader = gl.createShader(gl.VERTEX_SHADER);
    defer gl.deleteShader(vertex_shader);
    gl.shaderSource(vertex_shader, 1, &[_][*]const u8{sources.vertex}, &[_]i32{sources.vertex.len});
    gl.compileShader(vertex_shader);

    const fragment_shader = gl.createShader(gl.FRAGMENT_SHADER);
    defer gl.deleteShader(fragment_shader);
    gl.shaderSource(fragment_shader, 1, &[_][*]const u8{sources.fragment}, &[_]i32{sources.fragment.len});
    gl.compileShader(fragment_shader);

    const program = gl.createProgram();
    gl.attachShader(program, vertex_shader);
    gl.attachShader(program, fragment_shader);
    gl.linkProgram(program);

    const position: u32 = @bitCast(gl.getAttribLocation(program, "v_position"));
    const color: u32 = @bitCast(gl.getAttribLocation(program, "v_color"));
    const uv: u32 = @bitCast(gl.getAttribLocation(program, "v_uv"));

    const projection = gl.getUniformLocation(program, "projection");
    const sampler = gl.getUniformLocation(program, "sampler");
    const use_sampler = gl.getUniformLocation(program, "use_sampler");

    var vao: u32 = undefined;
    gl.genVertexArrays(1, &vao);

    var buffers: [2]u32 = undefined;
    gl.genBuffers(buffers.len, &buffers);
    const vbo = buffers[0];
    const ebo = buffers[1];

    gl.bindVertexArray(vao);

    gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);

    gl.enableVertexAttribArray(position);
    gl.enableVertexAttribArray(color);
    gl.enableVertexAttribArray(uv);
    gl.vertexAttribPointer(position, 2, gl.FLOAT, gl.FALSE, @sizeOf(dvui.Vertex), @ptrFromInt(@offsetOf(dvui.Vertex, "pos")));
    gl.vertexAttribPointer(color, 4, gl.UNSIGNED_BYTE, gl.FALSE, @sizeOf(dvui.Vertex), @ptrFromInt(@offsetOf(dvui.Vertex, "col")));
    gl.vertexAttribPointer(uv, 2, gl.FLOAT, gl.FALSE, @sizeOf(dvui.Vertex), @ptrFromInt(@offsetOf(dvui.Vertex, "uv")));

    gl.bindVertexArray(0);

    return .{
        .allocator = allocator,
        .program = program,
        .uniforms = .{
            .projection = projection,
            .sampler = sampler,
            .use_sampler = use_sampler,
        },
        .vao = vao,
        .vbo = vbo,
        .ebo = ebo,
    };
}

pub fn deinit(self: *@This()) void {
    self.framebuffers.deinit(self.allocator);
    const buffers = [_]u32{ self.vbo, self.ebo };
    gl.deleteBuffers(buffers.len, &buffers);
    gl.deleteVertexArrays(1, &self.vao);
    gl.deleteProgram(self.program);
}

pub fn begin(self: *@This(), _: std.mem.Allocator) !void {
    gl.useProgram(self.program);
    gl.bindVertexArray(self.vao);

    gl.enable(gl.BLEND);
    gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
}

pub fn end(_: *@This()) !void {}

pub fn drawClippedTriangles(self: *@This(), physical_size: dvui.Size.Physical, maybe_texture: ?dvui.Texture, vtx: []const dvui.Vertex, idx: []const dvui.Vertex.Index, maybe_clipr: ?dvui.Rect.Physical) !void {
    const size = self.render_target_size orelse physical_size;
    gl.viewport(0, 0, @intFromFloat(size.w), @intFromFloat(size.h));

    if (maybe_clipr) |clipr| {
        gl.enable(gl.SCISSOR_TEST);
        gl.scissor(
            @intFromFloat(clipr.x),
            @intFromFloat(if (self.render_target_size == null) physical_size.h - clipr.y - clipr.h else clipr.y),
            @intFromFloat(clipr.w),
            @intFromFloat(clipr.h),
        );
    }

    gl.bufferData(gl.ARRAY_BUFFER, @bitCast(vtx.len * @sizeOf(dvui.Vertex)), vtx.ptr, gl.STREAM_DRAW);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @bitCast(idx.len * @sizeOf(dvui.Vertex.Index)), idx.ptr, gl.STREAM_DRAW);

    if (maybe_texture) |texture| {
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, @intCast(@intFromPtr(texture.ptr)));
        gl.uniform1i(self.uniforms.use_sampler, 1);
        gl.uniform1i(self.uniforms.sampler, 0);
    } else {
        gl.uniform1i(self.uniforms.use_sampler, 0);
    }

    const sign: f32 = if (self.render_target_size != null) -1 else 1;
    gl.uniformMatrix4fv(self.uniforms.projection, 1, gl.FALSE, &[_]f32{
        2 / size.w, 0,                  0,  0,
        0,          -sign * 2 / size.h, 0,  0,
        0,          0,                  1,  0,
        -1,         sign * 1,           -1, 1,
    });

    const index_type = switch (dvui.Vertex.Index) {
        u16 => gl.UNSIGNED_SHORT,
        u32 => gl.UNSIGNED_INT,
        else => @compileError("invalid vertex index type"),
    };
    gl.drawElements(gl.TRIANGLES, @intCast(idx.len), index_type, null);

    if (maybe_clipr != null) {
        gl.disable(gl.SCISSOR_TEST);
    }
}

pub fn textureCreate(_: *@This(), pixels: [*]const u8, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation, format: dvui.enums.TexturePixelFormat) !dvui.Texture {
    return .{ .ptr = @ptrFromInt(try createTexture(pixels, width, height, interpolation, format)), .width = width, .height = height, .format = format };
}

pub fn textureUpdate(_: *@This(), texture: dvui.Texture, pixels: [*]const u8) !void {
    gl.bindTexture(gl.TEXTURE_2D, @intCast(@intFromPtr(texture.ptr)));
    gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, @bitCast(texture.width), @bitCast(texture.height), gl.RGBA, gl.UNSIGNED_BYTE, pixels);
}

pub fn textureDestroy(self: *@This(), texture: dvui.Texture) void {
    const handle: u32 = @intCast(@intFromPtr(texture.ptr));
    gl.deleteTextures(1, &handle);
    if (self.framebuffers.fetchRemove(handle)) |kv| {
        gl.deleteFramebuffers(1, &kv.value);
    }
}

pub fn textureCreateTarget(self: *@This(), width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation, format: dvui.enums.TexturePixelFormat) !dvui.TextureTarget {
    const texture = try createTexture(null, width, height, interpolation, format);
    errdefer gl.deleteTextures(1, &texture);

    var framebuffer: u32 = undefined;
    gl.genFramebuffers(1, &framebuffer);
    errdefer gl.deleteFramebuffers(1, &framebuffer);

    try self.framebuffers.put(self.allocator, texture, framebuffer);

    gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, framebuffer);
    gl.framebufferTexture2D(gl.DRAW_FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, 0);

    return .{ .ptr = @ptrFromInt(texture), .width = width, .height = height, .format = format };
}

pub fn textureReadTarget(_: *@This(), texture: dvui.TextureTarget, pixels_out: [*]u8) !void {
    gl.bindTexture(gl.TEXTURE_2D, @intCast(@intFromPtr(texture.ptr)));
    gl.getTexImage(gl.TEXTURE_2D, 0, gl.RGBA, gl.UNSIGNED_BYTE, pixels_out);
}

pub fn textureClearTarget(self: *@This(), texture: dvui.Texture.Target) void {
    self.renderTarget(texture) catch return;
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    self.renderTarget(null) catch return;
}

pub fn textureDestroyTarget(self: *@This(), texture: dvui.Texture.Target) void {
    const handle: u32 = @intCast(@intFromPtr(texture.ptr));
    gl.deleteTextures(1, &handle);
    if (self.framebuffers.fetchRemove(handle)) |kv| {
        gl.deleteFramebuffers(1, &kv.value);
    }
}

pub fn textureFromTarget(_: *@This(), target: dvui.TextureTarget) !dvui.Texture {
    return .{ .ptr = target.ptr, .height = target.height, .width = target.width, .format = target.format };
}

pub fn textureFromTargetTemp(self: *@This(), target: dvui.TextureTarget) !dvui.Texture {
    return self.textureFromTarget(target);
}

pub fn renderTarget(self: *@This(), maybe_texture: ?dvui.TextureTarget) !void {
    if (maybe_texture) |texture| {
        const fbo = self.framebuffers.get(@intCast(@intFromPtr(texture.ptr))).?;
        gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, fbo);
        self.render_target_size = .{ .w = @floatFromInt(texture.width), .h = @floatFromInt(texture.height) };
    } else {
        gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, 0);
        self.render_target_size = null;
    }
}

fn createTexture(pixels: ?[*]const u8, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation, format: dvui.enums.TexturePixelFormat) !u32 {
    if (format != .rgba_32) {
        log.err("unsupported texture format", .{});
        return dvui.Backend.TextureError.TextureCreate;
    }

    var texture: u32 = undefined;
    gl.genTextures(1, &texture);
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, @bitCast(width), @bitCast(height), 0, gl.RGBA, gl.UNSIGNED_BYTE, pixels);

    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

    switch (interpolation) {
        .linear => {
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        },
        .nearest => {
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        },
    }

    return texture;
}

fn shaderSources(version: []const u8) type {
    return struct {
        const vertex =
            "#version " ++ version ++ "\n" ++
            \\
            \\in vec2 v_position;
            \\in vec4 v_color;
            \\in vec2 v_uv;
            \\
            \\out vec4 f_color;
            \\out vec2 f_uv;
            \\
            \\uniform mat4 projection;
            \\
            \\void main() {
            \\    gl_Position = projection * vec4(v_position, 0.0, 1.0);
            \\    f_color = v_color / 255.0;
            \\    f_uv = v_uv;
            \\}
            \\
            ;

        const fragment =
            "#version " ++ version ++ "\n" ++
            \\
            \\#ifdef GL_ES
            \\precision mediump float;
            \\#endif
            \\
            \\in vec4 f_color;
            \\in vec2 f_uv;
            \\
            \\out vec4 color;
            \\
            \\uniform sampler2D sampler;
            \\uniform bool use_sampler;
            \\
            \\void main() {
            \\    if (use_sampler) {
            \\        color = texture(sampler, f_uv) * f_color;
            \\    } else {
            \\        color = f_color;
            \\    }
            \\}
            \\
            ;
    };
}
