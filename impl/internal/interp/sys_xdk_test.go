package interp

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// K-07：xdk.sys.readFileText 解释器桥；1 MiB 文件长度必须精确。
func TestS8K07ReadFileText(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "big.txt")
	payload := bytes.Repeat([]byte("a"), 1<<20)
	if err := os.WriteFile(path, payload, 0o644); err != nil {
		t.Fatal(err)
	}
	src := `import xdk.sys
static Int main() {
    String s = readFileText("` + path + `")
    print(s.length())
    return 0
}`
	out, code, err := runSrcCode(t, src)
	if err != nil || code != 0 {
		t.Fatalf("code=%d err=%v out=%q", code, err, out)
	}
	if out != "1048576\n" {
		t.Fatalf("out=%q，期望 1048576", out)
	}
}

// K-07：缺失文件必须给出明确错误，不得静默返回空串。
func TestS8K07ReadFileTextMissing(t *testing.T) {
	path := filepath.Join(t.TempDir(), "no-such-file.txt")
	src := `import xdk.sys
static Int main() {
    String s = readFileText("` + path + `")
    print(s.length())
    return 0
}`
	out, code, err := runSrcCode(t, src)
	if err == nil || code == 0 {
		t.Fatalf("缺失文件应失败：code=%d out=%q err=%v", code, out, err)
	}
	if !strings.Contains(err.Error(), "readFileText") || !strings.Contains(err.Error(), path) {
		t.Fatalf("错误未点名 readFileText/path：%v", err)
	}
}
