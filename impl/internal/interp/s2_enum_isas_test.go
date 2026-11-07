package interp

import "testing"

// S2？§8：简单枚举值、格式化、==/!=、switch。
func TestS2EnumSimpleRuntime(t *testing.T) {
	out, err := runSrc(t, `
enum Color { Red, Green, Blue }
static Int main() {
    Color c = Color.Green
    print(c)
    print(c == Color.Green)
    print(c != Color.Red)
    switch c {
        case Color.Red: print("r")
        case Color.Green: print("g")
        case Color.Blue: print("b")
    }
    return 0
}`)
	want := "Green\ntrue\ntrue\ng\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// S2 §8.4：未知枚举项必须显式失败，不得静默接受。
func TestS2EnumUnknownItemRejected(t *testing.T) {
	_, code, err := runSrcCode(t, `
enum Color { Red, Green }
static Int main() { print(Color.Purple); return 0 }
`)
	if err == nil || code == 0 {
		t.Fatalf("未知项应显式失败：code=%d err=%v", code, err)
	}
}

// S2 §4/§5：类与协议的 is/as 运行时判定（含继承链）。
func TestS2ClassProtocolIsAs(t *testing.T) {
	out, err := runSrc(t, `
protocol Shape { Int area(); }
class Sq implements Shape { Int area() { return 1 } }
class Base { }
class Sub : Base { }
static Int main() {
    Sq s = new Sq()
    print(s is Shape)
    Sub b = new Sub()
    Base a = b
    print(a is Base)
    print(a is Sub)
    Sub? c = a as? Sub
    print(c != null)
    Any o = s
    print(o is Shape)
    return 0
}`)
	want := "true\ntrue\ntrue\ntrue\ntrue\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// as 失败路径：不相关类型 as? 返回 null，as 报 fatal。
func TestS2AsFailure(t *testing.T) {
	out, err := runSrc(t, `
class A { }
class B { }
static Int main() {
    A a = new A()
    B? b = a as? B
    print(b == null)
    return 0
}`)
	if err != nil || out != "true\n" {
		t.Fatalf("as? 失败应返回 null：out=%q err=%v", out, err)
	}
	_, code, err := runSrcCode(t, `
class A { }
class B { }
static Int main() { A a = new A(); B b = a as B; return 0 }
`)
	if err == nil || code != 134 {
		t.Fatalf("as 失败应 fatal（134）：code=%d err=%v", code, err)
	}
}

// S2 §8.3/§8.5：数据枚举项、字段、方法、身份与格式化。
func TestS2EnumDataRuntime(t *testing.T) {
	out, err := runSrc(t, `
enum Status {
    Ready(0, "ready"),
    Failed(1, "failed");

    final Int code;
    final String label;

    Status(Int code, String label) {
        self.code = code
        self.label = label
    }

    Int getCode() { return self.code }
}
static Int main() {
    print(Status.Ready.getCode())
    print(Status.Failed.label)
    print(Status.Ready)
    print(Status.Ready == Status.Ready)
    print(Status.Ready == Status.Failed)
    return 0
}`)
	want := "0\nfailed\nReady\ntrue\nfalse\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}
