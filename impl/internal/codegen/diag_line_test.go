package codegen

import (
	"bytes"
	"path/filepath"
	"strings"
	"testing"
)

// DIAG-LINE：cc 诊断应经 #line 映射回 .x 行号（而非生成 C 文件）。
func TestDiagLineMapping(t *testing.T) {
	dir := t.TempDir()
	src := "static Int main() {\n    Int xn_t1 = 1\n    print(str(xn_t1 + 1))\n    return 0\n}\n"
	mainPath := filepath.Join(dir, "main.x")
	writeFFIFile(t, mainPath, src)
	var stderr bytes.Buffer
	code := BuildWithOptions(mainPath, filepath.Join(dir, "prog"),
		filepath.Join("..", "..", "runtime"), Options{}, &stderr)
	if code == 0 {
		t.Fatalf("该用例应触发 cc 诊断")
	}
	msg := stderr.String()
	if !strings.Contains(msg, "main.x:2") {
		t.Fatalf("cc 诊断未映射回 .x:2：\n%s", msg)
	}
	for _, line := range strings.Split(msg, "\n") {
		if strings.Contains(line, "error:") && strings.Contains(line, "prog.c:") {
			t.Fatalf("cc 错误仍指向生成 C：%s", line)
		}
	}
}
