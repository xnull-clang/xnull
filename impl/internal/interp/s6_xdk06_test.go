package interp

import (
	"strings"
	"sync"
	"testing"
)

// XDK-06：运行时 API 的解释器桥（nowMono/nowWall/env/diagnose/dumpTasks）。
func TestS6XDK06RuntimeBuiltins(t *testing.T) {
	src := `import xdk.runtime
static Int main() {
    Int a = nowMono()
    Int b = nowMono()
    print(a <= b)
    print(nowWall() > 0)
    String? e = env("XNULL_S6_ENV_MISSING")
    print(e == null)
    diagnose("line1\nline2")
    dumpTasks()
    return 0
}`
	out, code, err := runSrcCode(t, src)
	if err != nil || code != 0 {
		t.Fatalf("code=%d err=%v out=%q", code, err, out)
	}
	want := "true\ntrue\ntrue\nline1 line2\ntasks: live=0\n"
	if out != want {
		t.Fatalf("out=%q，期望 %q", out, want)
	}
}

// XDK-06：exit 立即终止、跳过 defer，退出码原样（S1 §10.3）。
func TestS6XDK06ExitSkipsDefer(t *testing.T) {
	src := `import xdk.runtime
static Int main() {
    defer print("defer-ran")
    print("before")
    exit(7)
    return 0
}`
	out, code, err := runSrcCode(t, src)
	if err != nil || code != 7 {
		t.Fatalf("code=%d err=%v out=%q，期望 7", code, err, out)
	}
	if strings.Contains(out, "defer-ran") {
		t.Fatalf("exit 后仍执行 defer：%q", out)
	}
	if out != "before\n" {
		t.Fatalf("out=%q，期望 before\\n", out)
	}
}

// XDK-06：env 缺失返回 null；存在值可读；两次读取一致（快照）。
func TestS6XDK06EnvSnapshot(t *testing.T) {
	envOnce = sync.Once{}
	envSnap = nil
	t.Setenv("XNULL_S6_ENV_SNAPSHOT", "v1")
	src := `import xdk.runtime
static Int main() {
    String? a = env("XNULL_S6_ENV_SNAPSHOT")
    String? b = env("XNULL_S6_ENV_SNAPSHOT")
    String? m = env("XNULL_S6_ENV_MISSING")
    print(a == b)
    print(a == "v1")
    print(m == null)
    return 0
}`
	out, code, err := runSrcCode(t, src)
	if err != nil || code != 0 || out != "true\ntrue\ntrue\n" {
		t.Fatalf("code=%d err=%v out=%q", code, err, out)
	}
}
