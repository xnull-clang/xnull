import xdk.time.Duration

static Int main() {
    Duration d = new Duration(1500)
    print(d.seconds())
    print(d.millis())
    print(d.micros())
    print(d.plus(new Duration(500)).millis())
    print(d.minus(new Duration(500)).millis())
    return 0
}
