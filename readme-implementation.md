# DVUI - Implementation Details

This document describes the internals of DVUI and is useful for people extending or writing new widgets.  See [readme](/README.md) for a broad overview.

### Example: button()

```zig
pub fn button(src: std.builtin.SourceLocation, label_str: []const u8, opts: Options) !bool {
    // initialize widget and get rectangle from parent
    var bw = ButtonWidget.init(src, .{}, opts);

    // make ourselves the new parent
    try bw.install();

    // process events (mouse and keyboard)
    bw.processEvents();

    // draw background/border
    try bw.drawBackground();

    // this child widget:
    // - has bw as parent
    // - gets a rectangle from bw
    // - draws itself
    // - reports its min size to bw
    try labelNoFmt(@src(), label_str, opts.strip().override(.{ .gravity_x = 0.5, .gravity_y = 0.5 }));

    var click = bw.clicked();

    // draw focus
    try bw.drawFocus();

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
* tracking ctrl key for ctrl-click
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
    * pass to `parent.screenRectScale()` to get a `RectScale` which is a screen (pixel) rectangle plus scale from logical points to physical pixels
  * `dataGet()` load persisted data from last frame
  * note: during `init()` the struct is in temporary memory, so you can't take the address of it or any field yet (including calling `widget()`)

Here the widget has a rectangle, but hasn't drawn anything.  Animations (fading in, sliding, growing/shrinking) would be applied here and could adjust the rectangle (see the animations section of the demo).

* `install()`
  * `parentSet()` set this widget as the new parent
  * `register()` provides debugging information
  * some widgets set the clipping rectangle (sometimes called scissor rectangle) to prevent drawing outside its given space
    * this is how a scroll container prevents children that are half-off the scroll viewport from drawing over other widgets

Now the widget is the parent widget, so further widgets nested here will be children of this widget.

* `processEvents()`
  * loop over `events()`, call `matchEvent()` for each
  * set `Event.handled` if no other widget should process this event
  * bubble event to parent if `Event.bubbleable()`

See the Event Handling section for details.

* `drawBackground()`, `draw()`, `drawFocus()`, `drawCursor()`
  * draw parts of the widget, there's some variety here
  * some widgets (BoxWidget) only do border/background

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
* child: `parentSet()` installs itself as the new parent
* child (in deinit - minSizeReportToParent): `parent.minSizeForChild()` send our min size for this frame to parent
  * parent uses this to calculate it's own min size for this frame
* child (in deinit): `parentSet()` install previous parent

Each widget keeps a pointer to its parent widget, which forms a chain going back to `dvui.Window` which is the original parent.  This chain is used for:
* `parent.screenRectScale()` translate from our child Rect (in our parent's coordinate space) to a RectScale (in screen coordinates).
* `parent.processEvent()` bubble keyboard events, so pressing the "up" key while focused on a button can make the containing scroll area scroll.

TODO: floatingWindows/popups

### Windows and Subwindows
`dvui.Window` maps to a single OS window.  All widgets and drawing happen in that window.

`subwindow` is the term dvui uses for floating windows/dialogs/popups/etc.  They are dvui widgets and are not detachable or moveable outside the OS window.

### Widget IDs
Each widget gets a `u32` id by combining:
- parent's id (see https://github.com/david-vanderson/dvui/blob/main/README.md#parent-child-and-nesting )
- @src() passed to widget
- `.id_extra` field of Options passed to widget (defaults to 0)

Since each parent already has a unique id, we only need to ensure that all children in that parent get unique ids.  Normally @src() is enough for this.  Even if a widget is made in a function or loop (so @src is always the same), usually the parent will be different each time.

When that is not the case, we can add `.id_extra` to the `Options` passed to the widget.

If creating widgets in a function, you probably want the function to take `@src()` and `Options` and pass those to the outer-most created widget.

Examples
```zig
// caller is responsible for passing src and .id_extra if needed
fn my_wrapper(src: std.builtin.SourceLocation, opts: Options) !void {
    var wrapper_box = try dvui.box(src, .horizontal, opts);
    defer wrapper_box.deinit();

    // label is a child of wrapper_box, so can just call @src() here
    try dvui.label(@src(), "Wrapped", .{}, .{});
}

pub fn frame() !void {
    // normally we pass @src() and that is good enough
    var vbox = try dvui.box(@src(), .vertical, .{});
    defer vbox.deinit();

    for (0..3) |i| {
        // this will be called multiple times with the same parent and
        // @src(), so pass .id_extra here to keep the IDs unique
        var hbox = try dvui.box(@src(), .horizontal, .{ .id_extra = i });

        // label is a child of hbox, so can just call @src() here
        try dvui.label(@src(), "Label {d}", .{i}, .{});

        hbox.deinit();

        // this will be called multiple times with the same parent and
        // @src(), so pass .id_extra here to keep the IDs unique
        try my_wrapper(@src(), .{ .id_extra = i });
    }
}

```

## Event Handling

DVUI provides a time-ordered array of all events since last frame (`events()`).  Intead of trying to route events to widgets, the widgets are responsible for choosing which events in the array to process.  The function `eventMatch()` provides the normal logic widgets will use.

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
  * if it doesn't, it bubbles the event up the parent chain
    * example: button has focus, pressing the "up" key can bubble to a containing scroll area

Special Events
* `.focus`
  * mouse event that DVUI creates that comes just before the user action (currently left-mouse-down or finger-down)
  * allows separation between focusing a widget and processing mouse-down
  * example: `windowHeader()` intercepts the `.focus` event to prevent the window from clearing the focused widget, but allows the mouse-down through so the window can do normal click-drag
* `.position`
  * mouse event that DVUI creates each frame that comes after all other events
  * represents the final mouse position for this frame
  * used to set cursor and sometimes hover state

Sometimes a widget will just want to observe events but not mark them as processed.  An example is how to differentiate ctrl-click from normal click.  In a low framerate situation, we can't rely on checking the current keyboard state when the click happens. This way the widget can watch all keyboard events and keep track of the ctrl state properly interleaved with mouse events.


## Min Size and Layout
A widget receives its position and size from its parent.  The widget sends these fields of the Options struct to the parent:
- min_size_content - the minimum size requested for this widget's content area
  - padding/border/margin are automatically added
- expand - whether to take up all the space available
  - horizontal or vertical or both
- gravity_x, gravity_y - position a non-expanded widget inside a larger rectangle
- rect - directly specify position in parent (rarely used)
  - a long scrollable list can use this to skip widgets that aren't visible
  - example is the demo icon browser

- communication from child to parent
- how refresh works

## FPS and Frame Refresh

## Animations

## Debugging

## dataGet/dataSet/dataGetSlice

## Clipping

## Mutlithreading

## Tab Index
* null vs 0 vs 1-

## Drawing
All drawing happens in pixel space.  A widget can call `parent.screenRectScale()` to get a rectangle in pixel screen coordinates plus the scale from logical points to physical pixels.

- also margin/border/padding/content
- deferred
- subwindows
- pathStrokeAfter for focus outlines

