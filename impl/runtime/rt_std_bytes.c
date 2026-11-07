/* rt_std_bytes.c — Bytes 可变字节缓冲原语（S1 §9.7 / S3 §188，B0-07c BYTES-RUNTIME）
 *
 * 合同：
 *   - 长度权威（xrt_bytes_len），允许内嵌 NUL，不要求 NUL 终止（S7 §3.4）；
 *   - 字节区不参与扫描（S3 §188“字节区免扫描”）；对象本身无引用字段；
 *   - get/set 越界 → xrt_fatal（S1 §9.7“越界 panic”）；
 *   - push/set 取值的低 8 位（Byte 语义）；扩容按 2 倍几何增长，OOM → xrt_fatal；
 *   - slice 复制出新区间，不共享底层缓冲。
 *
 * 分配种类：当前用 ARC（与 String/类/容器一致；生成代码按作用域 release）。
 * S3 §188 的“GC 对象”分类待 codegen 生命周期整体切到根登记后再改 kind——
 * 本文件的 API、类型名与布局不变，切换点只有 xrt_bytes_alloc 的 kind 实参。
 */
#include "rt.h"
#include "xrt.h"

#include <stdlib.h>
#include <string.h>

typedef struct {
    uint8_t *data;
    size_t   len;
    size_t   cap;
} bytes_payload;

static void bytes_deinit(void *obj) {
    /* deinit 收完整对象指针（S3 §14 / B0-07c 约定），载荷经 rt_payload 取。 */
    bytes_payload *p = rt_payload(obj);
    free(p->data);
    p->data = NULL;
    p->len = 0;
    p->cap = 0;
}

static const rt_type RT_TYPE_BYTES = {
    .name = "Bytes",
    .payload_size = sizeof(bytes_payload),
    .deinit = bytes_deinit,
    .scan = NULL, /* 无对象引用；字节区免扫描（S3 §188） */
};

static bytes_payload *payload_of(const xrt_bytes_buf *b) {
    return rt_payload((void *)b);
}

static xrt_bytes_buf *bytes_new_cap(size_t cap) {
    xrt_bytes_buf *b = xrt_alloc(XRT_KIND_ARC, (const xrt_type *)&RT_TYPE_BYTES);
    bytes_payload *p = payload_of(b);
    p->data = NULL;
    p->len = 0;
    p->cap = 0;
    if (cap > 0) {
        p->data = malloc(cap);
        if (p->data == NULL) {
            xrt_fatal("Bytes：分配失败（S3 §2）");
        }
        p->cap = cap;
    }
    return b;
}

static void bytes_reserve(xrt_bytes_buf *b, size_t need) {
    bytes_payload *p = payload_of(b);
    if (need <= p->cap) {
        return;
    }
    size_t cap = p->cap ? p->cap : 16;
    while (cap < need) {
        if (cap > (size_t)-1 / 2) {
            cap = need;
            break;
        }
        cap *= 2;
    }
    uint8_t *d = realloc(p->data, cap);
    if (d == NULL) {
        xrt_fatal("Bytes：扩容失败（S3 §2）");
    }
    p->data = d;
    p->cap = cap;
}

xrt_bytes_buf *xrt_bytes_new(void) {
    return bytes_new_cap(0);
}

xrt_bytes_buf *xrt_bytes_alloc(size_t len) {
    xrt_bytes_buf *b = bytes_new_cap(len);
    bytes_payload *p = payload_of(b);
    p->len = len;
    if (len > 0) {
        memset(p->data, 0, len);
    }
    return b;
}

xrt_bytes_buf *xrt_bytes_from_c(const void *data, size_t len) {
    if (len > 0 && data == NULL) {
        xrt_fatal("Bytes.fromString：数据为空但长度非零（S1 §9.7）");
    }
    xrt_bytes_buf *b = bytes_new_cap(len);
    bytes_payload *p = payload_of(b);
    p->len = len;
    if (len > 0) {
        memcpy(p->data, data, len);
    }
    return b;
}

size_t xrt_bytes_len(const xrt_bytes_buf *b) {
    return b == NULL ? 0 : payload_of(b)->len;
}

void *xrt_bytes_data(xrt_bytes_buf *b) {
    return b == NULL ? NULL : payload_of(b)->data;
}

int32_t xrt_bytes_get(const xrt_bytes_buf *b, size_t i) {
    if (b == NULL) {
        xrt_fatal("Bytes.get：缓冲为空（S1 §9.7）");
    }
    const bytes_payload *p = payload_of(b);
    if (i >= p->len) {
        xrt_fatal("Bytes.get：索引越界（S1 §9.7）");
    }
    return (int32_t)p->data[i];
}

void xrt_bytes_set(xrt_bytes_buf *b, size_t i, int32_t v) {
    if (b == NULL) {
        xrt_fatal("Bytes.set：缓冲为空（S1 §9.7）");
    }
    bytes_payload *p = payload_of(b);
    if (i >= p->len) {
        xrt_fatal("Bytes.set：索引越界（S1 §9.7）");
    }
    p->data[i] = (uint8_t)v;
}

void xrt_bytes_push(xrt_bytes_buf *b, int32_t v) {
    if (b == NULL) {
        xrt_fatal("Bytes.push：缓冲为空（S1 §9.7）");
    }
    bytes_payload *p = payload_of(b);
    if (p->len == (size_t)-1) {
        xrt_fatal("Bytes.push：长度溢出（S3 §2）");
    }
    bytes_reserve(b, p->len + 1);
    p->data[p->len++] = (uint8_t)v;
}

void xrt_bytes_append(xrt_bytes_buf *b, const xrt_bytes_buf *src) {
    if (b == NULL || src == NULL) {
        return;
    }
    const bytes_payload *s = payload_of(src);
    bytes_payload *p = payload_of(b);
    if (s->len == 0) {
        return;
    }
    if (p->len > (size_t)-1 - s->len) {
        xrt_fatal("Bytes.append：长度溢出（S3 §2）");
    }
    bytes_reserve(b, p->len + s->len);
    /* src 与 b 相同时 reserve 可能已扩容，重新取 p->data 后再复制。 */
    memmove(p->data + p->len, s->data, s->len);
    p->len += s->len;
}

xrt_bytes_buf *xrt_bytes_slice(const xrt_bytes_buf *b, size_t start, size_t end) {
    if (b == NULL) {
        xrt_fatal("Bytes.slice：缓冲为空（S1 §9.7）");
    }
    const bytes_payload *p = payload_of(b);
    if (start > end || end > p->len) {
        xrt_fatal("Bytes.slice：区间越界（S1 §9.7）");
    }
    return xrt_bytes_from_c(p->data + start, end - start);
}
