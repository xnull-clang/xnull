#include <stdint.h>
#include <stddef.h>

int64_t native_add(int64_t a, int64_t b) { return a + b; }
int64_t native_strlen2(const char *bytes, size_t len) { (void)bytes; return (int64_t)len; }
