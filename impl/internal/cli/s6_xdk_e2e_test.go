package cli

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/codegen"
	"xnull.dev/xnull/internal/exitcode"
)

const xdkE2EResC = `#include <stddef.h>
static const unsigned char res_a[] = { 65, 66 };
static const char *xn_res_names[] = { "a.txt" };
static const unsigned char *xn_res_data[] = { res_a };
static const size_t xn_res_len[] = { 2 };
size_t xrt_resource_count(void) { return 1; }
int xrt_resource_at(size_t i, const char **name, size_t *nlen,
                    const unsigned char **out, size_t *out_len) {
    if (i >= 1) { return 1; }
    *name = xn_res_names[i]; *nlen = 5; *out = xn_res_data[i]; *out_len = xn_res_len[i];
    return 0;
}
int xrt_resource_get(const char *name, size_t nlen, const unsigned char **out, size_t *out_len) {
    if (nlen != 5 || name[0] != 'a') { return 1; }
    *out = res_a; *out_len = 2;
    return 0;
}
`

const xdkE2ESrc = `import xdk.sys
import xdk.tasks
import xdk.errors
@tasks
static Int main() {
    Context c = Context.background()
    print(resourceExists("a.txt"))
    Int? sz = resourceSize("a.txt")
    if (sz != null) { print("size-ok") }
    Result<Bytes, Error> rb = readResource(c, "a.txt")
    if (rb.isOk()) { print("rb-ok") }
    Result<Text, Error> rt = readResourceText(c, "a.txt")
    if (rt.isOk()) { print("rt-ok") }
    Result<List<String>, Error> rl = listResources(c, "")
    if (rl.isOk()) { print("rl-ok") }
    return 0
}
`

func writeXdkProject(t *testing.T) (dir, mainPath, resC string) {
	t.Helper()
	dir = t.TempDir()
	sysSrc, err := os.ReadFile(filepath.Join("..", "..", "..", "bindings", "xdk", "sys.xfb"))
	if err != nil {
		t.Fatalf("读取 sys.xfb：%v", err)
	}
	if err := os.MkdirAll(filepath.Join(dir, "bindings", "xdk"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "bindings", "xdk", "sys.xfb"), sysSrc, 0o644); err != nil {
		t.Fatal(err)
	}
	mainPath = filepath.Join(dir, "main.x")
	if err := os.WriteFile(mainPath, []byte(xdkE2ESrc), 0o644); err != nil {
		t.Fatal(err)
	}
	resC = filepath.Join(dir, "res.c")
	if err := os.WriteFile(resC, []byte(xdkE2EResC), 0o644); err != nil {
		t.Fatal(err)
	}
	return dir, mainPath, resC
}

// S6 XDK-10：check 与 build 注入面一致；资源 5 API 端到端构建/运行。
func TestS6Xdk10CheckBuildRun(t *testing.T) {
	_, mainPath, resC := writeXdkProject(t)

	// check：资源 API 可见且签名被检查（合法程序通过）。
	if code, out, errOut := run("check", mainPath); code != exitcode.Success {
		t.Fatalf("check 合法程序退出码 %d stdout=%q stderr=%s", code, out, errOut)
	}
	// check：实参类型错误必须被拒（与 build 同口径）。
	badPath := filepath.Join(filepath.Dir(mainPath), "bad.x")
	bad := strings.Replace(xdkE2ESrc, `resourceExists("a.txt")`, `resourceExists(1)`, 1)
	if err := os.WriteFile(badPath, []byte(bad), 0o644); err != nil {
		t.Fatal(err)
	}
	if code, _, _ := run("check", badPath); code == exitcode.Success {
		t.Fatalf("check 未拒绝 resourceExists(1)（check/build 口径不一致）")
	}

	// build + run：真实资源表 + 5 API 运行。
	bin := filepath.Join(filepath.Dir(mainPath), "prog")
	var stderr bytes.Buffer
	if code := codegen.BuildWithOptions(mainPath, bin, filepath.Join("..", "..", "runtime"), codegen.Options{ResC: resC}, &stderr); code != 0 {
		t.Fatalf("构建失败 code=%d\n%s", code, stderr.String())
	}
	var out bytes.Buffer
	cmd := exec.Command(bin)
	cmd.Stdout = &out
	if err := cmd.Run(); err != nil {
		t.Fatalf("运行失败：%v（stdout=%q）", err, out.String())
	}
	if want := "true\nsize-ok\nrb-ok\nrt-ok\nrl-ok\n"; out.String() != want {
		t.Fatalf("stdout=%q，期望 %q", out.String(), want)
	}
}
