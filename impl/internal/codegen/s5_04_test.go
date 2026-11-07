package codegen

import (
	"strings"
	"testing"
)

// S5-04：跨任务内存——任务 env GC 根/scan、任务结果根、挂起点安全点。
func TestS5_04TaskSpawnJoin(t *testing.T) {
	src := `import xdk.tasks
@tasks
static Int main() {
    Context c = Context.background()
    TaskGroup g = TaskGroup.create(c)
    Result<Int, TaskError> seed = Ok(41)
    Task<Int> t = g.spawn(() -> { return seed })
    Result<Int, TaskError> r = t.join()
    print(r.unwrapOr(0))
    Result<void, TaskError> cr = g.close()
    print(cr.isOk())
    return 0
}`
	csrc := emitWithPolicy(t, src)
	for _, want := range []string{
		"xrt_context_background()",
		"xrt_task_group_new(",
		"xrt_task_group_spawn(",
		"xn_task_env",
		"xrt_task_join(",
		"xrt_task_group_close(",
		"xrt_safepoint();",
	} {
		if !strings.Contains(csrc, want) {
			t.Fatalf("缺少任务发射产物 %q：\n%s", want, csrc)
		}
	}
	got, code := compileAndRunPolicy(t, src)
	if want := "41\ntrue\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}

// S5-04：捕获对象进入 env refs 并由 scan 访问；任务持有期间保持可达。
func TestS5_04TaskEnvScan(t *testing.T) {
	src := `import xdk.tasks
class N { N? next; Int x = 7; }
static Result<N, TaskError> passN(N n) { return Ok(n) }
@tasks
static Int main() {
    Context c = Context.background()
    TaskGroup g = TaskGroup.create(c)
    N n = new N()
    Task<N> t = g.spawn(() -> { return passN(n) })
    Result<N, TaskError> r = t.join()
    if (r.isOk()) {
        N got = r.value()
        print(got.x)
    } else {
        print(-1)
    }
    Result<void, TaskError> cr = g.close()
    print(cr.isOk())
    return 0
}`
	csrc := emitWithPolicy(t, src)
	if !strings.Contains(csrc, "xn_task_env_scan") || !strings.Contains(csrc, "visit(") {
		t.Fatalf("任务 env 缺 scan：\n%s", csrc)
	}
	if !strings.Contains(csrc, "xrt_task_root_bind(") || !strings.Contains(csrc, "xrt_task_root_unbind(") {
		t.Fatalf("任务持有 GC 结果对象未登记/注销任务根：\n%s", csrc)
	}
	got, code := compileAndRunPolicy(t, src)
	if want := "7\ntrue\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}
