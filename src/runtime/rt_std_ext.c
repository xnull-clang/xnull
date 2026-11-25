/* rt_std_ext.c — XDK 扩展包原语（math/time/env/util/codec 后端）
 *
 * 合同：
 *   - 只依赖 libc/libm/libz；符号前缀 xdkc_ 为工具链内部库面（随产物静态编入）。
 *   - String 形态的 FFI 返回一律不返回 NULL（缺失映射空串）；
 *   - 二进制进出统一走 hex 字符串（与 sys_raw 的 readFileHexRaw 约定一致），
 *     避免 Bytes 借出 ABI 在冻结编译器调用点的已记录缺陷（B5）。
 *   - malloc 返回的 C 字符串由 FFI 拷贝进 rt_string 后不再释放（进程生命周期）。
 */

#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <zlib.h>

#if defined(__APPLE__)
#include <sys/sysctl.h>
#endif
#if defined(__linux__) && defined(__GLIBC__)
#include <gnu/libc-version.h>
#endif

#include <stdint.h>
#include <pthread.h>

#ifdef __linux__
#include <fcntl.h>
#include <sys/random.h>
#endif

/* ---------- math ---------- */

double xdkc_math_sqrt(double x)  { return sqrt(x); }
double xdkc_math_cbrt(double x)  { return cbrt(x); }
double xdkc_math_pow(double x, double y) { return pow(x, y); }
double xdkc_math_exp(double x)   { return exp(x); }
double xdkc_math_log(double x)   { return log(x); }
double xdkc_math_log2(double x)  { return log2(x); }
double xdkc_math_log10(double x) { return log10(x); }
double xdkc_math_sin(double x)   { return sin(x); }
double xdkc_math_cos(double x)   { return cos(x); }
double xdkc_math_tan(double x)   { return tan(x); }
double xdkc_math_asin(double x)  { return asin(x); }
double xdkc_math_acos(double x)  { return acos(x); }
double xdkc_math_atan(double x)  { return atan(x); }
double xdkc_math_atan2(double y, double x) { return atan2(y, x); }
double xdkc_math_sinh(double x)  { return sinh(x); }
double xdkc_math_cosh(double x)  { return cosh(x); }
double xdkc_math_tanh(double x)  { return tanh(x); }
double xdkc_math_fmod(double a, double b)  { return fmod(a, b); }
double xdkc_math_floor(double x)  { return floor(x); }
double xdkc_math_ceil(double x)   { return ceil(x); }
double xdkc_math_round(double x)  { return round(x); }
double xdkc_math_trunc(double x)  { return trunc(x); }
double xdkc_math_nan(void) { return NAN; }
double xdkc_math_inf(void) { return INFINITY; }
int32_t xdkc_math_isnan(double x)  { return isnan(x) ? 1 : 0; }
int32_t xdkc_math_isinf(double x)  { return isinf(x) ? 1 : 0; }

/* ---------- random（xorshift64*，全局实例） ---------- */

static uint64_t g_rand_state = 88172645463325252ULL;

void xdkc_rand_seed(int64_t s) {
    g_rand_state = (uint64_t)s ? (uint64_t)s : 88172645463325252ULL;
}

static uint64_t rnd64(void) {
    uint64_t x = g_rand_state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    g_rand_state = x;
    return x * 2685821657736338717ULL;
}

int64_t xdkc_rand_next(void) {
    return (int64_t)(rnd64() >> 1); /* 非负 */
}

double xdkc_rand_double(void) {
    return (double)(rnd64() >> 11) * (1.0 / 9007199254740992.0); /* [0,1) */
}

/* ---------- 安全随机（OS CSPRNG） ---------- */

static void secure_fill(uint8_t *buf, int32_t count) {
#if defined(__APPLE__)
    arc4random_buf(buf, (size_t)count);
#elif defined(__linux__)
    int32_t off = 0;
    while (off < count) {
        ssize_t n = getrandom(buf + off, (size_t)(count - off), 0);
        if (n > 0) {
            off += (int32_t)n;
        } else if (n < 0 && errno == EINTR) {
            continue;
        } else {
            break;
        }
    }
    if (off < count) {
        int fd = open("/dev/urandom", O_RDONLY);
        if (fd >= 0) {
            while (off < count) {
                ssize_t n = read(fd, buf + off, (size_t)(count - off));
                if (n > 0) {
                    off += (int32_t)n;
                } else if (n < 0 && errno == EINTR) {
                    continue;
                } else {
                    break;
                }
            }
            close(fd);
        }
    }
    if (off < count) {
        memset(buf + off, 0, (size_t)(count - off));
    }
#else
    int fd = open("/dev/urandom", O_RDONLY);
    if (fd < 0) {
        memset(buf, 0, (size_t)count);
        return;
    }
    int32_t off = 0;
    while (off < count) {
        ssize_t n = read(fd, buf + off, (size_t)(count - off));
        if (n > 0) {
            off += (int32_t)n;
        } else if (n < 0 && errno == EINTR) {
            continue;
        } else {
            break;
        }
    }
    close(fd);
    if (off < count) {
        memset(buf + off, 0, (size_t)(count - off));
    }
#endif
}

char *xdkc_secure_random_hex(int32_t count) {
    static const char hexd[] = "0123456789abcdef";
    if (count <= 0) {
        char *empty = (char *)malloc(1);
        if (empty != NULL) {
            empty[0] = 0;
        }
        return empty;
    }
    uint8_t *buf = (uint8_t *)malloc((size_t)count);
    char *out = (char *)malloc((size_t)count * 2 + 1);
    if (buf == NULL || out == NULL) {
        free(buf);
        free(out);
        return NULL;
    }
    secure_fill(buf, count);
    for (int32_t i = 0; i < count; i++) {
        out[i * 2] = hexd[buf[i] >> 4];
        out[i * 2 + 1] = hexd[buf[i] & 0xF];
    }
    out[(size_t)count * 2] = 0;
    free(buf);
    return out;
}

/* ---------- ULID 单调计数器（每毫秒） ---------- */

static pthread_mutex_t g_ulid_mu = PTHREAD_MUTEX_INITIALIZER;
static int64_t g_ulid_last_ms = -1;
static int64_t g_ulid_seq = 0;

