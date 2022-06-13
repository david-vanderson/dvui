# Easy to Integrate Immediate Mode GUI for Zig

A [Zig](https://ziglang.org/) native GUI toolkit for whole applications or extra debugging windows in an existing application.

## Contents

- Immediate Mode Interface
- Use for whole UI or for debugging on top of existing application
- Integrate with just a few functions
  - Existing integrations with [Mach](https://machengine.org/) and [SDL](https://libsdl.org/)
- Icon support via [TinyVG](https://tinyvg.tech/)
- Font support via [mach-freetype](https://github.com/hexops/mach-freetype/)
- Support for:
  - Animations
  - Themes
  - FPS throttling

## Building

### As a standalone Mach app

```
git clone https://github.com/david-vanderson/gui.git
cd gui
git submodule add https://github.com/hexops/mach libs/mach
git submodule add https://github.com/hexops/mach-freetype libs/mach-freetype
git submodule add https://github.com/PiergiorgioZagaria/zmath.git libs/zmath
zig build run-mach-gui-test
```

### On top of an existing Mach app

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
