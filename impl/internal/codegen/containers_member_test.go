package codegen

import (
	"strings"
	"testing"
)

// M4.4a：容器字段作为值（valExpr 的 *xfront.Member 分支）——类字段。
// 覆盖：变量初始化、函数实参、for-in 源、Map 字段整值传递、keys()。
func TestM44aContainerMemberValueClass(t *testing.T) {
	src := `
import xdk.collections;
class Box {
    List<Int> xs = [];
    Map<String, Int> m = [];
    Int firstSelf() {
        List<Int> ys = self.xs;
        return ys.get(0);
    }
}
static Int total(List<Int> xs) {
    Int s = 0;
    for v in xs { s = s + v; }
    return s;
}
static Int main() {
    Box b = new Box();
    b.xs.push(1);
    b.xs.push(2);
    List<Int> ys = b.xs;
    ys.push(3);
    print(b.xs.length());
    print(b.firstSelf());
    print(total(b.xs));
    for v in b.xs { print(v); }
    b.m.put("a", 7);
    b.m.put("b", 8);
    Map<String, Int> m2 = b.m;
    print(m2.getOr("b", 0));
    List<String> ks = b.m.keys();
    print(ks.length());
    return 0;
}`
	got, code := compileAndRun(t, src)
	if want := "3\n1\n6\n1\n2\n3\n8\n2\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
	csrc := emitWithPolicy(t, src)
	if !strings.Contains(csrc, "xn_arr_i * ys = b->xs;") {
		t.Fatalf("容器成员未按字段引用生成：\n%s", csrc)
	}
}

// M4.4a：容器字段作为值——类字段链（o.h.xs）与 Map 字段。
// 注：struct 字段不允许容器（S2 §3.2 值字段限制，sema TY-204），字段链用类覆盖。
func TestM44aContainerMemberValueClassChain(t *testing.T) {
	src := `
import xdk.collections;
class Holder {
    List<Int> xs = [];
    Map<String, Int> m = [];
}
class Outer {
    Holder h = new Holder();
}
static Int first(List<Int> xs) { return xs.get(0); }
static Int main() {
    Outer o = new Outer();
    o.h.xs.push(4);
    o.h.xs.push(5);
    List<Int> xs = o.h.xs;
    print(xs.length());
    print(first(o.h.xs));
    o.h.m.put("k", 9);
    Map<String, Int> m = o.h.m;
    print(m.getOr("k", 0));
    return 0;
}`
	got, code := compileAndRun(t, src)
	if want := "2\n4\n9\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}
