package codegen

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// M6-B0-07c：FFI handle 的 P-09 注入与绑定可见性（open 返回句柄、close 幂等）。
func TestFFIHandleOpenClose(t *testing.T) {
	dir := t.TempDir()
	// 使用真实 xdk.sys 绑定：验证 handle 类型注入与 fileClose 可见性。
	sysSrc, err := os.ReadFile(filepath.Join("..", "..", "..", "bindings", "xdk", "sys.xfb"))
	if err != nil {
		t.Skipf("缺少 bindings/xdk/sys.xfb：%v", err)
	}
	writeFFIFile(t, filepath.Join(dir, "bindings", "xdk", "sys.xfb"), string(sysSrc))
	data := filepath.Join(dir, "in.txt")
	writeFFIFile(t, data, "hello\n")

	src := `static Int main() {
    File f = fileOpenRead("` + data + `")
    fileClose(f)
    print("closed")
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
	csrc, err := EmitCWithFFI(u, reg)
	if err != nil {
		t.Fatalf("EmitCWithFFI: %v", err)
	}
	for _, sym := range []string{"xn_ffi_fileOpenRead(", "xn_ffi_fileClose(", "xrt_handle *"} {
		if !strings.Contains(csrc, sym) {
			t.Fatalf("生成代码缺少 %q", sym)
		}
	}

	rt := filepath.Join("..", "..", "..", "impl", "runtime")
	bin := filepath.Join(dir, "prog")
	var stderr bytes.Buffer
	if code := Build(mainPath, bin, rt, &stderr); code != 0 {
		t.Fatalf("编译失败：code=%d\n%s", code, stderr.String())
	}
	var got bytes.Buffer
	cmd := exec.Command(bin)
	cmd.Stdout = &got
	if err := cmd.Run(); err != nil {
		t.Fatalf("运行失败：%v", err)
	}
	// oracle：同程序去掉 FFI 调用，只打印同一行。
	if got.String() != "closed\n" {
		t.Fatalf("stdout=%q，期望 closed", got.String())
	}
}
