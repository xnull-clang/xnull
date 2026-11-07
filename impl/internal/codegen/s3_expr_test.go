package codegen

import "testing"

// S3-EXPR 1：成员表达式作类实例实参（take(h.v)）。
func TestS3_EXPRMemberArg(t *testing.T) {
	src := `class V { Int x = 1; }
class H { V v; }
static Int take(V v) { return v.x }
static Int main() {
    H h = new H()
    h.v = new V()
    h.v.x = 3
    print(take(h.v) + h.v.x)
    return 0
}`
	got, code := compileAndRunPolicy(t, src)
	if code != 0 || got != "6\n" {
		t.Fatalf("out=%q code=%d，期望 6", got, code)
	}
}

// S3-EXPR 2：调用结果作类成员接收者（xs.get(0).x）。
func TestS3_EXPRCallReceiver(t *testing.T) {
	src := `class V { Int x = 0; }
static Int main() {
    List<V> xs = []
    V a = new V()
    a.x = 5
    xs.push(a)
    print(xs.get(0).x)
    return 0
}`
	got, code := compileAndRunPolicy(t, src)
	if code != 0 || got != "5\n" {
		t.Fatalf("out=%q code=%d，期望 5", got, code)
	}
}

// S3-EXPR 3：调用结果参与 Int 算术（Map.get 的 V? → .v）。
func TestS3_EXPRMapGetArithmetic(t *testing.T) {
	src := `static Int main() {
    Map<String, Int> m = ["a": 1, "b": 2]
    Set<Int> s = [1, 2, 2, 3]
    print(m.get("a") + m.get("b") + s.length())
    return 0
}`
	got, code := compileAndRunPolicy(t, src)
	if code != 0 || got != "6\n" {
		t.Fatalf("out=%q code=%d，期望 6", got, code)
	}
}
