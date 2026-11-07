/* test_std.c — XDK C 层原语测试（M4.6a/b）
 *
 * 覆盖：diagnose 单行折叠、exit 不执行 atexit、时钟合同、env 不可变快照、
 * 严格解析/格式化、UTF-8↔UTF-16（含代理对与非法序列）、文件读写与幂等关闭。
 */
#define _POSIX_C_SOURCE 200809L

#define XRT_BINDINGS_LAYER 1
#include "xrt.h"
#include "rt_gc.h"

#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

/* C 层原型（测试直接调用，不经 .xfb 包装） */
void        xdkc_diagnose(const char *bytes, size_t len);
void        xdkc_exit(int64_t code);
int64_t     xdkc_now_mono_ms(void);
int64_t     xdkc_now_wall_ms(void);
const char *xdkc_env_get(const char *name, size_t len, size_t *out_len);
int32_t     xdkc_parse_int(const char *bytes, size_t len, int64_t *out);
int32_t     xdkc_parse_float(const char *bytes, size_t len, double *out);
int64_t     xdkc_format_int(int64_t v, char *buf, size_t cap);
int32_t     xdkc_utf8_valid(const char *bytes, size_t len);
int64_t     xdkc_utf8_to_utf16(const char *src, size_t n, uint16_t *dst, size_t cap);
int64_t     xdkc_utf16_to_utf8(const uint16_t *src, size_t n, char *dst, size_t cap);
void       *xdkc_file_open_read(const char *bytes, size_t len);
void       *xdkc_file_open_write(const char *bytes, size_t len);
int64_t     xdkc_file_read(void *fp, void *buf, size_t cap, int32_t *code);
int32_t     xdkc_file_write(void *fp, const void *buf, size_t n);
int32_t     xdkc_file_close(void *fp);
void       *xdkc_dir_open(const char *path, size_t len);
const char *xdkc_dir_read(void *dp);
int32_t     xdkc_dir_close(void *dp);
int32_t     xdkc_path_exists(const char *path, size_t len);
int32_t     xdkc_proc_status(const char *cmd, size_t len);
int32_t     xdkc_regex_match(const char *pat, size_t plen, const char *sub, size_t slen);
int64_t     xdkc_fmt_append_raw(char *buf, size_t cap, size_t *off, const char *src, size_t n);
int64_t     xdkc_fmt_append_int(char *buf, size_t cap, size_t *off, int64_t v);

static int g_failures = 0;

#define CHECK(cond)                                                          \
    do {                                                                     \
        if (!(cond)) {                                                       \
            g_failures++;                                                    \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);   \
        }                                                                    \
    } while (0)

static void test_diagnose(void) {
    /* 把 stderr 重定向到临时文件，验证"单行折叠 + 换行结尾" */
    FILE *tmp = tmpfile();
    CHECK(tmp != NULL);
    if (tmp == NULL) {
        return;
    }
    int saved = dup(STDERR_FILENO);
    CHECK(saved >= 0);
    CHECK(dup2(fileno(tmp), STDERR_FILENO) >= 0);
    xdkc_diagnose("line1\nline2", 11);
    CHECK(fflush(stderr) == 0);
    CHECK(dup2(saved, STDERR_FILENO) >= 0);
    close(saved);

    CHECK(fseek(tmp, 0, SEEK_SET) == 0);
    char buf[64];
    size_t n = fread(buf, 1, sizeof(buf) - 1, tmp);
    buf[n] = 0;
    CHECK(strcmp(buf, "line1 line2\n") == 0);
    fclose(tmp);
}

static char g_atexit_path[64];

static void mark_atexit(void) {
    FILE *f = fopen(g_atexit_path, "ab");
    if (f != NULL) {
        fwrite("x", 1, 1, f);
        fclose(f);
    }
}

