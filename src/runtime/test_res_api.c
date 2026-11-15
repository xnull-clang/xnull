/* test_res_api.c — XDK-10 资源读取 5 API（S6 §4.8 七条约束逐条）
 *
 * 资源表由 build_rt.sh 现场生成（同一资源目录）：
 *   a.txt=hello  b.bin=01 02 FF  bad.txt=FF FE（非法 UTF-8）
 *   dir1/x.txt=x  dir1/y.txt=yy  dir2/z.txt=zzz  xres_only.txt=R
 * 生成表按名称升序（S8 §5.6）：a.txt < b.bin < bad.txt < dir1/x.txt
 *   < dir1/y.txt < dir2/z.txt < xres_only.txt。
 */
#include "xrt.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void *xdkc_file_open_read(const char *bytes, size_t len);
int32_t xdkc_file_close(void *fp);

static int g_failures = 0;

#define CHECK(cond)                                                          \
    do {                                                                     \
        if (!(cond)) {                                                       \
            g_failures++;                                                    \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);  \
        }                                                                    \
    } while (0)

static xrt_context *ok_ctx(void) {
    return xrt_context_background();
}

static void expect_read_err(xrt_context *ctx, const char *p, size_t n,
                            xrt_error_kind kind) {
    xrt_bytes_buf *b = (xrt_bytes_buf *)(void *)1;
    int32_t ek = -1;
    CHECK(xdkc_read_resource(ctx, p, n, &b, &ek) == 0);
    CHECK(b == NULL);
    CHECK(ek == (int32_t)kind);
}

static void expect_text_err(xrt_context *ctx, const char *p, size_t n,
                            xrt_error_kind kind) {
    xrt_text *t = (xrt_text *)(void *)1;
    int32_t ek = -1;
    CHECK(xdkc_read_resource_text(ctx, p, n, &t, &ek) == 0);
    CHECK(t == NULL);
    CHECK(ek == (int32_t)kind);
}

static void expect_list_err(xrt_context *ctx, const char *p, size_t n,
                            xrt_error_kind kind) {
    const char **items = (const char **)(void *)1;
    size_t count = 99;
    int32_t ek = -1;
    CHECK(xdkc_list_resources(ctx, p, n, &items, &count, &ek) == 0);
    CHECK(items == NULL && count == 0);
    CHECK(ek == (int32_t)kind);
}

/* 约束 1：绝对路径、`..` 段、空段、反斜杠 → InvalidArgument。 */
static void test_path_invalid(void) {
    xrt_context *ctx = ok_ctx();
    const char *bad[] = {
        "/a.txt",        /* 绝对路径 */
        "../a.txt",      /* .. 段（开头） */
        "dir1/../a.txt", /* .. 段（中段） */
        "dir1//x.txt",   /* 空段 */
        "dir1/",         /* 尾随空段 */
        "dir1\\x.txt",   /* 反斜杠 */
        "a\0b",          /* 内嵌 NUL */
    };
    for (size_t i = 0; i < sizeof(bad) / sizeof(bad[0]); i++) {
        size_t n = (i == 6) ? 3 : strlen(bad[i]);
        expect_read_err(ctx, bad[i], n, XRT_ERR_INVALID_ARGUMENT);
        expect_text_err(ctx, bad[i], n, XRT_ERR_INVALID_ARGUMENT);
    }
    /* 空路径（非 listResources）是空段。 */
    expect_read_err(ctx, "", 0, XRT_ERR_INVALID_ARGUMENT);

    /* listResources 的四类非法；空前缀是根，不在此列。 */
    for (size_t i = 0; i < 6; i++) {
        size_t n = strlen(bad[i]);
        expect_list_err(ctx, bad[i], n, XRT_ERR_INVALID_ARGUMENT);
    }
    xrt_release(ctx);
}

