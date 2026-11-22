# `RuntimeStats`

| 项 | 值 |
| --- | --- |
| 类型 | `class RuntimeStats` |
| 包 | `xdk.runtime` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

运行时分配/GC 计数快照：分配次数、释放次数、字节数、GC 次数、GC 释放字节；供诊断和统计开关使用。

不做：精确堆普查、GC 调优、内存归因、profiler。

---

## 2. 设计逻辑

- 不可变快照；由 `stats()` 创建，不提供公共构造器。
- `live()` = `allocs - frees`；是近似值，不是存活堆大小。
- 计数字段用 `Long`；不支持时字段为 0。
- 统计默认关闭；`statsSetEnabled(true)` 只影响后续计数。
- `statsReset()` 清零计数，不改变开关状态。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_allocs` | `Long` | final | 分配次数 |
| `_frees` | `Long` | final | 释放次数 |
| `_bytes` | `Long` | final | 当前/累计字节计数 |
| `_gcCollections` | `Long` | final | GC 次数 |
| `_gcFreed` | `Long` | final | GC 释放字节 |

不变量：所有值 ≥0；`live()` 可为负（近似计数）；不可变；可共享。

---

## 4. 生命周期

不可变；无 close；可跨任务共享。

---

## 5. 构造契约

构造器内部；公共入口 `runtime.stats()`。测试可通过运行时注入计数，不属于公共 API。

---

## 6. 字段表

见 §3；字段私有，通过访问器读取。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `allocs` | 分配次数 | 无 | `Long` | 无 |
| `frees` | 释放次数 | 无 | `Long` | 无 |
| `bytes` | 字节计数 | 无 | `Long` | 无 |
| `gcCollections` | GC 次数 | 无 | `Long` | 无 |
| `gcFreed` | GC 释放字节 | 无 | `Long` | 无 |
| `live` | 近似存活数 | 无 | `Long` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `copy` | 复制快照 | 无 | `RuntimeStats` | 无 |

---

## 8. 使用的技术

- 运行时计数读取；
- 不可变快照；
- 差值计算；
- 字符串拼接。

---

## 9. 需要的支撑

- 语言：class、Long、String；
- 运行时：分配/释放/GC 计数原语；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无其他 XDK 类；只依赖语言原语和运行时计数。

---

## 11. 所有权与并发

不可变；可共享；无资源；只读快照。

---

## 12. 示例与反例

正确：

```xnull
RuntimeStats stats = stats()
Long live = stats.live()
Bool enabled = statsEnabled()
statsSetEnabled(true)
statsReset()
```

反例：用 `live()` 做精确内存计量；把 `bytes` 当堆上限；在统计关闭时期望非零；用 `statsReset()` 改变开关状态。

---

## 13. 测试/场景义务

默认关闭；`statsSetEnabled(true/false)` 后 `statsEnabled()` 一致；`statsReset()` 清零但不改开关；`allocs/frees/bytes/gcCollections/gcFreed` 与运行时计数一致；`live()` 差值；快照不可变；并发读取安全。

---

## 14. XNull 伪代码

```xnull
class RuntimeStats {
    final Long _allocs
    final Long _frees
    final Long _bytes
    final Long _gcCollections
    final Long _gcFreed

    RuntimeStats(Long allocs, Long frees, Long bytes,
                 Long gcCollections, Long gcFreed) {
        _allocs = allocs
        _frees = frees
        _bytes = bytes
        _gcCollections = gcCollections
        _gcFreed = gcFreed
    }

    Long allocs() { return _allocs }
    Long frees() { return _frees }
    Long bytes() { return _bytes }
    Long gcCollections() { return _gcCollections }
    Long gcFreed() { return _gcFreed }
    Long live() { return _allocs - _frees }

    String describe() {
        return "allocs=" + str(_allocs)
            + " frees=" + str(_frees)
            + " bytes=" + str(_bytes)
            + " gc=" + str(_gcCollections)
            + " gc_freed=" + str(_gcFreed)
    }

    RuntimeStats copy() {
        return new RuntimeStats(_allocs, _frees, _bytes, _gcCollections, _gcFreed)
    }
}

RuntimeStats stats() {
    return new RuntimeStats(statsAllocsRaw(), statsFreesRaw(), statsBytesRaw(),
        statsGcCollectionsRaw(), statsGcFreedRaw())
}

Bool statsEnabled() { return statsEnabledRaw() != 0 }
void statsSetEnabled(Bool enabled) { statsSetEnabledRaw(enabled ? 1 : 0) }
void statsReset() { statsResetRaw() }
```

---

## 15. 1.x 兼容边界（C7）

- 1.x 公共字段 `allocs/frees/bytes/gcCollections/gcFreed` 在 2.x 迁移为同名访问器；不保留重复公共字段。
- `live()` 语义不变：`allocs - frees`，仍是近似值。
- `RuntimeStats` 是 1.x 分配/GC 计数；`MemoryStats` 是 2.x 内存快照，两者并存，不互相替代。
- 测试义务：1.x 字段访问迁移到访问器；`live()` 差值；`statsReset` 不改开关；快照不可变。
