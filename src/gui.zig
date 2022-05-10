const std = @import("std");
const math = std.math;
const c = @import("c.zig");
const tvg = @import("tinyvg/tinyvg.zig");
const fnv = std.hash.Fnv1a_32;
pub const icons = @import("icons.zig");
pub const fonts = @import("fonts.zig");

//const stb = @cImport({
//    @cInclude("stb_rect_pack.h");
//    @cDefine("STB_TRUETYPE_IMPLEMENTATION", "1");
//    @cInclude("stb_truetype.h");
//});

const log = std.log.scoped(.gui);
const gui = @This();

var current_window: ?*Window = null;
var cursor_backing: [@typeInfo(CursorKind).Enum.fields.len]*c.SDL_Cursor = undefined;

pub var log_debug: bool = false;
pub fn debug(comptime str: []const u8, args: anytype) void {
  if (log_debug) {
    log.debug(str, args);
  }
}

pub const Theme = struct {
  color_accent: Color,
  color_accent_bg: Color,
  color_success: Color,
  color_success_bg: Color,
  color_warning: Color,
  color_warning_bg: Color,
  color_err: Color,
  color_err_bg: Color,
  color_window: Color,
  color_window_bg: Color,
  color_content: Color,
  color_content_bg: Color,
  color_control: Color,
  color_control_bg: Color,

  font_body: Font,
  font_heading: Font,
  font_caption: Font,
  font_caption_heading: Font,
  font_title_large: Font,
  font_title_1: Font,
  font_title_2: Font,
  font_title_3: Font,
  font_title_4: Font,
};

pub const Theme_Adwaita = Theme{
  .font_body = Font{.size = 11, .name = "Vera", .ttf_bytes = fonts.bitstream_vera.Vera},
  .font_heading = Font{.size = 11, .name = "VeraBd", .ttf_bytes = fonts.bitstream_vera.VeraBd},
  .font_caption = Font{.size = 9, .name = "Vera", .ttf_bytes = fonts.bitstream_vera.Vera},
  .font_caption_heading = Font{.size = 9, .name = "VeraBd", .ttf_bytes = fonts.bitstream_vera.VeraBd},
  .font_title_large = Font{.size = 24, .name = "Vera", .ttf_bytes = fonts.bitstream_vera.Vera},
  .font_title_1 = Font{.size = 20, .name = "VeraBd", .ttf_bytes = fonts.bitstream_vera.VeraBd},
  .font_title_2 = Font{.size = 17, .name = "VeraBd", .ttf_bytes = fonts.bitstream_vera.VeraBd},
  .font_title_3 = Font{.size = 15, .name = "VeraBd", .ttf_bytes = fonts.bitstream_vera.VeraBd},
  .font_title_4 = Font{.size = 13, .name = "VeraBd", .ttf_bytes = fonts.bitstream_vera.VeraBd},
  .color_accent = Color{.r = 0xff, .g = 0xff, .b = 0xff, .a = 255},
  .color_accent_bg = Color{.r = 0x35, .g = 0x84, .b = 0xe4, .a = 255},
  .color_success = Color{.r = 0, .g = 0, .b = 0, .a = 255},
  .color_success_bg = Color{.r = 0, .g = 0, .b = 0, .a = 255},
  .color_warning = Color{.r = 0, .g = 0, .b = 0, .a = 255},
  .color_warning_bg = Color{.r = 0, .g = 0, .b = 0, .a = 255},
  .color_err = Color{.r = 0, .g = 0, .b = 0, .a = 255},
  .color_err_bg = Color{.r = 0, .g = 0, .b = 0, .a = 255},
  .color_window = Color{.r = 0x31, .g = 0x31, .b = 0x31, .a = 255},
  .color_window_bg = Color{.r = 0xf0, .g = 0xf0, .b = 0xf0, .a = 255},
  .color_content = Color{.r = 0, .g = 0, .b = 0, .a = 255},
  .color_content_bg = Color{.r = 0xff, .g = 0xff, .b = 0xff, .a = 255},
  .color_control = Color{.r = 0x31, .g = 0x31, .b = 0x31, .a = 255},
  .color_control_bg = Color{.r = 0xe0, .g = 0xe0, .b = 0xe0, .a = 255},
};

pub const Options = struct {
  pub const Expand = enum {
    none,
    horizontal,
    vertical,
    both,

    pub fn Horizontal(self: *const Expand) bool {
      return (self.* == .horizontal or self.* == .both);
    }

    pub fn Vertical(self: *const Expand) bool {
      return (self.* == .vertical or self.* == .both);
    }
  };

  pub const Gravity = enum {
    upleft,
    up,
    upright,
    left,
    center,
    right,
    downleft,
    down,
    downright,
  };

  pub const FontStyle = enum {
    custom,
    body,
    heading,
    caption,
    caption_heading,
    title_large,
    title_1,
    title_2,
    title_3,
    title_4,
  };

  pub const ColorStyle = enum {
    custom,
    accent,
    success,
    warning,
    err,
    window,
    content,
    control,
  };

  // default is .none
  expand: ?Expand = null,

  // default is .topleft
  gravity: ?Gravity = null,

  // widgets will be focusable only if this is set
  tab_index: ?u16 = null,

  // only used if .color_style == .custom
  color_custom: ?Color = null,
  color_custom_bg: ?Color = null,

  // only used if .font_style == .custom
  font_custom: ?Font = null,

  // colors and fonts are pulled from here
  theme: ?*const Theme = null,

  // For the rest of these fields, if null, each widget uses its defaults

  // x left, y top, w right, h bottom
  margin: ?Rect = null,
  border: ?Rect = null,
  padding: ?Rect = null,

  // x topleft, y topright, w botright, h botleft
  corner_radius: ?Rect = null,

  // includes padding/border/margin
  // see overrideMinSizeContent()
  min_size: ?Size = null,

  color_style: ?ColorStyle = null,
  background: ?bool = null,
  font_style: ?FontStyle = null,

  pub fn color(self: *const Options) Color {
    return self.colorWithDefault(.control);
  }

  pub fn colorWithDefault(self: *const Options, style_default: ColorStyle) Color {
    const style = self.color_style orelse style_default;
    const col =
      switch (style) {
        .custom => self.color_custom,
        .accent => if (self.theme) |t| t.color_accent else null,
        .success => if (self.theme) |t| t.color_success else null,
        .warning => if (self.theme) |t| t.color_warning else null,
        .err => if (self.theme) |t| t.color_err else null,
        .content => if (self.theme) |t| t.color_content else null,
        .window => if (self.theme) |t| t.color_window else null,
        .control => if (self.theme) |t| t.color_control else null,
    };
      
    if (col) |cc| {
      return cc;
    }
    else {
      log.debug("Options.color() couldn't find a color, substituting magenta\n", .{});
      return Color{.r = 255, .g = 0, .b = 255, .a = 255};
    }
  }

  pub fn color_bg(self: *const Options) Color {
    return self.color_bgWithDefault(.control);
  }

  pub fn color_bgWithDefault(self: *const Options, style_default: ColorStyle) Color {
    const style = self.color_style orelse style_default;
    const col =
      switch (style) {
        .custom => self.color_custom_bg,
        .accent => if (self.theme) |t| t.color_accent_bg else null,
        .success => if (self.theme) |t| t.color_success_bg else null,
        .warning => if (self.theme) |t| t.color_warning_bg else null,
        .err => if (self.theme) |t| t.color_err_bg else null,
        .content => if (self.theme) |t| t.color_content_bg else null,
        .window => if (self.theme) |t| t.color_window_bg else null,
        .control => if (self.theme) |t| t.color_control_bg else null,
    };
      
    if (col) |cc| {
      return cc;
    }
    else {
      log.debug("Options.color_bg() couldn't find a color, substituting green\n", .{});
      return Color{.r = 0, .g = 255, .b = 0, .a = 255};
    }
  }

  pub fn color_focus(self: *const Options) Color {
    if (self.theme) |t| {
      return t.color_accent;
    }
    else  {
      log.debug("Options.color_focus() couldn't find a color, substituting blue\n", .{});
      return Color{.r = 0, .g = 0, .b = 255, .a = 255};
    }
  }

  pub fn color_focus_bg(self: *const Options) Color {
    if (self.theme) |t| {
      return t.color_accent_bg;
    }
    else  {
      log.debug("Options.color_focus_bg() couldn't find a color, substituting red\n", .{});
      return Color{.r = 255, .g = 0, .b = 0, .a = 255};
    }
  }

  pub fn font(self: *const Options) Font {
    return self.fontWithDefault(.body);
  }

  pub fn fontWithDefault(self: *const Options, style_default: FontStyle) Font {
    const style = self.font_style orelse style_default;
    const f =
      switch (style) {
        .custom => self.font_custom,
        .body => if (self.theme) |t| t.font_body else null,
        .heading => if (self.theme) |t| t.font_heading else null,
        .caption => if (self.theme) |t| t.font_caption else null,
        .caption_heading => if (self.theme) |t| t.font_caption_heading else null,
        .title_large => if (self.theme) |t| t.font_title_large else null,
        .title_1 => if (self.theme) |t| t.font_title_1 else null,
        .title_2 => if (self.theme) |t| t.font_title_2 else null,
        .title_3 => if (self.theme) |t| t.font_title_3 else null,
        .title_4 => if (self.theme) |t| t.font_title_4 else null,
    };
      
    if (f) |ff| {
      return ff;
    }
    else {
      log.debug("Options.font() couldn't find a font, falling back\n", .{});
      return Font{.name = "VeraMono", .ttf_bytes = gui.fonts.bitstream_vera.VeraMono, .size = 12};
    }
  }

  pub fn marginGet(self: *const Options) Rect {
    return self.margin orelse Rect{};
  }

  pub fn borderGet(self: *const Options) Rect {
    return self.border orelse Rect{};
  }

  pub fn paddingGet(self: *const Options) Rect {
    return self.padding orelse Rect{};
  }
  
  pub fn corner_radiusGet(self: *const Options) Rect {
    return self.corner_radius orelse Rect{};
  }

  pub fn expandHorizontal(self: *const Options) bool {
    return (self.expand orelse Expand.none).Horizontal();
  }

  pub fn expandVertical(self: *const Options) bool {
    return (self.expand orelse Expand.none).Vertical();
  }

  pub fn expandAny(self: *const Options) bool {
    return (self.expand orelse Expand.none) != Expand.none;
  }

  pub fn gravitate(self: *const Options, in: Rect, avail: Rect) Rect {
    const g = self.gravity orelse .upleft;
    var r = in;
    switch (g) {
      .upleft, .left, .downleft => r.x = avail.x,
      .up, .center, .down => r.x = avail.x + (avail.w - r.w) / 2.0,
      .upright, .right, .downright => r.x = avail.x + (avail.w - r.w),
    }

    switch (g) {
      .upleft, .up, .upright => r.y = avail.y,
      .left, .center, .right => r.y = avail.y + (avail.h - r.h) / 2.0,
      .downleft, .down, .downright => r.y = avail.y + (avail.h - r.h),
    }

    debug("    gravitate {} {} in {} to {}", .{self.gravity, in, avail, r});
    return r;
  }

  pub fn plain(self: *const Options) Options {
    return self.override(.{.margin = .{}, .border = .{}, .background = false, .padding = .{}});
  }

  // make sure you've previously overridden padding/border/margin
  pub fn overrideMinSizeContent(self: *const Options, min_size_content: Size) Options {
    return self.override(.{.min_size = min_size_content.pad(self.paddingGet()).pad(self.borderGet()).pad(self.marginGet())});
  }

  pub fn override(self: *const Options, over: Options) Options {
    var ret = self.*;

    inline for (@typeInfo(Options).Struct.fields) |f| {
      if (@field(over, f.name)) |fval| {
        @field(ret, f.name) = fval;
      }
    }

    return ret;
  }

  pub fn overrideIfNull(self: *const Options, over: Options) Options {
    var ret = self.*;

    inline for (@typeInfo(Options).Struct.fields) |f| {
      if (@field(over, f.name)) |fval| {
        if (@field(ret, f.name) == null) {
          @field(ret, f.name) = fval;
        }
      }
    }

    return ret;
  }

  pub fn format(self: *const Options, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try std.fmt.format(writer, "Options{{ .background = {}, .color_style = {} }}", .{self.background, self.color_style});
  }
};

// override the global options and return the previous settings
pub fn OptionsSet(options: Options) Options {
  var cw = current_window orelse unreachable;
  const ret = cw.options;
  cw.options = cw.options.override(options);
  return ret;
}

// set (not override) global options
pub fn OptionsReset(options: Options) void {
  var cw = current_window orelse unreachable;
  cw.options = options;
}

// get global options overlayed with passed in options
pub fn OptionsGet(options: Options) Options {
  var cw = current_window orelse unreachable;
  return cw.options.override(options);
}

pub fn PlaceOnScreen(spawner: Rect, start: Rect) Rect {
  var r = start;
  const wr = WindowRect();
  if ((r.x + r.w) > wr.w) {
    if (spawner.w == 0) {
      r.x = wr.w - r.w;
    }
    else {
      r.x = spawner.x - spawner.w - r.w;
    }
  }

  if ((r.y + r.h) > wr.h) {
    if (spawner.h == 0) {
      r.y = wr.h - r.h;
    }
  }

  return r;
}

pub fn CurrentWindow() *Window {
  return current_window orelse unreachable;
}

pub fn frameTimeNS() i128 {
  var cw = current_window orelse unreachable;
  return cw.frame_time_ns;
}

// All widgets have to bubble keyboard events if they can have keyboard focus
// so that pressing the up key in any child of a scrollarea will scroll.  Call
// this helper at the end of processing normal events.
fn BubbleEvents(w: Widget) void {
  var iter = EventIterator.init(w.ID(), Rect{});
  while (iter.next()) |e| {
    if (e.handled) {
      continue;
    }

    switch (e.evt) {
      .key,
      .text, => {
        w.bubbleEvent(e);
      },

      .close_popup,
      .mouse, => {},
    }
  }
}

pub const Font = struct {
  size: f32,
  line_skip_factor: f32 = 1.0,
  name: []const u8,
  ttf_bytes: []const u8,

  pub fn resize(self: *const Font, s: f32) Font {
    return Font{.size = s, .name = self.name, .ttf_bytes = self.ttf_bytes};
  }

  pub fn textSize(self: *const Font, text: []const u8) Size {
    var cw = current_window orelse unreachable;

    // ask for a font that matches the natural display pixels so we get a more
    // accurate size
    const ask_size = @ceil(self.size * WindowNaturalScale());
    const target_fraction = self.size / ask_size;
    const sized_font = self.resize(ask_size);

    //std.debug.print("textSize size {d} for \"{s}\"\n", .{sized_font.size, text});
    const sdlfont = FontCacheGet(sized_font);

    var text0 = cw.arena.allocWithOptions(u8, text.len, null, 0) catch unreachable;
    std.mem.copy(u8, text0, text);

    var tw: c_int = undefined;
    var th: c_int = undefined;
    _ = c.TTF_SizeUTF8(sdlfont, text0, &tw, &th);
    return Size{.w = @intToFloat(f32, tw) * target_fraction, .h = @intToFloat(f32, th) * target_fraction};
  }

  pub fn lineSkip(self: *const Font) f32 {
    // do the same sized thing as textSize so they will cache the same font
    const ask_size = @ceil(self.size * WindowNaturalScale());
    const target_fraction = self.size / ask_size;
    const sized_font = self.resize(ask_size);

    const sdlfont = FontCacheGet(sized_font);
    const skip = c.TTF_FontLineSkip(sdlfont);
    return @intToFloat(f32, skip) * target_fraction * self.line_skip_factor;
  }
};

const FontCacheEntry = struct {
  ttf_font: *c.TTF_Font,
  used: bool = true,

  pub fn hash(font: Font) u32 {
    var h = fnv.init();
    h.update(std.mem.asBytes(&font.ttf_bytes.ptr));
    h.update(std.mem.asBytes(&font.size));
    return h.final();
  }
};

const TextCacheEntry = struct {
  texture: *c.SDL_Texture,
  used: bool = true,
};

pub fn FontCacheGet(font: Font) *c.TTF_Font {
  var cw = current_window orelse unreachable;
  const fontHash = FontCacheEntry.hash(font);
  if (cw.font_cache.getPtr(fontHash)) |fce| {
    fce.used = true;
    return fce.ttf_font;
  }

  //std.debug.print("FontCacheGet creating font size {d} name \"{s}\"\n", .{font.size, font.name});

  const rwops = c.SDL_RWFromConstMem(font.ttf_bytes.ptr, @intCast(c_int, font.ttf_bytes.len));
  const ret = c.TTF_OpenFontRW(rwops, 1, @floatToInt(c_int, font.size)) orelse unreachable;

  const entry = FontCacheEntry{.ttf_font = ret};
  cw.font_cache.put(fontHash, entry) catch unreachable;

  return ret;
}

const IconCacheEntry = struct {
  texture: *c.SDL_Texture,
  used: bool = true,

  pub fn hash(tvg_bytes: []const u8, height: f32) u32 {
    var h = fnv.init();
    h.update(std.mem.asBytes(&tvg_bytes.ptr));
    h.update(std.mem.asBytes(&height));
    return h.final();
  }
};

pub fn IconWidth(name: []const u8, tvg_bytes: []const u8, height_natural: f32) f32 {
  var cw = current_window orelse unreachable;
  const height = height_natural * WindowNaturalScale();
  const icon_hash = IconCacheEntry.hash(tvg_bytes, height);

  // ensure it's in the cache
  _ = IconTexture(name, tvg_bytes, height);

  if (cw.icon_cache.getPtr(icon_hash)) |ice| {
    ice.used = true;
    var w: c_int = undefined;
    var h: c_int = undefined;
    _ = c.SDL_QueryTexture(ice.texture, null, null, &w, &h);
    return @intToFloat(f32, w) / WindowNaturalScale();
  }
  else {
    unreachable;
  }
}

pub fn IconTexture(name: []const u8, tvg_bytes: []const u8, ask_height: f32) *c.SDL_Texture {
  var cw = current_window orelse unreachable;
  const icon_hash = IconCacheEntry.hash(tvg_bytes, ask_height);

  if (cw.icon_cache.getPtr(icon_hash)) |ice| {
    ice.used = true;
    return ice.texture;
  }

  var image = tvg.rendering.renderBuffer(
      cw.arena,
      cw.arena,
      tvg.rendering.SizeHint{ .height = @floatToInt(u32, ask_height) },
      @intToEnum(tvg.rendering.AntiAliasing, 2),
      tvg_bytes,
  ) catch unreachable;
  defer image.deinit(cw.arena);

  var surface = c.SDL_CreateRGBSurfaceWithFormatFrom(image.pixels.ptr,
    @intCast(c_int, image.width), @intCast(c_int, image.height), 32, @intCast(c_int, 4*image.width), c.SDL_PIXELFORMAT_ABGR8888);
  defer c.SDL_FreeSurface(surface);

  const texture = c.SDL_CreateTextureFromSurface(Renderer(), surface) orelse unreachable;

  var w: c_int = undefined;
  var h: c_int = undefined;
  _ = c.SDL_QueryTexture(texture, null, null, &w, &h);

  _ = name;
  //std.debug.print("created icon texture \"{s}\" ask height {d} size {d}x{d}\n", .{name, ask_height, w, h});

  const entry = IconCacheEntry{.texture = texture};
  cw.icon_cache.put(icon_hash, entry) catch unreachable;

  return texture;
}

pub fn TextTexture(font: Font, text: []const u8) *c.SDL_Texture {
  var cw = current_window orelse unreachable;
  var hash = fnv.init();
  hash.update(std.mem.asBytes(&font.size));
  hash.update(font.name);
  hash.update(text);
  const textHash = hash.final();

  if (cw.text_cache.getPtr(textHash)) |tce| {
    tce.used = true;
    return tce.texture;
  }

  //std.debug.print("creating text texture size {d} for \"{s}\"\n", .{font.size, text});

  const sdlfont = FontCacheGet(font);

  var text0 = cw.arena.allocWithOptions(u8, text.len, null, 0) catch unreachable;
  defer cw.arena.free(text0);
  std.mem.copy(u8, text0, text);

  const white = c.SDL_Color{.r = 255, .g = 255, .b = 255, .a = 255};
  const textSurface = c.TTF_RenderUTF8_Blended(sdlfont, text0, white);
  defer c.SDL_FreeSurface(textSurface);

  const ret = c.SDL_CreateTextureFromSurface(Renderer(), textSurface) orelse unreachable;

  const entry = TextCacheEntry{.texture = ret};
  cw.text_cache.put(textHash, entry) catch unreachable;

  return ret;
}

pub const RenderCmd = struct {
  clip: Rect,
  cmd: union(enum) {
    text: struct {
      font: Font,
      text: []const u8,
      rs: RectScale,
      color: Color,
    },
    icon: struct {
      name: []const u8,
      tvg_bytes: []const u8,
      rs: RectScale,
      colormod: Color,
    },
    pathFillConvex: struct {
      path: std.ArrayList(Point),
      color: Color,
    },
    pathStroke: struct {
      path: std.ArrayList(Point),
      closed: bool,
      thickness: f32,
      color: Color,
    },
  },
};

pub const DeferredRenderQueue = struct {
  cmds: std.ArrayList(RenderCmd),

  pub fn init(arena: std.mem.Allocator) DeferredRenderQueue {
    return DeferredRenderQueue{
      .cmds = std.ArrayList(RenderCmd).init(arena),
    };
  }
};

pub fn DeferRender() void {
  var cw = current_window orelse unreachable;
  const drq = DeferredRenderQueue.init(cw.arena);
  cw.deferred_render_queues.append(drq) catch unreachable;
}

pub fn DeferRenderPop() void {
  var cw = current_window orelse unreachable;
  const drq = cw.deferred_render_queues.pop();
  const len = cw.deferred_render_queues.items.len;
  if (len > 0) {
    cw.deferred_render_queues.items[len - 1].cmds.appendSlice(drq.cmds.items) catch unreachable;
    return;
  }

  const oldclip = ClipGet();
  for (drq.cmds.items) |drc| {
    ClipSet(drc.clip);
    switch (drc.cmd) {
      .text => |t| {
        renderText(t.font, t.text, t.rs, t.color);
      },
      .icon => |i| {
        renderIcon(i.name, i.tvg_bytes, i.rs, i.colormod);
      },
      .pathFillConvex => |pf| {
        cw.path.appendSlice(pf.path.items) catch unreachable;
        PathFillConvex(pf.color);
        pf.path.deinit();
      },
      .pathStroke => |ps| {
        cw.path.appendSlice(ps.path.items) catch unreachable;
        PathStroke(ps.closed, ps.thickness, ps.color);
        ps.path.deinit();
      },
    }
  }

  ClipSet(oldclip);
  drq.cmds.deinit();
}

