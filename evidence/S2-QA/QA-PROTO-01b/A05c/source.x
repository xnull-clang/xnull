protocol P { Int f(); }
class C implements P { Int f() { return 1 } }
static Int main() {
    P p = new C()
    C? c = p as? C
    print(c != null)
    return 0
}
