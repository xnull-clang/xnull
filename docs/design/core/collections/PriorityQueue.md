# `PriorityQueue<T>`

| 项 | 值 |
| --- | --- |
| 类型 | `class PriorityQueue<T>` |
| 包 | `xdk.collections` |
| 稳定性 | `stable` |
| 依赖 | `List` |

---

## 1. 定位

以比较器定义优先级的最小堆。

不做：并发、稳定排序、索引堆、可更新优先级。

---

## 2. 设计逻辑

- `lessThan(a,b)` 为 true 表示 a 优先于 b；必须严格弱序。
- push/pop O(log n)；peek O(1)。
- 空 peek/pop 返回 null。
- 不保证相等优先级顺序。
- 非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_heap` | `List<T>` | 二叉堆 |
| `_lessThan` | `Bool(T,T)` | 比较器 |

不变量：父节点不劣于子节点；堆大小 = 元素数。

---

## 4. 生命周期

引用类型；无 close；可 clear。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `PriorityQueue(Bool(T,T) lessThan)` | lessThan | 非 null、严格弱序 | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `length` | 元素数 | 无 | `Int` | 无 |
| `isEmpty` | 是否为空 | 无 | `Bool` | 无 |
| `push` | 插入 | `T value` | `void` | 无 |
| `peek` | 堆顶 | 无 | `T?` | 无 |
| `pop` | 弹出堆顶 | 无 | `T?` | 无 |
| `remove` | 删除值 | `T value` | `Bool` | 无 |
| `contains` | 是否含值 | `T value` | `Bool` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |
| `toList` | 快照 | 无 | `List<T>` | 无 |

---

## 8. 使用的技术

- 二叉最小堆；
- 上浮/下沉；
- 比较器；
- 线性查找删除。

---

## 9. 需要的支撑

- 语言：class、List、泛型 T、Bool、Int；
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

正确：`new PriorityQueue<Int>((a,b)->a<b)`；push 3/1/2，pop 1。  
反例：比较器用 `<=`；null 比较器；依赖相等优先级顺序。

---

## 13. 测试/场景义务

空/单/多；堆序；push/pop；remove/contains；比较器边界；toList 快照。

---

## 14. XNull 伪代码

```xnull
class PriorityQueue<T> {
    List<T> _heap
    Bool(T, T) _lessThan

    PriorityQueue(Bool(T, T) lessThan) {
        if lessThan == null { throw "PriorityQueue: null comparator" }
        _heap = new List<T>()
        _lessThan = lessThan
    }

    Int length() { return _heap.length() }
    Bool isEmpty() { return _heap.isEmpty() }

    void swap(Int left, Int right) {
        T temporary = _heap.get(left)
        _heap.set(left, _heap.get(right))
        _heap.set(right, temporary)
    }

    void siftUp(Int index) {
        while index > 0 {
            Int parent = (index - 1) / 2
            if _lessThan(_heap.get(index), _heap.get(parent)) {
                self.swap(index, parent)
                index = parent
            } else {
                break
            }
        }
    }

    void siftDown(Int index) {
        Int count = _heap.length()
        while true {
            Int left = index * 2 + 1
            Int right = left + 1
            Int best = index
            if left < count && _lessThan(_heap.get(left), _heap.get(best)) {
                best = left
            }
            if right < count && _lessThan(_heap.get(right), _heap.get(best)) {
                best = right
            }
            if best == index { break }
            self.swap(index, best)
            index = best
        }
    }

    void push(T value) {
        _heap.push(value)
        self.siftUp(_heap.length() - 1)
    }

    T? peek() {
        if _heap.isEmpty() { return null }
        return _heap.get(0)
    }

    T? pop() {
        if _heap.isEmpty() { return null }
        T top = _heap.get(0)
        Int last = _heap.length() - 1
        _heap.set(0, _heap.get(last))
        _heap.remove(last)
        if !_heap.isEmpty() {
            self.siftDown(0)
        }
        return top
    }

    Bool remove(T value) {
        Int index = 0
        while index < _heap.length() {
            if _heap.get(index) == value {
                Int last = _heap.length() - 1
                _heap.set(index, _heap.get(last))
                _heap.remove(last)
                if index < _heap.length() {
                    self.siftDown(index)
                    self.siftUp(index)
                }
                return true
            }
            index = index + 1
        }
        return false
    }

    Bool contains(T value) {
        Int index = 0
        while index < _heap.length() {
            if _heap.get(index) == value { return true }
            index = index + 1
        }
        return false
    }

    void clear() {
        _heap.clear()
    }

    List<T> toList() {
        return _heap.copy()
    }
}
```
