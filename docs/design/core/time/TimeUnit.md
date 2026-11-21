# `TimeUnit`

| 项 | 值 |
| --- | --- |
| 类型 | `enum TimeUnit` |
| 包 | `xdk.time` |
| 稳定性 | `stable` |
| 依赖 | 无 |

---

## 1. 定位

时间单位换算：毫秒/秒/分/时/天。

不做：纳秒/微秒（`Duration` 有显式方法）、月/年（日历长度不固定）。

---

## 2. 设计逻辑

- 5 个成员。
- `toMillis(value)` 乘法；溢出 panic。
- `tryToMillis(value)` checked。
- `fromMillis(milliseconds)` 截断除法。
- `convert(value, source, target)` 先转毫秒再转目标；`tryConvert` 是 checked 版本。

---

## 3. 表示与不变量

| 成员 | 毫秒因子 |
| --- | ---: |
| `Millis` | 1 |
| `Seconds` | 1000 |
| `Minutes` | 60000 |
| `Hours` | 3600000 |
| `Days` | 86400000 |

不变量：成员固定；因子固定。

---

## 4. 生命周期

值类型；无 close；可共享。

---

## 5. 构造契约

枚举成员直接使用。

---

## 6. 字段表

无实例字段。

---

## 7. 相关顶层函数

`TimeUnit` 没有实例方法；单位换算由顶层函数提供。

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `toMillis` | 转毫秒 | `Long value` | `Long` | 溢出 → panic |
| `tryToMillis` | checked 转毫秒 | `Long value` | `Result<Long, Error>` | `InvalidArgument` |
| `fromMillis` | 毫秒转本单位 | `Long milliseconds` | `Long` | 无（截断） |
| `convert` | 单位转换 | `Long value, TimeUnit source, TimeUnit target` | `Long` | 溢出 → panic |
| `tryConvert` | checked 转换 | 同上 | `Result<Long, Error>` | `InvalidArgument` |

---

## 8. 使用的技术

- 固定因子；
- 乘法/除法；
- 溢出检查。

---

## 9. 需要的支撑

- 语言：enum、Long、Result；
- 运行时：整数运算；
- 接口：`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

值语义；可共享；无资源。

---

## 12. 示例与反例

正确：`TimeUnit.Seconds.toMillis(2)` → 2000。  
反例：用 `fromMillis` 期望四舍五入；用 TimeUnit 表示月/年；忽略溢出。

---

## 13. 测试/场景义务

每个单位的 toMillis/fromMillis；溢出；convert；截断；零/负值。

---

## 14. XNull 伪代码

```xnull
enum TimeUnit {
    Millis,
    Seconds,
    Minutes,
    Hours,
    Days,
}

Long factorMillis(TimeUnit timeUnit) {
    if timeUnit == TimeUnit.Millis { return 1 }
    if timeUnit == TimeUnit.Seconds { return 1000 }
    if timeUnit == TimeUnit.Minutes { return 60000 }
    if timeUnit == TimeUnit.Hours { return 3600000 }
    return 86400000
}

Result<Long, Error> tryToMillis(TimeUnit timeUnit, Long value) {
    Long factor = factorMillis(timeUnit)
    if value > 9223372036854775807 / factor
        || value < -9223372036854775808 / factor {
        return Err(new BasicError(ErrorKind.InvalidArgument, "time unit overflow"))
    }
    return Ok(value * factor)
}

Long toMillis(TimeUnit timeUnit, Long value) {
    Result<Long, Error> result = tryToMillis(timeUnit, value)
    if result.isErr() {
        throw result.error().describe()
    }
    return result.value()
}

Long fromMillis(TimeUnit timeUnit, Long milliseconds) {
    return milliseconds / factorMillis(timeUnit)
}

Long convert(Long value, TimeUnit source, TimeUnit target) {
    return fromMillis(target, toMillis(source, value))
}

Result<Long, Error> tryConvert(Long value, TimeUnit source, TimeUnit target) {
    Result<Long, Error> millis = tryToMillis(source, value)
    if millis.isErr() {
        return Err(millis.error())
    }
    return Ok(fromMillis(target, millis.value()))
}
```
