package app.execution
import xdk.execution
import xdk.errors
import xdk.sync
import xdk.time

static Void atomicAdd(AtomicInt value, Int delta) {
    Bool done = false
    while !done {
        Int current = value.load()
        done = value.compareExchange(current, current + delta)
    }
}

static Void bumpMax(AtomicInt max, Int value) {
    Bool done = false
    while !done {
        Int current = max.load()
        if current >= value {
            done = true
        } else {
            done = max.compareExchange(current, value)
        }
    }
}

static TaskGroup newGroup(Context parent) {
    return TaskGroup.create(Context.withCancel(parent))
}

static Int main() {
    Context context = Context.background()

    // ---------- Semaphore ----------
    Semaphore semaphore = new Semaphore(2)
    print("sem=" + str(semaphore.permits()) + "," + str(semaphore.available()) + "," +
        str(semaphore.tryAcquire()) + "," + str(semaphore.tryAcquire()) + "," +
        str(semaphore.available()) + "," + str(semaphore.tryAcquire()) + "," +
        str(semaphore.release()) + "," + str(semaphore.available()))

    Context preCancelled = Context.background()
    preCancelled.cancel()
    Semaphore zeroSemaphore = new Semaphore(0)
    Result<Unit, Error> cancelledAcquire = zeroSemaphore.acquire(preCancelled)
    print("sem-cancel=" + errorKindName(cancelledAcquire.error().kind()))

    Semaphore closedSemaphore = new Semaphore(1)
    closedSemaphore.close()
    closedSemaphore.close()
    Result<Unit, Error> closedAcquire = closedSemaphore.acquire(context)
    print("sem-close=" + str(closedSemaphore.isClosed()) + "," +
        errorKindName(closedAcquire.error().kind()) + "," + str(closedSemaphore.release()))

    Semaphore gate = new Semaphore(1)
    gate.tryAcquire()
    AtomicInt gateWoke = AtomicInt(0)
    TaskGroup semGroup = newGroup(context)
    Task<Int> gateWaiter = semGroup.spawn((Context taskContext) -> {
        Result<Unit, Error> result = gate.acquire(taskContext)
        if result.isOk() { gateWoke.store(1) }
        return Ok(0)
    })
    sleepMs(20)
    print("sem-wait=" + str(gateWoke.load()))
    gate.release()
    Result<Int, TaskError> gateJoined = gateWaiter.join()
    print("sem-wake=" + str(gateWoke.load()) + "," + str(gateJoined.isOk()))

    Semaphore closingGate = new Semaphore(1)
    closingGate.tryAcquire()
    AtomicInt closeReason = AtomicInt(0)
    Task<Int> closeWaiter = semGroup.spawn((Context taskContext) -> {
        Result<Unit, Error> result = closingGate.acquire(taskContext)
        if result.isErr() && result.error().kind() == ErrorKind.Unavailable {
            closeReason.store(1)
        }
        return Ok(0)
    })
    sleepMs(20)
    closingGate.close()
    closeWaiter.join()
    print("sem-close-wake=" + str(closeReason.load()))
    semGroup.close()

    // ---------- WaitGroup ----------
    WaitGroup waitGroup = new WaitGroup()
    waitGroup.add(0)
    waitGroup.add(3)
    waitGroup.done()
    print("wg=" + str(waitGroup.count()))
    waitGroup.done()
    waitGroup.done()
    print("wg-zero=" + str(waitGroup.wait(context).isOk()) + "," + str(waitGroup.count()))

    WaitGroup held = new WaitGroup()
    held.add(1)
    Context cancelledWait = Context.background()
    cancelledWait.cancel()
    Result<Unit, Error> waitCancelled = held.wait(cancelledWait)
    print("wg-cancel=" + errorKindName(waitCancelled.error().kind()) + "," + str(held.count()))

    WaitGroup multi = new WaitGroup()
    multi.add(1)
    AtomicInt multiArrived = AtomicInt(0)
    TaskGroup multiGroup = newGroup(context)
    Task<Int> multiOne = multiGroup.spawn((Context taskContext) -> {
        if multi.wait(taskContext).isOk() { atomicAdd(multiArrived, 1) }
        return Ok(0)
    })
    Task<Int> multiTwo = multiGroup.spawn((Context taskContext) -> {
        if multi.wait(taskContext).isOk() { atomicAdd(multiArrived, 1) }
        return Ok(0)
    })
    sleepMs(20)
    print("wg-multi-waiting=" + str(multiArrived.load()))
    multi.done()
    multiOne.join()
    multiTwo.join()
    print("wg-multi-done=" + str(multiArrived.load()))
    multiGroup.close()

    // ---------- Once ----------
    Once once = new Once()
    AtomicInt onceCount = AtomicInt(0)
    TaskGroup onceGroup = newGroup(context)
    Task<Int> onceOne = onceGroup.spawn((Context taskContext) -> {
        once.run(taskContext, () -> {
            atomicAdd(onceCount, 1)
            sleepMs(20)
        })
        return Ok(0)
    })
    Task<Int> onceTwo = onceGroup.spawn((Context taskContext) -> {
        once.run(taskContext, () -> {
            atomicAdd(onceCount, 1)
            sleepMs(20)
        })
        return Ok(0)
    })
    Task<Int> onceThree = onceGroup.spawn((Context taskContext) -> {
        once.run(taskContext, () -> {
            atomicAdd(onceCount, 1)
            sleepMs(20)
        })
        return Ok(0)
    })
    onceOne.join()
    onceTwo.join()
    onceThree.join()
    print("once=" + str(once.isDone()) + "," + str(onceCount.load()))
    onceGroup.close()

    Once cancelledOnce = new Once()
    AtomicInt cancelledOnceCount = AtomicInt(0)
    Result<Unit, Error> onceCancelled = cancelledOnce.run(preCancelled, () -> {
        cancelledOnceCount.store(1)
    })
    print("once-cancel=" + errorKindName(onceCancelled.error().kind()) + "," +
        str(cancelledOnce.isDone()) + "," + str(cancelledOnceCount.load()))

    // ---------- RwLock ----------
    RwLock<Int> lock = new RwLock<Int>(10)
    AtomicInt readValue = AtomicInt(0)
    lock.withRead(context, (Int value) -> { readValue.store(value) })
    lock.withWrite(context, (Int value) -> { readValue.store(value + 1) })
    print("rw=" + str(readValue.load()) + "," + str(lock.readerCount()) + "," +
        str(lock.isWriteLocked()) + "," + str(lock.waitingWriters()))

    RwLock<Int> shared = new RwLock<Int>(0)
    AtomicInt activeReaders = AtomicInt(0)
    AtomicInt maxReaders = AtomicInt(0)
    TaskGroup readGroup = newGroup(context)
    Task<Int> readerOne = readGroup.spawn((Context taskContext) -> {
        shared.withRead(taskContext, (Int value) -> {
            atomicAdd(activeReaders, 1)
            bumpMax(maxReaders, activeReaders.load())
            sleepMs(60)
            atomicAdd(activeReaders, -1)
        })
        return Ok(0)
    })
    Task<Int> readerTwo = readGroup.spawn((Context taskContext) -> {
        shared.withRead(taskContext, (Int value) -> {
            atomicAdd(activeReaders, 1)
            bumpMax(maxReaders, activeReaders.load())
            sleepMs(60)
            atomicAdd(activeReaders, -1)
        })
        return Ok(0)
    })
    sleepMs(25)
    Int readersInside = shared.readerCount()
    readerOne.join()
    readerTwo.join()
    print("rw-readers=" + str(readersInside) + "," + str(maxReaders.load()))
    readGroup.close()

    RwLock<Int> exclusive = new RwLock<Int>(0)
    AtomicBool writing = AtomicBool(false)
    AtomicInt readWhileWriting = AtomicInt(0)
    TaskGroup exclusiveGroup = newGroup(context)
    Task<Int> writer = exclusiveGroup.spawn((Context taskContext) -> {
        exclusive.withWrite(taskContext, (Int value) -> {
            writing.store(true)
            sleepMs(80)
            writing.store(false)
        })
        return Ok(0)
    })
    sleepMs(20)
    Task<Int> exclusiveReader = exclusiveGroup.spawn((Context taskContext) -> {
        exclusive.withRead(taskContext, (Int value) -> {
            if writing.load() { readWhileWriting.store(1) }
        })
        return Ok(0)
    })
    writer.join()
    exclusiveReader.join()
    print("rw-exclusive=" + str(readWhileWriting.load()))
    exclusiveGroup.close()

    RwLock<Int> priority = new RwLock<Int>(0)
    AtomicInt order = AtomicInt(0)
    AtomicInt readerAfterWriter = AtomicInt(0)
    TaskGroup priorityGroup = newGroup(context)
    Task<Int> longReader = priorityGroup.spawn((Context taskContext) -> {
        priority.withRead(taskContext, (Int value) -> { sleepMs(120) })
        return Ok(0)
    })
    sleepMs(20)
    Task<Int> waitingWriter = priorityGroup.spawn((Context taskContext) -> {
        priority.withWrite(taskContext, (Int value) -> { order.store(1) })
        return Ok(0)
    })
    sleepMs(20)
    Task<Int> nextReader = priorityGroup.spawn((Context taskContext) -> {
        priority.withRead(taskContext, (Int value) -> {
            if order.load() == 1 { readerAfterWriter.store(1) }
        })
        return Ok(0)
    })
    sleepMs(20)
    Int waitingSnapshot = priority.waitingWriters()
    longReader.join()
    waitingWriter.join()
    nextReader.join()
    print("rw-priority=" + str(waitingSnapshot) + "," + str(readerAfterWriter.load()))
    priorityGroup.close()

    RwLock<Int> cancelLock = new RwLock<Int>(0)
    TaskGroup cancelGroup = newGroup(context)
    Task<Int> cancelHolder = cancelGroup.spawn((Context taskContext) -> {
        cancelLock.withRead(taskContext, (Int value) -> { sleepMs(80) })
        return Ok(0)
    })
    sleepMs(20)
    Result<Unit, Error> writerCancelled = cancelLock.withWrite(preCancelled, (Int value) -> { })
    print("rw-cancel=" + errorKindName(writerCancelled.error().kind()) + "," +
        str(cancelLock.waitingWriters()))
    cancelHolder.join()
    cancelGroup.close()

    RwLock<Int> closedLock = new RwLock<Int>(0)
    closedLock.close()
    closedLock.close()
    Result<Unit, Error> closedRead = closedLock.withRead(context, (Int value) -> { })
    print("rw-close=" + str(closedLock.isClosed()) + "," +
        errorKindName(closedRead.error().kind()))

    // ---------- Pool ----------
    AtomicInt creations = AtomicInt(0)
    AtomicInt destructions = AtomicInt(0)
    Pool<Int> pool = new Pool<Int>(2,
        () -> {
            atomicAdd(creations, 1)
            return Ok(creations.load())
        },
        (Int value) -> { atomicAdd(destructions, 1) })
    Result<Int, Error> first = pool.acquire(context)
    Result<Int, Error> second = pool.acquire(context)
    Result<Int, Error> full = pool.acquire(preCancelled)
    print("pool=" + str(first.value()) + "," + str(second.value()) + "," +
        errorKindName(full.error().kind()) + "," + str(pool.capacity()) + "," +
        str(pool.inUseCount()) + "," + str(pool.idleCount()))
    pool.release(first.value())
    Result<Int, Error> reused = pool.acquire(context)
    print("pool-reuse=" + str(reused.value()) + "," + str(creations.load()) + "," +
        str(pool.inUseCount()) + "," + str(pool.idleCount()))
    pool.release(second.value())
    pool.release(reused.value())
    print("pool-idle=" + str(pool.idleCount()))
    pool.close()
    Result<Int, Error> closedPool = pool.acquire(context)
    print("pool-close=" + str(pool.isClosed()) + "," + str(destructions.load()) + "," +
        errorKindName(closedPool.error().kind()))

    Pool<Int> failingPool = new Pool<Int>(1,
        () -> { return Err(new BasicError(ErrorKind.Io, "factory")) },
        (Int value) -> { })
    Result<Int, Error> factoryFailure = failingPool.acquire(context)
    print("pool-factory=" + errorKindName(factoryFailure.error().kind()) + "," +
        str(failingPool.inUseCount()) + "," + str(failingPool.idleCount()))
    failingPool.close()

    // ---------- Promise / Future ----------
    Promise<Int> promise = new Promise<Int>()
    Future<Int> future = promise.future()
    TaskGroup promiseGroup = newGroup(context)
    Task<Int> completer = promiseGroup.spawn((Context taskContext) -> {
        sleepMs(20)
        promise.complete(11)
        return Ok(0)
    })
    Result<Int, Error> awaited = future.get(context)
    completer.join()
    print("future=" + str(future.isDone()) + "," + str(awaited.value()) + "," +
        str(promise.complete(12)))

    Promise<Int> sharedPromise = new Promise<Int>()
    Future<Int> sharedFuture = sharedPromise.future()
    Task<Int> sharedOne = promiseGroup.spawn((Context taskContext) -> {
        Result<Int, Error> firstRead = sharedFuture.get(taskContext)
        return Ok(firstRead.value())
    })
    Task<Int> sharedTwo = promiseGroup.spawn((Context taskContext) -> {
        Result<Int, Error> secondRead = sharedFuture.get(taskContext)
        return Ok(secondRead.value())
    })
    sleepMs(20)
    sharedPromise.complete(13)
    print("future-multi=" + str(sharedOne.join().value()) + "," + str(sharedTwo.join().value()))

    Promise<Int> failedPromise = new Promise<Int>()
    Future<Int> failedFuture = failedPromise.future()
    failedPromise.fail(new BasicError(ErrorKind.Io, "bad"))
    Result<Int, Error> failed = failedFuture.get(context)
    print("future-fail=" + errorKindName(failed.error().kind()) + "," +
        str(failedFuture.isCancelled()) + "," + str(failedPromise.failure() != null))

    Promise<Int> cancelledPromise = new Promise<Int>()
    Future<Int> cancelledFuture = cancelledPromise.future()
    cancelledPromise.cancel("stop")
    Result<Int, Error> cancelledGet = cancelledFuture.get(context)
    print("future-cancel=" + errorKindName(cancelledGet.error().kind()) + "," +
        str(cancelledFuture.isCancelled()))

    Promise<Int> deadlinePromise = new Promise<Int>()
    Long started = nowMono()
    Future<Int> deadlineFuture = deadlinePromise.future()
    Result<Int, Error> timedOut = deadlineFuture.getDeadline(context, nowMono() + 40)
    Long elapsed = nowMono() - started
    print("future-deadline=" + errorKindName(timedOut.error().kind()) + "," +
        str(elapsed < 2000) + "," + str(deadlinePromise.isDone()))

    Promise<Int> readyPromise = new Promise<Int>()
    readyPromise.complete(3)
    Future<Int> readyFuture = readyPromise.future()
    Result<Int, Error> ready = readyFuture.getDeadline(context, nowMono() - 1)
    print("future-ready=" + str(ready.isOk()) + "," + str(ready.value()))

    Promise<Int> abandoned = new Promise<Int>()
    Future<Int> abandonedFuture = abandoned.future()
    Result<Int, Error> abandonedGet = abandonedFuture.get(preCancelled)
    print("future-wait-cancel=" + errorKindName(abandonedGet.error().kind()))
    promiseGroup.close()

    // ---------- Executor ----------
    Executor executor = Executor.fixed(context, 2)
    AtomicInt activeTasks = AtomicInt(0)
    AtomicInt maxTasks = AtomicInt(0)
    Result<Task<Int>, Error> pendingOne = executor.submit<Int>(context, (Context taskContext) -> {
        atomicAdd(activeTasks, 1)
        bumpMax(maxTasks, activeTasks.load())
        sleepMs(40)
        atomicAdd(activeTasks, -1)
        return Ok(1)
    })
    Result<Task<Int>, Error> pendingTwo = executor.submit<Int>(context, (Context taskContext) -> {
        atomicAdd(activeTasks, 1)
        bumpMax(maxTasks, activeTasks.load())
        sleepMs(40)
        atomicAdd(activeTasks, -1)
        return Ok(1)
    })
    Result<Task<Int>, Error> pendingThree = executor.submit<Int>(context, (Context taskContext) -> {
        atomicAdd(activeTasks, 1)
        bumpMax(maxTasks, activeTasks.load())
        sleepMs(40)
        atomicAdd(activeTasks, -1)
        return Ok(1)
    })
    Result<Task<Int>, Error> pendingFour = executor.submit<Int>(context, (Context taskContext) -> {
        atomicAdd(activeTasks, 1)
        bumpMax(maxTasks, activeTasks.load())
        sleepMs(40)
        atomicAdd(activeTasks, -1)
        return Ok(1)
    })
    Task<Int> taskOne = pendingOne.value()
    Task<Int> taskTwo = pendingTwo.value()
    Task<Int> taskThree = pendingThree.value()
    Task<Int> taskFour = pendingFour.value()
    Int taskSum = 0
    taskSum = taskSum + taskOne.join().value()
    taskSum = taskSum + taskTwo.join().value()
    taskSum = taskSum + taskThree.join().value()
    taskSum = taskSum + taskFour.join().value()
    print("exec=" + str(executor.parallelism()) + "," + str(taskSum) + "," +
        str(maxTasks.load() <= 2) + "," + str(maxTasks.load() >= 1))

    Result<Task<Int>, Error> cancelledSubmit = executor.submit<Int>(preCancelled, (Context taskContext) -> {
        return Ok(0)
    })
    print("exec-cancel=" + errorKindName(cancelledSubmit.error().kind()))

    Result<Unit, Error> firstClose = executor.close()
    print("exec-close=" + str(firstClose.isOk()) + "," + str(executor.isClosed()) + "," +
        str(executor.close().isOk()))
    Result<Task<Int>, Error> afterClose = executor.submit<Int>(context, (Context taskContext) -> {
        return Ok(0)
    })
    print("exec-after-close=" + errorKindName(afterClose.error().kind()) + "," +
        str(context.isCancelled()))

    Executor failingExecutor = Executor.single(context)
    Result<Task<Int>, Error> failingTask = failingExecutor.submit<Int>(context, (Context taskContext) -> {
        return Err(new BasicError(ErrorKind.Io, "task"))
    })
    Task<Int> failingTaskValue = failingTask.value()
    Result<Int, TaskError> failingJoined = failingTaskValue.join()
    Result<Unit, Error> failingClose = failingExecutor.close()
    print("exec-error=" + errorKindName(errorKindFromCode(failingJoined.error() as Int)) + "," +
        errorKindName(failingClose.error().kind()))
    return 0
}
