import xdk.time

static Int main() {
    Duration d = durationOfSeconds(2)
    print(d.millis())
    print(d.minus(durationOfMillis(500)).seconds())
    return 0
}
