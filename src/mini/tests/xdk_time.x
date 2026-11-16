import xdk.time

static Int main() {
    Duration d = durationOfSeconds(2)
    print(d.millis())
    print(nowWallMs() > 0)
    DateTime dt = now()
    print(dt.year() > 2000)
    print(dt.iso8601().length() > 10)
    return 0
}
