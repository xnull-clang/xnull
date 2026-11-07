/* 样例原生侧实现（模拟第三方库）；P-10 之前由手工 cc 清单链接。 */
#include <stdint.h>
#include <stddef.h>

int64_t native_add(int64_t a, int64_t b) { return a + b; }
int64_t native_strlen2(const char *bytes, size_t len) { return (int64_t)len; }
