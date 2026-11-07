protocol Value { Int get(); }
class One implements Value { Int get() { return 1 } }
class Two implements Value { Int get() { return 2 } }
class Base { Int f() { return 7 } }
class Derived : Base { Int g() { return 9 } }
static Int main() {
    Value a = new One()
    Value b = new Two()
    Base x = new Derived()
    print(a.get())
    print(b.get())
    print(x.f())
    return 0
}
