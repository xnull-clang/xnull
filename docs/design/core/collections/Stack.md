# `Stack<T>`

| 项 | 值 |
| --- | --- |
| 类型 | `class Stack<T>` |
| 包 | `xdk.collections` |
| 稳定性 | `preview` |
| 依赖 | `List` |

---

## 1. 定位

后进先出栈：push/pop/peek。

不做：并发、阻塞、优先。

---

## 2. 设计逻辑

- 用 `List<T>` 末尾作为栈顶；push/pop/peek O(1) 摊还。
- 空 pop/peek 返回 null。
- 非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_items` | `List<T>` | 栈元素；末尾为顶 |

不变量：栈顶 = 最后元素；非线程安全。

---

## 4. 生命周期

引用类型；无 close；可 clear。

---

## 5. 构造契约

`Stack()` 空栈。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `push` | 入栈 | `T value` | `void` | 无 |
| `pop` | 出栈 | 无 | `T?` | 无 |
| `peek` | 看栈顶 | 无 | `T?` | 无 |
| `length` | 元素数 | 无 | `Int` | 无 |
| `isEmpty` | 是否为空 | 无 | `Bool` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |
| `toList` | 快照（底→顶） | 无 | `List<T>` | 无 |

---

## 8. 使用的技术

- 动态数组末尾；
- LIFO；
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

持有元素引用；pop 转移；非线程安全。

---

## 12. 示例与反例

正确：push 1/2，pop 2，peek 1。  
反例：空 pop 期望 panic；用栈做队列。

---

## 13. 测试/场景义务

空/单/多；LIFO；clear；toList 顺序；null 元素限制。

---

## 14. XNull 伪代码

```xnull
class Stack<T> {
    List<T> _items

    Stack() {
        _items = new List<T>()
    }

    void push(T value) {
        _items.push(value)
    }

    T? pop() {
        if _items.isEmpty() { return null }
        return _items.remove(_items.length() - 1)
    }

    T? peek() {
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
