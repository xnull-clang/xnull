/* rt_std_net.c —— xdk.net C 原语（S6-09 / S6 §4.7）
 *
 * 合同：
 *   - Socket/Listener 为 POSIX fd，经 xrt_handle 包装；close 幂等（S3 §18）。
 *   - plain 形态同步阻塞；异步形态由 codegen 在调用点做 Context 取消检查后调用
 *     同一原语（调度器切片接管后替换实现，符号/签名不变）。
 *   - 错误码：0 成功、1 参数非法、2 IO 失败、3 连接不存在、4 超时。
 *   - HTTP 只实现最小请求/响应（GET/POST，http://，Content-Length 或读到 EOF）。
 */
#define _POSIX_C_SOURCE 200809L
#include "xrt.h"

#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

static int net_errno_kind(int e) {
    switch (e) {
    case EINVAL:
        return 1;
    case ETIMEDOUT:
        return 4;
    case ECONNREFUSED:
    case EHOSTUNREACH:
    case ENETUNREACH:
        return 3;
    default:
        return 2;
    }
}

static char *net_host_dup(const char *host, size_t len) {
    if (host == NULL || len == 0 || memchr(host, 0, len) != NULL) {
        return NULL;
    }
    char *p = (char *)malloc(len + 1);
    if (p == NULL) {
        return NULL;
    }
    memcpy(p, host, len);
    p[len] = '\0';
    return p;
}

/* 连接/监听共用的地址解析；host 为空或 "0.0.0.0" 时 bind 到任意地址。 */
static int net_resolve(const char *host, size_t hlen, int32_t port, int listen_mode,
                       struct sockaddr_storage *out, socklen_t *outlen) {
    char portbuf[16];
    snprintf(portbuf, sizeof(portbuf), "%d", (int)port);
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_flags = listen_mode ? AI_PASSIVE : 0;
    const char *node = NULL;
    char *hostdup = NULL;
    if (!(hlen == 0 || (hlen == 7 && memcmp(host, "0.0.0.0", 7) == 0))) {
        hostdup = net_host_dup(host, hlen);
        if (hostdup == NULL) {
            return 1;
        }
        node = hostdup;
    }
    struct addrinfo *ai = NULL;
    int rc = getaddrinfo(node, portbuf, &hints, &ai);
    free(hostdup);
    if (rc != 0 || ai == NULL) {
        return 3;
    }
    memcpy(out, ai->ai_addr, ai->ai_addrlen);
    *outlen = (socklen_t)ai->ai_addrlen;
    freeaddrinfo(ai);
    return 0;
}

void *xdkc_net_connect(const char *host, size_t hlen, int32_t port, int32_t *kind) {
    if (kind == NULL) {
        xrt_fatal("socketConnect：错误码出参为空（S6 §4.7）");
    }
    *kind = 0;
    struct sockaddr_storage addr;
    socklen_t alen = 0;
    if ((*kind = net_resolve(host, hlen, port, 0, &addr, &alen)) != 0) {
        return NULL;
    }
    int fd = socket(addr.ss_family, SOCK_STREAM, 0);
    if (fd < 0) {
        *kind = net_errno_kind(errno);
        return NULL;
    }
    if (connect(fd, (struct sockaddr *)&addr, alen) != 0) {
        *kind = net_errno_kind(errno);
        close(fd);
        return NULL;
    }
    return (void *)(intptr_t)fd;
}

void *xdkc_net_listen(const char *host, size_t hlen, int32_t port, int32_t *kind) {
    if (kind == NULL) {
        xrt_fatal("socketListen：错误码出参为空（S6 §4.7）");
    }
    *kind = 0;
    struct sockaddr_storage addr;
    socklen_t alen = 0;
    if ((*kind = net_resolve(host, hlen, port, 1, &addr, &alen)) != 0) {
        return NULL;
    }
    int fd = socket(addr.ss_family, SOCK_STREAM, 0);
    if (fd < 0) {
        *kind = net_errno_kind(errno);
        return NULL;
    }
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    if (bind(fd, (struct sockaddr *)&addr, alen) != 0 || listen(fd, 16) != 0) {
        *kind = net_errno_kind(errno);
        close(fd);
        return NULL;
    }
    return (void *)(intptr_t)fd;
}

void *xdkc_net_accept(void *listener, int32_t *kind) {
    if (kind == NULL) {
        xrt_fatal("socketAccept：错误码出参为空（S6 §4.7）");
    }
    *kind = 0;
    if (listener == NULL) {
        *kind = 1;
        return NULL;
    }
    int fd = accept((int)(intptr_t)listener, NULL, NULL);
    if (fd < 0) {
        *kind = net_errno_kind(errno);
        return NULL;
    }
    return (void *)(intptr_t)fd;
}

