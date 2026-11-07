package interp

import (
	"strings"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// ===== 独立验收（CEO3-QA1）TUPLE-01 / S1 §2.11 =====
// 不复用实现者 tuple_test.go 的用例与期望值。

func qaRun(t *testing.T, src string) (string, int, error) {
	t.Helper()
	u, pd := xfront.ParseUnit("qa.x", src)
	if len(pd) != 0 {
		t.Fatalf("解析诊断（用例应为可解析输入）：%v", pd)
	}
	var out strings.Builder
	code, err := Run(u, &out, nil)
	return out.String(), code, err
}

func qaExpect(t *testing.T, src, want string) {
	t.Helper()
	got, code, err := qaRun(t, src)
	if err != nil || code != 0 || got != want {
		t.Fatalf("out=%q want=%q code=%d err=%v", got, want, code, err)
	}
}

// 相等/不等/同一性/插值（值元素）。
func TestQATupleValueEqualityAndInterp(t *testing.T) {
	qaExpect(t, `static Int main() {
    (Int, String) a = (1, "x")
    (Int, String) b = (1, "x")
    (Int, String) c = (1, "y")
    print(a == b)
    print(a != b)
    print(a == c)
    print(a != c)
    print(a === b)
    print(a !== b)
    print($"a={a}")
    ((Int, String), Bool) n = ((1, "x"), true)
    print($"n={n}")
    return 0
}`, "true\nfalse\nfalse\ntrue\ntrue\nfalse\na=(1, x)\nn=((1, x), true)\n")
}

// 相等/同一性（引用元素）：== 按元素类型相等语义（Object 为身份），=== 按同一性。
func TestQATupleReferenceElementEquality(t *testing.T) {
	qaExpect(t, `class Box { Int v = 0; }
static Int main() {
    Box o = new Box()
    Box p = new Box()
    (Box, Int) a = (o, 1)
    (Box, Int) b = (o, 1)
    (Box, Int) c = (p, 1)
    print(o == o)
    print(a == a)
    print(a == b)
    print(a === b)
    print(a == c)
    print(a === c)
    return 0
}`, "true\ntrue\ntrue\ntrue\nfalse\nfalse\n")
}

// 值语义：赋值、传参复制整个元组，副本与原值独立。
func TestQATupleCopySemantics(t *testing.T) {
	qaExpect(t, `static Int mutate((Int, Int) p) {
    p.0 = 99
    return p.0
}
static Int main() {
    (Int, Int) a = (1, 2)
    (Int, Int) b = a
    b.0 = 9
    print(a.0)
    print(b.0)
    print(mutate(a))
    print(a.0)
    ((Int, Int), Bool) n = ((3, 4), true)
    (Int, Int) inner = n.0
    inner.0 = 7
    (Int, Int) orig = n.0
    print(orig.0)
    return 0
}`, "1\n9\n99\n1\n3\n")
}

// 推断运行：var 得元组类型，元素可读。
func TestQATupleInferenceRuntime(t *testing.T) {
	qaExpect(t, `static Int main() {
    var a = (1, "x")
    print(a.0)
    print(a.1)
    var b = (true, 3.0)
    print(b.0)
    return 0
}`, "1\nx\ntrue\n")
}

// 元素访问：.0/.1、嵌套链式、?.N（非空接收者）。
func TestQATupleElementAccessRuntime(t *testing.T) {
	qaExpect(t, `static Int main() {
    (Int, String) p = (7, "a")
    print(p.0)
    print(p.1)
    print(p?.0)
    ((Int, String), Bool) n = ((8, "b"), true)
    print((n.0).0)
    print((n.0).1)
    print(n.1)
    return 0
}`, "7\na\n7\n8\nb\ntrue\n")
}

// 越界兜底：即使绕过 sema，解释器也不得静默返回错误元素。
func TestQATupleOutOfRangeRuntimeFallback(t *testing.T) {
	u, pd := xfront.ParseUnit("qa.x", `static Int main() {
    (Int, String) p = (1, "a")
    print(p.5)
    return 0
}`)
	if len(pd) != 0 {
		t.Fatalf("解析不应失败：%v", pd)
	}
	var out strings.Builder
	code, err := Run(u, &out, nil)
	if code != 134 || err == nil || !strings.Contains(err.Error(), "越界") {
		t.Fatalf("期望 fatal 134 + 越界，实际 code=%d err=%v out=%q", code, err, out.String())
	}
}

// ===/!== 的 String 元素：§2.8 规定 String 的 === 按对象身份，不是内容。
func TestQATupleStringIdentity(t *testing.T) {
	qaExpect(t, `static Int main() {
    String s1 = "a" + "b"
    String s2 = "a" + "b"
    print(s1 === s2)
    (String, Int) p = (s1, 1)
    (String, Int) q = (s2, 1)
    print(p === q)
    print(p !== q)
    return 0
}`, "false\nfalse\ntrue\n")
}

// 引用元素（S1 数组，不依赖 S2 类）：同一数组句柄的元组 == 应为 true。
func TestQATupleArrayElementEquality(t *testing.T) {
	qaExpect(t, `static Int main() {
    Int[] arr = [1, 2]
    (Int[], Int) p = (arr, 1)
    (Int[], Int) q = (arr, 1)
    print(p == p)
    print(p == q)
    return 0
}`, "true\ntrue\n")
}
