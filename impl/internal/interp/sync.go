// sync.go：解释器侧 xdk.sync 语义（S5 §7.1）：Mutex / Channel / Atomic*。
// 解释器为单载体确定性模型：Mutex.withLock 为作用域回调；Channel 不阻塞，
// 满/空时返回 Cancelled 错误面；Atomic 顺序一致语义按单线程执行。
package interp

import (
	"fmt"

	"xnull.dev/xnull/internal/xfront"
)

type mutexV struct {
	data   *Value
	locked bool
}

type channelV struct {
	cap    int
	q      []*Value
	closed bool
}

type atomicV struct {
	kind string // "int" / "bool" / "ref"
	i    int64
	b    bool
	ref  *Value
}

func isSyncTypeName(name string) bool {
	switch name {
	case "Mutex", "Channel", "AtomicInt", "AtomicBool", "AtomicRef":
		return true
	}
	return false
}

// makeSync 构造同步原语（`Mutex<T>(v)` / `Channel<T>(cap)` / `AtomicInt(v)` 等）。
func (in *Interp) makeSync(name string, args []*Value) *Value {
	switch name {
	case "Mutex":
		if len(args) != 1 {
			panic(runtimeErr{"Mutex<T>(data) 需要 1 个参数（S5 §7.1）"})
		}
		return &Value{K: vMutex, Mu: &mutexV{data: args[0]}}
	case "Channel":
		if len(args) != 1 || args[0].K != vInt || args[0].I <= 0 {
			panic(runtimeErr{"Channel<T>(capacity) 需要 1 个正 Int 参数（S5 §7.1）"})
		}
		return &Value{K: vChannel, Ch: &channelV{cap: int(args[0].I)}}
	case "AtomicInt":
		a := &atomicV{kind: "int"}
		if len(args) > 0 && args[0].K == vInt {
			a.i = args[0].I
		}
		return &Value{K: vAtomic, At: a}
	case "AtomicBool":
		a := &atomicV{kind: "bool"}
		if len(args) > 0 && args[0].K == vBool {
			a.b = args[0].B
		}
		return &Value{K: vAtomic, At: a}
	case "AtomicRef":
		a := &atomicV{kind: "ref"}
		if len(args) > 0 {
			a.ref = args[0]
		}
		return &Value{K: vAtomic, At: a}
	}
	panic(runtimeErr{"未知同步类型：" + name})
}

func (in *Interp) callMutexMethod(m *mutexV, name string, args []*Value, pos xfront.Pos) *Value {
	switch name {
	case "withLock":
		if len(args) != 1 || args[0].K != vClosure {
			panic(runtimeErr{"Mutex.withLock 需要 1 个闭包参数（S5 §7.1）"})
		}
		if m.locked {
			panic(runtimeErr{"Mutex 重入被拒绝（S5 §7.1）"})
		}
		m.locked = true
		defer func() { m.locked = false }()
		return in.callClosure(args[0].Clo, []*Value{m.data})
	}
	panic(runtimeErr{"Mutex 没有成员方法 " + name + "（S5 §7.1）"})
}

func (in *Interp) callChannelMethod(c *channelV, name string, args []*Value, pos xfront.Pos) *Value {
	switch name {
	case "send":
		if len(args) != 1 {
			panic(runtimeErr{"Channel.send 需要 1 个参数（S5 §7.1）"})
		}
		if c.closed || len(c.q) >= c.cap {
			return errValue(in.cancelledErr())
		}
		c.q = append(c.q, args[0])
		return okVoid()
	case "receive":
		if len(args) != 0 {
			panic(runtimeErr{"Channel.receive 不接受参数（S5 §7.1）"})
		}
		if len(c.q) > 0 {
			v := c.q[0]
			c.q = c.q[1:]
			return &Value{K: vResult, R: &resv{ok: true, v: v}}
		}
		return errValue(in.cancelledErr()) // 空/已关闭：确定性返回取消错误面
	case "close":
		if len(args) != 0 {
			panic(runtimeErr{"Channel.close 不接受参数（S5 §7.1）"})
		}
		c.closed = true
		c.q = nil
		return &Value{K: vNull}
	}
	panic(runtimeErr{"Channel 没有成员方法 " + name + "（S5 §7.1）"})
}

func (in *Interp) callAtomicMethod(a *atomicV, name string, args []*Value, pos xfront.Pos) *Value {
	switch name {
	case "load":
		if len(args) != 0 {
			panic(runtimeErr{"Atomic.load 不接受参数（S5 §7.1）"})
		}
		switch a.kind {
		case "int":
			return &Value{K: vInt, I: a.i}
		case "bool":
			return &Value{K: vBool, B: a.b}
		default:
			if a.ref == nil {
				return &Value{K: vNull}
			}
			return a.ref
		}
	case "store":
		if len(args) != 1 {
			panic(runtimeErr{"Atomic.store 需要 1 个参数（S5 §7.1）"})
		}
		switch a.kind {
		case "int":
			a.i = args[0].I
		case "bool":
			a.b = args[0].B
		default:
			a.ref = args[0]
		}
		return &Value{K: vNull}
	case "compareExchange":
		if len(args) != 2 {
			panic(runtimeErr{"Atomic.compareExchange 需要 2 个参数（S5 §7.1）"})
		}
		switch a.kind {
		case "int":
			if a.i == args[0].I {
				a.i = args[1].I
				return &Value{K: vBool, B: true}
			}
		case "bool":
			if a.b == args[0].B {
				a.b = args[1].B
				return &Value{K: vBool, B: true}
			}
		default:
			if identical(a.ref, args[0]) {
				a.ref = args[1]
				return &Value{K: vBool, B: true}
			}
		}
		return &Value{K: vBool, B: false}
	}
	panic(runtimeErr{fmt.Sprintf("Atomic 没有成员方法 %s（S5 §7.1）", name)})
}