int64_t xdkc_net_read(void *sock, void *buf, size_t cap, int32_t *kind) {
    if (kind == NULL) {
        xrt_fatal("socketRead：错误码出参为空（S6 §4.7）");
    }
    *kind = 0;
    if (sock == NULL) {
        *kind = 1;
        return -1;
    }
    if (cap > 0 && buf == NULL) {
        *kind = 1;
        return -1;
    }
    ssize_t n = recv((int)(intptr_t)sock, buf, cap, 0);
    if (n < 0) {
        *kind = net_errno_kind(errno);
        return -1;
    }
    return (int64_t)n;
}

int32_t xdkc_net_write(void *sock, const void *buf, size_t n) {
    if (sock == NULL) {
        return 1;
    }
    if (n > 0 && buf == NULL) {
        return 1;
    }
    const unsigned char *p = (const unsigned char *)buf;
    size_t off = 0;
    while (off < n) {
        ssize_t w = send((int)(intptr_t)sock, p + off, n - off, 0);
        if (w <= 0) {
            return net_errno_kind(errno);
        }
        off += (size_t)w;
    }
    return 0;
}

int32_t xdkc_net_close(void *sock) {
    if (sock == NULL) {
        return 0; /* 幂等 */
    }
    return close((int)(intptr_t)sock) == 0 ? 0 : 2;
}

/* ---- HTTP ---- */

static int http_parse_url(const char *url, size_t len, char *host, size_t hostcap,
                          char *port, size_t portcap, char *path, size_t pathcap) {
    if (url == NULL || len < 8 || memcmp(url, "http://", 7) != 0) {
        return 1;
    }
    const char *p = url + 7;
    const char *end = url + len;
    const char *slash = memchr(p, '/', (size_t)(end - p));
    const char *hostend = slash ? slash : end;
    const char *colon = memchr(p, ':', (size_t)(hostend - p));
    if (colon != NULL) {
        size_t hl = (size_t)(colon - p);
        if (hl + 1 > hostcap) {
            return 1;
        }
        memcpy(host, p, hl);
        host[hl] = '\0';
        size_t pl = (size_t)(hostend - colon - 1);
        if (pl + 1 > portcap) {
            return 1;
        }
        memcpy(port, colon + 1, pl);
        port[pl] = '\0';
    } else {
        size_t hl = (size_t)(hostend - p);
        if (hl + 1 > hostcap) {
            return 1;
        }
        memcpy(host, p, hl);
        host[hl] = '\0';
        snprintf(port, portcap, "80");
    }
    if (slash != NULL) {
        size_t pl = (size_t)(end - slash);
        if (pl + 1 > pathcap) {
            return 1;
        }
        memcpy(path, slash, pl);
        path[pl] = '\0';
    } else {
        snprintf(path, pathcap, "/");
    }
    return 0;
}

