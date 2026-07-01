// src/backends/linux_font_fallback.c

#ifndef __linux__
#error "linux_font_fallback.c is Linux-only"
#endif

#include <fontconfig/fontconfig.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>

static int dvui_linux_weight_from_bold(int bold) {
    return bold ? FC_WEIGHT_BOLD : FC_WEIGHT_NORMAL;
}

static int dvui_linux_slant_from_italic(int italic) {
    return italic ? FC_SLANT_ITALIC : FC_SLANT_ROMAN;
}

int dvui_linux_font_path_for_codepoint(
    uint32_t codepoint,
    const char *family,
    size_t family_len,
    int bold,
    int italic,
    char *out,
    size_t out_len
) {
    FcPattern *pat = NULL;
    FcPattern *match = NULL;
    FcCharSet *charset = NULL;
    FcResult result = FcResultNoMatch;
    FcChar8 *file = NULL;
    FcBool scalable = FcFalse;
    FcBool outline = FcFalse;

    if (!out || out_len == 0) return 0;
    out[0] = 0;

    if (!FcInit()) return 0;

    pat = FcPatternCreate();
    if (!pat) return 0;

    if (family && family_len > 0) {
        char family_buf[256];
        if (family_len >= sizeof(family_buf)) family_len = sizeof(family_buf) - 1;
        memcpy(family_buf, family, family_len);
        family_buf[family_len] = 0;
        FcPatternAddString(pat, FC_FAMILY, (const FcChar8 *)family_buf);
    }

    FcPatternAddInteger(pat, FC_WEIGHT, dvui_linux_weight_from_bold(bold));
    FcPatternAddInteger(pat, FC_SLANT, dvui_linux_slant_from_italic(italic));

    charset = FcCharSetCreate();
    if (!charset) {
        FcPatternDestroy(pat);
        return 0;
    }

    if (!FcCharSetAddChar(charset, codepoint)) {
        FcCharSetDestroy(charset);
        FcPatternDestroy(pat);
        return 0;
    }

    FcPatternAddCharSet(pat, FC_CHARSET, charset);
    FcCharSetDestroy(charset);

    FcConfigSubstitute(NULL, pat, FcMatchPattern);
    FcDefaultSubstitute(pat);

    match = FcFontMatch(NULL, pat, &result);
    FcPatternDestroy(pat);
    if (!match) return 0;

    if (FcPatternGetBool(match, FC_SCALABLE, 0, &scalable) != FcResultMatch || !scalable) {
        FcPatternDestroy(match);
        return 0;
    }

    if (FcPatternGetBool(match, FC_OUTLINE, 0, &outline) == FcResultMatch && !outline) {
        FcPatternDestroy(match);
        return 0;
    }

    if (FcPatternGetString(match, FC_FILE, 0, &file) != FcResultMatch || !file) {
        FcPatternDestroy(match);
        return 0;
    }

    {
        size_t len = strlen((const char *)file);
        if (len + 1 > out_len) {
            FcPatternDestroy(match);
            return 0;
        }
        memcpy(out, file, len + 1);
    }

    FcPatternDestroy(match);
    return 1;
}
