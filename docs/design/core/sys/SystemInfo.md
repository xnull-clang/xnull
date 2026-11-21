# `SystemInfo`

| 项 | 值 |
| --- | --- |
| 类型 | `class SystemInfo` |
| 包 | `xdk.sys` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

系统信息快照：主机名、uptime、CPU、内存、磁盘。

不做：容器/cgroup/GPU/温度/网络接口。

---

## 2. 设计逻辑

- 不可变快照；字段全为值。
- CPU 使用率是瞬时采样；不承诺精确。
- 磁盘信息用 `Map<String,Long>`（mount → available bytes），避免额外类。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_hostname` | `String` | 主机名 |
| `_uptimeMillis` | `Long` | uptime |
| `_cpuCores` | `Int` | 核数 |
| `_cpuModel` | `String` | 型号 |
| `_cpuFrequencyMhz` | `Int` | 频率 |
| `_cpuUsagePercent` | `Double` | 使用率 |
| `_memoryTotal` | `Long` | 总内存 |
| `_memoryFree` | `Long` | 空闲 |
| `_memoryAvailable` | `Long` | 可用 |
| `_disks` | `Map<String,Long>` | mount→available |

不变量：数值 ≥0；usage 0..100；不可变。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

构造器内部；公共入口 `SystemInfo.snapshot()`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `snapshot` | 当前快照 | 无 | `SystemInfo` | 无 |
| `hostname` | 主机名 | 无 | `String` | 无 |
| `uptimeMillis` | uptime | 无 | `Long` | 无 |
| `cpuCores` | 核数 | 无 | `Int` | 无 |
| `cpuModel` | 型号 | 无 | `String` | 无 |
| `cpuFrequencyMhz` | 频率 | 无 | `Int` | 无 |
| `cpuUsagePercent` | 使用率 | 无 | `Double` | 无 |
| `memoryTotal/Free/Available` | 内存 | 无 | `Long` | 无 |
| `disks` | 磁盘 | 无 | `Map<String,Long>` | 无 |
| `describe` | 摘要 | 无 | `String` | 无 |
| `copy` | 复制 | 无 | `SystemInfo` | 无 |

---

## 8. 使用的技术

- OS 信息查询；
- 快照；
- 映射复制。

---

## 9. 需要的支撑

- 语言：class、String、Long、Int、Double、Map；
- 运行时/OS：sysinfo/statfs；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`SystemInfo.snapshot().cpuCores()`。  
反例：用快照做精确容量规划；期望跨平台字段全有；高频采样。

---

## 13. 测试/场景义务

字段非负；usage 0..100；disks；describe；copy；缺失字段为 0/空。

---

## 14. XNull 伪代码

```xnull
class SystemInfo {
    final String _hostname
    final Long _uptimeMillis
    final Int _cpuCores
    final String _cpuModel
    final Int _cpuFrequencyMhz
    final Double _cpuUsagePercent
    final Long _memoryTotal
    final Long _memoryFree
    final Long _memoryAvailable
    final Map<String, Long> _disks

    SystemInfo(String hostname, Long uptimeMillis, Int cpuCores, String cpuModel,
               Int cpuFrequencyMhz, Double cpuUsagePercent,
               Long memoryTotal, Long memoryFree, Long memoryAvailable,
               Map<String, Long> disks) {
        _hostname = hostname
        _uptimeMillis = uptimeMillis
        _cpuCores = cpuCores
        _cpuModel = cpuModel
        _cpuFrequencyMhz = cpuFrequencyMhz
        _cpuUsagePercent = cpuUsagePercent
        _memoryTotal = memoryTotal
        _memoryFree = memoryFree
        _memoryAvailable = memoryAvailable
        _disks = disks.copy()
    }

    static SystemInfo snapshot() {
        return readSystemInfoRaw()
    }

    String hostname() { return _hostname }
    Long uptimeMillis() { return _uptimeMillis }
    Int cpuCores() { return _cpuCores }
    String cpuModel() { return _cpuModel }
    Int cpuFrequencyMhz() { return _cpuFrequencyMhz }
    Double cpuUsagePercent() { return _cpuUsagePercent }
    Long memoryTotal() { return _memoryTotal }
    Long memoryFree() { return _memoryFree }
    Long memoryAvailable() { return _memoryAvailable }
    Map<String, Long> disks() { return _disks.copy() }

    String describe() {
        return _hostname + " cores=" + str(_cpuCores)
            + " cpu=" + str(_cpuUsagePercent) + "%"
            + " mem=" + str(_memoryAvailable) + "/" + str(_memoryTotal)
            + " disks=" + str(_disks.length())
    }

    SystemInfo copy() {
        return new SystemInfo(_hostname, _uptimeMillis, _cpuCores, _cpuModel,
            _cpuFrequencyMhz, _cpuUsagePercent, _memoryTotal,
            _memoryFree, _memoryAvailable, _disks)
    }
}
```

> `readSystemInfoRaw` 是 OS/运行时快照原语。
