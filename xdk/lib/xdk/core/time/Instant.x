// xdk.time —— Instant（M21.0）
//
// UTC epoch 毫秒时间点；不可变值语义。时区/日历字段由 DateTime/TimeZone 承担。
package xdk.time

class Instant {
    final Long _epochMillis

    private Instant(Long epochMillis) {
        self._epochMillis = epochMillis
    }

    static Instant ofEpochMillis(Long epochMillis) {
        return new Instant(epochMillis)
    }

    static Instant ofEpochSeconds(Long seconds) {
        Long limit = 9223372036854775 as Long
        Long negativeLimit = 0 as Long - limit
        if seconds > limit || seconds < negativeLimit {
            throw "Instant: overflow"
        }
        return new Instant(seconds * (1000 as Long))
    }

    static Instant now() {
        return new Instant(nowWallMs())
    }

    Long epochMillis() { return self._epochMillis }

    Long epochSeconds() { return self._epochMillis / (1000 as Long) }

    Instant plus(Duration duration) {
        if duration == null { throw "Instant.plus: null" }
        return new Instant(self._epochMillis + duration.millis())
    }

    Instant minus(Duration duration) {
        if duration == null { throw "Instant.minus: null" }
        return new Instant(self._epochMillis - duration.millis())
    }

    Bool isBefore(Instant other) {
        if other == null { throw "Instant.isBefore: null" }
        return self._epochMillis < other.epochMillis()
    }

    Bool isAfter(Instant other) {
        if other == null { throw "Instant.isAfter: null" }
        return self._epochMillis > other.epochMillis()
    }

    Int compare(Instant other) {
        if other == null { throw "Instant.compare: null" }
        if self._epochMillis < other.epochMillis() { return -1 }
        if self._epochMillis > other.epochMillis() { return 1 }
        return 0
    }

    DateTime toDateTime() {
        return new DateTime(self._epochMillis)
    }

    String toString() {
        return "instant(" + str(self._epochMillis) + "ms)"
    }

    Instant copy() {
        return new Instant(self._epochMillis)
    }

    Bool equals(Instant other) {
        if other == null { return false }
        return self._epochMillis == other.epochMillis()
    }
}
