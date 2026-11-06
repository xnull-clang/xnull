/* 由 impl/tools/gen_resources.py 生成（构建期产物，勿手改；S8 §5.6）。
 * 资源表按名称升序；查找为二分；空表零成本。 */
#include <stddef.h>
#include <string.h>

typedef struct {
    const char         *name;
    const unsigned char *data;
    size_t              len;
} xrt_resource;

static const xrt_resource g_xrt_resources[] = {
    /* a.txt（5 字节） */
    {
        .name = "a.txt",
        .data = (const unsigned char[]){
    0x68, 0x65, 0x6C, 0x6C, 0x6F,
        },
        .len = 5,
    },
    /* b.bin（3 字节） */
    {
        .name = "b.bin",
        .data = (const unsigned char[]){
    0x01, 0x02, 0xFF,
        },
        .len = 3,
    },
    /* config.json（7 字节） */
    {
        .name = "config.json",
        .data = (const unsigned char[]){
    0x7B, 0x22, 0x6B, 0x22, 0x3A, 0x31, 0x7D,
        },
        .len = 7,
    },
};

size_t xrt_resource_count(void) {
    return sizeof(g_xrt_resources) / sizeof(g_xrt_resources[0]);
}

int xrt_resource_get(const char *name, size_t nlen,
                     const unsigned char **out, size_t *out_len) {
    size_t lo = 0, hi = xrt_resource_count();
    while (lo < hi) {
        size_t mid = lo + (hi - lo) / 2;
        const xrt_resource *r = &g_xrt_resources[mid];
        size_t min_len = nlen < strlen(r->name) ? nlen : strlen(r->name);
        int cmp = memcmp(name, r->name, min_len);
        if (cmp == 0) {
            if (nlen == strlen(r->name)) {
                *out = r->data; *out_len = r->len; return 0;
            }
            cmp = nlen < strlen(r->name) ? -1 : 1;
        }
        if (cmp < 0) { hi = mid; } else { lo = mid + 1; }
    }
    return 1; /* 未找到：显式区分，不静默给空 */
}
