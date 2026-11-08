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
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <signal.h>
#include <unistd.h>

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
        return NULL;
    }
    char *p = path_dup(bytes, len);
    FILE *f = fopen(p, "rb");
    free(p);
    if (f == NULL) {
        g_read_file_text_error = 2;
        return NULL;
    }
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        g_read_file_text_error = 2;
        return NULL;
    }
    long n = ftell(f);
    if (n < 0 || (size_t)n > XDK_READ_FILE_TEXT_MAX || fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        g_read_file_text_error = 2;
        return NULL;
    }
    size_t need = (size_t)n + 1;
    if (need > g_text_cap) {
        char *nb = realloc(g_text_buf, need);
        if (nb == NULL) {
            fclose(f);
            g_read_file_text_error = 2;
            return NULL;
        }
        g_text_buf = nb;
        g_text_cap = need;
    }
    size_t got = fread(g_text_buf, 1, (size_t)n, f);
    int bad = ferror(f);
    fclose(f);
    if (bad || got != (size_t)n) {
        g_read_file_text_error = 2;
        return NULL;
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
} proc_t;

void *xdkc_proc_spawn(const char *cmd, size_t len, int32_t *code) {
    if (cmd == NULL) {
        xrt_fatal("procSpawn：命令为空（S6 §4.7）");
    }
    char *c = malloc(len + 1);
    if (c == NULL) {
        xrt_fatal("procSpawn：内存不足（S6 §4.7）");
    }
    memcpy(c, cmd, len);
    c[len] = 0;
    pid_t pid = fork();
    if (pid == 0) {
        execl("/bin/sh", "sh", "-c", c, (char *)NULL);
        _exit(127);
    }
    free(c);
    if (pid < 0) {
        if (code != NULL) {
            *code = 2;
        }
        return NULL;
    }
    proc_t *p = malloc(sizeof(*p));
    if (p == NULL) {
        xrt_fatal("procSpawn：内存不足（S6 §4.7）");
    }
    p->pid = pid;
    p->reaped = 0;
    p->status = 0;
    if (code != NULL) {
        *code = 0;
    }
    return p;
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

/* close 必达：未终结则 SIGKILL + reap；幂等（reaped 后只释放）。 */
int32_t xdkc_proc_close(void *proc) {
    proc_t *p = proc;
    if (p == NULL) {
        return 0;
    }
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
