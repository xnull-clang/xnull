# `Set<T>`

| 项 | 值 |
| --- | --- |
| 类型 | 语言容器 |
| 包 | `xdk.collections` |
| 稳定性 | `stable` |
| 依赖 | 无 |

---

## 1. 定位

元素唯一的集合；支持成员判断、增删、集合运算。

不做：并发安全、持久化、有序集合（用 `OrderedMap`/排序列表）。

---

## 2. 设计逻辑

- 元素相等规则同 `Map` 键：整数按值、String 按内容、Double 位模式、Bytes/class 按引用。
- `add` 已存在返回 false；`remove` 不存在返回 false。
- `union/intersection/difference` 返回新集合；不修改入参。
- 顺序不承诺；`toList` 快照。
- 非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_items` | 运行时集合 | 元素 |
| `_size` | `Int` | 元素数 |

不变量：元素唯一；size 与元素数一致。

---

## 4. 生命周期

引用类型；无 close；GC 管理。

---

## 5. 构造契约

`Set.of(...)` 编译器脱糖；`Set<T>()` 空集合。

---

## 6. 字段表

见 §3；字段内部。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `length` | 元素数 | 无 | `Int` | 无 |
| `isEmpty` | 是否为空 | 无 | `Bool` | 无 |
| `has` | 是否存在 | `T value` | `Bool` | 无 |
| `add` | 新增 | `T value` | `Bool` | 无 |
| `addAll` | 批量新增 | `List<T> values` | `Int` | null → panic |
| `remove` | 删除 | `T value` | `Bool` | 无 |
| `removeAll` | 批量删除 | `List<T> values` | `Int` | null → panic |
| `retainAll` | 保留交集 | `List<T> values` | `Int` | null → panic |
| `clear` | 清空 | 无 | `void` | 无 |
| `union` | 并集 | `Set<T> other` | `Set<T>` | null → panic |
| `intersection` | 交集 | `Set<T> other` | `Set<T>` | null → panic |
| `difference` | 差集 | `Set<T> other` | `Set<T>` | null → panic |
| `isSubset` | 子集 | `Set<T> other` | `Bool` | null → panic |
| `isSuperset` | 超集 | `Set<T> other` | `Bool` | null → panic |
| `toList` | 快照 | 无 | `List<T>` | 无 |
| `copy` | 副本 | 无 | `Set<T>` | 无 |

---

## 8. 使用的技术

- 哈希集合/快速路径；
- 元素相等；
- 集合运算；
- 快照。

---

## 9. 需要的支撑

- 语言：class/容器、泛型 T、Int、Bool、List；
- 运行时：集合存储/查找；
- 接口：无错误依赖。

---

## 10. 依赖的特性/接口/类

`List`。

---

## 11. 所有权与并发

- 持有元素引用；`remove` 删除。
- `toList` 快照；集合运算返回新集合。
- 非线程安全。

---

## 12. 示例与反例

正确：`Set.of(1,2,2)` 长度 2；`add` 已存在 false。  
反例：可变对象作元素；依赖迭代顺序；遍历时删除。

---

## 13. 测试/场景义务

空/重复/删除；addAll/removeAll/retainAll；union/intersection/difference；子集/超集；快照。

---

## 14. XNull 伪代码

```xnull
class Set<T> {
    SetStorage<T> _items
    Int _size

    Set() {
        _items = new SetStorage<T>()
        _size = 0
    }

    Int length() { return _size }
    Bool isEmpty() { return _size == 0 }

    Bool has(T value) {
        return _items.has(value)
    }

    Bool add(T value) {
        if _items.has(value) {
            return false
        }
        _items.add(value)
        _size = _size + 1
        return true
    }

    Int addAll(List<T> values) {
        if values == null { throw "Set.addAll: null" }
        Int added = 0
        Int index = 0
        while index < values.length() {
            if self.add(values.get(index)) {
                added = added + 1
            }
            index = index + 1
        }
        return added
    }

    Bool remove(T value) {
        if !_items.has(value) {
            return false
        }
        _items.remove(value)
        _size = _size - 1
        return true
    }

    Int removeAll(List<T> values) {
        if values == null { throw "Set.removeAll: null" }
        Int removed = 0
        Int index = 0
        while index < values.length() {
            if self.remove(values.get(index)) {
                removed = removed + 1
            }
            index = index + 1
        }
        return removed
    }

    Int retainAll(List<T> values) {
        if values == null { throw "Set.retainAll: null" }
        Set<T> keep = new Set<T>()
        Int index = 0
        while index < values.length() {
            keep.add(values.get(index))
            index = index + 1
        }
        List<T> current = self.toList()
        Int removed = 0
        index = 0
        while index < current.length() {
            if !keep.has(current.get(index)) {
                self.remove(current.get(index))
                removed = removed + 1
            }
            index = index + 1
        }
        return removed
    }

    void clear() {
        _items.clear()
        _size = 0
    }

    Set<T> union(Set<T> other) {
        if other == null { throw "Set.union: null" }
        Set<T> result = self.copy()
        result.addAll(other.toList())
        return result
    }

    Set<T> intersection(Set<T> other) {
        if other == null { throw "Set.intersection: null" }
        Set<T> result = new Set<T>()
        List<T> values = self.toList()
        Int index = 0
        while index < values.length() {
            if other.has(values.get(index)) {
                result.add(values.get(index))
            }
            index = index + 1
        }
        return result
    }

    Set<T> difference(Set<T> other) {
        if other == null { throw "Set.difference: null" }
        Set<T> result = new Set<T>()
        List<T> values = self.toList()
        Int index = 0
        while index < values.length() {
            if !other.has(values.get(index)) {
                result.add(values.get(index))
            }
            index = index + 1
        }
        return result
    }

    Bool isSubset(Set<T> other) {
        if other == null { throw "Set.isSubset: null" }
        List<T> values = self.toList()
        Int index = 0
        while index < values.length() {
            if !other.has(values.get(index)) { return false }
            index = index + 1
        }
        return true
    }

    Bool isSuperset(Set<T> other) {
        if other == null { throw "Set.isSuperset: null" }
        return other.isSubset(self)
    }

    List<T> toList() {
        return _items.toList()
    }

    Set<T> copy() {
        Set<T> result = new Set<T>()
        result.addAll(self.toList())
        return result
    }
}
```

> `SetStorage` 是运行时集合原语。
