protocol P { Int f(); }
class C implements P { Int f() { return 1 } }
static Int main() {
    P p = new C()
    print(p is C)
    return 0
}
