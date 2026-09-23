# Cross-compiling dvui backends

Exactly which native libraries each backend links, per target OS. Pulled
straight from each fork's `build.zig` (`linkSystemLibrary`/`linkFramework`
calls) — the sibling dirs `../lib-sdl-dev`, `../raylib-dev-fork`,
`../wio-dev-fork`, `../pugl-dev-fork`, and the `zglfw` package.

Windows never needs a sysroot: Zig bundles mingw-w64 headers/import libs, so
`-Dtarget=x86_64-windows-gnu` alone is enough — the libs listed below are
already in that bundle. Linux and macOS need a real sysroot (see below) with
these headers+libs present, passed via `-Dsystem_include_path=...
-Dlibrary_path=...` (Linux) or `--sysroot ... -Dsystem_include_path=...
-Dsystem_framework_path=...` (macOS).

custom / testing / proxy: no native deps anywhere, libc only.
web: n/a, always builds to `wasm32-freestanding` regardless of host.
dx11: Windows-only backend, build steps don't even register for Linux/macOS targets.

## Windows (libs, all bundled by zig's mingw-w64 — nothing to install)

- sdl2 / sdl3 / sdl3gpu: `user32 shell32 advapi32 setupapi winmm gdi32 imm32 version oleaut32 ole32`
- raylib / raylib_zig: `opengl32 winmm gdi32` (+ `shcore` if HiDPI)
- glfw: `gdi32 user32 shell32`
- wio: `user32 shell32 ole32 gdi32 opengl32 hid` + `xinput9_1_0`/`xinput1_4`
- pugl: `user32 shlwapi dwmapi gdi32 opengl32`
- dx11: `win32`/zigwin32 bindings, `comdlg32 ole32`

## Linux (apt packages, install into the sysroot)

- sdl2 / sdl3 / sdl3gpu: links `X11 Xext pulse` → `libx11-dev libxext-dev libpulse-dev`
- raylib / raylib_zig (X11 backend, default): links `GL X11 Xrandr Xinerama Xi Xcursor` → `libgl-dev libx11-dev libxrandr-dev libxinerama-dev libxi-dev libxcursor-dev`
- raylib / raylib_zig (`-Dlinux_display_backend=Wayland`): links `wayland-client wayland-cursor wayland-egl xkbcommon` → `libwayland-dev libxkbcommon-dev`
- glfw: links `X11` → `libx11-dev`
- wio (X11 backend): links `x11 xrandr xcursor xext` (+`gl` if OpenGL renderer) → `libx11-dev libxrandr-dev libxcursor-dev libxext-dev libgl-dev`
- wio (Wayland backend): links `wayland-client xkbcommon libdecor-0` (+`wayland-egl egl` for GL) → `libwayland-dev libxkbcommon-dev libdecor-0-dev libegl-dev`
- wio (Vulkan renderer, either backend): + `vulkan` → `libvulkan-dev`
- wio (`-Dwio_audio=true`): + `libpulse` → `libpulse-dev`
- pugl: links `m X11 Xrender` (+`Xcursor Xrandr Xext` if enabled) + `GL` or `vulkan` depending on renderer → `libx11-dev libxrender-dev libgl-dev` (+`libxcursor-dev libxrandr-dev libxext-dev libvulkan-dev` as needed)

Don't want to scope packages per backend? The superset apt line already used
in `.github/workflows/test.yml`'s "Install libraries" step covers every case
above in one shot:

```
sudo apt-get install mesa-common-dev libgl-dev libglx-dev libegl-dev \
  libpulse-dev libxext-dev libxfixes-dev libxrender-dev libasound2-dev \
  libx11-dev libxrandr-dev libxi-dev libgl1-mesa-dev libglu1-mesa-dev \
  libxcursor-dev libxinerama-dev libwayland-dev libxkbcommon-dev
```

## macOS (frameworks, extract from Xcode's SDK into the sysroot)

- sdl2 / sdl3 / sdl3gpu: `OpenGL Metal CoreVideo Cocoa IOKit ForceFeedback Carbon CoreAudio AudioToolbox AVFoundation Foundation`
- raylib / raylib_zig: `Foundation CoreServices CoreGraphics AppKit IOKit OpenGL`
- glfw: `IOKit CoreFoundation Metal AppKit CoreServices CoreGraphics Foundation` + `objc`
- wio: `Cocoa QuartzCore IOKit` (+ `CoreAudio AudioUnit AudioToolbox` with `-Dwio_audio=true`)
- pugl: `Cocoa CoreVideo` (+ `Metal QuartzCore` for the Vulkan/Metal renderer)

## Building a sysroot

**Linux** — install the packages above into a real (or containerized) Linux
system, or `apt-get download` + `dpkg -x` them into a scratch dir without
installing, so you end up with a tree containing `usr/include` and
`usr/lib/x86_64-linux-gnu`, e.g. `/tmp/linux-sysroot`. Then:

```
-Dsystem_include_path=/tmp/linux-sysroot/usr/include \
-Dlibrary_path=/tmp/linux-sysroot/usr/lib/x86_64-linux-gnu
```

**macOS** — on any Mac, run `xcrun --sdk macosx --show-sdk-path` and tar up
`usr/include`, `usr/lib`, and `System/Library/Frameworks` from that path
(headers + `.tbd` stub libs only — no compiled Apple binaries, so it's fine
to redistribute/cache in CI). Extract it somewhere, e.g. `/tmp/macos-sysroot`,
then:

```
-Dtarget=aarch64-macos --sysroot /tmp/macos-sysroot \
-Dsystem_include_path=/tmp/macos-sysroot/usr/include \
-Dsystem_framework_path=/tmp/macos-sysroot/System/Library/Frameworks
```

This is exactly what the `macos-sdk` + `compile-macos-cross` jobs in
`test.yml` already automate.
