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
