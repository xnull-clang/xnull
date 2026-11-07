package codegen

import (
	"strings"
	"testing"
)

// S6-02：xdk.runtime 六个签名的发射面 + env 可选值 + dumpTasks 单行诊断。
func TestS6_02RuntimeSurface(t *testing.T) {
	src := `import xdk.runtime
static Int main() {
    String? e = env("PATH")
    if (e != null) {
        print("env-ok")
    }
    String? missing = env("XN_S6_02_NO_SUCH_ENV")
    print(missing == null)
    print(nowMono() > 0)
    print(nowWall() > 0)
    diagnose("diag-line\nsecond")
    dumpTasks()
    return 0
}`
	csrc := emitWithPolicy(t, src)
	for _, want := range []string{
		"xdkc_env_get(", "xn_env_lookup(",
		"xdkc_now_mono_ms()", "xdkc_now_wall_ms()",
		"xdkc_diagnose(", "xdkc_dump_tasks()",
	} {
		if !strings.Contains(csrc, want) {
			t.Fatalf("缺少 S6-02 发射产物 %q：\n%s", want, csrc)
		}
	}
	stdout, stderr, code := compileAndRunPolicyFull(t, src)
	if code != 0 {
		t.Fatalf("code=%d stderr=%q", code, stderr)
	}
	if want := "env-ok\ntrue\ntrue\ntrue\n"; stdout != want {
		t.Fatalf("stdout=%q，期望 %q", stdout, want)
	}
	// diagnose 单行折叠 + dumpTasks 单行。
	if !strings.Contains(stderr, "diag-line second") {
		t.Fatalf("diagnose 未单行输出：%q", stderr)
	}
	if !strings.Contains(stderr, "tasks: live=0") {
		t.Fatalf("dumpTasks 未输出任务计数：%q", stderr)
	}
	for _, line := range strings.Split(strings.TrimSuffix(stderr, "\n"), "\n") {
		if strings.Count(line, "diag-line") > 0 && strings.Contains(line, "second") == false {
			t.Fatalf("diagnose 折行异常：%q", line)
		}
	}
}

// S6-02：exit 不执行 defer（进程级退出码原样；defer 路径不运行）。
func TestS6_02ExitSkipsDefer(t *testing.T) {
	src := `import xdk.runtime
static Int main() {
    defer print("defer-ran")
    print("before")
    exit(7)
    return 0
}`
	csrc := emitWithPolicy(t, src)
	if !strings.Contains(csrc, "xdkc_exit(") {
		t.Fatalf("exit 未发射 xdkc_exit：\n%s", csrc)
	}
	stdout, stderr, code := compileAndRunPolicyFull(t, src)
	if code != 7 {
		t.Fatalf("退出码 %d，期望 7（stderr=%s）", code, stderr)
	}
	if strings.Contains(stdout, "defer-ran") {
		t.Fatalf("exit 后仍执行 defer：stdout=%q", stdout)
	}
}

// S6-02：dumpTasks 反映生成侧任务计数（spawn/join 后归零）。
func TestS6_02DumpTasksCounts(t *testing.T) {
	src := `import xdk.runtime
import xdk.tasks
@tasks
static Int main() {
    Context c = Context.background()
    TaskGroup g = TaskGroup.create(c)
    Result<Int, TaskError> seed = Ok(1)
    Task<Int> t = g.spawn(() -> { return seed })
    dumpTasks()
    Result<Int, TaskError> r = t.join()
    print(r.unwrapOr(0))
    dumpTasks()
    Result<void, TaskError> cr = g.close()
    return 0
}`
	stdout, stderr, code := compileAndRunPolicyFull(t, src)
	if code != 0 {
		t.Fatalf("code=%d stderr=%q", code, stderr)
	}
	if stdout != "1\n" {
		t.Fatalf("stdout=%q，期望 1", stdout)
	}
	// 多载体下首个 dump 时任务可能已终结（live=0）；只要求来源为运行时计数，
	// 且 join/close 后归零是确定性的。
	if !strings.Contains(stderr, "tasks: live=") || !strings.Contains(stderr, "tasks: live=0") {
		t.Fatalf("dumpTasks 计数不符：%q", stderr)
	}
}
