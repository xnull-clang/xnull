# `CpuCache`

| 项 | 值 |
| --- | --- |
| 类型 | `class CpuCache` |
| 包 | `xdk.os.cpu` |
| 稳定性 | `preview` |
| 依赖 | `CpuCacheKind` |

---

## 1. 定位

CPU 缓存层级条目：层级、类型、大小、行宽、共享 CPU 数。

不做：缓存策略、替换算法、性能计数、缓存刷新。

---

## 2. 设计逻辑

- `level` 从 1 开始；L1/L2/L3...
- `kind` 是 `CpuCacheKind`；统一缓存用 `Unified`。
- `sizeBytes`/`lineBytes` 用 `Long`/`Int`；0 表示未知。
- `sharedByCpuCount` 是共享该缓存的逻辑 CPU 数；0 表示未知。
- 值语义快照；不可变。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_level` | `Int` | final | >0 |
| `_kind` | `CpuCacheKind` | final | 非 null |
| `_sizeBytes` | `Long` | final | ≥0 |
| `_lineBytes` | `Int` | final | ≥0 |
| `_sharedByCpuCount` | `Int` | final | ≥0 |

不变量：level>0；kind 非 null；其余 ≥0；不可变。

---

## 4. 生命周期

构造后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CpuCache(...)` | 5 个字段 | level>0；kind 非 null；其余 ≥0 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `level` | 层级 | 无 | `Int` | 无 |
| `kind` | 类型 | 无 | `CpuCacheKind` | 无 |
| `sizeBytes` | 大小 | 无 | `Long` | 无 |
| `lineBytes` | 行宽 | 无 | `Int` | 无 |
| `sharedByCpuCount` | 共享 CPU 数 | 无 | `Int` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `equals` | 值比较 | `CpuCache other` | `Bool` | null → false |
| `copy` | 复制 | 无 | `CpuCache` | 无 |

---

## 8. 使用的技术

- 不可变值快照；
- 枚举；
- 字符串描述。

---

## 9. 需要的支撑

- 语言：class、final 字段、Int、Long、Bool、String；
- 运行时/适配器：CPU 缓存读取；
- 接口：`CpuCacheKind`、`CpuTopology`。

---

## 10. 依赖的特性/接口/类

`CpuCacheKind`、`CpuTopology`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：`equals` 字段比较；`==` 仍是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：按 `level` 排序/显示缓存。  
反例：用缓存大小推断性能；未知值用 0 当真实；跨平台假设 L1 一定存在。

---

## 13. 测试/场景义务

L1/L2/L3；Data/Instruction/Unified；未知大小/行宽；共享数；多 socket；equals/copy。

---

## 14. XNull 伪代码

```xnull
class CpuCache {
    final Int _level
    final CpuCacheKind _kind
    final Long _sizeBytes
    final Int _lineBytes
    final Int _sharedByCpuCount

    CpuCache(Int level, CpuCacheKind kind, Long sizeBytes,
             Int lineBytes, Int sharedByCpuCount) {
        if kind == null { throw "CpuCache: null kind" }
        if level <= 0 || sizeBytes < 0 || lineBytes < 0 || sharedByCpuCount < 0 {
            throw "CpuCache: invalid field"
        }
        _level = level
        _kind = kind
        _sizeBytes = sizeBytes
        _lineBytes = lineBytes
        _sharedByCpuCount = sharedByCpuCount
    }

    Int level() { return _level }
    CpuCacheKind kind() { return _kind }
    Long sizeBytes() { return _sizeBytes }
    Int lineBytes() { return _lineBytes }
    Int sharedByCpuCount() { return _sharedByCpuCount }

    String describe() {
        return "cache L" + str(_level)
            + " " + cpuCacheKindName(_kind)
            + " size=" + str(_sizeBytes)
            + " line=" + str(_lineBytes)
            + " shared=" + str(_sharedByCpuCount)
    }

    Bool equals(CpuCache other) {
        if other == null { return false }
        return _level == other.level()
            && _kind == other.kind()
            && _sizeBytes == other.sizeBytes()
            && _lineBytes == other.lineBytes()
            && _sharedByCpuCount == other.sharedByCpuCount()
    }

    CpuCache copy() {
        return new CpuCache(_level, _kind, _sizeBytes, _lineBytes,
            _sharedByCpuCount)
    }
}
```
