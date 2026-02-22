
## Using a Custom raylib-zig Version

If you want to inject a specific [raylib-zig](https://github.com/raylib-zig/raylib-zig) version of your choice, follow the pattern below:

``` zig
// In build.zig while loading the dvui dependency
const dvui_dep = b.dependency("dvui", .{
    .target = target,
    .optimize = optimize,
    .backend = .raylib_zig,
});

// If you don't want to import your own raylib dependency and use the one provided 
// in the dvui library, you may skip the following 3 lines which is used for
// preventing raylib dependencies conflicting between the library and your projects. 
const backend_mod = dvui_dep.module("raylib_zig");
backend_mod.addImport("raylib", raylib); // from your raylib dependency
backend_mod.addImport("raygui", raygui);

exe.root_module.addImport("dvui", dvui_dep.module("dvui_raylib"));
exe.root_module.addImport("backend", backend_mod);

// in your project, you may access raylib either:
const raylib_direct = @import("raylib"); // if custom raylib dependency is supplied

const backend = @import("backend");
const raylib_dvui = backend.raylib;
```
