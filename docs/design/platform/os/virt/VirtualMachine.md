# `VirtualMachine`

| 项 | 值 |
| --- | --- |
| 类型 | `class VirtualMachine` |
| 包 | `xdk.os.virt` |
| 稳定性 | `preview` |
| 依赖 | `VirtualMachineState` |

---

## 1. 定位

单个 VM 条目的只读快照：标识、名称、状态、内存、vCPU 数、所属 hypervisor。

不做：创建/启动/停止/暂停/恢复 VM、快照/克隆/迁移、设备直通、虚拟磁盘/网络、guest 内省。

---

## 2. 设计逻辑

- 不可变快照；由 `VirtualizationHost.virtualMachines(context)` 返回。
- `id` 是 hypervisor 范围内的 VM 标识；适配器可截断；不承诺宿主全局唯一或跨重启稳定。
- `name` 是显示名；可为空；不保证唯一；不用于关联；可能敏感，日志中应截断。
- `state` 是 `VirtualMachineState` 快照；不定义转换规则，也不保证下一次查询仍相同。
- `memoryBytes` 是适配器可见的配置内存；`0` 表示未知；不是宿主总内存，也不保证是实时占用。
- `vcpuCount` 是可见 vCPU 数；`0` 表示未知；`Int` 计数。
- `hypervisor` 是稳定小写名，通常匹配 `Hypervisor.name()`；未知时可为空串。
- 不提供控制/刷新；不持有 VM 句柄。
- 为什么是 class：六个字段组成稳定快照；不用 enum 因为含开放标识/名称/数值。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_virtualMachineId` | `String` | final | 非 null；可截断/为空 |
| `_name` | `String` | final | 非 null；可为空 |
| `_state` | `VirtualMachineState` | final | 非 null |
| `_memoryBytes` | `Long` | final | ≥0；0 = 未知 |
| `_vcpuCount` | `Int` | final | ≥0；0 = 未知 |
| `_hypervisor` | `String` | final | 非 null；稳定小写；可为空 |

不变量：字符串/状态非 null；数值 ≥0；`state` 是合法枚举；不可变；无资源。

---

## 4. 生命周期

构造后不可变；无 close；可共享；无取消点。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `VirtualMachine(String virtualMachineId, String name, VirtualMachineState state, Long memoryBytes, Int vcpuCount, String hypervisor)` | 6 个字段 | 字符串/state 非 null；数值 ≥0 | null 或负数 → panic |

构造器主要供适配器/测试使用；业务代码通过 `VirtualizationHost.virtualMachines` 获取。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `id` | VM 标识 | 无 | `String` | 无 | O(1)；可截断 |
| `name` | 显示名 | 无 | `String` | 无 | O(1)；可为空 |
| `state` | 状态快照 | 无 | `VirtualMachineState` | 无 | O(1) |
| `memoryBytes` | 可见内存 | 无 | `Long` | 无 | O(1)；0 = 未知 |
| `vcpuCount` | vCPU 数 | 无 | `Int` | 无 | O(1)；0 = 未知 |
| `hypervisor` | 所属 hypervisor 名 | 无 | `String` | 无 | O(1)；可为空 |
| `describe` | 单行摘要 | 无 | `String` | 无 | O(n)；仅诊断 |

无 equals/copy：需要比较时逐字段比较；`==` 是引用身份。

---

## 8. 使用的技术

- 不可变快照；
- 枚举状态；
- 字节数 `Long`；
- 计数 `Int`；
- 字符串描述。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Long、Int、Enum；
- 运行时/适配器：VM 清单/状态读取；
- 接口：`VirtualMachineState`、`Hypervisor`、`VirtualizationHost`。

---

## 10. 依赖的特性/接口/类

`VirtualMachineState`、`Hypervisor`、`VirtualizationHost`。

---

## 11. 所有权与并发

引用语义；不可变；可跨任务共享；无资源；无取消点。
相等：`==` 是引用身份；本基线不提供 `equals`；需要比较时逐字段比较；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：按 `state()` 分类显示；用 `hypervisor()` 关联 `Hypervisor.name()`；内存/vCPU 只作展示。  
反例：假设 `id` 宿主全局唯一；假设 `name` 唯一/非空；把 `memoryBytes` 当宿主总量；
用 `state` 推断健康；把 `0` 当真实 0；把 VM 内资源当宿主全部。

---

## 13. 测试/场景义务

Running/Stopped/Paused/Unknown；`memoryBytes=0`；`vcpuCount=0`；ID 截断；空名称；
空 hypervisor；多 hypervisor；`describe`；null/负数构造 panic；VM/容器内可见性裁剪。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class VirtualMachine {
    final String _virtualMachineId
    final String _name
    final VirtualMachineState _state
    final Long _memoryBytes
    final Int _vcpuCount
    final String _hypervisor

    VirtualMachine(String virtualMachineId, String name,
                   VirtualMachineState state, Long memoryBytes,
                   Int vcpuCount, String hypervisor) {
        if virtualMachineId == null || name == null || state == null
            || hypervisor == null {
            throw "VirtualMachine: null field"
        }
        if memoryBytes < 0 || vcpuCount < 0 {
            throw "VirtualMachine: negative field"
        }
        _virtualMachineId = virtualMachineId
        _name = name
        _state = state
        _memoryBytes = memoryBytes
        _vcpuCount = vcpuCount
        _hypervisor = hypervisor
    }

    String id() { return _virtualMachineId }

    String name() { return _name }

    VirtualMachineState state() { return _state }

    Long memoryBytes() { return _memoryBytes }

    Int vcpuCount() { return _vcpuCount }

    String hypervisor() { return _hypervisor }

    String describe() {
        String label = _name
        if label == "" { label = _virtualMachineId }
        return "vm " + label
            + " state=" + virtualMachineStateName(_state)
            + " vcpu=" + str(_vcpuCount)
            + " memory=" + str(_memoryBytes)
    }
}
```
