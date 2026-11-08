import xdk.runtime

static Int main() {
    diagnose("s6\nruntime")
    Int a = nowMono()
    Int b = nowMono()
    Int w = nowWall()
    String? e = env("XNULL_S6_ENV")
    dumpTasks()
    print(a <= b)
    print(w > 0)
    print(e == null)
    return 0
}
