#import <CoreFoundation/CoreFoundation.h>
#import <CoreText/CoreText.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>

static int dvui_copy_font_path_if_usable(CTFontRef font, char *out, size_t out_len) {
    if (!font || !out || out_len == 0) return 0;

    CFURLRef url = CTFontCopyAttribute(font, kCTFontURLAttribute);
    if (!url) return 0;

    char path[4096];
    Boolean ok = CFURLGetFileSystemRepresentation(url, true, (UInt8 *)path, sizeof(path));
    CFRelease(url);
    if (!ok) return 0;

    if (strcmp(path, "/System/Library/Fonts/Apple Color Emoji.ttc") == 0) {
        return 0;
    }

    if (strncmp(
            path,
            "/System/Library/PrivateFrameworks/FontServices.framework/Resources/Reserved/",
            strlen("/System/Library/PrivateFrameworks/FontServices.framework/Resources/Reserved/")
        ) == 0) {
        return 0;
    }

    size_t len = strlen(path);
    if (len + 1 > out_len) return 0;
    memcpy(out, path, len + 1);
    return 1;
}

static CTFontRef dvui_font_with_family(const char *family, double size) {
    CFStringRef family_name = CFStringCreateWithCString(kCFAllocatorDefault, family, kCFStringEncodingUTF8);
    if (!family_name) return NULL;
    CTFontRef font = CTFontCreateWithName(family_name, size, NULL);
    CFRelease(family_name);
    return font;
}

int dvui_macos_font_path_for_codepoint(
    uint32_t codepoint,
    const char *family,
    size_t family_len,
    int bold,
    int italic,
    char *out,
    size_t out_len
) {
    if (!out || out_len == 0) return 0;
    out[0] = 0;

    UniChar chars[2];
    CFIndex len = 1;

    if (codepoint <= 0xFFFF) {
        chars[0] = (UniChar)codepoint;
    } else if (codepoint <= 0x10FFFF) {
        codepoint -= 0x10000;
        chars[0] = (UniChar)(0xD800 + (codepoint >> 10));
        chars[1] = (UniChar)(0xDC00 + (codepoint & 0x3FF));
        len = 2;
    } else {
        return 0;
    }

    CFStringRef sample = CFStringCreateWithCharacters(kCFAllocatorDefault, chars, len);
    if (!sample) return 0;

    CFStringRef family_name = NULL;
    CTFontRef base = NULL;

    if (family && family_len > 0) {
        family_name = CFStringCreateWithBytes(
            kCFAllocatorDefault,
            (const UInt8 *)family,
            family_len,
            kCFStringEncodingUTF8,
            false
        );
    }

    if (family_name) {
        base = CTFontCreateWithName(family_name, 12.0, NULL);
        CFRelease(family_name);
    }

    if (!base) {
        base = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 12.0, NULL);
    }

    if (!base) {
        CFRelease(sample);
        return 0;
    }

    CTFontSymbolicTraits traits = 0;
    if (bold) traits |= kCTFontBoldTrait;
    if (italic) traits |= kCTFontItalicTrait;

    CTFontRef styled = NULL;
    if (traits != 0) {
        styled = CTFontCreateCopyWithSymbolicTraits(base, 12.0, NULL, traits, traits);
    }

    CTFontRef lookup = styled ? styled : base;
    // CTFontRef fallback = CTFontCreateForString(lookup, sample, CFRangeMake(0, CFStringGetLength(sample)));
    const CFIndex sample_len = CFStringGetLength(sample);
    CTFontRef fallback = CTFontCreateForString(lookup, sample, CFRangeMake(0, sample_len));


    // CFRelease(sample);
    if (styled) CFRelease(styled);
    CFRelease(base);

    if (!fallback) return 0;

    // CFURLRef url = CTFontCopyAttribute(fallback, kCTFontURLAttribute);
    if (dvui_copy_font_path_if_usable(fallback, out, out_len)) {
        CFRelease(fallback);
        CFRelease(sample);
        return 1;
    }
    CFRelease(fallback);

    // if (!url) return 0;
    const char *cjk_families[] = {
        "PingFang SC",
        "PingFang TC",
        "Hiragino Sans",
        "Hiragino Kaku Gothic ProN",
        "Songti SC",
        "Heiti SC",
    };

    for (size_t i = 0; i < sizeof(cjk_families) / sizeof(cjk_families[0]); ++i) {
        CTFontRef probe = dvui_font_with_family(cjk_families[i], 12.0);
        if (!probe) continue;
 

    // Boolean ok = CFURLGetFileSystemRepresentation(url, true, (UInt8 *)out, out_len);
    // CFRelease(url);

    // CTFontRef alt = CTFontCreateForString(probe, sample, CFRangeMake(0, CFStringGetLength(sample)));
    CTFontRef alt = CTFontCreateForString(probe, sample, CFRangeMake(0, sample_len));

    CFRelease(probe);
    if (!alt) continue;

    if (dvui_copy_font_path_if_usable(alt, out, out_len)) {
        CFRelease(alt);
        CFRelease(sample);
        return 1;
    }

    CFRelease(alt);
    }

    const char *generic_families[] = {
        "Arial Unicode MS",
        "Apple Symbols",
    };

    for (size_t i = 0; i < sizeof(generic_families) / sizeof(generic_families[0]); ++i) {
        CTFontRef probe = dvui_font_with_family(generic_families[i], 12.0);
        if (!probe) continue;
        if (dvui_copy_font_path_if_usable(probe, out, out_len)) {
            CFRelease(probe);
            CFRelease(sample);
            return 1;
        }
        CFRelease(probe);
    }

        // return ok ? 1 : 0;
        CFRelease(sample);
        return 0;
}