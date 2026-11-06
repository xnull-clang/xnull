/* S0-25 探针：验证子目录资源可被收录并按相对路径查找（S8 §5.6）。 */
#include <stddef.h>
#include <stdio.h>
#include <string.h>

size_t xrt_resource_count(void);
int xrt_resource_get(const char *name, size_t nlen,
                     const unsigned char **out, size_t *out_len);

#define GET(n, ...) xrt_resource_get((n), sizeof(n) - 1, &out, &len)

int main(void) {
    const unsigned char *out = 0;
    size_t len = 0;

    if (xrt_resource_count() != 6) {
        printf("count=%zu（期望 6）\n", xrt_resource_count());
        return 1;
    }
    if (GET("sub/x.txt") != 0 || len != 1 || out[0] != 'x') {
        puts("sub/x.txt 查找失败");
        return 2;
    }
    if (GET("sub/multi/deep.bin") != 0 || len != 4) {
        puts("sub/multi/deep.bin 查找失败");
        return 3;
    }
    if (GET("templates/mail/welcome.html") != 0 || len != 9) {
        puts("templates/mail/welcome.html 查找失败");
        return 4;
    }
    if (GET("a.txt") != 0 || len != 5) {
        puts("a.txt 查找失败");
        return 5;
    }
    if (GET("sub/nope.txt") == 0) {
        puts("不存在的资源应返回非 0");
        return 6;
    }
    puts("S0-25 探针通过：6 项资源，含 3 个多级子目录路径");
    return 0;
}
