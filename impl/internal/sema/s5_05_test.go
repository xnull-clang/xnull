package sema

import "testing"

// S5-05：xdk.tasks 语言面签名 + @tasks 块约束。
func TestS5TasksSemaSurface(t *testing.T) {
	expectNone(t, `import xdk.tasks
@tasks
static Int main() {
    Context c = Context.background()
    CancelToken tok = c.token()
    TaskGroup g = TaskGroup.create(c)
    Result<Int,TaskError> r0 = Ok(1)
    Task<Int> t = g.spawn(() -> { return r0 })
    Result<Int,TaskError> r = t.join()
    Result<void,TaskError> cr = g.close()
    return 0
}`)

	expectCode(t, `import xdk.tasks
static Int main() {
    Context c = Context.background()
    return 0
}`, TyTasksBlock)

}

// xdk.sync 类型可见性（Mutex/Channel/Atomic）。
func TestS5SyncTypesVisible(t *testing.T) {
	expectNone(t, `import xdk.sync
static Int main() {
    Mutex<Int>? m = null
    Channel<Int>? ch = null
    AtomicInt? a = null
    return 0
}`)
}
