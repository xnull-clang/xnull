package interp

// QA2 集成复核独立探针（TUPLE 运行时语义）。仅存在于 /tmp 导出副本。

import "testing"

func TestQA2TupleRuntimeProbe(t *testing.T) {
	out, err := runSrc(t, `
static Int main() {
    (Int, Int) a = (1, 2)
    (Int, Int) b = (1, 3)
    print(a == b)
    print(a != b)
    print(a === a)
    print(a === b)
    b.1 = 2
    print(a == b)
    (Int, String) x = (1, "x")
    (Int, String) y = (1, "x")
    print(x === y)
    return 0
}`)
	want := "false\ntrue\ntrue\nfalse\ntrue\ntrue\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}
