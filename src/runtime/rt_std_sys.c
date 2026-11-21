/* rt_std_sys.c — XDK sys 文件原语（S6 §4.7；M4.6b 文件子集）
 *
 * 合同：
 *   - 文件句柄由 xrt_handle 包装（S3 §18：close 显式、幂等、不以 deinit 为唯一路径）；
 *   - 原生指针为 FILE*，只经本文件的函数解释，不外泄给其他单元；
 *   - 失败以错误码返回，不 panic（S6 §3 第 1 条）：0 成功、1 句柄无效、2 IO 失败。
 */
#define _POSIX_C_SOURCE 200809L

#include "xrt.h"

#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <signal.h>
#include <unistd.h>

/* macOS 的 <stdlib.h> 在 _POSIX_C_SOURCE=200809L 下隐藏 mkdtemp 声明。 */
extern char *mkdtemp(char *template);

static char *path_dup(const char *bytes, size_t len) {
    char *p = malloc(len + 1);
    if (p == NULL) {
        xrt_fatal("sys：路径缓冲不足（S6 §4.7）");
    }
    memcpy(p, bytes, len);
    p[len] = 0;
    return p;
}

void *xdkc_file_open_read(const char *bytes, size_t len) {
    if (bytes == NULL) {
        xrt_fatal("fileOpenRead：路径为空（S6 §4.7）");
    }
    if (len == 0 || memchr(bytes, 0, len) != NULL) {
        return NULL; /* 空路径或含 NUL：非法路径 */
    }
    char *p = path_dup(bytes, len);
    FILE *f = fopen(p, "rb");
    free(p);
    return f;
}

/* fileOpenWrite（B0-06 阻塞 #3 增补）：写模式打开，语义同 fileOpenRead。
 * 失败（路径非法/打开失败）返回 NULL；不 panic（S6 §3 第 1 条）。 */
void *xdkc_file_open_write(const char *bytes, size_t len) {
    if (bytes == NULL) {
        xrt_fatal("fileOpenWrite：路径为空（S6 §4.7）");
    }
    if (len == 0 || memchr(bytes, 0, len) != NULL) {
        return NULL;
    }
    char *p = path_dup(bytes, len);
    FILE *f = fopen(p, "wb");
    free(p);
    return f;
}

/* 返回值 = 读取字节数；code 为错误码出参（0 成功、1 句柄无效、2 IO 失败）。
 * 该形态与 .xfb 的 @errorCode(codeParam = .code) 合同一一对应（S7 §7.1）。 */
int64_t xdkc_file_read(void *fp, void *buf, size_t cap, int32_t *code) {
    if (code == NULL) {
        xrt_fatal("fileRead：错误码出参为空（S6 §4.7）");
    }
    *code = 0;
    if (fp == NULL) {
        *code = 1;
        return 0;
    }
    if (cap > 0 && buf == NULL) {
        xrt_fatal("fileRead：缓冲为空但容量非零（S6 §4.7）");
    }
    size_t n = fread(buf, 1, cap, (FILE *)fp);
    if (ferror((FILE *)fp)) {
        *code = 2;
        return 0;
    }
    return (int64_t)n;
}

int32_t xdkc_file_write(void *fp, const void *buf, size_t n) {
    if (fp == NULL) {
        return 1;
    }
    if (n > 0 && buf == NULL) {
        xrt_fatal("fileWrite：缓冲为空但长度非零（S6 §4.7）");
    }
    if (n > 0 && fwrite(buf, 1, n, (FILE *)fp) != n) {
        return 2;
    }
    return 0;
}

int32_t xdkc_file_close(void *fp) {
    if (fp == NULL) {
        return 0; /* 幂等：重复关闭成功（S7 §4.3 / INV-FFI-9 同款） */
    }
    return fclose((FILE *)fp) == 0 ? 0 : 2;
}

/* ---- 目录与路径（S6 §4.7 目录子集；M4.6b-2） ----
 *
 * 合同：
 *   - 目录句柄同样走 xrt_handle 包装（原生 DIR*，close 幂等）；
 *   - dirRead 返回内部缓冲指针，仅在下次调用前有效（逐项迭代，无分配）；
 *   - 迭代顺序依文件系统（不排序）；需要确定性顺序由调用方排序；
 *   - pathExists 对目录与文件同真；无权限按不存在返回（不区分错误类型）。
 */

void *xdkc_dir_open(const char *path, size_t len) {
    if (path == NULL) {
        xrt_fatal("dirOpen：路径为空（S6 §4.7）");
    }
    if (len == 0 || memchr(path, 0, len) != NULL) {
        return NULL;
    }
    char *p = path_dup(path, len);
    DIR *d = opendir(p);
    free(p);
    return d;
}

const char *xdkc_dir_read(void *dp) {
    if (dp == NULL) {
        return NULL;
    }
    struct dirent *e = readdir((DIR *)dp);
    if (e == NULL) {
        return NULL;
    }
    return e->d_name; /* 内部缓冲：下次调用前有效 */
}

int32_t xdkc_dir_close(void *dp) {
    if (dp == NULL) {
        return 0; /* 幂等 */
    }
    return closedir((DIR *)dp) == 0 ? 0 : 2;
}

int32_t xdkc_path_exists(const char *path, size_t len) {
    if (path == NULL || len == 0 || memchr(path, 0, len) != NULL) {
        return 0;
    }
    char *p = path_dup(path, len);
    struct stat st;
    int ok = stat(p, &st) == 0;
    free(p);
    return ok ? 1 : 0;
}

/* ---- 子进程（阻塞面：调用方按 .unaware 分类，S6 §9） ----
 *
 * 合同：返回被调命令的退出码（0—255）；被信号终止或无法启动返回 -1。
 * 命令经 shell 解释（system 语义）：仅用于工具型子进程，不解析参数向量；
 * 更细的 spawn/管道形态随调度器切片另行提案。
 */
int32_t xdkc_proc_status(const char *cmd, size_t len) {
    if (cmd == NULL || len == 0 || memchr(cmd, 0, len) != NULL) {
        return -1;
    }
    char *c = path_dup(cmd, len);
    int st = system(c);
    free(c);
    if (st == -1 || !WIFEXITED(st)) {
        return -1;
    }
    return (int32_t)WEXITSTATUS(st);
}

/* ---- 文本 API（B0-06 文本变体，M6-B0-07b） ----
 *
 * 合同：整文件读/写，不暴露句柄与 Bytes；失败返回 NULL/非 0，不 panic（S6 §3 第 1 条）。
 * readFileText 返回 NUL 结尾的复用缓冲：包装层 xrt_string_from_c 在调用返回后立即复制，
 * 因此缓冲可复用；运行时当前为单线程，调用期间不得重入（与 rt_* 同款假设）。
 */
static char *g_text_buf = NULL;
static size_t g_text_cap = 0;

/* K-07：readFileText 的错误码旁路（0 成功 / 2 打开或读取失败）。
 * 线程局部：调用点与错误读取点在同一线程；.unaware 未加 @longRunning，
 * 不走 companion 路由，因此不会跨线程丢失错误状态。 */
static _Thread_local int32_t g_read_file_text_error = 0;

#define XDK_READ_FILE_TEXT_MAX (64u * 1024u * 1024u) /* K-07：≥16 MiB，实取 64 MiB */

const char *xdkc_read_file_text(const char *bytes, size_t len) {
    g_read_file_text_error = 0;
    if (bytes == NULL) {
        xrt_fatal("readFileText：路径为空（S6 §4.7）");
    }
    if (len == 0 || memchr(bytes, 0, len) != NULL) {
        g_read_file_text_error = 2;
        return "";
    }
    char *p = path_dup(bytes, len);
    FILE *f = fopen(p, "rb");
    free(p);
    if (f == NULL) {
        g_read_file_text_error = 2;
        return "";
    }
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        g_read_file_text_error = 2;
        return "";
    }
    long n = ftell(f);
    if (n < 0 || (size_t)n > XDK_READ_FILE_TEXT_MAX || fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        g_read_file_text_error = 2;
        return "";
    }
    size_t need = (size_t)n + 1;
    if (need > g_text_cap) {
        char *nb = realloc(g_text_buf, need);
        if (nb == NULL) {
            fclose(f);
            g_read_file_text_error = 2;
            return "";
        }
        g_text_buf = nb;
        g_text_cap = need;
    }
    size_t got = fread(g_text_buf, 1, (size_t)n, f);
    int bad = ferror(f);
    fclose(f);
    if (bad || got != (size_t)n) {
        g_read_file_text_error = 2;
        return "";
    }
    g_text_buf[got] = 0;
    return g_text_buf;
}

