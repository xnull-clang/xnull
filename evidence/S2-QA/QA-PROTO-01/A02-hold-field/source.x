protocol P { Int f(); }
class C implements P {
    Int f() { return 7 }
    void deinit() { print("dC") }
}
class H { P p; }
static Int main() {
    H h = new H()
    h.p = new C()
    print(h.p.f())
    print("after")
    return 0
}
