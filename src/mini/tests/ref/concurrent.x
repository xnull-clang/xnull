// Reference concurrency program: 10k tasks, bounded channel backpressure,
// Mutex-protected state, cancellation.
import xdk.tasks
import xdk.sync

class Counter {
    Int value

    Counter(Int value) {
        self.value = value
    }
}

static Int main() {
    Context context = Context.background()
    TaskGroup group = TaskGroup.create(context)
    Channel<Int> results = new Channel<Int>(16)
    Counter counter = new Counter(0)
    Mutex<Counter> mutex = Mutex(counter)

    Int spawned = 0
    while spawned < 10000 {
        group.spawn(() -> {
            Result<void, TaskError> locked = mutex.withLock((Counter state) -> {
                state.value = state.value + 1
            })
            if locked.isErr() {
                return Ok(0)
            }
            Result<void, CancelledError> sent = results.send(1)
            if sent.isErr() {
                return Ok(0)
            }
            return Ok(1)
        })
        spawned = spawned + 1
    }

    Int received = 0
    Int sum = 0
    while received < 10000 {
        Result<Int, CancelledError> item = results.receive()
        if item.isErr() {
            print("receive-error")
            return 1
        }
        sum = sum + item.value()
        received = received + 1
    }
    print(received)
    print(sum)
    print(counter.value)

    Channel<Int> empty = new Channel<Int>(1)
    Task<Int> blocked = group.spawn(() -> {
        Result<Int, CancelledError> item = empty.receive()
        if item.isErr() {
            return Ok(99)
        }
        return Ok(item.value())
    })
    group.cancel()
    Result<Int, TaskError> joined = blocked.join()
    print(joined.isOk())
    print(joined.value())
    Result<void, TaskError> closed = group.close()
    print(closed.isOk())
    return 0
}
