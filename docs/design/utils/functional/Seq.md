# `Seq`

| 项 | 值 |
| --- | --- |
| 类型 | `class Seq<T>` |
| 包 | `xdk.functional` |
| 稳定性 | `preview` |
| 依赖 | `List`、`Set`、`Map`、`Pair` |

---

## 1. 定位

eager 集合管线：map/filter/flatMap、去重、排序、切片、分组、窗口、zip、聚合。

不做：惰性求值（X）、并行管线（X）、无限序列（X）、响应式流。

---

## 2. 设计逻辑

- 构造时复制输入列表；所有变换返回新 `Seq`，不修改入参。
- eager：每个方法立即遍历并生成结果；没有隐藏迭代器状态。
- 元素顺序稳定：`map/filter/flatMap/take/skip` 保持原顺序；`sorted` 由比较器决定。
- 相等语义使用 `==`；`distinct`/`toSet` 对类按引用相等，除非类型自定义值相等。
- 泛型方法按调用处推断；`groupBy` 的键必须非 null 且可哈希。
- 无 close；不可变快照；可共享（元素本身可能可变）。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_items` | `List<T>` | 私有快照 |

不变量：`_items` 非 null；构造后不被外部修改；方法不原地修改 `_items`。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可跨任务共享读取。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Seq(List<T> items)` | items | 非 null | null → panic |

应用可用 `Seq.of`/`Seq.empty`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `of` | 包装列表 | `List<T> items` | `Seq<T>` | null → panic |
| `empty` | 空序列 | 无 | `Seq<T>` | 无 |
| `length` | 元素数 | 无 | `Int` | 无 |
| `isEmpty` | 是否为空 | 无 | `Bool` | 无 |
| `get` | 索引读 | `Int index` | `T` | 越界 → panic |
| `map<R>` | 映射 | `R(T) transform` | `Seq<R>` | null → panic |
| `filter` | 过滤 | `Bool(T) predicate` | `Seq<T>` | null → panic |
| `flatMap<R>` | 映射并展平 | `List<R>(T) transform` | `Seq<R>` | null → panic |
| `distinct` | 去重 | 无 | `Seq<T>` | 无 |
| `sorted` | 排序 | `Int(T,T) comparator` | `Seq<T>` | null → panic |
| `reversed` | 逆序 | 无 | `Seq<T>` | 无 |
| `take` | 前 n 个 | `Int count` | `Seq<T>` | 负数 → panic |
| `skip` | 跳过 n 个 | `Int count` | `Seq<T>` | 负数 → panic |
| `takeWhile` | 前缀满足 | `Bool(T) predicate` | `Seq<T>` | null → panic |
| `dropWhile` | 丢弃前缀 | `Bool(T) predicate` | `Seq<T>` | null → panic |
| `chunk` | 固定分块 | `Int size` | `Seq<List<T>>` | ≤0 → panic |
| `window` | 滑动窗口 | `Int size` | `Seq<List<T>>` | ≤0 → panic |
| `zip<R>` | 配对 | `Seq<R> other` | `Seq<Pair<T,R>>` | null → panic |
| `groupBy<K>` | 分组 | `K(T) keySelector` | `Map<K,List<T>>` | null 键/selector → panic |
| `partition` | 二分 | `Bool(T) predicate` | `Pair<List<T>,List<T>>` | null → panic |
| `forEach` | 遍历 | `void(T) action` | `Unit` | null → panic |
| `reduce` | 归约 | `T initial, T(T,T) accumulator` | `T` | null → panic |
| `anyMatch` | 任一满足 | `Bool(T) predicate` | `Bool` | null → panic |
| `allMatch` | 全部满足 | `Bool(T) predicate` | `Bool` | null → panic |
| `noneMatch` | 全部不满足 | `Bool(T) predicate` | `Bool` | null → panic |
| `firstOrNull` | 首元素/无 | 无 | `T?` | 无 |
| `count` | 满足数量 | `Bool(T) predicate` | `Int` | null → panic |
| `toList` | 列表快照 | 无 | `List<T>` | 无 |
| `toSet` | 集合快照 | 无 | `Set<T>` | 无 |
| `join` | 字符串连接 | `String separator, String(T) stringify` | `String` | null → panic |

说明：

- `flatMap` 的 transform 返回 null 视为合同错误。
- `chunk` 最后一块可短于 size；`window` 不足 size 时返回空。
- `zip` 以较短序列为准。
- `groupBy` 的值列表保持遇到顺序；键顺序不承诺。
- `join` 对空序列返回空串，不返回分隔符。

---

## 8. 使用的技术

- 泛型类/泛型方法；
- 防御性复制；
- 哈希集合去重；
- 稳定遍历；
- 比较器排序；
- 短路聚合。

