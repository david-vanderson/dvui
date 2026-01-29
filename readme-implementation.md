# DVUI - Implementation Details

This document describes the internals of DVUI and is useful for people extending or writing new widgets.  See [readme](/README.md) for a broad overview.

If you want to make a widget that doesn't need to have child widgets inside it (but can still process events), then a function that combines existing widgets is the best approach.  Good examples are:
* textEntryNumber
* buttonIcon
* windowHeader

If you want to support child widgets, then you'll need to implement the Widget interface.  Good examples are:
* BoxWidget
* ButtonWidget

### Example: button() function combines ButtonWidget and label

```zig
pub fn button(src: std.builtin.SourceLocation, label_str: []const u8, opts: Options) bool {
    // initialize widget and get rectangle from parent
    var bw: ButtonWidget = undefined;
    bw.init(src, .{}, opts);

    // process events (mouse and keyboard)
    bw.processEvents();

    // draw background/border
    bw.drawBackground();

    // this child widget:
    // - has bw as parent
    // - gets a rectangle from bw
    // - draws itself
    // - reports its min size to bw
    labelNoFmt(@src(), label_str, opts.strip().override(.{ .gravity_x = 0.5, .gravity_y = 0.5 }));

    var click = bw.clicked();

    // draw focus
    bw.drawFocus();

    // restore previous parent
    // send our min size to parent
    bw.deinit();

    return click;
}
```

