## Running
1. Install Android Studio and Android NDK
    - https://developer.android.com/studio
    - https://developer.android.com/studio/projects/install-ndk

### Zig side
SDL3 is built from source (native lib + its Java sources), no `.aar` needed.
Gradle runs `zig build lib` (task `zigBuild`, before `preBuild`) and installs `libsdl_hello.a`, `libSDL3.a`, SDL headers and `java/` into `zig-project/zig-out`.
- If Android Studio can't find `zig` on its PATH, add `zig.path=/abs/path/to/zig` to `android-project/local.properties`.

### Testing
1. Open the project in Android studio and run the app
    - If the emulated phone has a notch, you might need to use [SDL_GetWindowSafeArea](https://wiki.libsdl.org/SDL3/SDL_GetWindowSafeArea)
