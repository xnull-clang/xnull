# `Cache`

| 项 | 值 |
| --- | --- |
| 类型 | `class Cache<K,V>` |
| 包 | `xdk.cache` |
| 稳定性 | `preview` |
| 依赖 | `CacheOptions`、`CacheStats`、`EvictionReason`、`RuntimeMonitor`、`Error` |

---

## 1. 定位

并发缓存：LRU 顺序、TTL、条目/权重上限、加载、显式失效、统计、淘汰监听、关闭。

不做：分布式缓存、持久化、弱引用、单飞加载、异步加载、按函数自动计权重。

---

## 2. 设计逻辑

- 字段：选项、监听函数、监视器、键值表、LRU 顺序、过期时间、权重表、总权重、计数器、关闭标志。
- 全部状态由 `RuntimeMonitor` 保护；`get/put/invalidate/stats` 线程安全。
- LRU 顺序：`_order` 最旧→最新；命中/写入把键移到末尾。
- TTL：写入时计算 `nowMono + ttl`；0 表示不过期；读取/统计前惰性清理。
- 容量：条目数或总权重超限时从最旧开始淘汰。
- `getOrLoad` 在锁外调用 loader；并发缺失可能重复加载（X single-flight）。
- listener 在锁内同步调用；不得重入 cache，不得阻塞。
- `close` 清空并通知 `Closed`；之后 `getOrLoad` 返回 `Unavailable`，读写静默失败。
- `recordStats=false` 时 hit/miss/load 计数保持 0；淘汰/过期计数仍维护。
- 无 close 资源；close 幂等。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_options` | `CacheOptions` | 选项副本 |
| `_listener` | `void(K,V,EvictionReason)` | 淘汰监听 |
| `_monitor` | `RuntimeMonitor` | 状态保护 |
| `_map` | `Map<K,V>` | 键值 |
| `_order` | `List<K>` | 最旧→最新 |
| `_expiry` | `Map<K,Long>` | 到期单调毫秒；0 不过期 |
| `_weights` | `Map<K,Long>` | 每项权重 |
| `_weight` | `Long` | 当前总权重 |
| `_hits`/`_misses` | `Long` | 命中/缺失 |
| `_loads`/`_loadFailures` | `Long` | 加载/失败 |
| `_evictions`/`_expirations` | `Long` | 淘汰/过期 |
| `_closed` | `Bool` | 是否关闭 |

不变量：order 无重复且与 map 键一致；weight = 各 weights 之和；0 ≤ size ≤ maxEntries（清理后）；weight ≤ maxWeight（除非单条超限被立即淘汰）；closed 后 map/order 为空。

---

## 4. 生命周期

构造；读写；`close` 清空并结束；close 幂等；无资源句柄。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Cache(CacheOptions options)` | options | 非 null | null → panic |
| `Cache(CacheOptions options, void(K,V,EvictionReason) listener)` | options/listener | 非 null | null → panic |

选项被复制；listener 不可为 null（用空函数表示不监听）。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `get` | 读取 | `K key` | `V?` | null key → panic |
| `getOrLoad` | 读取/加载 | `K key, Result<V,Error>(K) loader` | `Result<V, Error>` | `Unavailable`/loader 错误 |
| `put` | 写入 | `K key, V value` | `V?` | null key/value → panic |
| `putIfAbsent` | 不存在才写 | `K key, V value` | `V?` | 同上 |
| `putWithTtl` | 指定 TTL 写入 | `K key, V value, Long ttlMillis` | `V?` | ttl<0 → panic |
| `putWeighted` | 指定权重/TTL | `K key, V value, Long weight, Long ttlMillis` | `V?` | weight<1/ttl<0 → panic |
| `invalidate` | 删除 | `K key` | `Bool` | null key → panic |
| `invalidateAll` | 清空 | 无 | `void` | 无 |
| `cleanup` | 清理过期 | 无 | `Int` | 无 |
| `contains` | 是否存在 | `K key` | `Bool` | null key → panic |
| `size` | 条目数 | 无 | `Int` | 无 |
| `weight` | 总权重 | 无 | `Long` | 无 |
| `keys` | 键快照 | 无 | `List<K>` | 无 |
| `values` | 值快照 | 无 | `List<V>` | 无 |
| `entries` | 键值快照 | 无 | `Map<K,V>` | 无 |
| `stats` | 统计快照 | 无 | `CacheStats` | 无 |
| `resetStats` | 清零计数 | 无 | `void` | 无 |
| `options` | 选项副本 | 无 | `CacheOptions` | 无 |
| `close` | 关闭清空 | 无 | `void` | 无；幂等 |
| `isClosed` | 是否关闭 | 无 | `Bool` | 无 |

说明：

- `get` 命中返回缓存值；缺失/过期返回 null；null value 不允许缓存，因此 null 唯一表示缺失。
- `getOrLoad` loader 返回 null 视为合同错误（`InvalidArgument`），不计入 loads。
- `putIfAbsent` 已存在时不替换、不更新 TTL；返回现有值。
- `put`/`putWithTtl` 覆盖时通知 `Replaced`，但不算 eviction。
- `cleanup` 返回删除的过期条目数。
- `invalidateAll` 对每个条目通知 `Explicit`。
- `close` 对每个条目通知 `Closed`；之后 `invalidate` 返回 false。

