# `RingBuffer<T>`

| 项 | 值 |
| --- | --- |
| 类型 | `class RingBuffer<T>` |
| 包 | `xdk.collections` |
| 稳定性 | `stable` |
| 依赖 | `List` |

---

## 1. 定位

固定容量环形缓冲；满时拒绝写入，不覆盖。

不做：并发、阻塞、动态扩容。

---

## 2. 设计逻辑

- 容量构造后不变；`capacity > 0`。
- 满时 `push` 返回 false，不写入；不提供覆盖模式。
- `pop/peek` 取最旧；空返回 null。
- `drain` 取全部并清空。
- 非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_capacity` | `Int` | >0 |
| `_items` | `List<T>` | 元素；长度 ≤ capacity |

不变量：0 ≤ items.length ≤ capacity；capacity 不变。

---

## 4. 生命周期

引用类型；无 close；可 clear。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `RingBuffer(Int capacity)` | capacity | >0 | ≤0 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `length` | 元素数 | 无 | `Int` | 无 |
| `capacity` | 容量 | 无 | `Int` | 无 |
| `isEmpty` | 是否为空 | 无 | `Bool` | 无 |
| `isFull` | 是否已满 | 无 | `Bool` | 无 |
| `push` | 写入 | `T value` | `Bool` | 无 |
| `pop` | 取最旧 | 无 | `T?` | 无 |
| `peek` | 看最旧 | 无 | `T?` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |
| `toList` | 快照 | 无 | `List<T>` | 无 |
| `drain` | 取全部并清空 | 无 | `List<T>` | 无 |

---

## 8. 使用的技术

- 环形索引（首版用 List 承载）；
- 固定容量；
- FIFO；
- 快照/转移。

---

## 9. 需要的支撑

- 语言：class、List、泛型 T、Int、Bool；
- 运行时：列表；
- 接口：`List`。

---

## 10. 依赖的特性/接口/类

`List`。

---

## 11. 所有权与并发

持有元素引用；pop/drain 转移；非线程安全。

---

## 12. 示例与反例

正确：容量 2，push 1/2 成功，push 3 false；pop 1。  
反例：期望满时覆盖；capacity 0；多任务共享。

---

## 13. 测试/场景义务

空/满/边界；push false 不写入；peek/pop；drain；clear；capacity 不变。

---

## 14. XNull 伪代码

```xnull
class RingBuffer<T> {
    final Int _capacity
    List<T> _items

    RingBuffer(Int capacity) {
        if capacity <= 0 {
            throw "RingBuffer: capacity must be positive"
        }
        _capacity = capacity
        _items = new List<T>()
    }

    Int length() { return _items.length() }
    Int capacity() { return _capacity }
    Bool isEmpty() { return _items.isEmpty() }
    Bool isFull() { return _items.length() >= _capacity }

    Bool push(T value) {
        if self.isFull() {
            return false
        }
        _items.push(value)
        return true
    }

    T? pop() {
        if self.isEmpty() { return null }
        return _items.remove(0)
    }

    T? peek() {
        return _items.first()
    }

    void clear() {
        _items.clear()
    }

    List<T> toList() {
        return _items.copy()
    }

    List<T> drain() {
        List<T> result = _items.copy()
        _items.clear()
        return result
    }
}
```
