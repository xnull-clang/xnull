// xdk.time —— TimeZone（M21.0）
//
// 仅 UTC 与固定偏移；不实现 IANA/DST/历史规则。
package xdk.time

class TimeZone {
    final String _id
    final Int _offsetMillis

    private TimeZone(String zoneId, Int offsetMillis) {
        if zoneId == null || zoneId == "" {
            throw "TimeZone: empty id"
        }
        if offsetMillis < -64800000 || offsetMillis > 64800000 {
            throw "TimeZone: offset out of range"
        }
        self._id = zoneId
        self._offsetMillis = offsetMillis
    }

    static TimeZone utc() {
        return new TimeZone("UTC", 0)
    }

    static TimeZone fixed(Int offsetMillis) {
        String sign = "+"
        Int absolute = offsetMillis
        if absolute < 0 {
            sign = "-"
            absolute = 0 - absolute
        }
        Int hours = absolute / 3600000
        Int minutes = (absolute % 3600000) / 60000
        String id = "UTC" + sign + padLeftNum(str(hours), 2) + ":" +
            padLeftNum(str(minutes), 2)
        return new TimeZone(id, offsetMillis)
    }

    String id() { return self._id }
    Int offsetMillis() { return self._offsetMillis }

    Int offsetAt(Instant instant) {
        if instant == null { throw "TimeZone.offsetAt: null" }
        return self._offsetMillis
    }

    String abbreviation() { return self._id }

    Bool equals(TimeZone other) {
        if other == null { return false }
        return self._id == other.id() && self._offsetMillis == other.offsetMillis()
    }

    String toString() { return self._id }
}
