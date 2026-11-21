# `OrderedMap<V>`

| 项 | 值 |
| --- | --- |
| 类型 | `class OrderedMap<V>` |
| 包 | `xdk.collections` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

`Int` 键、按插入顺序迭代的映射。

不做：任意 K、排序键（`BTreeMap`）、并发。

---

## 2. 设计逻辑

- keys/values 平行列表；查找 O(n)，插入 O(n)。
- `put` 已存在替换值，不改变插入序；新键追加。
- `remove` 保持其余顺序。
- 非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_keys` | `List<Int>` | 插入序键 |
| `_values` | `List<V>` | 对应值 |

不变量：keys.length = values.length；键唯一。

---

## 4. 生命周期

引用类型；无 close；可 clear。

---

## 5. 构造契约

`OrderedMap()` 空映射。

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
| `clear` | 清空 | 无 | `void` | 无 |
| `firstKey` | 首个键 | 无 | `Int?` | 无 |
| `lastKey` | 最后键 | 无 | `Int?` | 无 |

---

## 8. 使用的技术

- 平行列表；
- 插入序；
- 线性查找；
- 快照。

---

## 9. 需要的支撑

- 语言：class、List、Int、泛型 V、Bool；
- 运行时：列表；
- 接口：`IntPair`。

---

## 10. 依赖的特性/接口/类

`IntPair`、`List`。

---

## 11. 所有权与并发

持有值引用；remove 删除；非线程安全。

---

## 12. 示例与反例

正确：put 2,1,3 → keys 2,1,3；替换 1 不改变顺序。  
反例：期望键排序；用可变值做键（键是 Int）；遍历时修改。

---

## 13. 测试/场景义务

插入序；替换；删除；get/getOr；keys/values/entries 快照；first/last；clear。

---

## 14. XNull 伪代码

```xnull
class OrderedMap<V> {
    List<Int> _keys
    List<V> _values

    OrderedMap() {
        _keys = new List<Int>()
        _values = new List<V>()
    }

    Int indexOf(Int key) {
        Int index = 0
        while index < _keys.length() {
            if _keys.get(index) == key { return index }
            index = index + 1
        }
        return -1
    }

    Int length() { return _keys.length() }
    Bool isEmpty() { return _keys.isEmpty() }
    Bool has(Int key) { return self.indexOf(key) >= 0 }

    V? get(Int key) {
        Int index = self.indexOf(key)
        if index < 0 { return null }
        return _values.get(index)
    }

    V getOr(Int key, V fallback) {
        Int index = self.indexOf(key)
        if index < 0 { return fallback }
        return _values.get(index)
    }

    Bool put(Int key, V value) {
        Int index = self.indexOf(key)
        if index >= 0 {
            _values.set(index, value)
            return true
        }
        _keys.push(key)
        _values.push(value)
        return false
    }

    Bool remove(Int key) {
        Int index = self.indexOf(key)
        if index < 0 { return false }
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

    void clear() {
        _keys.clear()
        _values.clear()
    }

    Int? firstKey() {
        if _keys.isEmpty() { return null }
        return _keys.get(0)
    }

    Int? lastKey() {
        if _keys.isEmpty() { return null }
        return _keys.get(_keys.length() - 1)
    }
}
```
