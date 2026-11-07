protocol P { Int f(); }
class C implements P { Int f() { return 1 } }
static Int main() {
    C c = new C()
    P p = c
    print(p.f())
    return 0
}
