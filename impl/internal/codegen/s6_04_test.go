package codegen

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/sema"
	"xnull.dev/xnull/internal/xfront"
)

// S6-04：资源读取 5 API 的声明注入与调用降级（Result/Bytes/Text/List 不经 .xfb）。
// 仅断言生成 C 形态；端到端链接待 E5 S6-04 runtime 合入 main。
func TestS6_04ResourceSurface(t *testing.T) {
	dir := t.TempDir()
	sysSrc, err := os.ReadFile(filepath.Join("..", "..", "..", "bindings", "xdk", "sys.xfb"))
	if err != nil {
		t.Fatalf("读取 sys.xfb：%v", err)
	}
	writeFFIFile(t, filepath.Join(dir, "bindings", "xdk", "sys.xfb"), string(sysSrc))
	src := `import xdk.sys
import xdk.tasks
import xdk.errors
@tasks
static Int main() {
    Context c = Context.background()
    print(resourceExists("res/a.txt"))
    Int? sz = resourceSize("res/a.txt")
    if (sz != null) {
        print("size-ok")
    }
    Result<Bytes, Error> rb = readResource(c, "res/a.txt")
    Result<Text, Error> rt = readResourceText(c, "res/a.txt")
    Result<List<String>, Error> rl = listResources(c, "res/")
    return 0
}`
	mainPath := filepath.Join(dir, "main.x")
	writeFFIFile(t, mainPath, src)
	reg, diags, err := LoadFFI(dir)
	if err != nil || len(diags) != 0 {
		t.Fatalf("LoadFFI: err=%v diags=%v", err, diags)
	}
	u, pdiags := xfront.ParseUnit(mainPath, src)
	if len(pdiags) != 0 {
		t.Fatalf("解析诊断：%v", pdiags)
	}
	if err := InjectFFI(u, reg); err != nil {
		t.Fatalf("InjectFFI: %v", err)
	}
	if err := InjectSys603(u); err != nil {
		t.Fatalf("InjectSys603: %v", err)
	}
	if err := InjectS604(u); err != nil {
		t.Fatalf("InjectS604: %v", err)
	}
	sema.RegisterExternalTypes(FFIHandleTypes(reg)...)
	sema.RegisterExternalTypes("Process")
	if sd := sema.Analyze(mainPath, u); len(sd) != 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
	csrc, err := EmitCWithFFI(u, reg)
	if err != nil {
		t.Fatalf("EmitCWithFFI: %v", err)
	}
	for _, want := range []string{
		"xdkc_resource_exists(",
		"xdkc_resource_size(",
		"xdkc_read_resource(",
		"xdkc_read_resource_text(",
		"xdkc_list_resources(",
		"xdkc_list_resources_free(",
		"xn_Result_Bytes_Error",
		"xn_Result_Text_Error",
		"xn_Result_List_Error",
	} {
		if !strings.Contains(csrc, want) {
			t.Fatalf("缺少 S6-04 发射 %q：\n%s", want, csrc)
		}
	}
}

const s604ResC = `#include <stddef.h>
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

// S6-04：资源 5 API 端到端（E5 runtime + 资源表）。
func TestS6_04ResourceEndToEnd(t *testing.T) {
	dir := t.TempDir()
	sysSrc, err := os.ReadFile(filepath.Join("..", "..", "..", "bindings", "xdk", "sys.xfb"))
	if err != nil {
		t.Fatalf("读取 sys.xfb：%v", err)
	}
	writeFFIFile(t, filepath.Join(dir, "bindings", "xdk", "sys.xfb"), string(sysSrc))
	resC := filepath.Join(dir, "res.c")
	writeFFIFile(t, resC, s604ResC)
	src := `import xdk.sys
import xdk.tasks
import xdk.errors
@tasks
static Int main() {
    Context c = Context.background()
    print(resourceExists("a.txt"))
    Int? sz = resourceSize("a.txt")
    if (sz != null) {
        print("size-ok")
    }
    Result<Bytes, Error> rb = readResource(c, "a.txt")
    if (rb.isOk()) {
        print("rb-ok")
    }
    return 0
}`
	mainPath := filepath.Join(dir, "main.x")
	writeFFIFile(t, mainPath, src)
	bin := filepath.Join(dir, "prog")
	var stderr bytes.Buffer
	if code := BuildWithOptions(mainPath, bin, filepath.Join("..", "..", "runtime"), Options{ResC: resC}, &stderr); code != 0 {
		t.Fatalf("构建失败 code=%d\n%s", code, stderr.String())
	}
	var out bytes.Buffer
	cmd := exec.Command(bin)
	cmd.Stdout = &out
	if err := cmd.Run(); err != nil {
		t.Fatalf("运行失败：%v（stdout=%q）", err, out.String())
	}
	if want := "true\nsize-ok\nrb-ok\n"; out.String() != want {
		t.Fatalf("stdout=%q，期望 %q", out.String(), want)
	}
}
