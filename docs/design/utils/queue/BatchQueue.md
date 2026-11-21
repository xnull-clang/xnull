# `BatchQueue`

| 项 | 值 |
| --- | --- |
| 类型 | `class BatchQueue<T>` |
| 包 | `xdk.queue` |
| 稳定性 | `preview` |
| 依赖 | `RuntimeMonitor` |

---

## 1. 定位

批处理缓冲：累积元素，达到 batchSize 后由调用方 flush；支持 peek/clear/close。

不做：自动定时 flush（X）、阻塞、容量上限、持久化。

---

## 2. 设计逻辑

- 字段：batchSize、监视器、元素列表、关闭标志。
- `add` 非阻塞，总是追加（未关闭时）；不自动 flush。
- `isFull` 表示 size ≥ batchSize；调用方据此 `flush`。
- `flush` 返回当前批次副本并清空；`peek` 只读副本。
- `close` 清空并拒绝 add；close 幂等。
- 线程安全；无 close 资源。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_batchSize` | `Int` | ≥1 |
| `_monitor` | `RuntimeMonitor` | 状态保护 |
| `_items` | `List<T>` | 当前批次 |
| `_closed` | `Bool` | 是否关闭 |

不变量：batchSize≥1；items 非 null；closed 后 items 为空。

---

## 4. 生命周期

构造后使用；`close` 结束；close 幂等；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `BatchQueue(Int batchSize)` | batchSize | ≥1 | ≤0 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `add` | 追加 | `T value` | `Bool` | null value → panic |
| `isFull` | 是否达到批量 | 无 | `Bool` | 无 |
| `flush` | 取走批次 | 无 | `List<T>` | 无 |
| `peek` | 查看批次 | 无 | `List<T>` | 无 |
| `size` | 当前数量 | 无 | `Int` | 无 |
| `batchSize` | 批量大小 | 无 | `Int` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |
| `close` | 关闭清空 | 无 | `void` | 无；幂等 |
| `isClosed` | 是否关闭 | 无 | `Bool` | 无 |

说明：

- `add` 返回 false 表示已关闭；未关闭时总是 true。
- `flush` 返回副本；空批次返回空列表。
- `close` 丢弃未 flush 的元素，不返回它们。
- `isFull` 在 closed 后为 false。

---

## 8. 使用的技术

- 批缓冲；
- 监视器同步；
- 快照/清空。

---

## 9. 需要的支撑

- 语言：class、泛型、List、Int、Bool；
- 运行时：`RuntimeMonitor.enter/exit`；
- 接口：无。

---

## 10. 依赖的特性/接口/类

`RuntimeMonitor`。

---

## 11. 所有权与并发

引用语义；线程安全；可跨任务共享；无资源。

---

## 12. 示例与反例

正确：batchSize=128；add 直到 isFull；flush 写入下游。  
反例：期望 add 自动 flush；close 后 add 期望成功；flush 后仍持有旧引用期望可继续追加。

---

## 13. 测试/场景义务

batchSize 1/N；add/flush/peek；isFull；空 flush；clear/close；关闭后 add；并发 add/flush；flush 副本独立性。

---

## 14. XNull 伪代码

```xnull
class BatchQueue<T> {
    final Int _batchSize
    final RuntimeMonitor _monitor
    final List<T> _items
    Bool _closed = false

    BatchQueue(Int batchSize) {
        if batchSize < 1 { throw "BatchQueue: batchSize < 1" }
        _batchSize = batchSize
        _monitor = new RuntimeMonitor()
        _items = []
    }

    Bool add(T value) {
        if value == null { throw "BatchQueue.add: null value" }
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return false
        }
        _items.push(value)
        _monitor.exit()
        return true
    }

    Bool isFull() {
        _monitor.enter()
        Bool result = !_closed && _items.length() >= _batchSize
        _monitor.exit()
        return result
    }

    List<T> flush() {
        _monitor.enter()
        List<T> result = _items.copy()
        _items.clear()
        _monitor.exit()
        return result
    }

    List<T> peek() {
        _monitor.enter()
        List<T> result = _items.copy()
        _monitor.exit()
        return result
    }

    Int size() {
        _monitor.enter()
        Int result = _items.length()
        _monitor.exit()
        return result
    }

    Int batchSize() { return _batchSize }

    void clear() {
        _monitor.enter()
        _items.clear()
        _monitor.exit()
    }

    void close() {
        _monitor.enter()
        if !_closed {
            _closed = true
            _items.clear()
        }
        _monitor.exit()
    }

    Bool isClosed() {
        _monitor.enter()
        Bool result = _closed
        _monitor.exit()
        return result
    }
}
```
