protocol P { Int f(); }
class C implements P {
    Int f() { return 7 }
    void deinit() { print("dC") }
}
class H { P p; }
static P make() {
    C c = new C()
    return c
}
static Int main() {
    P p = make()
    print(p.f())
    H h = new H()
    h.p = new C()
    print(h.p.f())
    P q = new C()
    if true {
        C c = new C()
        q = c
    }
    print(q.f())
    return 0
}
