
#include <stddef.h>

extern void *dvui_c_alloc(size_t size);
#define STBTT_malloc(x,u)  ((void)(u),dvui_c_alloc(x))
extern void dvui_c_free(void *ptr);
#define STBTT_free(x,u)    ((void)(u),dvui_c_free(x))

extern void dvui_c_panic(char const *msg);
#define STBTT_assert(_Assertion)                         \
  do {                                                  \
    if ((_Assertion) == 0)                              \
      dvui_c_panic("Assertion " #_Assertion " failed!"); \
  } while (0)

extern double dvui_c_floor(double x);
#define STBTT_ifloor(x)   ((int) dvui_c_floor(x))
extern double dvui_c_ceil(double x);
#define STBTT_iceil(x)    ((int) dvui_c_ceil(x))

extern double dvui_c_sqrt(double x);
#define STBTT_sqrt(x)      dvui_c_sqrt(x)
extern double dvui_c_pow(double x, double y);
#define STBTT_pow(x,y)     dvui_c_pow(x,y)

extern double dvui_c_fmod(double x, double y);
#define STBTT_fmod(x,y)    dvui_c_fmod(x,y)

extern double dvui_c_cos(double x);
#define STBTT_cos(x)       dvui_c_cos(x)
extern double dvui_c_acos(double x);
#define STBTT_acos(x)      dvui_c_acos(x)

extern double dvui_c_fabs(double x);
#define STBTT_fabs(x)      dvui_c_fabs(x)

extern size_t dvui_c_strlen(const char * str); 
#define STBTT_strlen(x)      dvui_c_strlen(x)

// zig's compiler_rt already bundles these functions
extern void *memcpy(void *dest, const void* src, size_t n);
#define STBTT_memcpy(dest, src, n)    memcpy(dest, src, n)
extern void *memset(void *dest, int x, size_t n);
#define STBTT_memset(dest, x, n)      memset(dest, x, n)

