import xdk.sync
import xdk.tasks
import xdk.errors

@tasks
static Int main() {
    Mutex<Int> m = Mutex<Int>(0)
    Result<void, TaskError> locked = m.withLock((Int x) -> {
        print(x)
        Result<void, TaskError> ok = Ok()
        return ok
    })
    Channel<Int> ch = Channel<Int>(1)
    Result<void, CancelledError> sent = ch.send(7)
    Result<Int, CancelledError> got = ch.receive()
    print(got.value())
    ch.close()
    AtomicInt a = AtomicInt(0)
    a.store(5)
    Bool cas = a.compareExchange(5, 6)
    print(a.load())
    AtomicBool b = AtomicBool(false)
    b.store(true)
    print(b.load())
    return 0
}
