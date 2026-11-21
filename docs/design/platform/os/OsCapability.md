# `OsCapability`

| 项 | 值 |
| --- | --- |
| 类型 | `enum OsCapability` |
| 包 | `xdk.os` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

 OS/硬件平台服务能力标记：CPU 拓扑、物理内存、PCI、GPU、防火墙、容器等。

不做：core 的 `Capability`（构建/运行时能力）、设备清单、权限模型、驱动能力。

---

## 2. 设计逻辑

- 与 core `Capability` 分开：core 表达“语言/运行时/网络是否可用”，`OsCapability` 表达“这台机器/这个 OS 是否提供某类平台服务”。
- `OsProfile` 持有能力列表；`OsHost` 按能力返回服务。
- 能力是“可能支持”，不是“一定成功”：无权限/驱动缺失仍返回 `PermissionDenied`/`Unsupported`。
- 成员固定，只允许追加；序号稳定。
- 只读清单和写控制共用能力；写权限由具体控制器检查。

---

## 3. 表示与不变量

| 成员 | 含义 | 需要特权 |
| --- | --- | --- |
| `CpuTopology` | CPU socket/core/thread/NUMA/缓存 | 否 |
| `CpuAffinity` | 绑核/亲和性 | 是 |
| `CpuFeatures` | ISA/向量特性 | 否 |
| `PhysicalMemory` | 物理内存/DIMM | 否 |
| `Numa` | NUMA 节点 | 否 |
| `Pci` | PCI/PCIe 设备 | 否 |
| `Usb` | USB 设备 | 否 |
| `Storage` | 磁盘/分区/SMART | 否 |
| `Sensors` | 温度/风扇/电压 | 否 |
| `Gpu` | GPU 适配器/设备 | 否 |
| `GpuCompute` | GPU 计算队列 | 否 |
| `Firewall` | 防火墙规则/状态 | 是 |
| `Container` | cgroup/namespace/容器 | 是 |
| `Virtualization` | hypervisor/VM | 是 |
| `ServiceManager` | 系统服务管理 | 是 |
| `RawDevice` | 裸设备/ioctl | 是 |

不变量：成员固定；只允许追加；值语义；可作 Map/Set 键。

---

## 4. 生命周期

值类型；无构造器、无 close；可共享。

---

## 5. 构造契约

枚举项直接使用，无构造器。

---

## 6. 字段表

无实例字段。

---

## 7. 方法面

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `osCapabilityName` | 稳定小写名 | `OsCapability capability` | `String` | 无 |
| `osCapabilityFromName` | 名称解析 | `String name` | `OsCapability?` | 无；未知返回 null |
| `osCapabilityRequiresPrivilege` | 是否通常需要特权 | `OsCapability capability` | `Bool` | 无 |
| `osCapabilityIsSensitive` | 是否涉及敏感信息 | `OsCapability capability` | `Bool` | 无 |

---

## 8. 使用的技术

- 简单枚举；
- 名称映射；
- 权限/敏感分类。

---

## 9. 需要的支撑

- 语言：enum、String、Bool；
- 运行时：无；
- 接口：`OsProfile`、`OsHost`。

---

## 10. 依赖的特性/接口/类

`OsProfile`、`OsHost`、`OsInfo`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。

---

## 12. 示例与反例

正确：`profile.has(OsCapability.Gpu)` 后才调用 `host.gpuAdapters(ctx)`。  
反例：把能力当运行时保证；用 core `Capability` 代替；能力存在就假设有权限。

---

## 13. 测试/场景义务

每个成员名称/解析；特权/敏感分类；服务器/无头能力矩阵；未知能力；与 `OsProfile` 查询一致。

---

## 14. XNull 伪代码

```xnull
enum OsCapability {
    CpuTopology,
    CpuAffinity,
    CpuFeatures,
    PhysicalMemory,
    Numa,
    Pci,
    Usb,
    Storage,
    Sensors,
    Gpu,
    GpuCompute,
    Firewall,
    Container,
    Virtualization,
    ServiceManager,
    RawDevice,
}

String osCapabilityName(OsCapability capability) {
    if capability == OsCapability.CpuTopology { return "cpu_topology" }
    if capability == OsCapability.CpuAffinity { return "cpu_affinity" }
    if capability == OsCapability.CpuFeatures { return "cpu_features" }
    if capability == OsCapability.PhysicalMemory { return "physical_memory" }
    if capability == OsCapability.Numa { return "numa" }
    if capability == OsCapability.Pci { return "pci" }
    if capability == OsCapability.Usb { return "usb" }
    if capability == OsCapability.Storage { return "storage" }
    if capability == OsCapability.Sensors { return "sensors" }
    if capability == OsCapability.Gpu { return "gpu" }
    if capability == OsCapability.GpuCompute { return "gpu_compute" }
    if capability == OsCapability.Firewall { return "firewall" }
    if capability == OsCapability.Container { return "container" }
    if capability == OsCapability.Virtualization { return "virtualization" }
    if capability == OsCapability.ServiceManager { return "service_manager" }
    if capability == OsCapability.RawDevice { return "raw_device" }
    return "unknown"
}

OsCapability? osCapabilityFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "cpu_topology" { return OsCapability.CpuTopology }
    if normalized == "cpu_affinity" { return OsCapability.CpuAffinity }
    if normalized == "cpu_features" { return OsCapability.CpuFeatures }
    if normalized == "physical_memory" { return OsCapability.PhysicalMemory }
    if normalized == "numa" { return OsCapability.Numa }
    if normalized == "pci" { return OsCapability.Pci }
    if normalized == "usb" { return OsCapability.Usb }
    if normalized == "storage" { return OsCapability.Storage }
    if normalized == "sensors" { return OsCapability.Sensors }
    if normalized == "gpu" { return OsCapability.Gpu }
    if normalized == "gpu_compute" { return OsCapability.GpuCompute }
    if normalized == "firewall" { return OsCapability.Firewall }
    if normalized == "container" { return OsCapability.Container }
    if normalized == "virtualization" { return OsCapability.Virtualization }
    if normalized == "service_manager" { return OsCapability.ServiceManager }
    if normalized == "raw_device" { return OsCapability.RawDevice }
    return null
}

Bool osCapabilityRequiresPrivilege(OsCapability capability) {
    if capability == OsCapability.CpuAffinity { return true }
    if capability == OsCapability.Firewall { return true }
    if capability == OsCapability.Container { return true }
    if capability == OsCapability.Virtualization { return true }
    if capability == OsCapability.ServiceManager { return true }
    if capability == OsCapability.RawDevice { return true }
    return false
}

Bool osCapabilityIsSensitive(OsCapability capability) {
    if capability == OsCapability.Pci { return true }
    if capability == OsCapability.Usb { return true }
    if capability == OsCapability.Sensors { return true }
    if capability == OsCapability.Firewall { return true }
    if capability == OsCapability.ServiceManager { return true }
    if capability == OsCapability.RawDevice { return true }
    return false
}
```
