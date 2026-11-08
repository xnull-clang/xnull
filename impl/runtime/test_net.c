/* test_net.c — S6-09/ADR-009：socket plain/Async + net.http 最小面 */
#define _POSIX_C_SOURCE 200809L
#include "xrt.h"

#include <arpa/inet.h>
#include <assert.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

void *xdkc_socket_connect(const char *host, size_t hlen, int32_t port, int32_t *code);
int64_t xdkc_socket_send(void *sock, const void *buf, size_t n, int32_t *code);
int64_t xdkc_socket_recv(void *sock, void *buf, size_t cap, int32_t *code);
int32_t xdkc_socket_close(void *sock);
void *xdkc_socket_connect_async(xrt_context *ctx, const char *host, size_t hlen, int32_t port, int32_t *code);
int64_t xdkc_socket_send_async(xrt_context *ctx, void *sock, const void *buf, size_t n, int32_t *code);
int64_t xdkc_socket_recv_async(xrt_context *ctx, void *sock, void *buf, size_t cap, int32_t *code);

void *xdkc_http_request(const char *method, size_t mlen, const char *host, size_t hlen,
                        int32_t port, const char *path, size_t plen,
                        const void *body, size_t blen, int32_t *code);
void *xdkc_http_request_async(xrt_context *ctx, const char *method, size_t mlen,
                              const char *host, size_t hlen, int32_t port,
                              const char *path, size_t plen,
                              const void *body, size_t blen, int32_t *code);
int32_t xdkc_http_status(void *resp);
const char *xdkc_http_body(void *resp, size_t *out_len);
int32_t xdkc_http_response_close(void *resp);

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

static pid_t server_once(int lfd, const char *response, int delay_ms) {
    pid_t pid = fork();
    assert(pid >= 0);
    if (pid == 0) {
        int c = accept(lfd, NULL, NULL);
        if (c < 0) {
            _exit(0);
        }
        char buf[1024];
        (void)read(c, buf, sizeof(buf));
        if (delay_ms > 0) {
            struct timespec ts = {delay_ms / 1000, (long)(delay_ms % 1000) * 1000000L};
            nanosleep(&ts, NULL);
        }
        (void)write(c, response, strlen(response));
        close(c);
        _exit(0);
    }
    return pid;
}

static void handle_close_socket(void *p) { (void)xdkc_socket_close(p); }

static void test_plain_socket(void) {
    int port = 0;
    int lfd = listen_local(&port);
    pid_t pid = server_once(lfd, "pong", 0);
    close(lfd);

    int32_t code = -1;
    void *s = xdkc_socket_connect("127.0.0.1", 9, port, &code);
    assert(s != NULL && code == 0);
    assert(xdkc_socket_send(s, "ping", 4, &code) == 4 && code == 0);
    char buf[8] = {0};
    int64_t n = xdkc_socket_recv(s, buf, sizeof(buf), &code);
    assert(code == 0 && n == 4 && memcmp(buf, "pong", 4) == 0);

    /* close 必达/幂等由句柄层保证 */
    xrt_handle *h = xrt_handle_new(s, handle_close_socket, "Socket");
    assert(xrt_handle_close(h) == 0);
    assert(xrt_handle_close(h) == 0);
    assert(xrt_handle_native(h) == NULL);
    xrt_release(h);
    int st = 0;
    assert(waitpid(pid, &st, 0) == pid);
}

static void test_async_socket(void) {
    int port = 0;
    int lfd = listen_local(&port);
    pid_t pid = server_once(lfd, "async", 0);
    close(lfd);

    xrt_context *ctx = xrt_context_background();
    int32_t code = -1;
    void *s = xdkc_socket_connect_async(ctx, "127.0.0.1", 9, port, &code);
    assert(s != NULL && code == 0);
    assert(xdkc_socket_send_async(ctx, s, "ping", 4, &code) == 4 && code == 0);
    char buf[8] = {0};
    int64_t n = xdkc_socket_recv_async(ctx, s, buf, sizeof(buf), &code);
    assert(code == 0 && n == 5 && memcmp(buf, "async", 5) == 0);
    (void)xdkc_socket_close(s);
    xrt_release(ctx);
    int st = 0;
    assert(waitpid(pid, &st, 0) == pid);
}

static void test_async_cancel(void) {
    int port = 0;
    int lfd = listen_local(&port);
    pid_t pid = server_once(lfd, "late", 200);
    close(lfd);

    xrt_context *ctx = xrt_context_background();
    int32_t code = -1;
    void *s = xdkc_socket_connect_async(ctx, "127.0.0.1", 9, port, &code);
    assert(s != NULL && code == 0);
    xrt_context *dead = xrt_context_with_deadline(xrt_context_background(),
                                                  xrt_clock_mono_ms() - 1);
    char buf[8] = {0};
    assert(xdkc_socket_recv_async(dead, s, buf, sizeof(buf), &code) == -1);
    assert(code == 3); /* Cancelled */
    (void)xdkc_socket_close(s);
    xrt_release(dead);
    xrt_release(ctx);
    int st = 0;
    assert(waitpid(pid, &st, 0) == pid);
}

static void test_errors(void) {
    int32_t code = -1;
    assert(xdkc_socket_connect(NULL, 0, 0, &code) == NULL && code == 1); /* InvalidArgument */

    int port = 0;
    int lfd = listen_local(&port);
    close(lfd);
    code = 0;
    void *s = xdkc_socket_connect("127.0.0.1", 9, port, &code);
    assert(s == NULL && code != 0); /* Io/Unavailable；不允许静默成功 */
}

static void test_http(void) {
    int port = 0;
    int lfd = listen_local(&port);
    pid_t pid = server_once(lfd,
        "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nhi", 0);
    close(lfd);

    int32_t code = -1;
    void *resp = xdkc_http_request("GET", 3, "127.0.0.1", 9, port, "/", 1, NULL, 0, &code);
    assert(resp != NULL && code == 0);
    assert(xdkc_http_status(resp) == 200);
    size_t n = 0;
    const char *body = xdkc_http_body(resp, &n);
    assert(body != NULL && n == 2 && memcmp(body, "hi", 2) == 0);
    assert(xdkc_http_response_close(resp) == 0);
    int st = 0;
    assert(waitpid(pid, &st, 0) == pid);
}

static void test_http_async_cancel(void) {
    int port = 0;
    int lfd = listen_local(&port);
    pid_t pid = server_once(lfd, "HTTP/1.1 200 OK\r\n\r\nx", 200);
    close(lfd);

    xrt_context *dead = xrt_context_with_deadline(xrt_context_background(),
                                                  xrt_clock_mono_ms() - 1);
    int32_t code = -1;
    void *resp = xdkc_http_request_async(dead, "GET", 3, "127.0.0.1", 9, port,
                                         "/", 1, NULL, 0, &code);
    assert(resp == NULL && code == 3); /* Cancelled */
    xrt_release(dead);
    (void)kill(pid, SIGKILL); /* 取消发生在连接前：子进程可能仍在 accept */
    int st = 0;
    assert(waitpid(pid, &st, 0) == pid);
}

int main(void) {
    xrt_runtime_init();
    test_plain_socket();
    test_async_socket();
    test_async_cancel();
    test_errors();
    test_http();
    test_http_async_cancel();
    printf("net tests passed (socket plain/async/cancel/close + http status/body)\n");
    return 0;
}
