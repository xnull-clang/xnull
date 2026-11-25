// xdk.execution —— L1 运行时与执行（M17.1）
//
// 本文件实现 8 个类型：Semaphore / WaitGroup / Once / RwLock<T> /
// Pool<T> / Promise<T> / Future<T> / Executor。
// Task/TaskGroup/Context 由编译器运行时提供；Mutex/Channel/Atomic* 由
// xdk.sync 提供，这里不重复定义。
//
// 稳定性：preview。设计合同见 docs/design/core/execution/。
package xdk.execution
import xdk.errors
import xdk.runtime

// ---------- Semaphore ----------
class Semaphore {
    final Int _permits
    Int _available
    Bool _closed
    final RuntimeMonitor _monitor

    Semaphore(Int permits) {
        if permits < 0 { throw "Semaphore: negative permits" }
        self._permits = permits
        self._available = permits
        self._closed = false
        self._monitor = new RuntimeMonitor()
    }

    Result<Unit, Error> acquire(Context context) {
        if context == null { throw "Semaphore.acquire: null context" }
        self._monitor.enter()
        while true {
            if self._closed {
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.Unavailable, "semaphore acquire: closed"))
            }
            if context.isCancelled() {
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.Cancelled, "semaphore acquire: cancelled"))
            }
            if self._available > 0 {
                self._available = self._available - 1
                self._monitor.exit()
                return Ok()
            }
            Bool woken = self._monitor.waitContext(context)
            if !woken {
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.Cancelled, "semaphore acquire: cancelled"))
            }
        }
    }

    Bool tryAcquire() {
        self._monitor.enter()
        if self._closed {
            self._monitor.exit()
            return false
        }
        if self._available <= 0 {
            self._monitor.exit()
            return false
        }
        self._available = self._available - 1
        self._monitor.exit()
        return true
    }

    Bool release() {
        self._monitor.enter()
        if self._closed {
            self._monitor.exit()
            return false
        }
        if self._available >= self._permits {
            self._monitor.exit()
            return false
        }
        self._available = self._available + 1
        self._monitor.notifyAll()
        self._monitor.exit()
        return true
    }

    Int available() {
        self._monitor.enter()
        Int result = self._available
        self._monitor.exit()
        return result
    }

    Int permits() {
        return self._permits
    }

    Void close() {
        self._monitor.enter()
        if !self._closed {
            self._closed = true
            self._monitor.notifyAll()
        }
        self._monitor.exit()
    }

    Bool isClosed() {
        self._monitor.enter()
        Bool result = self._closed
        self._monitor.exit()
        return result
    }
}

// ---------- WaitGroup ----------
class WaitGroup {
    Int _count
    final RuntimeMonitor _monitor

    WaitGroup() {
        self._count = 0
        self._monitor = new RuntimeMonitor()
    }

    Void add(Int count) {
        if count < 0 { throw "WaitGroup.add: negative count" }
        if count == 0 { return }
        self._monitor.enter()
        self._count = self._count + count
        self._monitor.exit()
    }

    Void done() {
        self._monitor.enter()
        if self._count <= 0 {
            self._monitor.exit()
            throw "WaitGroup.done: counter is zero"
        }
        self._count = self._count - 1
        if self._count == 0 { self._monitor.notifyAll() }
        self._monitor.exit()
    }

    Result<Unit, Error> wait(Context context) {
        if context == null { throw "WaitGroup.wait: null context" }
        self._monitor.enter()
        while self._count > 0 {
            if context.isCancelled() {
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.Cancelled, "wait group: cancelled"))
            }
            Bool woken = self._monitor.waitContext(context)
            if !woken {
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.Cancelled, "wait group: cancelled"))
            }
        }
        self._monitor.exit()
        return Ok()
    }

    Int count() {
        self._monitor.enter()
        Int result = self._count
        self._monitor.exit()
        return result
    }
}

// ---------- Once ----------
// 合同方法名为 do，但 do 是语言关键字；实现为 run，语义一致。
class Once {
    Bool _done
    Bool _running
    final RuntimeMonitor _monitor

    Once() {
        self._done = false
        self._running = false
        self._monitor = new RuntimeMonitor()
    }

