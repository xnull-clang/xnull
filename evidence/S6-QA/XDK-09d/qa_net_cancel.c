/* QA 侧补充夹具（仅验收证据，不属于产品代码）：S6-09 NET-02/NET-05
 * 目标：在 main 上实测 取消（deadline 到期）→ code=3 Cancelled；
 *       InvalidArgument → code=1；句柄 close 幂等；错误不静默成功。
 * 构建：见同目录 run.sh
 */
#define _POSIX_C_SOURCE 200809L

#include "rt.h"
#include "xrt.h"

#include <arpa/inet.h>
#include <assert.h>
#include <netinet/in.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

/* 运行时原语（与 test_net.c 同一声明面；非产品头文件导出）。 */
void *xdkc_net_connect(const char *host, size_t hlen, int32_t port, int32_t *code);
int64_t xdkc_net_read(void *sock, void *buf, size_t cap, int32_t *code);
int32_t xdkc_net_close(void *sock);
void *xdkc_socket_connect_async(xrt_context *ctx, const char *host, size_t hlen,
                                int32_t port, int32_t *code);
int64_t xdkc_socket_recv_async(xrt_context *ctx, void *sock, void *buf,
                               size_t cap, int32_t *code);

static int listen_local(int *out_port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    assert(fd >= 0);
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    struct sockaddr_in a;
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(0x7f000001); /* 127.0.0.1 */
    a.sin_port = 0;
    assert(bind(fd, (struct sockaddr *)&a, sizeof(a)) == 0);
    assert(listen(fd, 4) == 0);
    socklen_t len = sizeof(a);
    assert(getsockname(fd, (struct sockaddr *)&a, &len) == 0);
    *out_port = (int)ntohs(a.sin_port);
    return fd;
}

static void handle_close_socket(void *p) { (void)xdkc_net_close(p); }

int main(void) {
    xrt_runtime_init();

    int port = 0;
    int lfd = listen_local(&port);

    /* 已过期 deadline：Context 取消语义（NET-02）。 */
    xrt_context *bg = xrt_context_background();
    xrt_context *dead = xrt_context_with_deadline(bg, xrt_clock_mono_ms() - 1);
    assert(xrt_context_cancelled(dead) == 1);

    int32_t code = -1;
    void *c = xdkc_socket_connect_async(dead, "127.0.0.1", 9, port, &code);
    assert(c == NULL && code == 3); /* Cancelled，不得 Timeout/Io */

    /* 建立真实连接后，取消状态下的 readAsync 必须返回 3。 */
    code = -1;
    void *s = xdkc_net_connect("127.0.0.1", 9, port, &code);
    assert(s != NULL && code == 0);

    char buf[8] = {0};
    int64_t n = xdkc_socket_recv_async(dead, s, buf, sizeof(buf), &code);
    assert(n == -1 && code == 3);

    /* InvalidArgument（NET-05）：不静默成功。 */
    code = 0;
    assert(xdkc_net_read(NULL, NULL, 0, &code) == -1 && code == 1);

    /* 资源关闭：句柄 close 幂等，native 置空（S3 §18）。 */
    xrt_handle *h = xrt_handle_new(s, handle_close_socket, "Socket");
    assert(h != NULL);
    assert(xrt_handle_close(h) == 0);
    assert(xrt_handle_close(h) == 0);
    assert(xrt_handle_native(h) == NULL);
    xrt_release(h);

    close(lfd);
    xrt_release(dead);
    xrt_release(bg);
    printf("qa net cancel/error/close passed (code=3 cancelled, code=1 invalid, close idempotent)\n");
    return 0;
}
