package frontbridge

import (
	"os"
	"path/filepath"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// TestParseUnitMatchesOracle 验证桥接入口在 go 模式与 auto 模式下都不改变 AST。
func TestParseUnitMatchesOracle(t *testing.T) {
	root := repoRoot(t)
	files := []string{
		filepath.Join(root, "examples", "hello.x"),
		filepath.Join(root, "examples", "classes.x"),
		filepath.Join(root, "tests", "b2", "parser_cases", "stmt.x"),
	}
	for _, mode := range []string{"go", "auto"} {
		t.Setenv("XNULL_FRONTEND", mode)
		t.Setenv("XNULL_SELFHOST_BIN", "")
		t.Setenv("XNULL_BIN", "")
		for _, path := range files {
			src, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			want, wd := xfront.ParseUnit(path, string(src))
			if len(wd) > 0 {
				t.Fatalf("%s: oracle 诊断非空", path)
			}
			got, gd := ParseUnit(path, string(src))
			if len(gd) > 0 {
				t.Fatalf("%s[%s]: 桥接诊断非空：%s", path, mode, gd[0].String())
			}
			if xfront.PrintUnitPos(got) != xfront.PrintUnitPos(want) {
				t.Fatalf("%s[%s]: AST 与 oracle 不一致", path, mode)
			}
		}
	}
}

// TestParseUnitDiagnosticsFromOracle 验证错误文件仍返回 oracle 的完整诊断。
func TestParseUnitDiagnosticsFromOracle(t *testing.T) {
	root := repoRoot(t)
	path := filepath.Join(root, "tests", "b2", "parser_neg", "chain_cmp.x")
	src, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	_, wd := xfront.ParseUnit(path, string(src))
	if len(wd) == 0 {
		t.Fatal("oracle 应有诊断")
	}
	_, gd := ParseUnit(path, string(src))
	if len(gd) != len(wd) {
		t.Fatalf("诊断数量不一致：got=%d want=%d", len(gd), len(wd))
	}
	for i := range gd {
		if gd[i].Code != wd[i].Code || gd[i].Line != wd[i].Line || gd[i].Col != wd[i].Col || gd[i].Message != wd[i].Message {
			t.Fatalf("诊断 %d 不一致：got=%+v want=%+v", i, gd[i], wd[i])
		}
	}
}
