# `Date`

| 项 | 值 |
| --- | --- |
| 类型 | `class Date` |
| 包 | `xdk.time` |
| 稳定性 | `stable` |
| 依赖 | `Month`、`Weekday` |

---

## 1. 定位

公历年月日值对象；用于日期计算/显示，不携带时间/时区。

不做：时间、时区、日历系统、闰秒。

---

## 2. 设计逻辑

- 字段 `_year`、`_month: Month`、`_day`。
- 不可变；值语义。
- `plusMonths/plusYears` 月末钳制；`plusDays` 通过 DateTime 换算。
- `weekday` 用 daysFromCivil；ISO Monday=1..Sunday=7。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_year` | `Int` | 公历年 |
| `_month` | `Month` | 月份 |
| `_day` | `Int` | 日 1..月末 |

不变量：日期合法；不可变。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Date(Int year, Month month, Int day)` | year/month/day | day 1..月天数 | 非法 → panic |
| `Date.of(...)` | 同上 | 同上 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `year` | 年 | 无 | `Int` | 无 |
| `month` | 月 | 无 | `Month` | 无 |
| `monthNumber` | 月号 | 无 | `Int` | 无 |
| `day` | 日 | 无 | `Int` | 无 |
| `plusDays` | 加天 | `Int days` | `Date` | 无 |
| `plusMonths` | 加月 | `Int months` | `Date` | 无 |
| `plusYears` | 加年 | `Int years` | `Date` | 无 |
| `weekday` | 星期 | 无 | `Weekday` | 无 |
| `dayOfYear` | 年内日 | 无 | `Int` | 无 |
| `isLeapYear` | 闰年 | 无 | `Bool` | 无 |
| `compare` | 比较 | `Date other` | `Int` | null → panic |
| `equals` | 值相等 | `Date other` | `Bool` | 无 |
| `toString` | 文本 | 无 | `String` | 无 |

---

## 8. 使用的技术

- civil 日期换算；
- 月末钳制；
- 闰年；
- ISO weekday。

---

## 9. 需要的支撑

- 语言：class、Int、Bool、String；
- 运行时：无；
- 接口：`Month`、`Weekday`、`civilDaysInMonth`、`daysFromCivil`、`civilFromDays`、`monthFromNumber`、`weekdayFromIso`。

---

## 10. 依赖的特性/接口/类

`Month`、`Weekday`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`new Date(2026, Month.November, 21).weekday()`。  
反例：用 Date 表示时间点；`plusMonths` 期望 1/31 变 2/31；用 0 基月份。

---

## 13. 测试/场景义务

闰年/月末/年末；plusDays/Months/Years；weekday；dayOfYear；compare/equals；toString。

---

## 14. XNull 伪代码

```xnull
class Date {
    final Int _year
    final Month _month
    final Int _day

    Date(Int year, Month month, Int day) {
        if month == null {
            throw "Date: null month"
        }
        Int maximum = civilDaysInMonth(year, month)
        if day < 1 || day > maximum {
            throw "Date: invalid day"
        }
        _year = year
        _month = month
        _day = day
    }

    static Date of(Int year, Month month, Int day) {
        return new Date(year, month, day)
    }

    Int year() { return _year }
    Month month() { return _month }
    Int monthNumber() { return number(_month) }
    Int day() { return _day }
    Bool isLeapYear() { return civilIsLeap(_year) }

    Date plusDays(Int days) {
        Long epoch = (daysFromCivil(_year, self.monthNumber(), _day) as Long) * 86400000
        Long moved = epoch + (days as Long) * 86400000
        Civil civil = civilFromDays(floorDiv(moved, 86400000) as Int)
        return new Date(civil.year, monthFromNumber(civil.month).value(), civil.day)
    }

    Date plusMonths(Int months) {
        Int target = self.monthNumber() + months
        Int year = _year + floorDiv(target - 1, 12)
        Int monthValue = floorMod(target - 1, 12) + 1
        Month targetMonth = monthFromNumber(monthValue).value()
        Int maximum = civilDaysInMonth(year, targetMonth)
        Int day = _day
        if day > maximum { day = maximum }
        return new Date(year, targetMonth, day)
    }

    Date plusYears(Int years) {
        return self.plusMonths(years * 12)
    }

    Weekday weekday() {
        Int days = daysFromCivil(_year, self.monthNumber(), _day)
        Int iso = floorMod(days + 3, 7) + 1
        return weekdayFromIso(iso).value()
    }

    Int dayOfYear() {
        Int result = _day
        Int index = 1
        while index < self.monthNumber() {
            result = result + civilDaysInMonth(_year, monthFromNumber(index).value())
            index = index + 1
        }
        return result
    }

    Int compare(Date other) {
        if other == null { throw "Date.compare: null" }
        if _year < other._year { return -1 }
        if _year > other._year { return 1 }
        if self.monthNumber() < other.monthNumber() { return -1 }
        if self.monthNumber() > other.monthNumber() { return 1 }
        if _day < other._day { return -1 }
        if _day > other._day { return 1 }
        return 0
    }

    Bool equals(Date other) {
        if other == null { return false }
        return self.compare(other) == 0
    }

    String toString() {
        return padLeftNum(str(_year), 4) + "-" + padLeftNum(str(self.monthNumber()), 2) + "-" + padLeftNum(str(_day), 2)
    }
}
```
