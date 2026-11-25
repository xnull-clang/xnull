package app.genericlambda2
import xdk.errors
import xdk.sync

class Reader {
    Result<Int, Error> withRead(Context context, void(Int) body) {
        body(11)
        return Ok(0)
    }
}

class Lock<T> {
    T _value
    Lock(T value) { self._value = value }
    Result<Unit, Error> withRead(Context context, void(T) body) {
        body(self._value)
        return Ok()
    }
    Result<Unit, Error> withWrite(Context context, void(T) body) {
        body(self._value)
        return Ok()
    }
}

class Runner {
    Result<Task<T>, Error> submit<T>(Context context, Result<T, Error>(Context) body) {
        TaskGroup group = TaskGroup.create(context)
        return Ok(group.spawn((Context taskContext) -> {
            Result<T, Error> result = body(taskContext)
            return Ok(result.value())
        }))
    }
}

class PromiseLike<T> {
    T? _value
    Bool _done
    PromiseLike() { self._done = false }
    Bool complete(T value) {
        self._value = value
        self._done = true
        return true
    }
    Bool isDone() { return self._done }
    T? value() { return self._value }
    FutureLike<T> future() { return new FutureLike<T>(self) }
}

class FutureLike<T> {
    final PromiseLike<T> _promise
    FutureLike(PromiseLike<T> promise) { self._promise = promise }
    Bool isDone() { return self._promise.isDone() }
    T? get() { return self._promise.value() }
}

static Int main() {
    Context context = Context.background()

    Reader reader = new Reader()
    AtomicInt seen = AtomicInt(-1)
    Result<Int, Error> read = reader.withRead(context, (Int value) -> { seen.store(value) })
    print("read=" + str(read.isOk()) + "," + str(seen.load()))

    Lock<Int> lock = new Lock<Int>(7)
    AtomicInt genericRead = AtomicInt(-1)
    lock.withRead(context, (Int value) -> { genericRead.store(value) })
    print("generic-read=" + str(genericRead.load()))

    Lock<Int> writeLock = new Lock<Int>(8)
    AtomicInt genericWrite = AtomicInt(-1)
    writeLock.withWrite(context, (Int value) -> { genericWrite.store(value) })
    print("generic-write=" + str(genericWrite.load()))

    Runner runner = new Runner()
    Result<Task<Int>, Error> submitted = runner.submit<Int>(context, (Context taskContext) -> {
        return Ok(21)
    })
    Result<Int, TaskError> joined = submitted.value().join()
    print("submit=" + str(submitted.isOk()) + "," + str(joined.value()))

    PromiseLike<Int> promise = new PromiseLike<Int>()
    FutureLike<Int> future = promise.future()
    Bool before = future.isDone()
    promise.complete(42)
    print("future=" + str(before) + "," + str(future.isDone()) + "," + str(future.get()))
    return 0
}
