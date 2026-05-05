// Used by addTranslateC() in build.zig

// Zig 0.16 bundled arm_vector_types.h uses __mfp8 builtin that
// translate-c can't resolve. Gate arm_neon.h include off.
#define SDL_DISABLE_ARM_NEON_H 1

#include "SDL2/SDL.h"
#include "SDL2/SDL_syswm.h"
