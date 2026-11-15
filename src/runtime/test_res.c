/* test_res.c — 资源表合同测试（S8 §5.6；M4.6b-2）
 *
 * 资源表 C 文件由 build_rt.sh 调 gen_resources.py 现场生成（样例目录两文件，
 * 故意以 b 在前 a 在后的写入顺序验证生成器排序）。
 */
#include <stdio.h>
#include <string.h>

size_t xrt_resource_count(void);
int xrt_resource_get(const char *name, size_t nlen, const unsigned char **out, size_t *out_len);

static int g_failures = 0;

#define CHECK(cond)                                                        \
    do {                                                                   \
        if (!(cond)) {                                                     \
            g_failures++;                                                  \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
        }                                                                  \
    } while (0)

int main(void) {
    CHECK(xrt_resource_count() == 2);

    const unsigned char *d = 0;
    size_t n = 0;

    CHECK(xrt_resource_get("a.txt", 5, &d, &n) == 0);
    CHECK(n == 5 && memcmp(d, "hello", 5) == 0);

    CHECK(xrt_resource_get("b.bin", 5, &d, &n) == 0);
    CHECK(n == 3 && memcmp(d, "\x01\x02\xFF", 3) == 0);

    CHECK(xrt_resource_get("zz", 2, &d, &n) == 1);  /* 未找到：显式区分 */
    CHECK(xrt_resource_get("", 0, &d, &n) == 1);
    CHECK(xrt_resource_get("a.tx", 4, &d, &n) == 1); /* 前缀不等于全名 */

    if (g_failures != 0) {
        fprintf(stderr, "资源表测试失败 %d 项\n", g_failures);
        return 1;
    }
    printf("资源表测试通过\n");
    return 0;
}
