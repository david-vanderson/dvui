# Tracy integration

This is a working document / notes about my exploration of [tracy](https://github.com/wolfpld/tracy) integration.

# How to test

- Get Tracy server 0.11.1
    - Only the client part (what goes into the profiled application) is built with dvui
    - I use [this guy available for archlinux](https://aur.archlinux.org/packages/tracy-x11)
    - If not available in your distro, you will need to follow upstream doc and compile the server.
- Launch the server app, click on "connect"
- Build with `zig build sdl-standalone -Dtracy-enable`
- Play a bit with the dvui demo, then close, and the admire the traces ;-)

Note : 
- Running the binary with admin rights gives interesting extra data about CPU usage and thread interruption
- Source location doesn't work out of the box. (i.e. the button that shows source extract when you click on a zone)
    An easy fix is to `cwd` into the `dvui/src` folder and launch the app with `../zig-out/bin/sdl-standalone`
    (but even without doing so, you will have the filename and line number displayed and search in your editor)

# Implementation notes

## Zig bindings

I found a few. Started with [ztracy](https://github.com/zig-gamedev/ztracy) cause it was supporting zig 0.14.0 and I could make it work quite easily.

Another noticeable is zig-tracy. There is quite some forks. [This one](https://github.com/FalsePattern/zig-tracy) seems updated for 0.14 and support a few extra stuffs. But this fragmentation is not very appealing. Does it means everybody is just forking and tweaking some small things.

For what I can tell so far, the C API of tracy is quite understandable, and the zig wrappers are not too complicated, but deal with the context management in slightly different ways.

Questions :
- Should dvui just ship it's own wrapper or depend on an upstream lib ?

## What to instrument ?

Tracy being instrumentation based essentially, the big question is where it makes the most sense to insert "watch points"

### Frames

First thing is that the variable frame rate. Tracy has a convenient frame concept, but it's a single `FrameMark` macro and this results in the frames with a long wait (i.e. waiting for events) appear as bad guys. Thankfully, Tracy has has support for custom frames with the `FrameMarkStart(name)` / `FrameMarkEnd(name)`.
Most accurate place to insert theses is in the main loop, but this is on the client code side. Other option is to insert in `win.begin()` / `win.end()`. Did both and work fine.

Adding a zones around the `waitEventTimout` and `renderPresent` functions help to get a first sense of where the time is spent. This is in the backend code, but it worked nicely, at least in the SDL backend (did not try others yet)

### More zones

This is where things start to be more tricky. I don't want to clutter demo code with a bunch of tracy calls. This is a thing a library user might do to debug his app, but probably in a temporary manner... Or whatever way they want actually, not really a concern for dvui as a lib. Point being it's relatively trivial to provide `dvui.ztracy` and that is fine.

More interesting is if dvui wants to have default code zone. Note that this could be behind another compile time flag so a user could easily enable or disable these "built-in zones"

I tried to hook into widget generic stuff (`Widgets/init`, `WidgetData/rectScale`, ...) but this stuff is relatively short lived and fails to give a good overall sense.  
I then tried to just slap a zone in all main high level functions in `dvui.zig`. This has some usefulness, but it's still mostly short stuff that fail to give a general view of where the time goes. Plus it's ugly in the source code.

Came to realize this is because of the `init()`/`deinit()` pattern. Basically, what I want to do is to have Tracy zones start when the widget is declared, and end when the widget is deinited. The problem is that Tracy's `MarkZone` api mostly expects to work within a function scope. Or at the very least some context needs to be carried over.

### Box widget as proof of concept

Box widget being the main layout mechanism, if we can see when it starts and end, it give excellent insight about what part of the UI takes how much time to be executed.

1) Naïve approach
```
def init(...){
    self.tracy_ctx = ztracy.Zone(@src());
}
def deinit(...){
    self.tracy_ctx.End();
}
```
This doesn't work because nested boxes have the same Zone "identifier" and close each others breaking Tracy's instrumentation

2) Did a few attempts with `ztracy.ZoneN()` dirty tricks, passing a custom name. 

Did not manage to make it work. Tracy docs clearly state that you should not try to parametrize the color attribute of Zones. It's more ambiguous with the name. It mostly says you should make sure the `Start` and `End` macros get a pointer the same string (i.e. string pooling). In zig this is trivial (string are always pooled) but of course when you try to parametrize it goes south.... I don't know if this is possible nor make a lot of sense.

3) Using the `___tracy_emit_zone_begin_alloc` api

This might just be the right tool. I don't know what this extra allocation means in terms of performance / profiling accuracy.

And this was not supported by ztracy, so I did a quick fork to at least experiment. This seems to work.

Questions : 
- Does this work with threads ? Fibers ?
- Does this work with `TRACY_ON_DEMAND` ?

Since it seems to work decently, I went with the same approach for `ScrollAreaWidget` and `ButtonWidget`, just to fill a bit the space.

### Finer grain

TODO next would be to add some Zones in lower level stuff, like `Widget.data()`, `dvui.DataGet` ...

This might not add much to the overview (since it will be a lot of small regions) but for the statistical analysis this might give some interesting insights.

Questions :
- How much Zone is too much ? 
- When does the profiling/actual code ratio starts to become problematic to analyse ?

### `@src()` rabbit hole

While playing with the Zone naming / parametrization, it occur to me that the `ztracy` api require `comptime src: std.builtin.SourceLocation` and that dvui doesn't, which prevents me to "forward" the call site of the function. (i.e. report in Tracy the line where `dvui.box(...)` is called, but having the `ztracy.Zone(...)` call inside the widget code, which seems desirable behaviour/ergonomics.

I don't understand the comptime/runtime nature of `@src()` well. Discussion on Discord pointed out that `comptime SourceLocation` might lead to extra codegen / binary bloating.

Quick data point : sdl-standalone demo, without tracy

|     | Debug build | Release Safe build |
|---|:---:|:---:|
|just src |43Mo|25Mo|
|comptime src |47Mo|27Mo|


So this seems to be impact. Not dramatic but impact.

**Note however that this is not required** for `ZoneAlloc` approach, as the srcloc info is allocated anyways.

## Screenshots

Tracy provide some utilities to capture a screenshot of the app in the trace. This is very cool, but need to implement some the screenshot resizing and I have not even a clue where to start.