pub fn FocusedWindow() bool {
  const cw = current_window orelse unreachable;
  if (cw.window_currentId == cw.focused_windowId) {
    return true;
  }
  
  return false;
}

pub fn FocusedWindowId() u32 {
  const cw = current_window orelse unreachable;
  return cw.focused_windowId;
}

pub fn FocusWindow(window_id: ?u32, iter: ?*EventIterator) void {
  const cw = current_window orelse unreachable;
  const winId = window_id orelse cw.window_currentId;
  if (cw.focused_windowId != winId) {
    cw.focused_windowId = winId;
    CueFrame();
    if (iter) |it| {
      if (cw.focused_windowId == cw.id) {
        it.focusRemainingEvents(cw.focused_windowId, cw.focused_widgetId);
      }
      else {
        for (cw.floating_windows.items) |*fd| {
          if (cw.focused_windowId == fd.id) {
            it.focusRemainingEvents(cw.focused_windowId, fd.focused_widgetId);
            break;
          }
        }
      }
    }
  }
}

fn optionalEqual(comptime T: type, a: ?T, b: ?T) bool {
  if (a == null and b == null) {
    return true;
  }
  else if (a == null or b == null) {
    return false;
  }
  else {
    return (a.? == b.?);
  }
}

pub fn FocusWidget(id: ?u32, iter: ?*EventIterator) void {
  const cw = current_window orelse unreachable;
  if (cw.focused_windowId == cw.id) {
    if (!optionalEqual(u32, cw.focused_widgetId, id)) {
      cw.focused_widgetId = id;
      if (iter) |it| {
        it.focusRemainingEvents(cw.focused_windowId, cw.focused_widgetId);
      }
      CueFrame();
    }
  }
  else {
    for (cw.floating_windows.items) |*fd| {
      if (cw.focused_windowId == fd.id) {
        if (!optionalEqual(u32, fd.focused_widgetId, id)) {
          fd.focused_widgetId = id;
          if (iter) |it| {
            it.focusRemainingEvents(cw.focused_windowId, cw.focused_widgetId);
          }
          CueFrame();
          break;
        }
      }
    }
  }
}

pub fn FocusedWidgetId() ?u32 {
  const cw = current_window orelse unreachable;
  if (cw.focused_windowId == cw.id) {
    return cw.focused_widgetId;
  }
  else {
    for (cw.floating_windows.items) |*fd| {
      if (cw.focused_windowId == fd.id) {
        return fd.focused_widgetId;
      }
    }
  }

  return null;
}

pub fn FocusedWidgetIdInCurrentWindow() ?u32 {
  const cw = current_window orelse unreachable;
  if (cw.window_currentId == cw.id) {
    return cw.focused_widgetId;
  }
  else {
    for (cw.floating_windows.items) |*fd| {
      if (cw.window_currentId == fd.id) {
        return fd.focused_widgetId;
      }
    }
  }

  return null;
}

pub const CursorKind = enum(u8) {
  arrow,
  ibeam,
  wait,
  crosshair,
  small_wait,
  arrow_nw_se,
  arrow_ne_sw,
  arrow_w_e,
  arrow_n_s,
  arrow_all,
  bad,
  hand,
};

pub fn cursorsCreate() void {
  if (current_window != null) {
    return;
  }

  cursor_backing[@enumToInt(CursorKind.arrow)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_ARROW) orelse unreachable;
  cursor_backing[@enumToInt(CursorKind.ibeam)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_IBEAM) orelse unreachable;
  cursor_backing[@enumToInt(CursorKind.wait)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_WAIT) orelse unreachable;
  cursor_backing[@enumToInt(CursorKind.crosshair)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_CROSSHAIR) orelse unreachable;
  cursor_backing[@enumToInt(CursorKind.arrow_nw_se)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_SIZENWSE) orelse unreachable;
  cursor_backing[@enumToInt(CursorKind.arrow_ne_sw)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_SIZENESW) orelse unreachable;
  cursor_backing[@enumToInt(CursorKind.arrow_w_e)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_SIZEWE) orelse unreachable;
  cursor_backing[@enumToInt(CursorKind.arrow_n_s)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_SIZENS) orelse unreachable;
  cursor_backing[@enumToInt(CursorKind.arrow_all)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_SIZEALL) orelse unreachable;
  cursor_backing[@enumToInt(CursorKind.bad)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_NO) orelse unreachable;
  cursor_backing[@enumToInt(CursorKind.hand)] = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_HAND) orelse unreachable;
}

pub fn CursorGetDragging() ?CursorKind {
  const cw = current_window orelse unreachable;
  return cw.cursor_dragging;
}

pub fn CursorSet(p: Point, cursor: CursorKind) void {
  const cw = current_window orelse unreachable;
  if (cw.mouse_pt.equals(p)) {
    cw.cursor_requested = cursor;
  }
}

pub fn Highlight(p: Point, r: Rect) bool {
  const cw = current_window orelse unreachable;
  if (cw.mouse_pt.equals(p) and r.contains(cw.mouse_pt)) {
    return true;
  }

  return false;
}

pub fn PathAddPoint(p: Point) void {
  const cw = current_window orelse unreachable;
  cw.path.append(p) catch unreachable;
}

pub fn PathAddRect(r: Rect, radius: Rect) void {
  var rad = radius;
  const maxrad = math.min(r.w, r.h) / 2 - 0.0001;
  rad.x = math.min(rad.x, maxrad);
  rad.y = math.min(rad.y, maxrad);
  rad.w = math.min(rad.w, maxrad);
  rad.h = math.min(rad.h, maxrad);
  PathAddArc(Point{.x = r.x + rad.x, .y = r.y + rad.x}, rad.x, math.pi * 1.5, math.pi, false);
  PathAddArc(Point{.x = r.x + rad.h, .y = r.y + r.h - rad.h}, rad.h, math.pi, math.pi * 0.5, false);
  PathAddArc(Point{.x = r.x + r.w - rad.w, .y = r.y + r.h - rad.w}, rad.w, math.pi * 0.5, 0, false);
  PathAddArc(Point{.x = r.x + r.w - rad.y, .y = r.y + rad.y}, rad.y, math.pi * 2.0, math.pi * 1.5, false);
}

pub fn PathAddArc(center: Point, rad: f32, start: f32, end: f32, skip_end: bool) void {
  if (rad == 0) {
    PathAddPoint(center);
    return;
  }
  const err = 1.0;
  // angle that has err error between circle and segments
  const theta = math.acos(1.0 - math.min(rad, err) / rad);
  // make sure we never have less than 4 segments
  // so a full circle can't be less than a diamond
  const num_segments = math.max(@ceil((start - end) / theta), 4.0);
  const step = (start - end) / num_segments;

  const num = @floatToInt(u32, num_segments);
  var a: f32 = start;
  var i: u32 = 0;
  while (i < num) : (i += 1) {
    PathAddPoint(Point{.x = center.x + rad * @cos(a), .y = center.y + rad * @sin(a)});
    a -= step;
  }

  if (!skip_end) {
    a = end;
    PathAddPoint(Point{.x = center.x + rad * @cos(a), .y = center.y + rad * @sin(a)});
  }
}

pub fn PathFillConvex(col: Color) void {
  const cw = current_window orelse unreachable;
  if (cw.path.items.len < 3) {
    cw.path.clearAndFree();
    return;
  }

  const drqlen = cw.deferred_render_queues.items.len;
  if (drqlen > 1) {
    var path_copy = std.ArrayList(Point).init(cw.arena);
    path_copy.appendSlice(cw.path.items) catch unreachable;
    var cmd = RenderCmd{.clip = ClipGet(), .cmd = .{.pathFillConvex = .{.path = path_copy, .color = col}}};
    cw.deferred_render_queues.items[drqlen-2].cmds.append(cmd) catch unreachable;
    cw.path.clearAndFree();
    return;
  }

  var vtx = std.ArrayList(c.SDL_Vertex).initCapacity(cw.arena, cw.path.items.len * 2) catch unreachable;
  defer vtx.deinit();
  const idx_count = (cw.path.items.len - 2) * 3 + cw.path.items.len * 6;
  var idx = std.ArrayList(c_int).initCapacity(cw.arena, idx_count) catch unreachable;
  defer idx.deinit();
  var col_trans = col;
  col_trans.a = 0;

  var i: usize = 0;
  while (i < cw.path.items.len) : (i += 1) {
    const ai = (i + cw.path.items.len - 1) % cw.path.items.len;
    const bi = i % cw.path.items.len;
    const ci = (i + 1) % cw.path.items.len;
    const aa = cw.path.items[ai];
    const bb = cw.path.items[bi];
    const cc = cw.path.items[ci];

    const diffab = Point.diff(aa, bb).normalize();
    const diffbc = Point.diff(bb, cc).normalize();
    // average of normals on each side
    const halfnorm = (Point{.x = (diffab.y + diffbc.y) / 2, .y = (-diffab.x - diffbc.x) / 2}).normalize().scale(0.5);

    var v: c.SDL_Vertex = undefined;
    // inner vertex
    v.position.x = bb.x - halfnorm.x;
    v.position.y = bb.y - halfnorm.y;
    v.color = col.sdlcolor();
    vtx.append(v) catch unreachable;

    // outer vertex
    v.position.x = bb.x + halfnorm.x;
    v.position.y = bb.y + halfnorm.y;
    v.color = col_trans.sdlcolor();
    vtx.append(v) catch unreachable;

    // indexes for fill
    if (i > 1) {
      idx.append(@intCast(c_int, 0)) catch unreachable;
      idx.append(@intCast(c_int, ai * 2)) catch unreachable;
      idx.append(@intCast(c_int, bi * 2)) catch unreachable;
    }

    // indexes for aa fade from inner to outer
    idx.append(@intCast(c_int, ai * 2)) catch unreachable;
    idx.append(@intCast(c_int, ai * 2 + 1)) catch unreachable;
    idx.append(@intCast(c_int, bi * 2)) catch unreachable;
    idx.append(@intCast(c_int, ai * 2 + 1)) catch unreachable;
    idx.append(@intCast(c_int, bi * 2 + 1)) catch unreachable;
    idx.append(@intCast(c_int, bi * 2)) catch unreachable;
  }

  _ = c.SDL_RenderGeometry(Renderer(), null,
    vtx.items.ptr, @intCast(c_int, vtx.items.len),
    idx.items.ptr, @intCast(c_int, idx.items.len));

  cw.path.clearAndFree();
}

pub fn PathStroke(closed_in: bool, thickness: f32, col: Color) void {
  const cw = current_window orelse unreachable;
  if (cw.path.items.len == 0) {
    return;
  }

  const drqlen = cw.deferred_render_queues.items.len;
  if (drqlen > 1) {
    var path_copy = std.ArrayList(Point).init(cw.arena);
    path_copy.appendSlice(cw.path.items) catch unreachable;
    var cmd = RenderCmd{.clip = ClipGet(), .cmd = .{.pathStroke = .{.path = path_copy, .closed = closed_in, .thickness = thickness, .color = col}}};
    cw.deferred_render_queues.items[drqlen-2].cmds.append(cmd) catch unreachable;
    cw.path.clearAndFree();
    return;
  }

  if (cw.path.items.len == 1) {
    // draw a circle with radius thickness at that point
    const center = cw.path.items[0];

    // remove old path so we don't have a center point
    cw.path.clearAndFree();

    PathAddArc(center, thickness, math.pi * 2.0, 0, true);
    PathFillConvex(col);
    cw.path.clearAndFree();
    return;
  }

  var closed: bool = closed_in;
  if (cw.path.items.len == 2) {
    // a single segment can't be closed
    closed = false;
  }

  var vtx_count = cw.path.items.len * 4;
  if (!closed) {
    vtx_count += 4;
  }
  var vtx = std.ArrayList(c.SDL_Vertex).initCapacity(cw.arena, vtx_count) catch unreachable;
  defer vtx.deinit();
  var idx_count = (cw.path.items.len - 1) * 18;
  if (closed) {
    idx_count += 18;
  }
  else {
    idx_count += 8*3;
  }
  var idx = std.ArrayList(c_int).initCapacity(cw.arena, idx_count) catch unreachable;
  defer idx.deinit();
  var col_trans = col;
  col_trans.a = 0;

  var vtx_start: usize = 0;
  var i: usize = 0;
  while (i < cw.path.items.len) : (i += 1) {
    const ai = (i + cw.path.items.len - 1) % cw.path.items.len;
    const bi = i % cw.path.items.len;
    const ci = (i + 1) % cw.path.items.len;
    const aa = cw.path.items[ai];
    var bb = cw.path.items[bi];
    const cc = cw.path.items[ci];

    // the amount to move from bb to the edge of the line
    var halfnorm: Point = undefined;

    var v: c.SDL_Vertex = undefined;
    var diffab: Point = undefined;

    if (!closed and ((i == 0) or ((i + 1) == cw.path.items.len))) {
      if (i == 0) {
        const diffbc = Point.diff(bb, cc).normalize();
        // rotate by 90 to get normal
        halfnorm = Point{.x = diffbc.y / 2, .y = (-diffbc.x) / 2};

        // square endcaps move bb out by thickness
        bb.x += diffbc.x * thickness;
        bb.y += diffbc.y * thickness;

        // add 2 extra vertexes for endcap fringe
        vtx_start += 2;

        v.position.x = bb.x - halfnorm.x * (thickness + 1.0) + diffbc.x;
        v.position.y = bb.y - halfnorm.y * (thickness + 1.0) + diffbc.y;
        v.color = col_trans.sdlcolor();
        vtx.append(v) catch unreachable;

        v.position.x = bb.x + halfnorm.x * (thickness + 1.0) + diffbc.x;
        v.position.y = bb.y + halfnorm.y * (thickness + 1.0) + diffbc.y;
        v.color = col_trans.sdlcolor();
        vtx.append(v) catch unreachable;

        // add indexes for endcap fringe
        idx.append(@intCast(c_int, 0)) catch unreachable;
        idx.append(@intCast(c_int, vtx_start)) catch unreachable;
        idx.append(@intCast(c_int, vtx_start + 1)) catch unreachable;

        idx.append(@intCast(c_int, 0)) catch unreachable;
        idx.append(@intCast(c_int, 1)) catch unreachable;
        idx.append(@intCast(c_int, vtx_start)) catch unreachable;

        idx.append(@intCast(c_int, 1)) catch unreachable;
        idx.append(@intCast(c_int, vtx_start)) catch unreachable;
        idx.append(@intCast(c_int, vtx_start + 2)) catch unreachable;

        idx.append(@intCast(c_int, 1)) catch unreachable;
        idx.append(@intCast(c_int, vtx_start + 2)) catch unreachable;
        idx.append(@intCast(c_int, vtx_start + 2 + 1)) catch unreachable;
      }
      else if ((i + 1) == cw.path.items.len) {
        diffab = Point.diff(aa, bb).normalize();
        // rotate by 90 to get normal
        halfnorm = Point{.x = diffab.y / 2, .y = (-diffab.x) / 2};

        // square endcaps move bb out by thickness
        bb.x -= diffab.x * thickness;
        bb.y -= diffab.y * thickness;
      }
    }
    else {
      diffab = Point.diff(aa, bb).normalize();
      const diffbc = Point.diff(bb, cc).normalize();
      // average of normals on each side
      halfnorm = Point{.x = (diffab.y + diffbc.y) / 2, .y = (-diffab.x - diffbc.x) / 2};

      // scale averaged normal by angle between which happens to be the same as
      // dividing by the length^2
      const d2 = halfnorm.x * halfnorm.x + halfnorm.y * halfnorm.y;
      if (d2 > 0.000001) {
        halfnorm = halfnorm.scale(0.5 / d2);
      }

      // limit distance our vertexes can be from the point to 2 * thickness so
      // very small angles don't produce huge geometries
      const l = halfnorm.length();
      if (l > 2.0) {
        halfnorm = halfnorm.scale(2.0 / l);
      }
    }

    // side 1 inner vertex
    v.position.x = bb.x - halfnorm.x * thickness;
    v.position.y = bb.y - halfnorm.y * thickness;
    v.color = col.sdlcolor();
    vtx.append(v) catch unreachable;

    // side 1 AA vertex
    v.position.x = bb.x - halfnorm.x * (thickness + 1.0);
    v.position.y = bb.y - halfnorm.y * (thickness + 1.0);
    v.color = col_trans.sdlcolor();
    vtx.append(v) catch unreachable;

    // side 2 inner vertex
    v.position.x = bb.x + halfnorm.x * thickness;
    v.position.y = bb.y + halfnorm.y * thickness;
    v.color = col.sdlcolor();
    vtx.append(v) catch unreachable;

    // side 2 AA vertex
    v.position.x = bb.x + halfnorm.x * (thickness + 1.0);
    v.position.y = bb.y + halfnorm.y * (thickness + 1.0);
    v.color = col_trans.sdlcolor();
    vtx.append(v) catch unreachable;

    if (closed or ((i + 1) != cw.path.items.len)) {
      // indexes for fill
      idx.append(@intCast(c_int, vtx_start + bi * 4)) catch unreachable;
      idx.append(@intCast(c_int, vtx_start + bi * 4 + 2)) catch unreachable;
      idx.append(@intCast(c_int, vtx_start + ci * 4)) catch unreachable;

      idx.append(@intCast(c_int, vtx_start + bi * 4 + 2)) catch unreachable;
      idx.append(@intCast(c_int, vtx_start + ci * 4 + 2)) catch unreachable;
      idx.append(@intCast(c_int, vtx_start + ci * 4)) catch unreachable;

      // indexes for aa fade from inner to outer side 1
      idx.append(@intCast(c_int, vtx_start + bi * 4)) catch unreachable;
      idx.append(@intCast(c_int, vtx_start + bi * 4 + 1)) catch unreachable;
      idx.append(@intCast(c_int, vtx_start + ci * 4 + 1)) catch unreachable;

      idx.append(@intCast(c_int, vtx_start + bi * 4)) catch unreachable;
      idx.append(@intCast(c_int, vtx_start + ci * 4 + 1)) catch unreachable;
      idx.append(@intCast(c_int, vtx_start + ci * 4)) catch unreachable;

      // indexes for aa fade from inner to outer side 2
      idx.append(@intCast(c_int, vtx_start + bi * 4 + 2)) catch unreachable;
      idx.append(@intCast(c_int, vtx_start + bi * 4 + 3)) catch unreachable;
      idx.append(@intCast(c_int, vtx_start + ci * 4 + 3)) catch unreachable;

      idx.append(@intCast(c_int, vtx_start + bi * 4 + 2)) catch unreachable;
      idx.append(@intCast(c_int, vtx_start + ci * 4 + 2)) catch unreachable;
      idx.append(@intCast(c_int, vtx_start + ci * 4 + 3)) catch unreachable;
    }
    else if (!closed and (i + 1) == cw.path.items.len) {
      // add 2 extra vertexes for endcap fringe
      v.position.x = bb.x - halfnorm.x * (thickness + 1.0) - diffab.x;
      v.position.y = bb.y - halfnorm.y * (thickness + 1.0) - diffab.y;
      v.color = col_trans.sdlcolor();
      vtx.append(v) catch unreachable;

      v.position.x = bb.x + halfnorm.x * (thickness + 1.0) - diffab.x;
      v.position.y = bb.y + halfnorm.y * (thickness + 1.0) - diffab.y;
      v.color = col_trans.sdlcolor();
      vtx.append(v) catch unreachable;

      // add indexes for endcap fringe
      idx.append(@intCast(c_int, vtx_start + bi * 4)) catch unreachable;
      idx.append(@intCast(c_int, vtx_start + bi * 4 + 1)) catch unreachable;
      idx.append(@intCast(c_int, vtx_start + bi * 4 + 4)) catch unreachable;

      idx.append(@intCast(c_int, vtx_start + bi * 4 + 4)) catch unreachable;
      idx.append(@intCast(c_int, vtx_start + bi * 4)) catch unreachable;
      idx.append(@intCast(c_int, vtx_start + bi * 4 + 2)) catch unreachable;

      idx.append(@intCast(c_int, vtx_start + bi * 4 + 4)) catch unreachable;
      idx.append(@intCast(c_int, vtx_start + bi * 4 + 2)) catch unreachable;
      idx.append(@intCast(c_int, vtx_start + bi * 4 + 5)) catch unreachable;

      idx.append(@intCast(c_int, vtx_start + bi * 4 + 2)) catch unreachable;
      idx.append(@intCast(c_int, vtx_start + bi * 4 + 3)) catch unreachable;
      idx.append(@intCast(c_int, vtx_start + bi * 4 + 5)) catch unreachable;
    }
  }

  _ = c.SDL_RenderGeometry(Renderer(), null,
    vtx.items.ptr, @intCast(c_int, vtx.items.len),
    idx.items.ptr, @intCast(c_int, idx.items.len));

  cw.path.clearAndFree();
}

pub fn WindowFor(p: Point) u32 {
  const cw = current_window orelse unreachable;
  var i = cw.floating_windows_prev.items.len;
  while (i > 0) : (i -= 1) {
    const fw = &cw.floating_windows_prev.items[i - 1];
    if (fw.modal or fw.rect.contains(p)) {
      return fw.id;
    }
  }

  return cw.id;
}

// Are we in a popup currently?
pub fn PopupIn() bool {
  const cw = current_window orelse unreachable;

  var i = cw.floating_windows.items.len;
  while (i > 0) : (i -= 1) {
    const fd = cw.floating_windows.items[i - 1];
    if (fd.id == cw.window_currentId) {
      if (fd.prevWinId != null) {
        // popup
        return true;
      }
      else {
        // not a popup
        return false;
      }
    }
  }

  return false;
}

pub fn PopupAncestorFocused(id: u32) bool {
  const cw = current_window orelse unreachable;

  var prevId = id;
  var i = cw.floating_windows.items.len;
  while (i > 0) : (i -= 1) {
    const fd = cw.floating_windows.items[i - 1];
    if (fd.id == prevId) {
      if (fd.prevWinId) |pid| {
        // popup
        if (fd.id == cw.focused_windowId) {
          return true;
        }
        prevId = pid;
      }
      else {
        // found a non popup window so stop
        return false;
      }
    }
  }

  return false;
}

pub fn FloatingWindowNoChildren() bool {
  const cw = current_window orelse unreachable;
  if (cw.floating_windows.items.len == 0) {
    return true;
  }

  const fd = cw.floating_windows.items[cw.floating_windows.items.len-1];
  if (cw.window_currentId == fd.id) {
    return true;
  }
  else {
    return false;
  }
}

pub fn FloatingWindowClosing(id: u32) void {
  const cw = current_window orelse unreachable;
  if (cw.floating_windows.items.len > 0) {
    const fd = cw.floating_windows.items[cw.floating_windows.items.len-1];
    if (fd.id == id) {
      _ = cw.floating_windows.pop();
    }
    else {
      debug("FloatingWindowClosing: last added floating window id {x} doesn't match {x}\n", .{fd.id, id});
    }
  }
  else {
    debug("FloatingWindowClosing: no floating windows\n", .{});
  }
}

