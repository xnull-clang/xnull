/* rt_std_res_empty.c — 资源表符号的弱兜底（S6-04 / XDK-10）
 *
 * `rt_std_res.c` 引用 xrt_resource_count/get/at；工程资源表由 `xnull dev res`
 * 生成（强符号）。本文件提供弱定义，保证以下场景仍能链接：
 *   - 零资源工程/手工 cc 的测试未注入资源表；
 *   - 产物构建未提供 ResC。
 *
 * 强定义（生成的资源表或 build.go 的空表）在链接期覆盖弱定义。
 * 注意：必须与 rt_std_res.c 分属不同编译单元——若写在同文件，-O2 可能把
 * 调用绑定到本地弱定义，导致生成的表不生效。
 */
#include <stddef.h>

#if defined(__GNUC__) || defined(__clang__)
#define XRT_WEAK __attribute__((weak))
#else
#define XRT_WEAK
#endif

XRT_WEAK size_t xrt_resource_count(void) {
    return 0;
}

XRT_WEAK int xrt_resource_get(const char *name, size_t nlen,
                              const unsigned char **out, size_t *out_len) {
    (void)name;
    (void)nlen;
    *out = 0;
    *out_len = 0;
    return 1;
}

XRT_WEAK int xrt_resource_at(size_t i, const char **name, size_t *nlen,
                             const unsigned char **out, size_t *out_len) {
    (void)i;
    *name = 0;
    *nlen = 0;
    *out = 0;
    *out_len = 0;
    return 1;
}