/* K-07：最近一次 xdkc_read_file_text 的错误码（0=成功）。
 * 供 xdk.sys 源码层把失败转成 throw，避免静默空串。 */
int32_t xdkc_read_file_text_error(void) {
    return g_read_file_text_error;
}

/* K-07：带错误码的文件读取入口（C 层测试与解释器语义对齐用）。
 * code=0 成功；1 参数非法；2 打开/读取失败或超过 64 MiB。 */
const char *xdkc_read_file_text_code(const char *bytes, size_t len, int32_t *code) {
    if (code != NULL) {
        *code = 0;
    }
    if (bytes == NULL || len == 0) {
        if (code != NULL) {
            *code = 1;
        }
        return NULL;
    }
    const char *p = xdkc_read_file_text(bytes, len);
    if (code != NULL) {
        *code = g_read_file_text_error;
    }
    return p;
}

int64_t xdkc_write_file_text(const char *bytes, size_t plen,
                             const char *text, size_t tlen) {
    if (bytes == NULL) {
        xrt_fatal("writeFileText：路径为空（S6 §4.7）");
    }
    if (plen == 0 || memchr(bytes, 0, plen) != NULL) {
        return 1;
    }
    if (tlen > 0 && text == NULL) {
        xrt_fatal("writeFileText：内容为空但长度非零（S6 §4.7）");
    }
    char *p = path_dup(bytes, plen);
    FILE *f = fopen(p, "wb");
    free(p);
    if (f == NULL) {
        return 1;
    }
    size_t n = 0;
    if (tlen > 0) {
        n = fwrite(text, 1, tlen, f);
    }
    int rc = (n == tlen) ? 0 : 1;
    if (fclose(f) != 0) {
        rc = 1;
    }
    return (int64_t)rc;
}

/* ---- S6-03：plain/Async 双形态（Context 首参；close 必达/幂等由句柄层保证） ----
 *
 * Async 形态把阻塞原语投递到伴生执行器（S5 §2.2），等待可被 Context 取消。
 * 取消语义：
 *   - open/read/write/dir：等待取消后仍等待完成以回收结果（避免泄漏/UAF），
 *     返回 XRT_ERR_CANCELLED/code=2（写操作可能已产生副作用，属原生调用不可抢占；
 *     B3 异步 I/O 收敛）；
 *   - close（file/dir）：取消只打断等待，不撤销已完成的关闭；返回真实 close 结果（0 成功），
 *     确保句柄层能 mark_closed，不留下“已关闭但句柄层以为未关闭”的悬垂指针；
 *   - proc_run_async：取消立即返回，命令继续在伴生线程执行（结果丢弃）。
 */

typedef struct {
    const char *bytes;
    size_t      len;
} async_path_arg;

typedef struct {
    void   *fp;
    void   *buf;
    size_t  cap;
    const void *wbuf;
    size_t  wn;
} async_file_arg;

typedef struct {
    char  *cmd;
    size_t len;
} async_cmd_arg;

static int32_t wait_future_reap(xrt_future *f, xrt_context *ctx, void **out) {
    int32_t rc = xrt_companion_wait(f, ctx, out);
    if (rc == XRT_ERR_CANCELLED) {
        void *ignored = NULL;
        (void)xrt_companion_wait(f, NULL, &ignored); /* 等完成以回收资源 */
        if (out != NULL) {
            *out = ignored;
        }
    }
    xrt_release(f);
    return rc;
}

static void *thunk_file_open_read(void *arg) {
    async_path_arg *a = arg;
    void *fp = xdkc_file_open_read(a->bytes, a->len);
    free(a);
    return fp;
}

void *xdkc_file_open_read_async(xrt_context *ctx, const char *bytes, size_t len, int32_t *code) {
    async_path_arg *a = malloc(sizeof(*a));
    if (a == NULL) {
        xrt_fatal("fileOpenReadAsync：内存不足（S6 §4.7）");
    }
    a->bytes = bytes;
    a->len = len;
    xrt_future *f = xrt_companion_submit(thunk_file_open_read, a);
    void *fp = NULL;
    int32_t rc = wait_future_reap(f, ctx, &fp);
    if (rc == XRT_ERR_CANCELLED) {
        if (fp != NULL) {
            (void)xdkc_file_close(fp); /* 取消后的打开结果必须关闭 */
        }
        if (code != NULL) {
            *code = 2;
        }
        return NULL;
    }
    if (code != NULL) {
        *code = 0;
    }
    return fp;
}

static void *thunk_file_open_write(void *arg) {
    async_path_arg *a = arg;
    void *fp = xdkc_file_open_write(a->bytes, a->len);
    free(a);
    return fp;
}

void *xdkc_file_open_write_async(xrt_context *ctx, const char *bytes, size_t len, int32_t *code) {
    async_path_arg *a = malloc(sizeof(*a));
    if (a == NULL) {
        xrt_fatal("fileOpenWriteAsync：内存不足（S6 §4.7）");
    }
    a->bytes = bytes;
    a->len = len;
    xrt_future *f = xrt_companion_submit(thunk_file_open_write, a);
    void *fp = NULL;
    int32_t rc = wait_future_reap(f, ctx, &fp);
    if (rc == XRT_ERR_CANCELLED) {
        if (fp != NULL) {
            (void)xdkc_file_close(fp);
        }
        if (code != NULL) {
            *code = 2;
        }
        return NULL;
    }
    if (code != NULL) {
        *code = 0;
    }
    return fp;
}

static void *thunk_file_read(void *arg) {
    async_file_arg *a = arg;
    int32_t code = 0;
    int64_t n = xdkc_file_read(a->fp, a->buf, a->cap, &code);
    int64_t *r = malloc(sizeof(*r));
    if (r == NULL) {
        abort();
    }
    *r = (code != 0) ? -1 : n;
    free(a);
    return r;
}

int64_t xdkc_file_read_async(xrt_context *ctx, void *fp, void *buf, size_t cap, int32_t *code) {
    async_file_arg *a = malloc(sizeof(*a));
    if (a == NULL) {
        xrt_fatal("fileReadAsync：内存不足（S6 §4.7）");
    }
    a->fp = fp;
    a->buf = buf;
    a->cap = cap;
    xrt_future *f = xrt_companion_submit(thunk_file_read, a);
    void *out = NULL;
    int32_t rc = wait_future_reap(f, ctx, &out);
    int64_t n = -1;
    if (out != NULL) {
        int64_t *p = out;
        n = *p;
        free(p);
    }
    if (rc == XRT_ERR_CANCELLED) {
        if (code != NULL) {
            *code = 2;
        }
        return -1;
    }
    if (code != NULL) {
        *code = (n < 0) ? 2 : 0;
    }
    return n;
}

static void *thunk_file_write(void *arg) {
    async_file_arg *a = arg;
    int32_t rc = xdkc_file_write(a->fp, a->wbuf, a->wn);
    int64_t *r = malloc(sizeof(*r));
    if (r == NULL) {
        abort();
    }
    *r = rc;
    free(a);
    return r;
}

int32_t xdkc_file_write_async(xrt_context *ctx, void *fp, const void *buf, size_t n) {
    async_file_arg *a = malloc(sizeof(*a));
    if (a == NULL) {
        xrt_fatal("fileWriteAsync：内存不足（S6 §4.7）");
    }
    a->fp = fp;
    a->wbuf = buf;
    a->wn = n;
    xrt_future *f = xrt_companion_submit(thunk_file_write, a);
    void *out = NULL;
    int32_t rc = wait_future_reap(f, ctx, &out);
    int32_t wrc = 0;
    if (out != NULL) {
        int64_t *p = out;
        wrc = (int32_t)*p;
        free(p);
    }
    return rc == XRT_ERR_CANCELLED ? 2 : wrc;
}

static void *thunk_file_close(void *arg) {
    async_file_arg *a = arg;
    int32_t rc = xdkc_file_close(a->fp);
    free(a);
    return (void *)(intptr_t)rc;
}

