protocol Ready {
    Bool ready();
}
class C implements Ready {
    Bool ready() { return true }
}
static Int main() {
    C c = new C()
    print(c.ready())
    return 0
}
