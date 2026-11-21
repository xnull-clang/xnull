# `NumaNode`

| 项 | 值 |
| --- | --- |
| 类型 | `class NumaNode` |
| 包 | `xdk.os.memory` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

NUMA 节点快照：节点 id、内存容量、可见逻辑 CPU id。

不做：NUMA 绑定、内存策略、页迁移、性能计数。

---

## 2. 设计逻辑

- 不可变快照；由 `PhysicalMemory.numaNodes()` 返回。
- `id` 是 OS 的 NUMA 节点 id；可能不连续。
- `memoryBytes` 是该节点内存；0 表示未知。
- `cpuIds` 是该节点关联的逻辑 CPU id 快照。
- 无 NUMA 支持时列表为空。
- 容器内只反映可见拓扑。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_id` | `Int` | final | ≥0 |
| `_memoryBytes` | `Long` | final | ≥0 |
| `_cpuIds` | `List<Int>` | final | 逻辑 CPU id |

不变量：id/memory ≥0；cpuIds 非 null；不可变；列表返回副本。

---

## 4. 生命周期

构造后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `NumaNode(...)` | 3 个字段 | id/memory ≥0；cpuIds 非 null | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `id` | 节点 id | 无 | `Int` | 无 |
| `memoryBytes` | 节点内存 | 无 | `Long` | 无 |
| `cpuIds` | CPU id 快照 | 无 | `List<Int>` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `equals` | 值比较 | `NumaNode other` | `Bool` | null → false |
| `copy` | 复制 | 无 | `NumaNode` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- 列表复制；
- 字符串描述。

---

## 9. 需要的支撑

- 语言：class、final 字段、Int、Long、List、Bool；
- 运行时/适配器：NUMA 信息读取；
- 接口：`PhysicalMemory`。

---

## 10. 依赖的特性/接口/类

`PhysicalMemory`、`CpuCore`、`CpuAffinity`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：`equals` 字段/列表比较；`==` 仍是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：按 `numaNodeId` 分配 worker/内存。  
反例：假设节点 id 连续；把节点内存当可用内存；容器内假设宿主全部 NUMA。

---

## 13. 测试/场景义务

单/多 NUMA；id 不连续；空 cpuIds；内存未知；equals/copy；容器裁剪。

---

## 14. XNull 伪代码

```xnull
class NumaNode {
    final Int _id
    final Long _memoryBytes
    final List<Int> _cpuIds

    NumaNode(Int nodeId, Long memoryBytes, List<Int> cpuIds) {
        if nodeId < 0 || memoryBytes < 0 || cpuIds == null {
            throw "NumaNode: invalid field"
        }
        _id = nodeId
        _memoryBytes = memoryBytes
        _cpuIds = cpuIds.copy()
    }

    Int id() { return _id }
    Long memoryBytes() { return _memoryBytes }
    List<Int> cpuIds() { return _cpuIds.copy() }

    String describe() {
        return "numa " + str(_id)
            + " memory=" + str(_memoryBytes)
            + " cpus=" + str(_cpuIds.length())
    }

    Bool equals(NumaNode other) {
        if other == null { return false }
        if _id != other.id() || _memoryBytes != other.memoryBytes() {
            return false
        }
        List<Int> values = other.cpuIds()
        if _cpuIds.length() != values.length() { return false }
        Int index = 0
        while index < _cpuIds.length() {
            if _cpuIds.get(index) != values.get(index) { return false }
            index = index + 1
        }
        return true
    }

    NumaNode copy() {
        return new NumaNode(_id, _memoryBytes, _cpuIds)
    }
}
```