int32_t xdkc_file_close_async(xrt_context *ctx, void *fp) {
    async_file_arg *a = malloc(sizeof(*a));
    if (a == NULL) {
        xrt_fatal("fileCloseAsync：内存不足（S6 §4.7）");
    }
    a->fp = fp;
    xrt_future *f = xrt_companion_submit(thunk_file_close, a);
    void *out = NULL;
    /* close 必达（S6 §4.7 / S3 §18）：取消只打断“等待”，不撤销已完成的关闭。
     * wait_future_reap 在取消后仍等待完成以回收，返回真实 close 结果，
     * 使句柄层能正确 mark_closed，避免“已关闭但句柄层以为未关闭”的悬垂指针。 */
    (void)wait_future_reap(f, ctx, &out);
    return (int32_t)(intptr_t)out;
}

static void *thunk_dir_open(void *arg) {
    async_path_arg *a = arg;
    void *dp = xdkc_dir_open(a->bytes, a->len);
    free(a);
    return dp;
}

void *xdkc_dir_open_async(xrt_context *ctx, const char *bytes, size_t len, int32_t *code) {
    async_path_arg *a = malloc(sizeof(*a));
    if (a == NULL) {
        xrt_fatal("dirOpenAsync：内存不足（S6 §4.7）");
    }
    a->bytes = bytes;
    a->len = len;
    xrt_future *f = xrt_companion_submit(thunk_dir_open, a);
    void *dp = NULL;
    int32_t rc = wait_future_reap(f, ctx, &dp);
    if (rc == XRT_ERR_CANCELLED) {
        if (dp != NULL) {
            (void)xdkc_dir_close(dp);
        }
        if (code != NULL) {
            *code = 2;
        }
        return NULL;
    }
    if (code != NULL) {
        *code = 0;
    }
    return dp;
}

static void *thunk_dir_read(void *arg) {
    void *dp = arg;
    return (void *)xdkc_dir_read(dp);
}

const char *xdkc_dir_read_async(xrt_context *ctx, void *dp, int32_t *code) {
    xrt_future *f = xrt_companion_submit(thunk_dir_read, dp);
    void *out = NULL;
    int32_t rc = wait_future_reap(f, ctx, &out);
    if (rc == XRT_ERR_CANCELLED) {
        if (code != NULL) {
            *code = 2;
        }
        return NULL;
    }
    if (code != NULL) {
        *code = 0;
    }
    return (const char *)out;
}

static void *thunk_dir_close(void *arg) {
    int32_t rc = xdkc_dir_close(arg);
    return (void *)(intptr_t)rc;
}

int32_t xdkc_dir_close_async(xrt_context *ctx, void *dp) {
    xrt_future *f = xrt_companion_submit(thunk_dir_close, dp);
    void *out = NULL;
    /* 同 fileCloseAsync：close 必达，取消不改变已完成的关闭结果。 */
    (void)wait_future_reap(f, ctx, &out);
    return (int32_t)(intptr_t)out;
}

/* ---- Process 句柄（S6 §4.7 子进程；close 必达：kill+reap） ---- */

typedef struct {
    pid_t pid;
    int   reaped;
    int   status;
    int   in_fd;
    int   out_fd;
    int   err_fd;
} proc_t;

static void proc_close_fds(proc_t *p) {
    if (p == NULL) {
        return;
    }
    if (p->in_fd >= 0) { (void)close(p->in_fd); p->in_fd = -1; }
    if (p->out_fd >= 0) { (void)close(p->out_fd); p->out_fd = -1; }
    if (p->err_fd >= 0) { (void)close(p->err_fd); p->err_fd = -1; }
}

static void *proc_spawn_internal(const char *cmd, size_t len, int32_t *code, int piped) {
    if (cmd == NULL) {
        xrt_fatal("procSpawn：命令为空（S6 §4.7）");
    }
    char *c = malloc(len + 1);
    if (c == NULL) {
        xrt_fatal("procSpawn：内存不足（S6 §4.7）");
    }
    memcpy(c, cmd, len);
    c[len] = 0;

    int in_pipe[2] = {-1, -1};
    int out_pipe[2] = {-1, -1};
    int err_pipe[2] = {-1, -1};
    if (piped) {
        if (pipe(in_pipe) != 0 || pipe(out_pipe) != 0 || pipe(err_pipe) != 0) {
            if (in_pipe[0] >= 0) { close(in_pipe[0]); close(in_pipe[1]); }
            if (out_pipe[0] >= 0) { close(out_pipe[0]); close(out_pipe[1]); }
            if (err_pipe[0] >= 0) { close(err_pipe[0]); close(err_pipe[1]); }
            free(c);
            if (code != NULL) { *code = 2; }
            return NULL;
        }
    }

    pid_t pid = fork();
    if (pid == 0) {
        /* 每个子进程自成一个进程组：组信号可一次覆盖 shell 及其后代。 */
        (void)setpgid(0, 0);
        if (piped) {
            (void)dup2(in_pipe[0], 0);
            (void)dup2(out_pipe[1], 1);
            (void)dup2(err_pipe[1], 2);
            (void)close(in_pipe[0]); (void)close(in_pipe[1]);
            (void)close(out_pipe[0]); (void)close(out_pipe[1]);
            (void)close(err_pipe[0]); (void)close(err_pipe[1]);
        }
        execl("/bin/sh", "sh", "-c", c, (char *)NULL);
        _exit(127);
    }
    free(c);
    if (pid < 0) {
        if (piped) {
            (void)close(in_pipe[0]); (void)close(in_pipe[1]);
            (void)close(out_pipe[0]); (void)close(out_pipe[1]);
            (void)close(err_pipe[0]); (void)close(err_pipe[1]);
        }
        if (code != NULL) {
            *code = 2;
        }
        return NULL;
    }
    (void)setpgid(pid, pid); /* 与子进程内的 setpgid 竞争，取先到者，结果一致。 */

    proc_t *p = malloc(sizeof(*p));
    if (p == NULL) {
        xrt_fatal("procSpawn：内存不足（S6 §4.7）");
    }
    p->pid = pid;
    p->reaped = 0;
    p->status = 0;
    p->in_fd = -1;
    p->out_fd = -1;
    p->err_fd = -1;
    if (piped) {
        p->in_fd = in_pipe[1];
        p->out_fd = out_pipe[0];
        p->err_fd = err_pipe[0];
        (void)close(in_pipe[0]);
        (void)close(out_pipe[1]);
        (void)close(err_pipe[1]);
    }
    if (code != NULL) {
        *code = 0;
    }
    return p;
}

void *xdkc_proc_spawn(const char *cmd, size_t len, int32_t *code) {
    return proc_spawn_internal(cmd, len, code, 0);
}

int32_t xdkc_proc_wait(void *proc, int32_t *status) {
    proc_t *p = proc;
    if (p == NULL) {
        return 1;
    }
    if (!p->reaped) {
        int st = 0;
        if (waitpid(p->pid, &st, 0) < 0) {
            return 2;
        }
        p->status = WIFEXITED(st) ? WEXITSTATUS(st) : 128 + WTERMSIG(st);
        p->reaped = 1;
    }
    if (status != NULL) {
        *status = p->status;
    }
    return 0;
}

int32_t xdkc_proc_kill(void *proc, int32_t sig) {
    proc_t *p = proc;
    if (p == NULL || p->reaped) {
        return 1;
    }
    return kill(p->pid, sig) == 0 ? 0 : 2;
}

/* close 必达：先关管道，再 kill + reap；幂等（reaped 后只释放）。 */
int32_t xdkc_proc_close(void *proc) {
    proc_t *p = proc;
    if (p == NULL) {
        return 0;
    }
    proc_close_fds(p);
    if (!p->reaped) {
        (void)kill(p->pid, SIGKILL);
        int st = 0;
        (void)waitpid(p->pid, &st, 0);
        p->reaped = 1;
    }
    free(p);
    return 0;
}

typedef struct {
    char  *cmd;
    size_t len;
} proc_async_arg;

static void *thunk_proc_run(void *arg) {
    proc_async_arg *a = arg;
    int32_t st = 0;
    void *h = xdkc_proc_spawn(a->cmd, a->len, NULL);
    free(a->cmd);
    free(a);
    if (h == NULL) {
        return (void *)(intptr_t)(-1);
    }
    (void)xdkc_proc_wait(h, &st);
    (void)xdkc_proc_close(h);
    return (void *)(intptr_t)st;
}