static void test_exit_skips_atexit(void) {
    char path[] = "/tmp/xnull_exit_testXXXXXX";
    int fd = mkstemp(path);
    CHECK(fd >= 0);
    if (fd < 0) {
        return;
    }
    close(fd);
    snprintf(g_atexit_path, sizeof(g_atexit_path), "%s", path);

    char out_path[] = "/tmp/xnull_exit_outXXXXXX";
    int ofd = mkstemp(out_path);
    CHECK(ofd >= 0);
    if (ofd < 0) {
        unlink(path);
        return;
    }

    pid_t pid = fork();
    CHECK(pid >= 0);
    if (pid == 0) {
        /* 子进程：stdout 重定向到文件；注册 atexit 后 exit(7)。
         * 期望：handler 不执行、退出码 7、exit 前的输出已冲刷。 */
        CHECK(dup2(ofd, STDOUT_FILENO) >= 0);
        close(ofd);
        atexit(mark_atexit);
        printf("before-exit\n");
        xdkc_exit(7);
        _exit(3); /* 不应到达 */
    }
    close(ofd);
    int status = 0;
    CHECK(waitpid(pid, &status, 0) == pid);
    CHECK(WIFEXITED(status));
    CHECK(WEXITSTATUS(status) == 7);

    struct stat st;
    CHECK(stat(path, &st) == 0);
    CHECK(st.st_size == 0); /* atexit 未执行（S1 §10.3） */

    /* exit 只跳过 defer/atexit，不丢已产生的输出：stdio 缓冲先冲刷。 */
    FILE *f = fopen(out_path, "rb");
    CHECK(f != NULL);
    if (f != NULL) {
        char buf[32] = {0};
        size_t n = fread(buf, 1, sizeof(buf) - 1, f);
        fclose(f);
        CHECK(n == 12 && memcmp(buf, "before-exit\n", 12) == 0);
    }
    unlink(path);
    unlink(out_path);
}

static void test_clocks(void) {
    int64_t m1 = xdkc_now_mono_ms();
    int64_t m2 = xdkc_now_mono_ms();
    CHECK(m2 >= m1);
    int64_t w = xdkc_now_wall_ms();
    CHECK(w > 1700000000000LL); /* 2023 之后，UTC 毫秒 */
}

static void test_env_snapshot(void) {
    CHECK(setenv("XNULL_STD_TEST_ENV", "v1", 1) == 0);
    size_t n = 0;
    const char *v = xdkc_env_get("XNULL_STD_TEST_ENV", 19, &n);
    CHECK(v != NULL);
    if (v != NULL) {
        CHECK(n == 2);
        CHECK(memcmp(v, "v1", 2) == 0);
    }
    /* 快照：进程内后续变更不可见 */
    CHECK(setenv("XNULL_STD_TEST_ENV", "v2", 1) == 0);
    v = xdkc_env_get("XNULL_STD_TEST_ENV", 19, &n);
    CHECK(v != NULL && n == 2 && memcmp(v, "v1", 2) == 0);

    v = xdkc_env_get("XNULL_STD_ABSENT_ENV", 20, &n);
    CHECK(v == NULL && n == 0);
}

static void test_parse_format(void) {
    int64_t v = 0;
    CHECK(xdkc_parse_int("42", 2, &v) == 0 && v == 42);
    CHECK(xdkc_parse_int("-7", 2, &v) == 0 && v == -7);
    CHECK(xdkc_parse_int("4x", 2, &v) == 1);
    CHECK(xdkc_parse_int("", 0, &v) == 1);
    CHECK(xdkc_parse_int("9223372036854775808", 19, &v) == 2);

    double d = 0;
    CHECK(xdkc_parse_float("3.5", 3, &d) == 0 && d > 3.49 && d < 3.51);
    CHECK(xdkc_parse_float("3.5x", 4, &d) == 1);

    char buf[8];
    CHECK(xdkc_format_int(-123, buf, sizeof(buf)) == 4 && strcmp(buf, "-123") == 0);
    CHECK(xdkc_format_int(12345, buf, 4) == -1); /* 缓冲不足 */
}

static void test_utf(void) {
    const char *s = "a\xF0\x9F\x98\x80" "b"; /* a😀b */
    size_t n = strlen(s);
    uint16_t u16[8];
    int64_t units = xdkc_utf8_to_utf16(s, n, u16, 8);
    CHECK(units == 4);
    char back[16];
    int64_t bytes = xdkc_utf16_to_utf8(u16, (size_t)units, back, sizeof(back));
    CHECK(bytes == (int64_t)n);
    CHECK(memcmp(back, s, n) == 0);

    CHECK(xdkc_utf8_to_utf16("\xC0\x80", 2, u16, 8) == -1); /* 过短编码 */
    CHECK(xdkc_utf8_to_utf16("\xED\xA0\x80", 3, u16, 8) == -1); /* 代理区 */
    CHECK(xdkc_utf8_to_utf16("abc", 3, u16, 2) == -1); /* 目标不足 */
}

