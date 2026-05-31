// Used by addTranslateC() in build.zig
#include <raygui.h>
#include <raylib.h>
#include <raymath.h>
#include <rlgl.h>

#include <glfw3.h>

#ifdef __EMSCRIPTEN__
    void emscripten_sleep(unsigned int ms);
#endif
