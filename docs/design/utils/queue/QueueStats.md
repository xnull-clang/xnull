# `QueueStats`

| 项 | 值 |
| --- | --- |
| 类型 | `class QueueStats` |
| 包 | `xdk.queue` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

队列统计快照：当前大小、入队、出队、丢弃、拒绝、关闭状态。

不做：实时引用、重置、容量（由队列自身提供）。

---

## 2. 设计逻辑

- 不可变快照；`stats()` 创建。
- 计数非负；size 非负。
- dropped 包括 DropOldest/DropNewest/clear/close 丢弃；rejected 只用于 Error 策略。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_size` | `Int` | 当前条目数 |
| `_pushed` | `Long` | 成功入队 |
| `_popped` | `Long` | 成功出队 |
| `_dropped` | `Long` | 丢弃 |
| `_rejected` | `Long` | 拒绝 |
| `_closed` | `Bool` | 是否关闭 |

不变量：计数/size 非负；rejected 与 dropped 不重叠计数同一值。

---

## 4. 生命周期

不可变；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `QueueStats(Int size, Long pushed, Long popped, Long dropped, Long rejected, Bool closed)` | 全部 | 非负 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `size` | 当前大小 | 无 | `Int` | 无 |
| `pushed` | 入队数 | 无 | `Long` | 无 |
| `popped` | 出队数 | 无 | `Long` | 无 |
| `dropped` | 丢弃数 | 无 | `Long` | 无 |
| `rejected` | 拒绝数 | 无 | `Long` | 无 |
| `isClosed` | 是否关闭 | 无 | `Bool` | 无 |
| `toString` | 摘要 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- 计数聚合。

---

## 9. 需要的支撑

- 语言：class、Int、Long、Bool、String；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`stats.dropped()`；`stats.isClosed()`。  
反例：修改 stats 期望影响队列；把 rejected 计入 dropped；负数计数。

---

## 13. 测试/场景义务

全零；入队/出队/丢弃/拒绝；关闭；toString；负参数。

---

## 14. XNull 伪代码

```xnull
class QueueStats {
    final Int _size
    final Long _pushed
    final Long _popped
    final Long _dropped
    final Long _rejected
    final Bool _closed

    QueueStats(Int size, Long pushed, Long popped, Long dropped,
               Long rejected, Bool closed) {
        if size < 0 || pushed < 0 || popped < 0 || dropped < 0 || rejected < 0 {
            throw "QueueStats: negative value"
        }
        _size = size
        _pushed = pushed
        _popped = popped
        _dropped = dropped
        _rejected = rejected
        _closed = closed
    }

    Int size() { return _size }
    Long pushed() { return _pushed }
    Long popped() { return _popped }
    Long dropped() { return _dropped }
    Long rejected() { return _rejected }
    Bool isClosed() { return _closed }

    String toString() {
        return "QueueStats(size=" + str(_size) + ", pushed=" + str(_pushed)
            + ", popped=" + str(_popped) + ", dropped=" + str(_dropped) + ")"
    }
}
```