static xrt_bytes_buf *http_request(const char *url, size_t ulen, const void *body, size_t blen,
                                   const char *method, int32_t *kind) {
    *kind = 0;
    char host[256], port[16], path[1024];
    if (http_parse_url(url, ulen, host, sizeof(host), port, sizeof(port), path, sizeof(path)) != 0) {
        *kind = 1;
        return NULL;
    }
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    struct addrinfo *ai = NULL;
    if (getaddrinfo(host, port, &hints, &ai) != 0 || ai == NULL) {
        *kind = 3;
        return NULL;
    }
    int fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
    if (fd < 0 || connect(fd, ai->ai_addr, ai->ai_addrlen) != 0) {
        *kind = net_errno_kind(errno);
        if (fd >= 0) {
            close(fd);
        }
        freeaddrinfo(ai);
        return NULL;
    }
    freeaddrinfo(ai);

    char head[2048];
    int hn = snprintf(head, sizeof(head),
                      "%s %s HTTP/1.1\r\nHost: %s:%s\r\nConnection: close\r\n"
                      "Content-Length: %zu\r\n\r\n",
                      method, path, host, port, blen);
    if (hn < 0 || (size_t)hn >= sizeof(head)) {
        *kind = 1;
        close(fd);
        return NULL;
    }
    if (xdkc_net_write((void *)(intptr_t)fd, head, (size_t)hn) != 0 ||
        (blen > 0 && xdkc_net_write((void *)(intptr_t)fd, body, blen) != 0)) {
        *kind = 2;
        close(fd);
        return NULL;
    }

    size_t cap = 8192, len = 0;
    unsigned char *buf = (unsigned char *)malloc(cap);
    if (buf == NULL) {
        *kind = 2;
        close(fd);
        return NULL;
    }
    for (;;) {
        if (len == cap) {
            size_t ncap = cap * 2;
            unsigned char *nb = (unsigned char *)realloc(buf, ncap);
            if (nb == NULL) {
                free(buf);
                *kind = 2;
                close(fd);
                return NULL;
            }
            buf = nb;
            cap = ncap;
        }
        ssize_t n = recv(fd, buf + len, cap - len, 0);
        if (n < 0) {
            free(buf);
            *kind = net_errno_kind(errno);
            close(fd);
            return NULL;
        }
        if (n == 0) {
            break;
        }
        len += (size_t)n;
    }
    close(fd);

    /* 剥离响应头；非 2xx → NotFound/IO（最小实现）。 */
    unsigned char *sep = NULL;
    for (size_t i = 0; i + 3 < len; i++) {
        if (buf[i] == '\r' && buf[i + 1] == '\n' && buf[i + 2] == '\r' && buf[i + 3] == '\n') {
            sep = buf + i + 4;
            break;
        }
    }
    if (sep == NULL || len < 12 || memcmp(buf, "HTTP/", 5) != 0) {
        free(buf);
        *kind = 2;
        return NULL;
    }
    int status = atoi((const char *)buf + 9);
    if (status < 200 || status >= 300) {
        free(buf);
        *kind = status == 404 ? 3 : 2;
        return NULL;
    }
    size_t bodylen = len - (size_t)(sep - buf);
    xrt_bytes_buf *out = xrt_bytes_from_c(sep, bodylen);
    free(buf);
    return out;
}

xrt_bytes_buf *xdkc_http_get(const char *url, size_t len, int32_t *kind) {
    if (kind == NULL) {
        xrt_fatal("httpGet：错误码出参为空（S6 §4.7）");
    }
    return http_request(url, len, NULL, 0, "GET", kind);
}

xrt_bytes_buf *xdkc_http_post(const char *url, size_t ulen, const void *body, size_t blen, int32_t *kind) {
    if (kind == NULL) {
        xrt_fatal("httpPost：错误码出参为空（S6 §4.7）");
    }
    return http_request(url, ulen, body, blen, "POST", kind);
}

/* ---- S6-09 兼容别名（早期 C 名；E4 绑定面使用 xdkc_net_*） ----
 * QA XDK-09b：旧测试/绑定若引用 xdkc_socket_*，链接不再缺符号。
 * Async 别名只在调用前检查 Context；真正的取消检查由 codegen 调用点负责。
 */
void *xdkc_socket_connect(const char *host, size_t hlen, int32_t port, int32_t *code) {
    return xdkc_net_connect(host, hlen, port, code);
}

int64_t xdkc_socket_send(void *sock, const void *buf, size_t n, int32_t *code) {
    int32_t rc = xdkc_net_write(sock, buf, n);
    if (code != NULL) {
        *code = rc;
    }
    return rc == 0 ? (int64_t)n : -1;
}

int64_t xdkc_socket_recv(void *sock, void *buf, size_t cap, int32_t *code) {
    return xdkc_net_read(sock, buf, cap, code);
}

int32_t xdkc_socket_close(void *sock) {
    return xdkc_net_close(sock);
}

static int net_ctx_cancelled(xrt_context *ctx) {
    return ctx != NULL && xrt_context_check_cancel(ctx) == XRT_ERR_CANCELLED;
}

void *xdkc_socket_connect_async(xrt_context *ctx, const char *host, size_t hlen,
                                int32_t port, int32_t *code) {
    if (net_ctx_cancelled(ctx)) {
        if (code != NULL) {
            *code = 3;
        }
        return NULL;
    }
    return xdkc_net_connect(host, hlen, port, code);
}

int64_t xdkc_socket_send_async(xrt_context *ctx, void *sock, const void *buf,
                               size_t n, int32_t *code) {
    if (net_ctx_cancelled(ctx)) {
        if (code != NULL) {
            *code = 3;
        }
        return -1;
    }
    return xdkc_socket_send(sock, buf, n, code);
}

int64_t xdkc_socket_recv_async(xrt_context *ctx, void *sock, void *buf,
                               size_t cap, int32_t *code) {
    if (net_ctx_cancelled(ctx)) {
        if (code != NULL) {
            *code = 3;
        }
        return -1;
    }
    return xdkc_net_read(sock, buf, cap, code);
}
