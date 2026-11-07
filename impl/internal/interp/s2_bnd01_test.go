package interp

import "testing"

// S2 §7.4 / BND-01：私有字段规范名 `_a` 在类内裸写可解析。
func TestS2PrivateCanonicalField(t *testing.T) {
	out, err := runSrc(t, `
class C {
    private Int a = 1;
    protected Int b = 2;
    public Int c = 3;

    private Int pa() { return _a }
    protected Int pb() { return b }
    public Int pc() { return c }

    Int all() { return _a + b + c + pa() + pb() + pc() }
}
static Int main() {
    C x = new C()
    print(x.all())
    print(x.pc())
    print(x.c)
    return 0
}`)
	want := "12\n3\n3\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// S2 §2.5/§7.3：子类访问继承的 protected 字段/方法。
func TestS2InheritedProtectedField(t *testing.T) {
	out, err := runSrc(t, `
class B {
    protected Int x = 7;
    protected Int f() { return x }
}
class D : B {
    Int g() { return self.x + self.f() }
}
static Int main() {
    D d = new D()
    print(d.g())
    return 0
}`)
	if err != nil || out != "14\n" {
		t.Fatalf("out=%q want=%q err=%v", out, "14\n", err)
	}
}
