class Engine {
    Int starts
    Engine() { self.starts = 0 }
    Int start(Int x) {
        self.starts = self.starts + 1
        return x + 1
    }
    Void stop() {
        self.starts = self.starts + 10
    }
    String name() { return "engine" }
}
class Car {
    @Delegate final Engine engine
    Car(Engine engine) { self.engine = engine }
}
static Int main() {
    Engine engine = new Engine()
    Car car = new Car(engine)
    print(car.start(4))
    print(car.name())
    car.stop()
    print(engine.starts)
    return 0
}
