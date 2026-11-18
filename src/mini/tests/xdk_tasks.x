import xdk.tasks

static Int main() {
    Context ctx = Context.background()
    TaskGroup g = TaskGroup.create(ctx)
    print(ctx.isCancelled())
    Task<Int> t = g.spawn(() -> {
        return Ok(42)
    })
    Result<Int,TaskError> r = t.join()
    print(r.isOk())
    print(r.value())
    Task<Int> e = g.spawn(() -> {
        return Err(5)
    })
    Result<Int,TaskError> er = e.join()
    print(er.isOk())
    print(er.isErr())
    Result<void,TaskError> close = g.close()
    print(close.isOk())
    print(ctx.isCancelled())
    return 0
}
