protocol P { Int f(); }
class C implements P {
    Int f() { return 1 }
    Int g() { return 2 }
}
static Int main() {
    P p = new C()
    print(p.g())
    return 0
}
