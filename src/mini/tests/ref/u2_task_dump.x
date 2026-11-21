// U2 diagnostic: show a live blocked task, cancel it, then show it settled.
import xdk.tasks
import xdk.runtime

static Int main() {
    Context context = Context.background()
    TaskGroup group = TaskGroup.create(context)
    Channel<Int> channel = new Channel<Int>(1)
    Task<Int> blocked = group.spawn(() -> {
        Result<Int, CancelledError> item = channel.receive()
        if item.isErr() {
            return Ok(1)
        }
        return Ok(0)
    })
    dumpTasks()
    group.cancel()
    Result<Int, TaskError> joined = blocked.join()
    print(joined.isOk())
    print(joined.value())
    dumpTasks()
    group.close()
    return 0
}