/* 运行 shell 命令并返回退出状态；取消立即返回 XRT_ERR_CANCELLED（命令继续）。 */
int32_t xdkc_proc_run_async(xrt_context *ctx, const char *cmd, size_t len, int32_t *status) {
    proc_async_arg *a = malloc(sizeof(*a));
    if (a == NULL) {
        xrt_fatal("procRunAsync：内存不足（S6 §4.7）");
    }
    a->cmd = malloc(len + 1);
    if (a->cmd == NULL) {
        xrt_fatal("procRunAsync：内存不足（S6 §4.7）");
    }
    memcpy(a->cmd, cmd, len);
    a->cmd[len] = 0;
    a->len = len;
    xrt_future *f = xrt_companion_submit(thunk_proc_run, a);
    void *out = NULL;
    int32_t rc = xrt_companion_wait(f, ctx, &out);
    xrt_release(f); /* 取消时 future 由伴生线程持有并自行完成 */
    if (rc == XRT_ERR_CANCELLED) {
        return XRT_ERR_CANCELLED;
    }
    if (status != NULL) {
        *status = (int32_t)(intptr_t)out;
    }
    return 0;
}

int32_t xdkc_proc_status_async(xrt_context *ctx, const char *cmd, size_t len) {
    int32_t st = -1;
    int32_t rc = xdkc_proc_run_async(ctx, cmd, len, &st);
    return rc == XRT_ERR_CANCELLED ? -1 : st;
}


/* ---- XDK 源码层桥（bindings/xdk/sys_raw.xfb）----
 * 只用 String/标量形态，避开产品编译器尚未接通的 Bytes 借出/errorCode 出参。
 * 语义复用上方原语；Dir 用固定句柄表把 void* 收敛为 Int32 id（0=失败）。 */

/* 文件系统错误分类（跨平台稳定小整数）：
 *   0=OK；1=NotFound；2=PermissionDenied；3=AlreadyExists；
 *   4=InvalidArgument；5=Io；6=Unsupported；7=Busy。 */
static _Thread_local int32_t g_fs_last_error = 0;

static int32_t fs_error_from_errno(void) {
    switch (errno) {
        case 0:      return 0;
        case ENOENT:
        case ENOTDIR: return 1;
        case EACCES:
        case EPERM:
        case EROFS:  return 2;
        case EEXIST: return 3;
        case EINVAL:
        case ENAMETOOLONG:
        case ELOOP:
        case EISDIR: return 4;
        case ENOSPC:
        case EDQUOT:
        case EFBIG:  return 5;
        case ENOSYS: return 6;
        case EBUSY:
        case ETXTBSY: return 7;
        default:     return 5;
    }
}

static int32_t fs_fail(void) {
    g_fs_last_error = fs_error_from_errno();
    if (g_fs_last_error == 0) {
        g_fs_last_error = 5;
    }
    return g_fs_last_error;
}

int32_t xdkc_p_fs_error(void) {
    return g_fs_last_error;
}

int32_t xdkc_p_write_file_text(const char *path, size_t plen,
                               const char *text, size_t tlen) {
    g_fs_last_error = 0;
    int32_t rc = (int32_t)xdkc_write_file_text(path, plen, text, tlen);
    if (rc != 0) {
        fs_fail();
    }
    return rc;
}

#define XDK_DIR_SLOTS 64
static void *xdk_dir_slots[XDK_DIR_SLOTS];

int32_t xdkc_p_dir_open_id(const char *path, size_t len) {
    g_fs_last_error = 0;
    void *d = xdkc_dir_open(path, len);
    if (d == NULL) {
        fs_fail();
        return 0;
    }
    for (int32_t i = 0; i < XDK_DIR_SLOTS; i++) {
        if (xdk_dir_slots[i] == NULL) {
            xdk_dir_slots[i] = d;
            return i + 1;
        }
    }
    (void)xdkc_dir_close(d);
    g_fs_last_error = 7;
    return 0;
}

const char *xdkc_p_dir_next_id(int32_t id) {
    if (id < 1 || id > XDK_DIR_SLOTS || xdk_dir_slots[id - 1] == NULL) {
        g_fs_last_error = 4;
        return "";
    }
    g_fs_last_error = 0;
    const char *s = xdkc_dir_read(xdk_dir_slots[id - 1]);
    return s == NULL ? "" : s;
}

int32_t xdkc_p_dir_close_id(int32_t id) {
    if (id < 1 || id > XDK_DIR_SLOTS || xdk_dir_slots[id - 1] == NULL) {
        g_fs_last_error = 0;
        return 0; /* 幂等 */
    }
    void *d = xdk_dir_slots[id - 1];
    xdk_dir_slots[id - 1] = NULL;
    g_fs_last_error = 0;
    int32_t rc = xdkc_dir_close(d);
    if (rc != 0) {
        fs_fail();
    }
    return rc;
}

/* ---- xdk.fs T0-X 桥：File 句柄 / 元数据 / 权限 / 链接 / 临时 / 原子写 ---- */

static int fs_hex_value(int c) {
    if (c >= '0' && c <= '9') { return c - '0'; }
    if (c >= 'a' && c <= 'f') { return c - 'a' + 10; }
    if (c >= 'A' && c <= 'F') { return c - 'A' + 10; }
    return -1;
}

/* File 句柄：0=read, 1=write(truncate), 2=append, 3=read+write(existing)。 */
int64_t xdkc_p_file_open_handle(const char *path, size_t len, int32_t mode) {
    g_fs_last_error = 0;
    if (path == NULL || len == 0 || memchr(path, 0, len) != NULL) {
        g_fs_last_error = 4;
        return 0;
    }
    const char *flags = NULL;
    switch (mode) {
        case 0: flags = "rb"; break;
        case 1: flags = "wb"; break;
        case 2: flags = "ab"; break;
        case 3: flags = "r+b"; break;
        default: g_fs_last_error = 4; return 0;
    }
    char *p = path_dup(path, len);
    FILE *f = fopen(p, flags);
    free(p);
    if (f == NULL) {
        fs_fail();
        return 0;
    }
    return (int64_t)(intptr_t)f;
}

int32_t xdkc_p_file_close_handle(int64_t handle) {
    g_fs_last_error = 0;
    if (handle == 0) {
        g_fs_last_error = 4;
        return 1;
    }
    int rc = fclose((FILE *)(intptr_t)handle);
    if (rc != 0) {
        fs_fail();
        return 1;
    }
    return 0;
}

int64_t xdkc_p_file_size_handle(int64_t handle) {
    g_fs_last_error = 0;
    if (handle == 0) {
        g_fs_last_error = 4;
        return -1;
    }
    struct stat st;
    if (fstat(fileno((FILE *)(intptr_t)handle), &st) != 0) {
        fs_fail();
        return -1;
    }
    return (int64_t)st.st_size;
}

int64_t xdkc_p_file_tell_handle(int64_t handle) {
    g_fs_last_error = 0;
    if (handle == 0) {
        g_fs_last_error = 4;
        return -1;
    }
    off_t pos = ftello((FILE *)(intptr_t)handle);
    if (pos < 0) {
        fs_fail();
        return -1;
    }
    return (int64_t)pos;
}

int64_t xdkc_p_file_seek_handle(int64_t handle, int64_t offset) {
    g_fs_last_error = 0;
    if (handle == 0 || offset < 0) {
        g_fs_last_error = 4;
        return -1;
    }
    if (fseeko((FILE *)(intptr_t)handle, (off_t)offset, SEEK_SET) != 0) {
        fs_fail();
        return -1;
    }
    off_t pos = ftello((FILE *)(intptr_t)handle);
    if (pos < 0) {
        fs_fail();
        return -1;
    }
    return (int64_t)pos;
}

static char  *g_fs_hex_buf = NULL;
static size_t g_fs_hex_cap = 0;

