// B3.1 RuntimeMonitor：进入/退出、通知、可取消等待、幂等关闭与并发。
import xdk.runtime
import xdk.tasks

static Int main() {
    // 顺序路径：进入/退出、关闭幂等。
    RuntimeMonitor m = new RuntimeMonitor()
    print(m.isClosed())
    m.enter()
    m.exit()
    m.close()
    m.close()
    print(m.isClosed())

    // 关闭后等待立即返回，不再阻塞。
    Context ctx = Context.background()
    m.enter()
    print(m.waitContext(ctx))
    m.exit()

    // 可取消等待：已取消的上下文返回 false。
    Context cancelled = Context.background()
    cancelled.cancel()
    RuntimeMonitor c = new RuntimeMonitor()
    c.enter()
    print(c.waitContext(cancelled))
    c.exit()
    c.close()

    // 并发路径：主线程持有监视器，任务在 wait 释放后进入并通知。
    RuntimeMonitor shared = new RuntimeMonitor()
    TaskGroup group = TaskGroup.create(ctx)
    shared.enter()
    Task<Int> waiter = group.spawn(() -> {
        shared.enter()
        shared.notifyAll()
        shared.exit()
        return Ok(1)
    })
    print(shared.waitContext(ctx))
    shared.exit()
    print(waiter.join().isOk())
    shared.enter()
    shared.notify()
    shared.exit()
    shared.close()
    print(shared.isClosed())
    print(group.close().isOk())
    return 0
}
