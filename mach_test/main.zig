const std = @import("std");
const mach = @import("mach");
const gpu = @import("gpu");
const glfw = @import("glfw");
const zm = @import("zmath");
const zigimg = @import("zigimg");
const gui = @import("gui/gui.zig");


var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

app_engine: *mach.Engine,
pipeline: gpu.RenderPipeline,

win: gui.Window,

uniform_buffer: gpu.Buffer,
uniform_buffer_size: u32,
uniform_buffer_len: u32,
sampler: gpu.Sampler,

texture: ?*anyopaque,
clipr: gui.Rect,
vtx: std.ArrayList(gui.Vertex),
idx: std.ArrayList(u32),

encoder: gpu.CommandEncoder,

vertex_buffer: gpu.Buffer,
index_buffer: gpu.Buffer,
vertex_buffer_len: u32,
index_buffer_len: u32,
vertex_buffer_size: u32,
index_buffer_size: u32,

const App = @This();

pub const UniformBufferObject = struct {
    // dawn gives me an error when trying to align uniforms to less than this
    const Size = 256;
    mat: zm.Mat,
    use_tex: i32,
};

pub const Vertex = struct {
    pos: gui.Point,
    col: @Vector(4, f32),
    uv: @Vector(2, f32),
};

fn textureCreate(userdata: ?*anyopaque, pixels: []const u8, width: u32, height: u32) *anyopaque {
  const app = @ptrCast(*App, @alignCast(@alignOf(App), userdata));

  const img_size = gpu.Extent3D{ .width = width, .height = height };
  var texture = gpa.create(gpu.Texture) catch unreachable;
  texture.* = app.app_engine.device.createTexture(&.{
      .size = img_size,
      .format = .rgba8_unorm,
      .usage = .{
          .texture_binding = true,
          .copy_dst = true,
          .render_attachment = true,
      },
  });

  const data_layout = gpu.Texture.DataLayout{
      .bytes_per_row = @intCast(u32, width * 4),
      .rows_per_image = @intCast(u32, height),
  };

  var queue = app.app_engine.device.getQueue();
  queue.writeTexture(&.{ .texture = texture.* }, &data_layout, &img_size, u8, pixels);

  return texture;
}

fn textureDestroy(userdata: ?*anyopaque, texture: *anyopaque) void {
    const app = @ptrCast(*App, @alignCast(@alignOf(App), userdata));
    _ = app;
    if (app.texture != null and app.texture.? == texture) {
      // flush so we don't accidentally release this texture before we use it
      app.flushRender();
    }
    const tex = @ptrCast(*gpu.Texture, @alignCast(@alignOf(gpu.Texture), texture));
    tex.release();
    gpa.destroy(tex);
}


fn renderGeometry(userdata: ?*anyopaque, tex: ?*anyopaque, vtx: []gui.Vertex, idx: []u32) void {
    const clipr = gui.WindowRectPixels().intersect(gui.ClipGet());
    if (clipr.empty()) {
      return;
    }

    const app = @ptrCast(*App, @alignCast(@alignOf(App), userdata));

    //std.debug.print("renderGeometry {} {x}\n", .{clipr, tex});

    if (clipr.x != app.clipr.x or
        clipr.y != app.clipr.y or
        clipr.w != app.clipr.w or
        clipr.h != app.clipr.h or
        (app.texture == null and tex != null) or
        (app.texture != null and tex == null) or
        (app.texture != null and tex != null and app.texture.? != tex.?)) {
      // clip rect or texture changed, can't coalesce so flush
      app.flushRender();
    }

    app.clipr = clipr;
    app.texture = tex;

    for (idx) |id| {
      app.idx.append(id + @intCast(u32, app.vtx.items.len)) catch unreachable;
    }

    for (vtx) |v| {
      app.vtx.append(v) catch unreachable;
    }
}

