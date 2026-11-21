# `List<T>`

| 项 | 值 |
| --- | --- |
| 类型 | 语言容器 |
| 包 | `xdk.collections` |
| 稳定性 | `stable` |
| 依赖 | `xdk.errors` |

---

## 1. 定位

有序、可重复、按索引访问的序列。支持追加/插入/删除/替换/排序/反转/切片。

不做：并发安全、持久化、惰性迭代。

---

## 2. 设计逻辑

- 动态数组；`length` 与元素数一致。
- 索引合法域 `[0,length-1]`；insert 允许 `index == length`。
- unchecked 越界 panic；checked 返回 `Result`。
- 遍历期间禁止结构性修改；`set` 允许。
- `sortBy` 原地稳定；`copy`/`slice` 返回新列表。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_items` | 运行时数组 | 元素 |
| `_length` | `Int` | 元素数 |

不变量：0 ≤ length；元素连续；非线程安全。

---

## 4. 生命周期

引用类型；无 close；GC 管理；可跨任务共享但需外部同步。

---

## 5. 构造契约

编译器字面量 `[...]` 生成；也可 `List<T>()` 为空。

---

## 6. 字段表

见 §3；字段内部。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `length` | 元素数 | 无 | `Int` | 无 |
| `isEmpty` | 是否为空 | 无 | `Bool` | 无 |
| `get` | 索引读 | `Int index` | `T` | 越界 → panic |
| `tryGet` | checked 读 | `Int index` | `Result<T, Error>` | `InvalidArgument` |
| `first` | 首元素 | 无 | `T?` | 无 |
| `last` | 尾元素 | 无 | `T?` | 无 |
| `set` | 索引写 | `Int index, T value` | `void` | 越界 → panic |
| `trySet` | checked 写 | 同上 | `Result<Unit, Error>` | `InvalidArgument` |
| `push` | 末尾追加 | `T value` | `void` | 无 |
| `addAll` | 追加多个 | `List<T> values` | `void` | null → panic |
| `insert` | 插入 | `Int index, T value` | `void` | 越界 → panic |
| `tryInsert` | checked 插入 | 同上 | `Result<Unit, Error>` | `InvalidArgument` |
| `insertAll` | 插入多个 | `Int index, List<T> values` | `void` | 越界/null → panic |
| `remove` | 删除并返回 | `Int index` | `T` | 越界 → panic |
| `tryRemove` | checked 删除 | `Int index` | `Result<T, Error>` | `InvalidArgument` |
| `removeValue` | 删除首个值 | `T value` | `Bool` | 无 |
| `removeIf` | 条件删除 | `Bool(T) predicate` | `Int` | null → panic |
| `retainIf` | 条件保留 | `Bool(T) predicate` | `Int` | null → panic |
| `clear` | 清空 | 无 | `void` | 无 |
| `indexOf` | 首次下标 | `T value` | `Int` | 无（-1） |
| `lastIndexOf` | 末次下标 | `T value` | `Int` | 无（-1） |
| `contains` | 是否包含 | `T value` | `Bool` | 无 |
| `containsAll` | 是否包含全部 | `List<T> values` | `Bool` | null → panic |
| `reverse` | 原地反转 | 无 | `void` | 无 |
| `sortBy` | 原地稳定排序 | `Bool(T,T) lessThan` | `void` | null → panic |
| `copy` | 副本 | 无 | `List<T>` | 无 |
| `slice` | 子列表副本 | `Int start, Int end` | `List<T>` | 无（钳制） |
| `sublist` | 子列表副本 | `Int start, Int end` | `List<T>` | 越界 → panic |
| `fill` | 填充 | `T value` | `void` | 无 |
| `swap` | 交换 | `Int left, Int right` | `void` | 越界 → panic |
| `join` | 拼接 | `String separator` | `String` | 无（仅 String 元素） |
| `min` | 最小 | `Int(T,T) compare` | `T?` | 无 |
| `max` | 最大 | `Int(T,T) compare` | `T?` | 无 |
| `toArray` | 数组副本 | 无 | `T[]` | 无 |

---

## 8. 使用的技术

- 动态数组；
- 索引边界；
- 插入/删除搬移；
- 原地稳定排序；
- 快照/副本。

---

## 9. 需要的支撑

- 语言：class/容器、 Int、Bool、String、Result、数组；
- 运行时：数组分配/扩容；
- 接口：`Error`、`InvalidArgument`。

---

## 10. 依赖的特性/接口/类

`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

- 容器持有元素引用；`remove` 转移所有权。
- `copy` 浅复制；元素引用共享。
- 非线程安全。

---

## 12. 示例与反例

正确：`values.push(4)`；`tryGet(10)` 返回 Err；`slice` 副本独立。  
反例：遍历时 remove；用 get 读外部下标；把 List 当值类型。

---

## 13. 测试/场景义务

空/单/多；push/insert/remove；checked 越界；indexOf/lastIndexOf；reverse/sortBy；copy/slice 独立性；遍历修改。

---

## 14. XNull 伪代码

