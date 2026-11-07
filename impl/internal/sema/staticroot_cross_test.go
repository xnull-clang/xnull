package sema_test

import (
	"os"
	"path/filepath"
	"testing"

	"xnull.dev/xnull/internal/codegen"
	"xnull.dev/xnull/internal/sema"
)

// P1-10 跨模块：两个文件合并后根登记顺序与模块无关（按源码依赖顺序）。
func TestS3StaticRootsCrossModule(t *testing.T) {
	dir := t.TempDir()
	write := func(name, src string) {
		t.Helper()
		if err := os.WriteFile(filepath.Join(dir, name), []byte(src), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write("main.x", "import lib\nstatic Int main() { return 0 }\n")
	write("lib.x", "package lib\nsingleton S { static String s = \"x\"; }\n")
	u, ds := codegen.LoadUnits(filepath.Join(dir, "main.x"))
	if len(ds) != 0 {
		t.Fatalf("加载诊断：%v", ds)
	}
	res, sd := sema.AnalyzeWith(filepath.Join(dir, "main.x"), u)
	if len(sd) != 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
	roots := res.StaticRoots(u)
	found := false
	for _, r := range roots {
		if r.Decl == "S" && r.Field == "s" && r.Kind == "singleton.static" {
			found = true
		}
	}
	if !found {
		t.Fatalf("跨模块 root 未登记：%+v", roots)
	}
}
