/* rt_std_res.c — 内嵌资源读取（S6 §4.8 / XDK-10；S8 §5.6 资源表）
 *
 * 资源 = 产物内 `resources/` 前缀下的只读文件；本文件只读**编译期生成的静态表**，
 * 不触碰文件系统（约束 5：不回退 FS），也不提供写入/删除/重命名（约束 2：无 close）。
 *
 * C ABI（供绑定/发射面调用；Result 不跨 FFI 边界，错误经错误码出参交付）：
 *   - 成功返回 1；失败返回 0，并写 *error_kind（XRT_ERR_* 14 项枚举）。
 *     **不使用 0 表示成功**：XRT_ERR_INVALID_ARGUMENT 本身就是 0，必须与成功区分。
 *   - 路径以 `resources/` 为根，只接受 `/` 分隔的相对路径：
 *       绝对路径（前导 `/`）、`..` 段、空段（含尾 `/`、`//`）、反斜杠 → InvalidArgument；
 *       缺失 → NotFound；readResourceText 非法 UTF-8 → DataCorrupted；
 *       上下文已取消 → Cancelled（入口与逐条枚举均检查）。
 *   - listResources 返回的字符串指针指向静态表，数组本身由本文件分配；
 *     调用方复制后必须调用 xdkc_list_resources_free 释放数组（不可释放元素）。
 *
 * 资源表符号由 gen_resources.py / `xnull dev res` 生成（S8 §5.6）：
 *   size_t xrt_resource_count(void);
 *   int    xrt_resource_get(const char *name, size_t nlen,
 *                           const unsigned char **out, size_t *out_len);
 *   int    xrt_resource_at(size_t i, const char **name, size_t *nlen,
 *                          const unsigned char **out, size_t *out_len);
 */
#include "rt.h"
#include "xrt.h"

#include <stdlib.h>
#include <string.h>

size_t xrt_resource_count(void);
int    xrt_resource_get(const char *name, size_t nlen,
                        const unsigned char **out, size_t *out_len);
int    xrt_resource_at(size_t i, const char **name, size_t *nlen,
                       const unsigned char **out, size_t *out_len);
int32_t xdkc_utf8_valid(const char *bytes, size_t len);

/* 路径校验（S6 §4.8 约束 1）。allow_empty 只给 listResources("") 用：
 * 空前缀表示资源根；其余 API 的空路径是空段 → InvalidArgument。 */
static int res_path_ok(const char *p, size_t n, int allow_empty) {
    if (n == 0) {
        return allow_empty;
    }
    if (p == NULL) {
        return 0;
    }
    if (p[0] == '/') {        /* 绝对路径 */
        return 0;
    }
    if (p[n - 1] == '/') {    /* 尾随空段 */
        return 0;
    }
    size_t seg_start = 0;
    for (size_t i = 0; i <= n; i++) {
        if (i < n) {
            if (p[i] == '\\' || p[i] == '\0') { /* 反斜杠 / 内嵌 NUL */
                return 0;
            }
            if (p[i] != '/') {
                continue;
            }
        }
        size_t seg_len = i - seg_start;
        if (seg_len == 0) {   /* 空段（含前导 //） */
            return 0;
        }
        if (seg_len == 2 && p[seg_start] == '.' && p[seg_start + 1] == '.') {
            return 0;         /* .. 段 */
        }
        if (seg_len == 1 && p[seg_start] == '.') {
            return 0;         /* . 段（与生成器一致：资源名不含相对段） */
        }
        seg_start = i + 1;
    }
    return 1;
}

static int res_cancelled(xrt_context *ctx) {
    return ctx != NULL && xrt_context_check_cancel(ctx) == XRT_ERR_CANCELLED;
}

static int32_t res_fail(int32_t *error_kind, xrt_error_kind kind) {
    if (error_kind != NULL) {
        *error_kind = (int32_t)kind;
    }
    return 0;
}

/* ---- resourceExists(String) -> Bool ---- */
int32_t xdkc_resource_exists(const char *path, size_t len) {
    if (!res_path_ok(path, len, 0)) {
        return 0; /* 非法与缺失同为 false（签名无错误通道） */
    }
    const unsigned char *d = NULL;
    size_t n = 0;
    return xrt_resource_get(path, len, &d, &n) == 0 ? 1 : 0;
}

/* ---- resourceSize(String) -> Int? ---- */
int32_t xdkc_resource_size(const char *path, size_t len, int64_t *out_size) {
    if (out_size != NULL) {
        *out_size = 0;
    }
    if (!res_path_ok(path, len, 0)) {
        return 0; /* 非法与缺失同为 null（签名无错误通道） */
    }
    const unsigned char *d = NULL;
    size_t n = 0;
    if (xrt_resource_get(path, len, &d, &n) != 0) {
        return 0;
    }
    if (out_size != NULL) {
        *out_size = (int64_t)n;
    }
    return 1;
}

