import xdk.tasks
import xdk.sync

static Int main() {
    Context ctx = Context.background()
    TaskGroup g = TaskGroup.create(ctx)
    Channel<Int> ch = Channel(1)
    Task<Int> t = g.spawn(() -> {
        Result<Int,CancelledError> r = ch.receive()
        if r.isErr() {
            return Ok(21)
        }
        return Ok(r.value())
    })
    g.cancel()
    Result<Int,TaskError> j = t.join()
    print(j.isOk())
    print(j.value())
    print(g.close().isOk())

    Context ctx2 = Context.background()
    TaskGroup g2 = TaskGroup.create(ctx2)
    Channel<Int> ch2 = Channel(1)
    Task<Int> t2 = g2.spawn(() -> {
        Result<Int,CancelledError> r = ch2.receive()
        return Ok(33)
    })
    Long dl = nowMonoRaw() + 100
    Result<Int,TaskError> late = t2.joinDeadline(dl)
    print(late.isErr())
    g2.cancel()
    Result<Int,TaskError> j2 = t2.join()
    print(j2.isOk())
    print(j2.value())
    print(g2.close().isOk())
    return 0
}
