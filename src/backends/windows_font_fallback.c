// src/backends/windows_font_fallback.c

#ifndef _WIN32
#error "windows_font_fallback.c is Windows-only"
#endif

#include <windows.h>
#include <dwrite.h>
#include <dwrite_2.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdlib.h>

// MinGW headers declare these as extern but don't provide definitions.
const GUID IID_IDWriteFactory2 = {0x0439fc60,0xca44,0x4994,{0x8d,0xee,0x3a,0x9a,0xf7,0xb7,0x32,0xec}};
const GUID IID_IDWriteLocalFontFileLoader = {0xb2d9f3ec,0xc9fe,0x4a11,{0xa2,0xec,0xd8,0x62,0x08,0xf7,0xc0,0xa2}};
const GUID IID_IDWriteTextAnalysisSource = {0x688e1a58,0x5094,0x47c8,{0xad,0xc8,0xfb,0xce,0xa6,0x0a,0xe9,0x2b}};

#ifndef ARRAYSIZE
#define ARRAYSIZE(a) (sizeof(a) / sizeof((a)[0]))
#endif

static IDWriteFactory2 *dvui_dwrite_factory = NULL;
static IDWriteFontFallback *dvui_font_fallback = NULL;
static IDWriteFontCollection *dvui_system_fonts = NULL;

static void dvui_release(void *p) {
    if (p) ((IUnknown *)p)->lpVtbl->Release((IUnknown *)p);
}

static int dvui_init_dwrite(void) {
    HRESULT hr;

    if (dvui_dwrite_factory && dvui_font_fallback && dvui_system_fonts) {
        return 1;
    }

    hr = DWriteCreateFactory(
        DWRITE_FACTORY_TYPE_SHARED,
        &IID_IDWriteFactory2,
        (IUnknown **)&dvui_dwrite_factory
    );
    if (FAILED(hr) || !dvui_dwrite_factory) return 0;

    hr = dvui_dwrite_factory->lpVtbl->GetSystemFontCollection(
        dvui_dwrite_factory,
        &dvui_system_fonts,
        FALSE
    );
    if (FAILED(hr) || !dvui_system_fonts) return 0;

    hr = dvui_dwrite_factory->lpVtbl->GetSystemFontFallback(
        dvui_dwrite_factory,
        &dvui_font_fallback
    );
    if (FAILED(hr) || !dvui_font_fallback) return 0;

    return 1;
}

static UINT32 dvui_utf16_from_codepoint(uint32_t cp, WCHAR out[2]) {
    if (cp <= 0xFFFF) {
        out[0] = (WCHAR)cp;
        return 1;
    }
    if (cp <= 0x10FFFF) {
        cp -= 0x10000;
        out[0] = (WCHAR)(0xD800 + (cp >> 10));
        out[1] = (WCHAR)(0xDC00 + (cp & 0x3FF));
        return 2;
    }
    return 0;
}

static int dvui_utf8_to_utf16(const char *s, size_t len, WCHAR *out, int out_cap) {
    if (!s || len == 0 || !out || out_cap <= 0) return 0;
    int n = MultiByteToWideChar(CP_UTF8, 0, s, (int)len, out, out_cap - 1);
    if (n <= 0) return 0;
    out[n] = 0;
    return n;
}

typedef struct dvui_text_analysis_source {
    IDWriteTextAnalysisSource iface;
    ULONG ref_count;
    const WCHAR *text;
    UINT32 text_len;
    WCHAR locale[16];
} dvui_text_analysis_source;

