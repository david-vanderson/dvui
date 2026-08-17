// Used by addTranslateC() in build.zig

// musl fails to compile saying missing "bits/setjmp.h", and nobody should
// be using setjmp anyway
#define _SETJMP_H 1

#ifdef DVUI_USE_FREETYPE
#include "freetype/ftadvanc.h"
#include "freetype/ftbbox.h"
#include "freetype/ftbitmap.h"
#include "freetype/ftcolor.h"
#include "freetype/ftlcdfil.h"
#include "freetype/ftsizes.h"
#include "freetype/ftstroke.h"
#include "freetype/fttrigon.h"
#else
#include "stb_truetype.h"
#endif

#ifndef DVUI_USE_LIBC
#define STBI_NO_STDIO 1
#define STBI_NO_STDLIB 1
#define STBIW_NO_STDLIB 1
#endif

#include "stb_image.h"
#include "stb_image_write.h"

// Used by native dialogs
#ifdef DVUI_USE_TINYFILEDIALOGS
#include "tinyfiledialogs.h"
#endif

#ifdef DVUI_USE_TREESITTER
#include "tree_sitter/api.h"
#endif

#if defined(__APPLE__) && defined(DVUI_USE_FREETYPE)
#include <stddef.h>
#include <stdint.h>
int dvui_macos_font_path_for_codepoint(
    uint32_t codepoint,
    const char *family,
    size_t family_len,
    int bold,
    int italic,
    char *out,
    size_t out_len
);
#endif

#if defined(_WIN32) && defined(DVUI_USE_FREETYPE)
#include <stddef.h>
#include <stdint.h>
int dvui_windows_font_path_for_codepoint(
    uint32_t codepoint,
    const char *family,
    size_t family_len,
    int bold,
    int italic,
    char *out,
    size_t out_len
);
#endif

#if defined(__linux__) && defined(DVUI_USE_FREETYPE)
#include <stddef.h>
#include <stdint.h>
int dvui_linux_font_path_for_codepoint(
    uint32_t codepoint,
    const char *family,
    size_t family_len,
    int bold,
    int italic,
    char *out,
    size_t out_len
);
#endif
