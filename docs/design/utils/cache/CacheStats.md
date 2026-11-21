# `CacheStats`

| 项 | 值 |
| --- | --- |
| 类型 | `class CacheStats` |
| 包 | `xdk.cache` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

缓存统计快照：命中、缺失、加载、加载失败、淘汰、过期、当前大小/权重。

不做：实时引用、重置、导出格式。

---

## 2. 设计逻辑

- 不可变快照；`Cache.stats()` 创建。
- 计数为非负 Long；size/weight 为非负。
- 比率在分母为 0 时返回 0.0。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_hits` | `Long` | 命中 |
| `_misses` | `Long` | 缺失 |
| `_loads` | `Long` | 成功加载 |
| `_loadFailures` | `Long` | 加载失败 |
| `_evictions` | `Long` | 淘汰/删除总数 |
| `_expirations` | `Long` | 过期数 |
| `_size` | `Int` | 当前条目数 |
| `_weight` | `Long` | 当前权重 |

不变量：计数非负；size ≤ 容量由 Cache 保证；expirations ≤ evictions。

---

## 4. 生命周期

不可变；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CacheStats(Long hits, Long misses, Long loads, Long loadFailures, Long evictions, Long expirations, Int size, Long weight)` | 全部 | 非负；size≥0 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `hits` | 命中数 | 无 | `Long` | 无 |
| `misses` | 缺失数 | 无 | `Long` | 无 |
| `loads` | 加载数 | 无 | `Long` | 无 |
| `loadFailures` | 加载失败 | 无 | `Long` | 无 |
| `evictions` | 淘汰数 | 无 | `Long` | 无 |
| `expirations` | 过期数 | 无 | `Long` | 无 |
| `size` | 条目数 | 无 | `Int` | 无 |
| `weight` | 权重 | 无 | `Long` | 无 |
| `hitRate` | 命中率 | 无 | `Double` | 无 |
| `missRate` | 缺失率 | 无 | `Double` | 无 |
| `loadFailureRate` | 加载失败率 | 无 | `Double` | 无 |
| `toString` | 摘要 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- 比率计算；
- 计数聚合。

---

## 9. 需要的支撑

- 语言：class、Long、Int、Double、String；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`stats.hitRate()`；`stats.evictions()`。  
反例：修改 stats 期望影响 cache；分母 0 时除零；把 bytes 权重当条目数。

---

## 13. 测试/场景义务

全零；命中/缺失；加载失败；比率；size/weight；toString；负参数 panic。

---

## 14. XNull 伪代码

```xnull
class CacheStats {
    final Long _hits
    final Long _misses
    final Long _loads
    final Long _loadFailures
    final Long _evictions
    final Long _expirations
    final Int _size
    final Long _weight

    CacheStats(Long hits, Long misses, Long loads, Long loadFailures,
               Long evictions, Long expirations, Int size, Long weight) {
        if hits < 0 || misses < 0 || loads < 0 || loadFailures < 0 {
            throw "CacheStats: negative counter"
        }
        if evictions < 0 || expirations < 0 || size < 0 || weight < 0 {
            throw "CacheStats: negative value"
        }
        _hits = hits
        _misses = misses
        _loads = loads
        _loadFailures = loadFailures
        _evictions = evictions
        _expirations = expirations
        _size = size
        _weight = weight
    }

    Long hits() { return _hits }
    Long misses() { return _misses }
    Long loads() { return _loads }
    Long loadFailures() { return _loadFailures }
    Long evictions() { return _evictions }
    Long expirations() { return _expirations }
    Int size() { return _size }
    Long weight() { return _weight }

    Double hitRate() {
        Long total = _hits + _misses
        if total == 0 { return 0.0 }
        return (_hits as Double) / (total as Double)
    }

    Double missRate() {
        Long total = _hits + _misses
        if total == 0 { return 0.0 }
        return (_misses as Double) / (total as Double)
    }

    Double loadFailureRate() {
        Long total = _loads + _loadFailures
        if total == 0 { return 0.0 }
        return (_loadFailures as Double) / (total as Double)
    }

    String toString() {
        return "CacheStats(size=" + str(_size) + ", weight=" + str(_weight)
            + ", hits=" + str(_hits) + ", misses=" + str(_misses) + ")"
    }
}
```
