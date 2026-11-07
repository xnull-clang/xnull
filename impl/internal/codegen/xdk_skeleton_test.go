package codegen

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// S6-08：8 个 xdk 源码单元骨架 + 命名 + 依赖矩阵（机械核验）。
func TestXdkPackageSkeletons(t *testing.T) {
	dir, err := filepath.Abs(filepath.Join("..", "..", "lib", "xdk"))
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"errors", "tasks", "sync", "runtime", "collections", "text", "sys", "net"}
	allowed := map[string][]string{
		"errors": {"runtime"}, // S6-06：report 经 xdk.runtime.diagnose
		"text":   {"errors"},  // S6-05：text 的错误面复用 xdk.errors（ErrorKind/CauseError）
	}
	for _, name := range want {
		path := filepath.Join(dir, name+".x")
		src, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("缺少包骨架 %s：%v", path, err)
		}
		text := string(src)
		if !strings.Contains(text, "xdk."+name) {
			t.Fatalf("%s.x 缺少包名标注 xdk.%s", name, name)
		}
		u, diags := xfront.ParseUnit(path, text)
		if len(diags) > 0 {
			t.Fatalf("%s.x 解析诊断：%v", name, diags)
		}
		var deps []string
		for _, imp := range u.Imports {
			if len(imp.Path) < 2 || imp.Path[0] != "xdk" {
				continue
			}
			deps = append(deps, imp.Path[1])
		}
		okSet := map[string]bool{}
		for _, d := range allowed[name] {
			okSet[d] = true
		}
		for _, d := range deps {
			if !okSet[d] {
				t.Fatalf("%s.x 依赖 xdk.%s 不在依赖矩阵允许集（%v）", name, d, allowed[name])
			}
		}
	}
}

// S6-08：按 import 装载 xdk 源码单元（LoadUnits），依赖先、入口后。
func TestXdkLoaderByImport(t *testing.T) {
	dir := t.TempDir()
	mainPath := filepath.Join(dir, "main.x")
	src := "import xdk.errors\n\nstatic Int main() {\n    return 0\n}\n"
	if err := os.WriteFile(mainPath, []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	u, diags := LoadUnits(mainPath)
	if len(diags) > 0 {
		t.Fatalf("装载诊断：%v", diags)
	}
	foundEnum, foundProtocol, foundReport := false, false, false
	for _, d := range u.Decls {
		switch n := d.(type) {
		case *xfront.EnumDecl:
			foundEnum = foundEnum || n.Name == "ErrorKind"
		case *xfront.ProtocolDecl:
			foundProtocol = foundProtocol || n.Name == "Error"
		case *xfront.TopFunc:
			foundReport = foundReport || n.Name == "report"
		}
	}
	if !foundEnum || !foundProtocol || !foundReport {
		t.Fatalf("未装载 xdk.errors 声明：enum=%v proto=%v report=%v", foundEnum, foundProtocol, foundReport)
	}
}
