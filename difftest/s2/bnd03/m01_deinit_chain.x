class B {
    Int f() { return 1 }
    B() { print("B") }
    void deinit() { print("dB") }
}
class D : B {
    D() { print("D") }
    void deinit() { print("dD"); super.deinit() }
}
static Int main() {
    if true {
        D d = new D()
        print(d.f())
    }
    print("after")
    return 0
}
