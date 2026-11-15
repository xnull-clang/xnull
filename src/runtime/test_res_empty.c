/* test_res_empty.c — 资源表弱兜底（S6-04 / XDK-10）
 *
 * 不链接任何资源表，仅 rt_std_res.c + rt_std_res_empty.c；验证：
 *   - xrt_resource_* 弱符号可链接（Exit/手工 cc 测试不再缺符号）；
 *   - 零资源语义：count=0、exists=false、size=null、read=NotFound、list=Ok(空)。
 */
#include "xrt.h"

#include <assert.h>
#include <stdio.h>

int main(void) {
    assert(xrt_resource_count() == 0);
    assert(xdkc_resource_exists("a.txt", 5) == 0);

    int64_t sz = -1;
    assert(xdkc_resource_size("a.txt", 5, &sz) == 0 && sz == 0);

    xrt_context *ctx = xrt_context_background();
    xrt_bytes_buf *b = NULL;
    int32_t ek = -1;
    assert(xdkc_read_resource(ctx, "a.txt", 5, &b, &ek) == 0);
    assert(b == NULL && ek == XRT_ERR_NOT_FOUND);

    const char **items = NULL;
    size_t count = 99;
    assert(xdkc_list_resources(ctx, "", 0, &items, &count, &ek) == 1);
    assert(items == NULL && count == 0 && ek == 0);

    xrt_release(ctx);
    printf("empty resource table fallback ok\n");
    return 0;
}