const char *xdkc_p_file_read_hex(int64_t handle, int64_t count) {
    static const char digits[] = "0123456789abcdef";
    g_fs_last_error = 0;
    if (handle == 0 || count < 0) {
        g_fs_last_error = 4;
        return "";
    }
    if (count > 64ll * 1024ll * 1024ll) {
        g_fs_last_error = 6;
        return "";
    }
    size_t want = (size_t)count;
    size_t need = want * 2 + 1;
    if (need > g_fs_hex_cap) {
        char *nb = realloc(g_fs_hex_buf, need);
        if (nb == NULL) {
            g_fs_last_error = 5;
            return "";
        }
        g_fs_hex_buf = nb;
        g_fs_hex_cap = need;
    }
    unsigned char *buf = want == 0 ? NULL : (unsigned char *)malloc(want);
    if (want != 0 && buf == NULL) {
        g_fs_last_error = 5;
        return "";
    }
    size_t got = want == 0 ? 0 : fread(buf, 1, want, (FILE *)(intptr_t)handle);
    if (ferror((FILE *)(intptr_t)handle)) {
        free(buf);
        fs_fail();
        return "";
    }
    for (size_t i = 0; i < got; i++) {
        g_fs_hex_buf[i * 2] = digits[buf[i] >> 4];
        g_fs_hex_buf[i * 2 + 1] = digits[buf[i] & 0xF];
    }
    g_fs_hex_buf[got * 2] = 0;
    free(buf);
    return g_fs_hex_buf;
}

int64_t xdkc_p_file_write_hex(int64_t handle, const char *hex, size_t hlen) {
    g_fs_last_error = 0;
    if (handle == 0 || hex == NULL || hlen % 2 != 0) {
        g_fs_last_error = 4;
        return -1;
    }
    size_t n = hlen / 2;
    if (n > 64u * 1024u * 1024u) {
        g_fs_last_error = 6;
        return -1;
    }
    unsigned char *buf = n == 0 ? NULL : (unsigned char *)malloc(n);
    if (n != 0 && buf == NULL) {
        g_fs_last_error = 5;
        return -1;
    }
    for (size_t i = 0; i < n; i++) {
        int hi = fs_hex_value((unsigned char)hex[i * 2]);
        int lo = fs_hex_value((unsigned char)hex[i * 2 + 1]);
        if (hi < 0 || lo < 0) {
            free(buf);
            g_fs_last_error = 4;
            return -1;
        }
        buf[i] = (unsigned char)((hi << 4) | lo);
    }
    size_t wrote = n == 0 ? 0 : fwrite(buf, 1, n, (FILE *)(intptr_t)handle);
    free(buf);
    if (wrote != n) {
        fs_fail();
        return -1;
    }
    return (int64_t)wrote;
}

int32_t xdkc_p_file_flush_handle(int64_t handle) {
    g_fs_last_error = 0;
    if (handle == 0) {
        g_fs_last_error = 4;
        return 1;
    }
    if (fflush((FILE *)(intptr_t)handle) != 0) {
        fs_fail();
        return 1;
    }
    return 0;
}

int32_t xdkc_p_path_kind(const char *path, size_t len, int32_t follow) {
    g_fs_last_error = 0;
    if (path == NULL || len == 0 || memchr(path, 0, len) != NULL) {
        g_fs_last_error = 4;
        return 0;
    }
    char *p = path_dup(path, len);
    struct stat st;
    int rc = follow ? stat(p, &st) : lstat(p, &st);
    free(p);
    if (rc != 0) {
        fs_fail();
        return 0;
    }
    if (S_ISREG(st.st_mode)) { return 1; }
    if (S_ISDIR(st.st_mode)) { return 2; }
    if (S_ISLNK(st.st_mode)) { return 3; }
    return 4;
}

int64_t xdkc_p_path_size(const char *path, size_t len, int32_t follow) {
    g_fs_last_error = 0;
    if (path == NULL || len == 0 || memchr(path, 0, len) != NULL) {
        g_fs_last_error = 4;
        return -1;
    }
    char *p = path_dup(path, len);
    struct stat st;
    int rc = follow ? stat(p, &st) : lstat(p, &st);
    free(p);
    if (rc != 0) {
        fs_fail();
        return -1;
    }
    return (int64_t)st.st_size;
}

int64_t xdkc_p_path_mtime(const char *path, size_t len, int32_t follow) {
    g_fs_last_error = 0;
    if (path == NULL || len == 0 || memchr(path, 0, len) != NULL) {
        g_fs_last_error = 4;
        return -1;
    }
    char *p = path_dup(path, len);
    struct stat st;
    int rc = follow ? stat(p, &st) : lstat(p, &st);
    free(p);
    if (rc != 0) {
        fs_fail();
        return -1;
    }
    return (int64_t)st.st_mtime * 1000ll;
}

int32_t xdkc_p_path_mode(const char *path, size_t len, int32_t follow) {
    g_fs_last_error = 0;
    if (path == NULL || len == 0 || memchr(path, 0, len) != NULL) {
        g_fs_last_error = 4;
        return -1;
    }
    char *p = path_dup(path, len);
    struct stat st;
    int rc = follow ? stat(p, &st) : lstat(p, &st);
    free(p);
    if (rc != 0) {
        fs_fail();
        return -1;
    }
    return (int32_t)(st.st_mode & 07777);
}

int32_t xdkc_p_path_chmod(const char *path, size_t len, int32_t mode) {
    g_fs_last_error = 0;
    if (path == NULL || len == 0 || memchr(path, 0, len) != NULL || mode < 0) {
        g_fs_last_error = 4;
        return 1;
    }
    char *p = path_dup(path, len);
    int rc = chmod(p, (mode_t)(mode & 07777));
    free(p);
    if (rc != 0) {
        fs_fail();
        return 1;
    }
    return 0;
}

const char *xdkc_p_path_readlink(const char *path, size_t len) {
    static _Thread_local char target[4096];
    g_fs_last_error = 0;
    if (path == NULL || len == 0 || memchr(path, 0, len) != NULL) {
        g_fs_last_error = 4;
        return "";
    }
    char *p = path_dup(path, len);
    ssize_t n = readlink(p, target, sizeof(target) - 1);
    free(p);
    if (n < 0) {
        fs_fail();
        return "";
    }
    target[n] = 0;
    return target;
}

const char *xdkc_p_path_realpath(const char *path, size_t len) {
    static _Thread_local char resolved[4096];
    g_fs_last_error = 0;
    if (path == NULL || len == 0 || memchr(path, 0, len) != NULL) {
        g_fs_last_error = 4;
        return "";
    }
    char *p = path_dup(path, len);
    char *ok = realpath(p, resolved);
    free(p);
    if (ok == NULL) {
        fs_fail();
        return "";
    }
    return resolved;
}

int32_t xdkc_p_path_symlink(const char *target, size_t tlen,
                            const char *path, size_t plen) {
    g_fs_last_error = 0;
    if (target == NULL || path == NULL || tlen == 0 || plen == 0 ||
        memchr(target, 0, tlen) != NULL || memchr(path, 0, plen) != NULL) {
        g_fs_last_error = 4;
        return 1;
    }
    char *t = path_dup(target, tlen);
    char *p = path_dup(path, plen);
    int rc = symlink(t, p);
    free(t);
    free(p);
    if (rc != 0) {
        fs_fail();
        return 1;
    }
    return 0;
}

int32_t xdkc_p_path_hardlink(const char *target, size_t tlen,
                             const char *path, size_t plen) {
    g_fs_last_error = 0;
    if (target == NULL || path == NULL || tlen == 0 || plen == 0 ||
        memchr(target, 0, tlen) != NULL || memchr(path, 0, plen) != NULL) {
        g_fs_last_error = 4;
        return 1;
    }
    char *t = path_dup(target, tlen);
    char *p = path_dup(path, plen);
    int rc = link(t, p);
    free(t);
    free(p);
    if (rc != 0) {
        fs_fail();
        return 1;
    }
    return 0;
}

/* prefix 为空：使用系统临时目录 + xnull-；
 * prefix 无 '/'：放在系统临时目录下；含 '/'：按路径前缀处理。
 * 尾部没有 XXXXXX 时自动补。 */
