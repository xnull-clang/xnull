class B {
    Int f() { return 1 }
}
class D : B {
}
static Int main() {
    B b = new D()
    D d = new D()
    print(b.f())
    print(d.f())
    return 0
}
