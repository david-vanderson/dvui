
#if INCLUDE_CUSTOM_LIBC_FUNCS
#include "stb_image_libc.c"
#endif

#define STBI_FAILURE_USERMSG
#define STBI_NO_STDIO

// This removes the need for ldexp and strtol
#define STBI_NO_HDR


#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
