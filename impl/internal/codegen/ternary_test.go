package codegen

import "testing"

// M4.1：三元表达式 `cond ? a : b`——String/Int/Bool 结果与分支调用。
func TestM41TernaryExpr(t *testing.T) {
	src := `
static String left() { return "L"; }
static String right() { return "R"; }
static String pick(Bool f) { return f ? "a" : "b"; }
static Int main() {
    Bool f = true;
    String s = f ? "yes" : "no";
    print(s);
    f = false;
    s = f ? "yes" : "no";
    print(s);
    print("v=" + (f ? left() : right()));
    print(pick(true));
    Int x = f ? 1 : 2;
    print(x);
    Bool b = f ? false : true;
    print(b);
    return 0;
}`
	got, code := compileAndRun(t, src)
	if want := "yes\nno\nv=R\na\n2\ntrue\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}