---

## 8. 使用的技术

- LRU 顺序表；
- TTL 截止；
- 权重核算；
- 监视器同步；
- 加载器；
- 统计/监听。

---

## 9. 需要的支撑

- 语言：class、泛型 K/V、Map、List、Long、Int、Bool、Result、函数类型；
- 运行时：`RuntimeMonitor.enter/exit`、`nowMono`；
- 接口：`CacheOptions`、`CacheStats`、`EvictionReason`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`CacheOptions`、`CacheStats`、`EvictionReason`、`RuntimeMonitor`、`nowMono`、`Error`。

---

## 11. 所有权与并发

引用语义；线程安全；可跨任务共享；listener 锁内调用且不得重入；无资源。

---

## 12. 示例与反例

正确：`Cache<String,Bytes> c = new Cache<String,Bytes>(opts)`；`c.getOrLoad(key, loader)`。  
反例：缓存 null 值；listener 调 `c.get`；并发缺失期望只加载一次；`getOrLoad` 忽略关闭；单条权重超过总上限。

---

## 13. 测试/场景义务

命中/缺失/过期；LRU 顺序；容量/权重淘汰；替换；putIfAbsent；TTL 边界；cleanup；invalidate/all；close；listener 原因；统计/清零；并发读写；loader 失败/null；recordStats 关闭。

---

## 14. XNull 伪代码

