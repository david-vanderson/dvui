# DVUI - Inside Information

This document gives technical details and is useful for people extending or writing new widgets.  See [readme](/README.md) for a broad overview.

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
  * draws border and background
  * some widgets set the clipping rectangle (sometimes called scissor rectangle) to prevent drawing outside its given space
    * this is how a scroll container prevents children that are half-off the scroll viewport from drawing over other widgets

Now the widget is the parent widget, so further widgets nested here will be children of this widget.

* `processEvents()`
  * loop over `events()`, call `matchEvent()` for each
  * set `Event.handled` if no other widget should process this event
  * bubble event to parent if `Event.bubbleable()`

See the Event Handling section for details.

* `drawBackground()`, `draw()`, `drawFocus()`
  * draw parts of the widget, there's some variety here
  * some widgets (BoxWidget) don't have a draw at all, they only do border/background
  * some widgets (ButtonWidget) only have drawFocus to maybe draw a focus border

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
- parent's id
- @src() passed to widget
- `.id_extra` field of Options passed to widget (defaults to 0)

The id a widget gets should be the same each frame, even if other widgets are being added or removed.  Mixing in the parent's id also means you can package up a collection of widgets in a function and call that function in many different parents making it easy to replicate parts of the gui.

`.id_extra` is to differentiate many children being added to the same parent in a loop.

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
- communication from child to parent
- how refresh works

## FPS and Frame Refresh

## Animations

## Rect and RectScale
- also margin/border/padding/content

## Debugging

## dataGet/dataSet/dataGetSlice

## Clipping


## Mutlithreading

## Drawing
- deferred
- subwindows
- pathStrokeAfter for focus outlines

