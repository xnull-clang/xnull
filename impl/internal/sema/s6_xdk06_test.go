package sema

import "testing"

// XDK-06 QA 回归：dumpTasks 必须可调用（S6-02 runtime 面已实现）。
func TestXDK06DumpTasksSignature(t *testing.T) {
	expectNone(t, `import xdk.runtime
static Int main() {
    dumpTasks()
    return 0
}`)

	expectCode(t, `import xdk.runtime
static Int main() { dumpTasks(1); return 0 }`, TyAssignability)
}

// XDK-06 QA 回归：collections 源码单元的方法（RingBuffer.isFull/isEmpty 等）
// 必须按类方法签名解析，不能再落到 XDK 未支持的 TY-229。
func TestXDK06CollectionsMethods(t *testing.T) {
	expectNone(t, `import xdk.collections

class RingBuffer<T> {
    List<T> data = []
    Int length() { return self.data.length() }
    Bool isEmpty() { return self.data.length() == 0 }
    Bool isFull() { return false }
    Bool push(T v) { self.data.push(v); return true }
    T? pop() { return null }
    void clear() { self.data.clear() }
}

static Int main() {
    RingBuffer<Int> r = new RingBuffer<Int>()
    Bool e = r.isEmpty()
    Bool f = r.isFull()
    Int n = r.length()
    Bool p = r.push(1)
    Int? v = r.pop()
    r.clear()
    return n
}`)

	// 未登记成员仍须显式诊断。
	expectCode(t, `import xdk.collections
static Int f(RingBuffer<Int> r) { r.nope(); return 0 }`, TyXdkUnsupported)
}