fn flushRender(app: *App) void {
    const engine = app.app_engine;

    if (app.vtx.items.len == 0) {
      return;
    }

    //std.debug.print("  flush {d} {d}\n", .{app.uniform_buffer_size, app.uniform_buffer_len});

    if (app.uniform_buffer_size < app.uniform_buffer_len + 1 or
        app.vertex_buffer_size < app.vertex_buffer_len + app.vtx.items.len or
        app.index_buffer_size < app.index_buffer_len + app.idx.items.len) {

      if (app.uniform_buffer_size < app.uniform_buffer_len + 1) {
        app.uniform_buffer.release();

        app.uniform_buffer_size = app.uniform_buffer_len + 1;

        //std.debug.print("creating uniform buffer {d}\n", .{app.uniform_buffer_size});
        app.uniform_buffer = engine.device.createBuffer(&.{
            .usage = .{ .copy_dst = true, .uniform = true },
            .size = UniformBufferObject.Size * app.uniform_buffer_size,
            .mapped_at_creation = false,
        });

        app.uniform_buffer_len = 0;
      }

      if (app.vertex_buffer_size < app.vertex_buffer_len + app.vtx.items.len) {
        app.vertex_buffer.release();

        app.vertex_buffer_size = app.vertex_buffer_len + @intCast(u32, app.vtx.items.len);
          
        //std.debug.print("creating vertex buffer {d}\n", .{app.vertex_buffer_size});
        app.vertex_buffer = engine.device.createBuffer(&.{
            .usage = .{ .vertex = true, .copy_dst = true },
            .size = @sizeOf(Vertex) * app.vertex_buffer_size,
            .mapped_at_creation = false,
        });

        app.vertex_buffer_len = 0;
      }

      if (app.index_buffer_size < app.index_buffer_len + app.idx.items.len) {
        app.index_buffer.release();

        app.index_buffer_size = app.index_buffer_len + @intCast(u32, app.idx.items.len);

        //std.debug.print("creating index buffer {d}\n", .{app.index_buffer_size});
        app.index_buffer = engine.device.createBuffer(&.{
            .usage = .{ .index = true, .copy_dst = true },
            .size = @sizeOf(u32) * app.index_buffer_size,
            .mapped_at_creation = false,
        });

        app.index_buffer_len = 0;
      }
    }

    const back_buffer_view = engine.swap_chain.?.getCurrentTextureView();
    defer back_buffer_view.release();

    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .resolve_target = null,
        .clear_value = std.mem.zeroes(gpu.Color),
        .load_op = .load,
        .store_op = .store,
    };

    const default_texture_ptr = gui.IconTexture("default_texture", gui.icons.papirus.actions.media_playback_start_symbolic, 1.0).texture;
    const default_texture = @ptrCast(*gpu.Texture, @alignCast(@alignOf(gpu.Texture), default_texture_ptr)).*;

    var texture: ?gpu.Texture = null;
    if (app.texture) |t| {
      texture = @ptrCast(*gpu.Texture, @alignCast(@alignOf(gpu.Texture), t)).*;
    }

    {
        const model = zm.translation(-gui.WindowRectPixels().w / 2, gui.WindowRectPixels().h / 2, 0);
        const view = zm.lookAtLh(
            zm.f32x4(0, 0, 1, 1),
            zm.f32x4(0, 0, 0, 1),
            zm.f32x4(0, -1, 0, 0),
        );
        const proj = zm.orthographicLh(gui.WindowRectPixels().w, gui.WindowRectPixels().h, 1, 0);
        const mvp = zm.mul(zm.mul(view, model), proj);
        const ubo = UniformBufferObject{
            .mat = mvp,
            .use_tex = if (texture != null) 1 else 0,
        };
        app.encoder.writeBuffer(app.uniform_buffer, UniformBufferObject.Size * app.uniform_buffer_len, UniformBufferObject, &.{ubo});
    }

    const bind_group = engine.device.createBindGroup(
        &gpu.BindGroup.Descriptor{
            .layout = app.pipeline.getBindGroupLayout(0),
            .entries = &.{
                gpu.BindGroup.Entry.buffer(0, app.uniform_buffer, UniformBufferObject.Size * app.uniform_buffer_len, @sizeOf(UniformBufferObject)),
                gpu.BindGroup.Entry.sampler(1, app.sampler),
                gpu.BindGroup.Entry.textureView(2, (texture orelse default_texture).createView(&gpu.TextureView.Descriptor{})),
            },
        },
    );

    app.uniform_buffer_len += 1;

    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arena = arena_allocator.allocator();
    defer arena_allocator.deinit();

    var vertices = arena.alloc(Vertex, app.vtx.items.len) catch unreachable; 
    for (app.vtx.items) |vin, i| {
      vertices[i] = Vertex{.pos = vin.pos, .col = .{
        @intToFloat(f32, vin.col.r) / 255.0,
        @intToFloat(f32, vin.col.g) / 255.0,
        @intToFloat(f32, vin.col.b) / 255.0,
        @intToFloat(f32, vin.col.a) / 255.0 },
        .uv = vin.uv };
    }
    //std.debug.print("vertexes {d} + {d} indexes {d} + {d}\n", .{app.vertex_buffer_len, app.vtx.items.len, app.index_buffer_len, app.idx.items.len});
    app.encoder.writeBuffer(app.vertex_buffer, app.vertex_buffer_len * @sizeOf(Vertex), Vertex, vertices);
    app.encoder.writeBuffer(app.index_buffer, app.index_buffer_len * @sizeOf(u32), u32, app.idx.items);


    const render_pass_info = gpu.RenderPassEncoder.Descriptor{
        .color_attachments = &.{color_attachment},
        .depth_stencil_attachment = null,
    };
    const pass = app.encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(app.pipeline);
    pass.setVertexBuffer(0, app.vertex_buffer, @sizeOf(Vertex) * app.vertex_buffer_len, @sizeOf(Vertex) * @intCast(u32, app.vtx.items.len));
    pass.setIndexBuffer(app.index_buffer, .uint32, @sizeOf(u32) * app.index_buffer_len, @sizeOf(u32) * @intCast(u32, app.idx.items.len));
    pass.setBindGroup(0, bind_group, &.{});

    pass.setScissorRect(@floatToInt(u32, app.clipr.x), @floatToInt(u32, app.clipr.y), @floatToInt(u32, @ceil(app.clipr.w)), @floatToInt(u32, @ceil(app.clipr.h)));

    pass.drawIndexed(@intCast(u32, app.idx.items.len), 1, 0, 0, 0);
    pass.end();
    pass.release();
    bind_group.release();

    app.vertex_buffer_len += @intCast(u32, app.vtx.items.len);
    app.index_buffer_len += @intCast(u32, app.idx.items.len);

    app.vtx.clearRetainingCapacity();
    app.idx.clearRetainingCapacity();
}


