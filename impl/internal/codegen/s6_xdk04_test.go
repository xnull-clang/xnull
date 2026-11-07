package codegen

import (
	"strings"
	"testing"
)

// XDK-04：组是资源，close 是唯一合法终结路径（S5 §3.2）。
// 作用域退出时 release 未关闭的组 → group_deinit 合同诊断（进程级 fatal）。
func TestS6_XDK04GroupMustClose(t *testing.T) {
	src := `import xdk.tasks
@tasks
static Int main() {
    Context c = Context.background()
    TaskGroup g = TaskGroup.create(c)
    return 0
}`
	_, stderr, code := compileAndRunPolicyFull(t, src)
	if code == 0 {
		t.Fatalf("未 close 的任务组应触发合同诊断；stderr=%q", stderr)
	}
	if !strings.Contains(stderr, "任务组在未关闭时释放") {
		t.Fatalf("缺少组必关诊断：%q", stderr)
	}
}

// 正例：显式 close 后作用域退出，不得触发诊断。
func TestS6_XDK04GroupCloseOK(t *testing.T) {
	src := `import xdk.tasks
@tasks
static Int main() {
    Context c = Context.background()
    TaskGroup g = TaskGroup.create(c)
    Result<void, TaskError> r = g.close()
    return 0
}`
	_, stderr, code := compileAndRunPolicyFull(t, src)
	if code != 0 {
		t.Fatalf("已 close 的组不应 fatal：code=%d stderr=%q", code, stderr)
	}
}
