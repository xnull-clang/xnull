/* rt_std_text.c — XDK text 原语（S6 §4.6；M4.6a/续建）
 *
 * 合同：
 *   - 解析严格：全串消费、溢出独立报错（不 panic，返回错误码）；
 *   - 格式化交给调用方缓冲（builder 语义的无分配底座）；
 *   - 编码转换逐码点校验：非法序列返回 -1（调用方转 InvalidArgument）；
 *   - Regex 为 POSIX ERE 子集（REG_EXTENDED | REG_NOSUB）：
 *     返回 0 = 匹配、1 = 不匹配、2 = 模式语法错误（不 panic）；
 *   - Format 追加族：调用方持有缓冲与游标（*off），不足返回 -1，不 realloc。
 *
 * 错误码：0 = 成功；1 = 语法无效；2 = 溢出/模式错误。
 */
#include "xrt.h"

#include <errno.h>
#include <regex.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define XDK_PARSE_MAX 64

int32_t xdkc_parse_int(const char *bytes, size_t len, int64_t *out) {
    if (bytes == NULL || out == NULL) {
        xrt_fatal("parseInt：参数为空（S6 §4.6）");
    }
    if (len == 0 || len > XDK_PARSE_MAX) {
        return 1;
    }
    char buf[XDK_PARSE_MAX + 1];
    memcpy(buf, bytes, len);
    buf[len] = 0;
    errno = 0;
    char *end = NULL;
    long long v = strtoll(buf, &end, 10);
    if (end == buf || (size_t)(end - buf) != len) {
        return 1;
    }
    if (errno == ERANGE) {
        return 2;
    }
    *out = (int64_t)v;
    return 0;
}

int32_t xdkc_parse_float(const char *bytes, size_t len, double *out) {
    if (bytes == NULL || out == NULL) {
        xrt_fatal("parseFloat：参数为空（S6 §4.6）");
    }
    if (len == 0 || len > XDK_PARSE_MAX) {
        return 1;
    }
    char buf[XDK_PARSE_MAX + 1];
    memcpy(buf, bytes, len);
    buf[len] = 0;
    errno = 0;
    char *end = NULL;
    double v = strtod(buf, &end);
    if (end == buf || (size_t)(end - buf) != len) {
        return 1;
    }
    if (errno == ERANGE) {
        return 2;
    }
    *out = v;
    return 0;
}

int64_t xdkc_format_int(int64_t v, char *buf, size_t cap) {
    if (buf == NULL || cap == 0) {
        xrt_fatal("formatInt：缓冲为空（S6 §4.6）");
    }
    int n = snprintf(buf, cap, "%lld", (long long)v);
    if (n < 0 || (size_t)n >= cap) {
        return -1;
    }
    return (int64_t)n;
}

/* ---- Format 追加族（builder 底座：调用方持缓冲 + 游标） ---- */

int64_t xdkc_fmt_append_raw(char *buf, size_t cap, size_t *off, const char *src, size_t n) {
    if (buf == NULL || off == NULL) {
        xrt_fatal("fmtAppend：缓冲/游标为空（S6 §4.6）");
    }
    if (n > 0 && src == NULL) {
        xrt_fatal("fmtAppend：源为空但长度非零（S6 §4.6）");
    }
    if (*off > cap || cap - *off < n) {
        return -1; /* 容量不足：调用方决定扩容或报错，运行时不 realloc */
    }
    if (n > 0) {
        memcpy(buf + *off, src, n);
    }
    *off += n;
    return (int64_t)*off;
}

int64_t xdkc_fmt_append_int(char *buf, size_t cap, size_t *off, int64_t v) {
    char tmp[24];
    int n = snprintf(tmp, sizeof(tmp), "%lld", (long long)v);
    if (n < 0) {
        return -1;
    }
    return xdkc_fmt_append_raw(buf, cap, off, tmp, (size_t)n);
}

/* ---- Regex（POSIX ERE 子集，S6 §4.6 Regex 面） ---- */

int32_t xdkc_regex_match(const char *pat, size_t plen, const char *sub, size_t slen) {
    if ((pat == NULL && plen > 0) || (sub == NULL && slen > 0)) {
        xrt_fatal("regexMatch：参数为空但长度非零（S6 §4.6）");
    }
    if (plen == 0 || plen > 512) {
        return 2;
    }
    char *pbuf = malloc(plen + 1);
    if (pbuf == NULL) {
        xrt_fatal("regexMatch：内存不足（S6 §4.6）");
    }
    memcpy(pbuf, pat, plen);
    pbuf[plen] = 0;

    regex_t re;
    int rc = regcomp(&re, pbuf, REG_EXTENDED | REG_NOSUB);
    free(pbuf);
    if (rc != 0) {
        return 2; /* 模式语法错误：显式区分，不当作"不匹配" */
    }
    /* 主题串允许内嵌 NUL 之外的内容按 C 串处理（REG_NOSUB，无捕获组需求）；
     * 含 NUL 的主题在此子集下截断——文档化限制（完整形态随 XDK-08 API 面提案）。 */
    char *sbuf = malloc(slen + 1);
    if (sbuf == NULL) {
        regfree(&re);
        xrt_fatal("regexMatch：内存不足（S6 §4.6）");
    }
    if (slen > 0) {
        memcpy(sbuf, sub, slen);
    }
    sbuf[slen] = 0;
    rc = regexec(&re, sbuf, 0, NULL, 0);
    regfree(&re);
    free(sbuf);
    return rc == 0 ? 0 : 1;
}

