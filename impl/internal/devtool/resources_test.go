package devtool

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// goldenTwoFiles 是迁移前 gen_resources.py 对「a.txt=hello、c.bin=bytes(0..19)」
// 的逐字节输出（Python 3.12.14 / LC_ALL=C 采集），作为 B-full 的固定对照。
const goldenTwoFiles = `/* 由 impl/tools/gen_resources.py 生成（构建期产物，勿手改；S8 §5.6）。
 * 资源表按名称升序；查找为二分；空表零成本。 */
#include <stddef.h>
#include <string.h>

typedef struct {
    const char         *name;
    const unsigned char *data;
    size_t              len;
} xrt_resource;

static const xrt_resource g_xrt_resources[] = {
    /* a.txt（5 字节） */
    {
        .name = "a.txt",
        .data = (const unsigned char[]){
    0x68, 0x65, 0x6C, 0x6C, 0x6F,
        },
        .len = 5,
    },
    /* c.bin（20 字节） */
    {
        .name = "c.bin",
        .data = (const unsigned char[]){
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
    0x10, 0x11, 0x12, 0x13,
        },
        .len = 20,
    },
};

size_t xrt_resource_count(void) {
    return sizeof(g_xrt_resources) / sizeof(g_xrt_resources[0]);
}

int xrt_resource_get(const char *name, size_t nlen,
                     const unsigned char **out, size_t *out_len) {
    size_t lo = 0, hi = xrt_resource_count();
    while (lo < hi) {
        size_t mid = lo + (hi - lo) / 2;
        const xrt_resource *r = &g_xrt_resources[mid];
        size_t min_len = nlen < strlen(r->name) ? nlen : strlen(r->name);
        int cmp = memcmp(name, r->name, min_len);
        if (cmp == 0) {
            if (nlen == strlen(r->name)) {
                *out = r->data; *out_len = r->len; return 0;
            }
            cmp = nlen < strlen(r->name) ? -1 : 1;
        }
        if (cmp < 0) { hi = mid; } else { lo = mid + 1; }
    }
    return 1; /* 未找到：显式区分，不静默给空 */
}
`

const goldenEmpty = `/* 由 impl/tools/gen_resources.py 生成（构建期产物，勿手改；S8 §5.6）。
 * 资源表按名称升序；查找为二分；空表零成本。 */
#include <stddef.h>
#include <string.h>

typedef struct {
    const char         *name;
    const unsigned char *data;
    size_t              len;
} xrt_resource;

/* 空表：无资源的工程零成本 */
size_t xrt_resource_count(void) { return 0; }

int xrt_resource_get(const char *name, size_t nlen,
                     const unsigned char **out, size_t *out_len) {
    (void)name; (void)nlen;
    *out = 0; *out_len = 0;
    return 1;
}
`

func writeFile(t *testing.T, path string, data []byte) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
}

func generate(t *testing.T, src string) string {
	t.Helper()
	out := filepath.Join(t.TempDir(), "res_table.c")
	if err := GenerateResources(src, out); err != nil {
		t.Fatalf("生成失败：%v", err)
	}
	data, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestGenerateResourcesMatchesPythonGolden(t *testing.T) {
	src := t.TempDir()
	// 故意按乱序写入，验证按名排序。
	writeFile(t, filepath.Join(src, "c.bin"), func() []byte {
		b := make([]byte, 20)
		for i := range b {
			b[i] = byte(i)
		}
		return b
	}())
	writeFile(t, filepath.Join(src, "a.txt"), []byte("hello"))

	if got := generate(t, src); got != goldenTwoFiles {
		t.Fatalf("与 Python golden 不一致：\n--- got ---\n%s\n--- want ---\n%s", got, goldenTwoFiles)
	}
}

func TestGenerateResourcesEmptyMatchesPythonGolden(t *testing.T) {
	if got := generate(t, t.TempDir()); got != goldenEmpty {
		t.Fatalf("空表与 Python golden 不一致：\n%s", got)
	}
}

// 迁移期必须复现旧实现的「拒绝子目录」行为；放开子目录属 S0-25。
func TestGenerateResourcesRejectsSubdirectory(t *testing.T) {
	src := t.TempDir()
	writeFile(t, filepath.Join(src, "sub", "x.txt"), []byte("x"))
	err := GenerateResources(src, filepath.Join(t.TempDir(), "res.c"))
	if err == nil || !strings.Contains(err.Error(), "资源名非法（限 [A-Za-z0-9_.-]）：sub/x.txt") {
		t.Fatalf("子目录应被拒绝且点名相对路径，实际：%v", err)
	}
}

func TestGenerateResourcesRejectsInvalidName(t *testing.T) {
	src := t.TempDir()
	writeFile(t, filepath.Join(src, "bad name.txt"), []byte("x"))
	err := GenerateResources(src, filepath.Join(t.TempDir(), "res.c"))
	if err == nil || !strings.Contains(err.Error(), "资源名非法") {
		t.Fatalf("非法名应报错，实际：%v", err)
	}
}

func TestGenerateResourcesRejectsMissingDir(t *testing.T) {
	err := GenerateResources(filepath.Join(t.TempDir(), "nope"), filepath.Join(t.TempDir(), "res.c"))
	if err == nil || !strings.Contains(err.Error(), "资源目录不存在") {
		t.Fatalf("目录不存在应报错，实际：%v", err)
	}
}

func TestGenerateResourcesDeterministic(t *testing.T) {
	src := t.TempDir()
	writeFile(t, filepath.Join(src, "b.txt"), []byte("b"))
	writeFile(t, filepath.Join(src, "a.txt"), []byte("a"))
	first := generate(t, src)
	for i := 0; i < 3; i++ {
		if got := generate(t, src); got != first {
			t.Fatalf("第 %d 次生成结果不一致", i+2)
		}
	}
}
