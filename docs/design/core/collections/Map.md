# `Map<K,V>`

| 项 | 值 |
| --- | --- |
| 类型 | 语言容器 |
| 包 | `xdk.collections` |
| 稳定性 | `stable` |
| 依赖 | `xdk.errors` |

---

## 1. 定位

键唯一、可查找/替换/删除/快照的映射。

不做：并发安全、持久化。

---

## 2. 设计逻辑

- 键相等规则：整数/枚举按值，String 按内容，Double 按位模式，Bytes/class/协议按引用。
- `put` 返回 `Bool`：替换 true、插入 false。
- `remove` 返回 `Bool`；`removeOr` 返回旧值/fallback。
- `getOr` 只读，不插入。
- `entries` 返回 `List<Pair<String,Int>>`（`Map<String,Int>`）、`List<IntPair>`（`Map<Int,Int>`）或 `List<Entry<K,V>>`（其余受支持 K/V）快照。
- 非线程安全；顺序不承诺。

---

## 2.1 1.x 兼容边界（C7）

- 1.x t0 同时出现 `Bool put` 与 `Int? put` 两种写法；2.x 冻结 `Bool put`：替换 `true`、插入 `false`。需要旧值时用 `removeOr`、`putIfAbsent` 或先 `tryGet`。
- 1.x 固定 `Pair`（公共字段）仅用于 `Map<String,Int>.entries()`；2.x 返回 `Pair<String,Int>`，字段访问迁移到 `first()`/`second()`。
- 其余受支持 K/V 的 `entries()` 返回 `Entry<K,V>`，使用 `key()`/`value()`。
- `OrderedMap`/`BTreeMap` 的 `put` 仍返回 `V?` 旧值；这是专用容器既有契约，不与通用 `Map` 的 `Bool` 混用。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_entries` | 运行时映射 | 键值 |
| `_size` | `Int` | 键数 |

不变量：键唯一；size 与键数一致；非线程安全。

---

## 4. 生命周期

引用类型；无 close；GC 管理。

---

## 5. 构造契约

字面量 `[:]` 生成空 Map；也可 `Map<K,V>()`。

---

## 6. 字段表

见 §3；字段内部。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `length` | 键数 | 无 | `Int` | 无 |
| `isEmpty` | 是否为空 | 无 | `Bool` | 无 |
| `has` | 是否存在 | `K key` | `Bool` | 无 |
| `get` | 取值 | `K key` | `V` | 缺失 → panic |
| `getOr` | 取值/兜底 | `K key, V fallback` | `V` | 无 |
| `tryGet` | checked 取 | `K key` | `Result<V, Error>` | `NotFound` |
| `put` | 插入/替换 | `K key, V value` | `Bool` | 无 |
| `putIfAbsent` | 不存在才插 | `K key, V value` | `V?` | 无 |
| `putAll` | 批量插入 | `Map<K,V> other` | `void` | null → panic |
| `replace` | 替换 | `K key, V value` | `Bool` | 无 |
| `replaceIf` | 条件替换 | `K key, V expected, V value` | `Bool` | 无 |
| `replaceAll` | 批量替换 | `V(K,V) transform` | `void` | null → panic |
| `compute` | 计算 | `K key, V?(K,V?) remap` | `V?` | null → panic |
| `computeIfAbsent` | 缺失计算 | `K key, V(K) mapping` | `V` | null → panic |
| `merge` | 合并 | `K key, V value, V(V,V) combine` | `V` | null → panic |
| `remove` | 删除 | `K key` | `Bool` | 无 |
| `removeIf` | 条件删除 | `Bool(K,V) predicate` | `Int` | null → panic |
| `removeOr` | 删除并返回 | `K key, V fallback` | `V` | 无 |
| `keys` | 键快照 | 无 | `List<K>` | 无 |
| `values` | 值快照 | 无 | `List<V>` | 无 |
| `entries` | 条目快照 | 无 | `List<Pair<String,Int>>`/`List<IntPair>`/`List<Entry<K,V>>` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |
| `copy` | 副本 | 无 | `Map<K,V>` | 无 |
| `containsValue` | 是否含值 | `V value` | `Bool` | 无 |
| `count` | 满足数量 | `Bool(K,V) predicate` | `Int` | null → panic |
| `any` | 任一满足 | 同上 | `Bool` | null → panic |
| `all` | 全部满足 | 同上 | `Bool` | null → panic |

---

## 8. 使用的技术

- 哈希表/快速路径；
- 键相等/哈希；
- 快照；
- 计算/合并；
- 删除迭代。

---

## 9. 需要的支撑

- 语言：class/容器、K/V 泛型、Int、Bool、List、Result；
- 运行时：映射存储/查找；
- 接口：`Error`、`BasicError`、`ErrorKind`、`Pair`、`IntPair`、`Entry`。

---

## 10. 依赖的特性/接口/类

`Pair`、`IntPair`、`Entry`、`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

- 容器持有键值引用；`removeOr` 返回旧值。
- `keys/values/entries` 快照。
- 非线程安全；可变对象不得作键。

---

## 12. 示例与反例

正确：`put("a",1)` 插入 false；再次 put 替换 true；`tryGet` 缺失 Err。

正确：`Map<String,Bool> flags` 的 `entries()` 返回 `List<Entry<String,Bool>>`，用 `key()`/`value()` 读取。

反例：用可变对象作键；依赖迭代顺序；`get` 缺失期望 null；遍历时删除；把 2.x `put` 当 1.x 旧值返回；用 `entry.key` 公共字段访问 2.x `Entry`。

