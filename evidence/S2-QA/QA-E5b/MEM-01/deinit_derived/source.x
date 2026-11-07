class B { void deinit() { print("dB") } }
class D : B { void deinit() { print("dD") } }
static Int main() {
    D d = new D()
    print("main")
    return 0
}