```xnull
class List<T> {
    T[] _items
    Int _length

    List() {
        _items = new T[0]
        _length = 0
    }

    Int length() { return _length }
    Bool isEmpty() { return _length == 0 }

    T get(Int index) {
        if index < 0 || index >= _length {
            throw "List.get: out of range"
        }
        return _items[index]
    }

    Result<T, Error> tryGet(Int index) {
        if index < 0 || index >= _length {
            return Err(new BasicError(ErrorKind.InvalidArgument, "index out of range"))
        }
        return Ok(_items[index])
    }

    T? first() {
        if _length == 0 { return null }
        return _items[0]
    }

    T? last() {
        if _length == 0 { return null }
        return _items[_length - 1]
    }

    void set(Int index, T value) {
        if index < 0 || index >= _length {
            throw "List.set: out of range"
        }
        _items[index] = value
    }

    Result<Unit, Error> trySet(Int index, T value) {
        if index < 0 || index >= _length {
            return Err(new BasicError(ErrorKind.InvalidArgument, "index out of range"))
        }
        _items[index] = value
        return Ok(unit)
    }

    void push(T value) {
        if _length == _items.length() {
            _items = growArray(_items, _length + 1)
        }
        _items[_length] = value
        _length = _length + 1
    }

    void addAll(List<T> values) {
        if values == null { throw "List.addAll: null" }
        Int index = 0
        while index < values.length() {
            self.push(values.get(index))
            index = index + 1
        }
    }

    void insert(Int index, T value) {
        if index < 0 || index > _length {
            throw "List.insert: out of range"
        }
        if _length == _items.length() {
            _items = growArray(_items, _length + 1)
        }
        Int position = _length
        while position > index {
            _items[position] = _items[position - 1]
            position = position - 1
        }
        _items[index] = value
        _length = _length + 1
    }

    T remove(Int index) {
        if index < 0 || index >= _length {
            throw "List.remove: out of range"
        }
        T value = _items[index]
        Int position = index
        while position < _length - 1 {
            _items[position] = _items[position + 1]
            position = position + 1
        }
        _length = _length - 1
        return value
    }

    Bool removeValue(T value) {
        Int index = self.indexOf(value)
        if index < 0 { return false }
        self.remove(index)
        return true
    }

    Int removeIf(Bool(T) predicate) {
        if predicate == null { throw "List.removeIf: null" }
        Int removed = 0
        Int index = 0
        while index < _length {
            if predicate(_items[index]) {
                self.remove(index)
                removed = removed + 1
            } else {
                index = index + 1
            }
        }
        return removed
    }

    Int retainIf(Bool(T) predicate) {
        return self.removeIf((T value) -> !predicate(value))
    }

    void clear() {
        _length = 0
    }

    Int indexOf(T value) {
        Int index = 0
        while index < _length {
            if _items[index] == value { return index }
            index = index + 1
        }
        return -1
    }

    Int lastIndexOf(T value) {
        Int index = _length - 1
        while index >= 0 {
            if _items[index] == value { return index }
            index = index - 1
        }
        return -1
    }

    Bool contains(T value) {
        return self.indexOf(value) >= 0
    }

    void reverse() {
        Int left = 0
        Int right = _length - 1
        while left < right {
            T temporary = _items[left]
            _items[left] = _items[right]
            _items[right] = temporary
            left = left + 1
            right = right - 1
        }
    }

    void sortBy(Bool(T, T) lessThan) {
        if lessThan == null { throw "List.sortBy: null" }
        Int index = 1
        while index < _length {
            T value = _items[index]
            Int previous = index - 1
            while previous >= 0 && lessThan(value, _items[previous]) {
                _items[previous + 1] = _items[previous]
                previous = previous - 1
            }
            _items[previous + 1] = value
            index = index + 1
        }
    }

    List<T> copy() {
        List<T> result = new List<T>()
        Int index = 0
        while index < _length {
            result.push(_items[index])
            index = index + 1
        }
        return result
    }

    List<T> slice(Int start, Int end) {
        Int from = start
        Int to = end
        if from < 0 { from = 0 }
        if to > _length { to = _length }
        if from > to { from = to }
        List<T> result = new List<T>()
        Int index = from
        while index < to {
            result.push(_items[index])
            index = index + 1
        }
        return result
    }

    List<T> sublist(Int start, Int end) {
        if start < 0 || end > _length || start > end {
            throw "List.sublist: out of range"
        }
        return self.slice(start, end)
    }

    void fill(T value) {
        Int index = 0
        while index < _length {
            _items[index] = value
            index = index + 1
        }
    }

    void swap(Int left, Int right) {
        if left < 0 || right < 0 || left >= _length || right >= _length {
            throw "List.swap: out of range"
        }
        T temporary = _items[left]
        _items[left] = _items[right]
        _items[right] = temporary
    }

    String join(String separator) {
        String result = ""
        Int index = 0
        while index < _length {
            if index > 0 { result = result + separator }
            result = result + str(_items[index])
            index = index + 1
        }
        return result
    }

    T? min(Int(T, T) compare) {
        if _length == 0 { return null }
        T best = _items[0]
        Int index = 1
        while index < _length {
            if compare(_items[index], best) < 0 {
                best = _items[index]
            }
            index = index + 1
        }
        return best
    }

    T? max(Int(T, T) compare) {
        if _length == 0 { return null }
        T best = _items[0]
        Int index = 1
        while index < _length {
            if compare(_items[index], best) > 0 {
                best = _items[index]
            }
            index = index + 1
        }
        return best
    }

    T[] toArray() {
        T[] result = new T[_length]
        Int index = 0
        while index < _length {
            result[index] = _items[index]
            index = index + 1
        }
        return result
    }
}
```

> `growArray` 是运行时数组扩容原语，不是 XDK 公共类型。