/* B1-03 第 4 项诊断入口：字节级 UTF-8 合法性（0 合法 / 1 非法）。 */
static void test_utf8_valid(void) {
    CHECK(xdkc_utf8_valid("", 0) == 0);
    CHECK(xdkc_utf8_valid("abc", 3) == 0);
    CHECK(xdkc_utf8_valid("a\xF0\x9F\x98\x80" "b", 6) == 0); /* 4 字节码点 */
    CHECK(xdkc_utf8_valid("\xE4\xB8\xAD", 3) == 0);          /* 3 字节码点 */
    CHECK(xdkc_utf8_valid("a\0b", 3) == 0);                  /* 内嵌 NUL 合法 */
    CHECK(xdkc_utf8_valid(NULL, 0) == 0);

    CHECK(xdkc_utf8_valid("\x80", 1) == 1);                  /* 孤立续字节 */
    CHECK(xdkc_utf8_valid("\xC0\x80", 2) == 1);              /* 过短编码 */
    CHECK(xdkc_utf8_valid("\xE0\x80\x80", 3) == 1);          /* 过短编码 */
    CHECK(xdkc_utf8_valid("\xF0\x80\x80\x80", 4) == 1);      /* 过短编码 */
    CHECK(xdkc_utf8_valid("\xED\xA0\x80", 3) == 1);          /* 代理区 */
    CHECK(xdkc_utf8_valid("\xF4\x90\x80\x80", 4) == 1);      /* > U+10FFFF */
    CHECK(xdkc_utf8_valid("\xE4\xB8", 2) == 1);              /* 截断 */
    CHECK(xdkc_utf8_valid("\xFF", 1) == 1);                  /* 非法首字节 */
    CHECK(xdkc_utf8_valid(NULL, 1) == 1);
}

/* BYTES-RUNTIME（B0-07c）：可变字节缓冲的构造/读写/追加/切片与越界终止。 */
static void test_bytes(void) {
    xrt_bytes_buf *b = xrt_bytes_from_c("abc", 3);
    CHECK(xrt_bytes_len(b) == 3);
    CHECK(xrt_bytes_get(b, 0) == 'a');
    xrt_bytes_set(b, 0, 'A');
    CHECK(xrt_bytes_get(b, 0) == 'A');

    xrt_bytes_push(b, 0);
    xrt_bytes_push(b, 255);
    CHECK(xrt_bytes_len(b) == 5);
    CHECK(xrt_bytes_get(b, 3) == 0);
    CHECK(xrt_bytes_get(b, 4) == 255);
    CHECK(memcmp(xrt_bytes_data(b), "Abc\0\xff", 5) == 0);

    xrt_bytes_buf *a = xrt_bytes_from_c("XY", 2);
    xrt_bytes_append(b, a);
    CHECK(xrt_bytes_len(b) == 7);
    CHECK(memcmp(xrt_bytes_data(b), "Abc\0\xffXY", 7) == 0);
    xrt_release(a);

    xrt_bytes_buf *s = xrt_bytes_slice(b, 1, 3);
    CHECK(xrt_bytes_len(s) == 2);
    CHECK(memcmp(xrt_bytes_data(s), "bc", 2) == 0);
    xrt_release(s);

    xrt_bytes_buf *z = xrt_bytes_alloc(4);
    CHECK(xrt_bytes_len(z) == 4);
    CHECK(((const unsigned char *)xrt_bytes_data(z))[3] == 0);
    xrt_release(z);

    xrt_bytes_buf *e = xrt_bytes_new();
    CHECK(xrt_bytes_len(e) == 0);
    xrt_bytes_push(e, 7); /* 空缓冲扩容路径 */
    CHECK(xrt_bytes_len(e) == 1);
    xrt_release(e);

    xrt_bytes_buf *self = xrt_bytes_from_c("pq", 2);
    xrt_bytes_append(self, self); /* 自追加：扩容后仍按原长度复制 */
    CHECK(xrt_bytes_len(self) == 4);
    CHECK(memcmp(xrt_bytes_data(self), "pqpq", 4) == 0);
    xrt_release(self);

    xrt_release(b);
}