pub fn FloatingWindowAdd(id: u32, prevWinId: ?u32, rect: Rect, modal: bool) void {
  const cw = current_window orelse unreachable;
  // copy focus from previous frame
  var focus_widgetId: ?u32 = null;
  for (cw.floating_windows_prev.items) |*fd| {
    if (id == fd.id) {
      focus_widgetId = fd.focused_widgetId;
      break;
    }
  }

  const fd = Window.FloatingData{.id = id, .prevWinId = prevWinId, .rect = rect, .modal = modal, .focused_widgetId = focus_widgetId};
  cw.floating_windows.append(fd) catch unreachable;
}

pub fn WindowCurrentSet(id: u32) u32 {
  const cw = current_window orelse unreachable;
  const ret = cw.window_currentId;
  cw.window_currentId = id;
  return ret;
}

pub fn WindowCurrentId() u32 {
  const cw = current_window orelse unreachable;
  return cw.window_currentId;
}

pub fn DragPreStart(p: Point, cursor: CursorKind) void {
  const cw = current_window orelse unreachable;
  cw.drag_state = .prestart;
  cw.drag_pt = p;
  cw.cursor_dragging = cursor;
}

pub fn DragStart(p: Point, cursor: CursorKind) void {
  const cw = current_window orelse unreachable;
  cw.drag_state = .dragging;
  cw.drag_pt = p;
  cw.cursor_dragging = cursor;
  DragSetCursor();
}

pub fn DragSetCursor() void {
  const cw = current_window orelse unreachable;
  cw.CursorSet(cw.cursor_dragging orelse CursorKind.arrow);
}

pub fn Dragging(p: Point) ?Point {
  const cw = current_window orelse unreachable;
  switch (cw.drag_state) {
    .none => return null,
    .dragging => {
      const dp = Point.diff(p, cw.drag_pt);
      cw.drag_pt = p;
      return dp;
    },
    .prestart => {
      const dp = Point.diff(p, cw.drag_pt);
      const dps = dp.scale(1 / WindowNaturalScale());
      if (@fabs(dps.x) > 3 or @fabs(dps.y) > 3) {
        cw.drag_pt = p;
        cw.drag_state = .dragging;
        DragSetCursor();
        return dp;
      }
      else {
        return null;
      }
    },
  }
}

pub fn DragEnd() void {
  const cw = current_window orelse unreachable;
  cw.drag_state = .none;
  // set this so that if the mouse is somewhere nobody is requesting a specific
  // cursor, it will reset
  cw.cursor_requested_last_frame = cw.cursor_dragging;
  cw.cursor_dragging = null;
}

pub fn CaptureMouse(id: ?u32) void {
  const cw = current_window orelse unreachable;
  cw.captureID = id;
  if (id != null) {
    cw.captured_last_frame = true;
  }
}

pub fn CaptureMouseMaintain(id: u32) bool {
  const cw = current_window orelse unreachable;
  if (cw.captureID == id) {
    // to maintain capture, we must be on or above the
    // top modal window
    var i = cw.floating_windows_prev.items.len;
    while (i > 0) : (i -= 1) {
      const fw = &cw.floating_windows_prev.items[i - 1];
      if (fw.id == cw.window_currentId) {
        // maintaining capture
        break;
      }
      else if (fw.modal) {
        // found modal before we found current
        // cancel the capture, and cancel
        // any drag being done
        DragEnd();
        return false;
      }
    }

    // either our floating window as above the top modal
    // or there are no floating modal windows
    cw.captured_last_frame = true;
    return true;
  }

  return false;
}

pub fn CaptureMouseGet() ?u32 {
  const cw = current_window orelse unreachable;
  return cw.captureID;
}

fn ClipGet() Rect {
  const cw = current_window orelse unreachable;
  return cw.clipRect;
}

fn Clip(new: Rect) Rect {
  const cw = current_window orelse unreachable;
  var ret = cw.clipRect;
  ClipSet(cw.clipRect.intersect(new));
  return ret;
}

fn ClipSet(r: Rect) void {
  const cw = current_window orelse unreachable;
  cw.clipRect = r;
  const clip = c.SDL_Rect{.x = @floatToInt(c_int, r.x),
                          .y = @floatToInt(c_int, r.y),
                          .w = math.max(1, @floatToInt(c_int, @ceil(r.w))),
                          .h = math.max(1, @floatToInt(c_int, @ceil(r.h)))};
  _ = c.SDL_RenderSetClipRect(Renderer(), &clip);
}

pub fn CueFrame() void {
  const cw = current_window orelse unreachable;
  cw.extra_frames_needed = 1;
}

pub fn AnimationRate() f32 {
  const cw = current_window orelse unreachable;
  return cw.rate;
}

pub fn FPS() f32 {
  const cw = current_window orelse unreachable;
  return cw.FPS();
}

pub fn ParentGet() Widget {
  const cw = current_window orelse unreachable;
  return cw.parent;
}

pub fn ParentSet(w: Widget) Widget {
  var cw = current_window orelse unreachable;
  const ret = cw.parent;
  cw.parent = w;
  return ret;
}

pub fn MenuGet() ?*MenuWidget {
  const cw = current_window orelse unreachable;
  return cw.menu_current;
}

pub fn MenuSet(m: ?*MenuWidget) ?*MenuWidget {
  var cw = current_window orelse unreachable;
  const ret = cw.menu_current;
  cw.menu_current = m;
  return ret;
}

pub fn WindowRect() Rect {
  var cw = current_window orelse unreachable;
  return cw.rect;
}

pub fn WindowRectPixels() Rect {
  var cw = current_window orelse unreachable;
  return cw.rect_pixels;
}

pub fn WindowNaturalScale() f32 {
  var cw = current_window orelse unreachable;
  return cw.natural_scale;
}

pub fn Renderer() *c.SDL_Renderer {
  var cw = current_window orelse unreachable;
  return cw.renderer;
}

pub fn MinSizeGetPrevious(id: u32) ?Size {
  var cw = current_window orelse unreachable;
  const ret = cw.widgets_min_size_prev.get(id);
  debug("{x} MinSizeGetPrevious {}", .{id, ret});
  return ret;
}

pub fn MinSizeSet(id: u32, s: Size) void {
  debug("{x} MinSizeSet {}", .{id, s});
  var cw = current_window orelse unreachable;
  return cw.widgets_min_size.put(id, s) catch unreachable;
}

const DataOffset = struct {
  begin: u32,
  end: u32,
};

pub fn DataSet(id: u32, data: anytype) void {
  var cw = current_window orelse unreachable;
  var bytes: []const u8 = undefined;
  const dt = @typeInfo(@TypeOf(data));
  if (dt == .Pointer and dt.Pointer.size == .Slice) {
    bytes = std.mem.sliceAsBytes(data);
  }
  else {
    bytes = std.mem.asBytes(&data);
  }
  const begin = @intCast(u32, cw.data.items.len);
  cw.data.appendSlice(bytes) catch unreachable;
  const end = @intCast(u32, cw.data.items.len);
  cw.data_offset.put(id, DataOffset{.begin = begin, .end = end}) catch unreachable;
}

pub fn DataGet(id: u32, comptime T: type) ?T {
  var cw = current_window orelse unreachable;
  const offset = cw.data_offset_prev.get(id);
  if (offset) |o| {
    var bytes: [@sizeOf(T)]u8 = undefined;
    std.mem.copy(u8, &bytes, cw.data_prev.items[o.begin..o.end]);
    return std.mem.bytesAsValue(T, &bytes).*;
  }
  else {
    return null;
  }
}

pub fn DataGetSlice(id: u32, comptime T: type, arena: std.mem.Allocator) ?[]T {
  var cw = current_window orelse unreachable;
  const offset = cw.data_offset_prev.get(id);
  if (offset) |o| {
    var slice = arena.alloc(T, @divExact(o.end - o.begin, @sizeOf(T))) catch unreachable; 
    var bytes: []u8 = std.mem.sliceAsBytes(slice);
    std.mem.copy(u8, bytes, cw.data_prev.items[o.begin..o.end]);
    return slice;
  }
  else {
    return null;
  }
}

pub fn MinSize(id: ?u32, opts: ?Options) Size {
  var size = Size{};
  if (opts) |options| {
    if (options.min_size) |ms| {
      size = ms;
    }
  }

  // Need to take the max of both given and previous.  ScrollArea could be
  // passed a min size Size{.w = 0, .h = 200} meaning to get the width from the
  // previous min size.
  if (id) |id2| {
    if (MinSizeGetPrevious(id2)) |ms| {
      size = Size.max(size, ms);
    }
  }

  return size;
}

pub fn PlaceIn(id: ?u32, parentR: Rect, opts: Options) Rect {
  var size = MinSize(id, opts);

  if (opts.expandHorizontal()) {
    size.w = parentR.w;
  }

  if (opts.expandVertical()) {
    size.h = parentR.h;
  }

  const r = parentR.shrinkToSize(size);
  return opts.gravitate(r, parentR);
}

pub fn Events() *[]Event {
  var cw = current_window orelse unreachable;
  return &cw.events.items;
}

pub const EventIterator = struct {
  const Self = @This();
  id: u32,
  i: u32,
  r: Rect,

  pub fn init(id: u32, r: Rect) Self {
    return Self{.id = id, .i = 0, .r = r};
  }

  pub fn focusRemainingEvents(self: *Self, focusWindowId: u32, focusWidgetId: ?u32) void {
    var k = self.i;
    var events = Events();
    while (k < events.len) : (k += 1) {
      var e: *Event = &events.*[k];
      e.focus_windowId = focusWindowId;
      e.focus_widgetId = focusWidgetId;
    }
  }

  pub fn next(self: *Self) ?*Event {
    return self.nextCleanup(false);
  }

  pub fn nextCleanup(self: *Self, cleanup: bool) ?*Event {
    var events = Events();
    while (self.i < events.len) : (self.i += 1) {
      var e: *Event = &events.*[self.i];
      if (e.handled) {
        continue;
      }

      switch (e.evt) {
        .key,
        .text, => {
          if (cleanup) {
            // window is catching all focus-routed events that didn't get
            // processed (maybe the focus widget never showed up)
            if (e.focus_windowId != self.id) {
              continue;
            }
          }
          else {
            if (e.focus_widgetId != self.id) {
              continue;
            }
          }
        },

        .mouse => {
          if (CaptureMouseGet()) |id| {
            if (id != self.id) {
              continue;
            }
          }
          else {
            if (e.evt.mouse.floating_win != WindowCurrentId()) {
              continue;
            }

            if (!self.r.contains(e.evt.mouse.p)) {
              continue;
            }

            if (!ClipGet().contains(e.evt.mouse.p)) {
              continue;
            }
          }
        },

        .close_popup => unreachable,
      }

      self.i += 1;
      return e;
    }

    return null;
  }
};

pub const AnimationProperty = enum(u8) {
  timer,
  alpha,
  angle,
  xoffset,
  split_ratio,
  first_user,
  _,
};

pub const Animation = struct {
  start_val: f32,
  end_val: f32,
  start_time: i32 = 0,
  end_time: i32,

  pub fn lerp(a: *const Animation) f32 {
    var frac = @intToFloat(f32, -a.start_time) / @intToFloat(f32, a.end_time - a.start_time);
    frac = math.max(0, math.min(1, frac));
    return a.start_val + frac * (a.end_val - a.start_val);
  }
};

pub fn Animate(id: u32, prop: AnimationProperty, a: Animation) void {
  var cw = current_window orelse unreachable;
  var hash = fnv.init();
  hash.value = id;
  hash.update(std.mem.asBytes(&@enumToInt(prop)));
  cw.animations.put(hash.final(), a) catch unreachable;
}

pub fn AnimationGet(id: u32, prop: AnimationProperty) ?Animation {
  var cw = current_window orelse unreachable;
  var hash = fnv.init();
  hash.value = id;
  hash.update(std.mem.asBytes(&@enumToInt(prop)));
  return cw.animations.get(hash.final());
}

pub fn TimerSet(id: u32, micros: i32) void {
  const a = Animation{.start_val = 0, .end_val = 0, .start_time = micros, .end_time = micros};
  Animate(id, .timer, a);
}

pub fn TimerGet(id: u32) ?i32 {
  if (AnimationGet(id, .timer)) |a| {
    return a.start_time;
  }
  else {
    return null;
  }
}

pub fn TimerExists(id: u32) bool {
  return TimerGet(id) != null;
}

// returns true only on the frame where the timer expired
pub fn TimerDone(id: u32) bool {
  if (TimerGet(id)) |start| {
    if (start <= 0) {
      return true;
    }
  }

  return false;
}

const TabIndex = struct {
  windowId: u32,
  widgetId: u32,
  tabIndex: u16,
};

pub fn TabIndexSet(widget_id: u32, tab_index: ?u16) void {
  var cw = current_window orelse unreachable;
  const ti = TabIndex{.windowId = cw.window_currentId, .widgetId = widget_id, .tabIndex = (tab_index orelse math.maxInt(u16))};
  cw.tab_index.append(ti) catch unreachable;
}

pub fn TabIndexNext(iter: ?*EventIterator) void {
  const cw = current_window orelse unreachable;
  const widgetId = FocusedWidgetId();
  var oldtab: ?u16 = null;
  if (widgetId != null) {
    for (cw.tab_index_prev.items) |ti| {
      if (ti.windowId == cw.focused_windowId and ti.widgetId == widgetId.?) {
        oldtab = ti.tabIndex;
        break;
      }
    }
  }

  // find the first widget with a tabindex greater than oldtab
  // or the first widget with lowest tabindex if oldtab is null
  var newtab: u16 = math.maxInt(u16);
  var newId: ?u32 = null;
  var foundFocus = false;

  for (cw.tab_index_prev.items) |ti| {
    if (ti.windowId == cw.focused_windowId) {
      if (ti.widgetId == widgetId) {
        foundFocus = true;
      }
      else if (foundFocus == true and oldtab != null and ti.tabIndex == oldtab.?) {
        // found the first widget after current that has the same tabindex
        newtab = ti.tabIndex;
        newId = ti.widgetId;
        break;
      }
      else if (oldtab == null or ti.tabIndex > oldtab.?) {
        if (newId == null or ti.tabIndex < newtab) {
          newtab = ti.tabIndex;
          newId = ti.widgetId;
        }
      }
    }
  }

  FocusWidget(newId, iter);
}

pub fn TabIndexPrev(iter: ?*EventIterator) void {
  const cw = current_window orelse unreachable;
  const widgetId = FocusedWidgetId();
  var oldtab: ?u16 = null;
  if (widgetId != null) {
    for (cw.tab_index_prev.items) |ti| {
      if (ti.windowId == cw.focused_windowId and ti.widgetId == widgetId.?) {
        oldtab = ti.tabIndex;
        break;
      }
    }
  }

  // find the last widget with a tabindex less than oldtab
  // or the last widget with highest tabindex if oldtab is null
  var newtab: u16 = 0;
  var newId: ?u32 = null;
  var foundFocus = false;

  for (cw.tab_index_prev.items) |ti| {
    if (ti.windowId == cw.focused_windowId) {
      if (ti.widgetId == widgetId) {
        foundFocus = true;

        if (oldtab != null and newtab == oldtab.?) {
          // use last widget before that has the same tabindex
          // might be none before so we'll go to null
          break;
        }
      }
      else if (oldtab == null or ti.tabIndex < oldtab.? or (!foundFocus and ti.tabIndex == oldtab.?)) {
        if (ti.tabIndex >= newtab) {
          newtab = ti.tabIndex;
          newId = ti.widgetId;
        }
      }
    }
  }

  FocusWidget(newId, iter);
}

