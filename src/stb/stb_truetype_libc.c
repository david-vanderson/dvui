
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


