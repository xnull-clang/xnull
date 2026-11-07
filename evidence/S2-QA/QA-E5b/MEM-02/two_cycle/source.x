class A { B b; void deinit() { print("dA") } }
class B { A a; void deinit() { print("dB") } }
static Int main() {
    A a = new A()
    B b = new B()
    a.b = b
    b.a = a
    print("main")
    return 0
}
