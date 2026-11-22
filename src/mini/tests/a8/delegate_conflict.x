class Engine { Int start(Int x) { return x } }
class Car {
    @Delegate final Engine engine
    Car(Engine engine) { self.engine = engine }
    Int start(Int x) { return x + 1 }
}
static Int main() { return 0 }
