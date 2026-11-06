/* rt_std_sys.c — XDK sys 文件原语（S6 §4.7；M4.6b 文件子集）
 *
 * 合同：
 *   - 文件句柄由 xrt_handle 包装（S3 §18：close 显式、幂等、不以 deinit 为唯一路径）；
 *   - 原生指针为 FILE*，只经本文件的函数解释，不外泄给其他单元；
 *   - 失败以错误码返回，不 panic（S6 §3 第 1 条）：0 成功、1 句柄无效、2 IO 失败。
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

static char *path_dup(const char *bytes, size_t len) {
    char *p = malloc(len + 1);
    if (p == NULL) {
        xrt_fatal("sys：路径缓冲不足（S6 §4.7）");
    }
    memcpy(p, bytes, len);
    p[len] = 0;
    return p;
}

void *xdkc_file_open_read(const char *bytes, size_t len) {
    if (bytes == NULL) {
        xrt_fatal("fileOpenRead：路径为空（S6 §4.7）");
    }
    if (len == 0 || memchr(bytes, 0, len) != NULL) {
        return NULL; /* 空路径或含 NUL：非法路径 */
    }
    char *p = path_dup(bytes, len);
    FILE *f = fopen(p, "rb");
    free(p);
    return f;
}

/* 返回值 = 读取字节数；code 为错误码出参（0 成功、1 句柄无效、2 IO 失败）。
 * 该形态与 .xfb 的 @errorCode(codeParam = .code) 合同一一对应（S7 §7.1）。 */
int64_t xdkc_file_read(void *fp, void *buf, size_t cap, int32_t *code) {
    if (code == NULL) {
        xrt_fatal("fileRead：错误码出参为空（S6 §4.7）");
    }
    *code = 0;
    if (fp == NULL) {
        *code = 1;
        return 0;
    }
    if (cap > 0 && buf == NULL) {
        xrt_fatal("fileRead：缓冲为空但容量非零（S6 §4.7）");
    }
    size_t n = fread(buf, 1, cap, (FILE *)fp);
    if (ferror((FILE *)fp)) {
        *code = 2;
        return 0;
    }
    return (int64_t)n;
}

int32_t xdkc_file_write(void *fp, const void *buf, size_t n) {
    if (fp == NULL) {
        return 1;
    }
    if (n > 0 && buf == NULL) {
        xrt_fatal("fileWrite：缓冲为空但长度非零（S6 §4.7）");
    }
    if (n > 0 && fwrite(buf, 1, n, (FILE *)fp) != n) {
        return 2;
    }
    return 0;
}

int32_t xdkc_file_close(void *fp) {
    if (fp == NULL) {
        return 0; /* 幂等：重复关闭成功（S7 §4.3 / INV-FFI-9 同款） */
    }
    return fclose((FILE *)fp) == 0 ? 0 : 2;
}

/* ---- 目录与路径（S6 §4.7 目录子集；M4.6b-2） ----
 *
 * 合同：
 *   - 目录句柄同样走 xrt_handle 包装（原生 DIR*，close 幂等）；
 *   - dirRead 返回内部缓冲指针，仅在下次调用前有效（逐项迭代，无分配）；
 *   - 迭代顺序依文件系统（不排序）；需要确定性顺序由调用方排序；
 *   - pathExists 对目录与文件同真；无权限按不存在返回（不区分错误类型）。
 */

void *xdkc_dir_open(const char *path, size_t len) {
    if (path == NULL) {
        xrt_fatal("dirOpen：路径为空（S6 §4.7）");
    }
    if (len == 0 || memchr(path, 0, len) != NULL) {
        return NULL;
    }
    char *p = path_dup(path, len);
    DIR *d = opendir(p);
    free(p);
    return d;
}

const char *xdkc_dir_read(void *dp) {
    if (dp == NULL) {
        return NULL;
    }
    struct dirent *e = readdir((DIR *)dp);
    if (e == NULL) {
        return NULL;
    }
    return e->d_name; /* 内部缓冲：下次调用前有效 */
}

int32_t xdkc_dir_close(void *dp) {
    if (dp == NULL) {
        return 0; /* 幂等 */
    }
    return closedir((DIR *)dp) == 0 ? 0 : 2;
}

int32_t xdkc_path_exists(const char *path, size_t len) {
    if (path == NULL || len == 0 || memchr(path, 0, len) != NULL) {
        return 0;
    }
    char *p = path_dup(path, len);
    struct stat st;
    int ok = stat(p, &st) == 0;
    free(p);
    return ok ? 1 : 0;
}

/* ---- 子进程（阻塞面：调用方按 .unaware 分类，S6 §9） ----
 *
 * 合同：返回被调命令的退出码（0—255）；被信号终止或无法启动返回 -1。
 * 命令经 shell 解释（system 语义）：仅用于工具型子进程，不解析参数向量；
 * 更细的 spawn/管道形态随调度器切片另行提案。
 */
int32_t xdkc_proc_status(const char *cmd, size_t len) {
    if (cmd == NULL || len == 0 || memchr(cmd, 0, len) != NULL) {
        return -1;
    }
    char *c = path_dup(cmd, len);
    int st = system(c);
    free(c);
    if (st == -1 || !WIFEXITED(st)) {
        return -1;
    }
    return (int32_t)WEXITSTATUS(st);
}
