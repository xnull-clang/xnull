package interp

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/codegen"
)

// S6-XDK08：解释器 Bytes/UTF-16 转换（text.x 源码单元同一份执行）。
func TestXdkTextUTF16Runtime(t *testing.T) {
	dir := t.TempDir()
	mainPath := filepath.Join(dir, "main.x")
	src := `import xdk.text

static Int main() {
    Bytes b = Bytes.fromString("Aé中😀")
    Result<List<UInt16>, Error> u = utf8ToUtf16(b)
    print(u.value().length())
    print(u.value().get(0))
    print(u.value().get(1))
    print(u.value().get(2))
    print(u.value().get(3))
    print(u.value().get(4))

    Result<Bytes, Error> back = utf16ToUtf8(u.value())
    print(back.value().length())
    print(back.value().get(0))
    print(back.value().get(1))
    print(back.value().get(9))

    Bytes inv = Bytes.fromString("")
    inv.push(255)
    print(utf8ToUtf16(inv).isErr())
    return 0
}
`
	if err := os.WriteFile(mainPath, []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	u, diags := codegen.LoadUnits(mainPath)
	if len(diags) > 0 {
		t.Fatalf("装载诊断：%v", diags)
	}
	var out strings.Builder
	code, err := Run(u, &out, nil)
	want := "5\n65\n233\n20013\n55357\n56832\n10\n65\n195\n128\ntrue\n"
	if err != nil || code != 0 || out.String() != want {
		t.Fatalf("out=%q want=%q code=%d err=%v", out.String(), want, code, err)
	}
}

// Bytes 基础方法：length/get/set/push/append/slice。
func TestS6BytesMethods(t *testing.T) {
	out, err := runSrc(t, `
static Int main() {
    Bytes x = Bytes.fromString("ab")
    print(x.length())
    x.set(0, 65)
    x.push(67)
    print(x.get(0))
    print(x.length())
    Bytes tail = x.slice(1, 3)
    print(tail.length())
    Bytes bang = Bytes.fromString("!")
    x.append(bang)
    print(x.length())
    return 0
}`)
	want := "2\n65\n3\n2\n4\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}
