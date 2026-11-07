class B {
    B(Int v) { }
}
class D : B {
    D(Int v) {
        print("before")
        super(v)
    }
}
static Int main() { return 0 }
