package xdk2.time_extra
import xdk.time
import xdk.errors

static Int main() {
    Instant zero = Instant.ofEpochMillis(0 as Long)
    Instant positive = Instant.ofEpochMillis(1234 as Long)
    Instant negative = Instant.ofEpochMillis(-5 as Long)
    print("instant=" + str(zero.epochMillis()) + "," + str(positive.epochMillis()) +
        "," + str(negative.epochMillis()) + "," + str(positive.epochSeconds()) + "," +
        str(Instant.ofEpochMillis(1999 as Long).epochSeconds()) + "," +
        str(Instant.ofEpochMillis(-1999 as Long).epochSeconds()))
    print("instant-text=" + positive.toString() + "," + str(positive.equals(positive.copy())) +
        "," + str(positive.equals(null)))

    Instant seconds = Instant.ofEpochSeconds(2 as Long)
    print("instant-seconds=" + str(seconds.epochMillis()) + "," +
        str(Instant.ofEpochSeconds(0 as Long).epochMillis()) + "," +
        str(Instant.ofEpochSeconds(-2 as Long).epochMillis()))

    Instant base = Instant.ofEpochMillis(1000 as Long)
    Instant later = base.plus(durationOfMillis(500 as Long))
    Instant earlier = base.minus(durationOfMillis(250 as Long))
    print("instant-math=" + str(later.epochMillis()) + "," + str(earlier.epochMillis()) +
        "," + str(base.isBefore(later)) + "," + str(base.isAfter(earlier)) + "," +
        str(base.compare(later)) + "," + str(base.compare(base.copy())) + "," +
        str(later.compare(base)))

    DateTime epoch = zero.toDateTime()
    print("instant-datetime=" + epoch.iso8601() + "," +
        Instant.ofEpochMillis(86400000 as Long).toDateTime().iso8601())

    Long wall = nowWallMs()
    Instant now = Instant.now()
    Long difference = now.epochMillis() - wall
    if difference < 0 as Long { difference = 0 as Long - difference }
    print("instant-now=" + str(now.epochMillis() > 0 as Long) + "," +
        str(difference < 5000 as Long))

    TimeZone utc = TimeZone.utc()
    TimeZone east = TimeZone.fixed(28800000)
    TimeZone west = TimeZone.fixed(-19800000)
    TimeZone half = TimeZone.fixed(1800000)
    TimeZone zeroOffset = TimeZone.fixed(0)
    TimeZone edge = TimeZone.fixed(64800000)
    print("timezone=" + utc.id() + "," + str(utc.offsetMillis()) + "," +
        utc.abbreviation() + "," + east.id() + "," + str(east.offsetMillis()) + "," +
        west.id() + "," + half.id() + "," + zeroOffset.id() + "," + edge.id())
    print("timezone-offsetAt=" + str(east.offsetAt(positive)) + "," +
        str(west.offsetAt(negative)) + "," + str(utc.offsetAt(zero)))
    print("timezone-equals=" + str(utc.equals(TimeZone.utc())) + "," +
        str(utc.equals(TimeZone.fixed(0))) + "," +
        str(east.equals(TimeZone.fixed(28800000))) + "," + str(utc.equals(null)) +
        "," + utc.toString())
    return 0
}
