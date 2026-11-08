/* test_net.c — S6-09 / XDK-09b：net 运行时链接与最小行为
 *
 * 使用 E4 绑定面声明的 C 名：xdkc_net_{connect,listen,accept,read,write,close}
 * 与 xdkc_http_{get,post}（Bytes 返回）。本地回环服务验证 plain socket、
 * close 句柄幂等、错误码与 HTTP body；Async 由 codegen 调用点做 Context 检查。
 */
#define _POSIX_C_SOURCE 200809L
#include "xrt.h"

#include <arpa/inet.h>
#include <assert.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

void *xdkc_net_connect(const char *host, size_t hlen, int32_t port, int32_t *code);
int64_t xdkc_net_read(void *sock, void *buf, size_t cap, int32_t *code);
int32_t xdkc_net_write(void *sock, const void *buf, size_t n);
int32_t xdkc_net_close(void *sock);
xrt_bytes_buf *xdkc_http_get(const char *url, size_t len, int32_t *code);
xrt_bytes_buf *xdkc_http_post(const char *url, size_t ulen, const void *body, size_t blen, int32_t *code);

static int listen_local(int *port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    assert(fd >= 0);
    int one = 1;
    assert(setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one)) == 0);
    struct sockaddr_in a;
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(0x7f000001);
    a.sin_port = 0;
    assert(bind(fd, (struct sockaddr *)&a, sizeof(a)) == 0);
    assert(listen(fd, 4) == 0);
    socklen_t len = sizeof(a);
    assert(getsockname(fd, (struct sockaddr *)&a, &len) == 0);
    *port = ntohs(a.sin_port);
    return fd;
}

static pid_t server_once(int lfd, const char *response) {
    pid_t pid = fork();
    assert(pid >= 0);
    if (pid == 0) {
        int c = accept(lfd, NULL, NULL);
        if (c < 0) {
            _exit(0);
        }
        char buf[1024];
        (void)read(c, buf, sizeof(buf));
        (void)write(c, response, strlen(response));
        close(c);
        _exit(0);
    }
    return pid;
}

static void handle_close_socket(void *p) { (void)xdkc_net_close(p); }

static void test_plain_socket(void) {
    int port = 0;
    int lfd = listen_local(&port);
    pid_t pid = server_once(lfd, "pong");
    close(lfd);

    int32_t code = -1;
    void *s = xdkc_net_connect("127.0.0.1", 9, port, &code);
    assert(s != NULL && code == 0);
    assert(xdkc_net_write(s, "ping", 4) == 0);
    char buf[8] = {0};
    int64_t n = xdkc_net_read(s, buf, sizeof(buf), &code);
    assert(code == 0 && n == 4 && memcmp(buf, "pong", 4) == 0);

    xrt_handle *h = xrt_handle_new(s, handle_close_socket, "Socket");
    assert(xrt_handle_close(h) == 0);
    assert(xrt_handle_close(h) == 0); /* 句柄层幂等 */
    assert(xrt_handle_native(h) == NULL);
    xrt_release(h);
    int st = 0;
    assert(waitpid(pid, &st, 0) == pid);
}

static void test_errors(void) {
    int port = 0;
    int lfd = listen_local(&port);
    close(lfd);
    int32_t code = 0;
    void *s = xdkc_net_connect("127.0.0.1", 9, port, &code);
    assert(s == NULL && code != 0); /* 不允许静默成功 */
    assert(xdkc_net_read(NULL, NULL, 0, &code) == -1 && code == 1);
}

static void test_http_get(void) {
    int port = 0;
    int lfd = listen_local(&port);
    pid_t pid = server_once(lfd,
        "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nhi");
    close(lfd);

    char url[128];
    int n = snprintf(url, sizeof(url), "http://127.0.0.1:%d/", port);
    assert(n > 0);
    int32_t code = -1;
    xrt_bytes_buf *b = xdkc_http_get(url, (size_t)n, &code);
    assert(b != NULL && code == 0);
    assert(xrt_bytes_len(b) == 2 && memcmp(xrt_bytes_data(b), "hi", 2) == 0);
    xrt_release(b);
    int st = 0;
    assert(waitpid(pid, &st, 0) == pid);
}

static void test_http_not_found(void) {
    int port = 0;
    int lfd = listen_local(&port);
    pid_t pid = server_once(lfd,
        "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
    close(lfd);

    char url[128];
    int n = snprintf(url, sizeof(url), "http://127.0.0.1:%d/missing", port);
    assert(n > 0);
    int32_t code = -1;
    xrt_bytes_buf *b = xdkc_http_get(url, (size_t)n, &code);
    assert(b == NULL && code == 3); /* NotFound */
    int st = 0;
    assert(waitpid(pid, &st, 0) == pid);
}

static void test_http_post(void) {
    int port = 0;
    int lfd = listen_local(&port);
    pid_t pid = server_once(lfd,
        "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok");
    close(lfd);

    char url[128];
    int n = snprintf(url, sizeof(url), "http://127.0.0.1:%d/submit", port);
    assert(n > 0);
    int32_t code = -1;
    xrt_bytes_buf *b = xdkc_http_post(url, (size_t)n, "x=1", 3, &code);
    assert(b != NULL && code == 0);
    assert(xrt_bytes_len(b) == 2 && memcmp(xrt_bytes_data(b), "ok", 2) == 0);
    xrt_release(b);
    int st = 0;
    assert(waitpid(pid, &st, 0) == pid);
}

int main(void) {
    xrt_runtime_init();
    test_plain_socket();
    test_errors();
    test_http_get();
    test_http_not_found();
    test_http_post();
    printf("net tests passed (socket plain/close + http get/post/status)\n");
    return 0;
}