// maps to OS window
pub const Window = struct {
  const Self = @This();

  pub const FloatingData = struct {
    id: u32 = 0,
    prevWinId: ?u32 = 0,
    rect: Rect = Rect{},
    modal: bool = false,
    focused_widgetId: ?u32 = null,
  };

  floating_windows_prev: std.ArrayList(FloatingData),
  floating_windows: std.ArrayList(FloatingData),

  window_currentId: u32 = 0,

  focused_windowId: u32 = 0,
  focused_widgetId: ?u32 = null, // this is specific to the base window
  focused_widgetId_last_frame: ?u32 = null, // only used to intially mark events

  events: std.ArrayList(Event) = undefined,
  // mouse_pt tracks the last position we got a mouse event for
  // 1) used to add position info to mouse wheel events
  // 2) used to highlight the widget under the mouse
  // 3) used to change the cursor (for the final point each frame)
  // Start off screen so nothing is highlighted on the first frame
  mouse_pt: Point = Point{.x = -1, .y = -1},

  drag_state: enum {
    none,
    prestart,
    dragging,
  } = .none,
  drag_pt: Point = Point{},

  frame_time_ns: i128 = 0,
  loop_wait_target: ?i128 = null,
  loop_target_slop: i32 = 0,
  loop_target_slop_frames: i32 = 0,
  frame_times: [30]u32 = [_]u32{0} ** 30,

  rate: f32 = 0,
  extra_frames_needed: u8 = 0,
  clipRect: Rect = Rect{},

  parent: Widget = undefined,
  menu_current: ?*MenuWidget = null,
  options: Options = .{},
  widgets_min_size_prev: std.AutoHashMap(u32, Size),
  widgets_min_size: std.AutoHashMap(u32, Size),
  data_prev: std.ArrayList(u8),
  data: std.ArrayList(u8),
  data_offset_prev: std.AutoHashMap(u32, DataOffset),
  data_offset: std.AutoHashMap(u32, DataOffset),
  animations: std.AutoHashMap(u32, Animation),
  tab_index_prev: std.ArrayList(TabIndex),
  tab_index: std.ArrayList(TabIndex),
  text_cache: std.AutoHashMap(u32, TextCacheEntry),
  font_cache: std.AutoHashMap(u32, FontCacheEntry),
  icon_cache: std.AutoHashMap(u32, IconCacheEntry),
  deferred_render_queues: std.ArrayList(DeferredRenderQueue) = undefined,

  window: *c.SDL_Window,
  renderer: *c.SDL_Renderer,

  cursor_requested_last_frame: ?CursorKind = null,
  cursor_requested: ?CursorKind = null,
  cursor_current: CursorKind = CursorKind.arrow,
  cursor_dragging: ?CursorKind = null,

  defer_render: bool = false,

  id: u32 = 0,
  rect_pixels: Rect = Rect{},  // pixels
  natural_scale: f32 = 1.0,
  rect: Rect = Rect{},  // unscaled
  layout: BoxWidget = undefined,

  captureID: ?u32 = null,
  captured_last_frame: bool = false,

  arena: std.mem.Allocator = undefined,
  path: std.ArrayList(Point) = undefined,

  pub fn init(gpa: std.mem.Allocator, window: *c.SDL_Window, renderer: *c.SDL_Renderer) Self {
    var self = Self{.floating_windows_prev = std.ArrayList(FloatingData).init(gpa),
                    .floating_windows = std.ArrayList(FloatingData).init(gpa),
                    .widgets_min_size = std.AutoHashMap(u32, Size).init(gpa),
                    .widgets_min_size_prev = std.AutoHashMap(u32, Size).init(gpa),
                    .data_prev = std.ArrayList(u8).init(gpa),
                    .data = std.ArrayList(u8).init(gpa),
                    .data_offset_prev = std.AutoHashMap(u32, DataOffset).init(gpa),
                    .data_offset = std.AutoHashMap(u32, DataOffset).init(gpa),
                    .animations = std.AutoHashMap(u32, Animation).init(gpa),
                    .tab_index_prev = std.ArrayList(TabIndex).init(gpa),
                    .tab_index = std.ArrayList(TabIndex).init(gpa),
                    .text_cache = std.AutoHashMap(u32, TextCacheEntry).init(gpa),
                    .font_cache = std.AutoHashMap(u32, FontCacheEntry).init(gpa),
                    .icon_cache = std.AutoHashMap(u32, IconCacheEntry).init(gpa),
                    .window = window,
                    .id = fnv.init().final(),
                    .renderer = renderer};

    self.focused_windowId = self.id;
    self.frame_time_ns = std.time.nanoTimestamp();

    return self;
  }

  pub fn addEvent(self: *Self, event: c.SDL_Event) void {
    switch (event.type) {
      c.SDL_KEYDOWN => {
        self.events.append(Event{
          .focus_windowId = self.focused_windowId,
          .focus_widgetId = self.focused_widgetId_last_frame,
          .evt = AnyEvent{.key = KeyEvent{
            .state = if (event.key.repeat > 0) .repeat else .down,
            .keysym = event.key.keysym.sym,
            .mod = event.key.keysym.mod,
          }}
        }) catch unreachable;
      },
      c.SDL_TEXTINPUT => {
        self.events.append(Event{
          .focus_windowId = self.focused_windowId,
          .focus_widgetId = self.focused_widgetId_last_frame,
          .evt = AnyEvent{.text = TextEvent{
            .text = event.text.text,
          }}
        }) catch unreachable;
      },
      c.SDL_MOUSEMOTION => {
        self.mouse_pt.x = @intToFloat(f32, event.motion.x) * self.natural_scale;
        self.mouse_pt.y = @intToFloat(f32, event.motion.y) * self.natural_scale;
        self.events.append(Event{
          .focus_windowId = self.focused_windowId,
          .focus_widgetId = self.focused_widgetId_last_frame,
          .evt = AnyEvent{.mouse = MouseEvent{
            .p = self.mouse_pt,
            .dp = Point{.x = @intToFloat(f32, event.motion.xrel) * self.natural_scale,
                        .y = @intToFloat(f32, event.motion.yrel) * self.natural_scale},
            .wheel = 0,
            .floating_win = WindowFor(self.mouse_pt),
            .state = .motion,
          }}
        }) catch unreachable;
      },
      c.SDL_MOUSEBUTTONDOWN, c.SDL_MOUSEBUTTONUP => |updown| {
        self.mouse_pt.x = @intToFloat(f32, event.button.x) * self.natural_scale;
        self.mouse_pt.y = @intToFloat(f32, event.button.y) * self.natural_scale;
        const winId = WindowFor(self.mouse_pt);

        if (updown == c.SDL_MOUSEBUTTONDOWN) {
          FocusWindow(winId, null);
        }

        var state: MouseEvent.Kind = undefined;
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

        self.events.append(Event{
          .focus_windowId = self.focused_windowId,
          .focus_widgetId = self.focused_widgetId_last_frame,
          .evt = AnyEvent{.mouse = MouseEvent{
            .p = self.mouse_pt,
            .dp = Point{},
            .wheel = 0,
            .floating_win = winId,
            .state = state,
          }}
        }) catch unreachable;
      },
      c.SDL_MOUSEWHEEL => {
        const ticks = @intToFloat(f32, event.wheel.y);
        self.events.append(Event{
          .focus_windowId = self.focused_windowId,
          .focus_widgetId = self.focused_widgetId_last_frame,
          .evt = AnyEvent{.mouse = MouseEvent{
            .p = self.mouse_pt,
            .dp = Point{},
            .wheel = ticks,
            .floating_win = WindowFor(self.mouse_pt),
            .state = .wheel_y,
          }}
        }) catch unreachable;
      },
      else => {},
    }
  }

  pub fn endEvents(self: *Self) void {
    var haveMotion: bool = false;
    for (self.events.items) |e| {
      if (e.evt == .mouse and e.evt.mouse.state == .motion) {
        haveMotion = true;
        break;
      }
    }

    // synthesize a zero mouse motion event so that we can do mouse cursors
    // using the motion event path
    if (!haveMotion) {
      self.events.append(Event{
        .evt = AnyEvent{.mouse = MouseEvent{
          .p = self.mouse_pt,
          .dp = Point{},
          .wheel = 0,
          .floating_win = WindowFor(self.mouse_pt),
          .state = .motion,
        }}
      }) catch unreachable;
    }
  }

  pub fn FPS(self: *const Self) f32 {
    const diff = self.frame_times[0];
    if (diff == 0) {
      return 0;
    }

    const avg = @intToFloat(f32, diff) / @intToFloat(f32, self.frame_times.len - 1);
    const fps = 1_000_000.0 / avg;
    return fps;
  }

  pub fn begin(self: *Self, arena: std.mem.Allocator) void {
    var new_time = math.max(self.frame_time_ns, std.time.nanoTimestamp());

    if (self.loop_wait_target) |target| {
      // we were trying to sleep for a specific amount of time, adjust slop to
      // compensate if we didn't hit our target
      if (new_time > target) {
        // woke up later than expected
        self.loop_target_slop_frames = math.max(1, self.loop_target_slop_frames + 1);
        self.loop_target_slop += self.loop_target_slop_frames;
      }
      else if (new_time < target) {
        // woke up sooner than expected
        self.loop_target_slop_frames = math.min(-1, self.loop_target_slop_frames - 1);
        self.loop_target_slop += self.loop_target_slop_frames;

        // since we are early, spin a bit to guarantee that we never run before
        // the target
        //var i: usize = 0;
        //var first_time = new_time;
        while (new_time < target) {
          //i += 1;
          std.time.sleep(0);
          new_time = math.max(self.frame_time_ns, std.time.nanoTimestamp());
        }

        //if (i > 0) {
        //  std.debug.print("    begin {d} spun {d} {d}us\n", .{self.loop_target_slop, i, @divFloor(new_time - first_time, 1000)});
        //}
      }
    }

    //std.debug.print("begin {d:6}\n", .{self.loop_target_slop});
    self.beginNoTiming(arena, new_time);
  }

  pub fn end(self: *Self, maxFPS: ?f32) void {
    // naive micros we want to be between last begin and next begin
    const end_micros = self.endNoTiming();

    // minimum time to wait to hit max fps target
    var min_micros: u32 = 0;
    if (maxFPS) |mfps| {
      min_micros = @floatToInt(u32, 1_000_000.0 / mfps);
    }

    //std.debug.print("  end {d:6} min {d:6}", .{end_micros, min_micros});

    // wait_micros is amount on top of min_micros we will conditionally wait
    var wait_micros = (end_micros orelse 0) -| min_micros;

    // assume that we won't target a specific time to sleep but if we do
    // calculate the targets before removing so_far and slop
    self.loop_wait_target = null;
    const target_min = min_micros;
    const target = min_micros + wait_micros;

    // how long it's taken from begin to here
    const so_far_nanos = math.max(self.frame_time_ns, std.time.nanoTimestamp()) - self.frame_time_ns;
    var so_far_micros = @intCast(u32, @divFloor(so_far_nanos, 1000));
    //std.debug.print("  far {d:6}", .{so_far_micros});
    
    // take time from min_micros first
    const min_so_far = math.min(so_far_micros, min_micros);
    so_far_micros -= min_so_far;
    min_micros -= min_so_far;

    // then take time from wait_micros
    const min_so_far2 = math.min(so_far_micros, wait_micros);
    so_far_micros -= min_so_far2;
    wait_micros -= min_so_far2;

    var slop = self.loop_target_slop;

    // get slop we can take out of min_micros
    const min_us_slop = math.min(slop, min_micros);
    slop -= min_us_slop;
    if (min_us_slop >= 0) {
      min_micros -= @intCast(u32, min_us_slop);
    }
    else {
      min_micros += @intCast(u32, -min_us_slop);
    }

    // remaining slop we can take out of wait_micros
    const wait_us_slop = math.min(slop, wait_micros);
    slop -= wait_us_slop;
    if (wait_us_slop >= 0) {
      wait_micros -= @intCast(u32, wait_us_slop);
    }
    else {
      wait_micros += @intCast(u32, -wait_us_slop);
    }

    //std.debug.print("  min {d:6}", .{min_micros});
    if (min_micros > 0) {
      // wait unconditionally for fps target
      std.time.sleep(min_micros * 1000);
      self.loop_wait_target = self.frame_time_ns + (target_min * 1000);
    }

    if (c.SDL_PollEvent(null) == 1) {
      // there is already an event
      //std.debug.print("  wait event\n", .{});
      // if we had a wait target from min_micros leave it
      return;
    }

    if (end_micros == null) {
      // no target, wait indefinitely for next event
      //std.debug.print("  wait indef\n", .{});
      _ = c.SDL_WaitEvent(null);
      self.loop_wait_target = null;
    }
    else if (wait_micros > 0) {
      // wait conditionally
      //std.debug.print("  wait {d:6}\n", .{wait_micros});
      const result = c.SDL_WaitEventTimeout(null, @intCast(c_int, wait_micros / 1000));
      if (result == 1) {
        // interuppted by event, so don't adjust slop for target
        self.loop_wait_target = null;
      }
      else {
        // timeout so we are trying to hit the target
        self.loop_wait_target = self.frame_time_ns + (target * 1000);
      }
    }
    else {
      // trying to hit the target but ran out of time
      //std.debug.print("  wait none\n", .{});
      // if we had a wait target from min_micros leave it
    }
  }

  pub fn beginNoTiming(self: *Self, arena: std.mem.Allocator, time_ns: i128) void {
    var micros_since_last: u32 = 0;
    if (time_ns > self.frame_time_ns) {
      // enforce monotinicity
      const nanos_since_last = time_ns - self.frame_time_ns;
      micros_since_last = @intCast(u32, @divFloor(nanos_since_last, std.time.ns_per_us));
      self.frame_time_ns = time_ns;
    }

    //std.debug.print(" frame_time_ns {d}\n", .{self.frame_time_ns});

    cursorsCreate();
    current_window = self;
    self.defer_render = false;

    self.cursor_requested_last_frame = self.cursor_requested;
    self.cursor_requested = null;

    self.arena = arena;
    self.path = std.ArrayList(Point).init(arena);
    self.deferred_render_queues = std.ArrayList(DeferredRenderQueue).init(arena);

    // setup the initial deferred render queue, won't be used until someone
    // calls DeferRender again
    DeferRender();

    self.events = std.ArrayList(Event).init(arena);

    for (self.frame_times) |_, i| {
      if (i == (self.frame_times.len - 1)) {
        self.frame_times[i] = 0;
      } else {
        self.frame_times[i] = self.frame_times[i+1] + micros_since_last;
      }
    }

    // FocusedWindowLost uses floating_windows, so use it before we swap
    if (self.FocusedWindowLost()) {
      // if the floating window that was focused went away, focus the highest
      // remaining one
      if (self.floating_windows.items.len > 0) {
        const data = self.floating_windows.items[self.floating_windows.items.len-1];
        FocusWindow(data.id, null);
      }
      else {
        FocusWindow(self.id, null);
      }
    }

    // FocusedWidgetId() uses floating_windows, so use it before we swap
    self.focused_widgetId_last_frame = FocusedWidgetId();

    self.floating_windows_prev.deinit();
    self.floating_windows_prev = self.floating_windows;
    self.floating_windows = @TypeOf(self.floating_windows).init(self.floating_windows.allocator);

    self.widgets_min_size_prev.deinit();
    self.widgets_min_size_prev = self.widgets_min_size;
    self.widgets_min_size = @TypeOf(self.widgets_min_size).init(self.widgets_min_size.allocator);

    self.data_prev.deinit();
    self.data_prev = self.data;
    self.data = @TypeOf(self.data).init(self.data.allocator);

    self.data_offset_prev.deinit();
    self.data_offset_prev = self.data_offset;
    self.data_offset = @TypeOf(self.data_offset).init(self.data_offset.allocator);

    self.tab_index_prev.deinit();
    self.tab_index_prev = self.tab_index;
    self.tab_index = @TypeOf(self.tab_index).init(self.tab_index.allocator);

    var pixel_w: i32 = undefined;
    var pixel_h: i32 = undefined;
    _ = c.SDL_GetRendererOutputSize(self.renderer, &pixel_w, &pixel_h);
    self.rect_pixels = Rect{.x = 0, .y = 0, .w = @intToFloat(f32, pixel_w), .h = @intToFloat(f32, pixel_h)};
    ClipSet(self.rect_pixels);

    _ = c.SDL_SetRenderDrawColor(self.renderer, 75, 75, 75, 255);
    _ = c.SDL_RenderClear(self.renderer);

    var window_w: i32 = undefined;
    var window_h: i32 = undefined;
    _ = c.SDL_GetWindowSize(self.window, &window_w, &window_h);
    self.rect = Rect{.x = 0, .y = 0, .w = @intToFloat(f32, window_w), .h = @intToFloat(f32, window_h)};
    self.natural_scale = self.rect_pixels.w / self.rect.w; 

    debug("window size {d} x {d} renderer size {d} x {d} scale {d}", .{self.rect.w, self.rect.h, self.rect_pixels.w, self.rect_pixels.h, self.natural_scale});

    _ = WindowCurrentSet(self.id);

    self.extra_frames_needed -|= 1;
    if (micros_since_last == 0) {
      self.rate = 3600;
    }
    else {
      self.rate = @intToFloat(f32, micros_since_last) / 1_000_000;
    }

    {
      const micros: i32 = if (micros_since_last > math.maxInt(i32)) math.maxInt(i32) else @intCast(i32, micros_since_last);
      var deadAnimations = std.ArrayList(u32).init(arena);
      defer deadAnimations.deinit();
      var it = self.animations.iterator();
      while (it.next()) |kv| {
        if (kv.value_ptr.end_time <= 0) {
          deadAnimations.append(kv.key_ptr.*) catch unreachable;
        }
        else {
          kv.value_ptr.start_time -|= micros;
          kv.value_ptr.end_time -|= micros;
          if (kv.value_ptr.start_time <= 0 and kv.value_ptr.end_time > 0) {
            CueFrame();
          }
        }
      }

      for (deadAnimations.items) |id| {
        _ = self.animations.remove(id);
      }
    }

    {
      var deadTexts = std.ArrayList(u32).init(arena);
      defer deadTexts.deinit();
      var it = self.text_cache.iterator();
      while (it.next()) |kv| {
        if (kv.value_ptr.used) {
          kv.value_ptr.used = false;
        }
        else {
          deadTexts.append(kv.key_ptr.*) catch unreachable;
        }
      }

      for (deadTexts.items) |id| {
        const tce = self.text_cache.fetchRemove(id);
        c.SDL_DestroyTexture(tce.?.value.texture);
      }

      //std.debug.print("text_cache {d}\n", .{self.text_cache.count()});
    }

    {
      var deadFonts = std.ArrayList(u32).init(arena);
      defer deadFonts.deinit();
      var it = self.font_cache.iterator();
      while (it.next()) |kv| {
        if (kv.value_ptr.used) {
          kv.value_ptr.used = false;
        }
        else {
          deadFonts.append(kv.key_ptr.*) catch unreachable;
        }
      }

      for (deadFonts.items) |id| {
        const tce = self.font_cache.fetchRemove(id);
        c.TTF_CloseFont(tce.?.value.ttf_font);
      }

      //std.debug.print("font_cache {d}\n", .{self.font_cache.count()});
    }

    {
      var deadIcons = std.ArrayList(u32).init(arena);
      defer deadIcons.deinit();
      var it = self.icon_cache.iterator();
      while (it.next()) |kv| {
        if (kv.value_ptr.used) {
          kv.value_ptr.used = false;
        }
        else {
          deadIcons.append(kv.key_ptr.*) catch unreachable;
        }
      }

      for (deadIcons.items) |id| {
        const ice = self.icon_cache.fetchRemove(id);
        c.SDL_DestroyTexture(ice.?.value.texture);
      }

      //std.debug.print("icon_cache {d}\n", .{self.icon_cache.count()});
    }

    if (!self.captured_last_frame) {
      self.captureID = null;
    }
    self.captured_last_frame = false;

    self.parent = self.widget();
    self.menu_current = null;

    OptionsReset(.{.theme = &Theme_Adwaita});

    self.layout = BoxWidget{};
    self.layout.init(@src(), 0, .vertical, .{.expand = .both, .color_style = .window, .background = true});
    self.layout.install();
  }

  pub fn CursorSet(self: *Self, cursor: CursorKind) void {
    if (cursor != self.cursor_current) {
      self.cursor_current = cursor;
      c.SDL_SetCursor(cursor_backing[@enumToInt(cursor)]);
    }
  }

  pub fn endNoTiming(self: *Self) ?u32 {
    self.layout.deinit();

    DeferRenderPop();

    c.SDL_RenderPresent(Renderer());

    // events may have been tagged with a focus widget that never showed up, so
    // we wouldn't even get them bubbled
    var iter = EventIterator.init(self.id, self.rect_pixels);
    while (iter.nextCleanup(true)) |e| {
      // doesn't matter if we mark events has handled or not because this is
      // the end of the line for all events
      if (e.evt == .mouse) {
        if (e.evt.mouse.state == .leftdown or e.evt.mouse.state == .rightdown) {
          // unhandled click, clear focus
          FocusWidget(null, null);
        }
      }
      else if (e.evt == .key) {
        if (e.evt.key.state == .down and e.evt.key.keysym == c.SDLK_TAB) {
          if ((e.evt.key.mod & c.KMOD_SHIFT) > 0) {
            TabIndexPrev(&iter);
          }
          else {
            TabIndexNext(&iter);
          }
        }
      }
    }

    if (self.drag_state != .dragging) {
      if (self.cursor_requested) |cursor| {
        self.CursorSet(cursor);
      }
      else if (self.cursor_requested_last_frame != null) {
        self.CursorSet(CursorKind.arrow);
      }
    }
    
    if (self.FocusedWindowLost()) {
      // The floating window with focus disappeared, so do another frame and
      // we'll focus a new window in begin()
      CueFrame();
    }

    // This is what CueFrame affects
    if (self.extra_frames_needed > 0) {
      return 0;
    }

    // If there are current animations, return 0 so we go as fast as we can.
    // If all animations are scheduled in the future, pick the soonest start.
    var ret: ?u32 = null;
    var it = self.animations.iterator();
    while (it.next()) |kv| {
      if (kv.value_ptr.start_time > 0) {
        const st = @intCast(u32, kv.value_ptr.start_time);
        ret = math.min(ret orelse st, st);
      }
      else if (kv.value_ptr.end_time > 0) {
        ret = 0;
        break;
      }
    }

    return ret;
  }

  pub fn FocusedWindowLost(self: *Self) bool {
    if (self.id == self.focused_windowId) {
      return false;
    }
    else {
      for (self.floating_windows.items) |*fw| {
        if (fw.id == self.focused_windowId) {
          return false;
        }
      }
    }

    return true;
  }

  fn widget(self: *Self) Widget {
    return Widget.init(self, ID, rectFor, minSizeForChild, screenRectScale, bubbleEvent);
  }

  fn ID(self: *const Self) u32 {
    return self.id;
  }

  pub fn rectFor(self: *Self, id: u32, opts: Options) Rect {
    return PlaceIn(id, self.rect, opts);
  }

  pub fn minSizeForChild(self: *Self, s: Size) void {
    // the base window doesn't react to min sizes
    _ = self;
    _ = s;
  }

  pub fn screenRectScale(self: *Self, r: Rect) RectScale {
    const scaled = r.scale(self.natural_scale);
    return RectScale{.r = scaled.offset(self.rect_pixels), .s = self.natural_scale};
  }

  pub fn bubbleEvent(self: *Self, e: *Event) void {
    switch (e.evt) {
      .close_popup => |cp| {
        e.handled = true;
        // when a popup is closed, the window that spawned it (which had focus
        // previously) should become focused again
        FocusWindow(self.id, null);
        if (cp.defocus) {
          FocusWidget(null, null);
        }
      },
      else => {},
    }

    // can't bubble past the base window
  }
};

pub fn Popup(src: std.builtin.SourceLocation, id_extra: usize, initialRect: Rect, openflag: ?*bool, menu: ?*MenuWidget, opts: Options) *PopupWidget {
  const cw = current_window orelse unreachable;
  var ret = cw.arena.create(PopupWidget) catch unreachable;
  ret.* = PopupWidget{};
  ret.install(src, id_extra, initialRect, openflag, menu, opts);
  return ret;
}

pub const PopupWidget = struct {
  const Self = @This();
  var Defaults: Options = .{
    .corner_radius = Rect.all(5),
    .border = Rect.all(1),
    .padding = Rect.all(4),
    .background = true,
    .color_style = .window
  };

  id: u32 = undefined,
  parent: Widget = undefined,
  prev_windowId: u32 = 0,
  rect: Rect = Rect{},
  minSize: Size = Size{},
  layout: MenuWidget = undefined,
  openflag: ?*bool = null,
  menu: ?*MenuWidget = null,
  deferred_render_queue: DeferredRenderQueue = undefined,

  pub fn install(self: *Self, src: std.builtin.SourceLocation, id_extra: usize, initialRect: Rect, openflag: ?*bool, menu: ?*MenuWidget, opts: Options) void {
    const options = OptionsGet(opts).overrideIfNull(Defaults);
    DeferRender();
    self.parent = ParentSet(self.widget());
    self.id = self.parent.extendID(src, id_extra);
    self.prev_windowId = WindowCurrentSet(self.id);
    self.openflag = openflag;
    self.menu = menu;

    if (DataGet(self.id, Rect)) |p| {
      self.rect = p;
      if (self.rect.empty()) {
        const ms = MinSize(self.id, options);
        self.rect.w = ms.w;
        self.rect.h = ms.h;
        self.rect = PlaceOnScreen(initialRect, self.rect);
      }
    }
    else {
      self.rect = PlaceOnScreen(initialRect, Rect.fromPoint(initialRect.topleft()));
      FocusWindow(self.id, null);
    }

    debug("{x} Popup {}", .{self.id, self.rect});

    // outside normal flow, so don't get rect from parent
    const rs = self.screenRectScale(self.rect);
    FloatingWindowAdd(self.id, self.prev_windowId, rs.r, false);

    // we are using MenuWidget to do border/background but floating windows
    // don't have margin, so turn that off
    self.layout = MenuWidget{};
    self.layout.init(@src(), 0, .vertical, options.override(.{.margin = .{}}));
    self.layout.install();
  }

  pub fn close(self: *Self) void {
    FloatingWindowClosing(self.id);
    if (self.openflag) |of| {
      of.* = false;
    }
  }

  fn widget(self: *Self) Widget {
    return Widget.init(self, ID, rectFor, minSizeForChild, screenRectScale, bubbleEvent);
  }

  fn ID(self: *const Self) u32 {
    return self.id;
  }

  pub fn rectFor(self: *Self, id: u32, opts: Options) Rect {
    return PlaceIn(id, self.rect, opts);
  }

  pub fn minSizeForChild(self: *Self, s: Size) void {
    self.minSize = Size.max(self.minSize, s);
  }

  pub fn screenRectScale(self: *Self, r: Rect) RectScale {
    _ = self;
    const s = WindowNaturalScale();
    const scaled = r.scale(s);
    return RectScale{.r = scaled.offset(WindowRectPixels()), .s = s};
  }

  pub fn bubbleEvent(self: *Self, e: *Event) void {
    switch (e.evt) {
      .close_popup => {
        // close and continue bubbling
        self.close();
      },
      else => {},
    }

    if (!e.handled) {
      self.parent.bubbleEvent(e);
    }
  }

  pub fn deinit(self: *Self) void {
    // outside normal flow, so don't get rect from parent
    const rs = self.screenRectScale(self.rect);
    var iter = EventIterator.init(self.id, rs.r);
    while (iter.nextCleanup(true)) |e| {
      // mark all events as handled so no mouse events are handled by windows
      // under us
      e.handled = true;
      if (e.evt == .mouse) {
        if (e.evt.mouse.state == .leftdown or e.evt.mouse.state == .rightdown) {
          // unhandled click, clear focus
          FocusWidget(null, null);
        }
      }
      else if (e.evt == .key) {
        if (e.evt.key.state == .down and e.evt.key.keysym == c.SDLK_ESCAPE) {
          var closeE = Event{.evt = AnyEvent{.close_popup = ClosePopupEvent{.defocus = false}}};
          self.bubbleEvent(&closeE);
        }
      }
    }

    if (FloatingWindowNoChildren() and !PopupAncestorFocused(self.id)) {
      // this popup is the last popup in the chain and none of them are focused
      self.close();
    }

    self.layout.deinit();
    DataSet(self.id, self.rect);
    MinSizeSet(self.id, self.minSize);
    // we are outside of normal layout, so don't call minSizeForChild
    _ = ParentSet(self.parent);
    _ = WindowCurrentSet(self.prev_windowId);
    DeferRenderPop();
  }
};

pub fn FloatingWindow(src: std.builtin.SourceLocation, id_extra: usize, modal: bool, initialRect: Rect, openflag: ?*bool, opts: Options) *FloatingWindowWidget {
  const cw = current_window orelse unreachable;
  var ret = cw.arena.create(FloatingWindowWidget) catch unreachable;
  ret.* = FloatingWindowWidget{};
  ret.install(src, id_extra, modal, initialRect, openflag, opts);
  return ret;
}

