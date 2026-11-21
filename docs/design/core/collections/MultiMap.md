# `MultiMap<K,V>`

| 项 | 值 |
| --- | --- |
| 类型 | `class MultiMap<K,V>` |
| 包 | `xdk.collections` |
| 稳定性 | `preview` |
| 依赖 | `Map`、`List` |

---

## 1. 定位

一个键对应多个值的映射；用于分组、路由、索引。

不做：并发、有序键（用 `OrderedMap`/`BTreeMap`）、去重值。

---

## 2. 设计逻辑

- 内部 `Map<K,List<V>>`；`put` 追加，不去重。
- `get` 返回首个值；`getAll` 返回值快照。
- `remove` 删除键及全部值；`removeAll` 删除指定值。
- 非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_map` | `Map<K,List<V>>` | 键 → 值列表 |

不变量：每个列表非空；键存在则至少一个值。

---

## 4. 生命周期

引用类型；无 close；可 clear。

---

## 5. 构造契约

`MultiMap()` 空。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `put` | 追加值 | `K key, V value` | `void` | 无 |
| `get` | 首个值 | `K key` | `V?` | 无 |
| `getAll` | 全部值 | `K key` | `List<V>` | 无 |
| `remove` | 删除键 | `K key` | `List<V>` | 无 |
| `removeAll` | 删除值 | `K key, V value` | `Int` | 无 |
| `keys` | 键快照 | 无 | `List<K>` | 无 |
| `entries` | 条目快照 | 无 | `List<Pair<K,V>>` | 无 |
| `size` | 值总数 | 无 | `Int` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |

---

## 8. 使用的技术

- 嵌套映射；
- 值列表；
- 快照；
- 删除。

---

## 9. 需要的支撑

- 语言：class、Map、List、泛型 K/V、Int；
- 运行时：映射/列表；
- 接口：`Map`、`List`、`Pair`。

---

## 10. 依赖的特性/接口/类

`Map`、`List`、`Pair`。

---

## 11. 所有权与并发

持有值引用；`remove` 转移列表；非线程安全。

---

## 12. 示例与反例

正确：`put("a",1)`、`put("a",2)` → `getAll("a")` 两个值。  
反例：期望去重；遍历 entries 时修改；多任务共享。

---

## 13. 测试/场景义务

空/单/多值；get/getAll；remove/removeAll；keys/entries 快照；size；clear。

---

## 14. XNull 伪代码

```xnull
class MultiMap<K, V> {
    Map<K, List<V>> _map

    MultiMap() {
        _map = new Map<K, List<V>>()
    }

    void put(K key, V value) {
        if !_map.has(key) {
            _map.put(key, new List<V>())
        }
        _map.get(key).push(value)
    }

    V? get(K key) {
        if !_map.has(key) { return null }
        List<V> values = _map.get(key)
        if values.isEmpty() { return null }
        return values.get(0)
    }

    List<V> getAll(K key) {
        if !_map.has(key) { return new List<V>() }
        return _map.get(key).copy()
    }

    List<V> remove(K key) {
        if !_map.has(key) { return new List<V>() }
        return _map.removeOr(key, new List<V>())
    }

    Int removeAll(K key, V value) {
        if !_map.has(key) { return 0 }
        List<V> values = _map.get(key)
        Int removed = 0
        Int index = 0
        while index < values.length() {
            if values.get(index) == value {
                values.remove(index)
                removed = removed + 1
            } else {
                index = index + 1
            }
        }
        if values.isEmpty() {
            _map.remove(key)
        }
        return removed
    }

    List<K> keys() {
        return _map.keys()
    }

    List<Pair<K, V>> entries() {
        List<Pair<K, V>> result = []
        List<K> keys = _map.keys()
        Int index = 0
        while index < keys.length() {
            K key = keys.get(index)
            List<V> values = _map.get(key)
            Int valueIndex = 0
            while valueIndex < values.length() {
                result.push(new Pair<K, V>(key, values.get(valueIndex)))
                valueIndex = valueIndex + 1
            }
            index = index + 1
        }
        return result
    }

    Int size() {
        Int result = 0
        List<K> keys = _map.keys()
        Int index = 0
        while index < keys.length() {
            result = result + _map.get(keys.get(index)).length()
            index = index + 1
        }
        return result
    }

    void clear() {
        _map.clear()
    }
}
```