/* 越界访问必须终止进程（S1 §9.7 panic），不得静默截断。 */
static void test_bytes_bounds(void) {
    pid_t pid = fork();
    if (pid == 0) {
        FILE *null = freopen("/dev/null", "w", stderr);
        (void)null;
        xrt_bytes_buf *b = xrt_bytes_from_c("a", 1);
        (void)xrt_bytes_get(b, 1);
        _exit(0);
    }
    int st = 0;
    CHECK(pid > 0);
    if (pid > 0) {
        CHECK(waitpid(pid, &st, 0) == pid);
        CHECK(!(WIFEXITED(st) && WEXITSTATUS(st) == 0));
    }
}

/* Bytes 与文件原语的联合路径：证实运行时可作为 FFI 借出缓冲（data/len）直接使用。 */
static void test_bytes_file_io(void) {
    char path[] = "/tmp/xnull_std_bytesXXXXXX";
    int fd = mkstemp(path);
    CHECK(fd >= 0);
    if (fd < 0) {
        return;
    }
    CHECK(write(fd, "AB", 2) == 2);
    close(fd);

    void *fp = xdkc_file_open_read(path, strlen(path));
    CHECK(fp != NULL);
    xrt_bytes_buf *b = xrt_bytes_alloc(8);
    int32_t code = -1;
    int64_t got = xdkc_file_read(fp, xrt_bytes_data(b), xrt_bytes_len(b), &code);
    CHECK(code == 0);
    CHECK(got == 2);
    CHECK(xrt_bytes_get(b, 0) == 'A');
    CHECK(xrt_bytes_get(b, 1) == 'B');
    CHECK(xdkc_file_close(fp) == 0);

    char out[] = "/tmp/xnull_std_bytes_outXXXXXX";
    int ofd = mkstemp(out);
    CHECK(ofd >= 0);
    if (ofd >= 0) {
        close(ofd);
        void *wf = xdkc_file_open_write(out, strlen(out));
        CHECK(wf != NULL);
        xrt_bytes_buf *w = xrt_bytes_from_c("A\0B", 3);
        CHECK(xdkc_file_write(wf, xrt_bytes_data(w), xrt_bytes_len(w)) == 0);
        CHECK(xdkc_file_close(wf) == 0);

        char back[4] = {0};
        int rfd = open(out, O_RDONLY);
        CHECK(rfd >= 0);
        if (rfd >= 0) {
            CHECK(read(rfd, back, sizeof(back)) == 3);
            CHECK(memcmp(back, "A\0B", 3) == 0); /* 内嵌 NUL 按长度保留 */
            close(rfd);
        }
        unlink(out);
        xrt_release(w);
    }
    unlink(path);
    xrt_release(b);
}

/* S3-07：trampoline env 生命周期（创建登记根 → 调用 → 销毁注销 → 调用终止）。 */
static int32_t g_cb_calls = 0;

static int32_t test_callback(void *closure, const void *args, size_t nargs, void *result) {
    g_cb_calls++;
    (void)closure;
    (void)args;
    (void)nargs;
    if (result != NULL) {
        *(int32_t *)result = 42;
    }
    return 7;
}

static void test_callback_env(void) {
    int marker = 0;
    xrt_callback_env *env = xrt_callback_env_new(&marker, test_callback);
    CHECK(env != NULL);
    CHECK(xrt_callback_env_alive(env) == 1);
    CHECK(xrt_callback_env_closure(env) == &marker);

    int32_t out = 0;
    CHECK(xrt_callback_env_invoke(env, NULL, 0, &out) == 7);
    CHECK(out == 42);
    CHECK(g_cb_calls == 1);

    xrt_callback_env_destroy(env);
    CHECK(xrt_callback_env_alive(env) == 0);
    xrt_callback_env_destroy(env); /* 幂等 */
    CHECK(xrt_callback_env_alive(env) == 0);

    /* 已注销 env 再调用必须终止进程（S7 §5.2） */
    pid_t pid = fork();
    if (pid == 0) {
        FILE *null = freopen("/dev/null", "w", stderr);
        (void)null;
        (void)xrt_callback_env_invoke(env, NULL, 0, NULL);
        _exit(0);
    }
    int st = 0;
    CHECK(pid > 0);
    if (pid > 0) {
        CHECK(waitpid(pid, &st, 0) == pid);
        CHECK(!(WIFEXITED(st) && WEXITSTATUS(st) == 0));
    }
}

/* S6-02：xdk.runtime env 入口 + exit 不执行 defer/atexit（S1 §10.3）。 */
const char *xdkc_env_lookup(const char *name, size_t len);

static int g_atexit_fd = -1;

