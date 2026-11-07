protocol Ready {
    Bool ready();
}
class B {
    Bool ready() { return true }
}
class C : B implements Ready {
}
static Int main() {
    C c = new C()
    print(c.ready())
    return 0
}
