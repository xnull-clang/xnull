package interp

import "testing"

// S2 §9：singleton 自动 instance、字段/方法可读、main 前完成初始化。
func TestS2SingletonRuntime(t *testing.T) {
	t.Run("InstanceFields", func(t *testing.T) {
		out, err := runSrc(t, `
singleton AppInfo {
    final String name = "XNull";
    Int count = 3;
    Int next() { return count + 1 }
}
static Int main() {
    print(AppInfo.instance.name)
    print(AppInfo.instance.count)
    print(AppInfo.instance.next())
    return 0
}`)
		want := "XNull\n3\n4\n"
		if err != nil || out != want {
			t.Fatalf("out=%q want=%q err=%v", out, want, err)
		}
	})
	t.Run("StartupBeforeMain", func(t *testing.T) {
		out, err := runSrc(t, `
singleton Config {
    Int port = 8080;
    String host = "localhost";
}
static Int main() {
    print(Config.instance.host)
    print(Config.instance.port)
    return 0
}`)
		want := "localhost\n8080\n"
		if err != nil || out != want {
			t.Fatalf("out=%q want=%q err=%v", out, want, err)
		}
	})
	t.Run("InitOrderAndPrevSingleton", func(t *testing.T) {
		out, err := runSrc(t, `
Int top = 5
singleton A {
    Int base = top + 1;
}
singleton B {
    Int v = A.instance.base + 10;
}
static Int main() {
    print(A.instance.base)
    print(B.instance.v)
    return 0
}`)
		want := "6\n16\n"
		if err != nil || out != want {
			t.Fatalf("out=%q want=%q err=%v", out, want, err)
		}
	})
}
