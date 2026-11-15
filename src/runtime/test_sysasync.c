/* test_sysasync.c — S6-03：sys plain/Async 双形态 + Process 句柄（E5 运行时侧） */
#include "xrt.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

/* C 层原型（绑定层 cName；测试直接调用） */
void       *xdkc_file_open_write_async(xrt_context *ctx, const char *bytes, size_t len, int32_t *code);
void       *xdkc_file_open_read_async(xrt_context *ctx, const char *bytes, size_t len, int32_t *code);
int64_t     xdkc_file_read_async(xrt_context *ctx, void *fp, void *buf, size_t cap, int32_t *code);
int32_t     xdkc_file_write_async(xrt_context *ctx, void *fp, const void *buf, size_t n);
int32_t     xdkc_file_close_async(xrt_context *ctx, void *fp);
void       *xdkc_dir_open_async(xrt_context *ctx, const char *bytes, size_t len, int32_t *code);
const char *xdkc_dir_read_async(xrt_context *ctx, void *dp, int32_t *code);
int32_t     xdkc_dir_close_async(xrt_context *ctx, void *dp);
void       *xdkc_proc_spawn(const char *cmd, size_t len, int32_t *code);
int32_t     xdkc_proc_wait(void *proc, int32_t *status);
int32_t     xdkc_proc_kill(void *proc, int32_t sig);
int32_t     xdkc_proc_close(void *proc);
int32_t     xdkc_proc_run_async(xrt_context *ctx, const char *cmd, size_t len, int32_t *status);
int32_t     xdkc_proc_status_async(xrt_context *ctx, const char *cmd, size_t len);

static void test_file_async(void) {
    char path[] = "/tmp/xnull_sysasyncXXXXXX";
    int fd = mkstemp(path);
    assert(fd >= 0);
    close(fd);
    size_t plen = strlen(path);
    xrt_context *ctx = xrt_context_background();

    int32_t code = -1;
    void *wf = xdkc_file_open_write_async(ctx, path, plen, &code);
    assert(code == 0 && wf != NULL);
    assert(xdkc_file_write_async(ctx, wf, "AB", 2) == 0);
    assert(xdkc_file_close_async(ctx, wf) == 0);

    void *rf = xdkc_file_open_read_async(ctx, path, plen, &code);
    assert(code == 0 && rf != NULL);
    char buf[8] = {0};
    int64_t n = xdkc_file_read_async(ctx, rf, buf, sizeof(buf), &code);
    assert(code == 0 && n == 2 && memcmp(buf, "AB", 2) == 0);
    assert(xdkc_file_close_async(ctx, rf) == 0);
    unlink(path);
    xrt_release(ctx);
}

static void test_dir_async(void) {
    xrt_context *ctx = xrt_context_background();
    int32_t code = -1;
    void *dp = xdkc_dir_open_async(ctx, ".", 1, &code);
    assert(code == 0 && dp != NULL);
    int seen = 0;
    for (int i = 0; i < 64; i++) {
        const char *name = xdkc_dir_read_async(ctx, dp, &code);
        if (name == NULL) {
            break;
        }
        seen++;
    }
    assert(seen > 0);
    assert(xdkc_dir_close_async(ctx, dp) == 0);
    xrt_release(ctx);
}

/* 取消语义（S6-03 / S3 §18）：
 *   - read 取消是可恢复的 code=2（调用方自行决定），不是进程终止；
 *   - close 取消仍完成关闭，返回真实 close 结果（0），句柄层据此 mark_closed。 */
static void test_cancel_semantics(void) {
    char path[] = "/tmp/xnull_sysasync_cancelXXXXXX";
    int fd = mkstemp(path);
    assert(fd >= 0);
    close(fd);
    size_t plen = strlen(path);

    xrt_context *ctx = xrt_context_background();
    int32_t code = -1;
    void *wf = xdkc_file_open_write_async(ctx, path, plen, &code);
    assert(code == 0 && wf != NULL);
    assert(xdkc_file_write_async(ctx, wf, "AB", 2) == 0);

    xrt_context *dead = xrt_context_with_deadline(xrt_context_background(),
                                                  xrt_clock_mono_ms() - 1);
    /* close 必达：取消不撤销已完成的关闭，返回 0 而不是 2。 */
    assert(xdkc_file_close_async(dead, wf) == 0);

    void *rf = xdkc_file_open_read_async(ctx, path, plen, &code);
    assert(code == 0 && rf != NULL);
    char buf[8] = {0};
    int64_t n = xdkc_file_read_async(dead, rf, buf, sizeof(buf), &code);
    assert(n == -1 && code == 2); /* 可恢复的取消码，调用方决定如何报告 */
    assert(xdkc_file_close_async(ctx, rf) == 0);

    void *dp = xdkc_dir_open_async(ctx, ".", 1, &code);
    assert(code == 0 && dp != NULL);
    assert(xdkc_dir_close_async(dead, dp) == 0);

    xrt_release(dead);
    xrt_release(ctx);
    unlink(path);
}

static void test_process(void) {
    int32_t code = -1;
    void *p = xdkc_proc_spawn("exit 7", 6, &code);
    assert(code == 0 && p != NULL);
    int32_t st = -1;
    assert(xdkc_proc_wait(p, &st) == 0 && st == 7);
    assert(xdkc_proc_close(p) == 0);

    p = xdkc_proc_spawn("sleep 5", 7, &code);
    assert(code == 0 && p != NULL);
    struct timespec d = {0, 50000000};
    nanosleep(&d, NULL);
    assert(xdkc_proc_kill(p, 9) == 0); /* SIGKILL */
    assert(xdkc_proc_wait(p, &st) == 0);
    assert(st == 128 + 9);
    assert(xdkc_proc_close(p) == 0);
}

static void test_process_async(void) {
    xrt_context *ctx = xrt_context_background();
    int32_t st = -1;
    assert(xdkc_proc_run_async(ctx, "exit 3", 6, &st) == 0 && st == 3);
    assert(xdkc_proc_status_async(ctx, "exit 4", 6) == 4);

    /* 取消：等待立即返回 Cancelled；命令在伴生线程继续 */
    xrt_context *dl = xrt_context_with_deadline(xrt_context_background(),
                                                xrt_clock_mono_ms() + 10);
    int32_t rc = xdkc_proc_run_async(dl, "sleep 0.2", 9, &st);
    assert(rc == XRT_ERR_CANCELLED);
    struct timespec wait = {0, 300000000};
    nanosleep(&wait, NULL); /* 让伴生线程回收子进程 */
    xrt_release(dl);
    xrt_release(ctx);
}

int main(void) {
    test_file_async();
    test_dir_async();
    test_process();
    test_process_async();
    test_cancel_semantics();
    printf("sysasync tests passed (file/dir/process async + close + cancel)\n");
    return 0;
}
