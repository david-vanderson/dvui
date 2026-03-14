const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const wio = @import("wio");
const gl = @import("gl");
const log = std.log.scoped(.dvui_wio);

pub const kind: dvui.enums.Backend = .wio;

window: wio.Window,
size_natural: dvui.Size.Natural,
size_physical: dvui.Size.Physical,
arena: std.mem.Allocator = undefined, // assigned in begin()
mod: dvui.enums.Mod = .none,
renderer: *OpenGLRenderer,

pub fn backend(self: *@This()) dvui.Backend {
    return .init(self);
}

pub const InitOptions = struct {
    window: wio.Window,
    renderer: *OpenGLRenderer,
    size: ?wio.Size = null,
    framebuffer: ?wio.Size = null,
};

pub fn init(options: InitOptions) !@This() {
    const size_natural = options.size orelse wio.Size{ .width = 640, .height = 480 };
    const size_physical = options.framebuffer orelse wio.Size{ .width = 640, .height = 480 };

    return .{
        .window = options.window,
        .size_natural = .{ .w = @floatFromInt(size_natural.width), .h = @floatFromInt(size_natural.height) },
        .size_physical = .{ .w = @floatFromInt(size_physical.width), .h = @floatFromInt(size_physical.height) },
        .renderer = options.renderer,
    };
}

pub fn deinit(_: *@This()) void {}

pub fn nanoTime(_: *@This()) i128 {
    return std.time.nanoTimestamp();
}

pub fn sleep(_: *@This(), ns: u64) void {
    std.Thread.sleep(ns);
}

pub fn begin(self: *@This(), arena: std.mem.Allocator) !void {
    self.arena = arena;
    try self.renderer.begin();
}

pub fn end(self: *@This()) !void {
    try self.renderer.end();
}

pub fn pixelSize(self: *@This()) dvui.Size.Physical {
    return self.size_physical;
}

pub fn windowSize(self: *@This()) dvui.Size.Natural {
    return self.size_natural;
}

pub fn contentScale(_: *@This()) f32 {
    return 1;
}

pub fn drawClippedTriangles(self: *@This(), texture: ?dvui.Texture, vtx: []const dvui.Vertex, idx: []const dvui.Vertex.Index, clipr: ?dvui.Rect.Physical) !void {
    try self.renderer.drawClippedTriangles(self.size_physical, texture, vtx, idx, clipr);
}

pub fn textureCreate(self: *@This(), pixels: [*]const u8, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation, format: dvui.enums.TexturePixelFormat) !dvui.Texture {
    return self.renderer.textureCreate(pixels, width, height, interpolation, format);
}

pub fn textureUpdate(self: *@This(), texture: dvui.Texture, pixels: [*]const u8) !void {
    try self.renderer.textureUpdate(texture, pixels);
}

pub fn textureDestroy(self: *@This(), texture: dvui.Texture) void {
    self.renderer.textureDestroy(texture);
}

pub fn textureCreateTarget(self: *@This(), width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation, format: dvui.enums.TexturePixelFormat) !dvui.TextureTarget {
    return self.renderer.textureCreateTarget(width, height, interpolation, format);
}

pub fn textureReadTarget(self: *@This(), texture: dvui.TextureTarget, pixels_out: [*]u8) !void {
    try self.renderer.textureReadTarget(texture, pixels_out);
}

pub fn textureClearTarget(self: *@This(), texture: dvui.Texture.Target) void {
    self.renderer.textureClearTarget(texture);
}

pub fn textureDestroyTarget(self: *@This(), texture: dvui.Texture.Target) void {
    self.renderer.textureDestroyTarget(texture);
}

pub fn textureFromTarget(self: *@This(), target: dvui.TextureTarget) !dvui.Texture {
    return self.renderer.textureFromTarget(target);
}

pub fn textureFromTargetTemp(self: *@This(), target: dvui.TextureTarget) !dvui.Texture {
    return self.renderer.textureFromTargetTemp(target);
}