---

## 13. 测试/场景义务

空/插入/替换/删除；putIfAbsent；compute/merge；removeIf；keys/values/entries 快照；`Map<String,Int>`/`Map<Int,Int>`/通用 K/V 三种 entries 形状；`Entry` 访问器；`put` 返回 Bool 的插入/替换两侧；键相等规则；null 值限制。

---

## 14. XNull 伪代码

```xnull
class Map<K, V> {
    MapStorage<K, V> _entries
    Int _size

    Map() {
        _entries = new MapStorage<K, V>()
        _size = 0
    }

    Int length() { return _size }
    Bool isEmpty() { return _size == 0 }

    Bool has(K key) {
        return _entries.has(key)
    }

    V get(K key) {
        if !_entries.has(key) {
            throw "Map.get: key not found"
        }
        return _entries.get(key)
    }

    V getOr(K key, V fallback) {
        if !_entries.has(key) {
            return fallback
        }
        return _entries.get(key)
    }

    Result<V, Error> tryGet(K key) {
        if !_entries.has(key) {
            return Err(new BasicError(ErrorKind.NotFound, "key not found"))
        }
        return Ok(_entries.get(key))
    }

    Bool put(K key, V value) {
        Bool existed = _entries.has(key)
        _entries.put(key, value)
        if !existed {
            _size = _size + 1
        }
        return existed
    }

    V? putIfAbsent(K key, V value) {
        if _entries.has(key) {
            return _entries.get(key)
        }
        self.put(key, value)
        return null
    }

    void putAll(Map<K, V> other) {
        if other == null { throw "Map.putAll: null" }
        List<K> keys = other.keys()
        Int index = 0
        while index < keys.length() {
            K key = keys.get(index)
            self.put(key, other.get(key))
            index = index + 1
        }
    }

    Bool replace(K key, V value) {
        if !_entries.has(key) { return false }
        _entries.put(key, value)
        return true
    }

    Bool replaceIf(K key, V expected, V value) {
        if !_entries.has(key) { return false }
        if _entries.get(key) != expected { return false }
        _entries.put(key, value)
        return true
    }

    void replaceAll(V(K, V) transform) {
        if transform == null { throw "Map.replaceAll: null" }
        List<K> keys = self.keys()
        Int index = 0
        while index < keys.length() {
            K key = keys.get(index)
            _entries.put(key, transform(key, _entries.get(key)))
            index = index + 1
        }
    }

    V? compute(K key, V?(K, V?) remap) {
        if remap == null { throw "Map.compute: null" }
        V? current = null
        if _entries.has(key) {
            current = _entries.get(key)
        }
        V? next = remap(key, current)
        if next == null {
            if _entries.has(key) {
                _entries.remove(key)
                _size = _size - 1
            }
        } else {
            if !_entries.has(key) {
                _size = _size + 1
            }
            _entries.put(key, next)
        }
        return next
    }

    V computeIfAbsent(K key, V(K) mapping) {
        if mapping == null { throw "Map.computeIfAbsent: null" }
        if _entries.has(key) {
            return _entries.get(key)
        }
        V value = mapping(key)
        self.put(key, value)
        return value
    }

    V merge(K key, V value, V(V, V) combine) {
        if combine == null { throw "Map.merge: null" }
        if !_entries.has(key) {
            self.put(key, value)
            return value
        }
        V merged = combine(_entries.get(key), value)
        _entries.put(key, merged)
        return merged
    }

    Bool remove(K key) {
        if !_entries.has(key) { return false }
        _entries.remove(key)
        _size = _size - 1
        return true
    }

    Int removeIf(Bool(K, V) predicate) {
        if predicate == null { throw "Map.removeIf: null" }
        Int removed = 0
        List<K> keys = self.keys()
        Int index = 0
        while index < keys.length() {
            K key = keys.get(index)
            if predicate(key, _entries.get(key)) {
                self.remove(key)
                removed = removed + 1
            }
            index = index + 1
        }
        return removed
    }

    V removeOr(K key, V fallback) {
        if !_entries.has(key) { return fallback }
        V value = _entries.get(key)
        self.remove(key)
        return value
    }

    List<K> keys() {
        List<K> result = []
        List<K> stored = _entries.keys()
        Int index = 0
        while index < stored.length() {
            result.push(stored.get(index))
            index = index + 1
        }
        return result
    }

    List<V> values() {
        List<V> result = []
        List<K> keys = self.keys()
        Int index = 0
        while index < keys.length() {
            result.push(_entries.get(keys.get(index)))
            index = index + 1
        }
        return result
    }

    void clear() {
        _entries.clear()
        _size = 0
    }

    Bool containsValue(V value) {
        List<V> values = self.values()
        Int index = 0
        while index < values.length() {
            if values.get(index) == value { return true }
            index = index + 1
        }
        return false
    }

    Int count(Bool(K, V) predicate) {
        Int result = 0
        List<K> keys = self.keys()
        Int index = 0
        while index < keys.length() {
            K key = keys.get(index)
            if predicate(key, _entries.get(key)) {
                result = result + 1
            }
            index = index + 1
        }
        return result
    }

    Bool any(Bool(K, V) predicate) {
        return self.count(predicate) > 0
    }

    Bool all(Bool(K, V) predicate) {
        return self.count(predicate) == _size
    }
}
```

> `MapStorage` 是运行时映射原语；`entries()` 的 K 实现见 `Pair`/`IntPair`。
