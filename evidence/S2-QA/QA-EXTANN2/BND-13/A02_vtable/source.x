protocol P { Int f(); }
class C implements P {
    Int f() { return 1 }
}
extension C {
    Int g() { return 2 }
}
static Int main() {
    C c = new C()
    P p = c
    print(c.g())
    print(p.f())
    return 0
}
