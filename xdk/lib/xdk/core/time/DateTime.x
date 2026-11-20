// xdk.time —— 对标 Go time + Python datetime 的时钟与日期包。
// 约定：
//   - DateTime 内部统一持有 UNIX epoch 毫秒（UTC）；civil 字段按需换算。
//   - 时区：v1 只提供 UTC 语义（toUTC/toLocal 返回自身，等价直通）。
//   - Timer 闭包式 after/every 依赖函数类型形参（已知的源码层发射缺口），
//     v1 暂缓，仅提供阻塞 sleep 与 Duration/DateTime 全量能力。

package xdk.time

import xdk.errors
import xdk.sys

// ---------- 时钟 ----------






















































































































class DateTime {
    Long ms

    DateTime(Long ms0) {
        self.ms = ms0
    }

    Long timestamp() {
        return self.ms
    }

    Civil civil() {
        return civilFromDays(civilFloorDiv(self.ms as Int, 86400000))
    }

    Int year() {
        return self.civil().y
    }

    Int month() {
        return self.civil().m
    }

    Int day() {
        return self.civil().d
    }

    Int hour() {
        return civilMod(self.ms as Int, 86400000) / 3600000
    }

    Int minute() {
        return civilMod(self.ms as Int, 3600000) / 60000
    }

    Int second() {
        return civilMod(self.ms as Int, 60000) / 1000
    }

    Int millisecond() {
        return civilMod(self.ms as Int, 1000)
    }

    // 星期：0=周日 … 6=周六（1970-01-01 为周四=4）。
    Int weekday() {
        return civilMod(civilFloorDiv(self.ms as Int, 86400000) + 4, 7)
    }

    Int dayOfYear() {
        Civil c = self.civil()
        Int acc = 0
        Int i = 1
        while i < c.m {
            acc = acc + civilDaysInMonth(c.y, i)
            i = i + 1
        }
        return acc + c.d
    }

    DateTime add(Duration d) {
        return new DateTime(self.ms + d.ms)
    }

    Duration diff(DateTime other) {
        return new Duration(self.ms - other.ms)
    }

    Bool before(DateTime other) {
        return self.ms < other.ms
    }

    Bool after(DateTime other) {
        return self.ms > other.ms
    }

    Int compare(DateTime other) {
        if self.ms < other.ms {
            return -1
        }
        if self.ms > other.ms {
            return 1
        }
        return 0
    }

    DateTime toUTC() {
        return self
    }

    DateTime toLocal() {
        return self
    }

    // 布局令牌：yyyy MM dd HH mm ss SSS；其余字符原样输出。
    // 替换值均为纯数字，不会引入新的字母令牌，可安全全量替换。
    String format(String layout) {
        String out = layout
        out = out.replace("yyyy", padLeftNum(str(self.year()), 4))
        out = out.replace("SSS", padLeftNum(str(self.millisecond()), 3))
        out = out.replace("MM", padLeftNum(str(self.month()), 2))
        out = out.replace("dd", padLeftNum(str(self.day()), 2))
        out = out.replace("HH", padLeftNum(str(self.hour()), 2))
        out = out.replace("mm", padLeftNum(str(self.minute()), 2))
        out = out.replace("ss", padLeftNum(str(self.second()), 2))
        return out
    }

    String iso8601() {
        return self.format("yyyy-MM-ddTHH:mm:ss.SSS")
    }

    String rfc3339() {
        return self.format("yyyy-MM-ddTHH:mm:ss") + "Z"
    }
}
