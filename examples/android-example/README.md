## Running
1. Install Android Studio and Android NDK
    - https://developer.android.com/studio
    - https://developer.android.com/studio/projects/install-ndk

### How This Works
* SDL3 is built from source (native lib + its Java sources), no `.aar` needed.
* Gradle (android-project/app/build.gradle)
  * runs `zig build lib` (task `zigBuild`, before `preBuild`) and installs `libsdl_hello_lib.a`, `libSDL3.a`, SDL headers and `java/` into `zig-project/zig-out`.
  * runs cmake (src/main/c/CMakeLists.txt) that produces a shared library `libsdl_hello.so` with the static libraries linked into it
  * the manifest declares "HelloWorldActivity" as the entry point
    * android-project/app/src/main/java/org/libsdl/helloworld/HelloWorldActivity.java
    * extends SDLActivity and loads shared library "sdl_hello" (`libsdl_hello.so`) at startup
* Note: If Android Studio can't find `zig` on its PATH, add `zig.path=/abs/path/to/zig` to `android-project/local.properties`.

### Testing
1. Open the project in Android studio and run the app
    - If the emulated phone has a notch, you might need to use [SDL_GetWindowSafeArea](https://wiki.libsdl.org/SDL3/SDL_GetWindowSafeArea)
