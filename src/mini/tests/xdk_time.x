import xdk.time

static Int main() {
    Duration d = durationOfSeconds(2)
    print(d.millis())
    print(nowWallMs() > 0)
    DateTime dt = now()
    print(dt.year() > 2000)
    print(dt.iso8601().length() > 10)
    // Fixed civil date: catches 32-bit overflow in dateTimeOf (R4).
    DateTime fixed = dateTimeOf(2024, 1, 31, 23, 59, 59)
    print(fixed.format("yyyy-MM-dd HH:mm:ss"))
    print(fixed.timestamp())
    return 0
}