```xnull
class Cache<K, V> {
    final CacheOptions _options
    final void(K, V, EvictionReason) _listener
    final RuntimeMonitor _monitor
    final Map<K, V> _map
    final List<K> _order
    final Map<K, Long> _expiry
    final Map<K, Long> _weights
    Long _weight = 0
    Long _hits = 0
    Long _misses = 0
    Long _loads = 0
    Long _loadFailures = 0
    Long _evictions = 0
    Long _expirations = 0
    Bool _closed = false

    Cache(CacheOptions options) {
        if options == null { throw "Cache: null options" }
        _options = options.copy()
        _listener = (K key, V value, EvictionReason reason) -> {
        }
        _monitor = new RuntimeMonitor()
        _map = new Map<K, V>()
        _order = []
        _expiry = new Map<K, Long>()
        _weights = new Map<K, Long>()
    }

    Cache(CacheOptions options, void(K, V, EvictionReason) listener) {
        if options == null || listener == null {
            throw "Cache: null argument"
        }
        _options = options.copy()
        _listener = listener
        _monitor = new RuntimeMonitor()
        _map = new Map<K, V>()
        _order = []
        _expiry = new Map<K, Long>()
        _weights = new Map<K, Long>()
    }

    V? get(K key) {
        if key == null { throw "Cache.get: null key" }
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return null
        }
        self.cleanupExpiredLocked()
        if _map.has(key) {
            V value = _map.get(key)
            self.touchLocked(key)
            if _options.isRecordStats() { _hits = _hits + 1 }
            _monitor.exit()
            return value
        }
        if _options.isRecordStats() { _misses = _misses + 1 }
        _monitor.exit()
        return null
    }

    Result<V, Error> getOrLoad(K key, Result<V, Error>(K) loader) {
        if key == null || loader == null {
            throw "Cache.getOrLoad: null argument"
        }
        _monitor.enter()
        Bool closed = _closed
        _monitor.exit()
        if closed {
            return Err(new BasicError(ErrorKind.Unavailable, "cache is closed"))
        }
        V? cached = self.get(key)
        if cached != null { return Ok(cached as V) }
        Result<V, Error> loaded = loader(key)
        if loaded.isErr() {
            _monitor.enter()
            if _options.isRecordStats() { _loadFailures = _loadFailures + 1 }
            _monitor.exit()
            return loaded
        }
        if loaded.value() == null {
            _monitor.enter()
            if _options.isRecordStats() { _loadFailures = _loadFailures + 1 }
            _monitor.exit()
            return Err(new BasicError(ErrorKind.InvalidArgument, "loader returned null"))
        }
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "cache is closed"))
        }
        if _options.isRecordStats() { _loads = _loads + 1 }
        _monitor.exit()
        self.put(key, loaded.value())
        return loaded
    }

    V? put(K key, V value) {
        return self.putWeighted(key, value, 1, _options.getDefaultTtlMillis())
    }

    V? putIfAbsent(K key, V value) {
        if key == null || value == null {
            throw "Cache.putIfAbsent: null argument"
        }
        _monitor.enter()
        self.cleanupExpiredLocked()
        if _closed {
            _monitor.exit()
            return null
        }
        if _map.has(key) {
            V existing = _map.get(key)
            _monitor.exit()
            return existing
        }
        V? old = self.putLocked(key, value, 1, _options.getDefaultTtlMillis())
        _monitor.exit()
        return old
    }

    V? putWithTtl(K key, V value, Long ttlMillis) {
        if ttlMillis < 0 { throw "Cache.putWithTtl: negative ttl" }
        return self.putWeighted(key, value, 1, ttlMillis)
    }

    V? putWeighted(K key, V value, Long weight, Long ttlMillis) {
        if key == null || value == null {
            throw "Cache.putWeighted: null argument"
        }
        if weight < 1 { throw "Cache.putWeighted: weight < 1" }
        if ttlMillis < 0 { throw "Cache.putWeighted: negative ttl" }
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return null
        }
        V? old = self.putLocked(key, value, weight, ttlMillis)
        _monitor.exit()
        return old
    }

    Bool invalidate(K key) {
        if key == null { throw "Cache.invalidate: null key" }
        _monitor.enter()
        self.cleanupExpiredLocked()
        if !_map.has(key) {
            _monitor.exit()
            return false
        }
        self.removeEntryLocked(key, EvictionReason.Explicit)
        _monitor.exit()
        return true
    }

    void invalidateAll() {
        _monitor.enter()
        while _order.length() > 0 {
            self.removeEntryLocked(_order.get(0), EvictionReason.Explicit)
        }
        _monitor.exit()
    }

    Int cleanup() {
        _monitor.enter()
        Int before = _order.length()
        self.cleanupExpiredLocked()
        Int removed = before - _order.length()
        _monitor.exit()
        return removed
    }

    Bool contains(K key) {
        if key == null { throw "Cache.contains: null key" }
        _monitor.enter()
        self.cleanupExpiredLocked()
        Bool result = _map.has(key)
        _monitor.exit()
        return result
    }

    Int size() {
        _monitor.enter()
        self.cleanupExpiredLocked()
        Int result = _map.length()
        _monitor.exit()
        return result
    }

    Long weight() {
        _monitor.enter()
        self.cleanupExpiredLocked()
        Long result = _weight
        _monitor.exit()
        return result
    }

    List<K> keys() {
        _monitor.enter()
        self.cleanupExpiredLocked()
        List<K> result = _order.copy()
        _monitor.exit()
        return result
    }

    List<V> values() {
        _monitor.enter()
        self.cleanupExpiredLocked()
        List<V> result = []
        Int index = 0
        while index < _order.length() {
            result.push(_map.get(_order.get(index)))
            index = index + 1
        }
        _monitor.exit()
        return result
    }

    Map<K, V> entries() {
        _monitor.enter()
        self.cleanupExpiredLocked()
        Map<K, V> result = _map.copy()
        _monitor.exit()
        return result
    }

    CacheStats stats() {
        _monitor.enter()
        self.cleanupExpiredLocked()
        CacheStats result = new CacheStats(_hits, _misses, _loads, _loadFailures,
            _evictions, _expirations, _map.length(), _weight)
        _monitor.exit()
        return result
    }

    void resetStats() {
        _monitor.enter()
        _hits = 0
        _misses = 0
        _loads = 0
        _loadFailures = 0
        _evictions = 0
        _expirations = 0
        _monitor.exit()
    }

    CacheOptions options() { return _options.copy() }

    void close() {
        _monitor.enter()
        if !_closed {
            _closed = true
            while _order.length() > 0 {
                self.removeEntryLocked(_order.get(0), EvictionReason.Closed)
            }
        }
        _monitor.exit()
    }

    Bool isClosed() {
        _monitor.enter()
        Bool result = _closed
        _monitor.exit()
        return result
    }

    private V? putLocked(K key, V value, Long weight, Long ttlMillis) {
        self.cleanupExpiredLocked()
        V? old = null
        if _map.has(key) {
            old = _map.get(key)
            _weight = _weight - _weights.get(key)
            _order.removeValue(key)
            _listener(key, old as V, EvictionReason.Replaced)
        }
        _order.push(key)
        _map.put(key, value)
        _weights.put(key, weight)
        if ttlMillis > 0 {
            _expiry.put(key, nowMono() + ttlMillis)
        } else {
            _expiry.put(key, 0 as Long)
        }
        _weight = _weight + weight
        while _order.length() > _options.getMaxEntries() || _weight > _options.getMaxWeight() {
            if _order.length() == 0 { break }
            self.removeEntryLocked(_order.get(0), EvictionReason.Capacity)
        }
        return old
    }

    private void touchLocked(K key) {
        _order.removeValue(key)
        _order.push(key)
    }

    private void cleanupExpiredLocked() {
        Long now = nowMono()
        Int index = 0
        while index < _order.length() {
            K key = _order.get(index)
            Long expiry = _expiry.get(key)
            if expiry != 0 && now >= expiry {
                self.removeEntryLocked(key, EvictionReason.Expired)
            } else {
                index = index + 1
            }
        }
    }

    private void removeEntryLocked(K key, EvictionReason reason) {
        if !_map.has(key) { return }
        V value = _map.get(key)
        _weight = _weight - _weights.get(key)
        _map.remove(key)
        _weights.remove(key)
        _expiry.remove(key)
        _order.removeValue(key)
        _evictions = _evictions + 1
        if reason == EvictionReason.Expired {
            _expirations = _expirations + 1
        }
        _listener(key, value, reason)
    }
}
```
