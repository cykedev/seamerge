#include <stdarg.h>
#include <stdio.h>

#include "debug.h"

const P4Debug p4debug{};

void P4Debug::printf(const char *format, ...) const {
    va_list arguments;
    va_start(arguments, format);
    vfprintf(stderr, format, arguments);
    va_end(arguments);
}
