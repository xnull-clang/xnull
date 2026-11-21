# `DnsCacheStats`

| 项 | 值 |
| --- | --- |
| 类型 | `class DnsCacheStats` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

DNS resolver 缓存统计快照：条目、命中、未命中、淘汰、负缓存条目。

不做：实时可变统计、全局缓存指标、Prometheus 导出。

---

## 2. 设计逻辑

- 不可变快照；字段 `_entries`、`_hits`、`_misses`、`_evictions`、`_negativeEntries`。
- 所有值 ≥0；快照后不随缓存变化。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_entries` | `Int` | 正缓存条目 |
| `_hits` | `Long` | 命中 |
| `_misses` | `Long` | 未命中 |
| `_evictions` | `Long` | 淘汰 |
| `_negativeEntries` | `Int` | 负缓存条目 |

不变量：非负；不可变。

---

## 4. 生命周期

快照；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `DnsCacheStats(Int entries, Long hits, Long misses, Long evictions, Int negativeEntries)` | 见字段 | ≥0 | 负值 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `entries` | 正缓存条目 | 无 | `Int` | 无 |
| `hits` | 命中 | 无 | `Long` | 无 |
| `misses` | 未命中 | 无 | `Long` | 无 |
| `evictions` | 淘汰 | 无 | `Long` | 无 |
| `negativeEntries` | 负缓存 | 无 | `Int` | 无 |
| `toString` | 摘要 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- 计数器。

---

## 9. 需要的支撑

- 语言：class、Int、Long；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

不可变；无资源；可共享。

---

## 12. 示例与反例

正确：`resolver.cacheStats().hits()`。  
反例：修改 stats 期望缓存变化；负计数；把快照当实时视图。

---

## 13. 测试/场景义务

零值；各字段；快照独立；toString；负值 panic。

---

## 14. XNull 伪代码

```xnull
class DnsCacheStats {
    final Int _entries
    final Long _hits
    final Long _misses
    final Long _evictions
    final Int _negativeEntries

    DnsCacheStats(Int entries, Long hits, Long misses, Long evictions, Int negativeEntries) {
        if entries < 0 || hits < 0 || misses < 0 || evictions < 0 || negativeEntries < 0 {
            throw "DnsCacheStats: negative value"
        }
        _entries = entries
        _hits = hits
        _misses = misses
        _evictions = evictions
        _negativeEntries = negativeEntries
    }

    Int entries() { return _entries }
    Long hits() { return _hits }
    Long misses() { return _misses }
    Long evictions() { return _evictions }
    Int negativeEntries() { return _negativeEntries }

    String toString() {
        return "dns-cache(entries=" + str(_entries) + ",hits=" + str(_hits) + ")"
    }
}
```
