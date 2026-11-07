class D {
    void deinit() { print("dD") }
}
static Int main() {
    if true {
        D d = new D()
    }
    print("after")
    return 0
}
