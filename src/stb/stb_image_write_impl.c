
#if INCLUDE_CUSTOM_LIBC_FUNCS
#include "stb_image_libc.c"
#endif

#define STBI_WRITE_NO_STDIO
#define STBIW_WINDOWS_UTF8

extern double dvui_c_ldexp(double x, int n);
/* this should be in stb_image_libc.c like the rest, but then I get a linker error in ReleaseFast */
static double ldexp(double x, int n) {
    return dvui_c_ldexp(x, n);
}

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"
