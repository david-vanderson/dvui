
#include <stddef.h>

extern void *dvui_c_alloc(size_t size);
#define STBI_MALLOC(sz) dvui_c_alloc(sz)
extern void dvui_c_free(void *ptr);
#define STBI_FREE(p) dvui_c_free(p)
extern void *dvui_c_realloc_sized(void *ptr, size_t oldsize, size_t newsize);
#define STBI_REALLOC_SIZED(p,oldsz,newsz) dvui_c_realloc_sized(p,oldsz,newsz)

extern void dvui_c_panic(char const *msg);
#define STBI_ASSERT(_Assertion)                         \
  do {                                                  \
    if ((_Assertion) == 0)                              \
      dvui_c_panic("Assertion " #_Assertion " failed!"); \
  } while (0)

static int strcmp(const char *l, const char *r)
{
	for (; *l==*r && *l; l++, r++);
	return *(unsigned char *)l - *(unsigned char *)r;
}

static int strncmp(const char *_l, const char *_r, size_t n)
{
	const unsigned char *l=(void *)_l, *r=(void *)_r;
	if (!n--) return 0;
	for (; *l && *r && n && *l == *r ; l++, r++, n--);
	return *l - *r;
}

static long strtol(const char *restrict s, char **restrict p, int base)
{
    dvui_c_panic("strtol called");
    return 100;
}

static int abs(int a)
{
	return a>0 ? a : -a;
}

extern double dvui_c_pow(double x, double y);
static double pow(double x, double y)
{
    return dvui_c_pow(x, y);
}

extern double dvui_c_ldexp(double x, int n);
static double ldexp(double x, int n) {
    return dvui_c_ldexp(x, n);
}