static const char *fs_temp_template(const char *prefix, size_t len) {
    static _Thread_local char template[4096];
    const char *tmp = getenv("TMPDIR");
    if (tmp == NULL || tmp[0] == 0) {
        tmp = "/tmp";
    }
    size_t at = 0;
    if (len == 0) {
        int n = snprintf(template, sizeof(template), "%s/xnull-", tmp);
        if (n < 0 || (size_t)n >= sizeof(template)) {
            g_fs_last_error = 4;
            return NULL;
        }
        at = (size_t)n;
    } else if (memchr(prefix, '/', len) != NULL) {
        if (len >= sizeof(template)) {
            g_fs_last_error = 4;
            return NULL;
        }
        memcpy(template, prefix, len);
        template[len] = 0;
        at = len;
    } else {
        int n = snprintf(template, sizeof(template), "%s/", tmp);
        if (n < 0 || (size_t)n >= sizeof(template)) {
            g_fs_last_error = 4;
            return NULL;
        }
        at = (size_t)n;
        if (at + len >= sizeof(template)) {
            g_fs_last_error = 4;
            return NULL;
        }
        memcpy(template + at, prefix, len);
        at += len;
        template[at] = 0;
    }
    if (at < 6 || memcmp(template + at - 6, "XXXXXX", 6) != 0) {
        if (at + 6 >= sizeof(template)) {
            g_fs_last_error = 4;
            return NULL;
        }
        memcpy(template + at, "XXXXXX", 6);
        at += 6;
        template[at] = 0;
    }
    return template;
}

const char *xdkc_p_temp_file(const char *prefix, size_t len) {
    g_fs_last_error = 0;
    const char *tmpl = fs_temp_template(prefix, len);
    if (tmpl == NULL) {
        return "";
    }
    int fd = mkstemp((char *)tmpl);
    if (fd < 0) {
        fs_fail();
        return "";
    }
    if (close(fd) != 0) {
        int32_t saved = fs_fail();
        (void)remove(tmpl);
        g_fs_last_error = saved;
        return "";
    }
    return tmpl;
}

const char *xdkc_p_temp_dir(const char *prefix, size_t len) {
    g_fs_last_error = 0;
    const char *tmpl = fs_temp_template(prefix, len);
    if (tmpl == NULL) {
        return "";
    }
    if (mkdtemp((char *)tmpl) == NULL) {
        fs_fail();
        return "";
    }
    return tmpl;
}

int32_t xdkc_p_write_file_atomic(const char *path, size_t plen,
                                 const char *hex, size_t hlen) {
    g_fs_last_error = 0;
    if (path == NULL || plen == 0 || hex == NULL || hlen % 2 != 0 ||
        memchr(path, 0, plen) != NULL) {
        g_fs_last_error = 4;
        return 1;
    }
    size_t n = hlen / 2;
    unsigned char *buf = n == 0 ? NULL : (unsigned char *)malloc(n);
    if (n != 0 && buf == NULL) {
        g_fs_last_error = 5;
        return 1;
    }
    for (size_t i = 0; i < n; i++) {
        int hi = fs_hex_value((unsigned char)hex[i * 2]);
        int lo = fs_hex_value((unsigned char)hex[i * 2 + 1]);
        if (hi < 0 || lo < 0) {
            free(buf);
            g_fs_last_error = 4;
            return 1;
        }
        buf[i] = (unsigned char)((hi << 4) | lo);
    }
    char *target = path_dup(path, plen);
    size_t tlen = plen + 12;
    char *tmpl = (char *)malloc(tlen);
    if (tmpl == NULL) {
        free(target);
        free(buf);
        g_fs_last_error = 5;
        return 1;
    }
    snprintf(tmpl, tlen, "%s.tmp.XXXXXX", target);
    struct stat existing;
    int has_existing = stat(target, &existing) == 0;
    int fd = mkstemp(tmpl);
    if (fd < 0) {
        free(target);
        free(tmpl);
        free(buf);
        fs_fail();
        return 1;
    }
    int rc = 0;
    size_t written = 0;
    while (written < n) {
        ssize_t step = write(fd, buf + written, n - written);
        if (step < 0) {
            if (errno == EINTR) {
                continue;
            }
            rc = 1;
            break;
        }
        written += (size_t)step;
    }
    if (rc == 0 && fsync(fd) != 0) {
        rc = 1;
    }
    if (rc == 0) {
        mode_t mode;
        if (has_existing) {
            mode = existing.st_mode & 07777;
        } else {
            mode_t old = umask(0);
            umask(old);
            mode = (mode_t)(0666 & ~old);
        }
        if (fchmod(fd, mode) != 0) {
            rc = 1;
        }
    }
    if (close(fd) != 0) {
        rc = 1;
    }
    if (rc == 0 && rename(tmpl, target) != 0) {
        rc = 1;
    }
    if (rc != 0) {
        int32_t saved = fs_fail();
        (void)remove(tmpl);
        free(target);
        free(tmpl);
        free(buf);
        g_fs_last_error = saved;
        return 1;
    }
    free(target);
    free(tmpl);
    free(buf);
    return 0;
}

int64_t xdkc_p_proc_spawn_simple(const char *cmd, size_t len) {
    int32_t code = 0;
    void *p = xdkc_proc_spawn(cmd, len, &code);
    if (code != 0 || p == NULL) {
        return 0;
    }
    return (int64_t)(intptr_t)p;
}

int64_t xdkc_p_proc_wait_simple(int64_t proc) {
    int32_t st = 0;
    if (xdkc_proc_wait((void *)(intptr_t)proc, &st) != 0) {
        return -1;
    }
    return (int64_t)st;
}

int32_t xdkc_p_proc_kill_simple(int64_t proc, int32_t sig) {
    return xdkc_proc_kill((void *)(intptr_t)proc, sig);
}

int32_t xdkc_p_proc_close_simple(int64_t proc) {
    return xdkc_proc_close((void *)(intptr_t)proc);
}

/* ---- T0-X：stdio 管道 / 进程组 / 信号 / 环境枚举 ---- */

int64_t xdkc_p_proc_spawn_piped_simple(const char *cmd, size_t len) {
    int32_t code = 0;
    void *p = proc_spawn_internal(cmd, len, &code, 1);
    if (code != 0 || p == NULL) {
        return 0;
    }
    return (int64_t)(intptr_t)p;
}

int32_t xdkc_p_proc_pid_simple(int64_t proc) {
    proc_t *p = (proc_t *)(intptr_t)proc;
    return p == NULL ? -1 : (int32_t)p->pid;
}

int32_t xdkc_p_proc_signal_group_simple(int64_t proc, int32_t sig) {
    proc_t *p = (proc_t *)(intptr_t)proc;
    if (p == NULL || p->reaped || sig <= 0) {
        return 1;
    }
    return kill(-p->pid, sig) == 0 ? 0 : 2;
}

static char  *xdk_pipe_out_buf = NULL;
static size_t xdk_pipe_out_cap = 0;
static char  *xdk_pipe_err_buf = NULL;
static size_t xdk_pipe_err_cap = 0;

static int proc_hex_value(int c) {
    if (c >= '0' && c <= '9') { return c - '0'; }
    if (c >= 'a' && c <= 'f') { return c - 'a' + 10; }
    if (c >= 'A' && c <= 'F') { return c - 'A' + 10; }
    return -1;
}

static const char *proc_fd_read_hex(int *fdp, int64_t maximum, int read_all,
                                    char **store, size_t *store_cap) {
    static const char empty[] = "";
    static const char hex[] = "0123456789abcdef";
    if (fdp == NULL || *fdp < 0) {
        return empty;
    }
    int fd = *fdp;
    size_t cap = 4096;
    size_t n = 0;
    char *buf = malloc(cap);
    if (buf == NULL) {
        return empty;
    }
    for (;;) {
        size_t want = cap - n - 1;
        if (!read_all) {
            int64_t left = maximum - (int64_t)n;
            if (left <= 0) {
                break;
            }
            if ((size_t)left < want) {
                want = (size_t)left;
            }
        }
        if (want == 0) {
            if (read_all) {
                cap *= 2;
                char *nb = realloc(buf, cap);
                if (nb == NULL) { free(buf); return empty; }
                buf = nb;
                continue;
            }
            break;
        }
        ssize_t got = read(fd, buf + n, want);
        if (got < 0) {
            if (errno == EINTR) {
                continue;
            }
            break;
        }
        if (got == 0) {
            (void)close(fd);
            *fdp = -1;
            break;
        }
        n += (size_t)got;
        if (!read_all && (int64_t)n >= maximum) {
            break;
        }
    }
    size_t need = n * 2 + 1;
    if (need > *store_cap) {
        char *nb = realloc(*store, need);
        if (nb == NULL) {
            free(buf);
            return empty;
        }
        *store = nb;
        *store_cap = need;
    }
    for (size_t i = 0; i < n; i++) {
        unsigned char v = (unsigned char)buf[i];
        (*store)[i * 2] = hex[v >> 4];
        (*store)[i * 2 + 1] = hex[v & 15];
    }
    (*store)[n * 2] = 0;
    free(buf);
    return *store;
}

