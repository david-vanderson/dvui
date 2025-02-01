
#if INCLUDE_CUSTOM_LIBC_FUNCS
#include "stb_image_libc.c"
#endif

#define STBI_FAILURE_USERMSG
#define STBI_NO_STDIO

extern double dvui_c_ldexp(double x, int n);
/* this should be a static function in stb_image_libc.c like the rest, but then I get a linker error in ReleaseFast */
double ldexp(double x, int n) {
    return dvui_c_ldexp(x, n);
}


#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
