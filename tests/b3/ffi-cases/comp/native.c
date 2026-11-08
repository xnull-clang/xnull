#include <stdint.h>
#include "xrt.h"

int64_t native_exec(int64_t x) {
    return xrt_companion_on_worker() ? x : -1;
}
int64_t native_exec_companion(int64_t x) { return x; }