/* ---- readResource(Context, String) -> Result<Bytes, Error> ---- */
int32_t xdkc_read_resource(xrt_context *ctx, const char *path, size_t len,
                           xrt_bytes_buf **out, int32_t *error_kind) {
    if (out != NULL) {
        *out = NULL;
    }
    if (!res_path_ok(path, len, 0)) {
        return res_fail(error_kind, XRT_ERR_INVALID_ARGUMENT);
    }
    if (res_cancelled(ctx)) {
        return res_fail(error_kind, XRT_ERR_CANCELLED);
    }
    const unsigned char *d = NULL;
    size_t n = 0;
    if (xrt_resource_get(path, len, &d, &n) != 0) {
        return res_fail(error_kind, XRT_ERR_NOT_FOUND);
    }
    /* 每次调用都复制一次（约束 4：不隐式缓存）。 */
    if (res_cancelled(ctx)) {
        return res_fail(error_kind, XRT_ERR_CANCELLED);
    }
    xrt_bytes_buf *b = xrt_bytes_from_c(d, n);
    if (out != NULL) {
        *out = b;
    }
    if (error_kind != NULL) {
        *error_kind = 0;
    }
    return 1;
}

/* ---- readResourceText(Context, String) -> Result<Text, Error> ---- */
int32_t xdkc_read_resource_text(xrt_context *ctx, const char *path, size_t len,
                                xrt_text **out, int32_t *error_kind) {
    if (out != NULL) {
        *out = NULL;
    }
    if (!res_path_ok(path, len, 0)) {
        return res_fail(error_kind, XRT_ERR_INVALID_ARGUMENT);
    }
    if (res_cancelled(ctx)) {
        return res_fail(error_kind, XRT_ERR_CANCELLED);
    }
    const unsigned char *d = NULL;
    size_t n = 0;
    if (xrt_resource_get(path, len, &d, &n) != 0) {
        return res_fail(error_kind, XRT_ERR_NOT_FOUND);
    }
    if (res_cancelled(ctx)) {
        return res_fail(error_kind, XRT_ERR_CANCELLED);
    }
    if (xdkc_utf8_valid((const char *)d, n) != 0) {
        return res_fail(error_kind, XRT_ERR_DATA_CORRUPTED);
    }
    xrt_text *t = xrt_text_from_string((const char *)d, n);
    if (out != NULL) {
        *out = t;
    }
    if (error_kind != NULL) {
        *error_kind = 0;
    }
    return 1;
}

/* 前缀匹配：空前缀 = 根；非空前缀只列 `<prefix>/` 之下的条目。
 * 前缀本身是文件（或无此目录）→ 空列表，不是错误（S6 §4.8）。 */
static int res_prefix_match(const char *prefix, size_t plen,
                            const char *name, size_t nlen) {
    if (plen == 0) {
        return 1;
    }
    if (nlen <= plen) {
        return 0;
    }
    return memcmp(prefix, name, plen) == 0 && name[plen] == '/';
}

/* ---- listResources(Context, String) -> Result<List<String>, Error> ---- */
int32_t xdkc_list_resources(xrt_context *ctx, const char *prefix, size_t len,
                            const char ***out, size_t *out_count,
                            int32_t *error_kind) {
    if (out != NULL) {
        *out = NULL;
    }
    if (out_count != NULL) {
        *out_count = 0;
    }
    if (!res_path_ok(prefix, len, 1)) {
        return res_fail(error_kind, XRT_ERR_INVALID_ARGUMENT);
    }
    if (res_cancelled(ctx)) {
        return res_fail(error_kind, XRT_ERR_CANCELLED);
    }
    size_t total = xrt_resource_count();
    size_t count = 0;
    for (size_t i = 0; i < total; i++) {
        if (res_cancelled(ctx)) {
            return res_fail(error_kind, XRT_ERR_CANCELLED);
        }
        const char *name = NULL;
        size_t nlen = 0;
        const unsigned char *d = NULL;
        size_t dn = 0;
        if (xrt_resource_at(i, &name, &nlen, &d, &dn) != 0) {
            break;
        }
        if (res_prefix_match(prefix, len, name, nlen)) {
            count++;
        }
    }
    if (count == 0) {
        if (error_kind != NULL) {
            *error_kind = 0;
        }
        return 1; /* 前缀不是目录：Ok(空列表) */
    }
    const char **items = malloc(count * sizeof(*items));
    if (items == NULL) {
        return res_fail(error_kind, XRT_ERR_OUT_OF_MEMORY);
    }
    size_t k = 0;
    for (size_t i = 0; i < total && k < count; i++) {
        if (res_cancelled(ctx)) {
            free(items);
            return res_fail(error_kind, XRT_ERR_CANCELLED);
        }
        const char *name = NULL;
        size_t nlen = 0;
        const unsigned char *d = NULL;
        size_t dn = 0;
        if (xrt_resource_at(i, &name, &nlen, &d, &dn) != 0) {
            break;
        }
        if (res_prefix_match(prefix, len, name, nlen)) {
            items[k++] = name;
        }
    }
    if (out != NULL) {
        *out = items;
    }
    if (out_count != NULL) {
        *out_count = k;
    }
    if (error_kind != NULL) {
        *error_kind = 0;
    }
    return 1;
}

/* 释放 listResources 返回的数组（只释放数组；元素指向静态表，不释放）。 */
void xdkc_list_resources_free(const char **items) {
    free((void *)items);
}
