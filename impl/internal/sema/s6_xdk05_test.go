package sema

import "testing"

// XDK-05：同步原语的构造与端到端语言面（sema 部分）。
// 运行时/解释器/编译路径的缺口由 E3/E4/E5 接；本卡先保证源码可类型检查。

func TestXDK05SyncConstructors(t *testing.T) {
	expectNone(t, `import xdk.sync
import xdk.tasks
import xdk.errors
@tasks
static Int main() {
    Mutex<Int> m = Mutex<Int>(0)
    Result<void, TaskError> locked = m.withLock((Int x) -> {
        Result<void, TaskError> ok = Ok()
        return ok
    })
    Channel<Int> ch = Channel<Int>(1)
    Result<void, CancelledError> sent = ch.send(7)
    Result<Int, CancelledError> got = ch.receive()
    ch.close()
    AtomicInt a = AtomicInt(0)
    a.store(5)
    Bool cas = a.compareExchange(5, 6)
    Int n = a.load()
    AtomicBool b = AtomicBool(false)
    b.store(true)
    Bool t = b.load()
    return n
}`)

	expectCode(t, `import xdk.sync
struct S { Int x = 0; }
static Int main() { Mutex<S> m = Mutex<S>(new S()); return 0 }`, TySyncRule)

	expectCode(t, `import xdk.sync
static Int main() { AtomicRef<Int> a = AtomicRef<Int>(0); return 0 }`, TySyncRule)

	expectCode(t, `import xdk.sync
static Int main() { Channel<Int> ch = Channel<Int>("x"); return 0 }`, TyAssignability)

	expectCode(t, `import xdk.sync
static Int main() { AtomicInt a = AtomicInt(true); return 0 }`, TyAssignability)
}
