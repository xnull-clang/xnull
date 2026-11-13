/* rt_std_net.c — S6-09/ADR-009：xdk.net 运行时原语（socket plain/Async + net.http 最小面）
 *
 * 错误码（与 bindings 的 errorMap 对齐；XPD/ErrorKind 映射由绑定层完成）：
 *   0 ok / 1 InvalidArgument / 2 Io / 3 Cancelled / 4 Timeout / 5 Unavailable
 *
 * Async 形态（xrt_context * 首参）使用非阻塞 fd + poll 5ms 轮询：
 *   - 取消返回 code=3，不把缓冲区交给后台线程（无 UAF/悬挂写）；
 *   - 不做后台重试；取消后调用方关闭句柄即可。
 *
 * 句柄合同（S3 §18）：socket/response 由 xrt_handle 包装，close 显式；
 *   xdkc_*_close 只应由句柄 close_fn 调用一次；句柄层保证幂等。
 */
#define _POSIX_C_SOURCE 200809L

#include "rt.h"
#include "xrt.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

enum {
    NET_OK = 0,
    NET_INVALID = 1,
    NET_IO = 2,
    NET_CANCELLED = 3,
    NET_TIMEOUT = 4,
    NET_UNAVAILABLE = 5
};

typedef struct {
    int fd;
    int closed;
} net_socket;

typedef struct {
    int    status;
    char  *body;
    size_t len;
} net_http_response;

static void set_nonblock(int fd) {
    int fl = fcntl(fd, F_GETFL, 0);
    if (fl >= 0) {
        (void)fcntl(fd, F_SETFL, fl | O_NONBLOCK);
    }
}

static int context_cancelled(xrt_context *ctx) {
    return ctx != NULL && xrt_context_check_cancel(ctx) == XRT_ERR_CANCELLED;
}

/* 等待 fd 就绪；5ms 轮询上下文取消。0=ready，其它=错误码。 */
static int wait_fd(int fd, short events, xrt_context *ctx) {
    for (;;) {
        if (context_cancelled(ctx)) {
            return NET_CANCELLED;
        }
        struct pollfd p;
        p.fd = fd;
        p.events = events;
        p.revents = 0;
        int rc = poll(&p, 1, 5);
        if (rc < 0) {
            if (errno == EINTR) {
                continue;
            }
            return NET_IO;
        }
        if (rc == 0) {
            continue;
        }
        if (p.revents & POLLNVAL) {
            return NET_INVALID;
        }
        if (p.revents & (POLLERR | POLLHUP)) {
            if (p.revents & events) {
                return NET_OK;
            }
            return NET_IO;
        }
        if (p.revents & events) {
            return NET_OK;
        }
    }
}

static void *connect_socket(const char *host, size_t hlen, int32_t port,
                            xrt_context *ctx, int32_t *code) {
    if (code != NULL) {
        *code = NET_OK;
    }
    if (host == NULL || hlen == 0 || port <= 0 || port > 65535) {
        if (code != NULL) {
            *code = NET_INVALID;
        }
        return NULL;
    }
    char *h = malloc(hlen + 1);
    if (h == NULL) {
        if (code != NULL) {
            *code = NET_IO;
        }
        return NULL;
    }
    memcpy(h, host, hlen);
    h[hlen] = 0;

    char portstr[16];
    snprintf(portstr, sizeof(portstr), "%d", (int)port);
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    struct addrinfo *res = NULL;
    int gai = getaddrinfo(h, portstr, &hints, &res);
    free(h);
    if (gai != 0) {
        if (code != NULL) {
            *code = NET_UNAVAILABLE;
        }
        return NULL;
    }

    int fd = -1;
    int last = NET_IO;
    for (struct addrinfo *ai = res; ai != NULL; ai = ai->ai_next) {
        fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0) {
            continue;
        }
        if (ctx != NULL) {
            set_nonblock(fd);
            if (connect(fd, ai->ai_addr, ai->ai_addrlen) != 0) {
                if (errno != EINPROGRESS) {
                    close(fd);
                    fd = -1;
                    continue;
                }
                int w = wait_fd(fd, POLLOUT, ctx);
                if (w != NET_OK) {
                    last = w;
                    close(fd);
                    fd = -1;
                    continue;
                }
                int err = 0;
                socklen_t elen = sizeof(err);
                if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &elen) != 0 || err != 0) {
                    last = NET_IO;
                    close(fd);
                    fd = -1;
                    continue;
                }
            }
        } else if (connect(fd, ai->ai_addr, ai->ai_addrlen) != 0) {
            close(fd);
            fd = -1;
            continue;
        }
        break;
    }
    freeaddrinfo(res);
    if (fd < 0) {
        if (code != NULL) {
            *code = last;
        }
        return NULL;
    }
    net_socket *s = malloc(sizeof(*s));
    if (s == NULL) {
        close(fd);
        if (code != NULL) {
            *code = NET_IO;
        }
        return NULL;
    }
    s->fd = fd;
    s->closed = 0;
    return s;
}

