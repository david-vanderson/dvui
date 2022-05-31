const std = @import("std");
const mach = @import("mach");
const gpu = @import("gpu");
const glfw = @import("glfw");
const zm = @import("zmath");
const zigimg = @import("zigimg");
const gui = @import("gui/gui.zig");


var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();
var pending_events = std.ArrayList(gui.Event).init(gpa);

app_engine: *mach.Engine,
pipeline: gpu.RenderPipeline,

win: gui.Window,

uniform_buffer: gpu.Buffer,
sampler: gpu.Sampler,
vertex_buffer: gpu.Buffer,
index_buffer: gpu.Buffer,
const vertex_buffer_size = 10000;
const index_buffer_size = 10000;

const App = @This();

pub const UniformBufferObject = struct {
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
  texture.* = app.app_engine.gpu_driver.device.createTexture(&.{
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

  var queue = app.app_engine.gpu_driver.device.getQueue();
  queue.writeTexture(&.{ .texture = texture.* }, &data_layout, &img_size, u8, pixels);

  return texture;
}

fn textureDestroy(userdata: ?*anyopaque, texture: *anyopaque) void {
    _ = userdata;
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
    const engine = app.app_engine;
    var texture: ?gpu.Texture = null;
    if (tex) |t| {
      texture = @ptrCast(*gpu.Texture, @alignCast(@alignOf(gpu.Texture), t)).*;
    }

    const encoder = engine.gpu_driver.device.createCommandEncoder(null);

    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arena = arena_allocator.allocator();
    defer arena_allocator.deinit();

    var vertices = arena.alloc(Vertex, vtx.len) catch unreachable; 
    for (vtx) |vin, i| {
      vertices[i] = Vertex{.pos = vin.pos, .col = .{
        @intToFloat(f32, vin.col.r) / 255.0,
        @intToFloat(f32, vin.col.g) / 255.0,
        @intToFloat(f32, vin.col.b) / 255.0,
        @intToFloat(f32, vin.col.a) / 255.0 },
        .uv = vin.uv };
    }
    encoder.writeBuffer(app.vertex_buffer, 0, Vertex, vertices);

    //const vertex_buffer = engine.gpu_driver.device.createBuffer(&.{
    //    .usage = .{ .vertex = true },
    //    .size = @sizeOf(Vertex) * vtx.len,
    //    .mapped_at_creation = true,
    //});
    //defer vertex_buffer.release();
    //var vertex_mapped = vertex_buffer.getMappedRange(Vertex, 0, vtx.len);
    //for (vtx) |vin, i| {
    //  vertex_mapped[i] = Vertex{.pos = vin.pos, .col = .{
    //    @intToFloat(f32, vin.col.r) / 255.0,
    //    @intToFloat(f32, vin.col.g) / 255.0,
    //    @intToFloat(f32, vin.col.b) / 255.0,
    //    @intToFloat(f32, vin.col.a) / 255.0 },
    //    .uv = vin.uv };
    //}

    //vertex_buffer.unmap();

    encoder.writeBuffer(app.index_buffer, 0, u32, idx);

    //const index_buffer = engine.gpu_driver.device.createBuffer(&.{
    //    .usage = .{ .index = true },
    //    .size = @sizeOf(u32) * idx.len,
    //    .mapped_at_creation = true,
    //});
    //defer index_buffer.release();
    //var index_mapped = index_buffer.getMappedRange(u32, 0, idx.len);
    //std.mem.copy(u32, index_mapped, idx);
    //index_buffer.unmap();

    const back_buffer_view = engine.gpu_driver.swap_chain.?.getCurrentTextureView();
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

    const bind_group = engine.gpu_driver.device.createBindGroup(
        &gpu.BindGroup.Descriptor{
            .layout = app.pipeline.getBindGroupLayout(0),
            .entries = &.{
                gpu.BindGroup.Entry.buffer(0, app.uniform_buffer, 0, @sizeOf(UniformBufferObject)),
                gpu.BindGroup.Entry.sampler(1, app.sampler),
                gpu.BindGroup.Entry.textureView(2, (texture orelse default_texture).createView(&gpu.TextureView.Descriptor{})),
            },
        },
    );


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
        encoder.writeBuffer(app.uniform_buffer, 0, UniformBufferObject, &.{ubo});
    }


    const render_pass_info = gpu.RenderPassEncoder.Descriptor{
        .color_attachments = &.{color_attachment},
        .depth_stencil_attachment = null,
    };
    const pass = encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(app.pipeline);
    pass.setVertexBuffer(0, app.vertex_buffer, 0, @sizeOf(Vertex) * vtx.len);
    pass.setIndexBuffer(app.index_buffer, .uint32, 0, @sizeOf(u32) * idx.len);
    pass.setBindGroup(0, bind_group, &.{});

    pass.setScissorRect(@floatToInt(u32, clipr.x), @floatToInt(u32, clipr.y), @floatToInt(u32, @ceil(clipr.w)), @floatToInt(u32, @ceil(clipr.h)));
    pass.drawIndexed(@intCast(u32, idx.len), 1, 0, 0, 0);
    pass.end();
    pass.release();
    bind_group.release();

    var command = encoder.finish(null);
    encoder.release();

    var queue = app.app_engine.gpu_driver.device.getQueue();
    queue.submit(&.{command});
    command.release();
}

pub fn init(app: *App, engine: *mach.Engine) !void {

    app.uniform_buffer = engine.gpu_driver.device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = @sizeOf(UniformBufferObject),
        .mapped_at_creation = false,
    });

    app.sampler = engine.gpu_driver.device.createSampler(&.{
        .mag_filter = .linear,
        .min_filter = .linear,
    });

    app.vertex_buffer = engine.gpu_driver.device.createBuffer(&.{
        .usage = .{ .vertex = true, .copy_dst = true },
        .size = @sizeOf(Vertex) * vertex_buffer_size,
        .mapped_at_creation = false,
    });

    app.index_buffer = engine.gpu_driver.device.createBuffer(&.{
        .usage = .{ .index = true, .copy_dst = true },
        .size = @sizeOf(u32) * index_buffer_size,
        .mapped_at_creation = false,
    });


    const mouse_motion_callback = struct {
      fn callback(window: glfw.Window, xpos: f64, ypos: f64) void {
        _ = window;
        //std.debug.print("mouse motion {d} {d}\n", .{xpos, ypos});
        var e = gui.Event{
          .evt = gui.AnyEvent{.mouse = gui.MouseEvent{
            .state = .motion,
            .p = .{.x = @floatCast(f32, xpos), .y = @floatCast(f32, ypos)},
            .dp = .{},
            .wheel = 0,
            .floating_win = undefined,
          }}
        };
        pending_events.append(e) catch unreachable;
      }
    }.callback;
    engine.core.internal.window.setCursorPosCallback(mouse_motion_callback);

    const mouse_button_callback = struct {
      fn callback(window: glfw.Window, button: glfw.mouse_button.MouseButton, action: glfw.Action, mods: glfw.Mods) void {
        _ = window;
        _ = mods;
        //std.debug.print("mouse button {x} {x} {x}\n", .{button, action, mods});
        var state: gui.MouseEvent.Kind = undefined;
        switch (button) {
          .left => switch (action) {
            .press => {state = .leftdown;},
            .release => {state = .leftup;},
            else => {},
          },
          .right => switch (action) { 
            .press => {state = .rightdown;},
            .release => {state = .rightup;},
            else => {},
          },
          else => {},
        }

        var e = gui.Event{
          .evt = gui.AnyEvent{.mouse = gui.MouseEvent{
            .state = state,
            .p = .{},
            .dp = .{},
            .wheel = 0,
            .floating_win = undefined,
          }}
        };
        pending_events.append(e) catch unreachable;
      }
    }.callback;
    engine.core.internal.window.setMouseButtonCallback(mouse_button_callback);

    const vs_module = engine.gpu_driver.device.createShaderModule(&.{
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

    const fs_module = engine.gpu_driver.device.createShaderModule(&.{
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
        .format = engine.gpu_driver.swap_chain_format,
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

    app.pipeline = engine.gpu_driver.device.createRenderPipeline(&pipeline_descriptor);

    vs_module.release();
    fs_module.release();

    app.win = gui.Window.init(gpa, app, renderGeometry, textureCreate, textureDestroy);
}

pub fn deinit(app: *App, _: *mach.Engine) void {
    _ = app;
}

pub fn update(app: *App, engine: *mach.Engine) !bool {
    app.app_engine = engine;

    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arena = arena_allocator.allocator();
    defer arena_allocator.deinit();

    const size = engine.core.getWindowSize();
    const psize = engine.core.getFramebufferSize();
    var nstime = app.win.beginWait();
    app.win.begin(arena, nstime, size.width, size.height, psize.width, psize.height);

    while (engine.core.pollEvent()) |event| {
        switch (event) {
            .key_press => |ev| {
                if (ev.key == .space)
                    engine.core.setShouldClose(true);
            },
            else => {},
        }
    }

    for (pending_events.items) |pe| {
      switch (pe.evt) {
        .mouse => |me| {
          switch (me.state) {
            .motion => {
              app.win.addEventMouseMotion(me.p.x, me.p.y);
            },
            else => {
              app.win.addEventMouseButton(me.state);
            },
          }
        },
        else => {},
      }
    }
    pending_events.clearAndFree();

    app.win.endEvents();

    TestGui();

    const end_micros = app.win.end();

    engine.gpu_driver.swap_chain.?.present();

    app.win.wait(end_micros, null);

    return true;
}


pub fn TestGui() void {
    {
      var box = gui.Box(@src(), 0, .vertical, .{.expand = .both, .background = false});
      defer box.deinit();

      var paned = gui.Paned(@src(), 0, .horizontal, 400, .{.expand = .both, .background = false});
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

