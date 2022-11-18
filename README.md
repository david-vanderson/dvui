# Easy to Integrate Immediate Mode GUI for Zig

A [Zig](https://ziglang.org/) native GUI toolkit for whole applications or extra debugging windows in an existing application.

## Screenshot

![screenshot of demo](/screenshot_demo.png?raw=true)

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

- [Build Standalone App](#standalone-app)
- [Build On Top of Existing App](#on-top-of-existing-app)
- [Design](#Design)

## Building

### Standalone App

```sh
git clone https://github.com/david-vanderson/gui
cd gui
git submodule update --init
zig build mach-test
zig build sdl-test 
```

### On Top of Existing App

Example code here assumes a Mach app, but building on top of an SDL App works almost identically.  See sdl-test.zig for code.

1. Link or copy this repo into the app:
    ```sh
    cd mach-examples/instanced-cube
    ln -s ~/gui gui
    ```

1. Add the necessary packages to the example (need freetype and zmath) (zmath only needed for mach backend):
    ```diff
    git diff ../build.zig
    -        .{ .name = "instanced-cube", .deps = &.{Packages.zmath} },
    +        .{ .name = "instanced-cube", .deps = &.{Packages.zmath}, .use_freetype = true },
    ```

1. Add the imports:
    ```zig
    const gui = @import("gui/src/gui.zig");
    const MachGuiBackend = @import("gui/src/MachBackend.zig");
    ```

1. Add variables for gui (need to persist frame to frame):
    ```zig
    win: gui.Window,
    win_backend: MachGuiBackend,
    shown_instances: u32,  // just for example
    ```

1. During app initialization, init the backend and gui (will need a persistant allocator like general purpose):
    ```zig
        app.win_backend = try MachGuiBackend.init(core);
        app.win = gui.Window.init(gpa, app.win_backend.guiBackend());
        app.shown_instances = 12;  // start with 12 cubes
    ```

1. At the beginning of the render loop, make an arena allocator and call Window.begin():
    ```zig
        var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const arena = arena_allocator.allocator();
        defer arena_allocator.deinit();

        try app.win.begin(arena, std.time.nanoTimestamp());
    ```

1. Add events for the gui:
    ```zig
        _ = try app.win_backend.addEvent(&app.win, event);
    ```

1. Call any gui functions you want:
    ```zig
        _ = try gui.examples.demo();

        {
            var fw = try gui.floatingWindow(@src(), 0, false, null, null, .{});
            defer fw.deinit();

            var box = try gui.box(@src(), 0, .horizontal, .{});
            defer box.deinit();

            if (try gui.button(@src(), 0, "more", .{})) {
                if (app.shown_instances < 16) {
                    app.shown_instances += 1;
                }
            }

            if (try gui.button(@src(), 0, "less", .{})) {
                if (app.shown_instances > 0) {
                    app.shown_instances -= 1;
                }
            }
        }
    ```

    ```
    -    pass.draw(vertices.len, 16, 0, 0);
    +    pass.draw(vertices.len, app.shown_instances, 0, 0);
    ```

1. At the end of the render loop, call Window.end() before the view is presented:
    ```zig
        _ = try app.win.end();
    ```

1. Add cleanup code:
    ```zig
        app.win.deinit();
        app.win_backend.deinit();
    ```


## Design

### Immediate Mode
```zig
if (try gui.button(@src(), 0, "Ok", .{})) {
  dialog.close();
}
```
Widgets are not stored between frames like in traditional gui toolkits (gtk, win32, cocoa).  `gui.Button()` processes input events, draws the button on the screen, and returns true if a button click happened this frame.

For an intro to immediate mode guis, see: https://github.com/ocornut/imgui/wiki#about-the-imgui-paradigm

### Widget Ids
Each widget gets a `u32` id by combining:
- parent's id
- @src() passed to widget
- extra `usize` passed to widget for loops

The id a widget gets should be the same each frame, even if other widgets are being added or removed.  Mixing in the parent's id also means you can package up a collection of widgets in a function and call that function in many different parents making it easy to replicate parts of the gui.

The extra `usize` is to differentiate many children being added to the same parent in a loop.

### Single Pass
Widgets handle events and draw themselves in `install()`.  This is before they know of any child widgets, so some information is stored from last frame about minimum sizes.

A new widget will typically receive a zero-sized rectangle, draw nothing on the first frame, and draw normally on the second frame.  For smooth UIs a new widget can be animated from zero-sized to normal size.

Between a widget's `install()` and `deinit()`, that widget becomes the parent to any widgets run between.  Each widget maintains a pointer to their parent, used for getting the screen rectangle for the child, and for key event propagation.

### Drawing
All drawing happens in pixel space.  A widget receives a rectangle from their parent in their parent's coordinate system.  They then call `parent.screenRectScale(rect)` to get their rectangle in pixel screen coordinates plus the scale value in pixels per rect unit.

This provides scaling (see `ScaleWidget`) while looking sharp, because nothing is being drawn and then scaled.

### Handle All Events
This library processes every input event, making it useable in low framerate situations.  A button can receive a mouse-down event and a mouse-up event in the same frame and correctly report a click.  A custom button can even report multiple clicks per frame.  (the higher level `gui.button()` function only reports 1 click per frame)

In the same frame these can all happen:
- text entry field A receives text events
- text entry field A receives a tab that moves keyboard focus to field B
- text entry field B receives more text events

Because everything is in a single pass, this works in the normal case where widget A is `install()`ed before widget B.  If keyboard focus moves to a previously installed widget, it can't process further key events this frame.

### Event Propagation
`gui.EventIterator` helps widgets process events.  It takes the widget id (for focus and mouse capture) and a rect (for mouse events).

For mouse events, `EventIterator` checks if the widget has mouse capture, or if the mouse event is within the given rect (and within the current clipping rect).  Mouse events can also be handled in a widget's `deinit()` if child widgets should get priority.  For example, `FloatingWindow.deinit()` handles remaining mouse events to allow click-dragging of floating windows anywhere a child widget doesn't handle the events.

For key events, `EventIterator` checks if the widget has focus and the current floating window has focus.  `EventIterator.nextCleanup()` can be used to catch key events not processed by child widgets.  For example, `FloatingWindow.deinit()` handles remaining key events to catch a tab if no widget had focus in the window.

Key events are also bubbled up to parent widgets if the child doesn't process them.  That is how `ScrollArea` can catch up/down key events and scroll even when it doesn't have focus.

### Floating Windows
This library can be used in 2 ways:
- as the gui for the whole application, drawing over the entire OS window
- as floating windows on top of an existing application with minimal changes:
  - use widgets only inside `gui.floatingWindow()` calls
  - `gui.addEvent...` functions return false if event won't be handled by gui (main application should handle it)
  - change `gui.cursorRequested()` to `gui.cursorRequestedFloating()` which returns null if the mouse cursor should be set by the main application

Floating windows and popups are handled by deferring their rendering so that they render properly on top of windows below them.  Rendering of all floating windows and popups happens during `window.end()`.

### FPS throttling
If your app is running at a fixed framerate, use `window.begin()` and `window.end()` which handle bookkeeping and rendering.

If you want to only render frames when needed, add `window.beginWait()` at the start and `window.waitTime()` at the end.  These cooperate to sleep the right amount and render frames when:
- an event comes in
- an animation is ongoing
- a timer has expired
- user code calls `gui.cueFrame()` (if your code knows you need a frame after the current one)

`window.waitTime()` also accepts a max fps parameter which will ensure the framerate stays below the given value.

`window.beginWait()` and `window.waitTime()` maintain an internal estimate of how much time is spent outside of the rendering code.  This is used in the calculation for how long to sleep for the next frame.

### Widget init and deinit
The easiest way to use widgets is through the functions that create and install them:
```zig
{
    var box = try gui.box(@src(), 0, .vertical, .{.expand = .both});
    defer box.deinit();
}
```
These functions allocate memory for the widget onto the arena allocator passed to `window.begin()`.

Instead you can allocate the widget on the stack:
```zig
{
    var box = BoxWidget.init(@src(), 0, .vertical, .{.expand = .both});
    // box now has an id, can look up animations/timers
    try box.install(.{});  // or try box.install(.{ .process_events = false});
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
- color_custom/color_custom_bg (used if color_style is .custom)
- font_style (use theme's fonts)
- font_custom (used if font_style is .custom)
```zig
if (try gui.button(@src(), 0, "Wild", .{
    .margin = gui.Rect.All(2),
    .padding = gui.Rect.all(8),
    .color_style = .custom,
    .color_custom = gui.Color{.r = 255, .g = 0, .b = 0, .a = 255},
    .color_custom_bg = gui.Color{.r = 255, .g = 0, .b = 255, .a = 255},
    })) {
    // clicked
}
```

Each widget has its own default options.  These can be changed directly:
```zig
gui.ButtonWidget.Defaults.background = false;
```

Colors come in foreground/background pairs.  Usually you want to use colors from the theme:
```zig
if (try gui.menuItemLabel(@src(), 0, "Cut", false, .{.color_style = .success, .background = true}) != null) {
    // selected
}
```

Themes can be changed between frames or even within a frame.  The theme controls the fonts and colors referenced by font_style and color_style.
```zig
if (theme_dark) {
    win.theme = &gui.theme_Adwaita_Dark;
}
else {
    win.theme = &gui.theme_Adwaita;
}
```
The theme's color_accent is also used to show keyboard focus.

### Layout
A widget receives its position rectangle from the parent, but can influence layout with Options:
- `.expand` - whether to take up all the space available (horizontal or vertical)
- `.gravity` - position a non-expanded widget inside a larger rectangle
- `.min_size` - get at least this much space (unless parent is unable)
- `.rect` - rarely used to directly specify position in parent

