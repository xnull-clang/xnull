import xdk.tasks

static Int main() {
    Context context = Context.background()
    TaskGroup group = TaskGroup.create(context)
    Task<Int> task = group.spawn(() -> {
        return Ok(42)
    })
    Result<Int, TaskError> result = task.join()
    print(result.value())
    Result<void, TaskError> closed = group.close()
    print(closed.isOk())
    return 0
}