/* UTF-8 单码点解码：成功返回消耗字节数（>0），非法返回 0。 */
static size_t utf8_decode(const unsigned char *p, size_t n, uint32_t *cp) {
    if (n == 0) {
        return 0;
    }
    unsigned char b0 = p[0];
    if (b0 < 0x80) {
        *cp = b0;
        return 1;
    }
    size_t need;
    uint32_t v;
    if ((b0 & 0xE0) == 0xC0) {
        need = 2;
        v = b0 & 0x1F;
    } else if ((b0 & 0xF0) == 0xE0) {
        need = 3;
        v = b0 & 0x0F;
    } else if ((b0 & 0xF8) == 0xF0) {
        need = 4;
        v = b0 & 0x07;
    } else {
        return 0;
    }
    if (n < need) {
        return 0;
    }
    for (size_t i = 1; i < need; i++) {
        if ((p[i] & 0xC0) != 0x80) {
            return 0;
        }
        v = (v << 6) | (uint32_t)(p[i] & 0x3F);
    }
    /* 过短编码与代理区、越界码点一律非法（S1 §9.2 UTF-8 合同） */
    if ((need == 2 && v < 0x80) || (need == 3 && v < 0x800) || (need == 4 && v < 0x10000)) {
        return 0;
    }
    if (v > 0x10FFFF || (v >= 0xD800 && v <= 0xDFFF)) {
        return 0;
    }
    *cp = v;
    return need;
}

int64_t xdkc_utf8_to_utf16(const char *src, size_t n, uint16_t *dst, size_t cap) {
    const unsigned char *p = (const unsigned char *)src;
    size_t i = 0, w = 0;
    while (i < n) {
        uint32_t cp = 0;
        size_t used = utf8_decode(p + i, n - i, &cp);
        if (used == 0) {
            return -1;
        }
        if (cp >= 0x10000) {
            if (w + 2 > cap) {
                return -1;
            }
            cp -= 0x10000;
            dst[w++] = (uint16_t)(0xD800 + (cp >> 10));
            dst[w++] = (uint16_t)(0xDC00 + (cp & 0x3FF));
        } else {
            if (w + 1 > cap) {
                return -1;
            }
            dst[w++] = (uint16_t)cp;
        }
        i += used;
    }
    return (int64_t)w;
}

int64_t xdkc_utf16_to_utf8(const uint16_t *src, size_t n, char *dst, size_t cap) {
    size_t w = 0;
    for (size_t i = 0; i < n; i++) {
        uint32_t cp = src[i];
        if (cp >= 0xD800 && cp <= 0xDBFF) {
            if (i + 1 >= n || src[i + 1] < 0xDC00 || src[i + 1] > 0xDFFF) {
                return -1;
            }
            cp = 0x10000 + ((cp - 0xD800) << 10) + (uint32_t)(src[i + 1] - 0xDC00);
            i++;
        } else if (cp >= 0xDC00 && cp <= 0xDFFF) {
            return -1;
        }
        unsigned char tmp[4];
        size_t k;
        if (cp < 0x80) {
            tmp[0] = (unsigned char)cp;
            k = 1;
        } else if (cp < 0x800) {
            tmp[0] = (unsigned char)(0xC0 | (cp >> 6));
            tmp[1] = (unsigned char)(0x80 | (cp & 0x3F));
            k = 2;
        } else if (cp < 0x10000) {
            tmp[0] = (unsigned char)(0xE0 | (cp >> 12));
            tmp[1] = (unsigned char)(0x80 | ((cp >> 6) & 0x3F));
            tmp[2] = (unsigned char)(0x80 | (cp & 0x3F));
            k = 3;
        } else {
            tmp[0] = (unsigned char)(0xF0 | (cp >> 18));
            tmp[1] = (unsigned char)(0x80 | ((cp >> 12) & 0x3F));
            tmp[2] = (unsigned char)(0x80 | ((cp >> 6) & 0x3F));
            tmp[3] = (unsigned char)(0x80 | (cp & 0x3F));
            k = 4;
        }
        if (w + k > cap) {
            return -1;
        }
        memcpy(dst + w, tmp, k);
        w += k;
    }
    return (int64_t)w;
}