    Result<Unit, Error> run(Context context, void() body) {
        if context == null { throw "Once.run: null context" }
        self._monitor.enter()
        if self._done {
            self._monitor.exit()
            return Ok()
        }
        if context.isCancelled() {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.Cancelled, "once: cancelled before run"))
        }
        while self._running {
            if context.isCancelled() {
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.Cancelled, "once: cancelled while waiting"))
            }
            Bool woken = self._monitor.waitContext(context)
            if !woken {
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.Cancelled, "once: cancelled while waiting"))
            }
        }
        if self._done {
            self._monitor.exit()
            return Ok()
        }
        self._running = true
        self._monitor.exit()
        body()
        self._monitor.enter()
        self._running = false
        self._done = true
        self._monitor.notifyAll()
        self._monitor.exit()
        return Ok()
    }

    Bool isDone() {
        self._monitor.enter()
        Bool result = self._done
        self._monitor.exit()
        return result
    }
}

// ---------- RwLock<T> ----------
class RwLock<T> {
    final T _value
    Int _readers
    Bool _writer
    Int _waitingWriters
    Bool _closed
    final RuntimeMonitor _monitor

    RwLock(T value) {
        self._value = value
        self._readers = 0
        self._writer = false
        self._waitingWriters = 0
        self._closed = false
        self._monitor = new RuntimeMonitor()
    }

    Result<Unit, Error> withRead(Context context, void(T) body) {
        if context == null { throw "RwLock.withRead: null context" }
        self._monitor.enter()
        while true {
            if self._closed {
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.Unavailable, "rwlock read: closed"))
            }
            if context.isCancelled() {
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.Cancelled, "rwlock read: cancelled"))
            }
            if !self._writer && self._waitingWriters == 0 {
                self._readers = self._readers + 1
                self._monitor.exit()
                break
            }
            Bool woken = self._monitor.waitContext(context)
            if !woken {
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.Cancelled, "rwlock read: cancelled"))
            }
        }
        body(self._value)
        self.releaseRead()
        return Ok()
    }

    Result<Unit, Error> withWrite(Context context, void(T) body) {
        if context == null { throw "RwLock.withWrite: null context" }
        self._monitor.enter()
        self._waitingWriters = self._waitingWriters + 1
        while true {
            if self._closed {
                self._waitingWriters = self._waitingWriters - 1
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.Unavailable, "rwlock write: closed"))
            }
            if context.isCancelled() {
                self._waitingWriters = self._waitingWriters - 1
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.Cancelled, "rwlock write: cancelled"))
            }
            if !self._writer && self._readers == 0 {
                self._writer = true
                self._waitingWriters = self._waitingWriters - 1
                self._monitor.exit()
                break
            }
            Bool woken = self._monitor.waitContext(context)
            if !woken {
                self._waitingWriters = self._waitingWriters - 1
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.Cancelled, "rwlock write: cancelled"))
            }
        }
        body(self._value)
        self.releaseWrite()
        return Ok()
    }

    Int readerCount() {
        self._monitor.enter()
        Int result = self._readers
        self._monitor.exit()
        return result
    }

    Bool isWriteLocked() {
        self._monitor.enter()
        Bool result = self._writer
        self._monitor.exit()
        return result
    }

    Int waitingWriters() {
        self._monitor.enter()
        Int result = self._waitingWriters
        self._monitor.exit()
        return result
    }

    Void close() {
        self._monitor.enter()
        if !self._closed {
            self._closed = true
            self._monitor.notifyAll()
        }
        self._monitor.exit()
    }

    Bool isClosed() {
        self._monitor.enter()
        Bool result = self._closed
        self._monitor.exit()
        return result
    }

    private Void releaseRead() {
        self._monitor.enter()
        self._readers = self._readers - 1
        self._monitor.notifyAll()
        self._monitor.exit()
    }

    private Void releaseWrite() {
        self._monitor.enter()
        self._writer = false
        self._monitor.notifyAll()
        self._monitor.exit()
    }
}

// ---------- Pool<T> ----------
class Pool<T> {
    final Int _capacity
    final List<T> _idle
    Int _inUse
    Int _creating
    Bool _closed
    final RuntimeMonitor _monitor
    final Result<T, Error> () _factory
    final void(T) _destroy

    Pool(Int capacity, Result<T, Error> () factoryFn, void(T) destroyFn) {
        if capacity <= 0 { throw "Pool: capacity must be positive" }
        self._capacity = capacity
        self._idle = []
        self._inUse = 0
        self._creating = 0
        self._closed = false
        self._monitor = new RuntimeMonitor()
        self._factory = factoryFn
        self._destroy = destroyFn
    }

