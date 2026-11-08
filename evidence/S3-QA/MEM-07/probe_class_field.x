class C {
    Result<Int, String> r = Ok(5);
}
static Int main() {
    C c = new C()
    print(c.r.isOk())
    print(c.r.value())
    return 0
}