pub const FloatingWindowWidget = struct {
  const Self = @This();
  var Defaults: Options = .{
    .corner_radius = Rect.all(5),
    .border = Rect.all(1),
    .background = true,
    .color_style = .window
  };

  id: u32 = undefined,
  parent: Widget = undefined,
  modal: bool = false,
  prev_windowId: u32 = 0,
  rect: Rect = Rect{},
  minSize: Size = Size{},
  layout: BoxWidget = undefined,
  openflag: ?*bool = null,
  deferred_render_queue: DeferredRenderQueue = undefined,

  pub fn install(self: *Self, src: std.builtin.SourceLocation, id_extra: usize, modal: bool, initialRect: Rect, openflag: ?*bool, opts: Options) void {
    const options = OptionsGet(opts).overrideIfNull(Defaults);

    DeferRender();
    self.parent = ParentSet(self.widget());
    self.id = self.parent.extendID(src, id_extra);
    self.modal = modal;
    self.prev_windowId = WindowCurrentSet(self.id);
    self.openflag = openflag;

    if (DataGet(self.id, Rect)) |p| {
      self.rect = p;
      const ms = MinSize(self.id, options);
      if (self.rect.w == 0) {
        self.rect.w = ms.w;
        self.rect.x = WindowRect().w / 2 - ms.w / 2;
      }
      if (self.rect.h == 0) {
        self.rect.h = ms.h;
        self.rect.y = WindowRect().h / 2 - ms.h / 2;
      }
    }
    else {
      self.rect = initialRect;
      FocusWindow(self.id, null);
    }

    debug("{x} FloatingWindow {}", .{self.id, self.rect});

    const captured = CaptureMouseMaintain(self.id);

    // processEventsBefore can change self.rect
    self.processEventsBefore(captured);

    // outside normal flow, so don't get rect from parent
    const rs = self.screenRectScale(self.rect);
    FloatingWindowAdd(self.id, null, rs.r, self.modal);

    if (self.modal) {
      // paint over everything below
      PathAddRect(WindowRectPixels(), Rect.all(0));
      var col = options.color();
      col.a = 100;
      PathFillConvex(col);
    }

    // we are using BoxWidget to do border/background but floating windows
    // don't have margin, so turn that off
    self.layout = BoxWidget{};
    self.layout.init(@src(), 0, .vertical, options.override(.{.margin = .{}, .expand = .both}));
    self.layout.install();
  }

  pub fn processEventsBefore(self: *Self, captured: bool) void {
    // outside normal flow, so don't get rect from parent
    const rs = self.screenRectScale(self.rect);
    var iter = EventIterator.init(self.id, rs.r);
    while (iter.next()) |e| {
      if (e.evt == .mouse) {
        var corner: bool = false;
        if (e.evt.mouse.p.x > rs.r.x + rs.r.w - 15 * rs.s and
            e.evt.mouse.p.y > rs.r.y + rs.r.h - 15 * rs.s) {
          // we are over the bottom-left resize corner
          corner = true;
        }

        if (captured or corner) {
          if (e.evt.mouse.state == .leftdown) {
            // capture and start drag
            CaptureMouse(self.id);
            DragStart(e.evt.mouse.p, .arrow_nw_se);
            e.handled = true;
          }
          else if (e.evt.mouse.state == .leftup) {
            // stop drag and capture
            CaptureMouse(null);
            DragEnd();
            e.handled = true;
          }
          else if (e.evt.mouse.state == .motion) {
            // move if dragging
            if (Dragging(e.evt.mouse.p)) |dps| {
              if (CursorGetDragging() == CursorKind.crosshair) {
                const dp = dps.scale(1 / rs.s);
                self.rect.x += dp.x;
                self.rect.y += dp.y;
              }
              else if (CursorGetDragging() == CursorKind.arrow_nw_se) {
                const p = e.evt.mouse.p.scale(1 / rs.s);
                self.rect.w = math.max(40, p.x - self.rect.x);
                self.rect.h = math.max(10, p.y - self.rect.y);
              }
              // don't need CueFrame() because we're before drawing
              e.handled = true;
            }
            else if (corner) {
              CursorSet(e.evt.mouse.p, .arrow_nw_se);
              e.handled = true;
            }
          }
        }
      }
    }
  }

  pub fn processEventsAfter(self: *Self) void {
    // outside normal flow, so don't get rect from parent
    const rs = self.screenRectScale(self.rect);
    var iter = EventIterator.init(self.id, rs.r);
    // duplicate processEventsBefore (minus corner stuff) because you could
    // have a click down, motion, and up in same frame and you wouldn't know
    // you needed to do anything until you got capture here
    while (iter.nextCleanup(true)) |e| {
      // mark all events as handled so no mouse events are handled by windows
      // under us
      e.handled = true;
      if (e.evt == .mouse) {
        if (e.evt.mouse.state == .rightdown) {
          FocusWidget(null, null);
        }
        else if (e.evt.mouse.state == .leftdown) {
          FocusWidget(null, null);

          // capture and start drag
          CaptureMouse(self.id);
          DragPreStart(e.evt.mouse.p, .crosshair);
        }
        else if (e.evt.mouse.state == .leftup) {
          // stop drag and capture
          CaptureMouse(null);
          DragEnd();
        }
        else if (e.evt.mouse.state == .motion) {
          // move if dragging
          if (Dragging(e.evt.mouse.p)) |dps| {
            if (CursorGetDragging() == CursorKind.crosshair) {
              const dp = dps.scale(1 / rs.s);
              self.rect.x += dp.x;
              self.rect.y += dp.y;
            }
            else if (CursorGetDragging() == CursorKind.arrow_nw_se) {
              const p = e.evt.mouse.p.scale(1 / rs.s);
              self.rect.w = math.max(40, p.x - self.rect.x);
              self.rect.h = math.max(10, p.y - self.rect.y);
            }
            CueFrame();
          }
        }
      }
      else if (e.evt == .key) {
        // catch any tabs that weren't handled by widgets (we passed true to iter.next)
        if (e.evt.key.state == .down and e.evt.key.keysym == c.SDLK_TAB) {
          if ((e.evt.key.mod & c.KMOD_SHIFT) > 0) {
            TabIndexPrev(&iter);
          }
          else {
            TabIndexNext(&iter);
          }
        }
      }
    }
  }

  pub fn close(self: *Self) void {
    FloatingWindowClosing(self.id);
    if (self.openflag) |of| {
      of.* = false;
    }
  }

  fn widget(self: *Self) Widget {
    return Widget.init(self, ID, rectFor, minSizeForChild, screenRectScale, bubbleEvent);
  }

  fn ID(self: *const Self) u32 {
    return self.id;
  }

  pub fn rectFor(self: *Self, id: u32, opts: Options) Rect {
    return PlaceIn(id, self.rect, opts);
  }

  pub fn minSizeForChild(self: *Self, s: Size) void {
    self.minSize = Size.max(self.minSize, s);
  }

  pub fn screenRectScale(self: *Self, r: Rect) RectScale {
    _ = self;
    const s = WindowNaturalScale();
    const scaled = r.scale(s);
    return RectScale{.r = scaled.offset(WindowRectPixels()), .s = s};
  }

  pub fn bubbleEvent(self: *Self, e: *Event) void {
    switch (e.evt) {
      .close_popup => |cp| {
        e.handled = true;
        // when a popup is closed, the window that spawned it (which had focus
        // previously) should become focused again
        FocusWindow(self.id, null);
        if (cp.defocus) {
          FocusWidget(null, null);
        }
      },
      else => {},
    }

    // floating windows don't bubble any events
  }

  pub fn deinit(self: *Self) void {
    self.processEventsAfter();
    self.layout.deinit();
    DataSet(self.id, self.rect);
    MinSizeSet(self.id, self.minSize);
    // we are outside of normal layout, so don't call minSizeForChild
    _ = ParentSet(self.parent);
    _ = WindowCurrentSet(self.prev_windowId);
    DeferRenderPop();
  }
};

pub fn Paned(src: std.builtin.SourceLocation, id_extra: usize, dir: gui.Direction, collapse_size: f32, opts: Options) *PanedWidget {
  var ret = gui.CurrentWindow().arena.create(PanedWidget) catch unreachable;
  ret.* = PanedWidget{};
  ret.init(src, id_extra, dir, collapse_size, opts);
  ret.install();
  return ret;
}

pub const PanedWidget = struct {
  const Self = @This();

  const Data = struct {
    split_ratio: f32,
    rect: Rect,
  };

  wd: WidgetData = undefined,

  split_ratio: f32 = undefined,
  dir: gui.Direction = undefined,
  collapse_size: f32 = 0,
  data: Data = undefined,
  first_side_id: ?u32 = null,

  pub fn init(self: *Self, src: std.builtin.SourceLocation, id_extra: usize, dir: gui.Direction, collapse_size: f32, opts: Options) void {
    const options = OptionsGet(opts);
    self.wd = WidgetData.init(src, id_extra, options);
    self.dir = dir;
    self.collapse_size = collapse_size;
  }

  pub fn install(self: *Self) void {
    _ = ParentSet(self.widget());
    gui.debug("{x} Paned {}", .{self.wd.id, self.wd.rect});
    self.wd.borderAndBackground();
    const rect = self.wd.contentRect();

    if (gui.DataGet(self.wd.id, Data)) |d| {
      self.split_ratio = d.split_ratio;
      switch (self.dir) {
        .horizontal => {
          if (d.rect.w >= self.collapse_size and rect.w < self.collapse_size) {
            // collapsing
            self.animate(1.0);
          }
          else if (d.rect.w < self.collapse_size and rect.w >= self.collapse_size) {
            // expanding
            self.animate(0.5);
          }
        },
        .vertical => {
          if (d.rect.w >= self.collapse_size and rect.w < self.collapse_size) {
            // collapsing
            self.animate(1.0);
          }
          else if (d.rect.w < self.collapse_size and rect.w >= self.collapse_size) {
            // expanding
            self.animate(0.5);
          }
        },
      }
    }
    else {
      // first frame
      switch (self.dir) {
        .horizontal => {
          if (rect.w < self.collapse_size) {
            self.split_ratio = 1.0;
          }
          else {
            self.split_ratio = 0.5;
          }
        },
        .vertical => {
          if (rect.w < self.collapse_size) {
            self.split_ratio = 1.0;
          }
          else if (rect.w >= self.collapse_size) {
            self.split_ratio = 0.5;
          }
        },
      }
    }

    if (gui.AnimationGet(self.wd.id, .split_ratio)) |a| {
      self.split_ratio = a.lerp();
    }

    if (!self.collapsed()) {
      self.processEvents();
    }
  }

  pub fn collapsed(self: *Self) bool {
    const rect = self.wd.contentRect();
    switch (self.dir) {
      .horizontal => return (rect.w < self.collapse_size),
      .vertical => return (rect.h < self.collapse_size),
    }
  }

  pub fn showOther(self: *Self) void {
    if (self.split_ratio == 0.0) {
      self.animate(1.0);
    }
    else if (self.split_ratio == 1.0) {
      self.animate(0.0);
    }
  }

  fn animate(self: *Self, end_val: f32) void {
    gui.Animate(self.wd.id, .split_ratio, gui.Animation{.start_val = self.split_ratio, .end_val = end_val, .end_time = 250_000});
  }

  pub fn processEvents(self: *Self) void {
    const rs = self.wd.contentRectScale();
    var iter = EventIterator.init(self.wd.id, rs.r);
    const captured = CaptureMouseMaintain(self.wd.id);
    while (iter.next()) |e| {
      if (e.evt == .mouse) {
        var target: f32 = undefined;
        var mouse: f32 = undefined;
        var cursor: CursorKind = undefined;
        switch (self.dir) {
          .horizontal => {
            target = rs.r.x + rs.r.w * self.split_ratio;
            mouse = e.evt.mouse.p.x;
            cursor = .arrow_w_e;
          },
          .vertical => {
            target = rs.r.y + rs.r.h * self.split_ratio;
            mouse = e.evt.mouse.p.y;
            cursor = .arrow_n_s;
          },
        }

        if (captured or @fabs(mouse - target) < (5 * WindowNaturalScale())) {
          e.handled = true;
          if (e.evt.mouse.state == .leftdown) {
            // capture and start drag
            CaptureMouse(self.wd.id);
            DragPreStart(e.evt.mouse.p, cursor);
          }
          else if (e.evt.mouse.state == .leftup) {
            // stop possible drag and capture
            CaptureMouse(null);
            DragEnd();
          }
          else if (e.evt.mouse.state == .motion) {
            // move if dragging
            if (Dragging(e.evt.mouse.p)) |dps| {
              _ = dps;
              switch (self.dir) {
                .horizontal => {
                  self.split_ratio = (e.evt.mouse.p.x - rs.r.x) / rs.r.w;
                },
                .vertical => {
                  self.split_ratio = (e.evt.mouse.p.y - rs.r.y) / rs.r.h;
                },
              }
            }
            else {
              CursorSet(e.evt.mouse.p, cursor);
            }
          }
        }
      }
    }
  }

  fn widget(self: *Self) gui.Widget {
    return gui.Widget.init(self, ID, rectFor, minSizeForChild, screenRectScale, bubbleEvent);
  }

  fn ID(self: *const Self) u32 {
    return self.wd.id;
  }

  pub fn rectFor(self: *Self, id: u32, opts: Options) gui.Rect {
    if (self.first_side_id == null or self.first_side_id.? == id) {
      self.first_side_id = id;
      var r = self.wd.contentRect();
      if (self.collapsed()) {
        if (self.split_ratio == 0.0) {
          r.w = 0;
          r.h = 0;
        }
        else {
          switch (self.dir) {
            .horizontal => r.x -= (r.w - (r.w * self.split_ratio)),
            .vertical => r.y -= (r.h - (r.h * self.split_ratio)),
          }
        }
      }
      else {
        switch (self.dir) {
          .horizontal => r.w *= self.split_ratio,
          .vertical => r.h *= self.split_ratio,
        }
      }
      return gui.PlaceIn(id, r, opts);
    }
    else {
      var r = self.wd.contentRect();
      if (self.collapsed()) {
        if (self.split_ratio == 1.0) {
          r.w = 0;
          r.h = 0;
        }
        else {
          switch (self.dir) {
            .horizontal => {
              r.x = r.w * self.split_ratio;
            },
            .vertical => {
              r.y = r.h * self.split_ratio;
            },
          }
        }
      }
      else {
        switch (self.dir) {
          .horizontal => {
            const first = r.w * self.split_ratio;
            r.w -= first;
            r.x += first;
          },
          .vertical => {
            const first = r.h * self.split_ratio;
            r.h -= first;
            r.y += first;
          },
        }
      }
      return gui.PlaceIn(id, r, opts);
    }
  }

  pub fn minSizeForChild(self: *Self, s: gui.Size) void {
    self.wd.minSizeMax(self.wd.padSize(s));
  }

  pub fn screenRectScale(self: *Self, r: gui.Rect) gui.RectScale {
    return self.wd.parent.screenRectScale(r);
  }

  pub fn bubbleEvent(self: *Self, e: *gui.Event) void {
    self.wd.parent.bubbleEvent(e);
  }

  pub fn deinit(self: *Self) void {
    gui.DataSet(self.wd.id, Data{.split_ratio = self.split_ratio, .rect = self.wd.contentRect()});
    self.wd.reportMinSize();
    _ = gui.ParentSet(self.wd.parent);
  }
};

pub fn TextLayout(src: std.builtin.SourceLocation, id_extra: usize, opts: Options) *TextLayoutWidget {
  const cw = current_window orelse unreachable;
  var ret = cw.arena.create(TextLayoutWidget) catch unreachable;
  ret.* = TextLayoutWidget{};
  ret.init(src, id_extra, opts);
  ret.install();
  return ret;
}

pub const TextLayoutWidget = struct {
  const Self = @This();
  var Defaults: Options = .{
    .margin = Rect.all(4),
    .padding = Rect.all(4),
    .background = true,
    .color_style = .content,
  };

  wd: WidgetData = undefined,
  corners: [4]?Rect = [_]?Rect{null} ** 4,
  cursor: Point = Point{},
  prevClip: Rect = Rect{},

  pub fn init(self: *Self, src: std.builtin.SourceLocation, id_extra: usize, opts: Options) void {
    const options = OptionsGet(opts).overrideIfNull(Defaults);
    self.wd = WidgetData.init(src, id_extra, options);
  }

  pub fn install(self: *Self) void {
    _ = ParentSet(self.widget());
    debug("{x} TextLayout {}", .{self.wd.id, self.wd.rect});
    self.wd.borderAndBackground();

    const rs = self.wd.contentRectScale();
    self.prevClip = Clip(rs.r);
    self.cursor = self.wd.contentRect().topleft();
  }

  pub fn addText(self: *Self, text: []const u8, opts: Options) void {
    const options = self.wd.options.override(opts);
    var iter = std.mem.split(u8, text, "\n");
    var first: bool = true;
    const startx = self.wd.contentRect().x;
    const lineskip = options.font().lineSkip();
    while (iter.next()) |line| {
      if (first) {
        first = false;
      }
      else {
        self.cursor.y += lineskip;
        self.cursor.x = startx;
      }
      self.addTextNoNewlines(line, options);
    }
  }

  pub fn addTextNoNewlines(self: *Self, text: []const u8, opts: Options) void {
    const options = self.wd.options.override(opts);
    const msize = options.font().textSize("m");
    const lineskip = options.font().lineSkip();
    var txt = text;

    while (txt.len > 0) {
      const rect = self.wd.contentRect();
      var linestart = rect.x;
      var linewidth = rect.w;
      var width = rect.w - self.cursor.x;
      for (self.corners) |corner| {
        if (corner) |cor| {
          if (math.max(cor.y, self.cursor.y) < math.min(cor.y + cor.h, self.cursor.y + lineskip)) {
            linewidth -= cor.w;
            if (linestart == cor.x) {
              linestart = (cor.x + cor.w);
            }

            if (self.cursor.x <= (cor.x + cor.w)) {
              width -= cor.w;
              if (self.cursor.x >= cor.x) {
                self.cursor.x = (cor.x + cor.w);
              }
            }
          }
        }
      }

      const lineguess = @floatToInt(usize, @ceil(math.max(0, width) / msize.w));
      var end: usize = math.max(1, math.min(lineguess, txt.len));

      // make sure we've got as many characters as we can
      var s = options.font().textSize(txt[0..end]);
      //std.debug.print("1 txt to {d} \"{s}\"\n", .{end, txt[0..end]});
      while (s.w < width and end < txt.len) {
        end += 1;
        s = options.font().textSize(txt[0..end]);
        //std.debug.print("2 txt to {d} \"{s}\"\n", .{end, txt[0..end]});
      }

      // make sure we're not too long
      while (s.w > width and end > 1) {
        end -= 1;
        s = options.font().textSize(txt[0..end]);
        //std.debug.print("3 txt to {d} \"{s}\"\n", .{end, txt[0..end]});
      }

      // if we are boxed in too much by corner widgets drop to next line
      if (s.w > width and linewidth < rect.w) {
        self.cursor.y += lineskip;
        self.cursor.x = rect.x;
        continue;
      }

      if (end < txt.len and linewidth > (10 * msize.w)) {
        const space: []const u8 = &[_]u8{' '};
        // now we are under the length limit but might be in the middle of a word
        const spaceIdx = std.mem.lastIndexOfLinear(u8, txt[0..end], space);
        if (spaceIdx) |si| {
          end = si + 1;
          s = options.font().textSize(txt[0..end]);
          //std.debug.print("4 txt to {d} \"{s}\"\n", .{end, txt[0..end]});
        }
        else if (self.cursor.x > linestart) {
          // can't fit breaking on space, but we aren't starting at the left edge
          // so drop to next line
          self.cursor.y += lineskip;
          self.cursor.x = rect.x;
          continue;
        }
      }

      // We want to render text, but no sense in doing it if we are off the end
      if (self.cursor.y < rect.y + rect.h) {
        const rs = self.screenRectScale(Rect{.x = self.cursor.x, .y = self.cursor.y, .w = width, .h = math.max(0, rect.h - self.cursor.y)});
        renderText(options.font(), txt[0..end], rs, options.color());
      }

      // even if we don't actually render, need to update cursor and minSize
      // like we did because our parent might size based on that (might be in a
      // scroll area)
      self.cursor.x += s.w;
      const size = Size{.w = 0, .h = self.cursor.y - rect.y + s.h};
      self.wd.min_size.h = math.max(self.wd.min_size.h, self.wd.padSize(size).h);
      txt = txt[end..];

      // move cursor to next line if we have more text
      if (txt.len > 0) {
        self.cursor.y += lineskip;
        self.cursor.x = rect.x;
      }
    }
  }

  fn widget(self: *Self) Widget {
    return Widget.init(self, ID, rectFor, minSizeForChild, screenRectScale, bubbleEvent);
  }

  fn ID(self: *const Self) u32 {
    return self.wd.id;
  }

  pub fn rectFor(self: *Self, id: u32, opts: Options) Rect {
    const ret = PlaceIn(id, self.wd.contentRect(), opts);
    const i: usize = switch (opts.gravity orelse .upleft) {
      .upleft => 0,
      .upright => 1,
      .downleft => 2,
      .downright => 3,
      else => unreachable,
    };
    self.corners[i] = ret;
    return ret;
  }

  pub fn minSizeForChild(self: *Self, s: Size) void {
    const padded = self.wd.padSize(s);
    self.wd.min_size.w = math.max(self.wd.min_size.w, padded.w);
    self.wd.min_size.h += padded.h;
  }

  pub fn screenRectScale(self: *Self, r: Rect) RectScale {
    return self.wd.parent.screenRectScale(r);
  }

  pub fn bubbleEvent(self: *Self, e: *Event) void {
    self.wd.parent.bubbleEvent(e);
  }

  pub fn deinit(self: *Self) void {
    ClipSet(self.prevClip);
    self.wd.reportMinSize();
    _ = ParentSet(self.wd.parent);
  }
};

pub fn Context(src: std.builtin.SourceLocation, id_extra: usize, opts: Options) *ContextWidget {
  const cw = current_window orelse unreachable;
  var ret = cw.arena.create(ContextWidget) catch unreachable;
  ret.* = ContextWidget{};
  ret.init(src, id_extra, opts);
  ret.install();
  return ret;
}

pub const ContextWidget = struct {
  const Self = @This();
  wd: WidgetData = undefined,

  winId: u32 = undefined,
  active: bool = false,
  activePt: Point = Point{},

  pub fn init(self: *Self, src: std.builtin.SourceLocation, id_extra: usize, opts: Options) void {
    const options = OptionsGet(opts);
    self.wd = WidgetData.init(src, id_extra, options);
    self.winId = WindowCurrentId();
    if (DataGet(self.wd.id, Point)) |a| {
      self.active = true;
      self.activePt = a;
    }
  }

  pub fn install(self: *Self) void {
    _ = ParentSet(self.widget());
    debug("{x} Context {}", .{self.wd.id, self.wd.rect});
    self.wd.borderAndBackground();
  }

  pub fn activePoint(self: *Self) ?Point {
    if (self.active) {
      return self.activePt;
    }
    else {
      return null;
    }
  }

  fn widget(self: *Self) Widget {
    return Widget.init(self, ID, rectFor, minSizeForChild, screenRectScale, bubbleEvent);
  }

  fn ID(self: *const Self) u32 {
    return self.wd.id;
  }

  pub fn rectFor(self: *Self, id: u32, opts: Options) Rect {
    return PlaceIn(id, self.wd.contentRect(), opts);
  }

  pub fn minSizeForChild(self: *Self, s: Size) void {
    self.wd.minSizeMax(self.wd.padSize(s));
  }

  pub fn screenRectScale(self: *Self, rect: Rect) RectScale {
    return self.wd.parent.screenRectScale(rect);
  }

  pub fn bubbleEvent(self: *Self, e: *Event) void {
    self.wd.parent.bubbleEvent(e);
  }

  pub fn processMouseEventsAfter(self: *Self) void {
    const rs = self.wd.borderRectScale();
    var iter = EventIterator.init(self.wd.id, rs.r);
    while (iter.next()) |e| {
      switch (e.evt) {
        .mouse => {
          if (e.evt.mouse.state == .rightdown) {
            e.handled = true;
            self.active = true;

            // scale the point back to natural so we can use it in Popup
            self.activePt = e.evt.mouse.p.scale(1 / WindowNaturalScale());

            // offset just enough so when Popup first appears nothing is highlighted
            self.activePt.x += 1;
          }
        },
        else => {},
      }
    }
  }

  pub fn deinit(self: *Self) void {
    self.processMouseEventsAfter();
    if (self.active) {
      DataSet(self.wd.id, self.activePt);
    }
    self.wd.reportMinSize();
    _ = ParentSet(self.wd.parent);
  }
};

