const std = @import("std");
const builtin = @import("builtin");
const c = @import("c.zig");
const gui = @import("gui.zig");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();


var cursor_backing: [@typeInfo(gui.CursorKind).Enum.fields.len]*c.SDL_Cursor = undefined;

pub fn addEventSDL(win: *gui.Window, event: c.SDL_Event) void {
  switch (event.type) {
    c.SDL_KEYDOWN => {
      win.addEventKey(
        SDL_keysym_to_gui(event.key.keysym.sym),
        SDL_keymod_to_gui(event.key.keysym.mod),
        if (event.key.repeat > 0) .repeat else .down,
      );
    },
    c.SDL_TEXTINPUT => {
      win.addEventText(&event.text.text);
    },
    c.SDL_MOUSEMOTION => {
      win.addEventMouseMotion(@intToFloat(f32, event.motion.x), @intToFloat(f32, event.motion.y));
    },
    c.SDL_MOUSEBUTTONDOWN, c.SDL_MOUSEBUTTONUP => |updown| {
      var state: gui.MouseEvent.Kind = undefined;
      if (event.button.button == c.SDL_BUTTON_LEFT) {
        if (updown == c.SDL_MOUSEBUTTONDOWN) {
          state = .leftdown;
        }
        else {
          state = .leftup;
        }
      }
      else if (event.button.button == c.SDL_BUTTON_RIGHT) {
        if (updown == c.SDL_MOUSEBUTTONDOWN) {
          state = .rightdown;
        }
        else {
          state = .rightup;
        }
      }

      win.addEventMouseButton(state);
    },
    c.SDL_MOUSEWHEEL => {
      const ticks = @intToFloat(f32, event.wheel.y);
      win.addEventMouseWheel(ticks);
    },
    else => {
      std.debug.print("unhandled SDL event type {}\n", .{event.type});
    },
  }
}

pub fn SDL_keymod_to_gui(keymod: u16) gui.keys.Mod {
  if (keymod == c.KMOD_NONE) return gui.keys.Mod.none;

  var m: u16 = 0;
  if (keymod & c.KMOD_LSHIFT > 0) m |= @enumToInt(gui.keys.Mod.lshift);
  if (keymod & c.KMOD_RSHIFT > 0) m |= @enumToInt(gui.keys.Mod.rshift);
  if (keymod & c.KMOD_LCTRL > 0) m |= @enumToInt(gui.keys.Mod.lctrl);
  if (keymod & c.KMOD_RCTRL > 0) m |= @enumToInt(gui.keys.Mod.rctrl);
  if (keymod & c.KMOD_LALT > 0) m |= @enumToInt(gui.keys.Mod.lalt);
  if (keymod & c.KMOD_RALT > 0) m |= @enumToInt(gui.keys.Mod.ralt);
  if (keymod & c.KMOD_LGUI > 0) m |= @enumToInt(gui.keys.Mod.lgui);
  if (keymod & c.KMOD_RGUI > 0) m |= @enumToInt(gui.keys.Mod.rgui);

  return @intToEnum(gui.keys.Mod, m);
}

pub fn SDL_keysym_to_gui(keysym: i32) gui.keys.Key {
  return switch (keysym) {
    c.SDLK_a => .a,
    c.SDLK_b => .b,
    c.SDLK_c => .c,
    c.SDLK_d => .d,
    c.SDLK_e => .e,
    c.SDLK_f => .f,
    c.SDLK_g => .g,
    c.SDLK_h => .h,
    c.SDLK_i => .i,
    c.SDLK_j => .j,
    c.SDLK_k => .k,
    c.SDLK_l => .l,
    c.SDLK_m => .m,
    c.SDLK_n => .n,
    c.SDLK_o => .o,
    c.SDLK_p => .p,
    c.SDLK_q => .q,
    c.SDLK_r => .r,
    c.SDLK_s => .s,
    c.SDLK_t => .t,
    c.SDLK_u => .u,
    c.SDLK_v => .v,
    c.SDLK_w => .w,
    c.SDLK_x => .x,
    c.SDLK_y => .y,
    c.SDLK_z => .z,

    c.SDLK_SPACE => .space,
    c.SDLK_BACKSPACE => .backspace,
    c.SDLK_UP => .up,
    c.SDLK_DOWN => .down,
    c.SDLK_TAB => .tab,
    c.SDLK_ESCAPE => .escape,
    else => .unknown,
  };
}

fn renderGeometry(userdata: ?*anyopaque, texture: ?*anyopaque, vtx: []gui.Vertex, idx: []u32) void {
  const clipr = gui.WindowRectPixels().intersect(gui.ClipGet());
  if (clipr.empty()) {
    return;
  }

  const renderer = @ptrCast(*c.SDL_Renderer, userdata);

  const clip = c.SDL_Rect{.x = @floatToInt(c_int, clipr.x),
                          .y = @floatToInt(c_int, clipr.y),
                          .w = std.math.max(0, @floatToInt(c_int, @ceil(clipr.w))),
                          .h = std.math.max(0, @floatToInt(c_int, @ceil(clipr.h)))};
  _ = c.SDL_RenderSetClipRect(renderer, &clip);

    const tex = @ptrCast(?*c.SDL_Texture, texture);

  _ = c.SDL_RenderGeometryRaw(renderer, tex,
    @ptrCast(*f32, &vtx[0].pos), @sizeOf(gui.Vertex),
    @ptrCast(*c_int, @alignCast(4, &vtx[0].col)), @sizeOf(gui.Vertex),
    @ptrCast(*f32, &vtx[0].uv), @sizeOf(gui.Vertex),
    @intCast(c_int, vtx.len),
    idx.ptr, @intCast(c_int, idx.len), @sizeOf(u32));
}

