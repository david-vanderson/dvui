#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>

// Implemented in zig-project/src/main.zig. Mirrors
// examples/android-example/android-project/app/src/main/c/main.c: dvui's App
// runs the whole event loop, so this native main() just hands off to it.
extern int dvui_main(int argc, char *argv[]);

int main(int argc, char *argv[]) {
    return dvui_main(argc, argv);
}
