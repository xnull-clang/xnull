# `CacheOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class CacheOptions` |
| 包 | `xdk.cache` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

缓存构造选项：最大条目数、最大权重、默认 TTL、统计开关。

不做：淘汰算法选择、loader、listener、并发度。

---

## 2. 设计逻辑

- 可变 builder；`Cache` 构造时复制。
- 默认：1024 条目、1,048,576 权重、TTL 0（不过期）、统计开启。
- `maxEntries ≥1`；`maxWeight ≥1`；`defaultTtlMillis ≥0`。
- `defaultTtlMillis=0` 表示不过期；条目可 `putWithTtl` 覆盖。
- 无 close；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_maxEntries` | `Int` | 条目上限 |
| `_maxWeight` | `Long` | 权重上限 |
| `_defaultTtlMillis` | `Long` | 默认 TTL；0 不过期 |
| `_recordStats` | `Bool` | 是否统计 |

不变量：maxEntries≥1；maxWeight≥1；ttl≥0。

---

## 4. 生命周期

可变；无 close；复制后独立。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CacheOptions()` | 无 | 默认值 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `maxEntries` | 设置条目上限 | `Int` | `CacheOptions` | <1 → panic |
| `maxWeight` | 设置权重上限 | `Long` | `CacheOptions` | <1 → panic |
| `defaultTtlMillis` | 设置默认 TTL | `Long` | `CacheOptions` | <0 → panic |
| `recordStats` | 设置统计 | `Bool` | `CacheOptions` | 无 |
| `getMaxEntries` | 读取条目上限 | 无 | `Int` | 无 |
| `getMaxWeight` | 读取权重上限 | 无 | `Long` | 无 |
| `getDefaultTtlMillis` | 读取 TTL | 无 | `Long` | 无 |
| `isRecordStats` | 是否统计 | 无 | `Bool` | 无 |
| `copy` | 独立副本 | 无 | `CacheOptions` | 无 |

---

## 8. 使用的技术

- builder；
- 边界校验；
- 防御性复制。

---

## 9. 需要的支撑

- 语言：class、Int、Long、Bool；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

可变；非线程安全；无资源；传入 Cache 后被复制。

---

## 12. 示例与反例

正确：`new CacheOptions().maxEntries(512).defaultTtlMillis(30000)`。  
反例：maxEntries=0；负 TTL；构造后继续改 options 期望影响 cache；把 TTL 0 当立即过期。

---

## 13. 测试/场景义务

默认值；每个 setter；边界；copy 独立性；TTL 0；recordStats 关闭；toString 无。

---

## 14. XNull 伪代码

```xnull
class CacheOptions {
    Int _maxEntries = 1024
    Long _maxWeight = 1048576
    Long _defaultTtlMillis = 0
    Bool _recordStats = true

    CacheOptions() {
    }

    CacheOptions maxEntries(Int value) {
        if value < 1 { throw "CacheOptions.maxEntries: < 1" }
        _maxEntries = value
        return self
    }

    CacheOptions maxWeight(Long value) {
        if value < 1 { throw "CacheOptions.maxWeight: < 1" }
        _maxWeight = value
        return self
    }

    CacheOptions defaultTtlMillis(Long value) {
        if value < 0 { throw "CacheOptions.defaultTtlMillis: negative" }
        _defaultTtlMillis = value
        return self
    }

    CacheOptions recordStats(Bool value) {
        _recordStats = value
        return self
    }

    Int getMaxEntries() { return _maxEntries }
    Long getMaxWeight() { return _maxWeight }
    Long getDefaultTtlMillis() { return _defaultTtlMillis }
    Bool isRecordStats() { return _recordStats }

    CacheOptions copy() {
        CacheOptions result = new CacheOptions()
        result._maxEntries = _maxEntries
        result._maxWeight = _maxWeight
        result._defaultTtlMillis = _defaultTtlMillis
        result._recordStats = _recordStats
        return result
    }
}
```
