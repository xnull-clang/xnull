class A {
    Int x = 3;
    Int f() { return 10 }
}
class B : A {
    Int g() { super.x = super.x + 1; return super.f() + super.x }
}
static Int main() {
    B b = new B()
    print(b.g())
    print(b.x)
    return 0
}
