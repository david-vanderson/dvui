// Workaround for a linker symbol clash on aarch64-windows
#define __mingw_current_teb ___mingw_current_teb
#include "accesskit.h"
