// B3.2 Context deadline/timeout/wait/cancel 传播。
import xdk.runtime
import xdk.tasks
import xdk.time

static Int main() {
    // 1.x 行为不变：根未取消；子取消不反向影响父。
    Context root = Context.background()
    print(root.isCancelled())
    Context child = Context.withCancel(root)
    print(child.isCancelled())
    child.cancel()
    print(child.isCancelled())
    print(root.isCancelled())
    child.wait()
    child.wait()
    print(child.isCancelled())

    // 父取消向子传播；子等待被唤醒。
    Context parent = Context.background()
    Context leaf = Context.withCancel(parent)
    print(leaf.isCancelled())
    parent.cancel()
    print(leaf.isCancelled())
    leaf.wait()
    leaf.wait()
    print(leaf.isCancelled())

    // 相对超时：等待到期后上下文取消；重复 wait 立即返回。
    Context timed = Context.withTimeout(Context.background(), 20)
    print(timed.isCancelled())
    timed.wait()
    print(timed.isCancelled())
    timed.wait()

    // 绝对截止：到期即取消。
    Context absolute = Context.withDeadline(Context.background(), nowMono() + 20)
    absolute.wait()
    print(absolute.isCancelled())

    // 已过期的截止/零超时：立即取消，wait 不阻塞。
    Context expired = Context.withDeadline(Context.background(), nowMono() - 1)
    print(expired.isCancelled())
    expired.wait()
    Context zero = Context.withTimeout(Context.background(), 0)
    print(zero.isCancelled())
    zero.wait()

    // 取消唤醒：另一任务取消，主线程 wait 返回。
    Context wake = Context.background()
    TaskGroup group = TaskGroup.create(Context.background())
    Task<Int> canceller = group.spawn(() -> {
        sleepMs(20)
        wake.cancel()
        wake.cancel()
        return Ok(1)
    })
    wake.wait()
    print(wake.isCancelled())
    print(canceller.join().isOk())
    print(group.close().isOk())
    return 0
}
