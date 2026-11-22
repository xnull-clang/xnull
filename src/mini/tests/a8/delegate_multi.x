class Engine {
    String start() { return "start" }
}
class Radio {
    String play() { return "play" }
}
class Car {
    @Delegate final Engine engine
    @Delegate final Radio radio
    Car(Engine engine, Radio radio) {
        self.engine = engine
        self.radio = radio
    }
}
static Int main() {
    Car car = new Car(new Engine(), new Radio())
    print(car.start())
    print(car.play())
    return 0
}
