/* Minimal printf for CoreMark: %d %u %x %s %c, the l modifier, '0' padding and width.
   Characters go to PRINT_ADDR, which the simulation harness prints. */
#include <stdarg.h>
#include "coremark.h"

#define PRINT_ADDR ((volatile unsigned int *)0x40000000)

static void out(char c) { *PRINT_ADDR = (unsigned char)c; }

static void out_num(unsigned int v, unsigned base, int neg, int width, char pad)
{
    char buf[12];
    int n = 0;
    do { unsigned d = v % base; buf[n++] = (char)(d < 10 ? '0' + d : 'a' + d - 10); v /= base; } while (v);
    if (neg) buf[n++] = '-';
    while (n < width--) out(pad);
    while (n) out(buf[--n]);
}

int ee_printf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    for (; *fmt; fmt++) {
        if (*fmt != '%') { out(*fmt); continue; }
        fmt++;
        char pad = ' ';
        int width = 0;
        if (*fmt == '0') { pad = '0'; fmt++; }
        while (*fmt >= '0' && *fmt <= '9') width = width * 10 + (*fmt++ - '0');
        while (*fmt == 'l') fmt++;
        switch (*fmt) {
        case 'd': { int v = va_arg(ap, int); out_num(v < 0 ? -(unsigned)v : (unsigned)v, 10, v < 0, width, pad); break; }
        case 'u': out_num(va_arg(ap, unsigned), 10, 0, width, pad); break;
        case 'x': out_num(va_arg(ap, unsigned), 16, 0, width, pad); break;
        case 'c': out((char)va_arg(ap, int)); break;
        case 's': { const char *s = va_arg(ap, const char *); while (*s) out(*s++); break; }
        default:  out(*fmt); break;
        }
    }
    va_end(ap);
    return 0;
}