pub fn init(app: *App, engine: *mach.Engine) !void {

    app.app_engine = engine;
    app.uniform_buffer_size = 1;
    app.uniform_buffer_len = 0;
    app.uniform_buffer = engine.device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = UniformBufferObject.Size * app.uniform_buffer_size,
        .mapped_at_creation = false,
    });

    app.sampler = engine.device.createSampler(&.{
        .mag_filter = .linear,
        .min_filter = .linear,
    });

    app.texture = null;
    app.clipr = gui.Rect{};
    app.vertex_buffer_size = 1000;
    app.index_buffer_size = 1000;
    app.vertex_buffer_len = 0;
    app.index_buffer_len = 0;
    app.vertex_buffer = engine.device.createBuffer(&.{
        .usage = .{ .vertex = true, .copy_dst = true },
        .size = @sizeOf(Vertex) * app.vertex_buffer_size,
        .mapped_at_creation = false,
    });
    app.index_buffer = engine.device.createBuffer(&.{
        .usage = .{ .index = true, .copy_dst = true },
        .size = @sizeOf(u32) * app.index_buffer_size,
        .mapped_at_creation = false,
    });
    
    const vs_module = engine.device.createShaderModule(&.{
        .label = "my vertex shader",
        .code = .{ .wgsl = @embedFile("vert.wgsl") },
    });

    const vertex_attributes = [_]gpu.VertexAttribute{
        .{ .format = .float32x2, .offset = @offsetOf(Vertex, "pos"), .shader_location = 0 },
        .{ .format = .float32x4, .offset = @offsetOf(Vertex, "col"), .shader_location = 1 },
        .{ .format = .float32x2, .offset = @offsetOf(Vertex, "uv"), .shader_location = 2 },
    };
    const vertex_buffer_layout = gpu.VertexBufferLayout{
        .array_stride = @sizeOf(Vertex),
        .step_mode = .vertex,
        .attribute_count = vertex_attributes.len,
        .attributes = &vertex_attributes,
    };

    const fs_module = engine.device.createShaderModule(&.{
        .label = "my fragment shader",
        .code = .{ .wgsl = @embedFile("frag.wgsl") },
    });

    // Fragment state
    const blend = gpu.BlendState{
        .color = .{
            .operation = .add,
            .src_factor = .src_alpha,
            .dst_factor = .one_minus_src_alpha,
        },
        .alpha = .{
            .operation = .add,
            .src_factor = .src_alpha,
            .dst_factor = .one_minus_src_alpha,
        },
    };
    const color_target = gpu.ColorTargetState{
        .format = engine.swap_chain_format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMask.all,
    };
    const fragment = gpu.FragmentState{
        .module = fs_module,
        .entry_point = "main",
        .targets = &.{color_target},
        .constants = null,
    };
    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &fragment,
        .vertex = .{
            .module = vs_module,
            .entry_point = "main",
            .buffers = &.{vertex_buffer_layout},
        },
        .primitive = .{
            .cull_mode = .none,
            .topology = .triangle_list,
        },
    };

    app.pipeline = engine.device.createRenderPipeline(&pipeline_descriptor);

    vs_module.release();
    fs_module.release();

    app.win = gui.Window.init(gpa, app, renderGeometry, textureCreate, textureDestroy);
}

