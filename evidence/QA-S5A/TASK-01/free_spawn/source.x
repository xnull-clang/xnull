import xdk.tasks
static Int main() {
    Task<Int> t = spawn(() -> { Result<Int, TaskError> r = Ok(1); return r })
    return 0
}
