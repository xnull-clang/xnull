/* QA1 独立探针：xdkc_utf8_valid 语义（S1 §9.2）。
 * 不引用 E5 的 test_std.c 用例；只测公开 C 入口。
 * 语义：0=合法，非0=非法；长度权威、允许内嵌 NUL。
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

int32_t xdkc_utf8_valid(const char *bytes, size_t len);

static int fails = 0;
static int total = 0;

static void check(const char *name, const char *s, size_t n, int want_nonzero) {
    int32_t r = xdkc_utf8_valid(s, n);
    int ok = want_nonzero ? (r != 0) : (r == 0);
    total++;
    if (!ok) {
        fails++;
        printf("FAIL %-28s rc=%d want=%s\n", name, r, want_nonzero ? "非0" : "0");
    }
}

#define VALID(name, lit) check(name, lit, sizeof(lit) - 1, 0)
#define INVALID(name, lit) check(name, lit, sizeof(lit) - 1, 1)

int main(void) {
    /* 合法 */
    check("empty", "", 0, 0);
    VALID("ascii", "abc");
    VALID("cjk-3byte", "\xE4\xB8\xAD");
    VALID("emoji-4byte", "\xF0\x9F\x98\x80");
    check("embedded-NUL", "a\0b", 3, 0);
    check("NULL,len0", NULL, 0, 0);
    VALID("boundary-U+007F", "\x7F");
    VALID("boundary-U+0080", "\xC2\x80");
    VALID("boundary-U+07FF", "\xDF\xBF");
    VALID("boundary-U+0800", "\xE0\xA0\x80");
    VALID("boundary-U+FFFF", "\xEF\xBF\xBF");
    VALID("boundary-U+10000", "\xF0\x90\x80\x80");
    VALID("boundary-U+10FFFF", "\xF4\x8F\xBF\xBF");

    /* 非法 */
    INVALID("lone-continuation", "\x80");
    INVALID("overlong-C0-80", "\xC0\x80");
    INVALID("overlong-C1-BF", "\xC1\xBF");
    INVALID("overlong-E0-80-80", "\xE0\x80\x80");
    INVALID("overlong-E0-9F-BF", "\xE0\x9F\xBF");
    INVALID("overlong-F0-80-80-80", "\xF0\x80\x80\x80");
    INVALID("overlong-F0-8F-BF-BF", "\xF0\x8F\xBF\xBF");
    INVALID("surrogate-ED-A0-80", "\xED\xA0\x80");
    INVALID("surrogate-ED-BF-BF", "\xED\xBF\xBF");
    INVALID("above-U+10FFFF", "\xF4\x90\x80\x80");
    INVALID("lead-F5", "\xF5\x80\x80\x80");
    INVALID("truncated-2byte", "\xE4\xB8");
    INVALID("truncated-3byte", "\xF0\x9F\x98");
    INVALID("invalid-lead-FF", "\xFF");
    INVALID("invalid-lead-FE", "\xFE");
    INVALID("5byte-F8", "\xF8\x88\x80\x80\x80");
    check("NULL,len1", NULL, 1, 1);
    INVALID("ascii-then-lone-cont", "a\x80");
    INVALID("truncated-after-valid", "\xE4\xB8\xAD\xE4");

    if (fails == 0) {
        printf("utf8_valid QA probe: %d/%d PASS\n", total, total);
        return 0;
    }
    printf("utf8_valid QA probe: %d/%d PASS, %d FAIL\n", total - fails, total, fails);
    return 1;
}