    Result<T, Error> acquire(Context context) {
        if context == null { throw "Pool.acquire: null context" }
        self._monitor.enter()
        while true {
            if self._closed {
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.Unavailable, "pool acquire: closed"))
            }
            if context.isCancelled() {
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.Cancelled, "pool acquire: cancelled"))
            }
            if self._idle.length() > 0 {
                Int last = self._idle.length() - 1
                T value = self._idle.get(last)
                self._idle.remove(last)
                self._inUse = self._inUse + 1
                self._monitor.exit()
                return Ok(value)
            }
            if self._inUse + self._creating < self._capacity {
                self._creating = self._creating + 1
                self._monitor.exit()
                Result<T, Error> made = self._factory()
                if made.isErr() {
                    self._monitor.enter()
                    self._creating = self._creating - 1
                    self._monitor.notifyAll()
                    self._monitor.exit()
                    return Err(made.error())
                }
                self._monitor.enter()
                self._creating = self._creating - 1
                if self._closed {
                    self._monitor.notifyAll()
                    self._monitor.exit()
                    self._destroy(made.value())
                    return Err(new BasicError(ErrorKind.Unavailable, "pool acquire: closed"))
                }
                self._inUse = self._inUse + 1
                self._monitor.notifyAll()
                self._monitor.exit()
                return Ok(made.value())
            }
            Bool woken = self._monitor.waitContext(context)
            if !woken {
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.Cancelled, "pool acquire: cancelled"))
            }
        }
    }

    Bool release(T value) {
        self._monitor.enter()
        if self._inUse <= 0 {
            self._monitor.exit()
            return false
        }
        self._inUse = self._inUse - 1
        if self._closed {
            self._monitor.notifyAll()
            self._monitor.exit()
            self._destroy(value)
            return false
        }
        self._idle.push(value)
        self._monitor.notifyAll()
        self._monitor.exit()
        return true
    }

    Void close() {
        self._monitor.enter()
        if self._closed {
            self._monitor.exit()
            return
        }
        self._closed = true
        List<T> values = self._idle.copy()
        self._idle.clear()
        self._monitor.notifyAll()
        self._monitor.exit()
        Int index = 0
        while index < values.length() {
            self._destroy(values.get(index))
            index = index + 1
        }
    }

    Bool isClosed() {
        self._monitor.enter()
        Bool result = self._closed
        self._monitor.exit()
        return result
    }

    Int capacity() {
        return self._capacity
    }

    Int idleCount() {
        self._monitor.enter()
        Int result = self._idle.length()
        self._monitor.exit()
        return result
    }

    Int inUseCount() {
        self._monitor.enter()
        Int result = self._inUse
        self._monitor.exit()
        return result
    }
}

// ---------- Promise<T> ----------
class Promise<T> {
    Bool _done
    T? _value
    Error? _error
    final RuntimeMonitor _monitor

    Promise() {
        self._done = false
        self._monitor = new RuntimeMonitor()
    }

    Future<T> future() {
        return new Future<T>(self)
    }

    Bool complete(T value) {
        self._monitor.enter()
        if self._done {
            self._monitor.exit()
            return false
        }
        self._value = value
        self._done = true
        self._monitor.notifyAll()
        self._monitor.exit()
        return true
    }

    Bool fail(Error error) {
        if error == null { throw "Promise.fail: null error" }
        self._monitor.enter()
        if self._done {
            self._monitor.exit()
            return false
        }
        self._error = error
        self._done = true
        self._monitor.notifyAll()
        self._monitor.exit()
        return true
    }

    Bool cancel(String reason) {
        if reason == null { throw "Promise.cancel: null reason" }
        return self.fail(new BasicError(ErrorKind.Cancelled, reason))
    }

    Bool isDone() {
        self._monitor.enter()
        Bool result = self._done
        self._monitor.exit()
        return result
    }

    Bool isCancelled() {
        self._monitor.enter()
        Bool result = false
        if self._done && self._error != null {
            Error error = self._error as Error
            if error.kind() == ErrorKind.Cancelled { result = true }
        }
        self._monitor.exit()
        return result
    }

    Error? failure() {
        self._monitor.enter()
        Error? result = self._error
        self._monitor.exit()
        return result
    }

