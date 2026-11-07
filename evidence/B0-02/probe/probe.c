/* B0-02 样例：强制链接 xrt_abi.c 与 rt_std_runtime.c 的符号。
 * 旧 4 源清单链接会失败（红）；新 8 源清单链接并运行通过（绿）。 */
#include <inttypes.h>
#include <stdio.h>

void xrt_runtime_init(void);      /* xrt_abi.c */
void xrt_safepoint(void);         /* xrt_abi.c */
int64_t xdkc_now_mono_ms(void);   /* rt_std_runtime.c */

int main(void) {
    xrt_runtime_init();
    xrt_safepoint();
    int64_t t = xdkc_now_mono_ms();
    if (t < 0) {
        puts("mono 时钟为负，异常");
        return 1;
    }
    puts("xrt_abi + rt_std 链接并运行通过");
    return 0;
}
