# `Queue<T>`

| 项 | 值 |
| --- | --- |
| 类型 | `class Queue<T>` |
| 包 | `xdk.collections` |
| 稳定性 | `preview` |
| 依赖 | `List` |

---

## 1. 定位

先进先出队列：enqueue/dequeue/peek。

不做：并发/阻塞/有界队列（`xdk.queue`）、优先队列。

---

## 2. 设计逻辑

- 首版用 `List<T>` + `_head` 索引；dequeue 后 head 前进，偶尔压缩。
- 空 dequeue/peek 返回 null。
- 非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_items` | `List<T>` | 元素 |
| `_head` | `Int` | 队首索引 |

不变量：0 ≤ head ≤ items.length；有效元素 `[head, length)`。

---

## 4. 生命周期

引用类型；无 close；可 clear。

---

## 5. 构造契约

`Queue()` 空队列。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `enqueue` | 入队 | `T value` | `void` | 无 |
| `dequeue` | 出队 | 无 | `T?` | 无 |
| `peek` | 看队首 | 无 | `T?` | 无 |
| `length` | 元素数 | 无 | `Int` | 无 |
| `isEmpty` | 是否为空 | 无 | `Bool` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |
| `toList` | 快照 | 无 | `List<T>` | 无 |

---

## 8. 使用的技术

- 队首索引；
- 惰性压缩；
- FIFO；
- 快照。

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

持有元素引用；dequeue 转移；非线程安全。

---

## 12. 示例与反例

正确：enqueue 1/2，dequeue 1，peek 2。  
反例：空 dequeue 期望 panic；用队列做栈；长期不压缩导致内存增长。

---

## 13. 测试/场景义务

空/单/多；FIFO；head 压缩；clear；toList 顺序。

---

## 14. XNull 伪代码

```xnull
class Queue<T> {
    List<T> _items
    Int _head

    Queue() {
        _items = new List<T>()
        _head = 0
    }

    void enqueue(T value) {
        _items.push(value)
    }

    T? dequeue() {
        if _head >= _items.length() { return null }
        T value = _items.get(_head)
        _head = _head + 1
        if _head > 32 && _head * 2 > _items.length() {
            _items = _items.slice(_head, _items.length())
            _head = 0
        }
        return value
    }

    T? peek() {
        if _head >= _items.length() { return null }
        return _items.get(_head)
    }

    Int length() { return _items.length() - _head }
    Bool isEmpty() { return _head >= _items.length() }

    void clear() {
        _items.clear()
        _head = 0
    }

    List<T> toList() {
        return _items.slice(_head, _items.length())
    }
}
```
