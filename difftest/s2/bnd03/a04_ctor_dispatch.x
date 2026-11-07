class B {
    Int f() { return 1 }
    B() { print("B") }
}
class D : B {
    Int y = 2;
    D() { super(); print("D"); print(self.f()) }
    Int g() { return self.f() + y }
}
static Int main() {
    D d = new D()
    print(d.g())
    return 0
}