pub fn deinit(app: *App, _: *mach.Engine) void {
    _ = app;
}

fn toGUIKey(key: mach.Key) gui.keys.Key {
    return switch (key) {
        .a => .a,
        else => .z,
    };
}

pub fn update(app: *App, engine: *mach.Engine) !bool {

    //std.debug.print("UPDATE\n", .{});
    app.clipr = gui.Rect{};
    app.texture = null;

    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arena = arena_allocator.allocator();
    defer arena_allocator.deinit();

    app.vtx = std.ArrayList(gui.Vertex).init(arena);
    app.idx = std.ArrayList(u32).init(arena);

    const size = engine.getWindowSize();
    const psize = engine.getFramebufferSize();
    var nstime = app.win.beginWait();
    app.win.begin(arena, nstime, size.width, size.height, psize.width, psize.height);

    while (engine.pollEvent()) |event| {
        switch (event) {
            .key_press => |ev| {
                if (ev.key == .space) {
                    engine.setShouldClose(true);
                }
                app.win.addEventKey(toGUIKey(ev.key), gui.keys.Mod.none, .down);
            },
            .key_release => |ev| {
                app.win.addEventKey(toGUIKey(ev.key), gui.keys.Mod.none, .up);
            },
            .mouse_motion => |mm| {
                app.win.addEventMouseMotion(@floatCast(f32, mm.x), @floatCast(f32, mm.y));
            },
            .mouse_press => |mb| {
                switch (mb.button) {
                  .left => app.win.addEventMouseButton(.leftdown),
                  .right => app.win.addEventMouseButton(.rightdown),
                  else => {},
                }
            },
            .mouse_release => |mb| {
                switch (mb.button) {
                  .left => app.win.addEventMouseButton(.leftup),
                  .right => app.win.addEventMouseButton(.rightup),
                  else => {},
                }
            },
            .scroll => |s| {
                app.win.addEventMouseWheel(@floatCast(f32, s.yoffset));
            },
            //else => {},
        }
    }

    app.win.endEvents();

    //std.debug.print("create encoder\n", .{});
    app.encoder = engine.device.createCommandEncoder(null);
    app.uniform_buffer_len = 0;
    app.vertex_buffer_len = 0;
    app.index_buffer_len = 0;

    TestGui();

    const end_micros = app.win.end();

    app.flushRender();
    var command = app.encoder.finish(null);
    //std.debug.print("  release encoder\n", .{});
    app.encoder.release();

    var queue = app.app_engine.device.getQueue();
    queue.submit(&.{command});
    command.release();

    engine.swap_chain.?.present();

    app.win.wait(end_micros, null);

    return true;
}


