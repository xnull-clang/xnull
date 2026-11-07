package sema

import "testing"

// S5-03：Mutex/Channel/Atomic 静态约束。
func TestS5SyncTypeRules(t *testing.T) {
	expectCode(t, `import xdk.sync
struct S { Int x = 0; }
static Int main() {
    Mutex<S> m
    return 0
}`, TySyncRule)

	expectCode(t, `import xdk.sync
static Int main() {
    AtomicRef<Int> a
    return 0
}`, TySyncRule)

	expectNone(t, `import xdk.sync
import xdk.tasks
class C { Int x = 0; }
@tasks
static Int f(Mutex<C> m, AtomicRef<C> a, Channel<Int> ch) {
    C x = new C()
    Result<void, TaskError> lr = m.withLock((C c) -> {
        Result<Int, TaskError> r = Ok(c.x)
        return r
    })
    a.store(x)
    a.compareExchange(x, x)
    Result<void, CancelledError> sr = ch.send(1)
    return 0
}`)
}

func TestS5ChannelAndMutexFlow(t *testing.T) {
	expectCode(t, `import xdk.sync
@tasks
static Int f(Channel<Int> ch) {
    ch.close()
    ch.send(1)
    return 0
}`, TySyncRule)

	expectCode(t, `import xdk.sync
@tasks
static Int f(Channel<Int> ch) {
    ch.send("x")
    return 0
}`, TyAssignability)

	expectCode(t, `import xdk.sync
class C { Int x = 0; }
@tasks
static Int f(Mutex<C> m) {
    m.withLock((C c) -> {
        m.withLock((C d) -> { return Ok(d.x) })
        return Ok(c.x)
    })
    return 0
}`, TySyncRule)

	expectCode(t, `import xdk.sync
@tasks
static Int f(AtomicInt a) {
    a.store("x")
    return 0
}`, TyAssignability)
}
