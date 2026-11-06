/* test_std.c — XDK C 层原语测试（M4.6a/b）
 *
 * 覆盖：diagnose 单行折叠、exit 不执行 atexit、时钟合同、env 不可变快照、
 * 严格解析/格式化、UTF-8↔UTF-16（含代理对与非法序列）、文件读写与幂等关闭。
 */
#define _POSIX_C_SOURCE 200809L

#include "xrt.h"

#include <dirent.h>
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
int64_t     xdkc_utf8_to_utf16(const char *src, size_t n, uint16_t *dst, size_t cap);
int64_t     xdkc_utf16_to_utf8(const uint16_t *src, size_t n, char *dst, size_t cap);
void       *xdkc_file_open_read(const char *bytes, size_t len);
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

    pid_t pid = fork();
    CHECK(pid >= 0);
    if (pid == 0) {
        /* 子进程：注册 atexit 后 exit(7)，期望 handler 不执行、退出码 7 */
        atexit(mark_atexit);
        xdkc_exit(7);
        _exit(3); /* 不应到达 */
    }
    int status = 0;
    CHECK(waitpid(pid, &status, 0) == pid);
    CHECK(WIFEXITED(status));
    CHECK(WEXITSTATUS(status) == 7);

    struct stat st;
    CHECK(stat(path, &st) == 0);
    CHECK(st.st_size == 0); /* atexit 未执行（S1 §10.3） */
    unlink(path);
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