static int64_t send_socket(net_socket *s, const void *buf, size_t n,
                           xrt_context *ctx, int32_t *code) {
    if (code != NULL) {
        *code = NET_OK;
    }
    if (s == NULL || s->closed || (buf == NULL && n > 0)) {
        if (code != NULL) {
            *code = NET_INVALID;
        }
        return -1;
    }
    size_t off = 0;
    while (off < n) {
        if (context_cancelled(ctx)) {
            if (code != NULL) {
                *code = NET_CANCELLED;
            }
            return -1;
        }
        if (ctx != NULL) {
            int w = wait_fd(s->fd, POLLOUT, ctx);
            if (w != NET_OK) {
                if (code != NULL) {
                    *code = w;
                }
                return -1;
            }
        }
        ssize_t w = send(s->fd, (const char *)buf + off, n - off, 0);
        if (w < 0) {
            if (errno == EINTR) {
                continue;
            }
            if (ctx != NULL && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                continue;
            }
            if (code != NULL) {
                *code = NET_IO;
            }
            return -1;
        }
        off += (size_t)w;
    }
    return (int64_t)off;
}

static int64_t recv_socket(net_socket *s, void *buf, size_t cap,
                           xrt_context *ctx, int32_t *code) {
    if (code != NULL) {
        *code = NET_OK;
    }
    if (s == NULL || s->closed || (buf == NULL && cap > 0) || cap == 0) {
        if (code != NULL) {
            *code = NET_INVALID;
        }
        return -1;
    }
    for (;;) {
        if (context_cancelled(ctx)) {
            if (code != NULL) {
                *code = NET_CANCELLED;
            }
            return -1;
        }
        if (ctx != NULL) {
            int w = wait_fd(s->fd, POLLIN, ctx);
            if (w != NET_OK) {
                if (code != NULL) {
                    *code = w;
                }
                return -1;
            }
        }
        ssize_t r = recv(s->fd, buf, cap, 0);
        if (r < 0) {
            if (errno == EINTR) {
                continue;
            }
            if (ctx != NULL && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                continue;
            }
            if (code != NULL) {
                *code = NET_IO;
            }
            return -1;
        }
        return (int64_t)r; /* 0 = EOF */
    }
}

static int32_t close_socket(net_socket *s) {
    if (s == NULL) {
        return 0;
    }
    if (!s->closed) {
        (void)close(s->fd);
        s->closed = 1;
    }
    free(s);
    return 0;
}

/* ---- plain API ---- */

void *xdkc_socket_connect(const char *host, size_t hlen, int32_t port, int32_t *code) {
    return connect_socket(host, hlen, port, NULL, code);
}

int64_t xdkc_socket_send(void *sock, const void *buf, size_t n, int32_t *code) {
    return send_socket((net_socket *)sock, buf, n, NULL, code);
}

int64_t xdkc_socket_recv(void *sock, void *buf, size_t cap, int32_t *code) {
    return recv_socket((net_socket *)sock, buf, cap, NULL, code);
}

int32_t xdkc_socket_close(void *sock) {
    return close_socket((net_socket *)sock);
}

/* ---- Async API（Context 首参；取消返回 code=3） ---- */

void *xdkc_socket_connect_async(xrt_context *ctx, const char *host, size_t hlen,
                                int32_t port, int32_t *code) {
    return connect_socket(host, hlen, port, ctx, code);
}

