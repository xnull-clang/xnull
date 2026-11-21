# `Month`

| 项 | 值 |
| --- | --- |
| 类型 | `enum Month` |
| 包 | `xdk.time` |
| 稳定性 | `stable` |
| 依赖 | 无 |

---

## 1. 定位

公历月份枚举；用于 `Date`/`DateTime`/`civilDaysInMonth`。

不做：日历系统、locale 名称、季度。

---

## 2. 设计逻辑

- 12 个成员，顺序固定。
- `number()` 1..12；`shortName()` 英文三字母。
- 天数由 `daysInCommonYear`/`daysInLeapYear` 提供；2 月随闰年变化。
- 值语义；可作 Map 键。

---

## 3. 表示与不变量

| 成员 | number |
| --- | ---: |
| `January` | 1 |
| `February` | 2 |
| `March` | 3 |
| `April` | 4 |
| `May` | 5 |
| `June` | 6 |
| `July` | 7 |
| `August` | 8 |
| `September` | 9 |
| `October` | 10 |
| `November` | 11 |
| `December` | 12 |

不变量：成员固定；只允许追加。

---

## 4. 生命周期

值类型；无 close；可共享。

---

## 5. 构造契约

枚举成员直接使用；`Month.fromNumber(Int)` 由顶层/静态函数提供。

---

## 6. 字段表

无实例字段。

---

## 7. 相关顶层函数

`Month` 没有实例方法；月份号/名称/天数由顶层函数提供。

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `number` | 月份号 | 无 | `Int` | 无 |
| `shortName` | 三字母名 | 无 | `String` | 无 |
| `daysInCommonYear` | 平年天数 | 无 | `Int` | 无 |
| `daysInLeapYear` | 闰年天数 | 无 | `Int` | 无 |
| `fromNumber` | 号→月份 | `Int number` | `Result<Month, Error>` | `InvalidArgument` |

---

## 8. 使用的技术

- 枚举；
- 固定表；
- 闰年天数表。

---

## 9. 需要的支撑

- 语言：enum、Int、String、Result；
- 运行时：无；
- 接口：`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

值语义；可共享；无资源。

---

## 12. 示例与反例

正确：`Month.February.daysInLeapYear()` → 29。  
反例：用 0 表示 January；用枚举顺序当稳定码（用 `number()`）。

---

## 13. 测试/场景义务

12 成员；number；shortName；平/闰天数；fromNumber 1..12 与越界。

---

## 14. XNull 伪代码

```xnull
enum Month {
    January,
    February,
    March,
    April,
    May,
    June,
    July,
    August,
    September,
    October,
    November,
    December,
}

Int number(Month month) {
    if month == Month.January { return 1 }
    if month == Month.February { return 2 }
    if month == Month.March { return 3 }
    if month == Month.April { return 4 }
    if month == Month.May { return 5 }
    if month == Month.June { return 6 }
    if month == Month.July { return 7 }
    if month == Month.August { return 8 }
    if month == Month.September { return 9 }
    if month == Month.October { return 10 }
    if month == Month.November { return 11 }
    return 12
}

Result<Month, Error> monthFromNumber(Int number) {
    if number == 1 { return Ok(Month.January) }
    if number == 2 { return Ok(Month.February) }
    if number == 3 { return Ok(Month.March) }
    if number == 4 { return Ok(Month.April) }
    if number == 5 { return Ok(Month.May) }
    if number == 6 { return Ok(Month.June) }
    if number == 7 { return Ok(Month.July) }
    if number == 8 { return Ok(Month.August) }
    if number == 9 { return Ok(Month.September) }
    if number == 10 { return Ok(Month.October) }
    if number == 11 { return Ok(Month.November) }
    if number == 12 { return Ok(Month.December) }
    return Err(new BasicError(ErrorKind.InvalidArgument, "invalid month"))
}
```
