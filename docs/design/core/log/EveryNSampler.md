# `EveryNSampler`

| 项 | 值 |
| --- | --- |
| 类型 | `class EveryNSampler implements Sampler` |
| 包 | `xdk.log` |
| 稳定性 | `stable` |
| 依赖 | `Sampler`、`LogRecord` |

---

## 1. 定位

确定性每 N 条采样：对已通过级别/过滤的记录计数，保留第 N、2N、3N… 条。

不做：时间窗口、随机采样、过滤、脱敏。

---

## 2. 设计逻辑

- 字段 `_interval`、`_seen`；`interval >= 1`。
- `keep(record)`：`record == null` → false；否则 `_seen = _seen + 1`，当 `_seen % _interval == 0` 返回 true。
- `count()` 返回该实例观察到的记录数（含被丢弃的记录）。
- 计数状态按实例；派生 Logger 共享同一实例时计数共享；非线程安全。
- 只统计已通过级别与过滤的记录。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_interval` | `Int` | ≥1 |
| `_seen` | `Int` | ≥0，已观察数 |

不变量：interval ≥1；seen ≥0；非线程安全。

---

## 4. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `EveryNSampler(Int interval)` | interval | ≥1 | ≤0 → panic |

---

## 5. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `keep` | 第 N 条保留 | `LogRecord record` | `Bool` | null → false |
| `count` | 已观察数 | 无 | `Int` | 无 |

---

## 6. 示例与反例

正确：`new EveryNSampler(3)` 保留第 3/6/9 条；`count()` 随每条通过前置条件的记录递增。

反例：interval 0；期望保留第 1 条；期望过滤前计数；多任务共享同一实例不进行同步。

---

## 7. 测试/场景义务

N=1 全保留；N=3 保留序列；`count()`；null record 不递增；构造非法 interval panic；与 filter 组合只统计通过者；跨实例状态独立。

---

## 8. XNull 伪代码

```xnull
class EveryNSampler implements Sampler {
    final Int _interval
    Int _seen = 0

    EveryNSampler(Int interval) {
        if interval < 1 { throw "EveryNSampler: interval must be positive" }
        _interval = interval
    }

    Bool keep(LogRecord record) {
        if record == null { return false }
        _seen = _seen + 1
        return _seen % _interval == 0
    }

    Int count() { return _seen }
}
```