int64_t xdkc_socket_send_async(xrt_context *ctx, void *sock, const void *buf,
                               size_t n, int32_t *code) {
    return send_socket((net_socket *)sock, buf, n, ctx, code);
}

int64_t xdkc_socket_recv_async(xrt_context *ctx, void *sock, void *buf,
                               size_t cap, int32_t *code) {
    return recv_socket((net_socket *)sock, buf, cap, ctx, code);
}

/* ---- net.http 最小面 ---- */

static char *find_ci(char *start, char *end, const char *needle) {
    size_t n = strlen(needle);
    for (char *p = start; p + n <= end; p++) {
        if (strncasecmp(p, needle, n) == 0) {
            return p;
        }
    }
    return NULL;
}

static char *http_build_request(const char *method, size_t mlen,
                                const char *host, size_t hlen,
                                const char *path, size_t plen,
                                const void *body, size_t blen, size_t *out_len) {
    size_t cap = mlen + plen + hlen + blen + 128;
    char *req = malloc(cap);
    if (req == NULL) {
        return NULL;
    }
    int n = snprintf(req, cap,
                     "%.*s %.*s HTTP/1.1\r\n"
                     "Host: %.*s\r\n"
                     "Connection: close\r\n"
                     "Content-Length: %zu\r\n\r\n",
                     (int)mlen, method, (int)plen, path, (int)hlen, host, blen);
    if (n < 0 || (size_t)n + blen > cap) {
        free(req);
        return NULL;
    }
    if (blen > 0 && body != NULL) {
        memcpy(req + n, body, blen);
        n += (int)blen;
    }
    *out_len = (size_t)n;
    return req;
}

static void *http_request(const char *method, size_t mlen,
                          const char *host, size_t hlen, int32_t port,
                          const char *path, size_t plen,
                          const void *body, size_t blen,
                          xrt_context *ctx, int32_t *code) {
    if (code != NULL) {
        *code = NET_OK;
    }
    if (method == NULL || mlen == 0 || path == NULL || plen == 0) {
        if (code != NULL) {
            *code = NET_INVALID;
        }
        return NULL;
    }
    size_t req_len = 0;
    char *req = http_build_request(method, mlen, host, hlen, path, plen, body, blen, &req_len);
    if (req == NULL) {
        if (code != NULL) {
            *code = NET_IO;
        }
        return NULL;
    }
    net_socket *s = connect_socket(host, hlen, port, ctx, code);
    if (s == NULL) {
        free(req);
        return NULL;
    }
    if (send_socket(s, req, req_len, ctx, code) < 0) {
        free(req);
        close_socket(s);
        return NULL;
    }
    free(req);

    size_t cap = 4096;
    size_t len = 0;
    char *raw = malloc(cap);
    if (raw == NULL) {
        close_socket(s);
        if (code != NULL) {
            *code = NET_IO;
        }
        return NULL;
    }
    for (;;) {
        if (len + 1024 + 1 > cap) {
            cap *= 2;
            char *nr = realloc(raw, cap);
            if (nr == NULL) {
                free(raw);
                close_socket(s);
                if (code != NULL) {
                    *code = NET_IO;
                }
                return NULL;
            }
            raw = nr;
        }
        int64_t r = recv_socket(s, raw + len, cap - len - 1, ctx, code);
        if (r < 0) {
            free(raw);
            close_socket(s);
            return NULL;
        }
        len += (size_t)r;
        if (r == 0) {
            break;
        }
        /* Content-Length 足够则提前结束；无 CL 时按 EOF（Connection: close）。 */
        char *hdr_end = strstr(raw, "\r\n\r\n");
        if (hdr_end != NULL) {
            size_t hdr_len = (size_t)(hdr_end - raw) + 4;
            char *cl = find_ci(raw, hdr_end, "Content-Length:");
            if (cl != NULL && cl < hdr_end) {
                long want = strtol(cl + 15, NULL, 10);
                if (want >= 0 && len >= hdr_len + (size_t)want) {
                    break;
                }
            }
        }
    }
    close_socket(s);
    raw[len] = 0;
    net_http_response *resp = calloc(1, sizeof(*resp));
    if (resp == NULL) {
        free(raw);
        if (code != NULL) {
            *code = NET_IO;
        }
        return NULL;
    }
    resp->status = 0;
    if (strncmp(raw, "HTTP/", 5) == 0) {
        char *sp = strchr(raw, ' ');
        if (sp != NULL) {
            resp->status = atoi(sp + 1);
        }
    }
    char *hdr_end = strstr(raw, "\r\n\r\n");
    char *body_start = hdr_end != NULL ? hdr_end + 4 : raw + len;
    resp->len = (size_t)(raw + len - body_start);
    resp->body = malloc(resp->len + 1);
    if (resp->body == NULL) {
        free(raw);
        free(resp);
        if (code != NULL) {
            *code = NET_IO;
        }
        return NULL;
    }
    memcpy(resp->body, body_start, resp->len);
    resp->body[resp->len] = 0;
    free(raw);
    if (resp->status <= 0) {
        if (code != NULL) {
            *code = NET_IO;
        }
        free(resp->body);
        free(resp);
        return NULL;
    }
    return resp;
}

