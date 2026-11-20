// xdk.time.Duration —— 毫秒精度时长，纯 XNull 实现。
package xdk.time

class Duration {
    Long ms

    Duration(Long ms0) {
        self.ms = ms0
    }

    Long seconds() {
        return self.ms / 1000
    }

    Long millis() {
        return self.ms
    }

    Long micros() {
        return self.ms * 1000
    }

    Duration plus(Duration other) {
        return new Duration(self.ms + other.ms)
    }

    Duration minus(Duration other) {
        return new Duration(self.ms - other.ms)
    }
}
