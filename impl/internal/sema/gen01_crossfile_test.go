package sema_test

import (
	"os"
	"path/filepath"
	"testing"

	"xnull.dev/xnull/internal/codegen"
	"xnull.dev/xnull/internal/sema"
)

// GEN-01 G16：跨文件泛型模板可见性（sema 对 LoadUnits 合并后的同一编译单元无文件边界）。
func TestGEN01CrossFileTemplateVisible(t *testing.T) {
	dir := t.TempDir()
	write := func(name, src string) {
		t.Helper()
		if err := os.WriteFile(filepath.Join(dir, name), []byte(src), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write("main.x", `import lib
static Int main() {
    print(id<Int>(7))
    return 0
}`)
	write("lib.x", `static T id<T>(T v) { return v }`)

	u, diags := codegen.LoadUnits(filepath.Join(dir, "main.x"))
	if len(diags) != 0 {
		t.Fatalf("加载诊断：%v", diags)
	}
	if sd := sema.Analyze(filepath.Join(dir, "main.x"), u); len(sd) != 0 {
		t.Fatalf("跨文件泛型不应有语义诊断：%v", sd)
	}
}
