// runtime_xdk.go：xdk.runtime 解释器桥（S6 §4.4 / XDK-06）。
//
// 与编译路径共享同一组语义：
//   - diagnose：单行折叠（已在 interp.go 内联）；
//   - nowMono：单调毫秒（进程内基准，不减）；
//   - nowWall：UTC 毫秒（可回拨）；
//   - env：进程环境快照（首次使用时冻结；缺失 → null）；
//   - dumpTasks：单行 `tasks: live=N`（非承诺诊断）；
//   - exit：立即终止，跳过 defer，退出码原样（S1 §10.3）。
package interp

import (
	"fmt"
	"os"
	"strings"
	"sync"
	"time"

	"xnull.dev/xnull/internal/xfront"
)

// exitSignal 是 exit(code) 的进程级终止信号；由 RunWithDiag 捕获并原样返回退出码。
// execBlock 的默认分支不执行 defer，因此它天然跳过 defer/errdefer（S1 §10.3）。
type exitSignal struct{ code int }

var (
	monoBase = time.Now()

	envOnce sync.Once
	envSnap map[string]string
)

func interpEnvSnapshot() map[string]string {
	envOnce.Do(func() {
		envSnap = make(map[string]string)
		for _, kv := range os.Environ() {
			if i := strings.IndexByte(kv, '='); i > 0 {
				envSnap[kv[:i]] = kv[i+1:]
			}
		}
	})
	return envSnap
}

// evalRuntimeBuiltin 处理 xdk.runtime 的内置函数；未命中返回 ok=false。
func (in *Interp) evalRuntimeBuiltin(name string, n *xfront.Call, sc *scope) (*Value, bool) {
	switch name {
	case "nowMono":
		if len(n.Args) != 0 {
			panic(runtimeErr{"nowMono 不接受参数（S6 §4.4）"})
		}
		return &Value{K: vInt, I: time.Since(monoBase).Milliseconds()}, true
	case "nowWall":
		if len(n.Args) != 0 {
			panic(runtimeErr{"nowWall 不接受参数（S6 §4.4）"})
		}
		return &Value{K: vInt, I: time.Now().UnixMilli()}, true
	case "env":
		if len(n.Args) != 1 {
			panic(runtimeErr{"env 恰好接受 1 个参数（S6 §4.4）"})
		}
		v := in.eval(n.Args[0], sc)
		if v.K != vStr {
			panic(runtimeErr{"env 的参数必须是 String（S6 §4.4）"})
		}
		if s, ok := interpEnvSnapshot()[v.S]; ok {
			return &Value{K: vStr, S: s}, true
		}
		return &Value{K: vNull}, true
	case "dumpTasks":
		if len(n.Args) != 0 {
			panic(runtimeErr{"dumpTasks 不接受参数（S6 §4.4）"})
		}
		// 单行、无控制字符；解释器任务同步执行，live 在任务体内才非零。
		fmt.Fprintf(in.diag, "tasks: live=%d\n", in.liveTasks)
		return &Value{K: vNull}, true
	case "exit":
		if len(n.Args) != 1 {
			panic(runtimeErr{"exit 恰好接受 1 个参数（S6 §4.4）"})
		}
		v := in.eval(n.Args[0], sc)
		if v.K != vInt {
			panic(runtimeErr{"exit 的参数必须是 Int（S6 §4.4）"})
		}
		panic(exitSignal{code: int(v.I)})
	}
	return nil, false
}