pub fn TestGui() void {
    {
      var window_box = gui.Box(@src(), 0, .vertical, .{.expand = .both, .color_style = .window, .background = true});
      defer window_box.deinit();

      var box = gui.Box(@src(), 0, .vertical, .{.expand = .both});
      defer box.deinit();

      var paned = gui.Paned(@src(), 0, .horizontal, 400, .{.expand = .both});
      const collapsed = paned.collapsed();

      podcastSide(paned);
      episodeSide(paned);

      paned.deinit();

      if (collapsed) {
        player();
      }
    }
}

var show_dialog: bool = false;

fn podcastSide(paned: *gui.PanedWidget) void {
  var box = gui.Box(@src(), 0, .vertical, .{.expand = .both});
  defer box.deinit();

  {
    var overlay = gui.Overlay(@src(), 0, .{.expand = .horizontal});
    defer overlay.deinit();

    {
      var menu = gui.Menu(@src(), 0, .horizontal, .{.expand = .horizontal});
      defer menu.deinit();

      gui.Spacer(@src(), 0, .{.expand = .horizontal});

      if (gui.MenuItemLabel(@src(), 0, "Hello", true, .{})) |r| {
        var fw = gui.Popup(@src(), 0, gui.Rect.fromPoint(gui.Point{.x = r.x, .y = r.y + r.h}), &menu.submenus_activated, menu, .{});
        defer fw.deinit();
        if (gui.MenuItemLabel(@src(), 0, "Add RSS", false, .{})) |rr| {
          _ = rr;
          show_dialog = true;
          gui.MenuGet().?.close();
        }
      }
    }

    gui.Label(@src(), 0, "fps {d}", .{@round(gui.FPS())}, .{});
    //std.debug.print("fps: {d}\n", .{@round(gui.FPS())});
  }

  if (show_dialog) {
    var dialog = gui.FloatingWindow(@src(), 0, true, null, &show_dialog, .{});
    defer dialog.deinit();

    gui.LabelNoFormat(@src(), 0, "Add RSS Feed", .{.gravity = .center});

    const TextEntryText = struct {
      //var text = array(u8, 100, "abcdefghijklmnopqrstuvwxyz");
      var text1 = array(u8, 100, "");
      fn array(comptime T: type, comptime size: usize, items: ?[]const T) [size]T {
        var output = std.mem.zeroes([size]T);
        if (items) |slice| std.mem.copy(T, &output, slice);
        return output;
      }
    };

    gui.TextEntry(@src(), 0, 26.0, &TextEntryText.text1, .{.gravity = .center});

    var box2 = gui.Box(@src(), 0, .horizontal, .{.gravity = .right});
    defer box2.deinit();
    if (gui.Button(@src(), 0, "Ok", .{})) {
      dialog.close();
    }
    if (gui.Button(@src(), 0, "Cancel", .{})) {
      dialog.close();
    }
  }

  var scroll = gui.ScrollArea(@src(), 0, null, .{.expand = .both, .color_style = .window, .background = false});

  const oo3 = gui.Options{
    .expand = .horizontal,
    .gravity = .left,
    .color_style = .content,
  };

  var i: usize = 1;
  var buf: [100]u8 = undefined;
  while (i < 8) : (i += 1) {
    const title = std.fmt.bufPrint(&buf, "Podcast {d}", .{i}) catch unreachable;
    var margin: gui.Rect = .{.x = 8, .y = 0, .w = 8, .h = 0};
    var border: gui.Rect = .{.x = 1, .y = 0, .w = 1, .h = 0};
    var corner = gui.Rect.all(0);

    if (i != 1) {
      gui.Separator(@src(), i, oo3.override(.{.margin = margin, .min_size = .{.w = 1, .h = 1}, .border = .{.x = 1, .y = 1, .w = 0, .h = 0}}));
    }

    if (i == 1) {
      margin.y = 8;
      border.y = 1;
      corner.x = 9;
      corner.y = 9;
    }
    else if (i == 7) {
      margin.h = 8;
      border.h = 1;
      corner.w = 9;
      corner.h = 9;
    }

    if (gui.Button(@src(), i, title, oo3.override(.{
        .margin = margin,
        .border = border,
        .corner_radius = corner,
        .padding = gui.Rect.all(8),
        }))) {
      paned.showOther();
    }
  }

  scroll.deinit();

  if (!paned.collapsed()) {
    player();
  }
}

