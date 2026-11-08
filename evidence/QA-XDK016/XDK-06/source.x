import xdk.runtime
static Int main() {
    diagnose("diag-line")
    dumpTasks()
    Int a = nowMono()
    Int b = nowMono()
    print(b >= a)
    String? e = env("PATH")
    print(e != null)
    String? missing = env("XNULL_NO_SUCH_ENV_QA")
    print(missing == null)
    defer { print("defer-should-not-run") }
    exit(3)
    return 0
}
