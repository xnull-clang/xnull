# `BTreeMap<V>`

| 项 | 值 |
| --- | --- |
| 类型 | `class BTreeMap<V>` |
| 包 | `xdk.collections` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

`Int` 键、按键升序维护的映射；支持 floor/ceiling/lower/higher/range。

不做：真正 B 树复杂度（首版有序数组）、任意 K、并发。

---

## 2. 设计逻辑

- keys 升序、values 平行；二分查找 O(log n)，插入/删除 O(n)。
- `put` 已存在替换值；新键插入有序位置。
- `floorKey/ceilingKey/lowerKey/higherKey` 返回 nullable。
- `range(from,to)` 返回半开区间快照。
- 非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_keys` | `List<Int>` | 升序键 |
| `_values` | `List<V>` | 对应值 |

不变量：keys 升序且唯一；keys.length = values.length。

---

## 4. 生命周期

引用类型；无 close；可 clear。

---

## 5. 构造契约

`BTreeMap()` 空映射。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `length` | 键数 | 无 | `Int` | 无 |
| `isEmpty` | 是否为空 | 无 | `Bool` | 无 |
| `has` | 是否存在 | `Int key` | `Bool` | 无 |
| `get` | 取值 | `Int key` | `V?` | 无 |
| `getOr` | 取值/兜底 | `Int key, V fallback` | `V` | 无 |
| `put` | 插入/替换 | `Int key, V value` | `Bool` | 无 |
| `remove` | 删除 | `Int key` | `Bool` | 无 |
| `keys` | 键快照 | 无 | `List<Int>` | 无 |
| `values` | 值快照 | 无 | `List<V>` | 无 |
| `entries` | 条目快照 | 无 | `List<IntPair>` | 无 |
| `floorKey` | ≤key | `Int key` | `Int?` | 无 |
| `ceilingKey` | ≥key | `Int key` | `Int?` | 无 |
| `lowerKey` | <key | `Int key` | `Int?` | 无 |
| `higherKey` | >key | `Int key` | `Int?` | 无 |
| `range` | 区间快照 | `Int from, Int to` | `List<IntPair>` | 无 |
| `descendingKeys` | 降序键 | 无 | `List<Int>` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |

---

## 8. 使用的技术

- 有序数组；
- 二分下界；
- 区间扫描；
- 快照。

---

## 9. 需要的支撑

- 语言：class、List、Int、泛型 V、Bool；
- 运行时：列表插入/删除；
- 接口：`IntPair`。

---

## 10. 依赖的特性/接口/类

`IntPair`、`List`。

---

## 11. 所有权与并发

持有值引用；非线程安全；快照。

---

## 12. 示例与反例

正确：put 3,1,2 → keys 1,2,3；floorKey(2)=2。  
反例：期望 O(log n) 插入；可变键（Int）；遍历时修改。

---

## 13. 测试/场景义务

升序；替换；删除；floor/ceiling/lower/higher；range；descendingKeys；空边界。

---

## 14. XNull 伪代码

```xnull
class BTreeMap<V> {
    List<Int> _keys
    List<V> _values

    BTreeMap() {
        _keys = new List<Int>()
        _values = new List<V>()
    }

    Int lowerBound(Int key) {
        Int low = 0
        Int high = _keys.length()
        while low < high {
            Int middle = low + (high - low) / 2
            if _keys.get(middle) < key {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    Int length() { return _keys.length() }
    Bool isEmpty() { return _keys.isEmpty() }

    Bool has(Int key) {
        Int index = self.lowerBound(key)
        return index < _keys.length() && _keys.get(index) == key
    }

    V? get(Int key) {
        Int index = self.lowerBound(key)
        if index >= _keys.length() || _keys.get(index) != key {
            return null
        }
        return _values.get(index)
    }

    V getOr(Int key, V fallback) {
        V? value = self.get(key)
        if value == null { return fallback }
        return value
    }

    Bool put(Int key, V value) {
        Int index = self.lowerBound(key)
        if index < _keys.length() && _keys.get(index) == key {
            _values.set(index, value)
            return true
        }
        _keys.insert(index, key)
        _values.insert(index, value)
        return false
    }

    Bool remove(Int key) {
        Int index = self.lowerBound(key)
        if index >= _keys.length() || _keys.get(index) != key {
            return false
        }
        _keys.remove(index)
        _values.remove(index)
        return true
    }

    List<Int> keys() { return _keys.copy() }
    List<V> values() { return _values.copy() }

    List<IntPair> entries() {
        List<IntPair> result = []
        Int index = 0
        while index < _keys.length() {
            result.push(new IntPair(_keys.get(index), _values.get(index)))
            index = index + 1
        }
        return result
    }

    Int? floorKey(Int key) {
        Int index = self.lowerBound(key)
        if index < _keys.length() && _keys.get(index) == key {
            return key
        }
        if index == 0 { return null }
        return _keys.get(index - 1)
    }

    Int? ceilingKey(Int key) {
        Int index = self.lowerBound(key)
        if index >= _keys.length() { return null }
        return _keys.get(index)
    }

    Int? lowerKey(Int key) {
        Int index = self.lowerBound(key)
        if index == 0 { return null }
        return _keys.get(index - 1)
    }

    Int? higherKey(Int key) {
        Int index = self.lowerBound(key + 1)
        if index >= _keys.length() { return null }
        return _keys.get(index)
    }

    List<IntPair> range(Int from, Int endKey) {
        List<IntPair> result = []
        Int index = self.lowerBound(from)
        while index < _keys.length() && _keys.get(index) < endKey {
            result.push(new IntPair(_keys.get(index), _values.get(index)))
            index = index + 1
        }
        return result
    }

    List<Int> descendingKeys() {
        List<Int> result = []
        Int index = _keys.length() - 1
        while index >= 0 {
            result.push(_keys.get(index))
            index = index - 1
        }
        return result
    }

    void clear() {
        _keys.clear()
        _values.clear()
    }
}
```