const char *xdkc_p_proc_read_stdout_hex(int64_t proc, int64_t maximum) {
    proc_t *p = (proc_t *)(intptr_t)proc;
    if (p == NULL) {
        return "";
    }
    return proc_fd_read_hex(&p->out_fd, maximum, 0, &xdk_pipe_out_buf, &xdk_pipe_out_cap);
}

const char *xdkc_p_proc_read_stderr_hex(int64_t proc, int64_t maximum) {
    proc_t *p = (proc_t *)(intptr_t)proc;
    if (p == NULL) {
        return "";
    }
    return proc_fd_read_hex(&p->err_fd, maximum, 0, &xdk_pipe_err_buf, &xdk_pipe_err_cap);
}

const char *xdkc_p_proc_read_all_stdout_hex(int64_t proc) {
    proc_t *p = (proc_t *)(intptr_t)proc;
    if (p == NULL) {
        return "";
    }
    return proc_fd_read_hex(&p->out_fd, 0, 1, &xdk_pipe_out_buf, &xdk_pipe_out_cap);
}

const char *xdkc_p_proc_read_all_stderr_hex(int64_t proc) {
    proc_t *p = (proc_t *)(intptr_t)proc;
    if (p == NULL) {
        return "";
    }
    return proc_fd_read_hex(&p->err_fd, 0, 1, &xdk_pipe_err_buf, &xdk_pipe_err_cap);
}

int32_t xdkc_p_proc_close_stdin(int64_t proc) {
    proc_t *p = (proc_t *)(intptr_t)proc;
    if (p == NULL || p->in_fd < 0) {
        return 0;
    }
    (void)close(p->in_fd);
    p->in_fd = -1;
    return 0;
}

int64_t xdkc_p_proc_write_stdin_hex(int64_t proc, const char *hex, size_t hlen) {
    proc_t *p = (proc_t *)(intptr_t)proc;
    if (p == NULL || p->in_fd < 0 || hex == NULL || (hlen % 2) != 0) {
        return -1;
    }
    size_t n = hlen / 2;
    if (n == 0) {
        return 0;
    }
    unsigned char *buf = malloc(n);
    if (buf == NULL) {
        return -1;
    }
    for (size_t i = 0; i < n; i++) {
        int hi = proc_hex_value((unsigned char)hex[i * 2]);
        int lo = proc_hex_value((unsigned char)hex[i * 2 + 1]);
        if (hi < 0 || lo < 0) {
            free(buf);
            return -1;
        }
        buf[i] = (unsigned char)((hi << 4) | lo);
    }
    size_t off = 0;
    while (off < n) {
        ssize_t got = write(p->in_fd, buf + off, n - off);
        if (got < 0) {
            if (errno == EINTR) {
                continue;
            }
            free(buf);
            return -1;
        }
        if (got == 0) {
            break;
        }
        off += (size_t)got;
    }
    free(buf);
    return (int64_t)off;
}

/* 信号名 → POSIX 编号；未知返回 -1。只暴露跨平台稳定的常用集合。 */
int32_t xdkc_p_signal_number(const char *name, size_t len) {
    if (name == NULL) {
        return -1;
    }
#define XDK_SIG_EQ(s) (len == sizeof(s) - 1 && memcmp(name, s, len) == 0)
    if (XDK_SIG_EQ("HUP"))  { return SIGHUP; }
    if (XDK_SIG_EQ("INT"))  { return SIGINT; }
    if (XDK_SIG_EQ("QUIT")) { return SIGQUIT; }
    if (XDK_SIG_EQ("KILL")) { return SIGKILL; }
    if (XDK_SIG_EQ("TERM")) { return SIGTERM; }
    if (XDK_SIG_EQ("USR1")) { return SIGUSR1; }
    if (XDK_SIG_EQ("USR2")) { return SIGUSR2; }
    if (XDK_SIG_EQ("PIPE")) { return SIGPIPE; }
    if (XDK_SIG_EQ("ALRM")) { return SIGALRM; }
    if (XDK_SIG_EQ("CHLD")) { return SIGCHLD; }
    if (XDK_SIG_EQ("STOP")) { return SIGSTOP; }
    if (XDK_SIG_EQ("CONT")) { return SIGCONT; }
#undef XDK_SIG_EQ
    return -1;
}

int32_t xdkc_p_signal_send(int32_t pid, int32_t sig) {
    if (pid <= 0 || sig <= 0) {
        return 1;
    }
    return kill(pid, sig) == 0 ? 0 : 2;
}

int32_t xdkc_p_signal_group(int32_t pgid, int32_t sig) {
    if (pgid <= 0 || sig <= 0) {
        return 1;
    }
    return kill(-pgid, sig) == 0 ? 0 : 2;
}

/* 环境变量名枚举：升序、'\n' 分隔、不含值；值经 envRaw(name) 读取。 */
static int env_name_cmp(const void *a, const void *b) {
    const char *const *pa = a;
    const char *const *pb = b;
    return strcmp(*pa, *pb);
}

const char *xdkc_p_env_names(void) {
    extern char **environ;
    static char *out = NULL;
    static size_t out_cap = 0;
    static const char empty[] = "";
    size_t count = 0;
    if (environ != NULL) {
        while (environ[count] != NULL) {
            count++;
        }
    }
    if (count == 0) {
        return empty;
    }
    char **names = malloc(sizeof(char *) * count);
    if (names == NULL) {
        return empty;
    }
    size_t used = 0;
    for (size_t i = 0; i < count; i++) {
        const char *entry = environ[i];
        const char *eq = strchr(entry, '=');
        size_t n = eq == NULL ? strlen(entry) : (size_t)(eq - entry);
        if (n == 0) {
            continue;
        }
        char *copy = malloc(n + 1);
        if (copy == NULL) {
            continue;
        }
        memcpy(copy, entry, n);
        copy[n] = 0;
        names[used++] = copy;
    }
    qsort(names, used, sizeof(char *), env_name_cmp);
    size_t total = 1;
    for (size_t i = 0; i < used; i++) {
        total += strlen(names[i]) + 1;
    }
    if (total > out_cap) {
        char *nb = realloc(out, total);
        if (nb == NULL) {
            for (size_t i = 0; i < used; i++) { free(names[i]); }
            free(names);
            return empty;
        }
        out = nb;
        out_cap = total;
    }
    size_t off = 0;
    for (size_t i = 0; i < used; i++) {
        size_t n = strlen(names[i]);
        memcpy(out + off, names[i], n);
        off += n;
        if (i + 1 < used) {
            out[off++] = '\n';
        }
        free(names[i]);
    }
    out[off] = 0;
    free(names);
    return out;
}

int64_t xdkc_p_proc_status(const char *cmd, size_t len) {
    return (int64_t)xdkc_proc_status(cmd, len);
}

/* ---- XDK 源码层 IO 桥（二进制/文件操作；hex 形态避开 Bytes 借出面）---- */
static char *xdk_io_hex = NULL;
static size_t xdk_io_hex_cap = 0;

static int xdk_hex_val(int c) {
    if (c >= '0' && c <= '9') { return c - '0'; }
    if (c >= 'a' && c <= 'f') { return c - 'a' + 10; }
    if (c >= 'A' && c <= 'F') { return c - 'A' + 10; }
    return -1;
}

