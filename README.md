# DVUI — Immediate Zig GUI for Apps and Games

[Zig](https://ziglang.org) GUI toolkit for whole applications or debugging windows in existing apps/games.

Tested with Zig v0.15.2 (for Zig v0.14.1, use DVUI [tag v0.3.0](https://github.com/david-vanderson/dvui/releases/tag/v0.3.0)).

[Homepage](https://david-vanderson.github.io) · [Demo](https://david-vanderson.github.io/demo) · [Docs](https://david-vanderson.github.io/docs/) · [Devlog](https://david-vanderson.github.io/log/2026)

![Screenshot of DVUI Standalone Example (Application Window)](/screenshot_demo.png?raw=true)

## Examples

`zig build sdl3-app`
* sdl3 backend, dvui handles mainloop
* good place to start, try changing <code>frame()</code> inside <code>./examples/app.zig</code>
* see [Getting Started](#getting-started)

<table>
  <thead>
    <tr>
      <th>Backend</th>
      <th>
        As app
        <br>
        <sub>
          dvui handles main loop
          <br>
          <a href="https://github.com/david-vanderson/dvui/blob/main/examples/app.zig"><code>app.zig</code></a>
        </sub>
      </th>
      <th>
        Standalone
        <br>
        <sub>
          you control main loop
          <br>
          <a href="https://github.com/david-vanderson/dvui/blob/main/examples"><code>*-standalone.zig</code></a>
        </sub>
      </th>
      <th>
        On top
        <br>
        <sub>
          debug HUD on existing app/game
          <br>
          <a href="https://github.com/david-vanderson/dvui/blob/main/examples"><code>*-ontop.zig</code></a>
        </sub>
      </th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><strong>SDL3</strong></td>
      <td><code>sdl3-app</code></td>
      <td><code>sdl3-standalone</code></td>
      <td><code>sdl3-ontop</code></td>
    </tr>
    <tr>
      <td>
        <strong>SDL3GPU</strong>
        <br>
        <sub>Rendering via SDL GPU</sub>
      </td>
      <td>todo</td>
      <td><code>sdl3gpu-standalone</code></td>
      <td><code>sdl3gpu-ontop</code></td>
    </tr>
    <tr>
      <td><strong>SDL2</strong></td>
      <td><code>sdl2-app</code></td>
      <td><code>sdl2-standalone</code></td>
      <td><code>sdl2-ontop</code></td>
    </tr>
    <tr>
      <td>
        <strong>Raylib</strong>
        <br>
        <sub>C API</sub>
      </td>
      <td><code>raylib-app</code></td>
      <td><code>raylib-standalone</code></td>
      <td><code>raylib-ontop</code></td>
    </tr>
    <tr>
      <td>
        <strong>Raylib</strong>
        <br>
        <sub>Bindings <a href="https://github.com/raylib-zig/raylib-zig"><code>raylib-zig</code></a></sub>
      </td>
      <td><code>raylib-zig-app</code></td>
      <td><code>raylib-zig-standalone</code></td>
      <td><code>raylib-zig-ontop</code></td>
    </tr>
    <tr>
      <td><strong>DX11</strong></td>
      <td><code>dx11-app</code></td>
      <td><code>dx11-standalone</code></td>
      <td><code>dx11-ontop</code></td>
    </tr>
    <tr>
      <td><strong>Web</strong></td>
      <td><code>web-app</code></td>
      <td>none</td>
      <td>none</td>
    </tr>
  </tbody>
</table>

[`dvui-demo`](https://github.com/david-vanderson/dvui-demo/) is a template repository that also includes these examples.  See [Getting Started](#getting-started).

### Docs

- `zig build docs -Dgenerate-images`
- Load `./zig-out/docs/index.html`
- [Online Docs](https://david-vanderson.github.io/docs/)

### Troubleshooting Raylib
- If you encounter error `No Wayland`, then also add flag `-Dlinux_display_backend=X11`

### Troubleshooting Web
- To load examples for this backend, they must first be served through a (local) web server using:
  - Python `python -m http.server -d ./zig-out/bin/web-app`
  - Caddy `caddy file-server --root ./zig-out/bin/web-app --listen :8000`
  - Any other web server
- Outputs are stored in `./zig-out/bin/web-app/`

## Featured Projects

The following projects use DVUI:
- [Graphl Visual Programming Language Demo](https://graphl.tech/graphl/demo/)
- [Podcast Player](https://github.com/david-vanderson/podcast)
- [Graphical Janet REPL](https://codeberg.org/iacore/janet-graphical-repl)
- [FIDO2/ Passkey compatible authenticator implementation for Linux](https://github.com/r4gus/keypass)
- [QEMU frontend](https://github.com/AnErrupTion/ZigEmu)
- [Static site generator GUI](https://github.com/nhanb/webmaker2000)
- [File explorer for Altair 8800 disk images](https://github.com/phatchman/altair_tools)
- [Kanji flashcard app](https://codeberg.org/tensorush/origa)
- [Azem - WIP micro-mouse simulator / maze solver](https://github.com/thuvasooriya/azem) - [Demo](https://www.thuvasooriya.me/azem/)
- [Pixi - Pixel art editor](https://github.com/foxnne/pixi)

Discuss yours on:
- Zig Discord [`#gui-dev`](https://discord.gg/eJgXXTtVzA)
- Zig Libera IRC `#dvui`
- [DVUI GitHub Discussions](https://github.com/david-vanderson/dvui/discussions)

## Feature Overview

- [Immediate-mode API](https://en.wikipedia.org/wiki/Immediate_mode_(computer_graphics)):
  - see [Design](#Design)
- Processs every input event
  - suitable for low frame rate situations
- Appropriate for
  - whole UI (`*-app` examples)
  - debugging on top of existing application
  - see [Ontop-Floating-Windows](#Ontop-Floating-Windows)
- Backends
  - [SDL2 and SDL3](https://libsdl.org/)
  - [Web](https://david-vanderson.github.io/demo)
  - [Raylib (C)](https://www.raylib.com/)
  - [Raylib (Zig)](https://github.com/raylib-zig/raylib-zig)
  - [DX11](https://learn.microsoft.com/en-us/windows/win32/direct3d11/atoc-dx-graphics-direct3d-11)
  - [OpenGL + GLFW](https://www.glfw.org/)
- [TinyVG](https://tinyvg.tech/) icons
  - [`zig-lib-svg2tvg`](https://github.com/nat3Github/zig-lib-svg2tvg)
  - more icons at [`zig-lib-icons`](https://github.com/nat3Github/zig-lib-icons)
- Raster images
  - [`stb_image`](https://github.com/nothings/stb)
- Fonts
  - [FreeType](https://github.com/david-vanderson/freetype/tree/zig-pkg)
  - [`stb_truetype`](https://github.com/nothings/stb)
- Touch
  - selection draggables in text entries
  - pinch-zoom scaling
- Accessibility:
  - [AccessKit](https://accesskit.dev/), enabled by adding flag `-Daccesskit` to `zig build`
  - see [Accessibility](#Accessibility)
- Native file dialogs
  - [`tinyfiledialogs`](https://sourceforge.net/projects/tinyfiledialogs)
- Animations
- Themes
- FPS throttling
  - see [FPS-Throttling](#FPS-Throttling)

Further reading:
- Implementation details for how to write and modify container widgets:
  - [`readme-implementation.md`](readme-implementation.md)

## [Getting Started](#getting-started)

[`dvui-demo`](https://github.com/david-vanderson/dvui-demo/) is a template repository
* `build.zig` and `build.zig.zon` reference dvui as a zig dependency
* includes all the examples

Alternatively:
1. Add DVUI as a dependency:
   ```
   zig fetch --save git+https://github.com/david-vanderson/dvui#main
   ```
2. Add `build.zig` logic (here using SDL3 backend):
   ```zig
   const dvui_dep = b.dependency("dvui", .{ .target = target, .optimize = optimize, .backend = .sdl3 });
   exe.root_module.addImport("dvui", dvui_dep.module("dvui_sdl3"));
   ```

Further reading:
- Using a version of `raylib-zig` that's not bundled with DVUI:
  - [`readme-raylib-zig-custom.md`](readme-raylib-zig-custom.md)

## Frequently Asked Questions

<!-- TODO due to use of HTML, syntax highlighting is disabled here -->

<details>
<summary>How can I enable LSP autocompletion for DVUI?</summary>
For <a href="https://zigtools.org/zls/install/">ZLS autocomplete</a> to work on DVUI's backend, you must import the latter directly:
<ol>
  <li>
    In `build.zig` (here using the SDL3 backend):
    <pre><code>exe.root_module.addImport("sdl-backend", dvui_dep.module("sdl3"));</code></pre>
  </li>
  <li>
    Then in your code:
    <pre><code>const SDLBackend = @import("sdl-backend");</code></pre>
  </li>
</ol>
</details>

<details>
<summary>How to debug DVUI?</summary>
Use the debug window <code>dvui.toggleDebugWindow()</code>. Its preview is available as a <code>Debug Window</code> button on the front page of the online demo.
</details>

<details>
<summary>Where to receive updates on new DVUI features?</summary>
Read the <a href="https://david-vanderson.github.io/log">DVUI Devlog</a> which also covers topics such as <a href="https://david-vanderson.github.io/log/2025/#2025-05-12">units in DVUI</a>. Subscribing to its RSS feed is possible.
</details>

## Built-in Widgets

Widgets implemented so far:
- Text entry:
  - Single- and multi-line
  - Includes touch support (selection draggables and menu)
- Number entry:
  - Supports all Integer and floating point types
- Text layout:
  - Parts can be clickable
  - Parts separately styled
- Floating window
- Menu
- Popup/context window
- Scroll Area
- Button
- Multi-line label:
  - Can be clickable for links
- Tooltips
- Slider
- Slider entry:
  - Combo slider and text entry
- Checkbox
- Radio buttons
- Toast
- Panes with draggable sash
- Dropdown
- Combo box
- Reorderable lists:
  - Drag to reorder/remove/add
- Data grid
- Group box (fieldset)

Widgets to be implemented:
- Docking

## Design

### Immediate Mode

Widgets are not stored between frames like in traditional GUI toolkits (GTK, Win32, Cocoa). In the example below, `dvui.button()` processes input events, draws the button on the screen, and returns true if a button click happened this frame:

```zig
if (dvui.button(@src(), "Ok", .{}, .{})) {
    dialog.close();
}
```

For an intro to immediate-mode GUIs (IMGUIs), see [this respective section from Dear ImGui](https://github.com/ocornut/imgui/wiki#about-the-imgui-paradigm).

#### Advantages
- Reducing widget state
  - For example, a checkbox which directly uses your app's bool
- Reducing GUI state
  - The widgets shown each frame directly reflect the code run each frame
  - Harder to be in a state where the GUI is showing one thing but the app thinks it's showing something else
  - Don't have to clean up widgets that aren't needed anymore
- Functions are the composable building blocks of the GUI
  - Since running a widget is a function, you can wrap a widget easily:
    ```zig
    // Let's wrap the sliderEntry widget so we have 3 that represent a Color
    pub fn colorSliders(src: std.builtin.SourceLocation, color: *dvui.Color, opts: Options) void {
        var hbox = dvui.box(src, .{ .dir = .horizontal }, opts);
        defer hbox.deinit();

        var red: f32 = @floatFromInt(color.r);
        var green: f32 = @floatFromInt(color.g);
        var blue: f32 = @floatFromInt(color.b);

        _ = dvui.sliderEntry(@src(), "R: {d:0.0}", .{ .value = &red, .min = 0, .max = 255, .interval = 1 }, .{ .gravity_y = 0.5 });
        _ = dvui.sliderEntry(@src(), "G: {d:0.0}", .{ .value = &green, .min = 0, .max = 255, .interval = 1 }, .{ .gravity_y = 0.5 });
        _ = dvui.sliderEntry(@src(), "B: {d:0.0}", .{ .value = &blue, .min = 0, .max = 255, .interval = 1 }, .{ .gravity_y = 0.5 });

        color.r = @intFromFloat(red);
        color.g = @intFromFloat(green);
        color.b = @intFromFloat(blue);
    }
    ```

#### Drawbacks
- Hard to do fire-and-forget
  - For example, showing a dialog with an error message from code that won't be run next frame
  - DVUI includes a retained mode space for dialogs and toasts for this
- Hard to do dialog sequence
  - Retained mode GUIs can run a modal dialog recursively so that dialog code can only exist in a single function
  - DVUI's retained dialogs can be chained together for this

### Handling All Events

DVUI processes every input event, making it useable in low frame rate situations. A button can receive a mouse-down event and a mouse-up event in the same frame and correctly report a click. A custom button could even report multiple clicks per frame (the higher level `dvui.button()` function only reports 1 click per frame).

In the same frame, these can all happen:
- Text entry field A receives text events
- Text entry field A receives a tab that moves keyboard focus to field B
- Text entry field B receives more text events

Because everything is in a single pass, this works in the normal case where widget A is run before widget B.  It doesn't work in the opposite order (widget B receives a tab that moves focus to A) because A ran before it got focus.

### Ontop-Floating-Windows

This library can be used in 2 ways:
- As the GUI for the whole application, drawing over the entire OS window
- As floating windows on top of an existing application with minimal changes:
  - Use widgets only inside `dvui.floatingWindow()` calls
  - The `dvui.Window.addEvent...` functions return `false` if event won't be handled by DVUI (the main application should handle it)
  - Change `dvui.Window.cursorRequested()` to `dvui.Window.cursorRequestedFloating()` which returns `null` if the mouse cursor should be set by the main application

Floating windows and popups are handled by deferring their rendering so that they render properly on top of windows below them. Rendering of all floating windows and popups happens during `dvui.Window.end()`.

### FPS-Throttling

If your app is running at a fixed framerate, use `dvui.Window.begin()` and `dvui.Window.end()` which handle bookkeeping and rendering.

If you want dvui to handle the mainloop for you, use `dvui.App`.

If you want to only render frames when needed, add `dvui.Window.beginWait()` at the start and `dvui.Window.waitTime()` at the end. These cooperate to sleep the right amount and render frames when:
- An event comes in
- An animation is ongoing
- A timer has expired
- GUI code calls `dvui.refresh(null, ...)` (if your code knows you need a frame after the current one)
- A background thread calls `dvui.refresh(window, ...)` which in turn calls `backend.refresh()`

`dvui.Window.waitTime()` also accepts a maximum FPS parameter which will ensure the frame rate stays below the given value.

`dvui.Window.beginWait()` and `dvui.Window.waitTime()` maintain an internal estimate of how much time is spent outside of the rendering code. This is used in the calculation for how long to sleep for the next frame.

The estimate is visible in the demo window `Animations > Clock > Estimate of frame overhead`. The estimate is only updated on frames caused by a timer expiring (like the clock example), and it starts at 1 ms.

### Widget `init` and `deinit`

The easiest way to use widgets is through the high-level functions that create them:
```zig
{
    var box = dvui.box(@src(), .{}, .{.expand = .both});
    defer box.deinit();

    // Widgets run here will be children of box
}
```
These functions allocate memory for the widget onto an internal arena allocator that is flushed each frame.

You can instead allocate the widget on the stack using the lower-level functions:
```zig
{
    var box: BoxWidget = undefined;
    box.init(@src(), .{}, .{.expand = .both});
    // Box is now parent widget

    box.drawBackground();
    // Might draw the background in a different way

    defer box.deinit();

    // Widgets run here will be children of box
}
```
The lower-level functions give a lot more customization options including animations, intercepting events, and drawing differently.

Start with the high-level functions, and when needed, copy the body of the high-level function and customize from there.

### Parent, Child, and Layout

The primary layout mechanism is nesting widgets. DVUI keeps track of the current parent widget. When a widget runs, it is a child of the current parent. A widget may then make itself the current parent, and reset back to the previous parent when it runs `deinit()`.

The parent widget decides what rectangle of the screen to assign to each child, unless the child passes `.rect = ` in their `dvui.Options`.

Usually you want each part of a GUI to either be packed tightly (take up only min size), or expand to take the available space. The choice might be different for vertical versus horizontal.

When a child widget is laid out (sized and positioned), it sends 2 pieces of information to the parent:
- Minimum size
- Hints for when space is larger than minimum size (`expand`, `gravity_x`, and `gravity_y`)

If parent is not `expand`ed, the intent is to pack as tightly as possible, so it will give all children only their minimum size.

If parent has more space than the children need, it will lay them out using the hints:
- `expand` — whether this child should take more space or not
- `gravity` — if not `expand`ed, where to position child in larger space

See [readme-implementation](readme-implementation.md) for more information.

### Appearance

Each widget has the following options that can be changed through the `Options` struct when creating the widget:
- `margin` (space outside border)
- `border` (on each side)
- `padding` (space inside border)
- `min_size_content` (margin/border/padding added to get min size)
- `max_size_content` (margin/border/padding added to get maximum min size)
- `background` (fills space inside border with background color)
- `corner_radius` (for each corner)
- `box_shadow`
- `style` (use theme's colors)
- `colors` (directly specify):
  - `color_fill`
  - `color_fill_hover`
  - `color_fill_press`
  - `color_text`
  - `color_text_hover`
  - `color_text_press`
  - `color_border`
- `font` (directly specify):
  - Can reference theme fonts via `Font.theme(.body)` (or `.heading`, `.title`, `.mono`)
- `theme` (use a separate theme altogether)
- `ninepatch_fill` (also `_hover` and `_press`):
  - Draws an image over the background

Each widget has its own default options. These can be changed directly:
```zig
dvui.ButtonWidget.defaults.background = false;
```

Themes can be changed between frames or even within a frame. The theme controls the fonts and colors referenced by `font_style` and named colors:
```zig
if (theme_dark) {
    dvui.themeSet(dvui.Theme.builtin.adwaita_dark);
} else {
    dvui.themeSet(dvui.Theme.builtin.adwaita_light);
}
```

The theme's `focus` color is used to show keyboard focus.

If no theme is passed to `Window.init()` the default theme will attempt to follow the system dark or light mode.

### Accessibility

DVUI has varying support for different kinds of accessibility infrastructure. The current state, including areas commonly tied to accessibility, is:
- Keyboard navigation:
  - Most widgets support keyboard navigation
- Language support:
  - Text rendering is simple left-to-right single glyph for each unicode codepoint
  - Grapheme clusters currently unsupported
  - No right-to-left or mixed text direction
- Language input:
  - IME (input method editor) works in SDL and web backends
- High-contrast themes:
  - DVUI's themes can support this
  - No current OS integration
- Screen reading and alternate input:
  - Uses `Options.role` and `Options.label` from AccessKit integration
  - [AccessKit](https://accesskit.dev/) integration
  - Add `-Daccesskit` to `zig build`

Further reading:
- Track accessibility progress:
  - [`readme-accessibility.md`](readme-accessibility.md)