pub fn Overlay(src: std.builtin.SourceLocation, id_extra: usize, opts: Options) *OverlayWidget {
  const cw = current_window orelse unreachable;
  var ret = cw.arena.create(OverlayWidget) catch unreachable;
  ret.* = OverlayWidget{};
  ret.init(src, id_extra, opts);
  ret.install();
  return ret;
}

pub const OverlayWidget = struct {
  const Self = @This();
  wd: WidgetData = undefined,

  pub fn init(self: *Self, src: std.builtin.SourceLocation, id_extra: usize, opts: Options) void {
    const options = OptionsGet(opts);
    self.wd = WidgetData.init(src, id_extra, options);
  }

  pub fn install(self: *Self) void {
    _ = ParentSet(self.widget());
    debug("{x} Overlay {}", .{self.wd.id, self.wd.rect});
    self.wd.borderAndBackground();
  }

  fn widget(self: *Self) Widget {
    return Widget.init(self, ID, rectFor, minSizeForChild, screenRectScale, bubbleEvent);
  }

  fn ID(self: *const Self) u32 {
    return self.wd.id;
  }

  pub fn rectFor(self: *Self, id: u32, opts: Options) Rect {
    return PlaceIn(id, self.wd.contentRect(), opts);
  }

  pub fn minSizeForChild(self: *Self, s: Size) void {
    self.wd.minSizeMax(self.wd.padSize(s));
  }

  pub fn screenRectScale(self: *Self, rect: Rect) RectScale {
    return self.wd.parent.screenRectScale(rect);
  }

  pub fn bubbleEvent(self: *Self, e: *Event) void {
    self.wd.parent.bubbleEvent(e);
  }

  pub fn deinit(self: *Self) void {
    self.wd.reportMinSize();
    _ = ParentSet(self.wd.parent);
  }
};

pub const Direction = enum {
  horizontal,
  vertical,
};

pub fn Box(src: std.builtin.SourceLocation, id_extra: usize, dir: Direction, opts: Options) *BoxWidget {
  const cw = current_window orelse unreachable;
  var ret = cw.arena.create(BoxWidget) catch unreachable;
  ret.* = BoxWidget{};
  ret.init(src, id_extra, dir, opts);
  ret.install();
  return ret;
}

pub const BoxWidget = struct {
  const Self = @This();

  wd: WidgetData = undefined,

  dir: Direction = undefined,
  max_thick: f32 = 0,
  space_taken: f32 = 0,
  total_weight_prev: ?f32 = null,
  total_weight: f32 = 0,
  current_weight: f32 = 0,
  childRect: Rect = Rect{},
  extra_pixels: f32 = 0,

  pub fn init(self: *Self, src: std.builtin.SourceLocation, id_extra: usize, dir: Direction, opts: Options) void {
    const options = OptionsGet(opts);
    self.wd = WidgetData.init(src, id_extra, options);
    self.dir = dir;
    if (DataGet(self.wd.id, f32)) |weight| {
      self.total_weight_prev = weight;
    }
  }

  pub fn install(self: *Self) void {
    _ = ParentSet(self.widget());
    debug("{x} Box {}", .{self.wd.id, self.wd.rect});
    self.wd.borderAndBackground();

    // our rect for children has to start at 0,0
    self.childRect = self.wd.contentRect();
    self.childRect.x = 0;
    self.childRect.y = 0;

    const ms = MinSize(self.wd.id, self.wd.options);
    const newRect = self.wd.rect;
    defer self.wd.rect = newRect;

    self.wd.rect.w = ms.w;
    self.wd.rect.h = ms.h;
    if (self.dir == .horizontal) {
      self.extra_pixels = math.max(0, self.childRect.w - self.wd.contentRect().w);
    }
    else {
      self.extra_pixels = math.max(0, self.childRect.h - self.wd.contentRect().h);
    }
  }

  fn widget(self: *Self) Widget {
    return Widget.init(self, ID, rectFor, minSizeForChild, screenRectScale, bubbleEvent);
  }

  fn ID(self: *const Self) u32 {
    return self.wd.id;
  }

  pub fn rectFor(self: *Self, id: u32, opts: Options) Rect {
    self.current_weight = 0.0;
    if ((self.dir == .horizontal and opts.expandHorizontal())
        or (self.dir == .vertical and opts.expandVertical())) {
      self.current_weight = 1.0;
    }
    self.total_weight += self.current_weight;

    var pixels_per_w: f32 = 0;
    if (self.total_weight_prev) |w| {
      pixels_per_w = self.extra_pixels / w;
    }

    var child_size = MinSize(id, opts);

    var rect = self.childRect;
    rect.w = math.min(rect.w, child_size.w);
    rect.h = math.min(rect.h, child_size.h);

    if (self.dir == .horizontal) {
      rect.h = self.childRect.h;
      if (self.wd.options.expandHorizontal()) {
        rect.w += pixels_per_w * self.current_weight;
      }

      self.childRect.w = math.max(0, self.childRect.w - rect.w);
      self.childRect.x += rect.w;
    }
    else if (self.dir == .vertical) {
      rect.w = self.childRect.w;
      if (self.wd.options.expandVertical()) {
        rect.h += pixels_per_w * self.current_weight;
      }

      self.childRect.h = math.max(0, self.childRect.h - rect.h);
      self.childRect.y += rect.h;
    }

    return PlaceIn(null, rect, opts.override(.{.min_size = child_size}));
  }

  pub fn minSizeForChild(self: *Self, s: Size) void {
    if (self.dir == .horizontal) {
      self.space_taken += s.w;
      self.max_thick = math.max(self.max_thick, s.h);
    }
    else {
      self.space_taken += s.h;
      self.max_thick = math.max(self.max_thick, s.w);
    }
  }

  pub fn screenRectScale(self: *Self, r: Rect) RectScale {
    const screenRS = self.wd.contentRectScale();
    const scaled = r.scale(screenRS.s);
    return RectScale{.r = scaled.offset(screenRS.r), .s = screenRS.s};
  }

  pub fn bubbleEvent(self: *Self, e: *Event) void {
    self.wd.parent.bubbleEvent(e);
  }

  pub fn deinit(self: *Self) void {
    var ms: Size = undefined;
    if (self.dir == .horizontal) {
      ms.w = self.space_taken;
      ms.h = self.max_thick;
    }
    else {
      ms.h = self.space_taken;
      ms.w = self.max_thick;
    }

    self.wd.minSizeMax(self.wd.padSize(ms));
    self.wd.reportMinSize();

    if (self.total_weight > 0) {
      DataSet(self.wd.id, self.total_weight);
    }

    _ = ParentSet(self.wd.parent);
  }
};

pub const ScrollBar = struct {
  const Self = @This();
  const thick = 10;
  const Data = struct {
    graboff: f32,
  };
  id: u32,
  parent: Widget,
  rect: Rect = Rect{},
  grabRect: Rect = Rect{},
  area: *ScrollAreaWidget,
  data: ?Data = null,
  highlight: bool = false,

  pub fn run(src: std.builtin.SourceLocation, id_extra: usize, area: *ScrollAreaWidget, rect_in: Rect, opts: Options) void {
    const options = OptionsGet(opts);
    const parent = ParentGet();
    var self = Self{.id = parent.extendID(src, id_extra), .parent = parent, .area = area};
    self.data = DataGet(self.id, Data);

    const captured = CaptureMouseMaintain(self.id);
    if (!captured) {
      self.data = null;
    }

    self.rect = rect_in;
    debug("{x} ScrollBar {}", .{self.id, self.rect});
    {
      const si = area.scrollInfo();
      self.grabRect = self.rect;
      self.grabRect.h = math.max(20, self.rect.h * si.fraction_visible);
      const insideH = self.rect.h - self.grabRect.h;
      self.grabRect.y += insideH * si.scroll_fraction;

      const grabrs = self.parent.screenRectScale(self.grabRect);
      self.processEvents(grabrs.r);
    }

    // processEvents could have changed scroll so recalc before render
    {
      const si = area.scrollInfo();
      self.grabRect = self.rect;
      self.grabRect.h = math.max(20, self.rect.h * si.fraction_visible);
      const insideH = self.rect.h - self.grabRect.h;
      self.grabRect.y += insideH * si.scroll_fraction;
    }

    //const rs = self.parent.screenRectScale(self.rect);
    //PathAddRect(rs.r, Rect.all(0));
    //var fill_color = Color{.r = 0, .g = 0, .b = 0, .a = 50};
    //PathFillConvex(fill_color);

    //fill_color = Color{.r = 100, .g = 100, .b = 100, .a = 255};
    var fill = options.color().transparent(0.5);
    if (captured or self.highlight) {
      fill = options.color().transparent(0.3);
    }
    self.grabRect = self.grabRect.insetAll(2);
    const grabrs = self.parent.screenRectScale(self.grabRect);
    PathAddRect(grabrs.r, Rect.all(grabrs.r.w));
    PathFillConvex(fill);

    if (self.data) |d| {
      DataSet(self.id, d);
    }
  }

  pub fn processEvents(self: *Self, grabrs: Rect) void {
    const rs = self.parent.screenRectScale(self.rect);
    var iter = EventIterator.init(self.id, rs.r);
    while (iter.next()) |e| {
      if (e.evt == .mouse) {
        if (e.evt.mouse.state == .leftdown) {
          e.handled = true;
          if (grabrs.contains(e.evt.mouse.p)) {
            // capture and start drag
            CaptureMouse(self.id);
            DragPreStart(e.evt.mouse.p, .arrow);
            const off = e.evt.mouse.p.y - (grabrs.y + grabrs.h / 2);
            self.data = Data{.graboff = off};
          }
          else {
            const si = self.area.scrollInfo();
            var fi = si.fraction_visible;
            // the last page is scroll fraction 1.0, so there is
            // one less scroll position between 0 and 1.0
            fi = 1.0 / ((1.0 / fi) - 1);
            var f: f32 = undefined;
            if (e.evt.mouse.p.y < grabrs.y) {
              // clicked above grab
              f = si.scroll_fraction - fi;
            }
            else {
              // clicked below grab
              f = si.scroll_fraction + fi;
            }
            self.area.scrollToFraction(f);
          }
        }
        else if (e.evt.mouse.state == .leftup) {
          e.handled = true;
          // stop possible drag and capture
          CaptureMouse(null);
          DragEnd();
        }
        else if (e.evt.mouse.state == .motion) {
          e.handled = true;
          // move if dragging
          if (Dragging(e.evt.mouse.p)) |dps| {
            _ = dps;
            const min = rs.r.y + grabrs.h / 2;
            const max = rs.r.y + rs.r.h - grabrs.h / 2;
            var grabmid = e.evt.mouse.p.y;
            if (self.data) |d| {
              grabmid -= d.graboff;
            }
            var f: f32 = 0;
            if (max > min) {
              f = (grabmid - min) / (max - min);
            }
            self.area.scrollToFraction(f);
          }
          else if (Highlight(e.evt.mouse.p, rs.r)) {
            self.highlight = true;
          }
        }
      }
    }
  }
};

pub fn ScrollArea(src: std.builtin.SourceLocation, id_extra: usize, opts: Options) *ScrollAreaWidget {
  const cw = current_window orelse unreachable;
  var ret = cw.arena.create(ScrollAreaWidget) catch unreachable;
  ret.* = ScrollAreaWidget{};
  ret.init(src, id_extra, opts);
  ret.install();
  return ret;
}

pub const ScrollAreaWidget = struct {
  const Self = @This();
  var Defaults: Options = .{
    .background = true,
    .corner_radius = Rect.all(5),
    .color_style = .content,
    .min_size = .{.w = 0, .h = 100},
  };

  const grab_thick = 10;
  const ScrollInfo = struct {
    fraction_visible: f32,
    scroll_fraction: f32,
  };

  const Data = struct {
    scroll: f32,
    virtualSize: Size,
  };

  wd: WidgetData = undefined,

  prevClip: Rect = Rect{},
  virtualSize: Size = Size{},
  nextVirtualSize: Size = Size{},
  cursor: f32 = 0,  // goes from 0 to viritualSize.h
  scroll: f32 = 0,  // how far down we are scrolled (natural scale pixels)
  scrollAfter: f32 = 0,  // how far we need to scroll after this frame

  pub fn init(self: *Self, src: std.builtin.SourceLocation, id_extra: usize, opts: Options) void {
    const options = OptionsGet(opts).overrideIfNull(Defaults);
    self.wd = WidgetData.init(src, id_extra, options);
    if (DataGet(self.wd.id, Data)) |d| {
      self.virtualSize = d.virtualSize;
      self.scroll = d.scroll;
    }
    self.cursor = 0;
  }

  pub fn install(self: *Self) void {
    debug("{x} ScrollArea {}", .{self.wd.id, self.wd.rect});
    self.wd.borderAndBackground();

    const max_scroll = math.max(0, self.virtualSize.h - self.wd.contentRect().h);
    if (self.scroll < 0) {
      self.scroll = math.min(0, self.scroll + 250 * AnimationRate());
      if (self.scroll < 0) {
        CueFrame();
      }
    }
    else if (self.scroll > max_scroll) {
      self.scroll = math.max(max_scroll, self.scroll - 250 * AnimationRate());
      if (self.scroll > max_scroll) {
        CueFrame();
      }
    }

    self.prevClip = Clip(self.wd.contentRectScale().r);

    var rect = self.wd.contentRect();
    if (rect.w >= grab_thick) {
      rect.x += rect.w - grab_thick;
      rect.w = grab_thick;
    }
    ScrollBar.run(@src(), 0, self, rect, self.wd.options);

    _ = ParentSet(self.widget());
  }

  pub fn scrollInfo(self: *Self) ScrollInfo {
    const rect = self.wd.contentRect();
    if (rect.h == 0) {
      return ScrollInfo{.fraction_visible = 0, .scroll_fraction = 0};
    }
    const max_hard_scroll = math.max(0, self.virtualSize.h - rect.h);
    var length = math.max(rect.h, self.virtualSize.h);
    if (self.scroll < 0) {
      // temporarily adding the dead space we are showing
      length -= self.scroll;
    }
    else if (self.scroll > max_hard_scroll) {
      length += (self.scroll - max_hard_scroll);
    }
    const fraction_visible = rect.h / length;  // <= 1

    const max_scroll = math.max(0, length - rect.h);
    var scroll_fraction: f32 = 0;
    if (max_scroll != 0) {
      scroll_fraction = math.max(0, self.scroll / max_scroll);
    }
    
    return ScrollInfo{.fraction_visible = fraction_visible, .scroll_fraction = scroll_fraction};
  }

  pub fn scrollToFraction(self: *Self, fin: f32) void {
    const f = math.max(0, math.min(1, fin));
    const max_hard_scroll = math.max(0, self.virtualSize.h - self.wd.contentRect().h);
    self.scroll = f * max_hard_scroll;
  }

  fn widget(self: *Self) Widget {
    return Widget.init(self, ID, rectFor, minSizeForChild, screenRectScale, bubbleEvent);
  }

  fn ID(self: *const Self) u32 {
    return self.wd.id;
  }

  pub fn rectFor(self: *Self, id: u32, opts: Options) Rect {
    var child_size = MinSize(id, opts);

    const y = self.cursor;
    const h = self.virtualSize.h - self.cursor;
    const rect = Rect{.x = 0, .y = y, .w = math.max(0, self.wd.contentRect().w - grab_thick), .h = math.min(h, child_size.h)};
    const ret = PlaceIn(id, rect, opts);
    self.cursor = (ret.y + ret.h);
    return ret;
  }

  pub fn minSizeForChild(self: *Self, s: Size) void {
    self.nextVirtualSize.h += s.h;
    const padded = self.wd.padSize(s);
    self.wd.min_size.w = math.max(self.wd.min_size.w, padded.w + grab_thick);
  }

  pub fn screenRectScale(self: *Self, rect: Rect) RectScale {
    var r = rect;
    r.x += self.wd.contentRect().x;
    r.y += self.wd.contentRect().y - self.scroll;
    return self.wd.parent.screenRectScale(r);
  }

  pub fn bubbleEvent(self: *Self, e: *Event) void {
    switch (e.evt) {
      .key => {
        if (e.evt.key.keysym == c.SDLK_UP and
            (e.evt.key.state == .down or e.evt.key.state == .repeat)) {
          e.handled = true;
          self.scrollAfter -= 10;
          if (self.scroll + self.scrollAfter < 0) {
            self.scrollAfter = math.min(0, -self.scroll);
          }
        }
        else if (e.evt.key.keysym == c.SDLK_DOWN and
                 (e.evt.key.state == .down or e.evt.key.state == .repeat)) {
          e.handled = true;
          self.scrollAfter += 10;
          const max_scroll = math.max(0, self.virtualSize.h - self.wd.contentRect().h);
          if (self.scroll + self.scrollAfter > max_scroll) {
            self.scrollAfter = math.max(0, max_scroll - self.scroll);
          }
        }
      },
      else => {},
    }

    if (!e.handled) {
      self.wd.parent.bubbleEvent(e);
    }
  }

  pub fn processEventsAfter(self: *Self) void {
    const rs = self.wd.borderRectScale();
    var iter = EventIterator.init(self.wd.id, rs.r);
    while (iter.next()) |e| {
      switch (e.evt) {
        .mouse => {
          if (e.evt.mouse.state == .wheel_y) {
            e.handled = true;
            self.scrollAfter += e.evt.mouse.wheel * 3;
          }
        },
        else => {},
      }
    }
  }

  pub fn deinit(self: *Self) void {
    self.processEventsAfter();

    ClipSet(self.prevClip);

    var scroll = self.scroll;
    if (self.scrollAfter != 0) {
      scroll += self.scrollAfter;
      CueFrame();
    }

    const d = Data{.virtualSize = self.nextVirtualSize, .scroll = scroll};
    DataSet(self.wd.id, d);

    self.wd.reportMinSize();
    _ = ParentSet(self.wd.parent);
  }
};

pub fn Separator(src: std.builtin.SourceLocation, id_extra: usize, opts: Options) void {
  const options = OptionsGet(opts);
  var wd = WidgetData.init(src, id_extra, options);
  debug("{x} Spacer {}", .{wd.id, wd.rect});
  wd.borderAndBackground();
  wd.reportMinSize();
}

pub fn Spacer(src: std.builtin.SourceLocation, id_extra: usize, opts: Options) void {
  _ = SpacerRect(src, id_extra, opts);
}

pub fn SpacerRect(src: std.builtin.SourceLocation, id_extra: usize, opts: Options) Rect {
  const options = OptionsGet(opts);
  var wd = WidgetData.init(src, id_extra, options.plain());
  debug("{x} Spacer {}", .{wd.id, wd.rect});
  wd.reportMinSize();
  return wd.rect;
}

pub fn Spinner(src: std.builtin.SourceLocation, id_extra: usize, size: f32) void {
  const s = Size{.w = size, .h = size};
  const parent = ParentGet();
  const id = parent.extendID(src, id_extra);
  const rect = parent.rectFor(id, .{.min_size = s, .expand = .none});
  debug("{x} Spinner {}", .{id, rect});
  parent.minSizeForChild(s);

  if (rect.empty()) {
    return;
  }

  const rs = parent.screenRectScale(rect);
  const r = rs.r;

  var angle: f32 = 0;
  var anim = Animation{.start_val = 0, .end_val = 2 * math.pi, .start_time = 0, .end_time = 4_500_000};
  if (AnimationGet(id, .angle)) |a| {
    var aa = a;
    if (aa.end_time <= 0) {
      aa = anim;
      aa.start_time = a.end_time;
      aa.end_time += a.end_time;
      Animate(id, .angle, aa);
    }
    angle = aa.lerp();
  }
  else {
    Animate(id, .angle, anim);
  }

  const center = Point{.x = r.x + r.w / 2, .y = r.y + r.h / 2};
  PathAddArc(center, size * rs.s / 3, angle + math.pi, angle, false);
  //PathAddPoint(center);
  const fill_color = Color{.r = 200, .g = 0, .b = 0, .a = 255};
  PathFillConvex(fill_color);
}

pub fn Scale(src: std.builtin.SourceLocation, id_extra: usize, initial_scale: f32, opts: Options) *ScaleWidget {
  const cw = current_window orelse unreachable;
  var ret = cw.arena.create(ScaleWidget) catch unreachable;
  ret.* = ScaleWidget{};
  ret.init(src, id_extra, initial_scale, opts);
  ret.install();
  return ret;
}

pub const ScaleWidget = struct {
  const Self = @This();
  wd: WidgetData = undefined,
  scale: f32 = 1.0,

  pub fn init(self: *Self, src: std.builtin.SourceLocation, id_extra: usize, initial_scale: f32, opts: Options) void {
    const options = OptionsGet(opts);
    self.wd = WidgetData.init(src, id_extra, options);
    self.scale = initial_scale;
    if (DataGet(self.wd.id, f32)) |s| {
      self.scale = s;
    }
  }

  pub fn install(self: *Self) void {
    _ = ParentSet(self.widget());
    debug("{x} Scale {d} {}", .{self.wd.id, self.scale, self.wd.rect});
    self.wd.borderAndBackground();
  }

  fn processEventsAfter(self: *Self) void {
    const rs = self.wd.borderRectScale();
    var iter = EventIterator.init(self.wd.id, rs.r);
    while (iter.next()) |e| {
      switch (e.evt) {
        .mouse => |me| {
          if (me.state == .wheel_y) {
            e.handled = true;
            var base: f32 = 1.05;
            const zs = @exp(@log(base) * e.evt.mouse.wheel);
            if (zs != 1.0) {
              self.scale *= zs;
              CueFrame();
            }
          }
        },
        else => {},
      }
    }
  }

  fn widget(self: *Self) Widget {
    return Widget.init(self, ID, rectFor, minSizeForChild, screenRectScale, bubbleEvent);
  }

  fn ID(self: *const Self) u32 {
    return self.wd.id;
  }

  pub fn rectFor(self: *Self, id: u32, opts: Options) Rect {
    return PlaceIn(id, self.wd.contentRect().justSize().scale(1.0 / self.scale), opts);
  }

  pub fn minSizeForChild(self: *Self, s: Size) void {
    self.wd.minSizeMax(self.wd.padSize(s.scale(self.scale)));
  }

  pub fn screenRectScale(self: *Self, r: Rect) RectScale {
    const screenRS = self.wd.contentRectScale();
    const s = screenRS.s * self.scale;
    const scaled = r.scale(s);
    return RectScale{.r = scaled.offset(screenRS.r), .s = s};
  }

  pub fn bubbleEvent(self: *Self, e: *Event) void {
    self.wd.parent.bubbleEvent(e);
  }

  pub fn deinit(self: *Self) void {
    self.processEventsAfter();
    DataSet(self.wd.id, self.scale);
    self.wd.reportMinSize();
    _ = ParentSet(self.wd.parent);
  }
};

