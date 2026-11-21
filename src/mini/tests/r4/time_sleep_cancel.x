// R4 evidence: cancellable sleep returns promptly when its Context is cancelled.
import xdk.time
import xdk.errors

static Int main() {
    Context context = Context.background()
    TaskGroup group = TaskGroup.create(context)
    Task<Int> task = group.spawn(() -> {
        Result<Unit, Error> slept = sleepContext(context, durationOfMillis(5000))
        if slept.isErr() {
            return Ok(errorKindCode(slept.error().kind()))
        }
        return Ok(0)
    })
    sleepMs(30)
    group.cancel()
    Long joinStart = nowMs()
    Result<Int, TaskError> joined = task.join()
    Long joinElapsed = nowMs() - joinStart
    print(joined.isOk())
    print(joined.value() == 7)
    print(joinElapsed < 3000)
    print(group.close().isOk())
    return 0
}