pub fn renderTarget(self: *@This(), texture: ?dvui.TextureTarget) !void {
    try self.renderer.renderTarget(texture);
}

pub fn clipboardText(self: *@This()) ![]const u8 {
    return self.window.getClipboardText(self.arena) orelse "";
}

pub fn clipboardTextSet(self: *@This(), text: []const u8) !void {
    self.window.setClipboardText(text);
}

pub fn openURL(_: *@This(), url: []const u8, _: bool) !void {
    _ = url;
}

pub fn preferredColorScheme(_: *@This()) ?dvui.enums.ColorScheme {
    return null;
}

pub fn refresh(_: *@This()) void {
    // TODO
}

pub fn native(self: *@This(), _: *dvui.Window) dvui.Window.Native {
    return switch (builtin.os.tag) {
        .windows => .{ .hwnd = self.window.backend.window },
        .macos => .{ .cocoa_window = self.window.backend.window },
        else => {},
    };
}

pub fn waitEventTimeout(_: *@This(), timeout_ms: u32) void {
    if (timeout_ms == std.math.maxInt(u32)) {
        wio.wait(.{});
    } else {
        wio.wait(.{ .timeout_ns = @as(u64, timeout_ms) * std.time.ns_per_ms });
    }
}

pub fn setTextInputRect(self: *@This(), maybe_rect: ?dvui.Rect.Natural) void {
    if (maybe_rect) |rect| {
        // FIXME: not actually the cursor position
        self.window.enableTextInput(.{ .cursor = .{ .x = std.math.lossyCast(u16, rect.x), .y = std.math.lossyCast(u16, rect.y) } });
    } else {
        self.window.disableTextInput();
    }
}

pub fn setCursor(self: *@This(), cursor: dvui.enums.Cursor) void {
    if (cursor == .hidden) {
        self.window.setCursorMode(.hidden);
        return;
    }

    self.window.setCursorMode(.normal);
    self.window.setCursor(switch (cursor) {
        .arrow => .arrow,
        .ibeam => .text,
        .wait => .busy,
        .wait_arrow => .arrow_busy,
        .crosshair => .crosshair,
        .arrow_nw_se => .size_nwse,
        .arrow_ne_sw => .size_nesw,
        .arrow_w_e => .size_ew,
        .arrow_n_s => .size_ns,
        .arrow_all => .move,
        .bad => .forbidden,
        .hand => .hand,
        .hidden => unreachable,
    });
}

pub fn addEvent(self: *@This(), win: *dvui.Window, event: wio.Event) !bool {
    switch (event) {
        .close => {
            try win.addEventWindow(.{ .action = .close });
            return false;
        },
        .size => |size| {
            self.size_natural = .{ .w = @floatFromInt(size.width), .h = @floatFromInt(size.height) };
            return false;
        },
        .framebuffer => |size| {
            self.size_physical = .{ .w = @floatFromInt(size.width), .h = @floatFromInt(size.height) };
            return false;
        },
        .char => |char| {
            var utf8: [4]u8 = undefined;
            const len = try std.unicode.utf8Encode(char, &utf8);
            return try win.addEventText(.{ .text = utf8[0..len] });
        },
        .button_press, .button_release => |button| {
            const maybe_mouse: ?dvui.enums.Button = switch (button) {
                .mouse_left => .left,
                .mouse_right => .right,
                .mouse_middle => .middle,
                .mouse_back => .four,
                .mouse_forward => .five,
                else => null,
            };

            if (maybe_mouse) |mouse| {
                return try win.addEventMouseButton(mouse, if (event == .button_press) .press else .release);
            }

            const maybe_mod: ?dvui.enums.Mod = switch (button) {
                .left_control => .lcontrol,
                .left_shift => .lshift,
                .left_alt => .lalt,
                .left_gui => .lcommand,
                .right_control => .rcontrol,
                .right_shift => .rshift,
                .right_alt => .ralt,
                .right_gui => .rcommand,
                else => null,
            };

            if (maybe_mod) |mod| {
                if (event == .button_press) {
                    self.mod.combine(mod);
                } else {
                    self.mod.unset(mod);
                }
            }

            return try win.addEventKey(.{
                .code = buttonToDvuiKey(button),
                .action = if (event == .button_press) .down else .up,
                .mod = self.mod,
            });
        },
        .button_repeat => |button| return try win.addEventKey(.{
            .code = buttonToDvuiKey(button),
            .action = .repeat,
            .mod = self.mod,
        }),
        .mouse => |mouse| {
            const x: f32 = @floatFromInt(mouse.x);
            const y: f32 = @floatFromInt(mouse.y);
            const scale = self.pixelSize().w / self.windowSize().w;
            return try win.addEventMouseMotion(.{ .pt = .{ .x = x * scale, .y = y * scale } });
        },
        .scroll_vertical => |ticks| return try win.addEventMouseWheel(ticks * dvui.scroll_speed, .vertical),
        .scroll_horizontal => |ticks| return try win.addEventMouseWheel(ticks * dvui.scroll_speed, .horizontal),
        else => return false,
    }
}