int64_t xdkc_ulid_monotonic(int64_t millis) {
    pthread_mutex_lock(&g_ulid_mu);
    if (millis != g_ulid_last_ms) {
        g_ulid_last_ms = millis;
        g_ulid_seq = 0;
    } else {
        g_ulid_seq++;
    }
    int64_t value = g_ulid_seq;
    pthread_mutex_unlock(&g_ulid_mu);
    return value;
}

/* ---------- time ---------- */

int64_t xdkc_now_micros(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        return 0;
    }
    return (int64_t)ts.tv_sec * 1000000 + (int64_t)(ts.tv_nsec / 1000);
}

void xdkc_sleep_ms(int64_t ms) {
    if (ms <= 0) {
        return;
    }
    struct timespec req;
    req.tv_sec = (time_t)(ms / 1000);
    req.tv_nsec = (long)((ms % 1000) * 1000000);
    while (nanosleep(&req, &req) != 0) {
        /* 被信号打断则继续剩余时长 */
    }
}

/* ---------- env / system ---------- */

const char *xdkc_env_lookup2(const char *name) {
    const char *v = getenv(name);
    return v ? v : "";
}

int32_t xdkc_env_has(const char *name) {
    return getenv(name) != NULL ? 1 : 0;
}

const char *xdkc_hostname(void) {
    static char buf[256];
    if (gethostname(buf, sizeof(buf) - 1) != 0) {
        return "";
    }
    buf[sizeof(buf) - 1] = 0;
    return buf;
}

/* ---------- OS identity ---------- */

static const char *xdkc_os_release_value(const char *key) {
    static char buf[256];
    FILE *file = fopen("/etc/os-release", "r");
    if (file == NULL) {
        file = fopen("/usr/lib/os-release", "r");
    }
    if (file == NULL) {
        return "";
    }
    size_t keylen = strlen(key);
    char line[512];
    while (fgets(line, sizeof(line), file) != NULL) {
        if (strncmp(line, key, keylen) != 0 || line[keylen] != '=') {
            continue;
        }
        char *value = line + keylen + 1;
        size_t len = strlen(value);
        while (len > 0 && (value[len - 1] == '\n' || value[len - 1] == '\r')) {
            value[len - 1] = 0;
            len--;
        }
        if (len >= 2 && (value[0] == '"' || value[0] == '\'')) {
            char quote = value[0];
            if (value[len - 1] == quote) {
                value[len - 1] = 0;
                value++;
            }
        }
        snprintf(buf, sizeof(buf), "%s", value);
        fclose(file);
        return buf;
    }
    fclose(file);
    return "";
}

const char *xdkc_os_name(void) {
#if defined(__APPLE__)
    return "macOS";
#elif defined(__linux__)
    const char *release = xdkc_os_release_value("NAME");
    if (release[0] != 0) {
        return release;
    }
    static char buf[256];
    struct utsname u;
    if (uname(&u) != 0) {
        return "";
    }
    snprintf(buf, sizeof(buf), "%s", u.sysname);
    return buf;
#else
    static char buf[256];
    struct utsname u;
    if (uname(&u) != 0) {
        return "";
    }
    snprintf(buf, sizeof(buf), "%s", u.sysname);
    return buf;
#endif
}

const char *xdkc_os_version(void) {
#if defined(__APPLE__)
    static char buf[128];
    size_t len = sizeof(buf) - 1;
    if (sysctlbyname("kern.osproductversion", buf, &len, NULL, 0) != 0) {
        return "";
    }
    buf[len] = 0;
    return buf;
#elif defined(__linux__)
    const char *release = xdkc_os_release_value("VERSION_ID");
    if (release[0] != 0) {
        return release;
    }
    return xdkc_os_release_value("VERSION");
#else
    return "";
#endif
}

const char *xdkc_kernel_version(void) {
    static char buf[256];
    struct utsname u;
    if (uname(&u) != 0) {
        return "";
    }
    snprintf(buf, sizeof(buf), "%s", u.release);
    return buf;
}

const char *xdkc_libc_version(void) {
#if defined(__APPLE__)
    return "libSystem";
#elif defined(__linux__) && defined(__GLIBC__)
    static char buf[64];
    snprintf(buf, sizeof(buf), "glibc %s", gnu_get_libc_version());
    return buf;
#else
    return "";
#endif
}

int32_t xdkc_is_containerized(void) {
#if defined(__linux__)
    if (access("/.dockerenv", F_OK) == 0) {
        return 1;
    }
    FILE *file = fopen("/proc/1/cgroup", "r");
    if (file != NULL) {
        char line[512];
        while (fgets(line, sizeof(line), file) != NULL) {
            if (strstr(line, "docker") != NULL || strstr(line, "kubepods") != NULL ||
                strstr(line, "containerd") != NULL || strstr(line, "lxc") != NULL ||
                strstr(line, "podman") != NULL) {
                fclose(file);
                return 1;
            }
        }
        fclose(file);
    }
    return 0;
#elif defined(__APPLE__)
    const char *container = getenv("container");
    if (container != NULL && container[0] != 0) {
        return 1;
    }
    const char *docker = getenv("DOCKER");
    if (docker != NULL && docker[0] != 0) {
        return 1;
    }
    return 0;
#else
    return 0;
#endif
}

const char *xdkc_platform(void) {
#if defined(__APPLE__)
    return "darwin";
#elif defined(__linux__)
    return "linux";
#else
    return "unknown";
#endif
}

const char *xdkc_arch(void) {
    static char buf[64];
    struct utsname u;
    if (uname(&u) != 0) {
        return "";
    }
    snprintf(buf, sizeof(buf), "%s", u.machine);
    return buf;
}

int64_t xdkc_pid(void) {
    return (int64_t)getpid();
}

const char *xdkc_cwd(void) {
    static char buf[4096];
    if (getcwd(buf, sizeof(buf)) == NULL) {
        return "";
    }
    return buf;
}

int32_t xdkc_chdir(const char *path) {
    return chdir(path) == 0 ? 1 : 0;
}

int64_t xdkc_file_mtime(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0) {
        return -1;
    }
    return (int64_t)st.st_mtime * 1000;
}

const char *xdkc_stdin_line(void) {
    static char buf[4096];
    if (fgets(buf, (int)sizeof(buf), stdin) == NULL) {
        return "";
    }
    size_t n = strlen(buf);
    while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r')) {
        buf[--n] = 0;
    }
    return buf;
}

/* ---------- hex 工具（内部） ---------- */