static HRESULT STDMETHODCALLTYPE
dvui_tas_QueryInterface(IDWriteTextAnalysisSource *self, REFIID riid, void **ppv) {
    if (!ppv) return E_INVALIDARG;
    *ppv = NULL;

    if (IsEqualIID(riid, &IID_IUnknown) ||
        IsEqualIID(riid, &IID_IDWriteTextAnalysisSource)) {
        *ppv = self;
        self->lpVtbl->AddRef(self);
        return S_OK;
    }
    return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE
dvui_tas_AddRef(IDWriteTextAnalysisSource *self) {
    dvui_text_analysis_source *src = (dvui_text_analysis_source *)self;
    return (ULONG)InterlockedIncrement((LONG *)&src->ref_count);
}

static ULONG STDMETHODCALLTYPE
dvui_tas_Release(IDWriteTextAnalysisSource *self) {
    dvui_text_analysis_source *src = (dvui_text_analysis_source *)self;
    ULONG rc = (ULONG)InterlockedDecrement((LONG *)&src->ref_count);
    return rc;
}

static HRESULT STDMETHODCALLTYPE
dvui_tas_GetTextAtPosition(
    IDWriteTextAnalysisSource *self,
    UINT32 textPosition,
    WCHAR const **textString,
    UINT32 *textLength
) {
    dvui_text_analysis_source *src = (dvui_text_analysis_source *)self;
    if (!textString || !textLength) return E_INVALIDARG;

    if (textPosition >= src->text_len) {
        *textString = NULL;
        *textLength = 0;
        return S_OK;
    }

    *textString = src->text + textPosition;
    *textLength = src->text_len - textPosition;
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE
dvui_tas_GetTextBeforePosition(
    IDWriteTextAnalysisSource *self,
    UINT32 textPosition,
    WCHAR const **textString,
    UINT32 *textLength
) {
    dvui_text_analysis_source *src = (dvui_text_analysis_source *)self;
    if (!textString || !textLength) return E_INVALIDARG;

    if (textPosition == 0 || textPosition > src->text_len) {
        *textString = NULL;
        *textLength = 0;
        return S_OK;
    }

    *textString = src->text;
    *textLength = textPosition;
    return S_OK;
}

static DWRITE_READING_DIRECTION STDMETHODCALLTYPE
dvui_tas_GetParagraphReadingDirection(IDWriteTextAnalysisSource *self) {
    (void)self;
    return DWRITE_READING_DIRECTION_LEFT_TO_RIGHT;
}

static HRESULT STDMETHODCALLTYPE
dvui_tas_GetLocaleName(
    IDWriteTextAnalysisSource *self,
    UINT32 textPosition,
    UINT32 *textLength,
    WCHAR const **localeName
) {
    dvui_text_analysis_source *src = (dvui_text_analysis_source *)self;
    (void)textPosition;
    if (!textLength || !localeName) return E_INVALIDARG;
    *textLength = src->text_len;
    *localeName = src->locale;
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE
dvui_tas_GetNumberSubstitution(
    IDWriteTextAnalysisSource *self,
    UINT32 textPosition,
    UINT32 *textLength,
    IDWriteNumberSubstitution **numberSubstitution
) {
    dvui_text_analysis_source *src = (dvui_text_analysis_source *)self;
    (void)textPosition;
    if (!textLength || !numberSubstitution) return E_INVALIDARG;
    *textLength = src->text_len;
    *numberSubstitution = NULL;
    return S_OK;
}

static IDWriteTextAnalysisSourceVtbl dvui_tas_vtbl = {
    dvui_tas_QueryInterface,
    dvui_tas_AddRef,
    dvui_tas_Release,
    dvui_tas_GetTextAtPosition,
    dvui_tas_GetTextBeforePosition,
    dvui_tas_GetParagraphReadingDirection,
    dvui_tas_GetLocaleName,
    dvui_tas_GetNumberSubstitution
};

static int dvui_font_file_to_path(IDWriteFontFile *file, char *out, size_t out_len) {
    HRESULT hr;
    const void *ref_key = NULL;
    UINT32 ref_key_size = 0;
    IDWriteFontFileLoader *loader = NULL;
    IDWriteLocalFontFileLoader *local_loader = NULL;
    WCHAR wpath[4096];
    UINT32 wpath_len = 0;
    int utf8_len;

    if (!file || !out || out_len == 0) return 0;
    out[0] = 0;

    hr = file->lpVtbl->GetLoader(file, &loader);
    if (FAILED(hr) || !loader) return 0;

    hr = loader->lpVtbl->QueryInterface(
        loader,
        &IID_IDWriteLocalFontFileLoader,
        (void **)&local_loader
    );
    if (FAILED(hr) || !local_loader) {
        dvui_release(loader);
        return 0;
    }

    hr = file->lpVtbl->GetReferenceKey(file, &ref_key, &ref_key_size);
    if (FAILED(hr) || !ref_key || ref_key_size == 0) {
        dvui_release(local_loader);
        dvui_release(loader);
        return 0;
    }

    hr = local_loader->lpVtbl->GetFilePathLengthFromKey(
        local_loader,
        ref_key,
        ref_key_size,
        &wpath_len
    );
    if (FAILED(hr) || wpath_len + 1 > ARRAYSIZE(wpath)) {
        dvui_release(local_loader);
        dvui_release(loader);
        return 0;
    }

    hr = local_loader->lpVtbl->GetFilePathFromKey(
        local_loader,
        ref_key,
        ref_key_size,
        wpath,
        wpath_len + 1
    );
    if (FAILED(hr)) {
        dvui_release(local_loader);
        dvui_release(loader);
        return 0;
    }

    utf8_len = WideCharToMultiByte(CP_UTF8, 0, wpath, -1, out, (int)out_len, NULL, NULL);
    dvui_release(local_loader);
    dvui_release(loader);
    return utf8_len > 0;
}

int dvui_windows_font_path_for_codepoint(
    uint32_t codepoint,
    const char *family,
    size_t family_len,
    int bold,
    int italic,
    char *out,
    size_t out_len
) {
    HRESULT hr;
    WCHAR text[2];
    UINT32 text_len;
    WCHAR base_family[256];
    dvui_text_analysis_source source;
    IDWriteTextFormat *format = NULL;
    UINT32 mapped_len = 0;
    IDWriteFont *mapped_font = NULL;
    FLOAT scale = 1.0f;
    IDWriteFontFace *face = NULL;
    UINT32 file_count = 0;
    IDWriteFontFile *files[1] = {0};
    DWRITE_FONT_WEIGHT dw_weight = bold ? DWRITE_FONT_WEIGHT_BOLD : DWRITE_FONT_WEIGHT_NORMAL;
    DWRITE_FONT_STYLE dw_style = italic ? DWRITE_FONT_STYLE_ITALIC : DWRITE_FONT_STYLE_NORMAL;

    if (!out || out_len == 0) return 0;
    out[0] = 0;

    if (!dvui_init_dwrite()) return 0;

    text_len = dvui_utf16_from_codepoint(codepoint, text);
    if (text_len == 0) return 0;

    memset(&source, 0, sizeof(source));
    source.iface.lpVtbl = &dvui_tas_vtbl;
    source.ref_count = 1;
    source.text = text;
    source.text_len = text_len;
    source.locale[0] = L'e';
    source.locale[1] = L'n';
    source.locale[2] = L'-';
    source.locale[3] = L'u';
    source.locale[4] = L's';
    source.locale[5] = 0;

    if (family && family_len > 0 && family_len < sizeof(base_family)) {
        if (!dvui_utf8_to_utf16(family, family_len, base_family, ARRAYSIZE(base_family))) {
            base_family[0] = 0;
        }
    } else {
        base_family[0] = 0;
    }

    hr = dvui_dwrite_factory->lpVtbl->CreateTextFormat(
        dvui_dwrite_factory,
        base_family[0] ? base_family : L"Segoe UI",
        dvui_system_fonts,
        dw_weight,
        dw_style,
        DWRITE_FONT_STRETCH_NORMAL,
        12.0f,
        L"en-us",
        &format
    );
    if (FAILED(hr) || !format) return 0;

    hr = dvui_font_fallback->lpVtbl->MapCharacters(
        dvui_font_fallback,
        (IDWriteTextAnalysisSource *)&source,
        0,
        text_len,
        dvui_system_fonts,
        base_family[0] ? base_family : NULL,
        dw_weight,
        dw_style,
        DWRITE_FONT_STRETCH_NORMAL,
        &mapped_len,
        &mapped_font,
        &scale
    );
    if (FAILED(hr) || !mapped_font || mapped_len == 0) {
        dvui_release(format);
        return 0;
    }

    hr = mapped_font->lpVtbl->CreateFontFace(mapped_font, &face);
    if (FAILED(hr) || !face) {
        dvui_release(mapped_font);
        dvui_release(format);
        return 0;
    }

    file_count = 1;
    hr = face->lpVtbl->GetFiles(face, &file_count, files);
    if (FAILED(hr) || file_count < 1 || !files[0]) {
        dvui_release(face);
        dvui_release(mapped_font);
        dvui_release(format);
        return 0;
    }

    {
        int ok = dvui_font_file_to_path(files[0], out, out_len);
        dvui_release(files[0]);
        dvui_release(face);
        dvui_release(mapped_font);
        dvui_release(format);
        return ok;
    }
}
