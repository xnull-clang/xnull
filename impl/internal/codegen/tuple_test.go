package codegen

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// TUPLE codegen（S1 §2.11）：类型/字面量/元素读写/嵌套/相等/插值/返回/参数/
// 顶层字段/类字段/整值复制。编译路径须与解释路径同输出。
func TestTupleCodegenRuns(t *testing.T) {
	src := `static (Int, Int) top = (11, 12)

class Holder {
    (Int, Int) p = (1, 2)
}

static (Int, Int) make(Int a, Int b) {
    return (a, b)
}

static (Int, String) greet() {
    return (1, "x")
}

static Int main() {
    (Int, Int) a = (1, 2)
    (Int, Int) b = a
    b.0 = 9
    print(a.0)
    print(b.0)

    (Int, String) x = (1, "x")
    (Int, String) y = (1, "x")
    print(x == y)
    print(x != y)
    print(x === x)
    print(x !== y)
    print($"v={x}")

    print(make(3, 4).1)
    print(greet().0)
    print(top.0)

    Holder h = new Holder()
    print(h.p.1)

    var inferred = (5, "z")
    print(inferred.1)

    ((Int, String), Bool) nested = ((2, "b"), true)
    (Int, String) inner = nested.0
    print(inner.0)
    print(nested.1)
    print(nested)

    (Int, Int) t = (1, 2)
    List<(Int, Int)> l = [t]
    t.0 = 9
    print(l.get(0).0)
    print(l.get(0).1)
    (Int, Int)[] arr = [(3, 4)]
    print(arr[0].1)
    return 0
}
`
	u, diags := xfront.ParseUnit("tuple.x", src)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	csrc, err := EmitC(u)
	if err != nil {
		t.Fatalf("EmitC: %v", err)
	}
	dir := t.TempDir()
	cf := filepath.Join(dir, "p.c")
	if err := os.WriteFile(cf, []byte(csrc), 0o644); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(dir, "p")
	rt := filepath.Join("..", "..", "..", "impl", "runtime")
	args := []string{"-std=c11", "-O2", "-I", rt, "-o", bin, cf}
	for _, s := range runtimeCSources {
		args = append(args, filepath.Join(rt, s))
	}
	cc := exec.Command("cc", args...)
	var cerr bytes.Buffer
	cc.Stderr = &cerr
	if err := cc.Run(); err != nil {
		t.Fatalf("cc 失败：%v\n%s\n---- C ----\n%s", err, cerr.String(), csrc)
	}
	var out bytes.Buffer
	run := exec.Command(bin)
	run.Stdout = &out
	if err := run.Run(); err != nil {
		t.Fatalf("运行失败：%v", err)
	}
	want := "1\n9\ntrue\nfalse\ntrue\ntrue\nv=(1, x)\n4\n1\n11\n2\nz\n2\ntrue\n((2, b), true)\n1\n2\n4\n"
	if got := out.String(); got != want {
		t.Fatalf("stdout=%q，期望 %q\n---- C ----\n%s", got, want, csrc)
	}
}
