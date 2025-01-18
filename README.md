# DVUI - Immediate Zig GUI for Apps and Games

A Zig GUI toolkit for whole applications or extra debugging windows in an existing application.

Tested with [Zig](https://ziglang.org/) 0.13

How to run the built-in examples:

- ```zig build sdl-standalone```
- ```zig build sdl-ontop```
- ```zig build raylib-standalone```
- ```zig build raylib-ontop```
- ```zig build web-test```
  - then load `zig-out/bin/index.html`
  - [online demo](https://david-vanderson.github.io)
- SDL3:
  - ```zig build sdl-standalone -Dsdl3```
  - ```zig build sdl-ontop -Dsdl3```
  - if you encounter error `No Wayland` also add flag `-Dlinux_display_backend=X11`
  

[Online Docs](https://david-vanderson.github.io/docs) This document is a broad overview.  See [implementation details](readme-implementation.md) for how to write and modify widgets.

Online discussion happens in #gui-dev on the zig discord server: https://discord.gg/426ZADhs

Below is a screenshot of the demo window, whose source code can be found at `src/Examples.zig`.

![Screenshot of DVUI Standalone Example (Application Window)](/screenshot_demo.png?raw=true)

### Projects using DVUI

* [Podcast Player](https://github.com/david-vanderson/podcast)
* [Graphical Janet REPL](https://codeberg.org/iacore/janet-graphical-repl)
* [FIDO2/ Passkey compatible authenticator implementation for Linux](https://github.com/r4gus/keypass)
* [QEMU frontend](https://github.com/AnErrupTion/ZigEmu)

## Features

- Immediate Mode Interface
- Process every input event (suitable for low-fps situations)
- Use for whole UI or for debugging on top of existing application
- Existing backends
  - [SDL](https://libsdl.org/)
  - [Web](https://david-vanderson.github.io)
  - [Raylib](https://www.raylib.com/)
  - [Mach](https://machengine.org/)
    - note: Mach backend is currently out of date
- Icon support via [TinyVG](https://tinyvg.tech/)
- Raster image support via [stb_image](https://github.com/nothings/stb)
- Font support
  - [freetype](https://github.com/david-vanderson/freetype/tree/zig-pkg)
  - [stb_truetype](https://github.com/nothings/stb)
- Touch support
  - Including selection draggables in text entries
- Native file dialogs via [tinyfiledialogs](https://sourceforge.net/projects/tinyfiledialogs)
- Animations
- Themes
- FPS throttling

## Usage

[DVUI Demo](https://github.com/david-vanderson/dvui-demo) is a template project you can use as a starting point.

The build.zig and build.zig.zon files there show how to reference dvui as a zig dependency.

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
  - Slider
  - SliderEntry
    - Combo slider and text entry
  - Checkbox
  - Radio Buttons
  - Toast
  - Panes with draggable sash
  - Dropdown
  - Reorderable Lists
    - Drag to reorder/remove/add
- Missing Widgets for now
  - Data Grid
  - Flex Layout
  - Docking

## Design

### Immediate Mode
```zig
if (try dvui.button(@src(), "Ok", .{}, .{})) {
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
pub fn colorSliders(src: std.builtin.SourceLocation, color: *dvui.Color, opts: Options) !void {
    var hbox = try dvui.box(src, .horizontal, opts);
    defer hbox.deinit();

    var red: f32 = @floatFromInt(color.r);
    var green: f32 = @floatFromInt(color.g);
    var blue: f32 = @floatFromInt(color.b);

    _ = try dvui.sliderEntry(@src(), "R: {d:0.0}", .{ .value = &red, .min = 0, .max = 255, .interval = 1 }, .{ .gravity_y = 0.5 });
    _ = try dvui.sliderEntry(@src(), "G: {d:0.0}", .{ .value = &green, .min = 0, .max = 255, .interval = 1 }, .{ .gravity_y = 0.5 });
    _ = try dvui.sliderEntry(@src(), "B: {d:0.0}", .{ .value = &blue, .min = 0, .max = 255, .interval = 1 }, .{ .gravity_y = 0.5 });

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
  - `dvui.addEvent...` functions return false if event won't be handled by dvui (main application should handle it)
  - change `dvui.cursorRequested()` to `dvui.cursorRequestedFloating()` which returns null if the mouse cursor should be set by the main application

Floating windows and popups are handled by deferring their rendering so that they render properly on top of windows below them.  Rendering of all floating windows and popups happens during `window.end()`.

### FPS throttling
If your app is running at a fixed framerate, use `window.begin()` and `window.end()` which handle bookkeeping and rendering.

If you want to only render frames when needed, add `window.beginWait()` at the start and `window.waitTime()` at the end.  These cooperate to sleep the right amount and render frames when:
- an event comes in
- an animation is ongoing
- a timer has expired
- user code calls `dvui.refresh(null, ...)` (if your code knows you need a frame after the current one)
- a background thread calls `dvui.refresh(window, ...)` which in turn calls `backend.refresh()`

`window.waitTime()` also accepts a max fps parameter which will ensure the framerate stays below the given value.

`window.beginWait()` and `window.waitTime()` maintain an internal estimate of how much time is spent outside of the rendering code.  This is used in the calculation for how long to sleep for the next frame.

The estimate is visible in the demo window Animations > Clock > "Estimate of frame overhead".  The estimate is only updated on frames caused by a timer expiring (like the clock example), and it starts at 1ms.

### Widget init and deinit
The easiest way to use widgets is through the high-level functions that create and install them:
```zig
{
    var box = try dvui.box(@src(), .vertical, .{.expand = .both});
    defer box.deinit();

    // widgets run here will be children of box
}
```
These functions allocate memory for the widget onto an internal arena allocator that is flushed each frame.

Instead you can allocate the widget on the stack using the lower-level functions:
```zig
{
    var box = BoxWidget.init(@src(), .vertical, false, .{.expand = .both});
    // box now has an id, can look up animations/timers

    try box.install();
    // box is now parent widget

    try box.drawBackground();
    // might draw the background in a different way

    defer box.deinit();

    // widgets run here will be children of box
}
```
The lower-level functions give a lot more customization options including animations, intercepting events, and drawing differently.

Start with the high-level functions, and when needed, copy the body of the high-level function and customize from there.

### Parent, Child, and Layout
The primary layout mechanism is nesting widgets.  DVUI keeps track of the current parent widget.  When a widget runs, it is a child of the current parent.  A widget may then make itself the current parent, and reset back to the previous parent when it runs `deinit()`.

The parent widget decides what rectangle of the screen to assign to each child.

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
- colors (either RGBA value or named)
  - example RGBA `.color_text = .{ .color = .{ .r = 0xe0, .g = 0x1b, .b = 0x24 } }`
  - example named `.color_text = .{ .name = .err }` (get current theme's `color_err`)
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
    win.theme = win.themes.get("Adwaita Dark").?;
}
else {
    win.theme = win.themes.get("Adwaita Light").?;
}
```
The theme's color_accent is also used to show keyboard focus.

See [implementation details](readme-implementation.md) for more information.

