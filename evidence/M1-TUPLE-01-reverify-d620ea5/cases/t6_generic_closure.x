static T id<T>(T x) { return x }
static Int main() {
    (Int, String) t = (1, "a")
    (Int, String) u = id<(Int, String)>(t)
    print(u.0)
    print(u.1)
    (Int, String) cap = (2, "b")
    Int(String) f = (String s) -> { return cap.0 }
    print(f("x"))
    return 0
}
