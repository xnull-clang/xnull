package cli

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// S6 XDK-08：Char + Format 链 + parseInt/parseFloat/UTF 编译路径端到端。
func TestS6XDK08CompiledE2E(t *testing.T) {
	src := `import xdk.text
static Int main() {
    Result<Int, Error> a = parseInt("42")
    if (a.isOk()) { print(a.value()) }
    Result<Double, Error> f = parseFloat("1.5")
    if (f.isOk()) { print(f.value()) }
    Bytes b = Bytes.fromString("A")
    Result<List<UInt16>, Error> u = utf8ToUtf16(b)
    print(u.isOk())
    if (u.isOk()) {
        Result<Bytes, Error> back = utf16ToUtf8(u.value())
        print(back.isOk())
    }
    print(Format.int(7).width(4).pad('0').build())
    return 0
}`
	dir := t.TempDir()
	path := filepath.Join(dir, "text.x")
	if err := os.WriteFile(path, []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	// check 与 build/run 同口径。
	if code, out, errOut := run("check", path); code != 0 {
		t.Fatalf("check 失败：code=%d out=%s stderr=%s", code, out, errOut)
	}
	code, out, errOut := run("run", path)
	want := "42\n1.5\ntrue\ntrue\n0007\n"
	if code != 0 {
		if strings.Contains(errOut, "未支持") || strings.Contains(errOut, "codegen") {
			t.Fatalf("XDK-08 编译路径仍阻塞：%s", strings.TrimSpace(errOut))
		}
		t.Fatalf("运行失败 code=%d stderr=%s", code, errOut)
	}
	if out != want {
		t.Fatalf("stdout=%q，期望 %q", out, want)
	}
}