pub fn Menu(src: std.builtin.SourceLocation, id_extra: usize, dir: Direction, opts: Options) *MenuWidget {
  const cw = current_window orelse unreachable;
  var ret = cw.arena.create(MenuWidget) catch unreachable;
  ret.* = MenuWidget{};
  ret.init(src, id_extra, dir, opts);
  ret.install();
  return ret;
}

pub const MenuWidget = struct {
  const Self = @This();

  wd: WidgetData = undefined,

  dir: Direction = undefined,
  parentMenu: ?*MenuWidget = null,
  box: BoxWidget = undefined,
  submenus_activated: bool = false,

  pub fn init(self: *Self, src: std.builtin.SourceLocation, id_extra: usize, dir: Direction, opts: Options) void {
    const options = OptionsGet(opts);
    self.wd = WidgetData.init(src, id_extra, options);

    self.dir = dir;
    if (MenuGet()) |m| {
      self.submenus_activated = m.submenus_activated;
    }
    else if (DataGet(self.wd.id, bool)) |a| {
      self.submenus_activated = a;
    }
  }

  pub fn install(self: *Self) void {
    _ = ParentSet(self.widget());
    self.parentMenu = MenuSet(self);
    debug("{x} Menu {}", .{self.wd.id, self.wd.rect});

    self.wd.borderAndBackground();

    self.box = BoxWidget{};
    self.box.init(@src(), 0, self.dir, self.wd.options.plain());
    self.box.install();
  }

  pub fn close(self: *Self) void {
    // bubble this event to close all popups that had submenus leading to this
    var e = Event{.evt = AnyEvent{.close_popup = ClosePopupEvent{}}};
    self.bubbleEvent(&e);
  }

  fn widget(self: *Self) Widget {
    return Widget.init(self, ID, rectFor, minSizeForChild, screenRectScale, bubbleEvent);
  }

  fn ID(self: *const Self) u32 {
    return self.wd.id;
  }

  pub fn rectFor(self: *Self, id: u32, opts: Options) Rect {
    return PlaceIn(id, self.wd.contentRect(), opts);
  }

  pub fn minSizeForChild(self: *Self, s: Size) void {
    self.wd.minSizeMax(self.wd.padSize(s));
  }

  pub fn screenRectScale(self: *Self, rect: Rect) RectScale {
    return self.wd.parent.screenRectScale(rect);
  }

  pub fn bubbleEvent(self: *Self, e: *Event) void {
    self.wd.parent.bubbleEvent(e);
  }

  pub fn deinit(self: *Self) void {
    self.box.deinit();
    DataSet(self.wd.id, self.submenus_activated);
    self.wd.reportMinSize();
    _ = MenuSet(self.parentMenu);
    _ = ParentSet(self.wd.parent);
  }
};

pub fn MenuItemLabel(src: std.builtin.SourceLocation, id_extra: usize, label: []const u8, submenu: bool, opts: Options) ?Rect {
  const options = OptionsGet(opts);
  var mi = MenuItem(src, id_extra, submenu, options);

  var labelopts = options.plain();
  if (mi.active()) {
    labelopts = labelopts.override(.{.color_style = .accent});
  }
  LabelNoFormat(@src(), 0, label, labelopts);

  var ret: ?Rect = null;
  if (mi.activeRect()) |r| {
    ret = r;
  }

  mi.deinit();

  return ret;
}

pub fn MenuItem(src: std.builtin.SourceLocation, id_extra: usize, submenu: bool, opts: Options) *MenuItemWidget {
  const cw = current_window orelse unreachable;
  var ret = cw.arena.create(MenuItemWidget) catch unreachable;
  ret.* = MenuItemWidget{};
  ret.init(src, id_extra, submenu, opts);
  ret.install();
  return ret;
}

pub const MenuItemWidget = struct {
  const Self = @This();
  var Defaults: Options = .{
    .corner_radius = Rect.all(5),
    .padding = Rect.all(4),
  };

  wd: WidgetData = undefined,
  focused: bool = false,
  highlight: bool = false,
  submenu: bool = false,
  activated: bool = false,

  pub fn init(self: *Self, src: std.builtin.SourceLocation, id_extra: usize, submenu: bool, opts: Options) void {
    const options = OptionsGet(opts).overrideIfNull(Defaults);
    self.wd = WidgetData.init(src, id_extra, options);
    self.submenu = submenu;
    if (!self.wd.rect.empty()) {
      TabIndexSet(self.wd.id, options.tab_index);
    }
  }

  pub fn install(self: *Self) void {
    _ = ParentSet(self.widget());
    debug("{x} MenuItem {}", .{self.wd.id, self.wd.rect});

    if (self.wd.id == FocusedWidgetId()) {
      self.focused = true;
    }

    self.processEvents();

    if (self.wd.options.borderGet().nonZero()) {
      const rs = self.wd.borderRectScale();
      PathAddRect(rs.r, self.wd.options.corner_radiusGet().scale(rs.s));
      var col = Color.lerp(self.wd.options.color_bg(), 0.3, self.wd.options.color());
      PathFillConvex(col);
    }

    if (self.active()) {
      // hovered
      const fill = self.wd.options.color_focus_bg();
      const rs = self.wd.backgroundRectScale();
      PathAddRect(rs.r, self.wd.options.corner_radiusGet().scale(rs.s));
      PathFillConvex(fill);
    }
    else if (self.wd.options.background orelse false) {
      const fill = self.wd.options.color_bg();
      const rs = self.wd.backgroundRectScale();
      PathAddRect(rs.r, self.wd.options.corner_radiusGet().scale(rs.s));
      PathFillConvex(fill);
    }
  }

  pub fn active(self: *const Self) bool {
    return (self.focused or self.highlight or (self.activeRect() != null));
  }

  pub fn activeRect(self: *const Self) ?Rect {
    var act = false;
    if (self.submenu) {
      if (MenuGet().?.submenus_activated) {
        if (FocusedWidgetIdInCurrentWindow()) |id| {
          if (id == self.wd.id) {
            act = true;
          }
        }
      }
    }
    else if (self.activated) {
      act = true;
    }

    if (act) {
      const rs = self.wd.borderRectScale();
      return rs.r.scale(1 / WindowNaturalScale());
    }
    else {
      return null;
    }
  }

  pub fn processEvents(self: *Self) void {
    const rs = self.wd.borderRectScale();
    var iter = EventIterator.init(self.wd.id, rs.r);
    while (iter.next()) |e| {
      switch (e.evt) {
        .mouse => {
          if (e.evt.mouse.state == .leftdown) {
            e.handled = true;
            if (self.submenu) {
              FocusWidget(self.wd.id, &iter);
              MenuGet().?.submenus_activated = true;
            }
          }
          else if (e.evt.mouse.state == .leftup) {
            e.handled = true;
            if (!self.submenu) {
              self.activated = true;
            }
          }
          else if (e.evt.mouse.state == .motion) {
            e.handled = true;
            // TODO don't do the rest here if the menu has an existing popup and the motion is towards the popup
            self.highlight = true;
            if (MenuGet().?.submenus_activated) {
              const winId = FocusedWindowId();
              FocusWindow(null, null);
              FocusWidget(self.wd.id, null);
              if (!PopupIn()) {
                // if we are in a regular window (like File), then we don't want
                // to focus the main window, so keep the focus on the popups
                FocusWindow(winId, null);
              }
            }
          }
        },
        .key => {
          if (e.evt.key.state == .down and e.evt.key.keysym == c.SDLK_SPACE) {
            e.handled = true;
            if (self.submenu) {
              FocusWidget(self.wd.id, &iter);
              MenuGet().?.submenus_activated = true;
            }
            else {
              self.activated = true;
            }
          }
        },
        else => {},
      }
    }

    BubbleEvents(self.widget());
  }

  fn widget(self: *Self) Widget {
    return Widget.init(self, ID, rectFor, minSizeForChild, screenRectScale, bubbleEvent);
  }

  fn ID(self: *const Self) u32 {
    return self.wd.id;
  }

  pub fn rectFor(self: *Self, id: u32, opts: Options) Rect {
    return PlaceIn(id, self.wd.contentRect(), opts);
  }

  pub fn minSizeForChild(self: *Self, s: Size) void {
    self.wd.minSizeMax(self.wd.padSize(s));
  }

  pub fn screenRectScale(self: *Self, rect: Rect) RectScale {
    return self.wd.parent.screenRectScale(rect);
  }

  pub fn bubbleEvent(self: *Self, e: *Event) void {
    self.wd.parent.bubbleEvent(e);
  }

  pub fn deinit(self: *Self) void {
    self.wd.reportMinSize();
    _ = ParentSet(self.wd.parent);
  }
};

pub const LabelWidget = struct {
  const Self = @This();
  var Defaults: Options = .{
    .padding = Rect.all(4),
    .color_style = .control,
  };

  wd: WidgetData = undefined,
  label: []const u8 = undefined,

  pub fn init(self: *Self, src: std.builtin.SourceLocation, id_extra: usize, comptime fmt: []const u8, args: anytype, opts: Options) void {
    var cw = current_window orelse unreachable;
    self.label = std.fmt.allocPrint(cw.arena, fmt, args) catch unreachable;

    const options = OptionsGet(opts).overrideIfNull(Defaults);
    const size = options.font().textSize(self.label);
    self.wd = WidgetData.init(src, id_extra, options.overrideMinSizeContent(size));
    self.wd.placeInsideNoExpand();
  }

  pub fn initNoFormat(self: *Self, src: std.builtin.SourceLocation, id_extra: usize, label: []const u8, opts: Options) void {
    const options = OptionsGet(opts);
    self.label = label;
    const size = options.font().textSize(self.label);
    self.wd = WidgetData.init(src, id_extra, options.overrideMinSizeContent(size));
    self.wd.placeInsideNoExpand();
  }

  pub fn install(self: *Self) void {
    debug("{x} Label \"{s:<10}\" {}", .{self.wd.id, self.label, self.wd.rect});
    self.wd.borderAndBackground();
    const rs = self.wd.contentRectScale();

    const oldclip = Clip(rs.r);
    if (!ClipGet().empty()) {
      renderText(self.wd.options.font(), self.label, rs, self.wd.options.color());
    }
    ClipSet(oldclip);

    self.wd.reportMinSize();
  }
};

pub fn Label(src: std.builtin.SourceLocation, id_extra: usize, comptime fmt: []const u8, args: anytype, opts: Options) void {
  var lw = LabelWidget{};
  lw.init(src, id_extra, fmt, args, opts);
  lw.install();
}

pub fn LabelNoFormat(src: std.builtin.SourceLocation, id_extra: usize, label: []const u8, opts: Options) void {
  var lw = LabelWidget{};
  lw.initNoFormat(src, id_extra, label, opts);
  lw.install();
}

pub fn Icon(src: std.builtin.SourceLocation, id_extra: usize, name: []const u8, tvg_bytes: []const u8, height: f32, opts: Options) void {
  const options = OptionsGet(opts);

  const size = Size{.w = IconWidth(name, tvg_bytes, height), .h = height};

  var wd = WidgetData.init(src, id_extra, options.overrideMinSizeContent(size));
  wd.placeInsideNoExpand();
  wd.borderAndBackground();

  debug("{x} Icon \"{s:<10}\" {}", .{wd.id, name, wd.rect});

  var highlight: bool = false;

  const rs = wd.contentRectScale();
  const oldclip = Clip(rs.r);
  if (!ClipGet().empty()) {
    var iter = EventIterator.init(wd.id, rs.r);
    while (iter.next()) |e| {
      if (e.evt == .mouse) {
        if (e.evt.mouse.state == .motion) {
          if (Highlight(e.evt.mouse.p, rs.r)) {
            highlight = true;
          }
          e.handled = true;
        }
      }
    }

    renderIcon(name, tvg_bytes, rs, options.color());
  }

  ClipSet(oldclip);

  wd.reportMinSize();
}

pub fn ButtonContainer(src: std.builtin.SourceLocation, id_extra: usize, show_focus: bool, opts: Options) *ButtonContainerWidget {
  const cw = current_window orelse unreachable;
  var ret = cw.arena.create(ButtonContainerWidget) catch unreachable;
  ret.* = ButtonContainerWidget{};
  ret.init(src, id_extra, show_focus, opts);
  ret.install();
  return ret;
}

pub const ButtonContainerWidget = struct {
  const Self = @This();
  wd: WidgetData = undefined,
  highlight: bool = false,
  captured: bool = false,
  focused: bool = false,
  show_focus: bool = false,
  clicked: bool = false,

  pub fn init(self: *Self, src: std.builtin.SourceLocation, id_extra: usize, show_focus: bool, opts: Options) void {
    const options = OptionsGet(opts);
    self.wd = WidgetData.init(src, id_extra, options);
    if (!self.wd.rect.empty()) {
      TabIndexSet(self.wd.id, options.tab_index);
    }
    self.show_focus = show_focus;
  }

  pub fn install(self: *Self) void {
    _ = ParentSet(self.widget());

    debug("{x} ButtonContainer {}", .{self.wd.id, self.wd.rect});

    self.captured = CaptureMouseMaintain(self.wd.id);
    self.clicked = self.processEvents();
    if (self.clicked) {
      CueFrame();
    }
    self.focused = (self.wd.id == FocusedWidgetId());

    if (self.wd.options.borderGet().nonZero()) {
      const rs = self.wd.borderRectScale();
      PathAddRect(rs.r, self.wd.options.corner_radiusGet().scale(rs.s));
      var col = Color.lerp(self.wd.options.color_bg(), 0.3, self.wd.options.color());
      PathFillConvex(col);
    }

    if (self.wd.options.background orelse false) {
      const rs = self.wd.backgroundRectScale();
      var fill: Color = undefined;
      if (self.captured) {
        // pressed
        fill = Color.lerp(self.wd.options.color_bg(), 0.2, self.wd.options.color());
      }
      else if (self.highlight) {
        // hovered
        fill = Color.lerp(self.wd.options.color_bg(), 0.1, self.wd.options.color());
      }
      else {
        fill = self.wd.options.color_bg();
      }

      PathAddRect(rs.r, self.wd.options.corner_radiusGet().scale(rs.s));
      PathFillConvex(fill);
    }

    if (self.focused and self.show_focus) {
      self.wd.focusBorder();
    }
  }

  pub fn processEvents(self: *Self) bool {
    var ret = false;
    const rs = self.wd.borderRectScale();
    var iter = EventIterator.init(self.wd.id, rs.r);
    while (iter.next()) |e| {
      switch (e.evt) {
        .mouse => {
          if (e.evt.mouse.state == .leftdown) {
            e.handled = true;
            CaptureMouse(self.wd.id);
            self.captured = true;
            FocusWidget(self.wd.id, &iter);
          }
          else if (e.evt.mouse.state == .leftup) {
            e.handled = true;
            if (self.captured) {
              CaptureMouse(null);
              self.captured = false;
              if (rs.r.contains(e.evt.mouse.p)) {
                ret = true;
              }
            }
          }
          else if (e.evt.mouse.state == .motion) {
            e.handled = true;
            if (Highlight(e.evt.mouse.p, rs.r)) {
              self.highlight = true;
            }
          }
        },
        .key => {
          if (e.evt.key.state == .down and e.evt.key.keysym == c.SDLK_SPACE) {
            e.handled = true;
            ret = true;
          }
        },
        else => {},
      }
    }

    BubbleEvents(self.widget());

    return ret;
  }

  fn widget(self: *Self) Widget {
    return Widget.init(self, ID, rectFor, minSizeForChild, screenRectScale, bubbleEvent);
  }

  fn ID(self: *const Self) u32 {
    return self.wd.id;
  }

  pub fn rectFor(self: *Self, id: u32, opts: Options) Rect {
    return PlaceIn(id, self.wd.contentRect(), opts);
  }

  pub fn minSizeForChild(self: *Self, s: Size) void {
    self.wd.minSizeMax(self.wd.padSize(s));
  }

  pub fn screenRectScale(self: *Self, r: Rect) RectScale {
    return self.wd.parent.screenRectScale(r);
  }

  pub fn bubbleEvent(self: *Self, e: *Event) void {
    self.wd.parent.bubbleEvent(e);
  }

  pub fn deinit(self: *Self) void {
    self.wd.reportMinSize();
    _ = ParentSet(self.wd.parent);
  }
};

pub const ButtonWidget = struct {
  const Self = @This();
  var Defaults: Options = .{
    .margin = Rect.all(4),
    .corner_radius = Rect.all(5),
    .padding = Rect.all(4),
    .background = true,
    .color_style = .control,
  };

  bc: ButtonContainerWidget = undefined,
  label: []const u8 = undefined,

  pub fn init(self: *Self, src: std.builtin.SourceLocation, id_extra: usize, label: []const u8, opts: Options) void {
    self.bc = ButtonContainerWidget{};
    _ = self.bc.init(src, id_extra, true, OptionsGet(opts).overrideIfNull(Defaults));
    self.label = label;
  }

  pub fn install(self: *ButtonWidget) bool {
    debug("Button {s}", .{self.label});
    self.bc.install();
    const clicked = self.bc.clicked;

    LabelNoFormat(@src(), 0, self.label, self.bc.wd.options.plain());

    self.bc.deinit();
    return clicked;
  }
};

pub fn Button(src: std.builtin.SourceLocation, id_extra: usize, label: []const u8, opts: Options) bool {
  var button = ButtonWidget{};
  button.init(src, id_extra, label, opts);
  return button.install();
}

pub fn ButtonIcon(src: std.builtin.SourceLocation, id_extra: usize, height: f32, name: []const u8, tvg_bytes: []const u8, opts: Options) bool {
  var Defaults: Options = .{
    .margin = gui.Rect.all(4),
    .corner_radius = Rect.all(5),
    .padding = Rect.all(4),
    .background = true,
    .color_style = .control,
    .gravity = .center,
  };
  const options = OptionsGet(opts).overrideIfNull(Defaults);
  debug("ButtonIcon \"{s}\" {}", .{name, options});
  var bc = ButtonContainer(src, id_extra, true, options);
  defer bc.deinit();

  Icon(@src(), 0, name, tvg_bytes, height, options.plain());

  return bc.clicked;
}

pub fn Checkbox(src: std.builtin.SourceLocation, id_extra: usize, target: *bool, label: []const u8, opts: Options) void {
  debug("Checkbox {s}", .{label});
  const options = OptionsGet(opts);
  var bc = ButtonContainer(src, id_extra, false, options.override(.{.background = false}));
  defer bc.deinit();

  if (bc.clicked) {
    target.* = !target.*;
  }

  var box = Box(@src(), 0, .horizontal, options.plain().override(.{.expand = .both}));
  defer box.deinit();

  var check_size = options.font().lineSkip();
  const r = SpacerRect(@src(), 0, .{.min_size = Size.all(check_size), .gravity = .left});

  var rs = ParentGet().screenRectScale(r);
  const thick_focus = 2;
  rs.r = rs.r.insetAll(thick_focus / 2 * rs.s);

  PathAddRect(rs.r, options.corner_radiusGet().scale(rs.s));
  var col = Color.lerp(options.color_bg(), 0.3, options.color());
  PathFillConvex(col);

  if (bc.focused) {
    PathAddRect(rs.r, options.corner_radiusGet().scale(rs.s));
    PathStroke(true, thick_focus * rs.s, options.color_focus_bg());
  }

  rs.r = rs.r.insetAll(0.5 * rs.s);

  PathAddRect(rs.r, options.corner_radiusGet().scale(rs.s));
  var fill = options.color_bg();
  if (target.*) {
    fill = options.color_focus_bg();
  }

  if (bc.captured) {
    // pressed
    fill = Color.lerp(fill, 0.2, options.color());
  }
  else if (bc.highlight) {
    // hovered
    fill = Color.lerp(fill, 0.1, options.color());
  }

  PathFillConvex(fill);

  if (target.*) {
    const pad = math.max(1.0, rs.r.w / 6);

    var thick = math.max(1.0, rs.r.w / 5);
    const size = rs.r.w - (thick / 2) - pad * 2;
    const third = size / 3.0;
    const x = rs.r.x + pad + (0.25 * thick) + third;
    const y = rs.r.y + pad + (0.25 * thick) + size - (third * 0.5);

    thick /= 1.5;

    PathAddPoint(Point{.x = x - third, .y = y - third});
    PathAddPoint(Point{.x = x, .y = y});
    PathAddPoint(Point{.x = x + third * 2, .y = y - third * 2});
    PathStroke(false, thick, options.color_focus());
  }

  LabelNoFormat(@src(), 0, label, options.override(.{
    .background = false,
    .margin = .{.x = 4, .y = 0, .w = 0, .h = 0},
  }));
}

pub fn TextEntry(src: std.builtin.SourceLocation, id_extra: usize, width: f32, text: []u8, opts: Options) void {
  const cw = current_window orelse unreachable;
  var ret = cw.arena.create(TextEntryWidget) catch unreachable;
  ret.* = TextEntryWidget{};
  ret.allocator = cw.arena;
  ret.init(src, id_extra, width, text, opts);
  ret.install();
  ret.deinit();
}

