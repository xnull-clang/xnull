# `Weekday`

| 项 | 值 |
| --- | --- |
| 类型 | `enum Weekday` |
| 包 | `xdk.time` |
| 稳定性 | `stable` |
| 依赖 | 无 |

---

## 1. 定位

星期枚举；ISO 顺序：Monday=1..Sunday=7。

不做：locale 周起始、宗教日历、工作日规则。

---

## 2. 设计逻辑

- 7 个成员，Monday..Sunday。
- `isoNumber()` 1..7；`shortName()` 三字母。
- `isWeekend()`：Saturday/Sunday。
- 值语义。

---

## 3. 表示与不变量

| 成员 | ISO |
| --- | ---: |
| `Monday` | 1 |
| `Tuesday` | 2 |
| `Wednesday` | 3 |
| `Thursday` | 4 |
| `Friday` | 5 |
| `Saturday` | 6 |
| `Sunday` | 7 |

不变量：成员固定；只允许追加。

---

## 4. 生命周期

值类型；无 close；可共享。

---

## 5. 构造契约

枚举成员直接使用；`weekdayFromIso(Int)` 由函数提供。

---

## 6. 字段表

无实例字段。

---

## 7. 相关顶层函数

`Weekday` 没有实例方法；编号/名称/周末判定由顶层函数提供。

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `isoNumber` | ISO 号 | 无 | `Int` | 无 |
| `shortName` | 三字母名 | 无 | `String` | 无 |
| `isWeekend` | 是否周末 | 无 | `Bool` | 无 |
| `fromIsoNumber` | 号→星期 | `Int number` | `Result<Weekday, Error>` | `InvalidArgument` |

---

## 8. 使用的技术

- 枚举；
- ISO 编号表；
- 周末判定。

---

## 9. 需要的支撑

- 语言：enum、Int、String、Bool、Result；
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

正确：`Weekday.Saturday.isWeekend()` → true。  
反例：用 0=Sunday 与 ISO 混用；用 locale 周起始替代 ISO。

---

## 13. 测试/场景义务

7 成员；isoNumber；shortName；周末；fromIsoNumber 1..7/越界。

---

## 14. XNull 伪代码

```xnull
enum Weekday {
    Monday,
    Tuesday,
    Wednesday,
    Thursday,
    Friday,
    Saturday,
    Sunday,
}

Int isoNumber(Weekday weekday) {
    if weekday == Weekday.Monday { return 1 }
    if weekday == Weekday.Tuesday { return 2 }
    if weekday == Weekday.Wednesday { return 3 }
    if weekday == Weekday.Thursday { return 4 }
    if weekday == Weekday.Friday { return 5 }
    if weekday == Weekday.Saturday { return 6 }
    return 7
}

Result<Weekday, Error> weekdayFromIso(Int number) {
    if number == 1 { return Ok(Weekday.Monday) }
    if number == 2 { return Ok(Weekday.Tuesday) }
    if number == 3 { return Ok(Weekday.Wednesday) }
    if number == 4 { return Ok(Weekday.Thursday) }
    if number == 5 { return Ok(Weekday.Friday) }
    if number == 6 { return Ok(Weekday.Saturday) }
    if number == 7 { return Ok(Weekday.Sunday) }
    return Err(new BasicError(ErrorKind.InvalidArgument, "invalid weekday"))
}
```
