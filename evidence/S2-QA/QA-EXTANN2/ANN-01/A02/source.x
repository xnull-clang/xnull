protocol P { Bool go(); }
class C implements P {
    @Override
    Bool go() { return true }
}
static Int main() {
    C c = new C()
    print(c.go())
    return 0
}