static void atexit_marker(void) {
    if (g_atexit_fd >= 0) {
        ssize_t w = write(g_atexit_fd, "x", 1);
        (void)w;
    }
}

static void test_runtime_env_exit(void) {
    CHECK(setenv("XNULL_S602_ENV", "abc", 1) == 0);
    const char *v = xdkc_env_lookup("XNULL_S602_ENV", sizeof("XNULL_S602_ENV") - 1);
    CHECK(v != NULL && strcmp(v, "abc") == 0);
    CHECK(xdkc_env_lookup("XNULL_S602_MISSING", sizeof("XNULL_S602_MISSING") - 1) == NULL);

    /* exit 不执行 atexit/defer；退出码透传 */
    int fds[2];
    CHECK(pipe(fds) == 0);
    pid_t pid = fork();
    if (pid == 0) {
        close(fds[0]);
        g_atexit_fd = fds[1];
        atexit(atexit_marker);
        xdkc_exit(7);
        _exit(0);
    }
    close(fds[1]);
    char buf[8];
    ssize_t n = read(fds[0], buf, sizeof(buf));
    close(fds[0]);
    int st = 0;
    CHECK(pid > 0 && waitpid(pid, &st, 0) == pid);
    CHECK(WIFEXITED(st) && WEXITSTATUS(st) == 7);
    CHECK(n == 0); /* atexit 未执行 */
}

/* S4 §9：诊断通道合同——无堆分配、单行、无附加敏感信息；ErrorKind 骨架。 */
static ssize_t read_all(int fd, char *buf, size_t cap) {
    size_t off = 0;
    while (off + 1 < cap) {
        ssize_t n = read(fd, buf + off, cap - off - 1);
        if (n <= 0) {
            break;
        }
        off += (size_t)n;
    }
    buf[off] = 0;
    return (ssize_t)off;
}

static void test_diagnose_contract(void) {
    /* 无堆分配：诊断调用前后 runtime 分配计数不变 */
    xrt_stats before, after;
    xrt_stats_reset();
    xrt_stats_set_enabled(1);
    xrt_stats_get(&before);
    xdkc_diagnose("a\nb", 3);
    xrt_stats_get(&after);
    CHECK(after.allocs == before.allocs);
    xrt_stats_set_enabled(0);

    /* 单行 + 控制字符折叠 */
    int fds[2];
    CHECK(pipe(fds) == 0);
    pid_t pid = fork();
    if (pid == 0) {
        close(fds[0]);
        dup2(fds[1], STDERR_FILENO);
        close(fds[1]);
        xdkc_diagnose("l1\nl2\rx", sizeof("l1\nl2\rx") - 1);
        _exit(0);
    }
    close(fds[1]);
    char buf[256];
    read_all(fds[0], buf, sizeof(buf));
    close(fds[0]);
    int st = 0;
    CHECK(pid > 0 && waitpid(pid, &st, 0) == pid);
    CHECK(strstr(buf, "l1 l2 x") != NULL);
    CHECK(strchr(buf, '\r') == NULL);
    int lines = 0;
    for (const char *p = buf; *p; p++) {
        if (*p == '\n') {
            lines++;
        }
    }
    CHECK(lines == 1);
}

static void test_fatal_contract(void) {
    int fds[2];
    CHECK(pipe(fds) == 0);
    pid_t pid = fork();
    if (pid == 0) {
        close(fds[0]);
        dup2(fds[1], STDERR_FILENO);
        close(fds[1]);
        rt_fatal("bad\nline\x01x");
        _exit(0);
    }
    close(fds[1]);
    char buf[512];
    read_all(fds[0], buf, sizeof(buf));
    close(fds[0]);
    int st = 0;
    CHECK(pid > 0 && waitpid(pid, &st, 0) == pid);
    CHECK(!(WIFEXITED(st) && WEXITSTATUS(st) == 0));
    CHECK(strncmp(buf, "xnull runtime fatal: ", 21) == 0);
    CHECK(strstr(buf, "bad line?x") != NULL);
    int lines = 0;
    for (const char *p = buf; *p; p++) {
        if (*p == '\n') {
            lines++;
        }
    }
    CHECK(lines == 1); /* 无调用栈、无附加行 */
}