---

## 9. 需要的支撑

- 语言：class、泛型、List、Set、Map、Pair、函数类型；
- 运行时：`sort`（集合排序）；
- 接口：无。

---

## 10. 依赖的特性/接口/类

`List`、`Set`、`Map`、`Pair`、`sort`。

---

## 11. 所有权与并发

不可变快照；可共享；元素引用共享；无资源；并发读取安全（元素自身可变性由调用方负责）。

---

## 12. 示例与反例

正确：`Seq.of(rows).filter((Row r) -> r.active).map((Row r) -> r.name).toList()`。  
反例：期望 `map` 原地修改；在 `groupBy` 返回 null 键；依赖未定义的键顺序；并发修改元素同时遍历。

---

## 13. 测试/场景义务

空/单/多元素；map/filter/flatMap；去重（引用/值）；排序稳定性；take/skip 边界；takeWhile/dropWhile；chunk/window；zip 长短；groupBy 顺序；partition；reduce 空/非空；短路；firstOrNull；toList 副本；join。

---

## 14. XNull 伪代码

```xnull
class Seq<T> {
    final List<T> _items

    Seq(List<T> items) {
        if items == null { throw "Seq: null items" }
        _items = items.copy()
    }

    static Seq<T> of(List<T> items) {
        return new Seq<T>(items)
    }

    static Seq<T> empty() {
        return new Seq<T>([])
    }

    Int length() { return _items.length() }
    Bool isEmpty() { return _items.isEmpty() }

    T get(Int index) {
        if index < 0 || index >= _items.length() {
            throw "Seq.get: index out of range"
        }
        return _items.get(index)
    }

    Seq<R> map<R>(R(T) transform) {
        if transform == null { throw "Seq.map: null transform" }
        List<R> result = []
        Int index = 0
        while index < _items.length() {
            result.push(transform(_items.get(index)))
            index = index + 1
        }
        return new Seq<R>(result)
    }

    Seq<T> filter(Bool(T) predicate) {
        if predicate == null { throw "Seq.filter: null predicate" }
        List<T> result = []
        Int index = 0
        while index < _items.length() {
            T item = _items.get(index)
            if predicate(item) { result.push(item) }
            index = index + 1
        }
        return new Seq<T>(result)
    }

    Seq<R> flatMap<R>(List<R>(T) transform) {
        if transform == null { throw "Seq.flatMap: null transform" }
        List<R> result = []
        Int index = 0
        while index < _items.length() {
            List<R> part = transform(_items.get(index))
            if part == null { throw "Seq.flatMap: transform returned null" }
            Int inner = 0
            while inner < part.length() {
                result.push(part.get(inner))
                inner = inner + 1
            }
            index = index + 1
        }
        return new Seq<R>(result)
    }

    Seq<T> distinct() {
        Set<T> seen = new Set<T>()
        List<T> result = []
        Int index = 0
        while index < _items.length() {
            T item = _items.get(index)
            if !seen.has(item) {
                seen.add(item)
                result.push(item)
            }
            index = index + 1
        }
        return new Seq<T>(result)
    }

    Seq<T> sorted(Int(T,T) comparator) {
        if comparator == null { throw "Seq.sorted: null comparator" }
        List<T> result = self.toList()
        sort(result, comparator)
        return new Seq<T>(result)
    }

    Seq<T> reversed() {
        List<T> result = []
        Int index = _items.length() - 1
        while index >= 0 {
            result.push(_items.get(index))
            index = index - 1
        }
        return new Seq<T>(result)
    }

    Seq<T> take(Int count) {
        if count < 0 { throw "Seq.take: negative count" }
        List<T> result = []
        Int index = 0
        while index < count && index < _items.length() {
            result.push(_items.get(index))
            index = index + 1
        }
        return new Seq<T>(result)
    }

    Seq<T> skip(Int count) {
        if count < 0 { throw "Seq.skip: negative count" }
        List<T> result = []
        Int index = count
        while index < _items.length() {
            result.push(_items.get(index))
            index = index + 1
        }
        return new Seq<T>(result)
    }

    Seq<T> takeWhile(Bool(T) predicate) {
        if predicate == null { throw "Seq.takeWhile: null predicate" }
        List<T> result = []
        Int index = 0
        while index < _items.length() {
            T item = _items.get(index)
            if !predicate(item) { return new Seq<T>(result) }
            result.push(item)
            index = index + 1
        }
        return new Seq<T>(result)
    }

    Seq<T> dropWhile(Bool(T) predicate) {
        if predicate == null { throw "Seq.dropWhile: null predicate" }
        List<T> result = []
        Bool dropping = true
        Int index = 0
        while index < _items.length() {
            T item = _items.get(index)
            if dropping && !predicate(item) { dropping = false }
            if !dropping { result.push(item) }
            index = index + 1
        }
        return new Seq<T>(result)
    }

    Seq<List<T>> chunk(Int size) {
        if size <= 0 { throw "Seq.chunk: size must be positive" }
        List<List<T>> result = []
        Int index = 0
        while index < _items.length() {
            List<T> part = []
            Int inner = 0
            while inner < size && index < _items.length() {
                part.push(_items.get(index))
                inner = inner + 1
                index = index + 1
            }
            result.push(part)
        }
        return new Seq<List<T>>(result)
    }

    Seq<List<T>> window(Int size) {
        if size <= 0 { throw "Seq.window: size must be positive" }
        List<List<T>> result = []
        if size > _items.length() { return new Seq<List<T>>(result) }
        Int start = 0
        while start <= _items.length() - size {
            List<T> part = []
            Int inner = 0
            while inner < size {
                part.push(_items.get(start + inner))
                inner = inner + 1
            }
            result.push(part)
            start = start + 1
        }
        return new Seq<List<T>>(result)
    }

    Seq<Pair<T, R>> zip<R>(Seq<R> other) {
        if other == null { throw "Seq.zip: null other" }
        List<Pair<T, R>> result = []
        Int length = _items.length()
        if other.length() < length { length = other.length() }
        Int index = 0
        while index < length {
            result.push(new Pair<T, R>(_items.get(index), other.get(index)))
            index = index + 1
        }
        return new Seq<Pair<T, R>>(result)
    }

    Map<K, List<T>> groupBy<K>(K(T) keySelector) {
        if keySelector == null { throw "Seq.groupBy: null selector" }
        Map<K, List<T>> groups = new Map<K, List<T>>()
        Int index = 0
        while index < _items.length() {
            T item = _items.get(index)
            K key = keySelector(item)
            if key == null { throw "Seq.groupBy: null key" }
            if groups.has(key) {
                groups.get(key).push(item)
            } else {
                List<T> bucket = []
                bucket.push(item)
                groups.put(key, bucket)
            }
            index = index + 1
        }
        return groups
    }

    Pair<List<T>, List<T>> partition(Bool(T) predicate) {
        if predicate == null { throw "Seq.partition: null predicate" }
        List<T> matching = []
        List<T> rest = []
        Int index = 0
        while index < _items.length() {
            T item = _items.get(index)
            if predicate(item) {
                matching.push(item)
            } else {
                rest.push(item)
            }
            index = index + 1
        }
        return new Pair<List<T>, List<T>>(matching, rest)
    }

    Unit forEach(void(T) action) {
        if action == null { throw "Seq.forEach: null action" }
        Int index = 0
        while index < _items.length() {
            action(_items.get(index))
            index = index + 1
        }
        return unit
    }

    T reduce(T initial, T(T, T) accumulator) {
        if accumulator == null { throw "Seq.reduce: null accumulator" }
        T result = initial
        Int index = 0
        while index < _items.length() {
            result = accumulator(result, _items.get(index))
            index = index + 1
        }
        return result
    }

    Bool anyMatch(Bool(T) predicate) {
        if predicate == null { throw "Seq.anyMatch: null predicate" }
        Int index = 0
        while index < _items.length() {
            if predicate(_items.get(index)) { return true }
            index = index + 1
        }
        return false
    }

    Bool allMatch(Bool(T) predicate) {
        if predicate == null { throw "Seq.allMatch: null predicate" }
        Int index = 0
        while index < _items.length() {
            if !predicate(_items.get(index)) { return false }
            index = index + 1
        }
        return true
    }

    Bool noneMatch(Bool(T) predicate) {
        return !self.anyMatch(predicate)
    }

    T? firstOrNull() {
        if _items.isEmpty() { return null }
        return _items.get(0)
    }

    Int count(Bool(T) predicate) {
        if predicate == null { throw "Seq.count: null predicate" }
        Int result = 0
        Int index = 0
        while index < _items.length() {
            if predicate(_items.get(index)) { result = result + 1 }
            index = index + 1
        }
        return result
    }

    List<T> toList() { return _items.copy() }

    Set<T> toSet() {
        Set<T> result = new Set<T>()
        Int index = 0
        while index < _items.length() {
            result.add(_items.get(index))
            index = index + 1
        }
        return result
    }

    String join(String separator, String(T) stringify) {
        if separator == null || stringify == null {
            throw "Seq.join: null argument"
        }
        String result = ""
        Int index = 0
        while index < _items.length() {
            if index > 0 { result = result + separator }
            String text = stringify(_items.get(index))
            if text == null { throw "Seq.join: stringify returned null" }
            result = result + text
            index = index + 1
        }
        return result
    }
}
```
