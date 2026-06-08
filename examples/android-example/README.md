## Running
1. Install Android Studio and Android NDK
    - https://developer.android.com/studio
    - https://developer.android.com/studio/projects/install-ndk

### Android Side
1. Download the latest android zip (called something similar to `SDL3-devel-<version>-android.zip`) from the [SDL releases](https://github.com/libsdl-org/SDL/releases) 
1. Extract and move the `.aar` to `andrdoi-project/app/libs/`
1. Update `andrdoi-project/app/build.gradle` to reflect the version of the `.aar`. The line should be at the end and is `implementation files('libs/SDL3-3.4.0.aar')`

### Zig side
1. In `zig-project/build.zig`, update `android_include_path` with the correct value
    - Should be close to "<android_home>/sdk/ndk/<version>/toolchains/llvm/prebuilt/<host>/sysroot/usr/include"
1. `(cd zig-project && zig build lib -Dtarget=aarch64-linux-android -Doptimize=ReleaseSafe)`
    - It takes a couple minutes and it'll feel like it's hanging but it's not
1. `mkdir -p android-project/app/src/main/c/prebuilt/arm64-v8a`
1. `cp zig-project/zig-out/lib/libsdl_hello.a android-project/app/src/main/c/prebuilt/arm64-v8a`

### Testing
1. Open the project in Android studio and run the app
    - If the emulated phone has a notch, you might need to use [SDL_GetWindowSafeArea](https://wiki.libsdl.org/SDL3/SDL_GetWindowSafeArea)
