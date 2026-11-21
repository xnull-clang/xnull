# `LRUCache<K,V>`

| 项 | 值 |
| --- | --- |
| 类型 | `class LRUCache<K,V>` |
| 包 | `xdk.collections` |
| 稳定性 | `preview` |
| 依赖 | `Map`、`List` |

---

## 1. 定位

固定容量 LRU 缓存：命中移到最近使用，超容量淘汰最旧。

不做：TTL（`xdk.cache`）、并发、持久化、弱引用。

---

## 2. 设计逻辑

- `_map` 存键值；`_order` 存使用顺序（最旧→最新）。
- `get` 命中时把 key 移到末尾；缺失 miss+1。
- `put` 已存在更新并移末尾；新键插入末尾；超容量删队首并 evictions+1。
- `getOrLoad` 缺失时调用 loader，插入并返回。
- 非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_capacity` | `Int` | >0 |
| `_map` | `Map<K,V>` | 键值 |
| `_order` | `List<K>` | 最旧→最新 |
| `_hits` | `Long` | 命中 |
| `_misses` | `Long` | 缺失 |
| `_evictions` | `Long` | 淘汰 |

不变量：map.size = order.length ≤ capacity；order 无重复。

---

## 4. 生命周期

引用类型；无 close；可 clear。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `LRUCache(Int capacity)` | capacity | >0 | ≤0 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `get` | 取值 | `K key` | `V?` | 无 |
| `put` | 写入 | `K key, V value` | `V?` | 无 |
| `getOrLoad` | 缺失加载 | `K key, V(K) loader` | `V` | null loader → panic |
| `remove` | 删除 | `K key` | `Bool` | 无 |
| `containsKey` | 是否存在 | `K key` | `Bool` | 无 |
| `size` | 大小 | 无 | `Int` | 无 |
| `capacity` | 容量 | 无 | `Int` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |
| `hits` | 命中数 | 无 | `Long` | 无 |
| `misses` | 缺失数 | 无 | `Long` | 无 |
| `evictions` | 淘汰数 | 无 | `Long` | 无 |

---

## 8. 使用的技术

- 哈希映射 + 顺序列表（首版 O(n) touch）；
- LRU 淘汰；
- 加载器；
- 统计。

---

## 9. 需要的支撑

- 语言：class、Map、List、泛型 K/V、Int、Long、Bool；
- 运行时：映射/列表；
- 接口：`Map`、`List`。

---

## 10. 依赖的特性/接口/类

`Map`、`List`。

---

## 11. 所有权与并发

持有值引用；`put` 返回旧值；非线程安全。

---

## 12. 示例与反例

正确：容量 2，get A/B 后 put C 淘汰最旧；get 命中移末尾。  
反例：capacity 0；loader 抛错期望缓存坏值；多任务共享。

---

## 13. 测试/场景义务

命中/缺失/淘汰；put 旧值；getOrLoad；remove；统计；clear；容量边界。

---

## 14. XNull 伪代码

```xnull
class LRUCache<K, V> {
    Int _capacity
    Map<K, V> _map
    List<K> _order
    Long _hits
    Long _misses
    Long _evictions

    LRUCache(Int capacity) {
        if capacity <= 0 {
            throw "LRUCache: capacity must be positive"
        }
        _capacity = capacity
        _map = new Map<K, V>()
        _order = new List<K>()
        _hits = 0
        _misses = 0
        _evictions = 0
    }

    void touch(K key) {
        Int index = _order.indexOf(key)
        if index >= 0 {
            _order.remove(index)
        }
        _order.push(key)
    }

    V? get(K key) {
        if !_map.has(key) {
            _misses = _misses + 1
            return null
        }
        _hits = _hits + 1
        self.touch(key)
        return _map.get(key)
    }

    V? put(K key, V value) {
        V? old = null
        if _map.has(key) {
            old = _map.get(key)
            _map.put(key, value)
            self.touch(key)
            return old
        }
        if _order.length() >= _capacity {
            K oldest = _order.remove(0)
            _map.remove(oldest)
            _evictions = _evictions + 1
        }
        _map.put(key, value)
        _order.push(key)
        return null
    }

    V getOrLoad(K key, V(K) loader) {
        if loader == null { throw "LRUCache.getOrLoad: null loader" }
        V? cached = self.get(key)
        if cached != null {
            return cached
        }
        V value = loader(key)
        self.put(key, value)
        return value
    }

    Bool remove(K key) {
        if !_map.has(key) { return false }
        _map.remove(key)
        _order.remove(_order.indexOf(key))
        return true
    }

    Bool containsKey(K key) { return _map.has(key) }
    Int size() { return _map.length() }
    Int capacity() { return _capacity }

    void clear() {
        _map.clear()
        _order.clear()
    }

    Long hits() { return _hits }
    Long misses() { return _misses }
    Long evictions() { return _evictions }
}
```