fn textureCreate(userdata: ?*anyopaque, pixels: *anyopaque, width: u32, height: u32) *anyopaque {
  const renderer = @ptrCast(*c.SDL_Renderer, userdata);
  var surface = c.SDL_CreateRGBSurfaceWithFormatFrom(
    pixels,
    @intCast(c_int, width),
    @intCast(c_int, height),
    32,
    @intCast(c_int, 4*width),
    c.SDL_PIXELFORMAT_ABGR8888);
  defer c.SDL_FreeSurface(surface);

  const texture = c.SDL_CreateTextureFromSurface(renderer, surface) orelse unreachable;
  return texture;
}

fn textureDestroy(userdata: ?*anyopaque, texture: *anyopaque) void {
  _ = userdata;
  c.SDL_DestroyTexture(@ptrCast(*c.SDL_Texture, texture));
}


pub fn main() void {
  if (c.SDL_Init(c.SDL_INIT_EVERYTHING) < 0) {
    std.debug.print("Couldn't initialize SDL: {s}\n", .{c.SDL_GetError()});
    return;
  }

  var window = c.SDL_CreateWindow("Gui Test", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 360, 600, c.SDL_WINDOW_ALLOW_HIGHDPI | c.SDL_WINDOW_RESIZABLE)
  orelse {
    std.debug.print("Failed to open window: {s}\n", .{c.SDL_GetError()});
    return;
  };

  _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "linear");

  var renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC)
    orelse {
    std.debug.print("Failed to create renderer: {s}\n", .{c.SDL_GetError()});
    return;
  };

  _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND);

  cursor_backing[@enumToInt(gui.CursorKind.arrow)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_ARROW) orelse unreachable;
  cursor_backing[@enumToInt(gui.CursorKind.ibeam)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_IBEAM) orelse unreachable;
  cursor_backing[@enumToInt(gui.CursorKind.wait)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_WAIT) orelse unreachable;
  cursor_backing[@enumToInt(gui.CursorKind.crosshair)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_CROSSHAIR) orelse unreachable;
  cursor_backing[@enumToInt(gui.CursorKind.arrow_nw_se)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_SIZENWSE) orelse unreachable;
  cursor_backing[@enumToInt(gui.CursorKind.arrow_ne_sw)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_SIZENESW) orelse unreachable;
  cursor_backing[@enumToInt(gui.CursorKind.arrow_w_e)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_SIZEWE) orelse unreachable;
  cursor_backing[@enumToInt(gui.CursorKind.arrow_n_s)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_SIZENS) orelse unreachable;
  cursor_backing[@enumToInt(gui.CursorKind.arrow_all)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_SIZEALL) orelse unreachable;
  cursor_backing[@enumToInt(gui.CursorKind.bad)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_NO) orelse unreachable;
  cursor_backing[@enumToInt(gui.CursorKind.hand)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_HAND) orelse unreachable;

  var win = gui.Window.init(gpa, renderer, renderGeometry, textureCreate, textureDestroy);

  main_loop: while (true) {
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    var window_w: i32 = undefined;
    var window_h: i32 = undefined;
    _ = c.SDL_GetWindowSize(window, &window_w, &window_h);

    var pixel_w: i32 = undefined;
    var pixel_h: i32 = undefined;
    _ = c.SDL_GetRendererOutputSize(renderer, &pixel_w, &pixel_h);

    _ = c.SDL_SetRenderDrawColor(renderer, 75, 75, 75, 255);
    _ = c.SDL_RenderClear(renderer);

    var nstime = win.beginWait();
    win.begin(arena, nstime, window_w, window_h, pixel_w, pixel_h);

    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event) != 0) {
      switch (event.type) {
        c.SDL_KEYDOWN, c.SDL_KEYUP => |updown| {
          if (updown == c.SDL_KEYDOWN and ((event.key.keysym.mod & c.KMOD_CTRL) > 0) and event.key.keysym.sym == c.SDLK_q) {
            break :main_loop;
          }
        },
        c.SDL_QUIT => {
          //std.debug.print("SDL_QUIT\n", .{});
          break :main_loop;
        },
        else => {
          //std.debug.print("other event\n", .{});
        }
      }
      addEventSDL(&win, event);
    }

    win.endEvents();

    {
      var scale = gui.Scale(@src(), 0, 1.0, .{.expand = .both, .background = false}); 
      defer scale.deinit();

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

    const end_micros = win.end();

    if (win.CursorRequested()) |cursor| {
      c.SDL_SetCursor(cursor_backing[@enumToInt(cursor)]);
    }

    c.SDL_RenderPresent(renderer);

    win.wait(end_micros, null);
  }

  c.SDL_DestroyRenderer(renderer);
  c.SDL_DestroyWindow(window);
  c.SDL_Quit();
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
  var buf: [256]u8 = undefined;
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