static void test_error_kind_skeleton(void) {
    CHECK(XRT_ERR_INVALID_ARGUMENT == 0);
    CHECK(XRT_ERR_TIMEOUT == 6);
    CHECK(XRT_ERR_CANCELLED == 7);
    CHECK(XRT_ERR_INTERNAL == 13);
    CHECK(strcmp(xrt_error_kind_name(XRT_ERR_TIMEOUT), "Timeout") == 0);
    CHECK(strcmp(xrt_error_kind_name(XRT_ERR_CANCELLED), "Cancelled") == 0);
    CHECK(xrt_error_kind_parse("Timeout") == XRT_ERR_TIMEOUT);
    CHECK(xrt_error_kind_parse("Cancelled") == XRT_ERR_CANCELLED);
    CHECK(xrt_error_kind_parse("Invalid") == XRT_ERR_INVALID_ARGUMENT);
    CHECK(xrt_error_kind_parse("Limit") == XRT_ERR_BUSY);
    CHECK(xrt_error_kind_parse("nope") == XRT_ERR_INTERNAL);
    CHECK(xrt_error_kind_parse(NULL) == XRT_ERR_INTERNAL);
}

/* S3-04：String/Text/Bytes/StringBuilder 均为 GC 对象（kind/弱引用/收集释放）。 */
static void test_s304_gc_types(void) {
    xrt_string *str = xrt_string_new("gc", 2);
    CHECK(((rt_object *)str)->hdr.kind == RT_KIND_GC);
    xrt_weak_slot *ws = xrt_weak_bind(str);
    CHECK(xrt_weak_read(ws) == str);
    rt_release(str);              /* GC：no-op */
    CHECK(xrt_weak_read(ws) == str);
    rt_gc_collect();              /* 不可达 → 回收 */
    CHECK(xrt_weak_read(ws) == NULL);
    xrt_weak_clear(ws);

    xrt_bytes_buf *by = xrt_bytes_from_c("abc", 3);
    CHECK(((rt_object *)by)->hdr.kind == RT_KIND_GC);
    xrt_weak_slot *wb = xrt_weak_bind(by);
    rt_release(by);
    rt_gc_collect();
    CHECK(xrt_weak_read(wb) == NULL);
    xrt_weak_clear(wb);

    xrt_text *tx = xrt_text_from_string("hello", 5);
    CHECK(((rt_object *)tx)->hdr.kind == RT_KIND_GC);
    CHECK(xrt_text_length(tx) == 5);
    CHECK(xrt_text_code_point_count(tx) == 5);
    xrt_weak_slot *wt = xrt_weak_bind(tx);
    rt_gc_collect();
    CHECK(xrt_weak_read(wt) == NULL);
    xrt_weak_clear(wt);

    xrt_sb *sb = xrt_sb_new();
    CHECK(((rt_object *)sb)->hdr.kind == RT_KIND_GC);
    xrt_sb_append_str(sb, "x", 1);
    xrt_sb_append_int(sb, 42);
    CHECK(xrt_sb_length(sb) == 3);
    xrt_weak_slot *wq = xrt_weak_bind(sb);
    rt_gc_collect();
    CHECK(xrt_weak_read(wq) == NULL);
    xrt_weak_clear(wq);
}

/* S3-08：分配统计与 GC 指标（默认关闭，显式打开）。 */
static void test_stats(void) {
    xrt_stats s;
    xrt_stats_reset();
    xrt_stats_set_enabled(1);

    xrt_string *str = xrt_string_new("stats", 5); /* String 为 GC 对象 */
    (void)str;
    rt_gc_collect(); /* 不可达 → 清扫，frees/gc_freed 计数 */

    xrt_callback_env *env = xrt_callback_env_new(NULL, NULL);
    xrt_callback_env_destroy(env);
    rt_gc_collect(); /* 注销根后回收 → gc_freed 计数 */

    xrt_stats_get(&s);
    CHECK(s.allocs >= 2);
    CHECK(s.frees >= 1);
    CHECK(s.bytes > 0);
    CHECK(s.gc_collections >= 1);
    CHECK(s.gc_freed >= 1);
    xrt_stats_set_enabled(0);
}

