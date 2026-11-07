class B {
    protected Int x = 7;
    protected Int f() { return x }
}
class D : B {
    Int g() { return self.x + self.f() }
}
static Int main() {
    D d = new D()
    print(d.g())
    return 0
}
