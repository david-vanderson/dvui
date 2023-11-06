# DVUI - Inside Information

This document gives technical details and is useful for people extending or writing new widgets.  See [readme](/README.md) for a broad overview.

### One Frame At a Time

DVUI is an immediate-mode GUI, so widgets are created on the fly.  We also process the whole list of events that happened since last frame.

A widget is a block of code that runs every frame.  Generally it follows this pattern:

* `init()`
  * create the struct representing this widget
  * `WidgetData.init()` generate ID and get a Rect from the parent widget (our place on the screen)
  * `dataGet()` load persisted data from last frame
  * note: during init() the struct is in temporary memory, so you can't take the address of it or any field yet

Here the widget has a Rect, but hasn't drawn anything.  Animations (fading in, sliding, growing/shrinking) would be applied here.

* `install()`
  * `parentSet()` set this widget as the new parent
  * `register()` provides debugging information
  * draws border and background

Now the widget is the parent widget, so further widgets nested here will be children of this widget.

* `processEvents()`
  * get `EventMatchOptions` for this widget
  * loop over `events()`, call `eventMatch()` for each
  * set `Event.handled` if no other widget should process this event
  * bubble event to parent if `Event.bubbleable()`

For mouse events, which are routed by the Rect, this widget can process them either here (before children), or in `deinit()` (after children).  For example, `FloatingWindowWidget` processes some mouse events before children - the lower-right drag-resize handle - and other mouse events after children - dragging anywhere in the background drags the subwindow.

* `draw()`
  * draw the content of the widget

Layout widgets like `BoxWidget` usually don't process events or draw anything besides border and background.

* `deinit()`
  * `dataSet()` store data for next frame
  * `minSizeSetAndRefresh()` store our min size for next frame, refresh if it changed
  * `minSizeReportToParent()` send min size to parent widget for next frame layout
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

TODO: popups/floaters

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


## BoxWidget vs box()


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

## Event Handling
- mouse vs keyboard
- how focus works
- .focus and .position events

## Mutlithreading
