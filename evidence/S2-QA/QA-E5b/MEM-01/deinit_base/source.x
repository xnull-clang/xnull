class Base {
    String name = "base"
    void deinit() { print("base-deinit") }
}
class Derived : Base {
    Int y = 2
}
static Int main() {
    Derived d = new Derived()
    print("main")
    return 0
}
