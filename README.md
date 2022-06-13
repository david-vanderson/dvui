# Easy to Integrate Immediate Mode GUI for Zig

A [Zig](https://ziglang.org/) native GUI toolkit for whole applications or extra debugging windows in an existing application.

## Contents

- Immediate Mode Interface
- Use for whole UI or for debugging on top of existing application
- Integrate with just a few functions
  - Existing integrations with [Mach](https://machengine.org/) and [SDL](https://libsdl.org/)
- Icon support via [TinyVG](https://tinyvg.tech/)
- Font support via [mach-freetype](https://github.com/hexops/mach-freetype/)
- Support for:
  - Animations
  - Themes
  - FPS throttling

## Building

Current hacky way to build a mach example:
- In the mach repo, add a new example dir "guidemo"
- copy gui/ and the contents of mach_test/
- In mach's build.zig, duplicate the gkurve example line and rename to "guidemo"
- In mach: zig build run-example-guidemo

