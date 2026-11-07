package codegen

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// S7-05：稳定 ABI v1 的生成侧顺序——main 首行先初始化运行时，再创建对象。
func TestS7_05RuntimeInitFirst(t *testing.T) {
	src := `static Int main() {
    print("ok")
    return 0
}`
	csrc := emitWithPolicy(t, src)
	mi := strings.Index(csrc, "int main(")
	if mi < 0 {
		t.Fatalf("生成代码缺少 main：\n%s", csrc)
	}
	body := csrc[mi:]
	initIdx := strings.Index(body, "xrt_runtime_init();")
	if initIdx < 0 {
		t.Fatalf("main 缺少 xrt_runtime_init()：\n%s", body)
	}
	for _, later := range []string{"xn_init_vtables();", "xn_init_enums();", "xn_init_globals();", "xn_init_singletons();", "xn_main();", "xn_main(xn_args);"} {
		if j := strings.Index(body, later); j >= 0 && j < initIdx {
			t.Fatalf("%s 出现在 xrt_runtime_init() 之前（S7 §6.3）", later)
		}
	}
	stdout, stderr, code := compileAndRunPolicyFull(t, src)
	if code != 0 || stdout != "ok\n" {
		t.Fatalf("code=%d stdout=%q stderr=%q", code, stdout, stderr)
	}
}

// S7-05：xrt.h 已从候选冻结转稳定 v1。
func TestS7_05HeaderStableV1(t *testing.T) {
	p := filepath.Join("..", "..", "runtime", "xrt.h")
	b, err := os.ReadFile(p)
	if err != nil {
		t.Fatalf("读取 %s：%v", p, err)
	}
	s := string(b)
	for _, want := range []string{"稳定 v1", "#define XRT_ABI_VERSION 1", "XRT_BINDINGS_LAYER"} {
		if !strings.Contains(s, want) {
			t.Fatalf("xrt.h 缺少 %q（S7-05）", want)
		}
	}
	if strings.Contains(s, "候选冻结") {
		t.Fatalf("xrt.h 仍保留“候选冻结”状态（S7-05）")
	}
}
