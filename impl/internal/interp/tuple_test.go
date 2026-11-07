package interp

import "testing"

// T3/T6：元素访问、元素赋值、==/!=/===/!==、插值。
func TestTupleElementAssignmentAndEquality(t *testing.T) {
	out, err := runSrc(t, `
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
    print(x === y)
    print(x !== y)
    print($"v={x}")
    return 0
}`)
	want := "1\n9\ntrue\nfalse\ntrue\nfalse\nv=(1, x)\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// T4：var 推断元组；嵌套元组访问。
func TestTupleInferenceAndNested(t *testing.T) {
	out, err := runSrc(t, `
static Int main() {
    var inferred = (1, "a")
    print(inferred.0)
    print(inferred.1)

    ((Int, String), Bool) nested = ((2, "b"), true)
    (Int, String) inner = nested.0
    print(inner.0)
    print(inner.1)
    print(nested.1)
    return 0
}`)
	want := "1\na\n2\nb\ntrue\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// T3：可空元组 `?.N`；非 null 时返回元素。
func TestTupleNullSafeElement(t *testing.T) {
	out, err := runSrc(t, `
static Int main() {
    (Int, String) pair = (7, "a")
    print(pair?.0)
    return 0
}`)
	if err != nil || out != "7\n" {
		t.Fatalf("out=%q err=%v", out, err)
	}
}
