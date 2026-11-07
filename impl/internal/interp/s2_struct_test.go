package interp

import "testing"

// S2 §3：struct 值语义——构造、字段、方法、赋值复制独立。
func TestS2StructValueSemantics(t *testing.T) {
	t.Run("CopyIndependence", func(t *testing.T) {
		out, err := runSrc(t, `
struct Point {
    Int x = 0;
    Int y = 0;
    Int sum() { return self.x + self.y }
}
static Int main() {
    Point a = new Point()
    a.x = 1
    a.y = 2
    Point b = a
    b.x = 10
    print(a.x)
    print(b.x)
    print(a.sum())
    print(b.sum())
    return 0
}`)
		want := "1\n10\n3\n12\n"
		if err != nil || out != want {
			t.Fatalf("out=%q want=%q err=%v", out, want, err)
		}
	})
	t.Run("NestedNullableFields", func(t *testing.T) {
		out, err := runSrc(t, `
struct Inner {
    Int v = 1;
}
struct Outer {
    Inner inner = new Inner();
    Int? opt = null;
}
static Int main() {
    Outer o = new Outer()
    print(o.inner.v)
    o.opt = 5
    print(o.opt)
    return 0
}`)
		want := "1\n5\n"
		if err != nil || out != want {
			t.Fatalf("out=%q want=%q err=%v", out, want, err)
		}
	})
	t.Run("NestedCopyIndependent", func(t *testing.T) {
		out, err := runSrc(t, `
struct Inner {
    Int v = 1;
}
struct Outer {
    Inner inner = new Inner();
}
static Int main() {
    Outer a = new Outer()
    Outer b = a
    b.inner.v = 9
    print(a.inner.v)
    print(b.inner.v)
    return 0
}`)
		want := "1\n9\n"
		if err != nil || out != want {
			t.Fatalf("out=%q want=%q err=%v", out, want, err)
		}
	})
}
