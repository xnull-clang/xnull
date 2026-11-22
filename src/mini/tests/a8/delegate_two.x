class A { Int start(Int x) { return x } }
class B { Int start(Int x) { return x + 1 } }
class Car {
    @Delegate final A a
    @Delegate final B b
    Car(A a, B b) { self.a = a; self.b = b }
}
static Int main() { return 0 }
