const std = @import("std");
const gui = @import("gui/gui.zig");

const c = @cImport({
    @cInclude("SDL2/SDL.h");
    //@cInclude("SDL2/SDL_image.h");
});

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
      //std.debug.print("unhandled SDL event type {}\n", .{event.type});
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

  //std.debug.print("renderGeometry:\n", .{});
  //for (vtx) |v, i| {
  //  std.debug.print("  {d} vertex {}\n", .{i, v});
  //}
  //for (idx) |id, i| {
  //  std.debug.print("  {d} index {d}\n", .{i, id});
  //}

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

fn textureCreate(userdata: ?*anyopaque, pixels: []u8, width: u32, height: u32) *anyopaque {
  const renderer = @ptrCast(*c.SDL_Renderer, userdata);
  var surface = c.SDL_CreateRGBSurfaceWithFormatFrom(
    pixels.ptr,
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

fn hasEvent(userdata: ?*anyopaque) bool {
  _ = userdata;
  return c.SDL_PollEvent(null) == 1;
}

fn waitEvent(userdata: ?*anyopaque) void {
  _ = userdata;
  _ = c.SDL_WaitEvent(null);
}

fn waitEventTimeout(userdata: ?*anyopaque, timeout: f64) void {
  _ = userdata;
  _ = c.SDL_WaitEventTimeout(null, @floatToInt(c_int, @ceil(timeout * 1000)));
}

pub fn main() void {
  if (c.SDL_Init(c.SDL_INIT_EVERYTHING) < 0) {
    std.debug.print("Couldn't initialize SDL: {s}\n", .{c.SDL_GetError()});
    return;
  }

  var window = c.SDL_CreateWindow("Gui Test", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 800, 600, c.SDL_WINDOW_ALLOW_HIGHDPI | c.SDL_WINDOW_RESIZABLE)
  orelse {
    std.debug.print("Failed to open window: {s}\n", .{c.SDL_GetError()});
    return;
  };

  _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "linear");

  var renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED)// | c.SDL_RENDERER_PRESENTVSYNC)
    orelse {
    std.debug.print("Failed to create renderer: {s}\n", .{c.SDL_GetError()});
    return;
  };

  _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND);

  var win = gui.Window.init(gpa, renderer, renderGeometry, textureCreate, textureDestroy, hasEvent, waitEvent, waitEventTimeout);

  var theme_dark = false;

  var buttons: [3][6]bool = undefined;
  for (buttons) |*b| {
    b.* = [_]bool{true} ** 6;
  }

  var maxz: usize = 20;
  _ = maxz;
  var floats: [6]bool = [_]bool{false} ** 6;

  //var rng = std.rand.DefaultPrng.init(0);

  main_loop: while (true) {
    var window_w: i32 = undefined;
    var window_h: i32 = undefined;
    _ = c.SDL_GetWindowSize(window, &window_w, &window_h);

    var pixel_w: i32 = undefined;
    var pixel_h: i32 = undefined;
    _ = c.SDL_GetRendererOutputSize(renderer, &pixel_w, &pixel_h);

    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    if (theme_dark) {
      win.theme = &gui.Theme_Adwaita_Dark;
    }
    else {
      win.theme = &gui.Theme_Adwaita;
    }
    var nstime = win.beginWait();
    win.begin(arena, nstime,
      @intCast(u32, window_w),
      @intCast(u32, window_h),
      @intCast(u32, pixel_w),
      @intCast(u32, pixel_h),
    );

    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event) != 0) {
      addEventSDL(&win, event);
      switch (event.type) {
        c.SDL_KEYDOWN, c.SDL_KEYUP => |updown| {
          if (updown == c.SDL_KEYDOWN and ((event.key.keysym.mod & c.KMOD_CTRL) > 0) and event.key.keysym.sym == c.SDLK_q) {
            break :main_loop;
          }
          if (updown == c.SDL_KEYDOWN and event.key.keysym.sym == c.SDLK_t) {
            for (floats) |f, fi| {
              if (!f) {
                floats[fi] = true;
                break;
              }
            }
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
    }

    win.endEvents();

    var window_box = gui.Box(@src(), 0, .vertical, .{.expand = .both, .color_style = .window, .background = true});

    {
      const oo = gui.Options{.expand = .both};
      var overlay = gui.Overlay(@src(), 0, oo);
      defer overlay.deinit();

      const scale = gui.Scale(@src(), 0, 1, oo);
      defer scale.deinit();

      const context = gui.Context(@src(), 0, oo);
      defer context.deinit();

      if (context.activePoint()) |cp| {
        //std.debug.print("context.rect {}\n", .{context.rect});
        var fw2 = gui.Popup(@src(), 0, gui.Rect.fromPoint(cp), &context.active, null, .{});
        defer fw2.deinit();

        _ = gui.MenuItemLabel(@src(), 0, "Cut", false, .{});
        if (gui.MenuItemLabel(@src(), 0, "Close", false, .{}) != null) {
          gui.MenuGet().?.close();
        }
        _ = gui.MenuItemLabel(@src(), 0, "Paste", false, .{});
      }

      {
        var layout = gui.Box(@src(), 0, .vertical, .{});
        defer layout.deinit();

        {
          var menu = gui.Menu(@src(), 0, .horizontal, .{});
          defer menu.deinit();

          {
            if (gui.MenuItemLabel(@src(), 0, "File", true, .{})) |r| {
              var fw = gui.Popup(@src(), 0, gui.Rect.fromPoint(gui.Point{.x = r.x, .y = r.y + r.h}), &menu.submenus_activated, menu, .{});
              defer fw.deinit();

              if (gui.MenuItemLabel(@src(), 0, "Open...", true, .{})) |rr| {
                var menu_rect2 = rr;
                menu_rect2.x += menu_rect2.w;
                var fw2 = gui.Popup(@src(), 0, menu_rect2, null, null, .{});
                defer fw2.deinit();

                _ = gui.MenuItemLabel(@src(), 0, "Cut", false, .{});
                if (gui.MenuItemLabel(@src(), 0, "Close", false, .{}) != null) {
                  gui.MenuGet().?.close();
                }
                _ = gui.MenuItemLabel(@src(), 0, "Paste", false, .{});
              }

              if (gui.MenuItemLabel(@src(), 0, "Close", false, .{}) != null) {
                gui.MenuGet().?.close();
              }
              _ = gui.MenuItemLabel(@src(), 0, "Print", false, .{});
            }
          }

          {
            if (gui.MenuItemLabel(@src(), 0, "Edit", true, .{})) |r| {
              var fw = gui.Popup(@src(), 0, gui.Rect.fromPoint(gui.Point{.x = r.x, .y = r.y + r.h}), &menu.submenus_activated, menu, .{});
              defer fw.deinit();

              _ = gui.MenuItemLabel(@src(), 0, "Cut", false, .{});
              _ = gui.MenuItemLabel(@src(), 0, "Copy", false, .{});
              _ = gui.MenuItemLabel(@src(), 0, "Paste", false, .{});
            }
          }

          {
            if (gui.MenuItemLabel(@src(), 0, "Theme", true, .{})) |r| {
              var fw = gui.Popup(@src(), 0, gui.Rect.fromPoint(gui.Point{.x = r.x, .y = r.y + r.h}), &menu.submenus_activated, menu, .{});
              defer fw.deinit();

              gui.Checkbox(@src(), 0, &theme_dark, "Dark", .{});

              _ = gui.MenuItemLabel(@src(), 0, "Cut", false, .{});
              _ = gui.MenuItemLabel(@src(), 0, "Copy", false, .{});
              _ = gui.MenuItemLabel(@src(), 0, "Paste", false, .{});
             
            }
          }
        }

        //{
        //  //const e2 = gui.Expand(.horizontal);
        //  //defer _ = gui.Expand(e2);

        //  var margin = gui.Margin(gui.Rect{.x = 20, .y = 20, .w = 20, .h = 20});
        //  defer _ = gui.Margin(margin);

        //  var box = gui.Box(@src(), 0, .horizontal);
        //  defer box.deinit();
        // 
        //  for (buttons) |*buttoncol, k| {
        //    if (k != 0) {
        //      gui.Spacer(@src(), k, 6);
        //    }
        //    if (buttoncol[0]) {
        //      var margin2 = gui.Margin(gui.Rect{.x = 4, .y = 4, .w = 4, .h = 4});
        //      defer _ = gui.Margin(margin2);

        //      var box2 = gui.Box(@src(), k, .vertical);
        //      defer box2.deinit();

        //      for (buttoncol) |b, i| {
        //        if (b) {
        //          if (i != 0) {
        //            gui.Spacer(@src(), i, 6);
        //            //gui.Label(@src(), i, "Label", .{});
        //          }
        //          var buf: [100:0]u8 = undefined;
        //          if (k == 0) {
        //            _ = std.fmt.bufPrintZ(&buf, "HELLO {d}", .{i}) catch unreachable;
        //          }
        //          else if (k == 1) {
        //            _ = std.fmt.bufPrintZ(&buf, "middle {d}", .{i}) catch unreachable;
        //          }
        //          else {
        //            _ = std.fmt.bufPrintZ(&buf, "bye {d}", .{i}) catch unreachable;
        //          }
        //          if (gui.Button(@src(), i, &buf)) {
        //            if (i == 0) {
        //              buttoncol[0] = false;
        //            }
        //            else if (i == 5) {
        //              buttons[k+1][0] = true;
        //            }
        //            else if (i % 2 == 0) {
        //              std.debug.print("Adding {d}\n", .{i + 1});
        //              buttoncol[i+1] = true;
        //            }
        //            else {
        //              std.debug.print("Removing {d}\n", .{i});
        //              buttoncol[i] = false;
        //            }
        //          }
        //        }
        //      }
        //    }
        //  }
        //}

        {
          var scroll = gui.ScrollArea(@src(), 0, null, .{});
          defer scroll.deinit();

          var buf: [100]u8 = undefined;
          var z: usize = 0;
          while (z < maxz) : (z += 1) {
            const buf_slice = std.fmt.bufPrint(&buf, "Button {d}", .{z}) catch unreachable;
            if (gui.Button(@src(), z, buf_slice, .{})) {
              if (z % 2 == 0) {
                maxz += 1;
              }
              else {
                maxz -= 1;
              }
            }
          }
        }

        {
          var button = gui.ButtonWidget{};
          _ = button.init(@src(), 0, "Wiggle", .{.tab_index = 10});

          if (gui.AnimationGet(button.bc.wd.id, "xoffset")) |a| {
            button.bc.wd.rect.x += a.lerp();
          }

          if (button.install()) {
            const a = gui.Animation{.start_val = 0, .end_val = 200, .start_time = 0, .end_time = 10_000_000};
            gui.Animate(button.bc.wd.id, "xoffset", a);
          }
        }

        {
          if (gui.Button(@src(), 0, "Stroke Test", .{})) {
            StrokeTest.show_dialog = !StrokeTest.show_dialog;
          }

          if (StrokeTest.show_dialog) {
            show_stroke_test_window();
          }
        }

        if (true) {
          const millis = @divFloor(gui.frameTimeNS(), 1_000_000);
          const left = @intCast(i32, @rem(millis, 1000));

          var label = gui.LabelWidget{};
          label.init(@src(), 0, "{d} {d}", .{@divTrunc(millis, 1000), @intCast(u32, left)}, .{.margin = gui.Rect.all(4), .min_size = (gui.Options{}).font().textSize("0" ** 15), .gravity = .left});
          label.install();

          if (gui.TimerDone(label.wd.id) or !gui.TimerExists(label.wd.id)) {
            const wait = 1000 * (1000 - left);
            gui.TimerSet(label.wd.id, wait);
            //std.debug.print("add timer {d}\n", .{wait});
          }
        }

        {
          gui.Spinner(@src(), 0, .{.color_style = .custom, .color_custom = .{.r = 100, .g = 200, .b = 100}});
        }

        {
          const CheckboxBool = struct {
            var b: bool = false;
          };

          var checklabel: []const u8 = "Check Me No";
          if (CheckboxBool.b) {
            checklabel = "Check Me Yes";
          }

          gui.Checkbox(@src(), 0, &CheckboxBool.b, checklabel, .{.tab_index = 6, .min_size = .{.w = 100, .h = 0}, .color_style = .content, .margin = gui.Rect.all(4), .corner_radius = gui.Rect.all(2)});
        }

        {
          const TextEntryText = struct {
            //var text = array(u8, 100, "abcdefghijklmnopqrstuvwxyz");
            var text1 = array(u8, 100, "abc");
            var text2 = array(u8, 100, "abc");
            fn array(comptime T: type, comptime size: usize, items: ?[]const T) [size]T {
              var output = std.mem.zeroes([size]T);
              if (items) |slice| std.mem.copy(T, &output, slice);
              return output;
            }
          };

          gui.TextEntry(@src(), 0, 26.0, &TextEntryText.text1, .{});
          gui.TextEntry(@src(), 0, 26.0, &TextEntryText.text2, .{});
        }

        {
          var box = gui.Box(@src(), 0, .horizontal, .{});

          _ = gui.Button(@src(), 0, "Accent", .{.color_style = .accent});
          _ = gui.Button(@src(), 0, "Success", .{.color_style = .success});
          _ = gui.Button(@src(), 0, "Warning", .{.color_style = .warning});
          _ = gui.Button(@src(), 0, "Error", .{.color_style = .err});

          box.deinit();

          gui.Label(@src(), 0, "Theme: {s}", .{gui.ThemeGet().name}, .{});

          if (gui.Button(@src(), 0, "Toggle Theme", .{})) {
            theme_dark = !theme_dark;
          }
        }

        IconBrowserButtonAndWindow();
      }
      

      const fps = gui.FPS();
      //std.debug.print("fps {d}\n", .{@round(fps)});
      //gui.render_text = true;
      gui.Label(@src(), 0, "fps {d:4.2}", .{fps}, .{.gravity = .upright});
      //gui.render_text = false;
    }

    {
      const FloatingWindowTest = struct {
        var show: bool = false;
        var rect = gui.Rect{.x = 300.25, .y = 200.25, .w = 300, .h = 200};
      };

      if (gui.Button(@src(), 0, "Floating Window", .{})) {
        FloatingWindowTest.show = !FloatingWindowTest.show;
      }

      if (FloatingWindowTest.show) {
        var fwin = gui.FloatingWindow(@src(), 0, false, &FloatingWindowTest.rect, &FloatingWindowTest.show, .{});
        defer fwin.deinit();
        gui.LabelNoFormat(@src(), 0, "Floating Window", .{.gravity = .center});

        {
          var menu = gui.Menu(@src(), 0, .horizontal, .{});
          defer menu.deinit();

          {
            if (gui.MenuItemLabel(@src(), 0, "File", true, .{})) |r| {
              var fw = gui.Popup(@src(), 0, gui.Rect.fromPoint(gui.Point{.x = r.x, .y = r.y + r.h}), &menu.submenus_activated, menu, .{});
              defer fw.deinit();

              if (gui.MenuItemLabel(@src(), 0, "Open...", true, .{})) |rr| {
                var menu_rect2 = rr;
                menu_rect2.x += menu_rect2.w;
                var fw2 = gui.Popup(@src(), 0, menu_rect2, null, null, .{});
                defer fw2.deinit();

                _ = gui.MenuItemLabel(@src(), 0, "Cut", false, .{});
                if (gui.MenuItemLabel(@src(), 0, "Close", false, .{}) != null) {
                  gui.MenuGet().?.close();
                }
                _ = gui.MenuItemLabel(@src(), 0, "Paste", false, .{});
              }

              if (gui.MenuItemLabel(@src(), 0, "Close", false, .{}) != null) {
                gui.MenuGet().?.close();
              }
              _ = gui.MenuItemLabel(@src(), 0, "Print", false, .{});
            }
          }

          {
            if (gui.MenuItemLabel(@src(), 0, "Edit", true, .{})) |r| {
              var fw = gui.Popup(@src(), 0, gui.Rect.fromPoint(gui.Point{.x = r.x, .y = r.y + r.h}), &menu.submenus_activated, menu, .{});
              defer fw.deinit();

              _ = gui.MenuItemLabel(@src(), 0, "Cut", false, .{});
              _ = gui.MenuItemLabel(@src(), 0, "Copy", false, .{});
              _ = gui.MenuItemLabel(@src(), 0, "Paste", false, .{});
            }
          }
        }
      

        gui.Label(@src(), 0, "Pretty Cool", .{}, .{.font_style = .custom, .font_custom = .{.name = "VeraMono", .ttf_bytes = gui.fonts.bitstream_vera.VeraMono, .size = 20}});

        if (gui.Button(@src(), 0, "button", .{})) {
          std.debug.print("floating button\n", .{});
          floats[0] = true;
        }

        const CheckboxBoolFloat = struct {
          var b: bool = false;
        };

        var checklabel: []const u8 = "Check Me No";
        if (CheckboxBoolFloat.b) {
          checklabel = "Check Me Yes";
        }

        gui.Checkbox(@src(), 0, &CheckboxBoolFloat.b, checklabel, .{});

        for (floats) |*f, fi| {
          if (f.*) {
            const modal = if (fi % 2 == 0) true else false;
            var name: []const u8 = "";
            if (modal) {
              name = "Modal";
            }
            var buf = std.mem.zeroes([100]u8);
            var buf_slice = std.fmt.bufPrintZ(&buf, "{d} {s} Dialog", .{fi, name}) catch unreachable;
            var fw2 = gui.FloatingWindow(@src(), fi, modal, null, f, .{.color_style = .window, .min_size = .{.w = 150, .h = 100}});
            defer fw2.deinit();
            gui.LabelNoFormat(@src(), 0, buf_slice, .{.gravity = .center});

            gui.Label(@src(), 0, "Asking a Question", .{}, .{});

            const oo = gui.Options{.margin = gui.Rect.all(4), .expand = .horizontal};
            var box = gui.Box(@src(), 0, .horizontal, oo);

            if (gui.Button(@src(), 0, "Yes", oo)) {
              std.debug.print("Yes {d}\n", .{fi});
              floats[fi+1] = true;
            }

            if (gui.Button(@src(), 0, "No", oo)) {
              std.debug.print("No {d}\n", .{fi});
              fw2.close();
            }

            box.deinit();
          }
        }


        var scroll = gui.ScrollArea(@src(), 0, null, .{.expand = .both});
        defer scroll.deinit();
        var tl = gui.TextLayout(@src(), 0, .{.expand = .both});
        {
          if (gui.Button(@src(), 0, "Up .1", .{.gravity = .upleft})) {
            fwin.wd.rect.y -= 0.1;
          }
          if (gui.Button(@src(), 0, "Down .1", .{.gravity = .upright})) {
            fwin.wd.rect.y += 0.1;
          }
        }
        const lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.";
        //const lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore";
        tl.addText(lorem, .{});
        //var it = std.mem.split(u8, lorem, " ");
        //while (it.next()) |word| {
        //  tl.addText(word);
        //  tl.addText(" ");
        //}
        tl.deinit();
      }
    }

    window_box.deinit();

    const end_micros = win.end();

    c.SDL_RenderPresent(renderer);

    win.wait(end_micros, null);
  }

  c.SDL_DestroyRenderer(renderer);
  c.SDL_DestroyWindow(window);
  c.SDL_Quit();
}

fn show_stroke_test_window() void {
  var win = gui.FloatingWindow(@src(), 0, false, &StrokeTest.show_rect, &StrokeTest.show_dialog, .{});
  defer win.deinit();
  gui.LabelNoFormat(@src(), 0, "Stroke Test", .{.gravity = .center});

  //var scale = gui.Scale(@src(), 0, 1, .{.expand = .both});
  //defer scale.deinit();

  var st = StrokeTest{};
  st.install(@src(), 0, .{.min_size = .{.w = 400, .h = 400}, .expand = .both});
}

pub const StrokeTest = struct {
  const Self = @This();
  var show_dialog: bool = false;
  var show_rect = gui.Rect{};
  var pointsArray: [10]gui.Point = [1]gui.Point{.{}} ** 10;
  var points: []gui.Point = pointsArray[0..0];
  var dragi: ?usize = null;
  var thickness: f32 = 1.0;

  wd: gui.WidgetData = undefined,

  pub fn install(self: *Self, src: std.builtin.SourceLocation, id_extra: usize, options: gui.Options) void {
    self.wd = gui.WidgetData.init(src, id_extra, options);
    gui.debug("{x} StrokeTest {}", .{self.wd.id, self.wd.rect});

    _ = gui.CaptureMouseMaintain(self.wd.id);
    self.processEvents();

    self.wd.borderAndBackground();

    const rs = gui.ParentGet().screenRectScale(self.wd.rect);
    const fill_color = gui.Color{.r = 200, .g = 200, .b = 200, .a = 255};
    for (points) |p| {
      var rect = gui.Rect.fromPoint(p.plus(.{.x = -10, .y = -10})).toSize(.{.w = 20, .h = 20});
      const rsrect = rect.scale(rs.s).offset(rs.r);
      gui.PathAddRect(rsrect, gui.Rect.all(1));
      gui.PathFillConvex(fill_color);
    }

    for (points) |p| {
      const rsp = rs.childPoint(p);
      gui.PathAddPoint(rsp);
    }

    const stroke_color = gui.Color{.r = 0, .g = 0, .b = 255, .a = 150};
    gui.PathStroke(false, rs.s * thickness, .square, stroke_color);

    self.wd.minSizeSetAndCue();
    self.wd.minSizeReportToParent();
  }

  pub fn processEvents(self: *Self) void {
    const rs = gui.ParentGet().screenRectScale(self.wd.rect);
    var iter = gui.EventIterator.init(self.wd.id, rs.r);
    while (iter.next()) |e| {
      switch (e.evt) {
        .mouse => |me| {
          const mp = me.p.inRectScale(rs);
          switch (me.state) {
            .leftdown => {
              e.handled = true;
              dragi = null;

              for (points) |p, i| {
                const dp = gui.Point.diff(p, mp);
                if (@fabs(dp.x) < 5 and @fabs(dp.y) < 5) {
                  dragi = i;
                  break;
                }
              }

              if (dragi == null and points.len < pointsArray.len) {
                dragi = points.len;
                points.len += 1;
                points[dragi.?] = mp;
              }

              if (dragi != null) {
                gui.CaptureMouse(self.wd.id);
                gui.DragPreStart(me.p, .crosshair);
              }
            },
            .leftup => {
              e.handled = true;
              gui.CaptureMouse(null);
              gui.DragEnd();
            },
            .motion => {
              e.handled = true;
              if (gui.Dragging(me.p)) |dps| {
                const dp = dps.scale(1 / rs.s);
                points[dragi.?].x += dp.x;
                points[dragi.?].y += dp.y;
              }
            },
            .wheel_y => {
              e.handled = true;
              var base: f32 = 1.05;
              const zs = @exp(@log(base) * me.wheel);
              if (zs != 1.0) {
                thickness *= zs;
              }
            },
            else => {},
          }
        },
        else => {},
      }
    }
  }
};

fn IconBrowserButtonAndWindow() void {
  const IconBrowser = struct {
    var show: bool = false;
    var rect = gui.Rect{.x = 0, .y = 0, .w = 300, .h = 300};
    var row_height: f32 = 0;
  };

  if (gui.Button(@src(), 0, "Icon Browser", .{})) {
    IconBrowser.show = !IconBrowser.show;
  }

  if (IconBrowser.show) {
    var fwin = gui.FloatingWindow(@src(), 0, false, &IconBrowser.rect, &IconBrowser.show, .{});
    defer fwin.deinit();
    gui.LabelNoFormat(@src(), 0, "Icon Browser", .{.gravity = .center});

    const num_icons = @typeInfo(gui.icons.papirus.actions).Struct.decls.len;
    const height = @intToFloat(f32, num_icons) * IconBrowser.row_height;

    var scroll = gui.ScrollArea(@src(), 0, gui.Size{.w = 0, .h = height}, .{.expand = .both});
    defer scroll.deinit();

    const visibleRect = scroll.visibleRect();
    var cursor: f32 = 0;

    inline for (@typeInfo(gui.icons.papirus.actions).Struct.decls) |d, i| {
      if (cursor <= (visibleRect.y + visibleRect.h) and (cursor + IconBrowser.row_height) >= visibleRect.y) {
        const r = gui.Rect{.x = 0, .y = cursor, .w = 0, .h = IconBrowser.row_height};
        var iconbox = gui.Box(@src(), i, .horizontal, .{.expand = .horizontal, .rect = r});
        //gui.Icon(@src(), 0, 20, d.name, @field(gui.icons.papirus.actions, d.name), .{.margin = gui.Rect.all(2)});
        _ = gui.ButtonIcon(@src(), 0, 20, d.name, @field(gui.icons.papirus.actions, d.name), .{.min_size = gui.Size.all(r.h)});
        gui.Label(@src(), 0, d.name, .{}, .{.gravity = .left});

        iconbox.deinit();

        if (IconBrowser.row_height == 0) {
          IconBrowser.row_height = iconbox.wd.min_size.h;
        }
      }

      cursor += IconBrowser.row_height;
    }
  }
}

