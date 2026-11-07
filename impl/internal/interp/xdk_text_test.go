package interp

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/codegen"
)

// S6-05：装载 xdk.text 源码单元并解释执行 Format/parse/Regex。
func TestXdkTextRuntime(t *testing.T) {
	dir := t.TempDir()
	mainPath := filepath.Join(dir, "main.x")
	src := `import xdk.text

static Int main() {
    Result<Int, Error> a = parseInt("42")
    print(a.value())
    Result<Int, Error> bad = parseInt("x")
    print(bad.isErr())
    Result<Double, Error> d = parseFloat("1.5")
    print(d.value())
    Result<Int, Error> ov = parseInt("999999999999999999999999")
    print(ov.isErr())
    String s = Format.int(7).width(4).pad('0').build()
    print(s)
    String b = Format.bool(true).build()
    print(b)
    Result<Regex, Error> re = Regex.compile("a+")
    print(re.value().isMatch("aaa"))
    print(re.value().isMatch("b"))
    Result<Regex, Error> rb = Regex.compile("*")
    print(rb.isErr())
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
	want := "42\ntrue\n1.5\ntrue\n0007\ntrue\ntrue\nfalse\ntrue\n"
	if err != nil || code != 0 || out.String() != want {
		t.Fatalf("out=%q want=%q code=%d err=%v", out.String(), want, code, err)
	}
}
