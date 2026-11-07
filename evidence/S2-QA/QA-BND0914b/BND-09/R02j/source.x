class B { private Int x = 5; }
class D : B { Int get() { return super._x } }
static Int main() {
    D d = new D()
    print(d.get())
    return 0
}
