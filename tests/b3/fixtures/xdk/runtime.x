import xdk.runtime

static Int main() {
    String? e = env("PATH")
    if (e != null) {
        print("env-ok")
    }
    String? missing = env("XN_S6_02_NO_SUCH_ENV")
    print(missing == null)
    print(nowMono() > 0)
    print(nowWall() > 0)
    diagnose("diag-line\nsecond")
    dumpTasks()
    return 0
}