static void test_files(void) {
    char path[] = "/tmp/xnull_std_fileXXXXXX";
    int fd = mkstemp(path);
    CHECK(fd >= 0);
    if (fd < 0) {
        return;
    }
    const char *payload = "xnull-io";
    CHECK(write(fd, payload, 8) == 8);
    close(fd);

    void *fp = xdkc_file_open_read(path, strlen(path));
    CHECK(fp != NULL);
    char buf[16];
    int32_t code = -1;
    int64_t got = xdkc_file_read(fp, buf, sizeof(buf), &code);
    CHECK(code == 0);
    CHECK(got == 8 && memcmp(buf, payload, 8) == 0);

    got = xdkc_file_read(fp, buf, sizeof(buf), &code);
    CHECK(code == 0 && got == 0); /* 读到末尾 */

    CHECK(xdkc_file_close(fp) == 0);
    CHECK(xdkc_file_close(NULL) == 0); /* 幂等 */

    void *missing = xdkc_file_open_read("/tmp/xnull_no_such_file_xyz", 28);
    CHECK(missing == NULL);
    unlink(path);
}

static void test_dirs_procs(void) {
    char dir[64];
    snprintf(dir, sizeof(dir), "/tmp/xnull_std_dir_%d", (int)getpid());
    CHECK(mkdir(dir, 0755) == 0);
    char f1[128];
    snprintf(f1, sizeof(f1), "%s/one.txt", dir);
    FILE *f = fopen(f1, "wb");
    CHECK(f != NULL);
    if (f != NULL) {
        fclose(f);
    }

    void *dp = xdkc_dir_open(dir, strlen(dir));
    CHECK(dp != NULL);
    int entries = 0, saw_one = 0;
    if (dp != NULL) {
        const char *name;
        while ((name = xdkc_dir_read(dp)) != NULL) {
            entries++;
            if (strcmp(name, "one.txt") == 0) {
                saw_one = 1;
            }
        }
        CHECK(xdkc_dir_close(dp) == 0);
        CHECK(xdkc_dir_close(NULL) == 0); /* 幂等 */
    }
    CHECK(entries >= 3); /* . .. one.txt */
    CHECK(saw_one == 1);
    CHECK(xdkc_dir_open("/tmp/xnull_no_such_dir_xyz", 27) == NULL);

    CHECK(xdkc_path_exists(f1, strlen(f1)) == 1);
    CHECK(xdkc_path_exists("/tmp/xnull_no_such_file_qq", 28) == 0);

    CHECK(xdkc_proc_status("true", 4) == 0);
    CHECK(xdkc_proc_status("exit 7", 6) == 7);
    CHECK(xdkc_proc_status("", 0) == -1);

    unlink(f1);
    rmdir(dir);
}

static void test_regex_fmt(void) {
    CHECK(xdkc_regex_match("a+b", 3, "xaab", 4) == 0);
    CHECK(xdkc_regex_match("a+b", 3, "xyz", 3) == 1);
    CHECK(xdkc_regex_match("^ab$", 4, "ab", 2) == 0);
    CHECK(xdkc_regex_match("^ab$", 4, "xab", 3) == 1);
    CHECK(xdkc_regex_match("[", 1, "a", 1) == 2); /* 语法错误显式区分 */
    CHECK(xdkc_regex_match("a+b", 3, "", 0) == 1);

    char buf[16];
    size_t off = 0;
    CHECK(xdkc_fmt_append_int(buf, sizeof(buf), &off, 42) == 2 && off == 2);
    CHECK(xdkc_fmt_append_raw(buf, sizeof(buf), &off, "x", 1) == 3);
    CHECK(xdkc_fmt_append_int(buf, sizeof(buf), &off, 7) == 4);
    CHECK(off == 4 && memcmp(buf, "42x7", 4) == 0);
    /* 填满到 16 字节后再追加：容量不足且失败不推进游标 */
    CHECK(xdkc_fmt_append_raw(buf, sizeof(buf), &off, "012345678901", 12) == 16);
    CHECK(xdkc_fmt_append_int(buf, sizeof(buf), &off, 1) == -1);
    CHECK(off == 16);
}

int main(void) {
    test_diagnose();
    test_exit_skips_atexit();
    test_clocks();
    test_env_snapshot();
    test_parse_format();
    test_utf();
    test_utf8_valid();
    test_bytes();
    test_bytes_bounds();
    test_bytes_file_io();
    test_callback_env();
    test_s304_gc_types();
    test_diagnose_contract();
    test_fatal_contract();
    test_runtime_env_exit();
    test_error_kind_skeleton();
    test_stats();
    test_files();
    test_dirs_procs();
    test_regex_fmt();

    if (g_failures != 0) {
        fprintf(stderr, "std 测试失败 %d 项\n", g_failures);
        return 1;
    }
    printf("std 测试通过\n");
    return 0;
}