See the code for [pub fn sliderEntry](https://github.com/david-vanderson/dvui/blob/master/src/dvui.zig#:~:text=pub%20fn%20sliderEntry) for an advanced example that includes:
* swapping the kind of widget
* min size calculated from font
* tab index
* storing data from frame to frame
* intercepting events and forwarding to child widgets
* drawing a rounded rect

### One Frame At a Time

DVUI is an immediate-mode GUI, so widgets are created on the fly.  We also process the whole list of events that happened since last frame.

A widget is a block of code that runs every frame.  For each widget (`ButtonWidget`) there is a higher-level function (`button()`) that shows how to use the widget's functions.  To customize or extend a widget, start with the code in the higher-level functions.

### Single Pass

Each widget's code is run a single time per frame.  This means a widget must ask for a rectangle, process events, and draw before knowing what child widgets will be inside it.  In particular a widget will only be able to calculate its min size in `deinit()`.

The solution is to save the min size from last frame.  A new widget will typically receive a zero-sized rectangle, draw nothing on the first frame, and draw normally on the second frame.  For smooth UIs a new widget can be animated from zero-sized to normal size.

To store other bits of state from frame to frame, see `dataGet()`/`dataSet()`/`dataGetSlice()`/`dataSetSlice()`.

### Widget Overview

Generally it follows this pattern:

* `init()`
  * create the struct representing this widget
  * `WidgetData.init()` generate ID and get a `Rect` from the parent widget (loads our min size from last frame)
    * `Rect` is a rectangle in the parent's coordinate space
    * pass to `parent.screenRectScale()` to get a `RectScale` which is a screen (physical pixel) rectangle plus scale from logical pixels to physical pixels
  * `dataGet()` load persisted data from last frame
  * `parentSet()` set this widget as the new parent
  * `register()` provides debugging information
  * some widgets set the clipping rectangle (sometimes called scissor rectangle) to prevent drawing outside its given space
    * this is how a scroll container prevents children that are half-off the scroll viewport from drawing over other widgets

Now the widget is the parent widget, so further widgets nested here will be children of this widget.

* `processEvents()`
  * loop over `events()`, call `matchEvent()` for each
  * call `Event.handle()` if no other widget should process this event

See the Event Handling section for details.

* `drawBackground()`, `draw()`, `drawFocus()`, `drawCursor()`
  * draw parts of the widget, there's some variety here
  * some widgets (BoxWidget) only do border/background/box_shadow

* `deinit()`
  * some widgets process some events here
  * `dataSet()` store data for next frame
  * `minSizeSetAndRefresh()` store our min size for next frame, refresh if it changed
  * `minSizeReportToParent()` send min size to parent widget for next frame layout
  * reset the clip rect if set before
  * `parentSet()` set the previous parent back

### Parents and Children, Widget and WidgetData
"widget" is a generic term that refers to everything that goes together to make a UI element.  `dvui.Widget` is the [interface](https://zig.news/david_vanderson/faster-interface-style-2b12) that allows parent and child widgets to communicate.  Every widget has a `widget()` function to produce this interface struct.

`dvui.WidgetData` is a helper struct that holds the essential pieces of data every widget needs.  `Widget.data()` gives the `WidgetData`, and usually every widget also has a `data()` function that skips the interface.

There is always a single parent widget.  `parentSet()` is how a widget sets itself as the new parent and records the existing parent in order to set that parent back, usually in `deinit()`.

#### Parent Child Communication:
* child (in WidgetData.init): `parentGet()` to get an interface to the parent
* child (in WidgetData.init): `parent.extendId()` to create an ID
* child (in WidgetData.init): `parent.rectFor()` send our min size from last frame to parent and get back a Rect (our place on the screen)
  * except when `Options.rect` is set - see below
* child: `parentSet()` installs itself as the new parent
* child (in deinit - minSizeReportToParent): `parent.minSizeForChild()` send our min size for this frame to parent
  * parent uses this to calculate it's own min size for this frame
  * except when `Options.rect` is set - see below
* child (in deinit): `parentReset()` install previous parent

Each widget keeps a pointer to its parent widget, which forms a chain going back to `dvui.Window` which is the original parent.  This chain is used for:
* `parent.screenRectScale()` translate from our child Rect (in our parent's coordinate space) to a RectScale (in screen coordinates).
* `parent.minSizeForChild()` to inform the parent of the final size of a child for layout purposes.

#### Opting Out of Normal Layout
If `Options.rect` is set, the widget is directly specifying its position and size (still in parent coordinates).  In this case, it does not call `parent.rectFor()` nor `parent.minSizeForChild()`, which means it is invisible to its parent for layout purposes.

### Windows and Subwindows
`dvui.Window` maps to a single OS window.  All widgets and drawing happen in that window.

`subwindow` is the term dvui uses for floating windows/dialogs/popups/etc.  They are dvui widgets and are not detachable or moveable outside the OS window.

### Widget IDs
Each widget gets an `Id` (fancy u64) by combining:
- parent's id (see https://github.com/david-vanderson/dvui/blob/main/README.md#parent-child-and-nesting )
- @src() passed to widget
- `.id_extra` field of Options passed to widget (defaults to 0)

Since each parent already has a unique id, we only need to ensure that all children in that parent get unique ids.  Normally @src() is enough for this.  Even if a widget is made in a function or loop (so @src is always the same), usually the parent will be different each time.

When that is not the case, we can add `.id_extra` to the `Options` passed to the widget.

If creating widgets in a function, you probably want the function to take `@src()` and `Options` and pass those to the outer-most created widget.

Examples
```zig
// caller is responsible for passing src and .id_extra if needed
fn my_wrapper(src: std.builtin.SourceLocation, opts: Options) void {
    var wrapper_box = dvui.box(src, .{ .dir = .horizontal }, opts);
    defer wrapper_box.deinit();

    // label is a child of wrapper_box, so can just call @src() here
    dvui.label(@src(), "Wrapped", .{}, .{});
}

pub fn frame() void {
    // normally we pass @src() and that is good enough
    var vbox = dvui.box(@src(), .{}, .{});
    defer vbox.deinit();

    for (0..3) |i| {
        // this will be called multiple times with the same parent and
        // @src(), so pass .id_extra here to keep the IDs unique
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .id_extra = i });

        // label is a child of hbox, so can just call @src() here
        dvui.label(@src(), "Label {d}", .{i}, .{});

        hbox.deinit();

        // this will be called multiple times with the same parent and
        // @src(), so pass .id_extra here to keep the IDs unique
        my_wrapper(@src(), .{ .id_extra = i });
    }
}

```

## Event Handling

DVUI provides a time-ordered array of all events since last frame (`events()`).  Instead of trying to route events to widgets, the widgets are responsible for choosing which events in the array to process.  The function `eventMatch()` provides the normal logic widgets will use.

Most events are either mouse (includes touch) or keyboard:
* Mouse Events
  * have a screen position
  * we want the widget whose screen rectangle contains that position to process the event
  * there might be multiple overlapping widgets (label inside button inside scroll area)
  * each widget can either process a mouse event before or after children
    * before example: `FloatingWindowWidget` lower-right drag-resize - by processing before children, we reserve the lower-right corner for drag-resize, even if there might be a widget (button) in that space that would process the event
    * after example: `ScrollContainerWidget` mouse-wheel - by processing after children, we only scroll if no child processed the event
  * widgets can capture the mouse to receive all mouse events until they release capture
* Keyboard Events
  * have the id of the last focused widget
  * have the id of the last focused subwindow (each subwindow has a focused widget)
  * we want the focused widget to process the event

Special Events
* `.focus`
  * mouse event that DVUI creates that comes just before the user action (currently left-mouse-down or finger-down)
  * allows separation between focusing a widget and processing mouse-down
  * example: `windowHeader()` intercepts the `.focus` event to prevent the window from clearing the focused widget, but allows the mouse-down through so the window can do normal click-drag
* `.position`
  * mouse event that DVUI creates each frame that comes after all other events
  * represents the final mouse position for this frame
  * used to set cursor and sometimes hover state

Sometimes a widget will just want to observe events but not mark them as processed.  An example is how to differentiate a click while holding a non-modifier key (like "a") from normal click.  In a low framerate situation, we can't rely on checking the current keyboard state when the click happens. This way the widget can watch all keyboard events and keep track of the key state properly interleaved with mouse events.

`Window.debug.logEvents()` can be used to make dvui log events for debugging.

## Min Size and Layout
A widget receives its position and size from its parent.  The widget sends these data to the parent:
* min_size - the minimum size requested for this widget (includes content, padding, border, and margin)
  * usually this is the max of Options.min_size_content (plus padding/border/margin) and the min_size calculated for this widget from last frame
  * the min_size is also capped by Options.max_size_content (plus padding/border/margin)
* expand - whether to take up all the space available
  * horizontal or vertical or both
* gravity_x, gravity_y - position a non-expanded widget inside a larger rectangle
* rect - directly specify position in parent (rarely used)
  * a long scrollable list can use this to skip widgets that aren't visible
  * example is the demo icon browser

## Refresh
`refresh()` signals that a new frame should be rendered:
- `refresh(null, ...)` is used during a frame (between `Window.begin()` and `Window.end()`)
- `refresh(window, ...)` is used outside the frame or from another thread
  - useful when a background thread needs to wake up the gui thread

If you are getting unexpected frames, you can turn on refresh logging.  Either using the button in the DVUI Debug window, or calling `Window.debug.logRefresh(true)`.  When on, DVUI will log calls to `refresh` along with src info and widget ids to help debug where the extra frames are coming from.

## Animations
`animation()` associates a value changing over time (represented by an `Animation` struct) with a widget id and key string.  `animationGet()` retrieves one if present.  `Animation.start_time` and `Animation.end_time` are offsets from the current frame time, and are updated each frame.

There will always be a single frame where an animation is `done()` (`Animation.end_time <= 0`), then it will automatically be removed.

See `spinner()` for how to make a seamless repeating animation.

Any animation will implicitly cause a refresh, requesting the highest possible FPS during animation.  If you want periodic changes instead, use `timer()`.  It is a degenerate animation that starts and ends on a single frame, so it won't spam frames.

## dataGet/dataSet/dataGetSlice
While widgets are not stored between frames, they usually will need to store some info (like whether a button is pressed).  Some data (like min size) is stored specially.  For everything else DVUI provides a way to store arbitrary data associated with a widget id and key string:
- `dataSet()` - store any data type
- `dataGet()` - retrieve data (you must specify the type, but DVUI will (in Debug builds) check that the stored and asked-for types match
- `dataSetSlice(), dataGetSlice()` - store/retrieve a slice of data
- `dataRemove()` - remove a stored data

The first parameter to these functions can be null during a frame (between `Window.begin()` and `Window.end()`).  If outside the frame or from a different thread, you must pass the `Window` as the first parameter.

If a stored data is not used (`dataSet()` or `dataGet()`) for a frame, it will be automatically removed.  If you only want to store something for one frame, you can `dataSet()`, then next frame when `dataGet()` returns it, use `dataRemove()`.

If you need a unique id separate from a widget, use `const uniqueId = dvui.parentGet().extendId(@src(), 0);`

## Tab Index
Pressing tab will cycle keyboard focus (keyboard navigate) through all the widgets that have called `tabIndexSet()`.  Widgets will call it with the passed in `Options.tab_index`.  The order is:
* lower tab_index values come first
* null (default) comes after everything else
* 0 (zero) tab_index disables keyboard navigation
* widgets with the same tab_index go in the order they are executed

## Drawing
All drawing happens in pixel space.  For a widget `w`:
- `w.data().rectScale()` - pixels in screen space and scale factor for whole widget (content, padding, border, margin)
- `w.data().borderRectScale()` - includes content, padding, border
- `w.data().backgroundRectScale()` - includes content, padding
- `w.data().contentRectScale()` - includes content

The drawing functions are:
- `renderText()` - single line of text
- `renderIcon()` - tvg icon
- `renderImage()` - raster image via stb_image
- `renderTexture()` - texture from `textureCreate()` or `textureCreateTarget()`
- `renderTriangles()` - raw vertex and index values sent to the backend
- `Path.fillConvex()` - fill convex path (see below)
- `Path.stroke()` - stroke path (see below)
- `Rect.fill()` - convenience for making and filling a rounded rect
- `Rect.stroke()` - convenience for making and stroking a rounded rect