    Result<T, Error> await(Context context) {
        if context == null { throw "Promise.await: null context" }
        self._monitor.enter()
        while !self._done {
            if context.isCancelled() {
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.Cancelled, "promise await: cancelled"))
            }
            Bool woken = self._monitor.waitContext(context)
            if !woken {
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.Cancelled, "promise await: cancelled"))
            }
        }
        if self._error != null {
            Error error = self._error as Error
            self._monitor.exit()
            return Err(error)
        }
        self._monitor.exit()
        return Ok(self._value)
    }

    Result<T, Error> awaitDeadline(Context context, Long deadlineMonoMillis) {
        if context == null { throw "Promise.awaitDeadline: null context" }
        Context bounded = Context.withDeadline(context, deadlineMonoMillis)
        self._monitor.enter()
        while !self._done {
            if context.isCancelled() {
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.Cancelled, "promise await: cancelled"))
            }
            if bounded.isCancelled() {
                self._monitor.exit()
                return Err(new BasicError(ErrorKind.Timeout, "promise await: deadline exceeded"))
            }
            Bool woken = self._monitor.waitContext(bounded)
            if !woken {
                Bool outerCancelled = context.isCancelled()
                self._monitor.exit()
                if outerCancelled {
                    return Err(new BasicError(ErrorKind.Cancelled, "promise await: cancelled"))
                }
                return Err(new BasicError(ErrorKind.Timeout, "promise await: deadline exceeded"))
            }
        }
        if self._error != null {
            Error error = self._error as Error
            self._monitor.exit()
            return Err(error)
        }
        self._monitor.exit()
        return Ok(self._value)
    }
}

// ---------- Future<T> ----------
class Future<T> {
    final Promise<T> _promise

    Future(Promise<T> promise) {
        if promise == null { throw "Future: null promise" }
        self._promise = promise
    }

    Result<T, Error> get(Context context) {
        if context == null { throw "Future.get: null context" }
        return self._promise.await(context)
    }

    Result<T, Error> getDeadline(Context context, Long deadlineMonoMillis) {
        if context == null { throw "Future.getDeadline: null context" }
        return self._promise.awaitDeadline(context, deadlineMonoMillis)
    }

    Bool isDone() {
        return self._promise.isDone()
    }

    Bool isCancelled() {
        return self._promise.isCancelled()
    }
}

// ---------- Executor ----------
class Executor {
    final Context _context
    final TaskGroup _group
    final Semaphore _semaphore
    final Int _parallelism
    final AtomicBool _closed
    final RuntimeMonitor _monitor
    Bool _closeCalled

    Executor(Context parent, Int parallelism) {
        if parent == null { throw "Executor: null parent" }
        if parallelism <= 0 { throw "Executor: parallelism must be positive" }
        self._context = Context.withCancel(parent)
        self._group = TaskGroup.create(self._context)
        self._semaphore = new Semaphore(parallelism)
        self._parallelism = parallelism
        self._closed = AtomicBool(false)
        self._monitor = new RuntimeMonitor()
        self._closeCalled = false
    }

    static Executor fixed(Context parent, Int parallelism) {
        return new Executor(parent, parallelism)
    }

    static Executor single(Context parent) {
        return new Executor(parent, 1)
    }

    Result<Task<T>, Error> submit<T>(Context context, Result<T, Error>(Context) body) {
        if context == null { throw "Executor.submit: null context" }
        self._monitor.enter()
        if self._closed.load() {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "executor submit: closed"))
        }
        self._monitor.exit()
        Result<Unit, Error> permit = self._semaphore.acquire(context)
        if permit.isErr() { return Err(permit.error()) }
        self._monitor.enter()
        if self._closed.load() {
            self._monitor.exit()
            self._semaphore.release()
            return Err(new BasicError(ErrorKind.Unavailable, "executor submit: closed"))
        }
        Task<T> task = self._group.spawn((Context taskContext) -> {
            Result<T, Error> result = body(taskContext)
            self._semaphore.release()
            if result.isOk() {
                return Ok(result.value())
            }
            return Err(errorKindCode(result.error().kind()))
        })
        self._monitor.exit()
        return Ok(task)
    }

    Result<Unit, Error> close() {
        self._monitor.enter()
        if self._closeCalled {
            self._monitor.exit()
            return Ok()
        }
        self._closeCalled = true
        self._closed.store(true)
        self._monitor.exit()
        self._semaphore.close()
        Result<void, TaskError> closed = self._group.close()
        if closed.isOk() { return Ok() }
        ErrorKind kind = errorKindFromCode(closed.error() as Int)
        return Err(new BasicError(kind, "executor task failed"))
    }

    Bool isClosed() {
        return self._closed.load()
    }

    Int parallelism() {
        return self._parallelism
    }

    Int activeCount() {
        return self._parallelism - self._semaphore.available()
    }

    Int availablePermits() {
        return self._semaphore.available()
    }
}
