package xdk.resilience
import xdk.errors
import xdk.runtime
import xdk.tasks
import xdk.time

class TimeoutTimer {
    final Context _timerContext
    final Context _child
    final Long _millis
    Bool _fired

    TimeoutTimer(Context timerContext, Context child, Long millis) {
        self._timerContext = timerContext
        self._child = child
        self._millis = millis
        self._fired = false
    }

    Bool fired() { return self._fired }

    Result<Int, TaskError> run() {
        Result<Unit, Error> slept = sleepContext(self._timerContext, durationOfMillis(self._millis))
        if slept.isErr() { return Ok(0) }
        if !self._child.isCancelled() {
            self._fired = true
            self._child.cancel()
        }
        return Ok(0)
    }
}

class Timeout {
    private Timeout() { }

    static Task<Int> _startTimer(TaskGroup group, TimeoutTimer timer) {
        return group.spawn(() -> {
            return timer.run()
        })
    }

    static Result<T, Error> execute<T>(Context parent, Long timeoutMillis,
                                       Result<T, Error>(Context) operation) {
        if parent == null { throw "Timeout.execute: null context" }
        if timeoutMillis <= 0 { return Err(resilienceError(ErrorKind.InvalidArgument, "timeout must be positive")) }
        if parent.isCancelled() { return Err(resilienceError(ErrorKind.Cancelled, "timeout cancelled")) }
        Context groupContext = Context.withCancel(parent)
        Context child = Context.withCancel(parent)
        TaskGroup group = TaskGroup.create(groupContext)
        TimeoutTimer timer = new TimeoutTimer(groupContext, child, timeoutMillis)
        Task<Int> timerTask = Timeout._startTimer(group, timer)
        Result<T, Error> result = operation(child)
        group.close()
        if parent.isCancelled() { return Err(resilienceError(ErrorKind.Cancelled, "timeout cancelled")) }
        if timer.fired() {
            return Err(resilienceError(ErrorKind.Timeout, "timeout"))
        }
        return result
    }
}
