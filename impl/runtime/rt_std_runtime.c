/* rt_std_runtime.c — XDK runtime 原语（S6 §4.4；M4.6a）
 *
 * 合同：
 *   - diagnose：单行输出、无分配（S5 §4.3）；换行折叠为空格，单次 write 语义；
 *   - exit：不执行 defer / atexit（S1 §10.3）→ _Exit；
 *   - nowMono：单调时钟（不保证跨进程可比）；nowWall：UTC 毫秒，允许回拨；
 *   - env：首次读取即快照，重复调用返回同一值（不可变快照，S6 §4.4）。
 *
 * 符号前缀 xdkc_ 为工具链内部库面（随产物静态编入，不对外承诺）。
 * 只依赖 xrt.h 与 libc。
 */
#define _POSIX_C_SOURCE 200809L

#include "xrt.h"

#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define XDK_ENV_MAX 32

typedef struct {
    char  *name;
    size_t name_len;
    char  *value;
    size_t value_len;
    int    present;
} env_entry;

static env_entry g_env[XDK_ENV_MAX];
static size_t    g_env_n = 0;

void xdkc_diagnose(const char *bytes, size_t len) {
    if (bytes == NULL && len > 0) {
        xrt_fatal("diagnose：空指针带长度（S5 §4.3）");
    }
    char chunk[512];
    size_t i = 0;
    while (i < len) {
        size_t n = len - i;
        if (n > sizeof(chunk)) {
            n = sizeof(chunk);
        }
        for (size_t k = 0; k < n; k++) {
            char c = bytes[i + k];
            chunk[k] = (c == '\n' || c == '\r') ? ' ' : c; /* 单行合同 */
        }
        ssize_t w = write(STDERR_FILENO, chunk, n);
        (void)w;
        i += n;
    }
    ssize_t w = write(STDERR_FILENO, "\n", 1);
    (void)w;
}

void xdkc_exit(int64_t code) {
    _Exit((int)code); /* 不执行 defer/atexit（S1 §10.3） */
}

int64_t xdkc_now_mono_ms(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        xrt_fatal("nowMono：单调时钟不可用（S6 §4.4）");
    }
    return (int64_t)ts.tv_sec * 1000 + (int64_t)(ts.tv_nsec / 1000000);
}

int64_t xdkc_now_wall_ms(void) {
    /* UTC 毫秒、允许回拨；更高精度不承诺（S6 §4.4 定案 3-d-2） */
    return (int64_t)time(NULL) * 1000;
}

static env_entry *env_slot(const char *name, size_t len) {
    for (size_t i = 0; i < g_env_n; i++) {
        if (g_env[i].name_len == len && memcmp(g_env[i].name, name, len) == 0) {
            return &g_env[i];
        }
    }
    if (g_env_n >= XDK_ENV_MAX) {
        xrt_fatal("env：快照容量已满（S6 §4.4）");
    }
    env_entry *e = &g_env[g_env_n++];
    e->name = malloc(len + 1);
    if (e->name == NULL) {
        xrt_fatal("env：快照内存不足（S6 §4.4）");
    }
    memcpy(e->name, name, len);
    e->name[len] = 0;
    e->name_len = len;
    const char *v = getenv(e->name);
    if (v == NULL) {
        e->present = 0;
        e->value = NULL;
        e->value_len = 0;
        return e;
    }
    size_t vl = strlen(v);
    e->value = malloc(vl + 1);
    if (e->value == NULL) {
        xrt_fatal("env：快照内存不足（S6 §4.4）");
    }
    memcpy(e->value, v, vl + 1);
    e->value_len = vl;
    e->present = 1;
    return e;
}

const char *xdkc_env_get(const char *name, size_t len, size_t *out_len) {
    if (name == NULL || out_len == NULL) {
        xrt_fatal("env：参数为空（S6 §4.4）");
    }
    env_entry *e = env_slot(name, len);
    if (e == NULL || !e->present) {
        *out_len = 0;
        return NULL;
    }
    *out_len = e->value_len;
    return e->value;
}
