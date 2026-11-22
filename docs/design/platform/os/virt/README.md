# `xdk.os.virt` 虚拟化/hypervisor

| 项 | 值 |
| --- | --- |
| 包 | `xdk.os.virt` |
| 层 | os / `xdk.os` |
| 依赖 | `xdk.core`、`xdk.os` |
| 能力 | `Virtualization` |
| 稳定性 | `preview` |

---

## 1. 定位

虚拟化环境只读快照：hypervisor 类型/版本、VM 清单、当前 OS 是否在 VM 内、当前 hypervisor 名。

不做：创建/启动/停止/暂停/恢复 VM、快照/克隆/迁移、设备直通、虚拟磁盘/网络、
hypervisor 管理 API 镜像。控制面属于 X 或 ecosystem。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 只读基线 | 查询 hypervisor/VM；生命周期控制 X |
| 不透明 | `VirtualizationHost` 持有 `Long` 句柄；不暴露 fd/管理连接 |
| 最小可见 | 只返回当前上下文可见的 hypervisor/VM；VM/容器内不承诺宿主全部 |
| 权限显式 | 管理面/VM 清单读取可能 `PermissionDenied`；不重试、不提权 |
| 平台显式 | 适配器决定 KVM/Hyper-V/Xen/VMware/Parallels/QEMU TCG；不支持返回 `Unsupported` |
| 脱敏 | VM 名称/ID 可截断；不暴露磁盘/网络/密钥 |
| 快照 | 构造后不可变；列表返回副本；不自动刷新 |
| 无全局 | 由 `OsHost` 返回控制器；不提供全局单例 |

---

## 3. 类型索引

| 类型 | 种类 | 职责 | 文件 |
| --- | --- | --- | --- |
| `HypervisorKind` | enum | hypervisor 分类 | [`HypervisorKind.md`](HypervisorKind.md) |
| `Hypervisor` | class | 单个 hypervisor 条目 | [`Hypervisor.md`](Hypervisor.md) |
| `VirtualMachineState` | enum | VM 状态分类 | [`VirtualMachineState.md`](VirtualMachineState.md) |
| `VirtualMachine` | class | 单个 VM 条目 | [`VirtualMachine.md`](VirtualMachine.md) |
| `VirtualizationHost` | class | 只读查询控制器 | [`VirtualizationHost.md`](VirtualizationHost.md) |

---

## 4. 跨类型规则

- 先 `OsProfile.has(OsCapability.Virtualization)`，再调用 `OsHost.virtualization(context)`；
  缺失能力返回 `Unsupported`。
- `VirtualizationHost` 是唯一入口；`Hypervisor`/`VirtualMachine` 由适配器构造，业务代码不直接构造。
- `VirtualMachine.state()` 是 `VirtualMachineState` 快照；枚举不表示状态机/转换规则。
- `VirtualMachine.hypervisor()` 是稳定小写名，通常等于 `Hypervisor.name()`；
  `Hypervisor.kind()` 是 `HypervisorKind`。
- `Hypervisor.isHost()` true = 当前 OS 是此 hypervisor 的宿主；false = 仅客户机/管理端线索。
- `VirtualMachine.memoryBytes()`/`vcpuCount()` 是配置/可见值；`0` 表示未知；
  不是宿主全部资源。
- `VirtualizationHost.isVirtualized()` 是进程级探测；`hypervisorName()` 是当前客户机 hypervisor；
  裸机为 false/空串；无法判定时 false/空串，不 panic。
- 空列表 = 支持但当前无可见 hypervisor/VM；`Unsupported` = 能力不存在/平台不支持。
- 特权读取返回 `PermissionDenied`；不重试、不提权。
- 只读：不提供创建/启动/停止/暂停/恢复/快照/迁移/设备直通；X/ecosystem。
- `VirtualizationHost` 由调用方 `close()`；`close()` 幂等；关闭后 `hypervisors`/`virtualMachines`
  返回 `Unavailable`；`isVirtualized`/`hypervisorName` 不依赖句柄。
- VM/容器内只报告可见 VM；不得把当前 VM 的资源当作宿主总量或宿主 VM 清单。
- 与容器域无依赖：容器检测用 `ContainerHost`，虚拟化检测用 `VirtualizationHost`；
  二者可同时为 true（容器运行在 VM 内）。
- `QemuTcg` 表示 QEMU 软件模拟，不是硬件虚拟化；`HypervisorKind` 只做分类，不解析版本。

---

## 5. 场景

- 服务器启动：检测是否在 VM 内，调整 CPU/内存/时钟/许可策略。
- 监控：上报 hypervisor/VM 摘要；不写控制面。
- 桌面：只读 `isVirtualized()`，用于禁用不支持的硬件加速。
- CI/嵌套：检测嵌套虚拟化线索；不承诺完整。

---

## 6. 缺口

- VM 生命周期/控制：X，需权限与审计。
- 快照/克隆/迁移：X/ecosystem。
- 设备直通/虚拟磁盘/虚拟网络：ecosystem。
- 云厂商元数据/实例类型：`xdk.utils`/应用。
- 嵌套虚拟化完整检测：X。
- hypervisor 特定 API（libvirt/WMI/Hyper-V）：适配器 internal，不公开。
- guest agent/VM 内自省：ecosystem。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Value`、`@Builder` |
| 处理器 | 标准 A8 |
| 生成物 | Hypervisor/VM 值语义 |
| 状态 | 无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Hypervisor`/`VirtualMachine` | `@Value` | 值语义成员 |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../../ANNOTATION-CATALOG.md)。