/* 约束 6：缺失是可恢复错误（NotFound），resourceExists/resourceSize 走可空语义。 */
static void test_missing(void) {
    xrt_context *ctx = ok_ctx();
    expect_read_err(ctx, "nope.txt", 8, XRT_ERR_NOT_FOUND);
    expect_text_err(ctx, "nope.txt", 8, XRT_ERR_NOT_FOUND);
    expect_read_err(ctx, "dir1", 4, XRT_ERR_NOT_FOUND); /* 目录不是资源文件 */
    expect_list_err(ctx, "nope/..", 7, XRT_ERR_INVALID_ARGUMENT);

    CHECK(xdkc_resource_exists("a.txt", 5) == 1);
    CHECK(xdkc_resource_exists("nope.txt", 8) == 0);
    CHECK(xdkc_resource_exists("/a.txt", 6) == 0); /* 非法 → false */

    int64_t sz = -1;
    CHECK(xdkc_resource_size("a.txt", 5, &sz) == 1 && sz == 5);
    sz = -1;
    CHECK(xdkc_resource_size("nope.txt", 8, &sz) == 0 && sz == 0);
    sz = -1;
    CHECK(xdkc_resource_size("/a.txt", 6, &sz) == 0 && sz == 0); /* 非法 → null */
    xrt_release(ctx);
}

/* readResource / readResourceText：字节权威、UTF-8 解码错误可恢复。 */
static void test_read(void) {
    xrt_context *ctx = ok_ctx();
    int32_t ek = -1;
    xrt_bytes_buf *b = NULL;
    CHECK(xdkc_read_resource(ctx, "a.txt", 5, &b, &ek) == 1 && ek == 0);
    CHECK(b != NULL && xrt_bytes_len(b) == 5);
    CHECK(memcmp(xrt_bytes_data(b), "hello", 5) == 0);

    CHECK(xdkc_read_resource(ctx, "b.bin", 5, &b, &ek) == 1 && ek == 0);
    CHECK(xrt_bytes_len(b) == 3);
    CHECK(memcmp(xrt_bytes_data(b), "\x01\x02\xFF", 3) == 0);

    xrt_text *t = NULL;
    CHECK(xdkc_read_resource_text(ctx, "a.txt", 5, &t, &ek) == 1 && ek == 0);
    CHECK(t != NULL && xrt_text_length(t) == 5);
    xrt_string *ts = xrt_text_to_string(t);
    CHECK(ts != NULL && xrt_string_len(ts) == 5 &&
          memcmp(xrt_string_bytes(ts), "hello", 5) == 0);

    /* 非法 UTF-8：DataCorrupted（S5 附录 A 解码/输入类），不是 panic。 */
    expect_text_err(ctx, "bad.txt", 7, XRT_ERR_DATA_CORRUPTED);
    /* 同一字节经 readResource 仍是合法的原始字节。 */
    CHECK(xdkc_read_resource(ctx, "bad.txt", 7, &b, &ek) == 1 && ek == 0);
    CHECK(xrt_bytes_len(b) == 2 && memcmp(xrt_bytes_data(b), "\xFF\xFE", 2) == 0);
    xrt_release(ctx);
}

/* 约束 3：listResources 字典序升序；前缀不是目录 → 空列表。 */
static void test_list(void) {
    xrt_context *ctx = ok_ctx();
    const char *want[] = {
        "a.txt", "b.bin", "bad.txt", "dir1/x.txt",
        "dir1/y.txt", "dir2/z.txt", "xres_only.txt",
    };
    const char **items = NULL;
    size_t count = 0;
    int32_t ek = -1;
    CHECK(xdkc_list_resources(ctx, "", 0, &items, &count, &ek) == 1 && ek == 0);
    CHECK(count == sizeof(want) / sizeof(want[0]));
    for (size_t i = 0; i < count && i < sizeof(want) / sizeof(want[0]); i++) {
        CHECK(strcmp(items[i], want[i]) == 0);
    }
    xdkc_list_resources_free(items);

    items = NULL;
    count = 0;
    CHECK(xdkc_list_resources(ctx, "dir1", 4, &items, &count, &ek) == 1 && ek == 0);
    CHECK(count == 2 && strcmp(items[0], "dir1/x.txt") == 0 &&
          strcmp(items[1], "dir1/y.txt") == 0);
    xdkc_list_resources_free(items);

    /* 前缀不是目录（无匹配 / 是文件 / 只是名字前缀）→ Ok(空列表)。 */
    const char *empty_prefix[] = {"dir", "a.txt", "dir1/x.txt", "zzz"};
    for (size_t i = 0; i < sizeof(empty_prefix) / sizeof(empty_prefix[0]); i++) {
        items = NULL;
        count = 99;
        CHECK(xdkc_list_resources(ctx, empty_prefix[i], strlen(empty_prefix[i]),
                                  &items, &count, &ek) == 1 &&
              ek == 0 && count == 0 && items == NULL);
    }
    xrt_release(ctx);
}