/* 读整文件为 hex；失败返回空串，错误经 xdkc_p_fs_error 读取。 */
const char *xdkc_p_read_file_hex(const char *path, size_t len) {
    static const char hex[] = "0123456789abcdef";
    g_fs_last_error = 0;
    if (path == NULL || len == 0 || memchr(path, 0, len) != NULL) {
        g_fs_last_error = 4;
        return "";
    }
    char *p = path_dup(path, len);
    FILE *f = fopen(p, "rb");
    free(p);
    if (f == NULL) { fs_fail(); return ""; }
    size_t cap = 4096, n = 0;
    unsigned char *buf = malloc(cap);
    if (buf == NULL) { fclose(f); g_fs_last_error = 5; return ""; }
    for (;;) {
        if (n == cap) {
            cap *= 2;
            unsigned char *nb = realloc(buf, cap);
            if (nb == NULL) { free(buf); fclose(f); g_fs_last_error = 5; return ""; }
            buf = nb;
        }
        size_t got = fread(buf + n, 1, cap - n, f);
        n += got;
        if (got == 0) { break; }
    }
    int bad = ferror(f);
    fclose(f);
    if (bad) { free(buf); fs_fail(); return ""; }
    if (n * 2 + 1 > xdk_io_hex_cap) {
        char *nb = realloc(xdk_io_hex, n * 2 + 1);
        if (nb == NULL) { free(buf); g_fs_last_error = 5; return ""; }
        xdk_io_hex = nb;
        xdk_io_hex_cap = n * 2 + 1;
    }
    for (size_t i = 0; i < n; i++) {
        xdk_io_hex[i * 2] = hex[(buf[i] >> 4) & 0xF];
        xdk_io_hex[i * 2 + 1] = hex[buf[i] & 0xF];
    }
    xdk_io_hex[n * 2] = 0;
    free(buf);
    return xdk_io_hex;
}

/* 写/追加 hex 内容；append=1 追加，否则截断。0=成功。 */
int32_t xdkc_p_write_file_hex(const char *path, size_t plen,
                              const char *hex, size_t hlen, int32_t append) {
    g_fs_last_error = 0;
    if (path == NULL || plen == 0 || hex == NULL || memchr(path, 0, plen) != NULL) {
        g_fs_last_error = 4;
        return 1;
    }
    if (hlen % 2 != 0) { g_fs_last_error = 4; return 1; }
    char *p = path_dup(path, plen);
    FILE *f = fopen(p, append ? "ab" : "wb");
    free(p);
    if (f == NULL) { fs_fail(); return 1; }
    unsigned char stackbuf[1024];
    unsigned char *buf = stackbuf;
    size_t cap = sizeof(stackbuf);
    size_t n = hlen / 2;
    if (n > cap) {
        buf = malloc(n);
        if (buf == NULL) { fclose(f); g_fs_last_error = 5; return 1; }
        cap = n;
    }
    for (size_t i = 0; i < n; i++) {
        int hi = xdk_hex_val((unsigned char)hex[i * 2]);
        int lo = xdk_hex_val((unsigned char)hex[i * 2 + 1]);
        if (hi < 0 || lo < 0) {
            if (buf != stackbuf) { free(buf); }
            fclose(f);
            g_fs_last_error = 4;
            return 1;
        }
        buf[i] = (unsigned char)((hi << 4) | lo);
    }
    int rc = 0;
    if (n > 0 && fwrite(buf, 1, n, f) != n) { rc = 1; }
    if (buf != stackbuf) { free(buf); }
    if (fclose(f) != 0) { rc = 1; }
    if (rc != 0) { fs_fail(); }
    return rc;
}

int64_t xdkc_p_file_size(const char *path, size_t len) {
    g_fs_last_error = 0;
    if (path == NULL || len == 0 || memchr(path, 0, len) != NULL) {
        g_fs_last_error = 4;
        return -1;
    }
    char *p = path_dup(path, len);
    struct stat st;
    int ok = stat(p, &st) == 0 && S_ISREG(st.st_mode);
    free(p);
    if (!ok) { fs_fail(); return -1; }
    return (int64_t)st.st_size;
}

int32_t xdkc_p_file_exists(const char *path, size_t len) {
    g_fs_last_error = 0;
    if (path == NULL || len == 0 || memchr(path, 0, len) != NULL) {
        g_fs_last_error = 4;
        return 0;
    }
    char *p = path_dup(path, len);
    struct stat st;
    int ok = stat(p, &st) == 0;
    free(p);
    if (!ok) { fs_fail(); return 0; }
    return 1;
}

int32_t xdkc_p_file_remove(const char *path, size_t len) {
    g_fs_last_error = 0;
    if (path == NULL || len == 0 || memchr(path, 0, len) != NULL) {
        g_fs_last_error = 4;
        return 1;
    }
    char *p = path_dup(path, len);
    int rc = remove(p);
    free(p);
    if (rc != 0) { fs_fail(); return 1; }
    return 0;
}

int32_t xdkc_p_file_rename(const char *from, size_t flen,
                           const char *to, size_t tlen) {
    g_fs_last_error = 0;
    if (from == NULL || to == NULL || flen == 0 || tlen == 0 ||
        memchr(from, 0, flen) != NULL || memchr(to, 0, tlen) != NULL) {
        g_fs_last_error = 4;
        return 1;
    }
    char *a = path_dup(from, flen);
    char *b = path_dup(to, tlen);
    int rc = rename(a, b);
    free(a);
    free(b);
    if (rc != 0) { fs_fail(); return 1; }
    return 0;
}

int32_t xdkc_p_dir_make(const char *path, size_t len) {
    g_fs_last_error = 0;
    if (path == NULL || len == 0 || memchr(path, 0, len) != NULL) {
        g_fs_last_error = 4;
        return 1;
    }
    char *p = path_dup(path, len);
    int rc = mkdir(p, 0777);
    free(p);
    if (rc != 0) { fs_fail(); return 1; }
    return 0;
}

int32_t xdkc_p_dir_remove(const char *path, size_t len) {
    g_fs_last_error = 0;
    if (path == NULL || len == 0 || memchr(path, 0, len) != NULL) {
        g_fs_last_error = 4;
        return 1;
    }
    char *p = path_dup(path, len);
    int rc = rmdir(p);
    free(p);
    if (rc != 0) { fs_fail(); return 1; }
    return 0;
}

int32_t xdkc_p_append_file_text(const char *path, size_t plen,
                                const char *text, size_t tlen) {
    g_fs_last_error = 0;
    if (path == NULL || plen == 0 || memchr(path, 0, plen) != NULL) {
        g_fs_last_error = 4;
        return 1;
    }
    char *p = path_dup(path, plen);
    FILE *f = fopen(p, "ab");
    free(p);
    if (f == NULL) { fs_fail(); return 1; }
    int rc = 0;
    if (tlen > 0 && fwrite(text, 1, tlen, f) != tlen) { rc = 1; }
    if (fclose(f) != 0) { rc = 1; }
    if (rc != 0) { fs_fail(); }
    return rc;
}

/* runProcessResult：捕获子进程 stdout（shell 语义，stderr 不捕获）。 */
static char   *xdk_proc_out = NULL;
static size_t  xdk_proc_out_cap = 0;
static int32_t xdk_proc_last_status = -1;

const char *xdkc_p_proc_output(const char *cmd, size_t len) {
    static const char empty[] = "";
    xdk_proc_last_status = -1;
    if (cmd == NULL || len == 0) { return empty; }
    char *c = path_dup(cmd, len);
    FILE *p = popen(c, "r");
    free(c);
    if (p == NULL) { return empty; }
    size_t cap = 4096, n = 0;
    char *buf = malloc(cap);
    if (buf == NULL) { pclose(p); return empty; }
    for (;;) {
        if (n + 1 >= cap) {
            cap *= 2;
            char *nb = realloc(buf, cap);
            if (nb == NULL) { free(buf); pclose(p); return empty; }
            buf = nb;
        }
        size_t got = fread(buf + n, 1, cap - n - 1, p);
        n += got;
        if (got == 0) { break; }
    }
    int st = pclose(p);
    buf[n] = 0;
    if (n + 1 > xdk_proc_out_cap) {
        char *nb = realloc(xdk_proc_out, n + 1);
        if (nb == NULL) { free(buf); return empty; }
        xdk_proc_out = nb;
        xdk_proc_out_cap = n + 1;
    }
    memcpy(xdk_proc_out, buf, n + 1);
    free(buf);
    if (st != -1 && WIFEXITED(st)) {
        xdk_proc_last_status = (int32_t)WEXITSTATUS(st);
    }
    return xdk_proc_out;
}

int32_t xdkc_p_proc_last_status(void) {
    return xdk_proc_last_status;
}