pub const TextEntryWidget = struct {
  const Self = @This();
  var Defaults: Options = .{
    .margin = Rect.all(4),
    .corner_radius = Rect.all(5),
    .border = Rect.all(1),
    .padding = Rect.all(4),
    .background = true,
    .color_style = .content,
  };

  wd: WidgetData = undefined,

  allocator: ?std.mem.Allocator = null,
  captured: bool = false,
  text: []u8 = undefined,
  len: usize = undefined,

  pub fn init(self: *Self, src: std.builtin.SourceLocation, id_extra: usize, width: f32, text: []u8, opts: Options) void {
    const options = OptionsGet(opts).overrideIfNull(Defaults);

    const msize = options.font().textSize("M");
    const size = Size{.w = msize.w * width, .h = msize.h};
    self.wd = WidgetData.init(src, id_extra, options.overrideMinSizeContent(size));

    if (!self.wd.rect.empty()) {
      TabIndexSet(self.wd.id, options.tab_index);
    }
    self.text = text;
    self.len = std.mem.indexOfScalar(u8, self.text, 0) orelse self.text.len;
  }

  pub fn install(self: *Self) void {
    _ = ParentSet(self.widget());
    debug("{x} Text {}", .{self.wd.id, self.wd.rect});
    self.wd.borderAndBackground();

    self.captured = CaptureMouseMaintain(self.wd.id);

    self.processEvents();
    const focused = (self.wd.id == FocusedWidgetId());

    const rs = self.wd.contentRectScale();

    const oldclip = Clip(rs.r);
    if (!ClipGet().empty()) {
      renderText(self.wd.options.font(), self.text[0..self.len], rs, self.wd.options.color());
    }
    ClipSet(oldclip);

    if (focused) {
      self.wd.focusBorder();
    }
  }

  pub fn processEvents(self: *Self) void {
    const rs = self.wd.borderRectScale();
    var iter = EventIterator.init(self.wd.id, rs.r);
    while (iter.next()) |e| {
      switch (e.evt) {
        .key => {
          if (e.evt.key.keysym == c.SDLK_BACKSPACE and
              (e.evt.key.state == .down or e.evt.key.state == .repeat)) {
            e.handled = true;
            self.len -|= 1;
            self.text[self.len] = 0;
          }
          else if (e.evt.key.keysym == c.SDLK_v and e.evt.key.state == .down and (e.evt.key.mod & c.KMOD_GUI) > 0) {
            const ct = c.SDL_GetClipboardText();
            defer c.SDL_free(ct);

            var i = self.len;
            while (i < self.text.len and ct.* != 0) : (i += 1) {
              self.text[i] = ct[i - self.len];
            }
            self.len = i;
          }
        },
        .text => {
          e.handled = true;
          var new = std.mem.sliceTo(&e.evt.text.text, 0);
          new.len = math.min(new.len, self.text.len - self.len);
          std.mem.copy(u8, self.text[self.len..], new);
          self.len += new.len;
        },
        .mouse => {
          if (e.evt.mouse.state == .leftdown) {
            e.handled = true;
            CaptureMouse(self.wd.id);
            self.captured = true;
            FocusWidget(self.wd.id, &iter);
          }
          else if (e.evt.mouse.state == .leftup) {
            e.handled = true;
            CaptureMouse(null);
            self.captured = false;
          }
          else if (e.evt.mouse.state == .motion) {
          }
        },
        else => {},
      }
    }

    BubbleEvents(self.widget());
  }

  fn widget(self: *Self) Widget {
    return Widget.init(self, ID, rectFor, minSizeForChild, screenRectScale, bubbleEvent);
  }

  fn ID(self: *const Self) u32 {
    return self.wd.id;
  }

  pub fn rectFor(self: *Self, id: u32, opts: Options) Rect {
    return PlaceIn(id, self.wd.contentRect(), opts);
  }

  pub fn minSizeForChild(self: *Self, s: Size) void {
    self.wd.minSizeMax(self.wd.padSize(s));
  }

  pub fn screenRectScale(self: *Self, r: Rect) RectScale {
    return self.wd.parent.screenRectScale(r);
  }

  pub fn bubbleEvent(self: *Self, e: *Event) void {
    self.wd.parent.bubbleEvent(e);
  }

  pub fn deinit(self: *Self) void {
    self.wd.reportMinSize();
    _ = ParentSet(self.wd.parent);

    if (self.allocator) |a| {
      a.destroy(self);
    }
  }
};

pub const Color = struct {
  r: u8 = 255,
  g: u8 = 255,
  b: u8 = 255,
  a: u8 = 255,

  pub fn sdlcolor(self: *const Color) c.SDL_Color {
    return c.SDL_Color{.r = self.r, .g = self.g, .b = self.b, .a = self.a};
  }

  pub fn transparent(x: Color, y: f32) Color {
    return Color{.r = x.r, .g = x.g, .b = x.b,
      .a = @floatToInt(u8, @intToFloat(f32, x.a) * y),
    };
  }

  pub fn lerp(x: Color, y: f32, z: Color) Color {
    return Color{
      .r = @floatToInt(u8, @intToFloat(f32, x.r) * (1-y) + @intToFloat(f32, z.r) * y),
      .g = @floatToInt(u8, @intToFloat(f32, x.g) * (1-y) + @intToFloat(f32, z.g) * y),
      .b = @floatToInt(u8, @intToFloat(f32, x.b) * (1-y) + @intToFloat(f32, z.b) * y),
      .a = @floatToInt(u8, @intToFloat(f32, x.a) * (1-y) + @intToFloat(f32, z.a) * y),
    };
  }

  pub fn format(self: *const Color, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try std.fmt.format(writer, "Color{{ {x} {x} {x} {x} }}", .{self.r, self.g, self.b, self.a});
  }
};

pub const Point = struct {
  const Self = @This();
  x: f32 = 0,
  y: f32 = 0,

  pub fn inRectScale(self: *const Self, rs: RectScale) Self {
    return Self{.x = (self.x - rs.r.x) / rs.s, .y = (self.y - rs.r.y) / rs.s};
  }

  pub fn plus(self: *const Self, b: Self) Self {
    return Self{.x = self.x + b.x, .y = self.y + b.y};
  }

  pub fn diff(a: Self, b: Self) Self {
    return Self{.x = a.x - b.x, .y = a.y - b.y};
  }

  pub fn scale(self: *const Self, s: f32) Self {
    return Self{.x = self.x * s, .y = self.y * s};
  }

  pub fn equals(self: *const Self, b: Self) bool {
    return (self.x == b.x and self.y == b.y);
  }

  pub fn length(self: *const Self) f32 {
    return @sqrt((self.x * self.x) + (self.y * self.y));
  }

  pub fn normalize(self: *const Self) Self {
    const d2 = self.x * self.x + self.y * self.y;
    if (d2 == 0) {
      return Self{.x = 1.0, .y = 0.0};
    }
    else {
      const inv_len = 1.0 / @sqrt(d2);
      return Self{.x = self.x * inv_len, .y = self.y * inv_len};
    }
  }

  pub fn format(self: *const Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try std.fmt.format(writer, "Point{{ {d} {d} }}", .{self.x, self.y});
  }
};

pub const Size = struct {
  const Self = @This();
  w: f32 = 0,
  h: f32 = 0,
  
  pub fn all(v: f32) Self {
    return Self{.w = v, .h = v};
  }

  pub fn pad(s: *const Self, padding: Rect) Self {
    return Size{.w = s.w + padding.x + padding.w, .h = s.h + padding.y + padding.h};
  }

  pub fn max(a: Self, b: Self) Self {
    return Self{.w = math.max(a.w, b.w), .h = math.max(a.h, b.h)};
  }

  pub fn scale(self: *const Self, s: f32) Self {
    return Self{.w = self.w * s, .h = self.h * s};
  }

  pub fn format(self: *const Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try std.fmt.format(writer, "Size{{ {d} {d} }}", .{self.w, self.h});
  }
};

pub const Rect = struct {
  const Self = @This();
  x: f32 = 0,
  y: f32 = 0,
  w: f32 = 0,
  h: f32 = 0,

  pub fn negate(self: *const Self) Rect {
    return Self{.x = -self.x, .y = -self.y, .w = -self.w, .h = -self.h};
  }
  
  pub fn add(self: *const Self, r: Self) Rect {
    return Self{.x = self.x + r.x, .y = self.y + r.y, .w = self.w + r.w, .h = self.h + r.h};
  }

  pub fn nonZero(self: *const Self) bool {
    return (self.x != 0 or self.y != 0 or self.w != 0 or self.h != 0);
  }

  pub fn all(v: f32) Self {
    return Self{.x = v, .y = v, .w = v, .h = v};
  }

  pub fn fromPoint(p: Point) Self {
    return Self{.x = p.x, .y = p.y};
  }

  pub fn toSize(self: *const Self, s: Size) Self {
    return Self{.x = self.x, .y = self.y, .w = s.w, .h = s.h};
  }

  pub fn justSize(self: *const Self) Self {
    return Self{.x = 0, .y = 0, .w = self.w, .h = self.h};
  }

  pub fn topleft(self: *const Self) Point {
    return Point{.x = self.x, .y = self.y};
  }

  pub fn size(self: *const Self) Size {
    return Size{.w = self.w, .h = self.h};
  }

  pub fn contains(self: *const Self, p: Point) bool {
    return (p.x >= self.x and p.x <= (self.x + self.w)
        and p.y >= self.y and p.y <= (self.y + self.h));
  }

  pub fn empty(self: *const Self) bool {
    return (self.w == 0 or self.h == 0);
  }

  pub fn scale(self: *const Self, s: f32) Self {
    return Self{.x = self.x * s, .y = self.y * s, .w = self.w * s, .h = self.h * s};
  }

  pub fn offset(self: *const Self, r: Rect) Self {
    return Self{.x = self.x + r.x, .y = self.y + r.y, .w = self.w, .h = self.h};
  }

  pub fn intersect(a: Self, b: Self) Self {
    const ax2 = a.x + a.w;
    const ay2 = a.y + a.h;
    const bx2 = b.x + b.w;
    const by2 = b.y + b.h;
    const x = math.max(a.x, b.x);
    const y = math.max(a.y, b.y);
    const x2 = math.min(ax2, bx2);
    const y2 = math.min(ay2, by2);
    return Self{.x = x, .y = y, .w = math.max(0, x2 - x), .h = math.max(0, y2 - y)};
  }
  
  pub fn shrinkToSize(self: *const Self, s: Size) Self {
    return Self{.x = self.x, .y = self.y,
                .w = math.min(self.w, s.w), .h = math.min(self.h, s.h)};
  }

  pub fn inset(self: *const Self, r: Rect) Self {
    return Self{.x = self.x + r.x, .y = self.y + r.y,
                .w = math.max(0, self.w - r.x - r.w), .h = math.max(0, self.h - r.y - r.h)};
  }

  pub fn insetAll(self: *const Self, p: f32) Self {
    return self.inset(Rect.all(p));
  }

  pub fn outset(self: *const Self, r: Rect) Self {
    return Self{.x = self.x - r.x, .y = self.y - r.y,
                .w = self.w + r.x + r.w, .h = self.h + r.y + r.h};
  }

  pub fn outsetAll(self: *const Self, p: f32) Self {
    return self.outset(Rect.all(p));
  }

  pub fn format(self: *const Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try std.fmt.format(writer, "Rect{{ {d} {d} {d} {d} }}", .{self.x, self.y, self.w, self.h});
  }
};

pub const RectScale = struct {
  r: Rect = Rect{},
  s: f32 = 0.0,

  pub fn child(rs: *const RectScale, r: Rect) RectScale {
    return .{.r = r.scale(rs.s).offset(rs.r), .s = rs.s};
  }

  pub fn childPoint(rs: *const RectScale, p: Point) Point {
    return p.scale(rs.s).plus(rs.r.topleft());
  }
};

//pub var render_text: bool = false;

pub fn renderText(font: Font, text: []const u8, rs: RectScale, color: Color) void {
  if (text.len == 0) {
    return;
  }

  //if (!render_text) return;

  var cw = current_window orelse unreachable;
  const drqlen = cw.deferred_render_queues.items.len;
  if (drqlen > 1) {
    var txt = cw.arena.alloc(u8, text.len) catch unreachable;
    std.mem.copy(u8, txt, text);
    var cmd = RenderCmd{.clip = ClipGet(), .cmd = .{.text = .{.font = font, .text = txt, .rs = rs, .color = color}}};
    cw.deferred_render_queues.items[drqlen-2].cmds.append(cmd) catch unreachable;
    return;
  }

  // Make sure to always ask for a bigger size font, we'll reduce it down below
  const target_size = font.size * rs.s;
  const ask_size = @ceil(target_size);
  const target_fraction = target_size / ask_size;

  const sized_font = font.resize(ask_size);
  // make sure we refresh the font cache
  _ = FontCacheGet(sized_font);
  const textTexture = TextTexture(sized_font, text);

  var w: c_int = undefined;
  var h: c_int = undefined;
  _ = c.SDL_QueryTexture(textTexture, null, null, &w, &h);

  const tsrcr = c.SDL_Rect{.x = 0, .y = 0,
    .w = w,
    .h = h,
  };
  const tdesr = c.SDL_FRect{
    .x = rs.r.x,
    .y = rs.r.y,
    .w = @intToFloat(f32, tsrcr.w) * target_fraction,
    .h = @intToFloat(f32, tsrcr.h) * target_fraction,
  };

  _ = c.SDL_SetTextureAlphaMod(textTexture, color.a);
  _ = c.SDL_SetTextureColorMod(textTexture, color.r, color.g, color.b);
  _ = c.SDL_RenderCopyF(Renderer(), textTexture, &tsrcr, &tdesr);
}

pub fn renderIcon(name: []const u8, tvg_bytes: []const u8, rs: RectScale, colormod: Color) void {
  var cw = current_window orelse unreachable;
  const drqlen = cw.deferred_render_queues.items.len;
  if (drqlen > 1) {
    var name_copy = cw.arena.alloc(u8, name.len) catch unreachable;
    std.mem.copy(u8, name_copy, name);
    var cmd = RenderCmd{.clip = ClipGet(), .cmd = .{.icon = .{.name = name_copy, .tvg_bytes = tvg_bytes, .rs = rs, .colormod = colormod}}};
    cw.deferred_render_queues.items[drqlen-2].cmds.append(cmd) catch unreachable;
    return;
  }

  // Make sure to always ask for a bigger size icon, we'll reduce it down below
  const target_size = rs.r.h;
  const ask_height = @ceil(target_size);
  const target_fraction = target_size / ask_height;

  const texture = IconTexture(name, tvg_bytes, ask_height);

  var w: c_int = undefined;
  var h: c_int = undefined;
  _ = c.SDL_QueryTexture(texture, null, null, &w, &h);

  const tsrcr = c.SDL_Rect{.x = 0, .y = 0,
    .w = w,
    .h = h,
  };
  const tdesr = c.SDL_FRect{
    .x = rs.r.x,
    .y = rs.r.y,
    .w = @intToFloat(f32, tsrcr.w) * target_fraction,
    .h = @intToFloat(f32, tsrcr.h) * target_fraction,
  };

  //_ = c.SDL_SetRenderDrawColor(Renderer(), 100, 100, 0, 255);
  //_ = c.SDL_RenderFillRectF(Renderer(), &tdesr);

  _ = c.SDL_SetTextureAlphaMod(texture, colormod.a);
  _ = c.SDL_SetTextureColorMod(texture, colormod.r, colormod.g, colormod.b);
  _ = c.SDL_RenderCopyF(Renderer(), texture, &tsrcr, &tdesr);
}

pub const KeyEvent = struct {
  const Kind = enum {
    down,
    repeat,
    up,
  };
  keysym: i32,
  mod: u16,
  state: Kind,
};

pub const TextEvent = struct {
  text: [32]u8,
};

pub const MouseEvent = struct {
  const Kind = enum {
    leftdown,
    leftup,
    rightdown,
    rightup,
    motion,
    wheel_y,
  };
  p: Point,
  dp: Point,  // for .motion
  wheel: f32,  // for .wheel_y
  floating_win: u32,
  state: Kind,
};

pub const ClosePopupEvent = struct {
  // if we are closing the popups because the user selected a menu item then we
  // should defocus the original File menu
  defocus: bool = true,
};

pub const AnyEvent = union(enum) {
  key: KeyEvent,
  text: TextEvent,
  mouse: MouseEvent,
  close_popup: ClosePopupEvent,
};

pub const Event = struct {
  handled: bool = false,
  focus_windowId: u32 = 0,
  focus_widgetId: ?u32 = null,
  evt: AnyEvent,
};

pub const WidgetData = struct {
  id: u32 = undefined,
  parent: Widget = undefined,
  rect: Rect = Rect{},
  min_size: Size = Size{},
  options: Options = undefined,

  pub fn init(src: std.builtin.SourceLocation, id_extra: usize, opts: Options) WidgetData {
    var self = WidgetData{};
    self.options = OptionsGet(opts);

    self.parent = ParentGet();
    self.id = self.parent.extendID(src, id_extra);
    self.rect = self.parent.rectFor(self.id, self.options);
    self.min_size = self.options.min_size orelse Size{};
    
    return self;
  }

  pub fn borderAndBackground(self: *const WidgetData) void {
    var bg = self.options.background orelse false;
    if (self.options.borderGet().nonZero()) {
      bg = true;
      const rs = self.borderRectScale();
      PathAddRect(rs.r, self.options.corner_radiusGet().scale(rs.s));
      var col = Color.lerp(self.options.color_bg(), 0.3, self.options.color());
      PathFillConvex(col);
    }

    if (bg) {
      const rs = self.backgroundRectScale();
      PathAddRect(rs.r, self.options.corner_radiusGet().scale(rs.s));
      PathFillConvex(self.options.color_bg());
    }
  }

  pub fn focusBorder(self: *const WidgetData) void {
    const thick_px = 4;
    const rs = self.borderRectScale();
    PathAddRect(rs.r.insetAll(thick_px / 2), self.options.corner_radiusGet().scale(rs.s));
    PathStroke(true, thick_px, self.options.color_focus_bg());
  }

  pub fn placeInsideNoExpand(self: *WidgetData) void {
    self.rect = PlaceIn(null, self.rect, self.options.override(.{.expand = .none}));
  }

  pub fn borderRect(self: *const WidgetData) Rect {
    return self.rect.inset(self.options.marginGet());
  }
  
  pub fn borderRectScale(self: *const WidgetData) RectScale {
    return self.parent.screenRectScale(self.borderRect());
  }

  pub fn backgroundRect(self: *const WidgetData) Rect {
    return self.rect.inset(self.options.marginGet()).inset(self.options.borderGet());
  }

  pub fn backgroundRectScale(self: *const WidgetData) RectScale {
    return self.parent.screenRectScale(self.backgroundRect());
  }

  pub fn contentRect(self: *const WidgetData) Rect {
    return self.rect.inset(self.options.marginGet()).inset(self.options.borderGet()).inset(self.options.paddingGet());
  }

  pub fn contentRectScale(self: *const WidgetData) RectScale {
    return self.parent.screenRectScale(self.contentRect());
  }

  pub fn padSize(self: *const WidgetData, s: Size) Size {
    return s.pad(self.options.paddingGet()).pad(self.options.borderGet()).pad(self.options.marginGet());
  }

  pub fn minSizeMax(self: *WidgetData, s: Size) void {
    self.min_size = Size.max(self.min_size, s);
  }

  pub fn reportMinSize(self: *const WidgetData) void {
    if (MinSizeGetPrevious(self.id)) |ms| {
      // If the size we got was exactly our previous min size then our min size
      // was a binding constraint.  So if our min size changed it might cause
      // layout changes.

      // If this was like a Label where we knew the min size before getting our
      // rect, then either our min size is the same as previous, or our rect is
      // a different size than our previous min size.
      if ((self.rect.w == ms.w and ms.w != self.min_size.w) or
          (self.rect.h == ms.h and ms.h != self.min_size.h)) {
        CueFrame();
      }
    }
    else {
      // This is the first frame for this widget.  Almost always need a
      // second frame to appear correctly since nobody knew our min size the
      // first frame.
      CueFrame();
    }
    MinSizeSet(self.id, self.min_size);
    self.parent.minSizeForChild(self.min_size);
  }
};

pub const Widget = struct {
  ptr: *anyopaque,
  vtable: *const VTable,

  const VTable = struct {
    id: fn (ptr: *anyopaque) u32,
    rectFor: fn (ptr: *anyopaque, id: u32, opts: Options) Rect,
    minSizeForChild: fn (ptr: *anyopaque, s: Size) void,
    screenRectScale: fn (ptr: *anyopaque, r: Rect) RectScale,
    bubbleEvent: fn (ptr: *anyopaque, e: *Event) void,
  };

  pub fn init(pointer: anytype,
              comptime idFn: fn (ptr: @TypeOf(pointer)) u32,
              comptime rectForFn: fn (ptr: @TypeOf(pointer), id: u32, opts: Options) Rect,
              comptime minSizeForChildFn: fn (ptr: @TypeOf(pointer), s: Size) void,
              comptime screenRectScaleFn: fn (ptr: @TypeOf(pointer), r: Rect) RectScale,
              comptime bubbleEventFn: fn (ptr: @TypeOf(pointer), e: *Event) void,
              ) Widget {
    const Ptr = @TypeOf(pointer);
    const ptr_info = @typeInfo(Ptr);
    std.debug.assert(ptr_info == .Pointer); // Must be a pointer
    std.debug.assert(ptr_info.Pointer.size == .One); // Must be a single-item pointer
    const alignment = ptr_info.Pointer.alignment;

    const gen = struct {
      fn idImpl(ptr: *anyopaque) u32 {
        const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
        return @call(.{.modifier = .always_inline}, idFn, .{self});
      }

      fn rectForImpl(ptr: *anyopaque, id: u32, opts: Options) Rect {
        const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
        return @call(.{.modifier = .always_inline}, rectForFn, .{self, id, opts});
      }

      fn minSizeForChildImpl(ptr: *anyopaque, s: Size) void {
        const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
        return @call(.{.modifier = .always_inline}, minSizeForChildFn, .{self, s});
      }
      
      fn screenRectScaleImpl(ptr: *anyopaque, r: Rect) RectScale {
        const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
        return @call(.{.modifier = .always_inline}, screenRectScaleFn, .{self, r});
      }

      fn bubbleEventImpl(ptr: *anyopaque, e: *Event) void {
        const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
        return @call(.{.modifier = .always_inline}, bubbleEventFn, .{self, e});
      }

      const vtable = VTable {
        .id = idImpl,
        .rectFor = rectForImpl,
        .minSizeForChild = minSizeForChildImpl,
        .screenRectScale = screenRectScaleImpl,
        .bubbleEvent = bubbleEventImpl,
      };
    };

    return .{
      .ptr = pointer,
      .vtable = &gen.vtable,
    };
  }

  pub fn ID(self: Widget) u32 {
    return self.vtable.id(self.ptr);
  }

  pub fn extendID(self: Widget, src: std.builtin.SourceLocation, id_extra: usize) u32 {
    var hash = fnv.init();
    hash.value = self.ID();
    hash.update(src.file);
    hash.update(std.mem.asBytes(&src.line));
    hash.update(std.mem.asBytes(&src.column));
    hash.update(std.mem.asBytes(&id_extra));
    return hash.final();
  }

  pub fn rectFor(self: Widget, id: u32, opts: Options) Rect {
    return self.vtable.rectFor(self.ptr, id, opts);
  }

  pub fn minSizeForChild(self: Widget, s: Size) void {
    return self.vtable.minSizeForChild(self.ptr, s);
  }

  pub fn screenRectScale(self: Widget, r: Rect) RectScale {
    return self.vtable.screenRectScale(self.ptr, r);
  }

  pub fn bubbleEvent(self: Widget, e: *Event) void {
    return self.vtable.bubbleEvent(self.ptr, e);
  }
};
