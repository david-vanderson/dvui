
#if INCLUDE_CUSTOM_LIBC_FUNCS
#include "stb_image_libc.c"
#endif

#define STBI_WRITE_NO_STDIO
#define STBIW_WINDOWS_UTF8

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"
