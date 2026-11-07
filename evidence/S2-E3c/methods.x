class M {
    static Int n = 4;
    static Int twice(Int x) { return x * 2 }
    Int f(Int x) { return x + 1 }
    Int f(String s) { return s.length() }
}
static Int main() {
    M m = new M()
    print(m.f(1))
    print(m.f("abc"))
    print(M.n)
    print(M.twice(3))
    return 0
}
