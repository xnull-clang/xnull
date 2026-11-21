# `ConnectionPoolStats`

| 项 | 值 |
| --- | --- |
| 类型 | `class ConnectionPoolStats` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

连接池统计快照：总数、空闲、活跃、等待者、复用、创建、关闭。

不做：实时指标、Prometheus 导出、每键明细。

---

## 2. 设计逻辑

- 不可变字段；全部 ≥0。
- 快照后不随池变化。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_total` | `Int` | 总连接 |
| `_idle` | `Int` | 空闲 |
| `_active` | `Int` | 借出 |
| `_waiting` | `Int` | 等待者 |
| `_reused` | `Long` | 复用次数 |
| `_created` | `Long` | 创建次数 |
| `_closed` | `Long` | 关闭次数 |

不变量：非负；不可变。

---

## 4. 生命周期

快照；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ConnectionPoolStats(...)` | 见字段 | ≥0 | 负值 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `total` | 总数 | 无 | `Int` | 无 |
| `idle` | 空闲 | 无 | `Int` | 无 |
| `active` | 活跃 | 无 | `Int` | 无 |
| `waiting` | 等待 | 无 | `Int` | 无 |
| `reused` | 复用 | 无 | `Long` | 无 |
| `created` | 创建 | 无 | `Long` | 无 |
| `closed` | 关闭 | 无 | `Long` | 无 |
| `toString` | 摘要 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- 计数器。

---

## 9. 需要的支撑

- 语言：class、Int、Long、String；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

不可变；无资源；可共享。

---

## 12. 示例与反例

正确：`pool.stats().active()`。  
反例：修改 stats 期望池变化；负计数；把快照当实时。

---

## 13. 测试/场景义务

零值；各字段；快照独立；负值 panic；toString。

---

## 14. XNull 伪代码

```xnull
class ConnectionPoolStats {
    final Int _total
    final Int _idle
    final Int _active
    final Int _waiting
    final Long _reused
    final Long _created
    final Long _closed

    ConnectionPoolStats(Int total, Int idle, Int active, Int waiting,
                        Long reused, Long created, Long closed) {
        if total < 0 || idle < 0 || active < 0 || waiting < 0 {
            throw "ConnectionPoolStats: negative count"
        }
        if reused < 0 || created < 0 || closed < 0 {
            throw "ConnectionPoolStats: negative counter"
        }
        _total = total
        _idle = idle
        _active = active
        _waiting = waiting
        _reused = reused
        _created = created
        _closed = closed
    }

    Int total() { return _total }
    Int idle() { return _idle }
    Int active() { return _active }
    Int waiting() { return _waiting }
    Long reused() { return _reused }
    Long created() { return _created }
    Long closed() { return _closed }

    String toString() {
        return "pool(total=" + str(_total) + ",idle=" + str(_idle) + ",active=" + str(_active) + ")"
    }
}
```
