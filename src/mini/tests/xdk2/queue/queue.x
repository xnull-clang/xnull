package xdk2.queue
import xdk.queue
import xdk.errors
import xdk.tasks
import xdk.time

static String popText(BoundedQueue<String> queue) {
    String? value = queue.pop()
    if value == null { return "null" }
    return value as String
}

static Int main() {
    Context context = Context.background()

    print("policy=" + dropPolicyName(DropPolicy.Error) + "," +
        dropPolicyName(DropPolicy.DropNewest) + "," +
        dropPolicyName(DropPolicy.DropOldest))
    DropPolicy? newest = parseDropPolicy(" DROP-NEWEST ")
    DropPolicy? missing = parseDropPolicy("bogus")
    print("policy-parse=" + dropPolicyName(newest as DropPolicy) + "," +
        str(missing == null) + "," + str(parseDropPolicy(null) == null))

    QueueStats stats = new QueueStats(2, 3 as Long, 4 as Long, 5 as Long, 6 as Long, false)
    print("stats=" + stats.describe() + "," + str(stats.equals(stats.copy())) + "," +
        str(stats.equals(null)) + "," + str(stats.rejected()))

    BoundedQueue<String> errorQueue = new BoundedQueue<String>(2, DropPolicy.Error)
    print("error-push=" + str(errorQueue.push("a")) + "," + str(errorQueue.push("b")) +
        "," + str(errorQueue.push("c")) + "," + str(errorQueue.isFull()) + "," +
        str(errorQueue.size()))
    print("error-pop=" + popText(errorQueue) + "," + popText(errorQueue) + "," +
        popText(errorQueue) + "," + str(errorQueue.isEmpty()))
    errorQueue.push("x")
    errorQueue.clear()
    QueueStats errorStats = errorQueue.stats()
    print("error-stats=" + str(errorStats.size()) + "," + str(errorStats.pushed()) +
        "," + str(errorStats.popped()) + "," + str(errorStats.dropped()) + "," +
        str(errorStats.rejected()) + "," + str(errorStats.isClosed()))
    errorQueue.push("y")
    errorQueue.close()
    errorQueue.close()
    print("error-close=" + str(errorQueue.push("z")) + "," + str(errorQueue.pop() == null) +
        "," + str(errorQueue.isClosed()) + "," + str(errorQueue.isFull()) + "," +
        str(errorQueue.stats().dropped()))

    BoundedQueue<String> newestQueue = new BoundedQueue<String>(1, DropPolicy.DropNewest)
    print("newest=" + str(newestQueue.push("a")) + "," + str(newestQueue.push("b")) +
        "," + popText(newestQueue) + "," + str(newestQueue.stats().dropped()) + "," +
        str(newestQueue.stats().rejected()))

    BoundedQueue<String> oldestQueue = new BoundedQueue<String>(2, DropPolicy.DropOldest)
    oldestQueue.push("a")
    oldestQueue.push("b")
    print("oldest=" + str(oldestQueue.push("c")) + "," + popText(oldestQueue) + "," +
        popText(oldestQueue) + "," + str(oldestQueue.stats().dropped()) + "," +
        str(oldestQueue.stats().pushed()))

    BatchQueue<String> batch = new BatchQueue<String>(2)
    print("batch-add=" + str(batch.add("a")) + "," + str(batch.add("b")) + "," +
        str(batch.add("c")) + "," + str(batch.isFull()) + "," + str(batch.size()))
    List<String> peeked = batch.peek()
    List<String> flushed = batch.flush()
    print("batch-flush=" + str(peeked.length()) + "," + str(flushed.length()) + "," +
        flushed.get(0) + "," + flushed.get(1) + "," + str(batch.size()) + "," +
        str(batch.flush().length()))
    batch.close()
    print("batch-close=" + str(batch.add("d")) + "," + str(batch.flush().length()) + "," +
        str(batch.isClosed()) + "," + str(batch.isFull()))

    DelayQueue<String> delayQueue = new DelayQueue<String>()
    print("delay-empty=" + str(delayQueue.isEmpty()) + "," + str(delayQueue.size()) + "," +
        str(delayQueue.nextReadyAt() == null) + "," + str(delayQueue.tryTake() == null))
    delayQueue.put("zero", 0 as Long)
    String? zero = delayQueue.tryTake()
    print("delay-zero=" + (zero as String) + "," + str(delayQueue.size()))
    delayQueue.put("late", 60 as Long)
    delayQueue.put("early", 10 as Long)
    Long? next = delayQueue.nextReadyAt()
    print("delay-next=" + str(next != null) + "," + str(delayQueue.size()) + "," +
        str(delayQueue.tryTake() == null))
    sleepMs(20 as Long)
    String? early = delayQueue.tryTake()
    print("delay-early=" + (early as String) + "," + str(delayQueue.size()))
    Result<String, Error> late = delayQueue.take(context)
    print("delay-late=" + late.value() + "," + str(delayQueue.size()) + "," +
        str(delayQueue.isEmpty()))

    DelayQueue<String> preCancelQueue = new DelayQueue<String>()
    Context preCancelled = Context.background()
    preCancelled.cancel()
    print("delay-cancel=" + errorKindName(preCancelQueue.take(preCancelled).error().kind()) +
        "," + str(preCancelQueue.size()))

    DelayQueue<String> wakeQueue = new DelayQueue<String>()
    TaskGroup wakeGroup = TaskGroup.create(Context.background())
    Task<Int> wakeTask = wakeGroup.spawn((Context taskContext) -> {
        Result<String, Error> result = wakeQueue.take(taskContext)
        if result.isOk() { return Ok(0) }
        if result.error().kind() == ErrorKind.Unavailable { return Ok(2) }
        if result.error().kind() == ErrorKind.Cancelled { return Ok(1) }
        return Ok(3)
    })
    sleepMs(10 as Long)
    wakeQueue.close()
    Result<Int, TaskError> woke = wakeTask.join()
    wakeGroup.close()
    print("delay-wake=" + str(woke.isOk()) + "," + str(woke.value() == 2) + "," +
        str(wakeQueue.size()))

    DelayQueue<String> closeQueue = new DelayQueue<String>()
    closeQueue.put("a", 100 as Long)
    closeQueue.close()
    print("delay-close=" + errorKindName(closeQueue.take(context).error().kind()) + "," +
        str(closeQueue.put("b", 0 as Long)) + "," + str(closeQueue.isClosed()) + "," +
        str(closeQueue.stats().dropped()) + "," + str(closeQueue.size()))

    BoundedQueue<Int> concurrent = new BoundedQueue<Int>(100, DropPolicy.Error)
    TaskGroup pushGroup = TaskGroup.create(Context.background())
    Task<Int> firstPush = pushGroup.spawn(() -> {
        Int index = 0
        while index < 50 {
            concurrent.push(index)
            index = index + 1
        }
        return Ok(0)
    })
    Task<Int> secondPush = pushGroup.spawn(() -> {
        Int index = 50
        while index < 100 {
            concurrent.push(index)
            index = index + 1
        }
        return Ok(0)
    })
    Result<Int, TaskError> firstJoined = firstPush.join()
    Result<Int, TaskError> secondJoined = secondPush.join()
    pushGroup.close()
    print("concurrent=" + str(firstJoined.isOk()) + "," + str(secondJoined.isOk()) + "," +
        str(concurrent.size()) + "," + str(concurrent.stats().pushed()) + "," +
        str(concurrent.stats().rejected()))
    return 0
}
