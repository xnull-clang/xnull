# `MemoryStats`

### 1. 定位

运行时内存快照：堆使用/总量/外部/峰值/GC 次数。用于诊断/日志/健康检查，不用于精确计费。

### 2. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_heapUsed` | `Long` | final | 已用堆字节 |
| `_heapTotal` | `Long` | final | 堆总字节 |
| `_external` | `Long` | final | 外部/非堆字节 |
| `_peak` | `Long` | final | 峰值堆字节 |
| `_gcCount` | `Long` | final | GC 次数 |

不变量：所有值 ≥0；heapUsed ≤ heapTotal（快照尽力）；peak ≥ heapUsed（实现提供时）；不可变；可共享。

### 3. 使用的技术

- 不可变快照；
- 比值钳制；
- 运行时内存读取。

### 4. 需要的支撑

- 语言：class、Long、Double、String；
- 运行时：内存统计原语；
- 接口：无。

### 5. 依赖的特性/接口/类

无其他 XDK 类；只依赖语言原语和运行时统计。

### 6. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `heapUsed` | 已用堆 | 无 | `Long` | 无 |
| `heapTotal` | 堆总量 | 无 | `Long` | 无 |
| `external` | 外部内存 | 无 | `Long` | 无 |
| `peak` | 峰值 | 无 | `Long` | 无 |
| `gcCount` | GC 次数 | 无 | `Long` | 无 |
| `usageRatio` | 使用率 | 无 | `Double` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `copy` | 复制 | 无 | `MemoryStats` | 无 |

### 7. XNull 伪代码

```xnull
class MemoryStats {
    final Long _heapUsed
    final Long _heapTotal
    final Long _external
    final Long _peak
    final Long _gcCount

    MemoryStats(Long heapUsed, Long heapTotal, Long external, Long peak, Long gcCount) {
        _heapUsed = heapUsed
        _heapTotal = heapTotal
        _external = external
        _peak = peak
        _gcCount = gcCount
    }

    Long heapUsed() { return _heapUsed }
    Long heapTotal() { return _heapTotal }
    Long external() { return _external }
    Long peak() { return _peak }
    Long gcCount() { return _gcCount }

    Double usageRatio() {
        if _heapTotal == 0 {
            return 0.0
        }
        Double ratio = _heapUsed / _heapTotal
        if ratio < 0.0 {
            return 0.0
        }
        if ratio > 1.0 {
            return 1.0
        }
        return ratio
    }

    String describe() {
        return "heap " + str(_heapUsed) + "/" + str(_heapTotal)
            + " external=" + str(_external)
            + " peak=" + str(_peak)
            + " gc=" + str(_gcCount)
    }

    MemoryStats copy() {
        return new MemoryStats(
            _heapUsed,
            _heapTotal,
            _external,
            _peak,
            _gcCount
        )
    }
}
```

---