static int hexval(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static size_t hex_decode(const char *hex, size_t n, uint8_t *out) {
    size_t m = 0;
    for (size_t i = 0; i + 1 < n; i += 2) {
        int hi = hexval(hex[i]);
        int lo = hexval(hex[i + 1]);
        if (hi < 0 || lo < 0) {
            return m;
        }
        out[m++] = (uint8_t)((hi << 4) | lo);
    }
    return m;
}

static const char HEXD[] = "0123456789abcdef";

/* 返回 malloc 的十六进制串（调用方负责释放；FFI 层拷贝后按进程生命周期泄漏） */
static char *hex_encode_alloc(const uint8_t *data, size_t n) {
    char *s = (char *)malloc(n * 2 + 1);
    if (s == NULL) {
        return NULL;
    }
    for (size_t i = 0; i < n; i++) {
        s[i * 2] = HEXD[data[i] >> 4];
        s[i * 2 + 1] = HEXD[data[i] & 0xF];
    }
    s[n * 2] = 0;
    return s;
}

/* ---------- process stdio adapter（B2） ----------
 *
 * 读走 read(0)，写走 write(1/2)：二进制安全，不受 NUL 或 stdio 行缓冲影响。
 * 返回 hex 的静态缓冲由 FFI 层立即拷贝；调用期间不得重入。
 * 读失败与 EOF 都返回空串（xdk.io 将其映射为 DataCorrupted），写失败返回 -1。
 */
#define XDKC_STDIO_READ_MAX (64 * 1024)

static char *g_stdio_read_hex = NULL;
static size_t g_stdio_read_hex_cap = 0;

char *xdkc_stdio_read_hex(int64_t max_bytes) {
    if (max_bytes <= 0) {
        return "";
    }
    if (max_bytes > XDKC_STDIO_READ_MAX) {
        max_bytes = XDKC_STDIO_READ_MAX;
    }
    size_t need = (size_t)max_bytes * 2 + 1;
    if (need > g_stdio_read_hex_cap) {
        char *grown = (char *)realloc(g_stdio_read_hex, need);
        if (grown == NULL) {
            return "";
        }
        g_stdio_read_hex = grown;
        g_stdio_read_hex_cap = need;
    }
    unsigned char *bytes = (unsigned char *)malloc((size_t)max_bytes);
    if (bytes == NULL) {
        return "";
    }
    ssize_t got;
    do {
        got = read(STDIN_FILENO, bytes, (size_t)max_bytes);
    } while (got < 0 && errno == EINTR);
    if (got <= 0) {
        free(bytes);
        return "";
    }
    for (ssize_t i = 0; i < got; i++) {
        g_stdio_read_hex[i * 2] = HEXD[bytes[i] >> 4];
        g_stdio_read_hex[i * 2 + 1] = HEXD[bytes[i] & 0xF];
    }
    g_stdio_read_hex[got * 2] = 0;
    free(bytes);
    return g_stdio_read_hex;
}

int32_t xdkc_stdio_write_hex(int32_t fd, const char *hex, size_t hlen) {
    if (fd != 1 && fd != 2) {
        return -1;
    }
    if (hlen == 0) {
        return 0;
    }
    if (hlen % 2 != 0) {
        return -1;
    }
    size_t n = hlen / 2;
    unsigned char *bytes = (unsigned char *)malloc(n);
    if (bytes == NULL) {
        return -1;
    }
    size_t decoded = hex_decode(hex, hlen, bytes);
    if (decoded != n) {
        free(bytes);
        return -1;
    }
    /* 先冲刷同一 fd 上的 stdio 缓冲，保证 print 与 writer 的顺序稳定。 */
    if (fd == 1) {
        fflush(stdout);
    } else {
        fflush(stderr);
    }
    size_t written = 0;
    while (written < n) {
        ssize_t w = write(fd, bytes + written, n - written);
        if (w < 0) {
            if (errno == EINTR) {
                continue;
            }
            free(bytes);
            return -1;
        }
        written += (size_t)w;
    }
    free(bytes);
    return (int32_t)n;
}

int32_t xdkc_stdio_flush(int32_t fd) {
    if (fd != 1 && fd != 2) {
        return -1;
    }
    return fflush(fd == 1 ? stdout : stderr) == 0 ? 0 : -1;
}

/* ---------- SHA-256 / SHA-512 / SHA-1 / MD5 / HMAC / CRC32 ---------- */

typedef struct {
    uint32_t h[8];
    uint64_t len;
    uint8_t  buf[64];
    size_t   buflen;
} sha256_ctx;

static const uint32_t K256[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

#define ROR32(x, n) (((x) >> (n)) | ((x) << (32 - (n))))
#define ROL32(x, n) (((x) << (n)) | ((x) >> (32 - (n))))

static void sha256_init(sha256_ctx *c) {
    c->h[0] = 0x6a09e667; c->h[1] = 0xbb67ae85; c->h[2] = 0x3c6ef372; c->h[3] = 0xa54ff53a;
    c->h[4] = 0x510e527f; c->h[5] = 0x9b05688c; c->h[6] = 0x1f83d9ab; c->h[7] = 0x5be0cd19;
    c->len = 0; c->buflen = 0;
}

static void sha256_block(sha256_ctx *c, const uint8_t *p) {
    uint32_t w[64];
    for (int i = 0; i < 16; i++) {
        w[i] = ((uint32_t)p[i * 4] << 24) | ((uint32_t)p[i * 4 + 1] << 16) |
               ((uint32_t)p[i * 4 + 2] << 8) | (uint32_t)p[i * 4 + 3];
    }
    for (int i = 16; i < 64; i++) {
        uint32_t s0 = ROR32(w[i - 15], 7) ^ ROR32(w[i - 15], 18) ^ (w[i - 15] >> 3);
        uint32_t s1 = ROR32(w[i - 2], 17) ^ ROR32(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    uint32_t a = c->h[0], b = c->h[1], d = c->h[3], e = c->h[4];
    uint32_t f = c->h[5], g = c->h[6], h = c->h[7], cc = c->h[2];
    for (int i = 0; i < 64; i++) {
        uint32_t S1 = ROR32(e, 6) ^ ROR32(e, 11) ^ ROR32(e, 25);
        uint32_t ch = (e & f) ^ (~e & g);
        uint32_t t1 = h + S1 + ch + K256[i] + w[i];
        uint32_t S0 = ROR32(a, 2) ^ ROR32(a, 13) ^ ROR32(a, 22);
        uint32_t mj = (a & b) ^ (a & cc) ^ (b & cc);
        uint32_t t2 = S0 + mj;
        h = g; g = f; f = e; e = d + t1;
        d = cc; cc = b; b = a; a = t1 + t2;
    }
    c->h[0] += a; c->h[1] += b; c->h[2] += cc; c->h[3] += d;
    c->h[4] += e; c->h[5] += f; c->h[6] += g; c->h[7] += h;
}

static void sha256_update(sha256_ctx *c, const uint8_t *p, size_t n) {
    c->len += n;
    while (n > 0) {
        size_t k = 64 - c->buflen;
        if (k > n) k = n;
        memcpy(c->buf + c->buflen, p, k);
        c->buflen += k;
        p += k;
        n -= k;
        if (c->buflen == 64) {
            sha256_block(c, c->buf);
            c->buflen = 0;
        }
    }
}

static void sha256_final(sha256_ctx *c, uint8_t *out) {
    uint64_t bits = c->len * 8;
    uint8_t pad = 0x80;
    sha256_update(c, &pad, 1);
    uint8_t z = 0;
    while (c->buflen != 56) {
        sha256_update(c, &z, 1);
    }
    uint8_t lenb[8];
    for (int i = 0; i < 8; i++) {
        lenb[i] = (uint8_t)(bits >> (56 - i * 8));
    }
    /* 直接写入（长度已计过 padding？否——先记 bits 再 update，上面已累计，
     * 因此这里绕过 update 手工补块） */
    memcpy(c->buf + c->buflen, lenb, 8);
    c->buflen += 8;
    if (c->buflen == 64) {
        sha256_block(c, c->buf);
        c->buflen = 0;
    }
    for (int i = 0; i < 8; i++) {
        out[i * 4] = (uint8_t)(c->h[i] >> 24);
        out[i * 4 + 1] = (uint8_t)(c->h[i] >> 16);
        out[i * 4 + 2] = (uint8_t)(c->h[i] >> 8);
        out[i * 4 + 3] = (uint8_t)c->h[i];
    }
}

char *xdkc_sha256_hex(const char *data, size_t n) {
    static char out[65];
    sha256_ctx c;
    sha256_init(&c);
    sha256_update(&c, (const uint8_t *)data, n);
    uint8_t d[32];
    sha256_final(&c, d);
    for (int i = 0; i < 32; i++) {
        out[i * 2] = HEXD[d[i] >> 4];
        out[i * 2 + 1] = HEXD[d[i] & 0xF];
    }
    out[64] = 0;
    return out;
}

/* SHA-1 */
typedef struct {
    uint32_t h[5];
    uint64_t len;
    uint8_t  buf[64];
    size_t   buflen;
} sha1_ctx;

static void sha1_init(sha1_ctx *c) {
    c->h[0] = 0x67452301; c->h[1] = 0xefcdab89; c->h[2] = 0x98badcfe;
    c->h[3] = 0x10325476; c->h[4] = 0xc3d2e1f0;
    c->len = 0; c->buflen = 0;
}

static void sha1_block(sha1_ctx *c, const uint8_t *p) {
    uint32_t w[80];
    for (int i = 0; i < 16; i++) {
        w[i] = ((uint32_t)p[i * 4] << 24) | ((uint32_t)p[i * 4 + 1] << 16) |
               ((uint32_t)p[i * 4 + 2] << 8) | (uint32_t)p[i * 4 + 3];
    }
    for (int i = 16; i < 80; i++) {
        w[i] = ROL32(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }
    uint32_t a = c->h[0], b = c->h[1], cc = c->h[2], d = c->h[3], e = c->h[4];
    for (int i = 0; i < 80; i++) {
        uint32_t f, k;
        if (i < 20)      { f = (b & cc) | ((~b) & d);          k = 0x5A827999U; }
        else if (i < 40) { f = b ^ cc ^ d;                     k = 0x6ED9EBA1U; }
        else if (i < 60) { f = (b & cc) | (b & d) | (cc & d);  k = 0x8F1BBCDCU; }
        else             { f = b ^ cc ^ d;                     k = 0xCA62C1D6U; }
        uint32_t t = ROL32(a, 5) + f + e + k + w[i];
        e = d; d = cc; cc = ROL32(b, 30); b = a; a = t;
    }
    c->h[0] += a; c->h[1] += b; c->h[2] += cc; c->h[3] += d; c->h[4] += e;
}

static void sha1_update(sha1_ctx *c, const uint8_t *p, size_t n) {
    c->len += n;
    while (n > 0) {
        size_t k = 64 - c->buflen;
        if (k > n) k = n;
        memcpy(c->buf + c->buflen, p, k);
        c->buflen += k;
        p += k;
        n -= k;
        if (c->buflen == 64) {
            sha1_block(c, c->buf);
            c->buflen = 0;
        }
    }
}

static void sha1_final(sha1_ctx *c, uint8_t *out) {
    uint64_t bits = (c->len - c->buflen) * 8 + c->buflen * 8; /* 与 256 相同语义，见下 */
    bits = 0; /* 重算：bits = 总比特数，在下面用 len 记录 */
    bits = c->len * 8;
    uint8_t pad = 0x80;
    uint64_t save = c->len;
    sha1_update(c, &pad, 1);
    uint8_t z = 0;
    while (c->buflen != 56) {
        sha1_update(c, &z, 1);
    }
    /* 补长度时不走 update（否则 bits 计入 padding） */
    uint8_t lenb[8];
    for (int i = 0; i < 8; i++) {
        lenb[i] = (uint8_t)(bits >> (56 - i * 8));
    }
    memcpy(c->buf + c->buflen, lenb, 8);
    c->buflen += 8;
    if (c->buflen == 64) {
        sha1_block(c, c->buf);
        c->buflen = 0;
    }
    (void)save;
    for (int i = 0; i < 5; i++) {
        out[i * 4] = (uint8_t)(c->h[i] >> 24);
        out[i * 4 + 1] = (uint8_t)(c->h[i] >> 16);
        out[i * 4 + 2] = (uint8_t)(c->h[i] >> 8);
        out[i * 4 + 3] = (uint8_t)c->h[i];
    }
}

char *xdkc_sha1_hex(const char *data, size_t n) {
    static char out[41];
    sha1_ctx c;
    sha1_init(&c);
    sha1_update(&c, (const uint8_t *)data, n);
    uint8_t d[20];
    sha1_final(&c, d);
    for (int i = 0; i < 20; i++) {
        out[i * 2] = HEXD[d[i] >> 4];
        out[i * 2 + 1] = HEXD[d[i] & 0xF];
    }
    out[40] = 0;
    return out;
}

/* MD5 */
typedef struct {
    uint32_t a, b, c, d;
    uint64_t len;
    uint8_t  buf[64];
    size_t   buflen;
} md5_ctx;

static uint32_t md5_f(uint32_t x, uint32_t y, uint32_t z) { return (x & y) | (~x & z); }
static uint32_t md5_g(uint32_t x, uint32_t y, uint32_t z) { return (x & z) | (y & ~z); }
static uint32_t md5_h(uint32_t x, uint32_t y, uint32_t z) { return x ^ y ^ z; }
static uint32_t md5_i(uint32_t x, uint32_t y, uint32_t z) { return y ^ (x | ~z); }
static uint32_t MD5_ROL32(uint32_t x, uint32_t n) { return (x << n) | (x >> (32 - n)); }

static void md5_init(md5_ctx *c) {
    c->a = 0x67452301; c->b = 0xefcdab89; c->c = 0x98badcfe; c->d = 0x10325476;
    c->len = 0; c->buflen = 0;
}

static void md5_block(md5_ctx *c, const uint8_t *p) {
    static const uint32_t K[64] = {
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a,
        0xa8304613, 0xfd469501, 0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
        0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821, 0xf61e2562, 0xc040b340,
        0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8,
        0x676f02d9, 0x8d2a4c8a, 0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
        0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70, 0x289b7ec6, 0xeaa127fa,
        0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92,
        0xffeff47d, 0x85845dd1, 0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
        0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
    };
    static const int R[64] = {
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
    };
    uint32_t m[16];
    for (int i = 0; i < 16; i++) {
        m[i] = (uint32_t)p[i * 4] | ((uint32_t)p[i * 4 + 1] << 8) |
               ((uint32_t)p[i * 4 + 2] << 16) | ((uint32_t)p[i * 4 + 3] << 24);
    }
    uint32_t a = c->a, b = c->b, d = c->c, e = c->d;
    for (int i = 0; i < 64; i++) {
        uint32_t f, g;
        if (i < 16)      { f = md5_f(b, d, e); g = i; }
        else if (i < 32) { f = md5_g(b, d, e); g = (5 * i + 1) % 16; }
        else if (i < 48) { f = md5_h(b, d, e); g = (3 * i + 5) % 16; }
        else             { f = md5_i(b, d, e); g = (7 * i) % 16; }
        uint32_t tmp = e;
        e = d;
        d = b;
        b = b + MD5_ROL32(a + f + K[i] + m[g], (uint32_t)R[i]);
        a = tmp;
    }
    c->a += a; c->b += b; c->c += d; c->d += e;
}

static void md5_update(md5_ctx *c, const uint8_t *p, size_t n) {
    c->len += n;
    while (n > 0) {
        size_t k = 64 - c->buflen;
        if (k > n) k = n;
        memcpy(c->buf + c->buflen, p, k);
        c->buflen += k;
        p += k;
        n -= k;
        if (c->buflen == 64) {
            md5_block(c, c->buf);
            c->buflen = 0;
        }
    }
}

static void md5_final(md5_ctx *c, uint8_t *out) {
    uint64_t bits = c->len * 8;
    uint8_t pad = 0x80;
    md5_update(c, &pad, 1);
    uint8_t z = 0;
    while (c->buflen != 56) {
        md5_update(c, &z, 1);
    }
    uint8_t lenb[8];
    for (int i = 0; i < 8; i++) {
        lenb[i] = (uint8_t)(bits >> (8 * i)); /* 小端 */
    }
    memcpy(c->buf + c->buflen, lenb, 8);
    c->buflen += 8;
    if (c->buflen == 64) {
        md5_block(c, c->buf);
        c->buflen = 0;
    }
    uint32_t regs[4] = { c->a, c->b, c->c, c->d };
    for (int i = 0; i < 4; i++) {
        out[i * 4] = (uint8_t)regs[i];
        out[i * 4 + 1] = (uint8_t)(regs[i] >> 8);
        out[i * 4 + 2] = (uint8_t)(regs[i] >> 16);
        out[i * 4 + 3] = (uint8_t)(regs[i] >> 24);
    }
}

char *xdkc_md5_hex(const char *data, size_t n) {
    static char out[33];
    md5_ctx c;
    md5_init(&c);
    md5_update(&c, (const uint8_t *)data, n);
    uint8_t d[16];
    md5_final(&c, d);
    for (int i = 0; i < 16; i++) {
        out[i * 2] = HEXD[d[i] >> 4];
        out[i * 2 + 1] = HEXD[d[i] & 0xF];
    }
    out[32] = 0;
    return out;
}

/* SHA-512 */
typedef struct {
    uint64_t h[8];
    uint64_t len;
    uint8_t  buf[128];
    size_t   buflen;
} sha512_ctx;

static const uint64_t K512[80] = {
    0x428a2f98d728ae22ULL, 0x7137449123ef65cdULL, 0xb5c0fbcfec4d3b2fULL, 0xe9b5dba58189dbbcULL,
    0x3956c25bf348b538ULL, 0x59f111f1b605d019ULL, 0x923f82a4af194f9bULL, 0xab1c5ed5da6d8118ULL,
    0xd807aa98a3030242ULL, 0x12835b0145706fbeULL, 0x243185be4ee4b28cULL, 0x550c7dc3d5ffb4e2ULL,
    0x72be5d74f27b896fULL, 0x80deb1fe3b1696b1ULL, 0x9bdc06a725c71235ULL, 0xc19bf174cf692694ULL,
    0xe49b69c19ef14ad2ULL, 0xefbe4786384f25e3ULL, 0x0fc19dc68b8cd5b5ULL, 0x240ca1cc77ac9c65ULL,
    0x2de92c6f592b0275ULL, 0x4a7484aa6ea6e483ULL, 0x5cb0a9dcbd41fbd4ULL, 0x76f988da831153b5ULL,
    0x983e5152ee66dfabULL, 0xa831c66d2db43210ULL, 0xb00327c898fb213fULL, 0xbf597fc7beef0ee4ULL,
    0xc6e00bf33da88fc2ULL, 0xd5a79147930aa725ULL, 0x06ca6351e003826fULL, 0x142929670a0e6e70ULL,
    0x27b70a8546d22ffcULL, 0x2e1b21385c26c926ULL, 0x4d2c6dfc5ac42aedULL, 0x53380d139d95b3dfULL,
    0x650a73548baf63deULL, 0x766a0abb3c77b2a8ULL, 0x81c2c92e47edaee6ULL, 0x92722c851482353bULL,
    0xa2bfe8a14cf10364ULL, 0xa81a664bbc423001ULL, 0xc24b8b70d0f89791ULL, 0xc76c51a30654be30ULL,
    0xd192e819d6ef5218ULL, 0xd69906245565a910ULL, 0xf40e35855771202aULL, 0x106aa07032bbd1b8ULL,
    0x19a4c116b8d2d0c8ULL, 0x1e376c085141ab53ULL, 0x2748774cdf8eeb99ULL, 0x34b0bcb5e19b48a8ULL,
    0x391c0cb3c5c95a63ULL, 0x4ed8aa4ae3418acbULL, 0x5b9cca4f7763e373ULL, 0x682e6ff3d6b2b8a3ULL,
    0x748f82ee5defb2fcULL, 0x78a5636f43172f60ULL, 0x84c87814a1f0ab72ULL, 0x8cc702081a6439ecULL,
    0x90befffa23631e28ULL, 0xa4506cebde82bde9ULL, 0xbef9a3f7b2c67915ULL, 0xc67178f2e372532bULL,
    0xca273eceea26619cULL, 0xd186b8c721c0c207ULL, 0xeada7dd6cde0eb1eULL, 0xf57d4f7fee6ed178ULL,
    0x06f067aa72176fbaULL, 0x0a637dc5a2c898a6ULL, 0x113f9804bef90daeULL, 0x1b710b35131c471bULL,
    0x28db77f523047d84ULL, 0x32caab7b40c72493ULL, 0x3c9ebe0a15c9bebcULL, 0x431d67c49c100d4cULL,
    0x4cc5d4becb3e42b6ULL, 0x597f299cfc657e2aULL, 0x5fcb6fab3ad6faecULL, 0x6c44198c4a475817ULL
};

#define ROR64(x, n) (((x) >> (n)) | ((x) << (64 - (n))))

static void sha512_init(sha512_ctx *c) {
    c->h[0] = 0x6a09e667f3bcc908ULL; c->h[1] = 0xbb67ae8584caa73bULL;
    c->h[2] = 0x3c6ef372fe94f82bULL; c->h[3] = 0xa54ff53a5f1d36f1ULL;
    c->h[4] = 0x510e527fade682d1ULL; c->h[5] = 0x9b05688c2b3e6c1fULL;
    c->h[6] = 0x1f83d9abfb41bd6bULL; c->h[7] = 0x5be0cd19137e2179ULL;
    c->len = 0; c->buflen = 0;
}

static void sha512_block(sha512_ctx *c, const uint8_t *p) {
    uint64_t w[80];
    for (int i = 0; i < 16; i++) {
        w[i] = 0;
        for (int j = 0; j < 8; j++) {
            w[i] = (w[i] << 8) | p[i * 8 + j];
        }
    }
    for (int i = 16; i < 80; i++) {
        uint64_t s0 = ROR64(w[i - 15], 1) ^ ROR64(w[i - 15], 8) ^ (w[i - 15] >> 7);
        uint64_t s1 = ROR64(w[i - 2], 19) ^ ROR64(w[i - 2], 61) ^ (w[i - 2] >> 6);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    uint64_t a = c->h[0], b = c->h[1], d = c->h[3], e = c->h[4];
    uint64_t f = c->h[5], g = c->h[6], h = c->h[7], cc = c->h[2];
    for (int i = 0; i < 80; i++) {
        uint64_t S1 = ROR64(e, 14) ^ ROR64(e, 18) ^ ROR64(e, 41);
        uint64_t ch = (e & f) ^ (~e & g);
        uint64_t t1 = h + S1 + ch + K512[i] + w[i];
        uint64_t S0 = ROR64(a, 28) ^ ROR64(a, 34) ^ ROR64(a, 39);
        uint64_t mj = (a & b) ^ (a & cc) ^ (b & cc);
        uint64_t t2 = S0 + mj;
        h = g; g = f; f = e; e = d + t1;
        d = cc; cc = b; b = a; a = t1 + t2;
    }
    c->h[0] += a; c->h[1] += b; c->h[2] += cc; c->h[3] += d;
    c->h[4] += e; c->h[5] += f; c->h[6] += g; c->h[7] += h;
}

static void sha512_update(sha512_ctx *c, const uint8_t *p, size_t n) {
    c->len += n;
    while (n > 0) {
        size_t k = 128 - c->buflen;
        if (k > n) k = n;
        memcpy(c->buf + c->buflen, p, k);
        c->buflen += k;
        p += k;
        n -= k;
        if (c->buflen == 128) {
            sha512_block(c, c->buf);
            c->buflen = 0;
        }
    }
}

static void sha512_final(sha512_ctx *c, uint8_t *out) {
    uint64_t bits = c->len * 8;
    uint8_t pad = 0x80;
    sha512_update(&*c, &pad, 1);
    uint8_t z = 0;
    while (c->buflen != 112) {
        sha512_update(c, &z, 1);
    }
    uint8_t lenb[16];
    for (int i = 0; i < 8; i++) {
        lenb[i] = 0; /* 高 64 位恒 0（长度 < 2^61 字节） */
    }
    for (int i = 0; i < 8; i++) {
        lenb[8 + i] = (uint8_t)(bits >> (56 - i * 8));
    }
    memcpy(c->buf + c->buflen, lenb, 16);
    c->buflen += 16;
    if (c->buflen == 128) {
        sha512_block(c, c->buf);
        c->buflen = 0;
    }
    for (int i = 0; i < 8; i++) {
        for (int j = 0; j < 8; j++) {
            out[i * 8 + j] = (uint8_t)(c->h[i] >> (56 - j * 8));
        }
    }
}

char *xdkc_sha512_hex(const char *data, size_t n) {
    static char out[129];
    sha512_ctx c;
    sha512_init(&c);
    sha512_update(&c, (const uint8_t *)data, n);
    uint8_t d[64];
    sha512_final(&c, d);
    for (int i = 0; i < 64; i++) {
        out[i * 2] = HEXD[d[i] >> 4];
        out[i * 2 + 1] = HEXD[d[i] & 0xF];
    }
    out[128] = 0;
    return out;
}

/* CRC-32（IEEE 802.3，zlib 多项式） */
static uint32_t crc_table[256];
static int crc_table_ready = 0;

static void crc_init_table(void) {
    if (crc_table_ready) {
        return;
    }
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t c = i;
        for (int k = 0; k < 8; k++) {
            c = (c & 1) ? 0xEDB88320U ^ (c >> 1) : c >> 1;
        }
        crc_table[i] = c;
    }
    crc_table_ready = 1;
}

int64_t xdkc_crc32(const char *data, size_t n) {
    crc_init_table();
    uint32_t c = 0xFFFFFFFFU;
    for (size_t i = 0; i < n; i++) {
        c = crc_table[(c ^ (uint8_t)data[i]) & 0xFF] ^ (c >> 8);
    }
    return (int64_t)(uint32_t)(c ^ 0xFFFFFFFFU);
}

/* HMAC-SHA256 */
char *xdkc_hmac_sha256_hex(const char *key, size_t klen, const char *data, size_t n) {
    static char out[65];
    uint8_t ip[64], op[64];
    uint8_t kbuf[64];
    memset(kbuf, 0, 64);
    if (klen > 64) {
        char *kd = xdkc_sha256_hex(key, klen);
        for (int i = 0; i < 32; i++) {
            kbuf[i] = (uint8_t)((hexval(kd[i * 2]) << 4) | hexval(kd[i * 2 + 1]));
        }
    } else {
        memcpy(kbuf, key, klen);
    }
    for (int i = 0; i < 64; i++) {
        ip[i] = kbuf[i] ^ 0x36;
        op[i] = kbuf[i] ^ 0x5c;
    }
    sha256_ctx c;
    sha256_init(&c);
    sha256_update(&c, ip, 64);
    sha256_update(&c, (const uint8_t *)data, n);
    uint8_t inner[32];
    sha256_final(&c, inner);

    sha256_init(&c);
    sha256_update(&c, op, 64);
    sha256_update(&c, inner, 32);
    uint8_t mac[32];
    sha256_final(&c, mac);
    for (int i = 0; i < 32; i++) {
        out[i * 2] = HEXD[mac[i] >> 4];
        out[i * 2 + 1] = HEXD[mac[i] & 0xF];
    }
    out[64] = 0;
    return out;
}

/* ---------- UUID v4 ---------- */

char *xdkc_uuid4(void) {
    static char out[37];
    uint8_t b[16];
    for (int i = 0; i < 16; i++) {
        b[i] = (uint8_t)(rnd64() >> 56);
    }
    b[6] = (uint8_t)((b[6] & 0x0F) | 0x40);
    b[8] = (uint8_t)((b[8] & 0x3F) | 0x80);
    const char *hx = HEXD;
    int p = 0;
    for (int i = 0; i < 16; i++) {
        if (i == 4 || i == 6 || i == 8 || i == 10) {
            out[p++] = '-';
        }
        out[p++] = hx[b[i] >> 4];
        out[p++] = hx[b[i] & 0xF];
    }
    out[p] = 0;
    return out;
}

/* ---------- gzip（zlib；hex 进出） ---------- */

char *xdkc_gzip_compress_hex(const char *hex, size_t hexlen) {
    size_t cap = hexlen / 2 + 64;
    uint8_t *src = (uint8_t *)malloc(cap);
    if (src == NULL) {
        return NULL;
    }
    size_t sn = hex_decode(hex, hexlen, src);

    z_stream zs;
    memset(&zs, 0, sizeof(zs));
    if (deflateInit2(&zs, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        free(src);
        return NULL;
    }
    size_t bound = deflateBound(&zs, sn) * 2 + 8;
    uint8_t *dst = (uint8_t *)malloc(bound / 2 + 16);
    if (dst == NULL) {
        deflateEnd(&zs);
        free(src);
        return NULL;
    }
    zs.next_in = src;
    zs.avail_in = (uInt)sn;
    zs.next_out = dst;
    zs.avail_out = (uInt)(bound / 2);
    int rc = deflate(&zs, Z_FINISH);
    size_t outn = (rc == Z_STREAM_END) ? zs.total_out : 0;
    deflateEnd(&zs);
    free(src);
    if (outn == 0) {
        free(dst);
        return NULL;
    }
    char *outhex = hex_encode_alloc(dst, outn);
    free(dst);
    return outhex;
}

char *xdkc_gzip_decompress_hex(const char *hex, size_t hexlen) {
    size_t cap = hexlen / 2 + 64;
    uint8_t *src = (uint8_t *)malloc(cap);
    if (src == NULL) {
        return NULL;
    }
    size_t sn = hex_decode(hex, hexlen, src);

    z_stream zs;
    memset(&zs, 0, sizeof(zs));
    /* windowBits 15+32：自动识别 gzip/zlib 头 */
    if (inflateInit2(&zs, 15 + 32) != Z_OK) {
        free(src);
        return NULL;
    }
    /* 压缩比上限按 64 倍预估，不够则扩容重试 */
    size_t cap2 = sn * 64 + 256;
    uint8_t *dst = (uint8_t *)malloc(cap2);
    if (dst == NULL) {
        inflateEnd(&zs);
        free(src);
        return NULL;
    }
    zs.next_in = src;
    zs.avail_in = (uInt)sn;
    zs.next_out = dst;
    zs.avail_out = (uInt)cap2;
    int rc = inflate(&zs, Z_FINISH);
    size_t outn = 0;
    if (rc == Z_STREAM_END || rc == Z_OK || rc == Z_BUF_ERROR) {
        outn = zs.total_out;
    }
    inflateEnd(&zs);
    free(src);
    if (outn == 0) {
        free(dst);
        return NULL;
    }
    char *outhex = hex_encode_alloc(dst, outn);
    free(dst);
    return outhex;
}

/* ---------- gzip/zlib/deflate 分级与限额（hex 进出） ---------- */

/* 0 = ok；1 = InvalidArgument（超限/空输入）；2 = DataCorrupted。
 * 每次 compress/decompress 入口重置；单线程使用。 */
static _Thread_local int32_t g_compress_error = 0;

int32_t xdkc_compress_last_error(void) {
    return g_compress_error;
}

static char *compress_hex_level(const char *hex, size_t hexlen, int32_t level, int windowBits) {
    g_compress_error = 0;
    if (level < 0 || level > 9) {
        level = Z_DEFAULT_COMPRESSION;
    }
    size_t cap = hexlen / 2 + 64;
    uint8_t *src = (uint8_t *)malloc(cap);
    if (src == NULL) {
        g_compress_error = 2;
        return NULL;
    }
    size_t sn = hex_decode(hex, hexlen, src);
    z_stream zs;
    memset(&zs, 0, sizeof(zs));
    if (deflateInit2(&zs, level, Z_DEFLATED, windowBits, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        free(src);
        g_compress_error = 2;
        return NULL;
    }
    size_t bound = deflateBound(&zs, sn);
    size_t alloc = bound > 64 ? bound : 64;
    uint8_t *dst = (uint8_t *)malloc(alloc);
    if (dst == NULL) {
        deflateEnd(&zs);
        free(src);
        g_compress_error = 2;
        return NULL;
    }
    zs.next_in = src;
    zs.avail_in = (uInt)sn;
    zs.next_out = dst;
    zs.avail_out = (uInt)alloc;
    int rc = deflate(&zs, Z_FINISH);
    size_t outn = (rc == Z_STREAM_END) ? zs.total_out : 0;
    deflateEnd(&zs);
    free(src);
    if (outn == 0) {
        free(dst);
        g_compress_error = 2;
        return NULL;
    }
    char *outhex = hex_encode_alloc(dst, outn);
    free(dst);
    return outhex;
}

static char *decompress_hex_limited(const char *hex, size_t hexlen, int windowBits, int32_t maxOut) {
    g_compress_error = 0;
    size_t sn = hexlen / 2;
    if (sn == 0) {
        g_compress_error = 1;
        char *empty = (char *)malloc(1);
        if (empty != NULL) {
            empty[0] = 0;
        }
        return empty;
    }
    uint8_t *src = (uint8_t *)malloc(sn);
    if (src == NULL) {
        g_compress_error = 2;
        return NULL;
    }
    size_t decoded = hex_decode(hex, hexlen, src);
    if (decoded != sn) {
        free(src);
        g_compress_error = 2;
        return NULL;
    }
    z_stream zs;
    memset(&zs, 0, sizeof(zs));
    if (inflateInit2(&zs, windowBits) != Z_OK) {
        free(src);
        g_compress_error = 2;
        return NULL;
    }
    size_t limit = 0;
    if (maxOut > 0) {
        limit = (size_t)maxOut + 1; /* +1 用于区分恰好等于 maxOut 与超限 */
    }
    size_t cap = sn * 8 + 256;
    if (cap < 1024) {
        cap = 1024;
    }
    if (limit > 0 && cap > limit) {
        cap = limit;
    }
    uint8_t *dst = (uint8_t *)malloc(cap);
    if (dst == NULL) {
        inflateEnd(&zs);
        free(src);
        g_compress_error = 2;
        return NULL;
    }
    zs.next_in = src;
    zs.avail_in = (uInt)sn;
    size_t total = 0;
    int done = 0;
    while (!done) {
        if (total >= cap) {
            if (limit > 0 && cap >= limit) {
                g_compress_error = 1;
                break;
            }
            size_t next = cap * 2;
            if (limit > 0 && next > limit) {
                next = limit;
            }
            uint8_t *grown = (uint8_t *)realloc(dst, next);
            if (grown == NULL) {
                g_compress_error = 2;
                break;
            }
            dst = grown;
            cap = next;
        }
        zs.next_out = dst + total;
        zs.avail_out = (uInt)(cap - total);
        int rc = inflate(&zs, Z_NO_FLUSH);
        total = cap - zs.avail_out;
        if (rc == Z_STREAM_END) {
            done = 1;
        } else if (rc == Z_OK) {
            if (total < cap) {
                /* 输出未满但仍未结束：输入可能耗尽，交给下一轮 Z_BUF_ERROR 判定。 */
                if (zs.avail_in == 0 && total < cap) {
                    g_compress_error = 2;
                    break;
                }
            }
        } else if (rc == Z_BUF_ERROR) {
            if (zs.avail_in == 0) {
                g_compress_error = 2;
                break;
            }
        } else {
            g_compress_error = 2;
            break;
        }
    }
    inflateEnd(&zs);
    free(src);
    if (g_compress_error != 0) {
        free(dst);
        char *empty = (char *)malloc(1);
        if (empty != NULL) {
            empty[0] = 0;
        }
        return empty;
    }
    char *outhex = hex_encode_alloc(dst, total);
    free(dst);
    return outhex;
}

char *xdkc_gzip_compress_level_hex(const char *hex, size_t hexlen, int32_t level) {
    return compress_hex_level(hex, hexlen, level, 15 + 16);
}

char *xdkc_gzip_decompress_limited_hex(const char *hex, size_t hexlen, int32_t maxOut) {
    return decompress_hex_limited(hex, hexlen, 15 + 16, maxOut);
}

char *xdkc_zlib_compress_level_hex(const char *hex, size_t hexlen, int32_t level) {
    return compress_hex_level(hex, hexlen, level, 15);
}

char *xdkc_zlib_decompress_limited_hex(const char *hex, size_t hexlen, int32_t maxOut) {
    return decompress_hex_limited(hex, hexlen, 15, maxOut);
}

char *xdkc_deflate_compress_level_hex(const char *hex, size_t hexlen, int32_t level) {
    return compress_hex_level(hex, hexlen, level, -15);
}

char *xdkc_deflate_decompress_limited_hex(const char *hex, size_t hexlen, int32_t maxOut) {
    return decompress_hex_limited(hex, hexlen, -15, maxOut);
}

/* ---------- 浮点位模式（BinaryWriter/Reader 用） ---------- */

int64_t xdkc_f64_bits(double v) {
    uint64_t u;
    memcpy(&u, &v, 8);
    return (int64_t)u;
}

double xdkc_f64_from_bits(int64_t b) {
    uint64_t u = (uint64_t)b;
    double v;
    memcpy(&v, &u, 8);
    return v;
}

int64_t xdkc_f32_bits(float v) {
    uint32_t u;
    memcpy(&u, &v, 4);
    return (int64_t)u;
}

double xdkc_f32_from_bits(int64_t b) {
    uint32_t u = (uint32_t)b;
    float v;
    memcpy(&v, &u, 4);
    return (double)v;
}