void *xdkc_http_request(const char *method, size_t mlen,
                        const char *host, size_t hlen, int32_t port,
                        const char *path, size_t plen,
                        const void *body, size_t blen, int32_t *code) {
    return http_request(method, mlen, host, hlen, port, path, plen, body, blen, NULL, code);
}

void *xdkc_http_request_async(xrt_context *ctx,
                              const char *method, size_t mlen,
                              const char *host, size_t hlen, int32_t port,
                              const char *path, size_t plen,
                              const void *body, size_t blen, int32_t *code) {
    return http_request(method, mlen, host, hlen, port, path, plen, body, blen, ctx, code);
}

int32_t xdkc_http_status(void *resp) {
    return resp == NULL ? 0 : ((net_http_response *)resp)->status;
}

const char *xdkc_http_body(void *resp, size_t *out_len) {
    if (resp == NULL) {
        if (out_len != NULL) {
            *out_len = 0;
        }
        return NULL;
    }
    net_http_response *r = resp;
    if (out_len != NULL) {
        *out_len = r->len;
    }
    return r->body;
}

/* 绑定层 String 返回形态：body 以 NUL 结尾；二进制请用 body+len 访问器。 */
const char *xdkc_http_body_text(void *resp) {
    return resp == NULL ? NULL : ((net_http_response *)resp)->body;
}

int32_t xdkc_http_response_close(void *resp) {
    if (resp != NULL) {
        net_http_response *r = resp;
        free(r->body);
        free(r);
    }
    return 0;
}
/* ---- XDK-09c：codegen 绑定面 C 名（xdkc_net_* / xdkc_http_get|post）----
 * 实现/别名到既有 socket/http 原语；只补链接符号，不改变行为。
 */
void *xdkc_net_connect(const char *host, size_t hlen, int32_t port, int32_t *code) {
    return xdkc_socket_connect(host, hlen, port, code);
}

int64_t xdkc_net_read(void *sock, void *buf, size_t cap, int32_t *code) {
    return xdkc_socket_recv(sock, buf, cap, code);
}

int32_t xdkc_net_write(void *sock, const void *buf, size_t n) {
    int32_t code = 0;
    int64_t w = xdkc_socket_send(sock, buf, n, &code);
    return w < 0 ? (code != 0 ? code : 2) : 0;
}

int32_t xdkc_net_close(void *sock) {
    return xdkc_socket_close(sock);
}

static int parse_http_url(const char *url, size_t len,
                          char **host, size_t *hlen, int32_t *port,
                          char **path, size_t *plen) {
    if (url == NULL || len < 8 || memcmp(url, "http://", 7) != 0) {
        return -1;
    }
    char *copy = malloc(len + 1);
    if (copy == NULL) {
        return -1;
    }
    memcpy(copy, url, len);
    copy[len] = 0;
    char *p = copy + 7;
    char *slash = strchr(p, '/');
    char *hostend = slash != NULL ? slash : p + strlen(p);
    char *colon = memchr(p, ':', (size_t)(hostend - p));
    *port = 80;
    if (colon != NULL) {
        *port = atoi(colon + 1);
        hostend = colon;
    }
    *hlen = (size_t)(hostend - p);
    *host = malloc(*hlen + 1);
    if (*host == NULL) {
        free(copy);
        return -1;
    }
    memcpy(*host, p, *hlen);
    (*host)[*hlen] = 0;
    const char *pp = slash != NULL ? slash : "/";
    *plen = strlen(pp);
    *path = malloc(*plen + 1);
    if (*path == NULL) {
        free(*host);
        free(copy);
        return -1;
    }
    memcpy(*path, pp, *plen + 1);
    free(copy);
    return 0;
}

