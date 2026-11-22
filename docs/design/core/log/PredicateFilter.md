# `PredicateFilter`

| 项 | 值 |
| --- | --- |
| 类型 | `class PredicateFilter implements Filter` |
| 包 | `xdk.log` |
| 稳定性 | `stable` |
| 依赖 | `Filter`、`LogRecord` |

---

## 1. 定位

用调用方 predicate 决定日志记录是否保留。

不做：级别阈值、采样、脱敏、sink。

---

## 2. 设计逻辑

- 构造时保存 `Bool(LogRecord) predicate`；predicate 必须非 null。
- `allow(record)` 直接返回 `predicate(record)`。
- `record == null` → 返回 `false`，不调用 predicate。
- 不修改记录；predicate 异常由调用方负责。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_predicate` | `Bool(LogRecord)` | 非 null |

不变量：predicate 非 null；实例无其他可变状态。

---

## 4. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `PredicateFilter(Bool(LogRecord) predicate)` | predicate | 非 null | null → panic |

---

## 5. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `allow` | 委托 predicate | `LogRecord record` | `Bool` | null record → false |

---

## 6. 示例与反例

正确：`new PredicateFilter((LogRecord record) -> record.message().contains("retry"))`。

反例：predicate 为 null；在 predicate 中写 sink；依赖全局过滤器状态。

---

## 7. 测试/场景义务

predicate true/false；null record；构造 null predicate panic；与 Logger 管道组合；predicate 不被修改。

---

## 8. XNull 伪代码

```xnull
class PredicateFilter implements Filter {
    final Bool(LogRecord) _predicate

    PredicateFilter(Bool(LogRecord) predicate) {
        if predicate == null { throw "PredicateFilter: null predicate" }
        _predicate = predicate
    }

    Bool allow(LogRecord record) {
        if record == null { return false }
        return _predicate(record)
    }
}
```