fn episodeSide(paned: *gui.PanedWidget) void {
  var box = gui.Box(@src(), 0, .vertical, .{.expand = .both});
  defer box.deinit();

  if (paned.collapsed()) {
    var menu = gui.Menu(@src(), 0, .horizontal, .{.expand = .horizontal});
    defer menu.deinit();

    if (gui.MenuItemLabel(@src(), 0, "Back", false, .{})) |rr| {
      _ = rr;
      paned.showOther();
    }
  }

  var scroll = gui.ScrollArea(@src(), 0, null, .{.expand = .both, .background = false});
  defer scroll.deinit();

  var i: usize = 0;
  while (i < 10) : (i += 1) {
    var tl = gui.TextLayout(@src(), i, .{.expand = .horizontal});

    var cbox = gui.Box(@src(), 0, .vertical, gui.Options{.gravity = .upright});

    _ = gui.ButtonIcon(@src(), 0, 18, "play",
      gui.icons.papirus.actions.media_playback_start_symbolic, .{.padding = gui.Rect.all(6)});
    _ = gui.ButtonIcon(@src(), 0, 18, "more",
      gui.icons.papirus.actions.view_more_symbolic, .{.padding = gui.Rect.all(6)});

    cbox.deinit();

    var f = gui.ThemeGet().font_heading;
    f.line_skip_factor = 1.3;
    tl.addText("Episode Title\n", .{.font_style = .custom, .font_custom = f});
    const lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.";
    tl.addText(lorem, .{});
    tl.deinit();
  }
}

fn player() void {
  const oo = gui.Options{
    .expand = .horizontal,
    .color_style = .content,
  };

  var box2 = gui.Box(@src(), 0, .vertical, oo.override(.{.background = true}));
  defer box2.deinit();

  gui.Label(@src(), 0, "Title of the playing episode", .{}, oo.override(.{
    .margin = gui.Rect{.x = 8, .y = 4, .w = 8, .h = 4},
    .font_style = .heading,
  }));

  var box3 = gui.Box(@src(), 0, .horizontal, oo.override(.{.padding = .{.x = 4, .y = 0, .w = 4, .h = 4}}));
  defer box3.deinit();

  const oo2 = gui.Options{.expand = .horizontal, .gravity = .center};

  _ = gui.ButtonIcon(@src(), 0, 20, "back",
    gui.icons.papirus.actions.media_seek_backward_symbolic, oo2);

  gui.Label(@src(), 0, "0.00%", .{}, oo2.override(.{.color_style = .content}));

  _ = gui.ButtonIcon(@src(), 0, 20, "forward",
    gui.icons.papirus.actions.media_seek_forward_symbolic, oo2);

  _ = gui.ButtonIcon(@src(), 0, 20, "play",
    gui.icons.papirus.actions.media_playback_start_symbolic, oo2);

}

