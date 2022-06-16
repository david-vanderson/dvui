# Easy to Integrate Immediate Mode GUI for Zig

A [Zig](https://ziglang.org/) native GUI toolkit for whole applications or extra debugging windows in an existing application.

## Features

- Immediate Mode Interface
- Process every input event (suitable for low-fps situations)
- Use for whole UI or for debugging on top of existing application
- Integrate with just a few functions
  - Existing integrations with [Mach](https://machengine.org/) and [SDL](https://libsdl.org/)
- Icon support via [TinyVG](https://tinyvg.tech/)
- Font support via [mach-freetype](https://github.com/hexops/mach-freetype/)
- Support for:
  - Animations
  - Themes
  - FPS throttling

## Contents

- [Build Standalone Mach App](#standalone-mach-app)
- [Build On Top of Existing Mach App](#on-top-of-existing-mach-app)
- [Design](#Design)

## Building

### Standalone Mach App

```
git clone https://github.com/david-vanderson/gui.git
cd gui
git submodule add https://github.com/hexops/mach libs/mach
git submodule add https://github.com/hexops/mach-freetype libs/mach-freetype
git submodule add https://github.com/PiergiorgioZagaria/zmath.git libs/zmath
zig build run-mach-test
```

### On Top of Existing Mach App

As an example, we'll extend the mach example `instanced-cube`.

Link or copy this repo into the example:
```
cd mach/examples/instanced-cube
ln -s ~/gui gui
```

Add the necessary packages to the example (need zmath and freetype):
```
git diff ../../build.zig
-        .{ .name = "instanced-cube", .packages = &[_]Pkg{Packages.zmath} },
+        .{ .name = "instanced-cube", .packages = &[_]Pkg{Packages.zmath, freetype.pkg } },
```

Add the following to the example:
```
git diff main.zig
diff --git a/examples/instanced-cube/main.zig b/examples/instanced-cube/main.zig
index 1f17475..e1b6450 100755
--- a/examples/instanced-cube/main.zig
+++ b/examples/instanced-cube/main.zig
@@ -6,10 +6,16 @@ const zm = @import("zmath");
 const Vertex = @import("cube_mesh.zig").Vertex;
 const vertices = @import("cube_mesh.zig").vertices;

+const gui = @import("gui/src/gui.zig");
+const MachGuiBackend = @import("gui/src/MachBackend.zig");
+
 const UniformBufferObject = struct {
     mat: zm.Mat,
 };

+var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
+const gpa = gpa_instance.allocator();
+
 var timer: mach.Timer = undefined;

 pipeline: gpu.RenderPipeline,
@@ -18,6 +24,10 @@ vertex_buffer: gpu.Buffer,
 uniform_buffer: gpu.Buffer,
 bind_group: gpu.BindGroup,

+win: gui.Window,
+win_backend: MachGuiBackend,
+shown_instances: u32,
+
 const App = @This();

 pub fn init(app: *App, engine: *mach.Engine) !void {
@@ -131,16 +141,31 @@ pub fn init(app: *App, engine: *mach.Engine) !void {
     fs_module.release();
     pipeline_layout.release();
     bgl.release();
+
+    app.win_backend = try MachGuiBackend.init(gpa, engine);
+    app.win = gui.Window.init(gpa, app.win_backend.guiBackend());
+    app.shown_instances = 12;
 }

 pub fn deinit(app: *App, _: *mach.Engine) void {
     app.vertex_buffer.release();
     app.bind_group.release();
     app.uniform_buffer.release();
+
+    app.win.deinit();
+    app.win_backend.deinit();
 }

 pub fn update(app: *App, engine: *mach.Engine) !void {
+
+    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
+    const arena = arena_allocator.allocator();
+    defer arena_allocator.deinit();
+
+    app.win.begin(arena, std.time.nanoTimestamp());
+
     while (engine.pollEvent()) |event| {
+        _ = app.win_backend.addEvent(&app.win, event);
         switch (event) {
             .key_press => |ev| {
                 if (ev.key == .space)
@@ -150,6 +175,26 @@ pub fn update(app: *App, engine: *mach.Engine) !void {
         }
     }

+    {
+        var fw = gui.FloatingWindow(@src(), 0, false, null, null, .{});
+        defer fw.deinit();
+
+        var box = gui.Box(@src(), 0, .horizontal, .{});
+        defer box.deinit();
+
+        if (gui.Button(@src(), 0, "more", .{})) {
+            if (app.shown_instances < 16) {
+                app.shown_instances += 1;
+            }
+        }
+
+        if (gui.Button(@src(), 0, "less", .{})) {
+            if (app.shown_instances > 0) {
+                app.shown_instances -= 1;
+            }
+        }
+    }
+
     const back_buffer_view = engine.swap_chain.?.getCurrentTextureView();
     const color_attachment = gpu.RenderPassColorAttachment{
         .view = back_buffer_view,
@@ -198,7 +243,7 @@ pub fn update(app: *App, engine: *mach.Engine) !void {
     pass.setPipeline(app.pipeline);
     pass.setVertexBuffer(0, app.vertex_buffer, 0, @sizeOf(Vertex) * vertices.len);
     pass.setBindGroup(0, app.bind_group, &.{0});
-    pass.draw(vertices.len, 16, 0, 0);
+    pass.draw(vertices.len, app.shown_instances, 0, 0);
     pass.end();
     pass.release();

@@ -207,6 +252,9 @@ pub fn update(app: *App, engine: *mach.Engine) !void {

     app.queue.submit(&.{command});
     command.release();
+
+    _ = app.win.end();
+
     engine.swap_chain.?.present();
     back_buffer_view.release();
 }
```

## Design

### Immediate Mode
```
if (gui.Button(@src(), 0, "Ok", .{})) {
  dialog.close();
}
```
Widgets are not stored between frames like in traditional gui toolkits (gtk, win32, cocoa).  `gui.Button()` processes input events, draws the button on the screen, and returns true if a button click happened this frame.

### Widget Ids
Each widget gets a `u32` id by combining:
- parent's id
- @src() passed to widget
- extra `usize` passed to widget for loops

The extra `usize` is to differentiate many children being added to the same parent in a loop.

### Single Pass
Widgets handle events and draw themselves in install().  This is before they know of any child widgets, so some information is stored from last frame about minimum sizes.

A new widget will typically receive a zero-sized rectangle, draw nothing on the first frame, and draw normally on the second frame.  For smooth UIs a new widget can be animated from zero-sized to normal size.

Between a widget's `install()` and `deinit()`, that widget becomes the parent to any widgets run between.  Each widget maintains a pointer to their parent, used for getting the screen rectangle for the child, and for key event propogation.

### Drawing
All drawing happens in pixel space.  A widget receives a rectangle from their parent in their parent's coordinate system.  They then call `parent.screenRectScale(rect)` to get their rectangle in pixel screen coordinates plus the scale value in pixels per rect unit.

This provides scaling (see `ScaleWidget`) while looking sharp, because nothing is being drawn and then scaled.

### Handle All Events
This library processes every input event, making it useable in low framerate situations.  A button can receive a mouse-down event and a mouse-up event in the same frame and correctly report a click.  A custom button can even report multiple clicks per frame.  (the higher level `gui.Button()` function only reports 1 click per frame)

In the same frame these can all happen:
- text entry field A receives text events
- text entry field A receives a tab that moves keyboard focus to field B
- text entry field B receives more text events

Because everything is in a single pass, this works in the normal case where widget A is `install()`ed before widget B.  If keyboard focus moves to a previously installed widget, it can't process further key events this frame.

### Event Propogation
`gui.EventIterator` helps widgets process events.  It takes the widget id (for focus and mouse capture) and a rect (for mouse events).

For mouse events, `EventIterator` checks if the widget has mouse capture, or if the mouse event is within the given rect (and within the current clipping rect).  Mouse events can also be handled in a widget's `deinit()` if child widgets should get priority.  For example, `FloatingWindow.deinit()` handles remaining mouse events to allow click-dragging of floating windows anywhere a child widget doesn't handle the events.

For key events, `EventIterator` checks if the widget has focus and the current floating window has focus.  `EventIterator.nextCleanup()` can be used to catch key events not processed by child widgets.  For example, `FloatingWindow.deinit()` handles remaining key events to catch a tab if no widget had focus in the window.

Key events are also bubbled up to parent widgets if the child doesn't process them.  That is how `ScrollArea` can catch up/down key events and scroll even when it doesn't have focus.

### Floating Windows
This library can be used in 2 ways:
- as the gui for the whole application, drawing over the entire OS window
- as floating windows on top of an existing application with minimal changes:
  - use widgets only inside `gui.FloatingWindow()` calls
  - `gui.addEvent...` functions return false if event won't be handled by gui (main application should handle it)
  - change `gui.CursorRequested()` to `gui.CursorRequestedFloating()` which returns null if the mouse cursor should be set by the main application

Floating windows and popups are handled by deferring their rendering so that they render properly on top of windows below them.  Rendering of all floating windows and popups happens during `window.end()`.

### FPS throttling
If your app is running at a fixed framerate, use `window.begin()` and `window.end()` which handle bookkeeping and rendering.

If you want to only render frames when needed, add `window.beginWait()` at the start and `window.wait()` at the end.  These cooperate to sleep the right amount and render frames when:
- an event comes in
- an animation is ongoing
- a timer has expired
- user code calls `gui.CueFrame()` (if your code knows you need a frame after the current one)

`window.wait()` also accepts a max fps parameter which will ensure the framerate stays below the given value.

`window.beginWait()` and `window.wait()` maintain an internal estimate of how much time is spent outside of the rendering code.  This is used in the calculation for how long to sleep for the next frame.

### Widget init and deinit
The easiest way to use widgets is through the functions that create and install them:
```
{
    var box = gui.Box(@src(), 0, .vertical, .{.expand = .both});
    defer box.deinit();
}
```
These functions allocate memory for the widget onto the arena allocator passed to `window.begin()`.

Instead you can allocate the widget on the stack:
```
{
    var box = BoxWidget.init(@src(), 0, .vertical, .{.expand = .both});
    // box now has an id, can look up animations/timers
    box.install();
    defer box.deinit();
}
```
This is also shows how to get a widget's id before install() (processes events and draws).  This is primarily used for animations.

### Appearance
Each widget has the following options that can be changed through the Options struct when creating the widget:
- margin (space oustide border)
- border (on each side)
- background (fills space inside border with background color)
- padding (space inside border)
- corner radius (for each corner)
- color_style (use theme's colors)
- color_custom/color_custom_bg (used if color_style is .custom)
- font_style (use theme's fonts)
- font_custom (used if font_style is .custom)
```
if (gui.Button(@src(), 0, "Wild", .{
    .margin = gui.Rect.All(2),
    .padding = gui.Rect.all(8),
    .color_style = .custom,
    .color_custom = gui.Color{.r = 255, .g = 0, .b = 0, .a = 255},
    .color_custom_bg = gui.Color{.r = 255, .g = 0, .b = 255, .a = 255},
    })) {
    // clicked
}
```

Each widget has it's own default options.  These can be changed directly:
```
gui.ButtonWidget.Defaults.background = false;
```

Colors come in foreground/background pairs.  Usually you want to use colors from the theme:
```
if (gui.MenuItemLabel(@src(), 0, "Cut", false, .{.color_style = .warning, .background = true}) != null) {
    // selected
}
```

Themes can be changed freely, and control the fonts and colors referenced by font_style and color_style.
```
if (theme_dark) {
    win.theme = &gui.Theme_Adwaita_Dark;
}
else {
    win.theme = &gui.Theme_Adwaita;
}
```
The current theme's color_accent is also used to show keyboard focus.

### Layout
A widget receives it's position rectangle from the parent, but can influence layout with Options:
- `.expand` - whether to take up all the space available (horizontal or vertical)
- `.gravity` - position a non-expanded widget inside a larger rectangle
- `.min_size` - get at least this much space (unless parent is unable)
- `.rect` - rarely used to directly specify position in parent

