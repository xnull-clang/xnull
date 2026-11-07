package sema

import (
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// BND-14：S2 禁止构造负例矩阵；每条至少 1 个带位置诊断，不崩溃/不静默。
func TestS2BND14NegativeMatrix(t *testing.T) {
	cases := []struct{ name, src string }{
		{"BND01 protected external", `class C { protected Int x = 1; }
static Int main() { C c = new C(); print(c.x); return 0 }`},
		{"BND02 new abstract", `abstract class A { Int x = 0; }
static Int main() { A a = new A(); return 0 }`},
		{"BND04 struct ref field", `struct S { String name; }
static Int main() { return 0 }`},
		{"BND05 protocol missing", `protocol P { void go(); }
class C implements P { }
static Int main() { return 0 }`},
		{"BND06 enum switch missing", `enum E { A, B }
static Int main() { E e = E.A; switch (e) { case E.A: print("a") } return 0 }`},
		{"BND07 new singleton", `singleton S { Int x = 1; }
static Int main() { S s = new S(); return 0 }`},
		{"BND08 factory invisible target", `factory F for Missing { static Int make() { return 0 } }
static Int main() { return 0 }`},
		{"BND09 private field external", `class C { private Int x = 0; }
static Int main() { C c = new C(); print(c.x); return 0 }`},
		{"BND10 internal policy anno", `@arc class C { Int x = 0; }
static Int main() { return 0 }`},
		{"BND12 static type param", `class Box<T> { static T value; }
static Int main() { return 0 }`},
		{"FIELD private underscore", `class C { private Int _x = 0; }
static Int main() { return 0 }`},
		{"INH final parent", `final class B { }
class D : B { }
static Int main() { return 0 }`},
		{"PROTO private method", `protocol P { private void go(); }
static Int main() { return 0 }`},
		{"STRUCT deinit", `struct S { void deinit() { } }
static Int main() { return 0 }`},
		{"ENUM data field non-final", `enum E { A(0); Int code; E(Int c) { self.code = c } }
static Int main() { return 0 }`},
		{"PCTOR non-final param", `class C(Int x) { }
static Int main() { return 0 }`},
		{"singleton manual instance", `singleton S { Int instance = 0; }
static Int main() { return 0 }`},
		{"factory self", `class D { Int x = 0; }
factory F for D { static D make() { return self.d } }
static Int main() { return 0 }`},
		{"enum immutable write", `enum S { A(0); final Int c; S(Int x) { self.c = x } }
static Int main() { S.A.c = 1; return 0 }`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			u, pd := xfront.ParseUnit("neg.x", c.src)
			var ds []struct {
				line, col int
			}
			for _, d := range pd {
				ds = append(ds, struct{ line, col int }{d.Line, d.Col})
			}
			if len(pd) == 0 {
				for _, d := range Analyze("neg.x", u) {
					ds = append(ds, struct{ line, col int }{d.Line, d.Col})
				}
			}
			if len(ds) == 0 {
				t.Fatalf("禁止构造被静默接受")
			}
			for _, d := range ds {
				if d.line <= 0 || d.col <= 0 {
					t.Fatalf("诊断位置非法：%d:%d", d.line, d.col)
				}
			}
		})
	}
}
