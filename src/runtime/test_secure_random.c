/* test_secure_random.c — OS CSPRNG 与 ULID 单调计数器最小验收。 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

char *xdkc_secure_random_hex(int32_t count);
int64_t xdkc_ulid_monotonic(int64_t millis);

static int fail(const char *message) {
    fprintf(stderr, "secure_random: FAIL %s\n", message);
    return 1;
}

int main(void) {
    char *empty = xdkc_secure_random_hex(0);
    if (empty == NULL || empty[0] != 0) {
        return fail("empty count");
    }
    char *one = xdkc_secure_random_hex(1);
    if (one == NULL || strlen(one) != 2) {
        return fail("length 1");
    }
    char *hex = xdkc_secure_random_hex(32);
    if (hex == NULL || strlen(hex) != 64) {
        return fail("length 32");
    }
    int nonzero = 0;
    for (size_t i = 0; hex[i] != 0; i++) {
        if (hex[i] >= '0' && hex[i] <= '9') {
            if (hex[i] != '0') {
                nonzero = 1;
            }
        } else if (hex[i] >= 'a' && hex[i] <= 'f') {
            nonzero = 1;
        } else {
            return fail("non-hex character");
        }
    }
    if (!nonzero) {
        return fail("all zero");
    }
    if (xdkc_ulid_monotonic(1000) != 0) {
        return fail("ulid first counter");
    }
    if (xdkc_ulid_monotonic(1000) != 1) {
        return fail("ulid same-ms increment");
    }
    if (xdkc_ulid_monotonic(1001) != 0) {
        return fail("ulid next-ms reset");
    }
    printf("secure_random: PASS\n");
    return 0;
}