pub fn main() !void {
    const app = dvui.App.get() orelse return error.DvuiAppNotDefined;
    const config = app.config.get();

    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator = debug_allocator.allocator();

    try wio.init(allocator, .{});
    defer wio.deinit();

    var window = try wio.createWindow(.{
        .title = config.title,
        .size = .{ .width = @intFromFloat(config.size.w), .height = @intFromFloat(config.size.h) },
        .scale = 1,
        .opengl = .{
            .major_version = 3,
            .minor_version = 2,
            .profile = .core,
        },
    });
    defer window.destroy();

    window.makeContextCurrent();
    if (config.vsync) {
        window.swapInterval(1);
    }

    var renderer = try OpenGLRenderer.init(allocator, wio.glGetProcAddress, "150");
    defer renderer.deinit();

    var back = try @This().init(.{ .window = window, .renderer = &renderer });
    defer back.deinit();

    var win = try dvui.Window.init(@src(), allocator, back.backend(), config.window_init_options);
    defer win.deinit();

    if (app.initFn) |initFn| {
        try win.begin(win.frame_time_ns);
        try initFn(&win);
        _ = try win.end(.{});
    }
    defer if (app.deinitFn) |deinitFn| deinitFn();

    while (true) {
        wio.update();
        while (window.getEvent()) |event| {
            _ = try back.addEvent(&win, event);
        }

        const time = win.beginWait(true);
        try win.begin(time);
        var res = try app.frameFn();
        for (dvui.events()) |*e| {
            if (!e.handled) {
                if (e.evt == .window and e.evt.window.action == .close) res = .close;
            }
        }
        const end_ms = try win.end(.{});
        if (res != .ok) break;

        back.setTextInputRect(win.textInputRequested());
        back.setCursor(win.cursorRequested());

        window.swapBuffers();

        const wait_ms = win.waitTime(end_ms);
        back.waitEventTimeout(wait_ms);
    }
}

