## Running
1. Install Android Studio and Android NDK
    - https://developer.android.com/studio
    - https://developer.android.com/studio/projects/install-ndk

### Zig side
SDL3 is built from source (native lib + its Java sources), no `.aar` needed.
1. `(cd zig-project && zig build lib -Dtarget=aarch64-linux-android -Doptimize=ReleaseSafe -Dandroid_include_path=<android_home>/sdk/ndk/<version>/toolchains/llvm/prebuilt/<host>/sysroot/usr/include)`
    - Installs `libsdl_hello.a`, `libSDL3.a`, SDL headers and `java/` into `zig-project/zig-out`, which the Android project reads directly.

### Testing
1. Open the project in Android studio and run the app
    - If the emulated phone has a notch, you might need to use [SDL_GetWindowSafeArea](https://wiki.libsdl.org/SDL3/SDL_GetWindowSafeArea)
