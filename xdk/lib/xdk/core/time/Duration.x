// xdk.time.Duration —— 毫秒精度时长，纯 XNull 实现。
package xdk.time

class Duration {
    Int64 ms

    Duration(Int64 ms0) {
        self.ms = ms0
    }

    Int64 seconds() {
        return self.ms / 1000
    }

    Int64 millis() {
        return self.ms
    }

    Int64 micros() {
        return self.ms * 1000
    }

    Duration plus(Duration other) {
        return new Duration(self.ms + other.ms)
    }

    Duration minus(Duration other) {
        return new Duration(self.ms - other.ms)
    }
}
