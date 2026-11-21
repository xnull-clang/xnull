// xdk.time —— 对标 Go time + Python datetime 的时钟与日期包。
// 约定：
//   - DateTime 内部统一持有 UNIX epoch 毫秒（UTC）；civil 字段按需换算。
//   - 时区：v1 只提供 UTC 语义（toUTC/toLocal 返回自身，等价直通）。
//   - Timer 闭包式 after/every 依赖函数类型形参（已知的源码层发射缺口），
//     v1 暂缓，仅提供阻塞 sleep 与 Duration/DateTime 全量能力。

package xdk.time

import xdk.errors
import xdk.sys

// 布局令牌（最长匹配）：yyyy MM MMM MMMM dd ddd dddd EEE EEEE HH mm ss SSS。
// 数字令牌不做二次替换；名称令牌用于展示，不参与解析。
static Bool layoutAt(String layout, Int index, String token) {
    if index < 0 || index + token.length() > layout.length() {
        return false
    }
    return layout.substring(index, token.length()) == token
}

static String monthShortName(Int month) {
    if month == 1 { return "Jan" }
    if month == 2 { return "Feb" }
    if month == 3 { return "Mar" }
    if month == 4 { return "Apr" }
    if month == 5 { return "May" }
    if month == 6 { return "Jun" }
    if month == 7 { return "Jul" }
    if month == 8 { return "Aug" }
    if month == 9 { return "Sep" }
    if month == 10 { return "Oct" }
    if month == 11 { return "Nov" }
    return "Dec"
}

static String monthLongName(Int month) {
    if month == 1 { return "January" }
    if month == 2 { return "February" }
    if month == 3 { return "March" }
    if month == 4 { return "April" }
    if month == 5 { return "May" }
    if month == 6 { return "June" }
    if month == 7 { return "July" }
    if month == 8 { return "August" }
    if month == 9 { return "September" }
    if month == 10 { return "October" }
    if month == 11 { return "November" }
    return "December"
}

static String weekdayShortName(Int weekday) {
    if weekday == 0 { return "Sun" }
    if weekday == 1 { return "Mon" }
    if weekday == 2 { return "Tue" }
    if weekday == 3 { return "Wed" }
    if weekday == 4 { return "Thu" }
    if weekday == 5 { return "Fri" }
    return "Sat"
}

static String weekdayLongName(Int weekday) {
    if weekday == 0 { return "Sunday" }
    if weekday == 1 { return "Monday" }
    if weekday == 2 { return "Tuesday" }
    if weekday == 3 { return "Wednesday" }
    if weekday == 4 { return "Thursday" }
    if weekday == 5 { return "Friday" }
    return "Saturday"
}

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

    // 布局令牌（最长匹配）：yyyy MM MMM MMMM dd ddd dddd EEE EEEE HH mm ss SSS。
    // 从左到右扫描，先匹配 4 字符令牌，再 3 字符，再 2 字符；其余字符原样输出。
    // 这样 MMM/MMMM 不会被 MM 吃掉，ddd 不会被 dd 吃掉。
    String format(String layout) {
        String out = ""
        Int i = 0
        while i < layout.length() {
            if layoutAt(layout, i, "yyyy") {
                out = out + padLeftNum(str(self.year()), 4)
                i = i + 4
            } else if layoutAt(layout, i, "MMMM") {
                out = out + monthLongName(self.month())
                i = i + 4
            } else if layoutAt(layout, i, "EEEE") {
                out = out + weekdayLongName(self.weekday())
                i = i + 4
            } else if layoutAt(layout, i, "dddd") {
                out = out + weekdayLongName(self.weekday())
                i = i + 4
            } else if layoutAt(layout, i, "SSS") {
                out = out + padLeftNum(str(self.millisecond()), 3)
                i = i + 3
            } else if layoutAt(layout, i, "MMM") {
                out = out + monthShortName(self.month())
                i = i + 3
            } else if layoutAt(layout, i, "EEE") {
                out = out + weekdayShortName(self.weekday())
                i = i + 3
            } else if layoutAt(layout, i, "ddd") {
                out = out + weekdayShortName(self.weekday())
                i = i + 3
            } else if layoutAt(layout, i, "MM") {
                out = out + padLeftNum(str(self.month()), 2)
                i = i + 2
            } else if layoutAt(layout, i, "dd") {
                out = out + padLeftNum(str(self.day()), 2)
                i = i + 2
            } else if layoutAt(layout, i, "HH") {
                out = out + padLeftNum(str(self.hour()), 2)
                i = i + 2
            } else if layoutAt(layout, i, "mm") {
                out = out + padLeftNum(str(self.minute()), 2)
                i = i + 2
            } else if layoutAt(layout, i, "ss") {
                out = out + padLeftNum(str(self.second()), 2)
                i = i + 2
            } else {
                out = out + layout.substring(i, 1)
                i = i + 1
            }
        }
        return out
    }

    String iso8601() {
        return self.format("yyyy-MM-ddTHH:mm:ss.SSS")
    }

    String rfc3339() {
        return self.format("yyyy-MM-ddTHH:mm:ss") + "Z"
    }
}
