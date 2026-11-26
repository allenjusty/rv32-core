/* GCC may emit calls to these even with -nostdlib.
   The optimize attribute stops GCC from turning these very loops back into calls to
   memcpy/memset (which would make them call themselves forever). */
#include <stddef.h>
#define NO_LIBCALL __attribute__((optimize("no-tree-loop-distribute-patterns")))
NO_LIBCALL void *memcpy(void *d, const void *s, size_t n) { char *a = d; const char *b = s; while (n--) *a++ = *b++; return d; }
NO_LIBCALL void *memset(void *d, int c, size_t n) { char *a = d; while (n--) *a++ = (char)c; return d; }
