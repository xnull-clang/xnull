import xdk.sync
import xdk.tasks
@tasks
static Int main() {
    Mutex<Int> m = Mutex<Int>(3)
    AtomicInt a = AtomicInt(0)
    Channel<Int> ch = Channel<Int>(1)
    Result<void, TaskError> r = m.withLock((Int n) -> {
        Result<void, TaskError> rr = Ok()
        return rr
    })
    print(r.isOk())
    a.store(5)
    print(a.load())
    print(ch.send(2).isOk())
    return 0
}
