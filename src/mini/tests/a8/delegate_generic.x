class Engine<T> { T start(T x) { return x } }
class Car {
    @Delegate final Engine<Int> engine
    Car(Engine<Int> engine) { self.engine = engine }
}
static Int main() { return 0 }
