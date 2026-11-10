package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// K-07：经 xnull run --interp 读取 ≥1 MiB 临时文件并输出长度。
func TestS8K07RunInterpReadFileText(t *testing.T) {
	dir := t.TempDir()
	data := filepath.Join(dir, "big.txt")
	payload := bytes.Repeat([]byte("b"), 1<<20)
	if err := os.WriteFile(data, payload, 0o644); err != nil {
		t.Fatal(err)
	}
	script := filepath.Join(dir, "main.x")
	src := `import xdk.sys
static Int main() {
    String s = readFileText("` + data + `")
    print(s.length())
    return 0
}`
	if err := os.WriteFile(script, []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	code, out, errOut := run("run", "--interp", script)
	if code != 0 {
		t.Fatalf("code=%d stderr=%q", code, errOut)
	}
	if out != "1048576\n" {
		t.Fatalf("stdout=%q，期望 1048576", out)
	}
}

// K-07：解释路径缺失文件错误必须显式。
func TestS8K07RunInterpReadFileTextMissing(t *testing.T) {
	dir := t.TempDir()
	missing := filepath.Join(dir, "missing.txt")
	script := filepath.Join(dir, "main.x")
	src := `import xdk.sys
static Int main() {
    String s = readFileText("` + missing + `")
    print(s.length())
    return 0
}`
	if err := os.WriteFile(script, []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	code, _, errOut := run("run", "--interp", script)
	if code == 0 {
		t.Fatalf("缺失文件应失败")
	}
	if !strings.Contains(errOut, "readFileText") || !strings.Contains(errOut, missing) {
		t.Fatalf("stderr 未点名 readFileText/path：%q", errOut)
	}
}
