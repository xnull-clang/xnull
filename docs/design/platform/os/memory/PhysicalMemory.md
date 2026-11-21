# `PhysicalMemory`

| 项 | 值 |
| --- | --- |
| 类型 | `class PhysicalMemory` |
| 包 | `xdk.os.memory` |
| 稳定性 | `preview` |
| 依赖 | `MemoryModule`、`NumaNode` |

---

## 1. 定位

物理内存只读快照：总/空闲/可用字节、DIMM 列表、NUMA 节点。

不做：分配/释放、GC、mmap、页表、ECC 注入、热插拔。

---

## 2. 设计逻辑

- 不可变快照；由 `OsHost.physicalMemory(context)` 返回。
- 所有字节数用 `Long`；`0` 表示未知/不支持。
- `freeBytes <= totalBytes`；`availableBytes` 是 OS 估计。
- `modules`/`numaNodes` 可为空；容器内只反映可见资源。
- 不提供写入；不自动刷新。
- `describe` 用于诊断/日志，不用于精确计费。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_totalBytes` | `Long` | final | ≥0 |
| `_freeBytes` | `Long` | final | ≥0 |
| `_availableBytes` | `Long` | final | ≥0 |
| `_modules` | `List<MemoryModule>` | final | DIMM 快照 |
| `_numaNodes` | `List<NumaNode>` | final | NUMA 快照 |

不变量：字节数 ≥0；列表非 null；不可变；列表返回副本。

---

## 4. 生命周期

构造后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `PhysicalMemory(...)` | 5 个字段 | 字节 ≥0；列表非 null | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `totalBytes` | 总内存 | 无 | `Long` | 无 |
| `freeBytes` | 空闲 | 无 | `Long` | 无 |
| `availableBytes` | 可用 | 无 | `Long` | 无 |
| `modules` | DIMM 快照 | 无 | `List<MemoryModule>` | 无 |
| `numaNodes` | NUMA 快照 | 无 | `List<NumaNode>` | 无 |
| `moduleCount` | DIMM 数 | 无 | `Int` | 无 |
| `numaNodeCount` | NUMA 节点数 | 无 | `Int` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `equals` | 值比较 | `PhysicalMemory other` | `Bool` | null → false |
| `copy` | 复制 | 无 | `PhysicalMemory` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- 列表复制；
- 字节数 `Long`；
- 字符串描述。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、Int、List、Bool；
- 运行时/适配器：物理内存/NUMA 读取；
- 接口：`MemoryModule`、`NumaNode`、`OsHost`。

---

## 10. 依赖的特性/接口/类

`MemoryModule`、`NumaNode`、`OsHost`。

---

## 11. 所有权与并发

不可变；可共享；`modules/numaNodes` 返回副本；无资源；无取消点。
相等：`equals` 字段/列表比较；`==` 仍是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：启动日志记录 `describe()`；按 NUMA 节点规划 worker。  
反例：用 `freeBytes` 做分配决策；假设 DIMM 列表存在；容器内假设宿主总量；精确计费。

---

## 13. 测试/场景义务

总量/空闲/可用关系；空 DIMM/NUMA；容器裁剪；equals/copy；describe；UNKNOWN 字段 0；
多 NUMA。

---

## 14. XNull 伪代码

```xnull
class PhysicalMemory {
    final Long _totalBytes
    final Long _freeBytes
    final Long _availableBytes
    final List<MemoryModule> _modules
    final List<NumaNode> _numaNodes

    PhysicalMemory(Long totalBytes, Long freeBytes, Long availableBytes,
                   List<MemoryModule> modules, List<NumaNode> numaNodes) {
        if totalBytes < 0 || freeBytes < 0 || availableBytes < 0 {
            throw "PhysicalMemory: negative size"
        }
        if modules == null || numaNodes == null {
            throw "PhysicalMemory: null list"
        }
        _totalBytes = totalBytes
        _freeBytes = freeBytes
        _availableBytes = availableBytes
        _modules = modules.copy()
        _numaNodes = numaNodes.copy()
    }

    Long totalBytes() { return _totalBytes }
    Long freeBytes() { return _freeBytes }
    Long availableBytes() { return _availableBytes }
    List<MemoryModule> modules() { return _modules.copy() }
    List<NumaNode> numaNodes() { return _numaNodes.copy() }
    Int moduleCount() { return _modules.length() }
    Int numaNodeCount() { return _numaNodes.length() }

    String describe() {
        return "memory total=" + str(_totalBytes)
            + " free=" + str(_freeBytes)
            + " available=" + str(_availableBytes)
            + " modules=" + str(_modules.length())
            + " numa=" + str(_numaNodes.length())
    }

    Bool equals(PhysicalMemory other) {
        if other == null { return false }
        if _totalBytes != other.totalBytes()
            || _freeBytes != other.freeBytes()
            || _availableBytes != other.availableBytes() {
            return false
        }
        List<MemoryModule> otherModules = other.modules()
        if _modules.length() != otherModules.length() { return false }
        Int index = 0
        while index < _modules.length() {
            if !_modules.get(index).equals(otherModules.get(index)) {
                return false
            }
            index = index + 1
        }
        List<NumaNode> otherNodes = other.numaNodes()
        if _numaNodes.length() != otherNodes.length() { return false }
        index = 0
        while index < _numaNodes.length() {
            if !_numaNodes.get(index).equals(otherNodes.get(index)) {
                return false
            }
            index = index + 1
        }
        return true
    }

    PhysicalMemory copy() {
        return new PhysicalMemory(_totalBytes, _freeBytes, _availableBytes,
            _modules, _numaNodes)
    }
}
```
