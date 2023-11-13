# DVUI - Easy to Integrate Immediate Mode GUI for Zig

A [Zig](https://ziglang.org/) native GUI toolkit for whole applications or extra debugging windows in an existing application.

Status: Alpha. Works well enough for use in real applications, like this [podcast player](https://github.com/david-vanderson/podcast), but not widely used as yet.

Note: This works with Zig 0.11.x.

See [dvui-demo](https://github.com/david-vanderson/dvui-demo) for integration examples.

Examples:
- ```zig build run-standalone-sdl```
- ```zig build run-ontop-sdl```

## Get Started
Find the widget you want in the example and copy the code from `src/Examples.zig`.

This document is a broad overview.  See [inside](/INSIDE.md) for implementation details and how to write and modify widgets.

## Screenshot

![screenshot of demo](/screenshot_demo.png?raw=true)

## Widgets

  - Text Entry (single and multiline)
  - Floating Window
  - Menu
  - Popup/Context Window
  - Scroll Area
  - Button
  - Slider
  - Checkbox
  - Toast
  - Panes with draggable sash
  - Dropdown
- Missing Widgets for now
  - combo box
  - radio button
  - datagrid

## Features

- Immediate Mode Interface
- Process every input event (suitable for low-fps situations)
- Use for whole UI or for debugging on top of existing application
- Integrate with just a few functions
  - Existing integrations with [Mach](https://machengine.org/) and [SDL](https://libsdl.org/)
- Icon support via [TinyVG](https://tinyvg.tech/)
- Font support via [freetype](https://github.com/david-vanderson/freetype/tree/zig-pkg)
- Support for:
  - Animations
  - Themes
  - FPS throttling

## Design

### Immediate Mode
```zig
if (try dvui.button(@src(), "Ok", .{})) {
  dialog.close();
}
```
Widgets are not stored between frames like in traditional gui toolkits (gtk, win32, cocoa).  `dvui.button()` processes input events, draws the button on the screen, and returns true if a button click happened this frame.

For an intro to immediate mode guis, see: https://github.com/ocornut/imgui/wiki#about-the-imgui-paradigm

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
- user code calls `dvui.refresh()` (if your code knows you need a frame after the current one)

`window.waitTime()` also accepts a max fps parameter which will ensure the framerate stays below the given value.

`window.beginWait()` and `window.waitTime()` maintain an internal estimate of how much time is spent outside of the rendering code.  This is used in the calculation for how long to sleep for the next frame.

### Widget init and deinit
The easiest way to use widgets is through the functions that create and install them:
```zig
{
    var box = try dvui.box(@src(), .vertical, .{.expand = .both});
    defer box.deinit();
}
```
These functions allocate memory for the widget onto the arena allocator passed to `window.begin()`.

Instead you can allocate the widget on the stack:
```zig
{
    var box = BoxWidget.init(@src(), .vertical, false, .{.expand = .both});
    // box now has an id, can look up animations/timers
    try box.install(.{});
    defer box.deinit();
}
```
This also shows how to get a widget's id before install() (processes events and draws).  This is useful for animations and specially handling events.

### Appearance
Each widget has the following options that can be changed through the Options struct when creating the widget:
- margin (space outside border)
- border (on each side)
- background (fills space inside border with background color)
- padding (space inside border)
- corner_radius (for each corner)
- color_style (use theme's colors)
- color_accent (overrides widget and theme defaults)
- color_text
- color_fill
- color_border
- color_hover
- color_press
- font_style (use theme's fonts)
- font (override font_style)
```zig
if (try dvui.button(@src(), "Wild", .{
    .margin = dvui.Rect.all(2),
    .padding = dvui.Rect.all(8),
    .color_text = dvui.Color{.r = 0, .g = 255, .b = 0, .a = 150},
    .color_fill = dvui.Color{.r = 100, .g = 0, .b = 100, .a = 255},
    })) {
    // clicked
}
```

Each widget has its own default options.  These can be changed directly:
```zig
dvui.ButtonWidget.defaults.background = false;
```

Colors come in styles (content, accent, control, window, success, err).  Usually you want to use colors from the theme:
```zig
if (try dvui.menuItemLabel(@src(), "Cut", false, .{.color_style = .success, .background = true}) != null) {
    // selected
}
```

Themes can be changed between frames or even within a frame.  The theme controls the fonts and colors referenced by font_style and color_style.
```zig
if (theme_dark) {
    win.theme = &dvui.theme_Adwaita_Dark;
}
else {
    win.theme = &dvui.theme_Adwaita;
}
```
The theme's color_accent is also used to show keyboard focus.

### Layout
A widget receives its position rectangle from the parent, but can influence layout with Options:
- `.expand` - whether to take up all the space available (horizontal or vertical)
- `.gravity_x`, `.gravity_y` - position a non-expanded widget inside a larger rectangle
- `.min_size` - get at least this much space (unless parent is unable)
- `.rect` - directly specify position in parent (rarely used)

