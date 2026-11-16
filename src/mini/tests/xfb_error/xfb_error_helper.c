#include <stdint.h>

int64_t demo_div(int64_t a, int64_t b, int32_t *code) {
    if (b == 0) {
        *code = 2;
        return 0;
    }
    *code = 0;
    return a / b;
}
