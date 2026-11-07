/* bytes-runtime/probe.c —— 只经 xrt.h（生成代码的唯一 ABI 头）使用 Bytes 对象。
 * 证明：rt_std_bytes.c 的符号/语义不依赖内部头 rt.h（INV-FFI-7）。
 */
#include "xrt.h"

#include <stdio.h>
#include <string.h>

int main(void) {
    xrt_bytes_buf *b = xrt_bytes_from_c("abc", 3);
    int ok = xrt_bytes_len(b) == 3 && xrt_bytes_get(b, 0) == 'a';

    xrt_bytes_set(b, 0, 'A');
    xrt_bytes_push(b, 0);
    xrt_bytes_push(b, 255);
    ok = ok && xrt_bytes_len(b) == 5;
    ok = ok && memcmp(xrt_bytes_data(b), "Abc\0\xff", 5) == 0;

    xrt_bytes_buf *a = xrt_bytes_from_c("XY", 2);
    xrt_bytes_append(b, a);
    ok = ok && xrt_bytes_len(b) == 7 && memcmp(xrt_bytes_data(b), "Abc\0\xffXY", 7) == 0;
    xrt_release(a);

    xrt_bytes_buf *s = xrt_bytes_slice(b, 1, 3);
    ok = ok && xrt_bytes_len(s) == 2 && memcmp(xrt_bytes_data(s), "bc", 2) == 0;
    xrt_release(s);

    xrt_bytes_buf *z = xrt_bytes_alloc(4);
    ok = ok && xrt_bytes_len(z) == 4 && ((const unsigned char *)xrt_bytes_data(z))[3] == 0;
    xrt_release(z);

    printf("len=%zu first=%d ok=%d\n", xrt_bytes_len(b), (int)xrt_bytes_get(b, 0), ok);
    xrt_release(b);
    return ok ? 0 : 1;
}
