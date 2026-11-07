// tasks.go：解释器侧 xdk.tasks 基础面（S5 §3）：Context / TaskGroup / Task。
// 解释器为单载体确定性执行：spawn 同步执行闭包并保存 Result；join 交付该 Result。
package interp

import (
	"fmt"
	"time"

	"xnull.dev/xnull/internal/xfront"
)

type ctxV struct {
	parent      *ctxV
	cancelled   bool
	deadline    int64
	hasDeadline bool
}

type taskGroupV struct {
	ctx       *ctxV
	tasks     []*taskV
	closed    bool
	cancelled bool
}

type taskV struct {
	ctx    *ctxV
	result *Value
	joined bool
}

func (c *ctxV) isCancelled() bool {
	for p := c; p != nil; p = p.parent {
		if p.cancelled {
			return true
		}
		if p.hasDeadline && time.Now().UnixMilli() > p.deadline {
			return true
		}
	}
	return false
}

func okVoid() *Value {
	return &Value{K: vResult, R: &resv{ok: true, v: &Value{K: vNull}}}
}

func errValue(e *Value) *Value {
	return &Value{K: vResult, R: &resv{ok: false, e: e}}
}

func (in *Interp) cancelledErr() *Value {
	if d, ok := in.enums["ErrorKind"]; ok {
		for i, it := range d.Items {
			if it.Name == "Cancelled" {
				return &Value{K: vEnum, E: "ErrorKind", S: "Cancelled", I: int64(i)}
			}
		}
	}
	return &Value{K: vStr, S: "Cancelled"}
}

// evalTasksStatic 处理 `Context.background()` / `TaskGroup.create(ctx)`。
func (in *Interp) evalTasksStatic(name string, n *xfront.Call, sc *scope) (*Value, bool) {
	switch name {
	case "Context":
		if len(n.Args) != 0 {
			panic(runtimeErr{"Context.background 不接受参数（S5 §3.3）"})
		}
		return &Value{K: vContext, Ctx: &ctxV{}}, true
	case "TaskGroup":
		if len(n.Args) != 1 {
			panic(runtimeErr{"TaskGroup.create(ctx) 恰好接受 1 个参数（S5 §3.2）"})
		}
		ctxv := in.eval(n.Args[0], sc)
		var c *ctxV
		if ctxv.K == vContext {
			c = ctxv.Ctx
		}
		return &Value{K: vTaskGroup, TG: &taskGroupV{ctx: c}}, true
	}
	return nil, false
}

func (in *Interp) callContextMethod(c *ctxV, name string, args []*Value, pos xfront.Pos) *Value {
	switch name {
	case "checkCancel":
		if len(args) != 0 {
			panic(runtimeErr{"Context.checkCancel() 不接受参数（S5 §3.3）"})
		}
		if c.isCancelled() {
			return errValue(in.cancelledErr())
		}
		return okVoid()
	case "cancel":
		if len(args) != 0 {
			panic(runtimeErr{"Context.cancel() 不接受参数（S5 §3.3）"})
		}
		c.cancelled = true
		return &Value{K: vNull}
	case "isCancelled":
		if len(args) != 0 {
			panic(runtimeErr{"Context.isCancelled() 不接受参数"})
		}
		return &Value{K: vBool, B: c.isCancelled()}
	case "withDeadline":
		if len(args) != 1 || args[0].K != vInt {
			panic(runtimeErr{"Context.withDeadline(Int) 需要 1 个 Int 参数（S5 §3.3）"})
		}
		return &Value{K: vContext, Ctx: &ctxV{parent: c, deadline: args[0].I, hasDeadline: true}}
	}
	panic(runtimeErr{"Context 没有成员方法 " + name + "（S5 §3.3）"})
}

func (in *Interp) callTaskGroupMethod(g *taskGroupV, name string, args []*Value, pos xfront.Pos) *Value {
	switch name {
	case "spawn":
		if g.closed {
			panic(fatal{"已关闭的任务组不能 spawn（S5 §3.2）"})
		}
		if len(args) != 1 || args[0].K != vClosure {
			panic(runtimeErr{"TaskGroup.spawn 需要 1 个任务闭包（S5 §3.2）"})
		}
		var res *Value
		if g.cancelled {
			res = errValue(in.cancelledErr())
		} else {
			res = in.callClosure(args[0].Clo, nil)
		}
		if !res.isResult() {
			panic(runtimeErr{"任务闭包必须返回 Result（S5 §3.4）"})
		}
		t := &taskV{ctx: g.ctx, result: res}
		g.tasks = append(g.tasks, t)
		return &Value{K: vTask, T: t}
	case "cancel":
		if len(args) != 0 {
			panic(runtimeErr{"TaskGroup.cancel() 不接受参数（S5 §3.2）"})
		}
		g.cancelled = true
		if g.ctx != nil {
			g.ctx.cancelled = true
		}
		return &Value{K: vNull}
	case "close":
		if len(args) != 0 {
			panic(runtimeErr{"TaskGroup.close() 不接受参数（S5 §3.2）"})
		}
		if g.closed {
			panic(fatal{"任务组重复 close（S5 §3.2）"})
		}
		g.closed = true
		// 同步执行模型下所有任务已终结；返回首个非取消类错误。
		for _, t := range g.tasks {
			if t.result.isResult() && !t.result.R.ok && !isCancelledValue(t.result.R.e) {
				return errValue(t.result.R.e)
			}
		}
		return okVoid()
	}
	panic(runtimeErr{"TaskGroup 没有成员方法 " + name + "（S5 §3.2）"})
}

func (in *Interp) callTaskMethod(t *taskV, name string, args []*Value, pos xfront.Pos) *Value {
	switch name {
	case "join", "joinDeadline":
		if len(args) > 1 {
			panic(runtimeErr{"Task.join/joinDeadline 参数过多（S5 §3.1）"})
		}
		if t.joined {
			panic(fatal{"Task.join 只能成功一次（S5 §3.1）"})
		}
		t.joined = true
		return t.result
	}
	panic(runtimeErr{"Task 没有成员方法 " + name + "（S5 §3.1）"})
}

func isCancelledValue(v *Value) bool {
	if v == nil {
		return false
	}
	if v.K == vEnum && v.E == "ErrorKind" && v.S == "Cancelled" {
		return true
	}
	if v.K == vStr && v.S == "Cancelled" {
		return true
	}
	return false
}

var _ = fmt.Sprintf
