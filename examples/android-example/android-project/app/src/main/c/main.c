#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>

extern int dvui_main(int argc, char *argv[]);

int main(int argc, char *argv[]) {
    return dvui_main(argc, argv);
}