static xrt_bytes_buf *http_response_bytes(void *resp, int32_t *code) {
    if (resp == NULL) {
        return NULL;
    }
    int status = xdkc_http_status(resp);
    if (status < 200 || status >= 300) {
        *code = status == 404 ? 3 : 2;
        (void)xdkc_http_response_close(resp);
        return NULL;
    }
    size_t n = 0;
    const char *body = xdkc_http_body(resp, &n);
    xrt_bytes_buf *out = xrt_bytes_from_c(body, n);
    (void)xdkc_http_response_close(resp);
    if (out == NULL) {
        *code = 2;
        return NULL;
    }
    *code = 0;
    return out;
}

xrt_bytes_buf *xdkc_http_get(const char *url, size_t len, int32_t *code) {
    if (code == NULL) {
        xrt_fatal("httpGet：错误码出参为空（S6 §4.7）");
    }
    char *host = NULL, *path = NULL;
    size_t hlen = 0, plen = 0;
    int32_t port = 0;
    if (parse_http_url(url, len, &host, &hlen, &port, &path, &plen) != 0) {
        *code = 1;
        return NULL;
    }
    void *resp = xdkc_http_request("GET", 3, host, hlen, port, path, plen, NULL, 0, code);
    free(host);
    free(path);
    return http_response_bytes(resp, code);
}

xrt_bytes_buf *xdkc_http_post(const char *url, size_t ulen, const void *body, size_t blen, int32_t *code) {
    if (code == NULL) {
        xrt_fatal("httpPost：错误码出参为空（S6 §4.7）");
    }
    char *host = NULL, *path = NULL;
    size_t hlen = 0, plen = 0;
    int32_t port = 0;
    if (parse_http_url(url, ulen, &host, &hlen, &port, &path, &plen) != 0) {
        *code = 1;
        return NULL;
    }
    void *resp = xdkc_http_request("POST", 4, host, hlen, port, path, plen, body, blen, code);
    free(host);
    free(path);
    return http_response_bytes(resp, code);
}


/* ---- XDK 源码层桥（bindings/xdk/net_raw.xfb）----
 * 文本形态 socket/HTTP；句柄以 Int64 流转，错误码经 socketErrorRaw/httpErrorRaw 读取。 */
static int32_t xdk_net_last_error = 0;
static int32_t xdk_http_last_status = 0;
static char   *xdk_net_buf = NULL;
static size_t  xdk_net_buf_cap = 0;

static char *xdk_net_buf_ensure(size_t need) {
    if (need + 1 > xdk_net_buf_cap) {
        size_t cap = need + 1;
        char *p = realloc(xdk_net_buf, cap);
        if (p == NULL) {
            return NULL;
        }
        xdk_net_buf = p;
        xdk_net_buf_cap = cap;
    }
    return xdk_net_buf;
}

int64_t xdkc_p_socket_connect_simple(const char *host, size_t hlen, int32_t port) {
    int32_t code = 0;
    void *s = xdkc_socket_connect(host, hlen, port, &code);
    xdk_net_last_error = code;
    if (code != 0 || s == NULL) {
        return 0;
    }
    return (int64_t)(intptr_t)s;
}

int32_t xdkc_p_socket_error(void) {
    return xdk_net_last_error;
}

int64_t xdkc_p_socket_send_text(int64_t sock, const char *data, size_t len) {
    int32_t code = 0;
    int64_t n = xdkc_socket_send((void *)(intptr_t)sock, data, len, &code);
    xdk_net_last_error = code;
    return code == 0 ? n : -1;
}

const char *xdkc_p_socket_recv_text(int64_t sock, int32_t max_bytes) {
    if (max_bytes <= 0) {
        xdk_net_last_error = 1;
        return "";
    }
    char *buf = xdk_net_buf_ensure((size_t)max_bytes);
    if (buf == NULL) {
        xdk_net_last_error = 5;
        return "";
    }
    int32_t code = 0;
    int64_t n = xdkc_socket_recv((void *)(intptr_t)sock, buf, (size_t)max_bytes, &code);
    xdk_net_last_error = code;
    if (code != 0 || n < 0) {
        return "";
    }
    buf[n] = 0;
    return buf;
}

