class C {
    Result<Int, String> r;
    C(Result<Int, String> x) { self.r = x }
}
static Int main() {
    Result<Int, String> a = Ok(7)
    Result<Int, String> b = a
    C c = new C(b)
    print(a.isOk())
    print(c.r.isOk())
    print(c.r.value())
    return 0
}
