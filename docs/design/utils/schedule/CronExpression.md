# `CronExpression`

| 项 | 值 |
| --- | --- |
| 类型 | `class CronExpression` |
| 包 | `xdk.schedule` |
| 稳定性 | `preview` |
| 依赖 | `TimeZone`、`Error` |

---

## 1. 定位

cron 表达式：解析、下一次/下 N 次触发、匹配、描述。

不做：调度执行、misfire、持久化、DST 规则（X）、Cron 名称字段（X）。

---

## 2. 设计逻辑

- 支持 5 字段（分 时 日 月 周）和 6 字段（秒 分 时 日 月 周）。
- 支持 `*`、`?`、列表 `a,b`、范围 `a-b`、步长 `*/n`、`a-b/n`；数字字段。
- 宏：`@yearly`/`@annually`、`@monthly`、`@weekly`、`@daily`/`@midnight`、`@hourly`。
- 解析委托 `CronScheduleRaw`；失败 `InvalidArgument`。
- `next` 严格晚于 from，按给定固定偏移时区计算；无未来时间返回 `InvalidArgument`。
- `matches` 按秒精度判断。
- `nextN` 返回最多 count 个未来时间；不足时返回已找到的列表还是错误？ 选择返回不足列表，调用方可检查长度。
- 不可变；无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_text` | `String` | 原始表达式 |
| `_description` | `String` | 可读描述 |
| `_handle` | `CronScheduleRaw` | 运行时解析句柄 |

不变量：text/description/handle 非 null；handle 已解析成功。

---

## 4. 生命周期

不可变；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CronExpression(String, CronScheduleRaw, String)` | 内部 | 非 null | 私有；null → panic |

应用使用 `parse`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `parse` | 解析 | `String text` | `Result<CronExpression, Error>` | `InvalidArgument` |
| `next` | 下次触发 | `Long fromEpochMillis, TimeZone zone` | `Result<Long, Error>` | `InvalidArgument` |
| `nextN` | 下 N 次 | `Long fromEpochMillis, TimeZone zone, Int count` | `Result<List<Long>, Error>` | count<1 → `InvalidArgument` |
| `matches` | 是否匹配 | `Long epochMillis, TimeZone zone` | `Bool` | null zone → panic |
| `describe` | 描述 | 无 | `String` | 无 |
| `text` | 原始表达式 | 无 | `String` | 无 |

说明：

- `next` 返回 epoch 毫秒；结果按秒对齐。
- `nextN` 从 from 开始逐次调用 next；不足 count 时返回较短列表，不报错。
- `matches` 对毫秒部分忽略或按秒截断由实现固定； 按秒截断。

---

## 8. 使用的技术

- cron 字段解析；
- 日历推进；
- 固定偏移时区；
- 运行时解析句柄。

---

## 9. 需要的支撑

- 语言：class、String、Long、Int、Bool、List、Result；
- 运行时：`cronParseRaw`、`cronNextRaw`、`cronMatchesRaw`、`CronScheduleRaw`；
- 接口：`TimeZone`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`TimeZone`、`Error`、cron 运行时原语。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`CronExpression.parse("0 3 * * *")`；`next(now, TimeZone.utc())`。  
反例：非法字段数；`2月30日`；把 cron 当本地 DST 规则；next 返回等于 from。

---

## 13. 测试/场景义务

5/6 字段；每个语法；宏；边界日期；闰年；月末；周字段；时区偏移；next 严格大于；nextN；matches；非法表达式；无未来。

---

## 14. XNull 伪代码

```xnull
class CronExpression {
    final String _text
    final String _description
    final CronScheduleRaw _handle

    private CronExpression(String text, CronScheduleRaw handle, String description) {
        if text == null || handle == null || description == null {
            throw "CronExpression: null argument"
        }
        _text = text
        _handle = handle
        _description = description
    }

    static Result<CronExpression, Error> parse(String text) {
        if text == null { throw "CronExpression.parse: null text" }
        Result<CronScheduleRaw, Error> parsed = cronParseRaw(text)
        if parsed.isErr() { return Err(parsed.error()) }
        CronScheduleRaw handle = parsed.value()
        return Ok(new CronExpression(text, handle, handle.description()))
    }

    Result<Long, Error> next(Long fromEpochMillis, TimeZone zone) {
        if zone == null { throw "CronExpression.next: null zone" }
        return cronNextRaw(_handle, fromEpochMillis, zone)
    }

    Result<List<Long>, Error> nextN(Long fromEpochMillis, TimeZone zone, Int count) {
        if zone == null { throw "CronExpression.nextN: null zone" }
        if count < 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "count must be positive"))
        }
        List<Long> result = []
        Long cursor = fromEpochMillis
        Int index = 0
        while index < count {
            Result<Long, Error> next = self.next(cursor, zone)
            if next.isErr() { break }
            result.push(next.value())
            cursor = next.value()
            index = index + 1
        }
        return Ok(result)
    }

    Bool matches(Long epochMillis, TimeZone zone) {
        if zone == null { throw "CronExpression.matches: null zone" }
        return cronMatchesRaw(_handle, epochMillis, zone)
    }

    String describe() { return _description }
    String text() { return _text }
}
```

> `CronScheduleRaw` 与 `cron*Raw` 是运行时 cron 原语；不是 XDK 公共类型。