/* 约束 5/7：只读静态表，不回退文件系统；文件 API 也读不到内嵌资源。 */
static void test_no_fs_fallback(void) {
    const char *name = "xres_only.txt";
    FILE *f = fopen(name, "wb");
    CHECK(f != NULL);
    if (f != NULL) {
        fputs("FS", f);
        fclose(f);
    }

    xrt_context *ctx = ok_ctx();
    int32_t ek = -1;
    xrt_bytes_buf *b = NULL;
    /* 工作目录存在同名文件，资源 API 仍读内嵌字节 "R"。 */
    CHECK(xdkc_read_resource(ctx, name, strlen(name), &b, &ek) == 1 && ek == 0);
    CHECK(xrt_bytes_len(b) == 1 && memcmp(xrt_bytes_data(b), "R", 1) == 0);

    /* 文件 API 读取只在产物内的资源：工作目录无该路径 → 打开失败。 */
    CHECK(xdkc_file_open_read("dir1/x.txt", 10) == NULL);

    /* 内嵌资源表存在，但文件 API 不会“看见”它。 */
    CHECK(xdkc_resource_exists("a.txt", 5) == 1);
    CHECK(xdkc_file_open_read("a.txt", 5) == NULL);

    unlink(name);
    xrt_release(ctx);
}

/* 约束 3：挂起点可取消；取消不是 NotFound。 */
static void test_cancel(void) {
    xrt_context *dead = xrt_context_with_deadline(xrt_context_background(),
                                                  xrt_clock_mono_ms() - 1);
    expect_read_err(dead, "a.txt", 5, XRT_ERR_CANCELLED);
    expect_text_err(dead, "a.txt", 5, XRT_ERR_CANCELLED);
    expect_list_err(dead, "", 0, XRT_ERR_CANCELLED);
    xrt_release(dead);
}

/* 约束 2：返回值不是句柄，无 close；每次调用独立复制（约束 4）。 */
static void test_no_close_and_no_cache(void) {
    xrt_context *ctx = ok_ctx();
    int32_t ek = -1;
    xrt_bytes_buf *a = NULL;
    xrt_bytes_buf *b = NULL;
    CHECK(xdkc_read_resource(ctx, "a.txt", 5, &a, &ek) == 1 && ek == 0);
    CHECK(xdkc_read_resource(ctx, "a.txt", 5, &b, &ek) == 1 && ek == 0);
    /* 值语义：两次读取是不同对象（不返回可共享句柄/缓存对象）。 */
    CHECK(a != b);
    CHECK(xrt_bytes_len(a) == xrt_bytes_len(b));
    /* Bytes 是 GC 对象；xrt_release 为 no-op，无需 close。 */
    xrt_release(a);
    xrt_release(b);
    xrt_release(ctx);
}

int main(void) {
    test_path_invalid();
    test_missing();
    test_read();
    test_list();
    test_no_fs_fallback();
    test_cancel();
    test_no_close_and_no_cache();
    if (g_failures != 0) {
        fprintf(stderr, "资源 API 测试失败 %d 项\n", g_failures);
        return 1;
    }
    printf("资源 API 测试通过（5 API / 7 约束）\n");
    return 0;
}
