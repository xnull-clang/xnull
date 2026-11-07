package interp

import "testing"

// S2 §11：extension 给 class/struct/singleton/数据 enum 添加实例方法。
func TestS2ExtensionMethods(t *testing.T) {
	t.Run("Class", func(t *testing.T) {
		out, err := runSrc(t, `
class Device {
    String name;
    Device(String n) { self.name = n }
}
extension Device {
    String label() { return "L:" + self.name }
}
static Int main() {
    Device d = new Device("x")
    print(d.label())
    return 0
}`)
		if err != nil || out != "L:x\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "L:x\n", err)
		}
	})
	t.Run("Struct", func(t *testing.T) {
		out, err := runSrc(t, `
struct P { Int x; }
extension P {
    Int twice() { return self.x * 2 }
}
static Int main() {
    P p = new P()
    p.x = 3
    print(p.twice())
    return 0
}`)
		if err != nil || out != "6\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "6\n", err)
		}
	})
	t.Run("Singleton", func(t *testing.T) {
		out, err := runSrc(t, `
singleton S { Int n = 2; }
extension S {
    Int twice() { return self.n * 2 }
}
static Int main() {
    print(S.instance.twice())
    return 0
}`)
		if err != nil || out != "4\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "4\n", err)
		}
	})
	t.Run("DataEnum", func(t *testing.T) {
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
}
extension Status {
    Bool isReady() { return self.code == 0 }
}
static Int main() {
    print(Status.Ready.isReady())
    print(Status.Failed.isReady())
    return 0
}`)
		want := "true\nfalse\n"
		if err != nil || out != want {
			t.Fatalf("out=%q want=%q err=%v", out, want, err)
		}
	})
}
