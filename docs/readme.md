# DVUI documentation
[generate signature docs](#how-to)

# The Guide
Let's learn how do DVUI components work, shall we?
DVUI uses a data system to store persistnent data between frames, it works like global variables but it's more flexible.
WARNING: It's a heap allocated database system so don't overuse it for business logic.
This system is great for getting a lot of the pros of retained mode GUI which makes it better than being just hardcore raw
(you don't store the widgets in state all the time, I'm talking to you DearImGui).

### Hello World
```zig
const std = @import("std");
const dvui = @import("dvui");

pub const dvui_app = dvui.App{
    .frameFn = frame,
    .config = .{ .options = .{ .size = .{ .w = 200, .h = 200 }, .title = "Hello, World" } },
};
pub const main = dvui.App.main;

fn frame() !dvui.App.Result {
    dvui.labelNoFmt(@src(), "Hello, World", .{}, .{});
    return .ok;
}
```
let's break this program down:
- lines 1-2: Imports
- lines 4-8: Creating the app struct, it's a struct that is found by DVUI at compile time (the naming is required) and defines how to start
  the app which is required so the renderer main function could work (we'll explain renderers later) you can have your own main funciton and have
  it call that one because all what this is just some convenience for less boiler renderer specific boiler plate
- function frame: this function is called each frame to render all the items, the UI creation goes as follows:
  - you create all of your elements using the dvui elements (no rendering requied)
  - you return a dvui.App.Result (.ok or .close), .ok means to continue the application, .close means to stop the application. DVUI handles window
  closing even if you don't every frame

### Basic Elements
There are a lot of elements in DVUI but these are the basic ones (for more advanced elements go to [Advanced Elements](#advanced-elements))
- buttons: `dvui.button(@src(), <text>, <init-options>, <options>);`
- label: `dvui.label(@src(), comptime <text>, <fmt-options>, <options>)`
- textEntry: `dvui.textEntry(@src(), <init-options>, <options>)` (returns an element)
- box: `dvui.box(@src(), <init-options>, <options>)` (returns an element)
- flexbox: `dvui.flexbox(@src(), <init-options>, <options>)` (returns an element)
- grid: `dvui.grid(@src(), <cols>, <init-options>, <options>)` (returns an element)
- scrollarea: `dvui.scrollArea(@src(), <init-options>, <options>)` (returns an element)

let's explain all of these arguments. The `@src()` argument present in each element is there to generate the ID (you'll learn more about
[Generating IDs](#ids) later). text is just a string, like the text that you print (it's a []const u8). Options are introduced to customize
the look and properties of the element. Init options are properties specific to the element itself (because Options is just a struct used
for all elements, for consistency and special properties are kept in Init Options.

### IDs
IDs are generated based on `std.builtin.SourceLocation` which is returned from the `@src()` builtin, hence why it's present in every
element intialization function, that system is great but when you have a loop, like showing a list of todos, you have to set the `id_extra`
option so IDs don't duplicate. Duplicate IDs will cause things to not show up and will cause a lot of errors spamming in the terminal.

### Options & Styling
In every GUI library there is a styling system, in dvui styles are just properties which is very convenient, check the signature for
`Options` to know how to style and configure your element as it is very straight forward. [Options](https://david-vanderson.github.io/docs/#dvui.Options)

### Themes
In DVUI themes are just structs that set some values by default in the options of your elements. [Themes](https://david-vanderson.github.io/docs/#dvui.Theme)

### Fonts
In DVUI Fonts are the configuration for text style, to load a font familly you use [addFont](https://david-vanderson.github.io/docs/#dvui.addFont). [Font](https://david-vanderson.github.io/docs/#dvui.Font)

# How to

Just run `zig build docs` 

This will generate the docs, ready for static server, in `zig-out/docs`

Viewing in local can be achieve with, for exemple :
- `python -m http.server -d zig-out/docs/`
- `caddy file-server --root zig-out/docs/ --listen :8000`

Note that `zig build docs --watch` should works beautifully.
I also add success temporarily adding in the `<head>` section of `docs/index.html` :  
` <script type="text/javascript" src="http://livejs.com/live.js"></script>`  
For a full auto reload experience. Cool enough to be mentioned.

# About Images

Images/screenshots are integrated in the docs. It works by : 

- Declaring a `test` block whose name ends with `.png`
- Said test block should use `dvui.testing.saveDocImage` function
- It relies on `docs/image_gen_test_runner.zig` test runner to provide a path.
- To use the image, use the markdown image syntax with the test name.

e.g. :
- `test "my-image.png" { // declare gui element and call dvui.testing.saveDocImage }`
- `/// ![image description](my-image.png)`


# About Customization

Simple Customization of the logo is performed with `docs/add_doc_logo.zig` that is automatically called via the `build.zig`.

`docs/index.html` is mostly a copy paste of the default one generated by the zig tool chain. 

Changes :
- Removed logo and favico for a NEEDLE_STRING that is replaced at build time.
- Played a bit around with the colors to roughly match Web Demo style

## Note to future self (or other future people)

It's possible (likely ?) that zig update will change stuff enough to make the current `index.html` broken at some point.
In which case one would need to comment out the "Html Customization" section in `build.zig`, build the docs, copy-paste the default `index.html` and reapply the relevant changes.

# CI

TODO 