/// OpenGL 3.0+ renderer.
///
/// After rendering, the following state will be changed:
/// - GL_CURRENT_PROGRAM
/// - GL_VERTEX_ARRAY_BINDING
/// - GL_VIEWPORT
/// - GL_ACTIVE_TEXTURE
/// - GL_TEXTURE_BINDING_2D
/// - GL_DRAW_FRAMEBUFFER_BINDING
/// - GL_BLEND
/// - GL_BLEND_SRC_RGB
/// - GL_BLEND_SRC_ALPHA
/// - GL_BLEND_DST_RGB
/// - GL_BLEND_DST_ALPHA
/// - GL_SCISSOR_TEST
pub const OpenGLRenderer = struct {
    allocator: std.mem.Allocator,
    render_target_size: ?dvui.Size.Physical = null,
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

    pub fn begin(self: *@This()) !void {
        gl.useProgram(self.program);
        gl.bindVertexArray(self.vao);

        gl.enable(gl.BLEND);
        gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
    }

    pub fn end(_: *@This()) !void {}

    pub fn drawClippedTriangles(self: *@This(), size_physical: dvui.Size.Physical, maybe_texture: ?dvui.Texture, vtx: []const dvui.Vertex, idx: []const dvui.Vertex.Index, maybe_clipr: ?dvui.Rect.Physical) !void {
        const size = self.render_target_size orelse size_physical;
        gl.viewport(0, 0, @intFromFloat(size.w), @intFromFloat(size.h));

        if (maybe_clipr) |clipr| {
            gl.enable(gl.SCISSOR_TEST);
            gl.scissor(
                @intFromFloat(clipr.x),
                @intFromFloat(if (self.render_target_size == null) size_physical.h - clipr.y - clipr.h else clipr.y),
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
        gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, @bitCast(texture.width), @bitCast(texture.height), gl.RGBA, gl.UNSIGNED_INT_8_8_8_8, pixels);
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
        gl.getTexImage(gl.TEXTURE_2D, 0, gl.RGBA, gl.UNSIGNED_INT_8_8_8_8, pixels_out);
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
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, @bitCast(width), @bitCast(height), 0, gl.RGBA, gl.UNSIGNED_INT_8_8_8_8, pixels);

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
};

fn buttonToDvuiKey(button: wio.Button) dvui.enums.Key {
    return switch (button) {
        .mouse_left, .mouse_right, .mouse_middle, .mouse_back, .mouse_forward => unreachable,
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
        .@"1" => .one,
        .@"2" => .two,
        .@"3" => .three,
        .@"4" => .four,
        .@"5" => .five,
        .@"6" => .six,
        .@"7" => .seven,
        .@"8" => .eight,
        .@"9" => .nine,
        .@"0" => .zero,
        .enter => .enter,
        .escape => .escape,
        .backspace => .backspace,
        .tab => .tab,
        .space => .space,
        .minus => .minus,
        .equals => .equal,
        .left_bracket => .left_bracket,
        .right_bracket => .right_bracket,
        .backslash => .backslash,
        .semicolon => .semicolon,
        .apostrophe => .apostrophe,
        .grave => .grave,
        .comma => .comma,
        .dot => .period,
        .slash => .slash,
        .caps_lock => .caps_lock,
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
        .print_screen => .print,
        .scroll_lock => .scroll_lock,
        .pause => .pause,
        .insert => .insert,
        .home => .home,
        .page_up => .page_up,
        .delete => .delete,
        .end => .end,
        .page_down => .page_down,
        .right => .right,
        .left => .left,
        .down => .down,
        .up => .up,
        .num_lock => .num_lock,
        .kp_slash => .kp_divide,
        .kp_star => .kp_multiply,
        .kp_minus => .kp_subtract,
        .kp_plus => .kp_add,
        .kp_enter => .kp_enter,
        .kp_1 => .kp_1,
        .kp_2 => .kp_2,
        .kp_3 => .kp_3,
        .kp_4 => .kp_4,
        .kp_5 => .kp_5,
        .kp_6 => .kp_6,
        .kp_7 => .kp_7,
        .kp_8 => .kp_8,
        .kp_9 => .kp_9,
        .kp_0 => .kp_0,
        .kp_dot => .kp_decimal,
        .iso_backslash => .backslash,
        .application => .menu,
        .kp_equals => .kp_equal,
        .f13 => .f13,
        .f14 => .f14,
        .f15 => .f15,
        .f16 => .f16,
        .f17 => .f17,
        .f18 => .f18,
        .f19 => .f19,
        .f20 => .f20,
        .f21 => .f21,
        .f22 => .f22,
        .f23 => .f23,
        .f24 => .f24,
        .left_control => .left_control,
        .left_shift => .left_shift,
        .left_alt => .left_alt,
        .left_gui => .left_command,
        .right_control => .right_control,
        .right_shift => .right_shift,
        .right_alt => .right_alt,
        .right_gui => .right_command,
        .kp_comma, .international1, .international2, .international3, .international4, .international5, .lang1, .lang2 => .unknown,
    };
}
