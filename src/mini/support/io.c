#include "rt.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Returns a NUL-terminated file image. The mini compiler reads one source
 * file at a time; the backing buffer is intentionally process-lifetime. */
const char *mini_read_file(const char *path_bytes, size_t path_len) {
    char *path = (char *)malloc(path_len + 1);
    if (path == NULL) {
        return "";
    }
    memcpy(path, path_bytes, path_len);
    path[path_len] = '\0';

    FILE *f = fopen(path, "rb");
    free(path);
    if (f == NULL) {
        return "";
    }
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return "";
    }
    long n = ftell(f);
    if (n < 0) {
        fclose(f);
        return "";
    }
    rewind(f);
    char *buf = (char *)malloc((size_t)n + 1);
    if (buf == NULL) {
        fclose(f);
        return "";
    }
    size_t got = fread(buf, 1, (size_t)n, f);
    fclose(f);
    buf[got] = '\0';
    return buf;
}

const char *mini_platform(void) {
    return "darwin";
}

int32_t mini_file_exists(const char *path, size_t len) {
    char *p = (char *)malloc(len + 1);
    if (p == NULL) { return 0; }
    memcpy(p, path, len);
    p[len] = '\0';
    int ok = access(p, F_OK) == 0;
    free(p);
    return ok ? 1 : 0;
}
