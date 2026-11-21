# `Deque<T>`

| 项 | 值 |
| --- | --- |
| 类型 | `class Deque<T>` |
| 包 | `xdk.collections` |
| 稳定性 | `preview` |
| 依赖 | `List` |

---

## 1. 定位

双端队列：两端 push/pop/peek。

不做：并发、阻塞、优先队列。

---

## 2. 设计逻辑

- 首版用 `List<T>` 承载；`pushFront/popFront` 为 O(n)，后端口 O(1)。
- 空 `pop/peek` 返回 null；不抛错。
- 只允许两端操作；不提供随机索引。
- 非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_items` | `List<T>` | 元素 |

不变量：元素顺序 = 前端到后端；非线程安全。

---

## 4. 生命周期

引用类型；无 close；可 clear 重用。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Deque()` | 无 | 空 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `pushFront` | 前端入队 | `T value` | `void` | 无 |
| `pushBack` | 后端入队 | `T value` | `void` | 无 |
| `popFront` | 前端出队 | 无 | `T?` | 无 |
| `popBack` | 后端出队 | 无 | `T?` | 无 |
| `peekFront` | 前端查看 | 无 | `T?` | 无 |
| `peekBack` | 后端查看 | 无 | `T?` | 无 |
| `length` | 元素数 | 无 | `Int` | 无 |
| `isEmpty` | 是否为空 | 无 | `Bool` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |
| `toList` | 快照 | 无 | `List<T>` | 无 |

---

## 8. 使用的技术

- 双端索引；
- 列表前端插入/删除；
- 快照。

---

## 9. 需要的支撑

- 语言：class、List、泛型 T、Int、Bool；
- 运行时：列表操作；
- 接口：`List`。

---

## 10. 依赖的特性/接口/类

`List`。

---

## 11. 所有权与并发

- 持有元素引用；pop 转移。
- `toList` 快照。
- 非线程安全。

---

## 12. 示例与反例

正确：`pushBack("a")`、`pushFront("b")` → `b,a`。  
反例：空 deque pop 期望 panic；依赖随机索引；多任务共享。

---

## 13. 测试/场景义务

两端 push/pop/peek；空；顺序；clear；toList 快照。

---

## 14. XNull 伪代码

```xnull
class Deque<T> {
    List<T> _items

    Deque() {
        _items = new List<T>()
    }

    void pushFront(T value) {
        _items.insert(0, value)
    }

    void pushBack(T value) {
        _items.push(value)
    }

    T? popFront() {
        if _items.isEmpty() { return null }
        return _items.remove(0)
    }

    T? popBack() {
        if _items.isEmpty() { return null }
        return _items.remove(_items.length() - 1)
    }

    T? peekFront() {
        return _items.first()
    }

    T? peekBack() {
        return _items.last()
    }

    Int length() { return _items.length() }
    Bool isEmpty() { return _items.isEmpty() }

    void clear() {
        _items.clear()
    }

    List<T> toList() {
        return _items.copy()
    }
}
```
