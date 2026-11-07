class C { Int x = 1; }
extension C {
    Int f() { return 1 }
    Int f(Int n) { return n }
    Int f(Int n, Int m) { return n + m }
}
static Int main() {
    C c = new C()
    print(c.f())
    print(c.f(2))
    print(c.f(2, 3))
    return 0
}