int32_t xdkc_p_socket_close_simple(int64_t sock) {
    return xdkc_socket_close((void *)(intptr_t)sock);
}

const char *xdkc_p_http_request_text(const char *method, size_t mlen,
                                     const char *host, size_t hlen, int32_t port,
                                     const char *path, size_t plen,
                                     const char *body, size_t blen) {
    int32_t code = 0;
    xdk_http_last_status = 0;
    void *resp = xdkc_http_request(method, mlen, host, hlen, port, path, plen,
                                   body, blen, &code);
    xdk_net_last_error = code;
    if (resp == NULL) {
        return "";
    }
    xdk_http_last_status = xdkc_http_status(resp);
    const char *text = xdkc_http_body_text(resp);
    size_t n = 0;
    const char *raw = xdkc_http_body(resp, &n);
    char *buf = xdk_net_buf_ensure(n);
    if (buf == NULL) {
        xdkc_http_response_close(resp);
        xdk_net_last_error = 5;
        return "";
    }
    if (n > 0 && raw != NULL) {
        memcpy(buf, raw, n);
    }
    buf[n] = 0;
    (void)text;
    xdkc_http_response_close(resp);
    return buf;
}

int32_t xdkc_p_http_status(void) {
    return xdk_http_last_status;
}

int32_t xdkc_p_http_error(void) {
    return xdk_net_last_error;
}

/* 二进制 socket：hex 形态（避开 Bytes 借出面）。 */
static int xdk_hexv(int c) {
    if (c >= '0' && c <= '9') { return c - '0'; }
    if (c >= 'a' && c <= 'f') { return c - 'a' + 10; }
    if (c >= 'A' && c <= 'F') { return c - 'A' + 10; }
    return -1;
}

int64_t xdkc_p_socket_send_hex(int64_t sock, const char *hex, size_t hlen) {
    if (hex == NULL || hlen % 2 != 0) {
        xdk_net_last_error = 1;
        return -1;
    }
    size_t n = hlen / 2;
    unsigned char *buf = malloc(n == 0 ? 1 : n);
    if (buf == NULL) {
        xdk_net_last_error = 5;
        return -1;
    }
    for (size_t i = 0; i < n; i++) {
        int hi = xdk_hexv((unsigned char)hex[i * 2]);
        int lo = xdk_hexv((unsigned char)hex[i * 2 + 1]);
        if (hi < 0 || lo < 0) {
            free(buf);
            xdk_net_last_error = 1;
            return -1;
        }
        buf[i] = (unsigned char)((hi << 4) | lo);
    }
    int32_t code = 0;
    int64_t sent = xdkc_socket_send((void *)(intptr_t)sock, buf, n, &code);
    free(buf);
    xdk_net_last_error = code;
    return code == 0 ? sent : -1;
}

const char *xdkc_p_socket_recv_hex(int64_t sock, int32_t max_bytes) {
    static const char hexdig[] = "0123456789abcdef";
    if (max_bytes <= 0) {
        xdk_net_last_error = 1;
        return "";
    }
    unsigned char *buf = malloc((size_t)max_bytes);
    if (buf == NULL) {
        xdk_net_last_error = 5;
        return "";
    }
    int32_t code = 0;
    int64_t n = xdkc_socket_recv((void *)(intptr_t)sock, buf, (size_t)max_bytes, &code);
    xdk_net_last_error = code;
    if (code != 0 || n < 0) {
        free(buf);
        return "";
    }
    size_t need = (size_t)n * 2 + 1;
    char *out = xdk_net_buf_ensure(need);
    if (out == NULL) {
        free(buf);
        xdk_net_last_error = 5;
        return "";
    }
    for (int64_t i = 0; i < n; i++) {
        out[i * 2] = hexdig[(buf[i] >> 4) & 0xF];
        out[i * 2 + 1] = hexdig[buf[i] & 0xF];
    }
    out[(size_t)n * 2] = 0;
    free(buf);
    return out;
}
