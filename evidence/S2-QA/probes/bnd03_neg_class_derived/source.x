class Base { Int f() { return 1 } }
class Derived : Base { Int g() { return 2 } }
static Int main() {
    Base value = new Derived()
    print(value.g())
    return 0
}
