class B { Int f() { return 1 } }
class D : B { Int g() { return super.f() + 1 } }
static Int main() {
    D d = new D()
    print(d.g())
    return 0
}
