package ffi

// emptyResC 是零资源表（xrt_std_res.c 的资源符号闭合，S6-04）。
const emptyResC = `
#include <stddef.h>
size_t xrt_resource_count(void) { return 0; }
int xrt_resource_get(const char *name, size_t nlen,
                     const unsigned char **out, size_t *out_len) {
    (void)name; (void)nlen; *out = 0; *out_len = 0; return 1;
}
int xrt_resource_at(size_t i, const char **name, size_t *nlen,
                    const unsigned char **out, size_t *out_len) {
    (void)i; *name = 0; *nlen = 0; *out = 0; *out_len = 0; return 1;
}
`

// rtSources 是 FFI 端到端测试链接的运行时源（含任务/同步/资源）。
func rtSources(rtDir string) []string {
	names := []string{
		"rt.c", "rt_gc.c", "rt_policy.c", "rt_weak.c", "xrt_abi.c",
		"rt_std_runtime.c", "rt_std_text.c", "rt_std_sys.c", "rt_std_bytes.c",
		"rt_task.c", "rt_sync.c", "rt_std_res.c", "rt_std_net.c",
	}
	out := make([]string, 0, len(names))
	for _, n := range names {
		out = append(out, rtDir+"/"+n)
	}
	return out
}
