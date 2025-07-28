# DVUI - Immediate Zig GUI for Apps and Games

[Homepage](https://david-vanderson.github.io) A Zig GUI toolkit for whole applications or extra debugging windows in an existing application.

Tested with [Zig](https://ziglang.org/) 0.14 (use tag v0.2.0 for zig 0.13)

How to run the built-in examples:

- SDL2
  - ```zig build sdl2-standalone```
  - ```zig build sdl2-ontop```
  - ```zig build sdl2-app```
- SDL3
  - ```zig build sdl3-standalone```
  - ```zig build sdl3-ontop```  
  - ```zig build sdl3-app```
- Raylib
  - if you encounter error `No Wayland` also add flag `-Dlinux_display_backend=X11`
  - ```zig build raylib-standalone```
  - ```zig build raylib-ontop```
  - ```zig build raylib-app```
- Dx11
  - ```zig build dx11-standalone```
  - ```zig build dx11-ontop```
  - ```zig build dx11-app```
- Web
  - to load web examples you need so serve the files through a local web server
    - `python -m http.server -d zig-out/bin/EXAMPLE_NAME`
    - `caddy file-server --root zig-out/bin/EXAMPLE_NAME --listen :8000`
  - ```zig build web-test```
    - then load `zig-out/bin/web-test/index.html`
  - ```zig build web-app```
    - then load `zig-out/bin/web-app/index.html`
    - [online demo](https://david-vanderson.github.io/demo)
- Docs
  - [Online Docs](https://david-vanderson.github.io/docs)
  - ```zig build docs```
    - then load `zig-out/docs/index.html`
  - ```zig build docs -Dgenerate-images```
    - adds images to the docs

This document is a broad overview.  See [implementation details](readme-implementation.md) for how to write and modify container widgets.

Online discussion happens in #gui-dev on the zig discord server: https://discord.gg/eJgXXTtVzA or in IRC (Libera) channel #dvui

Below is a screenshot of the demo window, whose source code can be found at `src/Examples.zig`.

![Screenshot of DVUI Standalone Example (Application Window)](/screenshot_demo.png?raw=true)

### Projects using DVUI

* [Graphl Visual Programming Language](https://github.com/MichaelBelousov/graphl) - [Demo](https://graphl.tech/graphl/demo/)
* [Podcast Player](https://github.com/david-vanderson/podcast)
* [Graphical Janet REPL](https://codeberg.org/iacore/janet-graphical-repl)
* [FIDO2/ Passkey compatible authenticator implementation for Linux](https://github.com/r4gus/keypass)
* [QEMU frontend](https://github.com/AnErrupTion/ZigEmu)
* [Static site generator GUI](https://github.com/nhanb/webmaker2000)
* [File explorer for Altair 8800 disk images](https://github.com/phatchman/altair_tools) - use the experimental branch.
* [Kanji flashcard app](https://codeberg.org/tensorush/origa)

## Features

- Immediate Mode Interface
- Process every input event (suitable for low-fps situations)
- Use for whole UI or for debugging on top of existing application
- Existing backends
  - [SDL2 and SDL3](https://libsdl.org/)
  - [Web](https://david-vanderson.github.io/demo)
  - [Raylib](https://www.raylib.com/)
  - [Dx11](https://learn.microsoft.com/en-us/windows/win32/direct3d11/atoc-dx-graphics-direct3d-11)
- [TinyVG](https://tinyvg.tech/) icon support via [zig-lib-svg2tvg](https://github.com/nat3Github/zig-lib-svg2tvg)
  - more icons at [zig-lib-icons](https://github.com/nat3Github/zig-lib-icons)
- Raster image support via [stb_image](https://github.com/nothings/stb)
- Font support
  - [freetype](https://github.com/david-vanderson/freetype/tree/zig-pkg)
  - [stb_truetype](https://github.com/nothings/stb)
- Touch support
  - selection draggables in text entries
  - pinch-zoom scaling
- Native file dialogs via [tinyfiledialogs](https://sourceforge.net/projects/tinyfiledialogs)
- Animations
- Themes
- FPS throttling

## Getting Started

[DVUI Demo](https://github.com/david-vanderson/dvui-demo) is a template project you can use as a starting point.
- build.zig and build.zig.zon show how to reference dvui as a zig dependency
- for applications, you can use the dvui.App layer to have dvui manage the mainloop for you

Important Tips:
* Use the debug window (`dvui.toggleDebugWindow()`)
* Read the [devlog](https://david-vanderson.github.io/log)
  * Especially about [units](https://david-vanderson.github.io/log/2025/#2025-05-12)

## Built-in Widgets

  - Text Entry (single and multiline)
    - Includes touch support (selection draggables and menu)
  - Number Entry
    - Supports all Integer and Floating Point types
  - Text Layout
    - Parts can be clickable
    - Parts separately styled
  - Floating Window
  - Menu
  - Popup/Context Window
  - Scroll Area
  - Button
  - Multi-line label
    - Can be clickable for links
  - Tooltips
  - Slider
  - SliderEntry
    - Combo slider and text entry
  - Checkbox
  - Radio Buttons
  - Toast
  - Panes with draggable sash
  - Dropdown
  - Combo Box
  - Reorderable Lists
    - Drag to reorder/remove/add
  - Data Grid
- Missing Widgets for now
  - Docking

## Design

### Immediate Mode
```zig
if (dvui.button(@src(), "Ok", .{}, .{})) {
  dialog.close();
}
```
Widgets are not stored between frames like in traditional gui toolkits (gtk, win32, cocoa).  `dvui.button()` processes input events, draws the button on the screen, and returns true if a button click happened this frame.

For an intro to immediate mode guis, see: https://github.com/ocornut/imgui/wiki#about-the-imgui-paradigm

#### Advantages
* Reduce widget state
  * example: checkbox directly uses your app's bool
* Reduce gui state
  * the widgets shown each frame directly reflect the code run each frame
  * harder to be in a state where the gui is showing one thing but the app thinks it's showing something else
  * don't have to clean up widgets that aren't needed anymore
* Functions are the composable building blocks of the gui
  * since running a widget is a function, you can wrap a widget easily
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
* Hard to do fire-and-forget
  * example: show a dialog with an error message from code that won't be run next frame
  * dvui includes a retained mode space for dialogs and toasts for this
* Hard to do dialog sequence
  * retained mode guis can run a modal dialog recursively so that dialog code can only exist in a single function
  * dvui retained dialogs can be chained together for this

### Handle All Events
DVUI processes every input event, making it useable in low framerate situations.  A button can receive a mouse-down event and a mouse-up event in the same frame and correctly report a click.  A custom button could even report multiple clicks per frame.  (the higher level `dvui.button()` function only reports 1 click per frame)

In the same frame these can all happen:
- text entry field A receives text events
- text entry field A receives a tab that moves keyboard focus to field B
- text entry field B receives more text events

Because everything is in a single pass, this works in the normal case where widget A is run before widget B.  It doesn't work in the opposite order (widget B receives a tab that moves focus to A) because A ran before it got focus.

### Floating Windows
This library can be used in 2 ways:
- as the gui for the whole application, drawing over the entire OS window
- as floating windows on top of an existing application with minimal changes:
  - use widgets only inside `dvui.floatingWindow()` calls
  - `dvui.Window.addEvent...` functions return false if event won't be handled by dvui (main application should handle it)
  - change `dvui.Window.cursorRequested()` to `dvui.Window.cursorRequestedFloating()` which returns null if the mouse cursor should be set by the main application

Floating windows and popups are handled by deferring their rendering so that they render properly on top of windows below them.  Rendering of all floating windows and popups happens during `dvui.Window.end()`.

### FPS throttling
If your app is running at a fixed framerate, use `dvui.Window.begin()` and `dvui.Window.end()` which handle bookkeeping and rendering.

If you want dvui to handle the mainloop for you, use `dvui.App`.

If you want to only render frames when needed, add `dvui.Window.beginWait()` at the start and `dvui.Window.waitTime()` at the end.  These cooperate to sleep the right amount and render frames when:
- an event comes in
- an animation is ongoing
- a timer has expired
- gui code calls `dvui.refresh(null, ...)` (if your code knows you need a frame after the current one)
- a background thread calls `dvui.refresh(window, ...)` which in turn calls `backend.refresh()`

`dvui.Window.waitTime()` also accepts a max fps parameter which will ensure the framerate stays below the given value.

`dvui.Window.beginWait()` and `dvui.Window.waitTime()` maintain an internal estimate of how much time is spent outside of the rendering code.  This is used in the calculation for how long to sleep for the next frame.

The estimate is visible in the demo window Animations > Clock > "Estimate of frame overhead".  The estimate is only updated on frames caused by a timer expiring (like the clock example), and it starts at 1ms.

### Widget init and deinit
The easiest way to use widgets is through the high-level functions that create and install them:
```zig
{
    var box = dvui.box(@src(), .{}, .{.expand = .both});
    defer box.deinit();

    // widgets run here will be children of box
}
```
These functions allocate memory for the widget onto an internal arena allocator that is flushed each frame.

Instead you can allocate the widget on the stack using the lower-level functions:
```zig
{
    var box = BoxWidget.init(@src(), .{}, .{.expand = .both});
    // box now has an id, can look up animations/timers

    box.install();
    // box is now parent widget

    box.drawBackground();
    // might draw the background in a different way

    defer box.deinit();

    // widgets run here will be children of box
}
```
The lower-level functions give a lot more customization options including animations, intercepting events, and drawing differently.

Start with the high-level functions, and when needed, copy the body of the high-level function and customize from there.

### Parent, Child, and Layout
The primary layout mechanism is nesting widgets.  DVUI keeps track of the current parent widget.  When a widget runs, it is a child of the current parent.  A widget may then make itself the current parent, and reset back to the previous parent when it runs `deinit()`.

The parent widget decides what rectangle of the screen to assign to each child, unless the child passes `.rect = ` in their `dvui.Options`.

Usually you want each part of a gui to either be packed tightly (take up only min size), or expand to take the available space.  The choice might be different for vertical vs. horizontal.

When a child widget is laid out (sized and positioned), it sends 2 pieces of info to the parent:
- min size
- hints for when space is larger than min size (expand, gravity_x, gravity_y)

If parent is not `expand`ed, the intent is to pack as tightly as possible, so it will give all children only their min size.

If parent has more space than the children need, it will lay them out using the hints:
- expand - whether this child should take more space or not
- gravity - if not expanded, where to position child in larger space

### Appearance
Each widget has the following options that can be changed through the Options struct when creating the widget:
- margin (space outside border)
- border (on each side)
- padding (space inside border)
- min_size_content (margin/border/padding added to get min size)
- max_size_content (margin/border/padding added to get maximum min size)
- background (fills space inside border with background color)
- corner_radius (for each corner)
- box_shadow
- colors (either RGBA value or named)
  - example RGBA `.color_text = .{ .color = .{ .r = 0xe0, .g = 0x1b, .b = 0x24 } }`
  - example HEX `.color_text = .fromHex("#e01b24")`
  - example named `.color_text = .err` (get current theme's `color_err`)
  - color_accent
  - color_text
  - color_text_press
  - color_fill
  - color_fill_hover
  - color_fill_press
  - color_border
- font_style (use theme's fonts)
  - or directly set font:
    - font

Each widget has its own default options.  These can be changed directly:
```zig
dvui.ButtonWidget.defaults.background = false;
```

Themes can be changed between frames or even within a frame.  The theme controls the fonts and colors referenced by font_style and named colors.
```zig
if (theme_dark) {
    win.theme = dvui.Theme.builtin.adwaita_dark;
} else {
    win.theme = dvui.Theme.builtin.adwaita_light;
}
```
The theme's color_accent is also used to show keyboard focus.

The default theme will attempt to follow the system dark or light mode, or it can be set in the `Window` init options or by setting the `Window.theme` field directly. See the app and standalone examples for how to set the default theme. 

See [implementation details](readme-implementation.md) for more information.
