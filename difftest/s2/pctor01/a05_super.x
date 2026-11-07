class B {
    Int x;
    B(Int v) { self.x = v }
}
class D : B {
    Int y;
    D(Int v) {
        super(v)
        self.y = v + 1
    }
}
static Int main() {
    D d = new D(5)
    print(d.x)
    print(d.y)
    return 0
}
