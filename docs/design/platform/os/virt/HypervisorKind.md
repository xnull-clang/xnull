# `HypervisorKind`

| 项 | 值 |
| --- | --- |
| 类型 | `enum HypervisorKind` |
| 包 | `xdk.os.virt` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

hypervisor/虚拟化环境分类：KVM、Hyper-V、Xen、VMware、Parallels、QEMU TCG、未知。

不做：hypervisor 管理 API、VM 生命周期、设备模型、虚拟磁盘/网络、版本比较。

---

## 2. 设计逻辑

- 只区分 hypervisor/emulator 家族；名称/版本/是否宿主由 `Hypervisor` 承载。
- `Kvm` 是 Linux KVM；`HyperV` 是 Microsoft Hyper-V；`Vmware` 覆盖 VMware ESXi/Workstation/Fusion；
  `Parallels` 覆盖 Parallels Desktop；`QemuTcg` 表示 QEMU 软件模拟（TCG），不是硬件虚拟化。
- `Unknown` 是合法值：无法识别时返回 `Unknown`，不 panic、不猜测。
- 平台适配器可把同一家族的不同产品映射到同一成员；产品名放 `Hypervisor.name`。
- 值语义；可作 `Map`/`Set` 键；成员固定，只允许追加。
- 名称映射使用稳定小写名；显示名不进入协议。

---

## 3. 表示与不变量

| 成员 | 含义 | 常见平台 |
| --- | --- | --- |
| `Kvm` | Linux KVM | Linux |
| `HyperV` | Microsoft Hyper-V | Windows/Hyper-V Server |
| `Xen` | Xen hypervisor | Linux/Windows 客户机 |
| `Vmware` | VMware ESXi/Workstation/Fusion | Linux/Windows/macOS |
| `Parallels` | Parallels Desktop | macOS/Windows |
| `QemuTcg` | QEMU TCG 软件模拟 | 跨平台 |
| `Unknown` | 未知/未识别 | 任意 |

不变量：成员固定；只允许追加；值语义；`Unknown` 不携带额外语义。

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

## 7. 方法总表 / 详表

枚举无实例方法；以下为包级辅助函数。

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `hypervisorKindName` | 稳定小写名 | `HypervisorKind kind` | `String` | 无 |
| `hypervisorKindFromName` | 名称解析 | `String name` | `HypervisorKind?` | 无；null/未知返回 null |

`hypervisorKindName` 返回 `kvm`/`hyperv`/`xen`/`vmware`/`parallels`/`qemu-tcg`/`unknown`；
`hypervisorKindFromName` 同时接受 `hyper-v`、`qemutcg` 别名，大小写不敏感。

---

## 8. 使用的技术

- 简单枚举；
- 名称映射；
- 平台适配器归一。

---

## 9. 需要的支撑

- 语言：enum、String；
- 运行时：无；
- 接口：`Hypervisor`、`VirtualizationHost`。

---

## 10. 依赖的特性/接口/类

`Hypervisor`、`VirtualizationHost`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：按枚举底层值比较；可作 `Map` 键。

---

## 12. 示例与反例

正确：`hypervisor.kind() == HypervisorKind.Kvm`；日志用 `hypervisorKindName(kind)`。  
反例：把 `QemuTcg` 当硬件虚拟化；用字符串比较代替枚举；把产品版本塞进枚举；未知值 panic。

---

## 13. 测试/场景义务

每个成员名称/解析；`hyper-v`/`qemutcg` 别名；大小写与空白；未知名称；null；
`QemuTcg` 与 `Kvm` 区分；与 `Hypervisor`/`VirtualMachine` 组合。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
enum HypervisorKind {
    Kvm,
    HyperV,
    Xen,
    Vmware,
    Parallels,
    QemuTcg,
    Unknown,
}

String hypervisorKindName(HypervisorKind kind) {
    if kind == HypervisorKind.Kvm { return "kvm" }
    if kind == HypervisorKind.HyperV { return "hyperv" }
    if kind == HypervisorKind.Xen { return "xen" }
    if kind == HypervisorKind.Vmware { return "vmware" }
    if kind == HypervisorKind.Parallels { return "parallels" }
    if kind == HypervisorKind.QemuTcg { return "qemu-tcg" }
    return "unknown"
}

HypervisorKind? hypervisorKindFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "kvm" { return HypervisorKind.Kvm }
    if normalized == "hyperv" || normalized == "hyper-v" {
        return HypervisorKind.HyperV
    }
    if normalized == "xen" { return HypervisorKind.Xen }
    if normalized == "vmware" { return HypervisorKind.Vmware }
    if normalized == "parallels" { return HypervisorKind.Parallels }
    if normalized == "qemu-tcg" || normalized == "qemutcg" {
        return HypervisorKind.QemuTcg
    }
    if normalized == "unknown" { return HypervisorKind.Unknown }
    return null
}
```
