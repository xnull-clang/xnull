#include <stdint.h>

#include <stddef.h>

int64_t demo_div(int64_t a, int64_t b, int32_t *code) {
    if (b == 0) {
        *code = 2;
        return 0;
    }
    *code = 0;
    return a / b;
}

int32_t demo_byte_at(const unsigned char *data, size_t len, int32_t index) {
    if (index < 0 || (size_t)index >= len) {
        return -1;
    }
    return (int32_t)data[index];
}
