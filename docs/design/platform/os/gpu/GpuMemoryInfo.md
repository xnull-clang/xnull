# `GpuMemoryInfo`

| 项 | 值 |
| --- | --- |
| 类型 | `class GpuMemoryInfo` |
| 包 | `xdk.os.gpu` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

GPU 显存只读快照：总字节、空闲字节、已用字节、共享字节。

不做：显存分配/预留/驱逐、精确预算、内存别名、页表、驱动内存管理。快照只用于诊断/容量提示。

---

## 2. 设计逻辑

- 不可变快照；由 `GpuDevice.memoryInfo(context)` 返回。
- 所有字节数用 `Long`；`0` 是未知/不支持的哨兵，不表示“零容量”。
- `freeBytes`/`usedBytes` 由驱动/后端报告；`usedBytes + freeBytes` 不保证等于 `totalBytes`，构造器不强制该等式。
- `totalBytes` 不要求等于 `GpuAdapter.memoryBytes()`；前者是设备当前报告，后者是适配器快照。
- `sharedBytes` 表示 GPU 使用的系统共享内存；`0` 表示未知/未报告，不一定是“没有共享”。
- 不自动刷新；需要新值时再次调用 `GpuDevice.memoryInfo`。
- `describe` 用于诊断/日志，不用于精确计费或分配决策。
- 不可变；无资源句柄；可安全缓存，但缓存值会过期。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_totalBytes` | `Long` | final | ≥0；0 未知 |
| `_freeBytes` | `Long` | final | ≥0；0 未知 |
| `_usedBytes` | `Long` | final | ≥0；0 未知 |
| `_sharedBytes` | `Long` | final | ≥0；0 未知 |

不变量：四个字节数都 ≥0；字段不可变；不强制 `freeBytes + usedBytes == totalBytes`；0 是未知哨兵，不表示零容量。

---

## 4. 生命周期

构造后不可变；无 close；可共享。设备关闭后，已取得的 `GpuMemoryInfo` 快照仍然可读，但不再代表当前状态。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `GpuMemoryInfo(...)` | 4 个字节数 | 每个 ≥0 | 负数 → panic |

构造器主要供宿主/测试使用；业务代码通过 `GpuDevice.memoryInfo(context)` 获取。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `totalBytes` | 总显存 | 无 | `Long` | 无 |
| `freeBytes` | 空闲显存 | 无 | `Long` | 无 |
| `usedBytes` | 已用显存 | 无 | `Long` | 无 |
| `sharedBytes` | 共享内存 | 无 | `Long` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `equals` | 值比较 | `GpuMemoryInfo other` | `Bool` | null → false |
| `copy` | 复制 | 无 | `GpuMemoryInfo` | 无 |

说明：

- 所有方法都是纯读取；无阻塞、无取消点。
- `describe` 输出原始字节数，不进行单位换算/四舍五入。
- `equals` 逐字段比较；`copy` 返回独立快照。

---

## 8. 使用的技术

- 不可变快照；
- `Long` 字节数；
- 值比较；
- 字符串描述。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、Bool、String；
- 运行时/适配器：`gpuMemoryInfoRaw(Context context, Long handle) -> Result<GpuMemoryInfo, Error>` 显存查询；
- 接口：`GpuDevice`、`GpuBackend`。

---

## 10. 依赖的特性/接口/类

`GpuDevice`、`GpuBackend`、`GpuAdapter`。

---

## 11. 所有权与并发

不可变；可共享；无资源；无取消点。
相等：`equals` 字段比较；`==` 仍是引用身份；不推荐作 `Map` 键，容量判断应重新采样而不是比较快照。

---

## 12. 示例与反例

正确：启动/巡检日志记录 `describe()`；把 `freeBytes` 当容量提示，分配失败仍按 `OutOfMemory` 处理。  
反例：按 `freeBytes` 精确分配；假设 `usedBytes + freeBytes == totalBytes`；把 `sharedBytes == 0` 当“没有共享内存”；用快照做计费；设备关闭后继续把旧快照当当前值。

---

## 13. 测试/场景义务

四个字段全 0；部分字段 0；`freeBytes > totalBytes` 不 panic；`usedBytes + freeBytes != totalBytes` 不 panic；
`equals`/`copy` 独立性；负数构造 panic；大 `Long` 值；独显/集显/共享内存；设备关闭后快照仍可读。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class GpuMemoryInfo {
    final Long _totalBytes
    final Long _freeBytes
    final Long _usedBytes
    final Long _sharedBytes

    GpuMemoryInfo(Long totalBytes, Long freeBytes, Long usedBytes, Long sharedBytes) {
        if totalBytes < 0 || freeBytes < 0 || usedBytes < 0 || sharedBytes < 0 {
            throw "GpuMemoryInfo: negative size"
        }
        _totalBytes = totalBytes
        _freeBytes = freeBytes
        _usedBytes = usedBytes
        _sharedBytes = sharedBytes
    }

    Long totalBytes() { return _totalBytes }
    Long freeBytes() { return _freeBytes }
    Long usedBytes() { return _usedBytes }
    Long sharedBytes() { return _sharedBytes }

    String describe() {
        return "gpu memory " + str(_usedBytes) + "/" + str(_totalBytes)
            + " shared=" + str(_sharedBytes)
    }

    Bool equals(GpuMemoryInfo other) {
        if other == null { return false }
        return _totalBytes == other.totalBytes()
            && _freeBytes == other.freeBytes()
            && _usedBytes == other.usedBytes()
            && _sharedBytes == other.sharedBytes()
    }

    GpuMemoryInfo copy() {
        return new GpuMemoryInfo(_totalBytes, _freeBytes, _usedBytes, _sharedBytes)
    }
}
```
