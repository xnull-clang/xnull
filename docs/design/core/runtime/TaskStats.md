# `TaskStats`

### 1. 定位

执行层任务快照：活跃/排队/完成/失败/取消。用于诊断/转储/健康检查。

### 2. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_active` | `Int` | final | 正在运行 |
| `_queued` | `Int` | final | 已提交未运行 |
| `_completed` | `Int` | final | 成功完成 |
| `_failed` | `Int` | final | 失败完成 |
| `_cancelled` | `Int` | final | 取消完成 |
| `_total` | `Int` | final | 累计创建 |

不变量：所有值 ≥0；快照尽力一致，不承诺强一致；不可变；可共享。

### 3. 使用的技术

- 不可变快照；
- 计数聚合；
- 空闲判定。

### 4. 需要的支撑

- 语言：class、Int、Bool、String；
- 运行时：任务统计原语；
- 接口：无。

### 5. 依赖的特性/接口/类

无其他 XDK 类；只依赖语言原语和运行时任务系统。

### 6. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `active` | 活跃 | 无 | `Int` | 无 |
| `queued` | 排队 | 无 | `Int` | 无 |
| `completed` | 完成 | 无 | `Int` | 无 |
| `failed` | 失败 | 无 | `Int` | 无 |
| `cancelled` | 取消 | 无 | `Int` | 无 |
| `total` | 累计 | 无 | `Int` | 无 |
| `isIdle` | 是否空闲 | 无 | `Bool` | 无 |
| `describe` | 摘要 | 无 | `String` | 无 |
| `copy` | 复制 | 无 | `TaskStats` | 无 |

### 7. XNull 伪代码

```xnull
class TaskStats {
    final Int _active
    final Int _queued
    final Int _completed
    final Int _failed
    final Int _cancelled
    final Int _total

    TaskStats(Int active, Int queued, Int completed,
              Int failed, Int cancelled, Int total) {
        _active = active
        _queued = queued
        _completed = completed
        _failed = failed
        _cancelled = cancelled
        _total = total
    }

    Int active() { return _active }
    Int queued() { return _queued }
    Int completed() { return _completed }
    Int failed() { return _failed }
    Int cancelled() { return _cancelled }
    Int total() { return _total }

    Bool isIdle() {
        return _active + _queued == 0
    }

    String describe() {
        return "active=" + str(_active)
            + " queued=" + str(_queued)
            + " completed=" + str(_completed)
            + " failed=" + str(_failed)
            + " cancelled=" + str(_cancelled)
            + " total=" + str(_total)
    }

    TaskStats copy() {
        return new TaskStats(
            _active,
            _queued,
            _completed,
            _failed,
            _cancelled,
            _total
        )
    }
}
```

---
