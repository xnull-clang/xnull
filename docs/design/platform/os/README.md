# `xdk.os` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.os` |
| 层 |  平台层 |
| 依赖 | `xdk.core`（必需）；按需 `xdk.net`、`xdk.utils` |
| 被依赖 | 桌面程序、服务器运维工具、安装器、监控 Agent |
| 稳定性 | `preview`；不进入 1.0 公共承诺 |
| 文档状态 | 基础 7 个类型 + domain 45 个类型，共 52 份类型文档已完成；desktop 已移除 |
| 文档原则 | 包级说明在本 README；所有公开类型一类型一文件；domain README 只做索引 |

---

## 1. 包定位

`xdk.os` 是 XDK 的**可选 OS/平台层**：提供 core 不适合承载的 OS 身份、硬件清单、桌面服务、
GPU 句柄、防火墙、容器、虚拟化和系统服务管理。

它不替代 core：

```text
xdk.sys    进程/环境/平台摘要
xdk.fs     文件/目录/路径
xdk.io     流/Stdio
core.net    网络传输/协议
xdk.os      OS 身份 + CPU/内存/硬件/GPU/桌面/防火墙/容器/虚拟化/服务
```

不做：

- 文件/进程/网络传输的重复 API；
- 驱动、厂商 SDK、裸设备 ioctl；
- 桌面 UI 框架、窗口/控件/布局；
- 渲染/音频编解码/张量计算；
- 全局驱动注册、全局服务管理器、自动提权。

---

## 2. 为什么不是 core

| 关注点 | 放 core 的后果 |
| --- | --- |
| CPU 拓扑/亲和性 | core 被迫依赖 OS/特权模型 |
| 物理内存/DIMM | core 被迫读 `/sys`/WMI/IOKit |
| 主板/PCI/USB | 客户端安装包携带硬件清单代码 |
| GPU | core 被迫依赖 Vulkan/Metal/DX12 |
| 防火墙 | core 暴露高危特权面 |
| 桌面/音频/输入 | 服务器核心被迫依赖桌面栈 |
| 容器/虚拟化 | core 被 Linux/cgroup 细节污染 |

因此：

- **core**：只保留可移植合同 + 只读摘要（`sys.SystemInfo`、`runtime.MemoryStats`、`Platform`）；
- **xdk.os**：可选 OS/硬件/桌面服务，按需导入；
- **runtime/FFI**：OS 适配器，internal；
- **ecosystem**：驱动/厂商 SDK/裸设备。

---

## 3. 设计原则

| 原则 | 说明 |
| --- | --- |
| 可选 | 不导入 `xdk.os` 不影响 core 程序 |
| 可失败 | 无能/无权限/取消分别返回 `Unsupported`/`PermissionDenied`/`Cancelled` |
| 不透明 | 设备/控制器用 `Long` 句柄；不暴露 fd/指针 |
| 显式关闭 | 控制器/设备必须 `close()`；close 幂等 |
| 只读优先 | 硬件清单默认只读；写操作显式命名 |
| 无全局 | 由 `OsHost`/控制器持有，不提供全局驱动注册 |
| 能力门控 | 先查 `OsProfile.has`，再调用服务 |
| 安全默认 | 防火墙/服务/裸设备默认拒绝；敏感信息不入日志 |
| 平台透明 | 公开 API 不出现 nftables/WFP/PF/X11/IOKit/DXGI |

---

## 4. 分层与依赖

```text
Application
  │
  ├─ xdk.os.*        （可选）
  │    ├─ xdk.os.cpu / memory / hardware / storage / gpu
  │    ├─ xdk.os.firewall / container / virt / service
  │    ├─ xdk.os（OsKind/OsFamily/OsCapability/OsInfo/OsProfile）
  │    └─ xdk.os.host（OsHost/Os）
  │
  ├─ xdk.net.*       L5
  ├─ core packages   L1–L3
  ├─ data/encoding   L4
  ▼
runtime / FFI       P2 适配器
  ▼
OS / 硬件           P3
```

规则：

- `xdk.os` 可以依赖 core/net/L4 服务包；core/net 不得依赖 `xdk.os`。
- 子包之间只允许下层依赖：`xdk.os` 基础类型不依赖 domain/host；domain 包依赖 `xdk.os` 基础类型；`xdk.os.host` 依赖全部 domain。
- 不提供 `xdk.os.linux`/`xdk.os.windows` 公共包；OS 适配器是 internal。

---

## 5. 包图

| 包 | 职责 | 主要类型 |
| --- | --- | --- |
| `xdk.os` | OS 身份、能力、画像（基础） | `OsKind`、`OsFamily`、`OsCapability`、`OsInfo`、`OsProfile` |
| [`xdk.os.host`](host/README.md) | 宿主聚合与静态入口 | `OsHost`、`Os` |
| [`xdk.os.cpu`](cpu/README.md) | CPU 拓扑/缓存/亲和性 | `CpuTopology`、`CpuCore`、`CpuCache`、`CpuCacheKind`、`CpuAffinity` |
| [`xdk.os.memory`](memory/README.md) | 物理内存/DIMM/NUMA | `PhysicalMemory`、`MemoryModule`、`NumaNode`、（X）`MappedRegion` |
| [`xdk.os.hardware`](hardware/README.md) | 主板/BIOS/PCI/USB/传感器 | `HardwareInventory`、`BoardInfo`、`BiosInfo`、`PciDevice`、`UsbDevice`、`SensorKind`、`SensorReading` |
| [`xdk.os.storage`](storage/README.md) | 磁盘/分区/SMART | `StorageInventory`、`StorageDevice`、`Partition`、`SmartHealth`、`SmartInfo` |
| [`xdk.os.gpu`](gpu/README.md) | GPU 适配器/设备/队列 | `GpuBackend`、`GpuAdapter`、`GpuDevice`、`GpuMemoryInfo`、`GpuQueueKind`、`GpuQueue` |
| [`xdk.os.firewall`](firewall/README.md) | 防火墙 | `FirewallAction`、`FirewallDirection`、`FirewallProtocol`、`FirewallRule`、`FirewallStatus`、`FirewallController` |
| [`xdk.os.container`](container/README.md) | 容器/cgroup/namespace | `NamespaceKind`、`Namespace`、`Cgroup`、`ContainerInfo`、`ContainerHost` |
| [`xdk.os.virt`](virt/README.md) | hypervisor/VM | `HypervisorKind`、`Hypervisor`、`VirtualMachineState`、`VirtualMachine`、`VirtualizationHost` |
| [`xdk.os.service`](service/README.md) | 系统服务 | `ServiceState`、`ServiceInfo`、`ServiceManager` |

---

## 6. 基础类型索引

| 类型 | 种类 | 文件 |
| --- | --- | --- |
| `OsKind` | enum | [`OsKind.md`](OsKind.md) |
| `OsFamily` | enum | [`OsFamily.md`](OsFamily.md) |
| `OsCapability` | enum | [`OsCapability.md`](OsCapability.md) |
| `OsInfo` | class | [`OsInfo.md`](OsInfo.md) |
| `OsProfile` | class | [`OsProfile.md`](OsProfile.md) |
| `OsHost` | protocol | [`host/OsHost.md`](host/OsHost.md) |
| `Os` | class（静态入口） | [`host/Os.md`](host/Os.md) |

---

## 7. `xdk.os.host.OsHost` 服务面

| 方法 | 能力 | 返回 | 说明 |
| --- | --- | --- | --- |
| `profile` | 无 | `OsProfile` | 非阻塞快照 |
| `cpuTopology` | `CpuTopology` | `Result<CpuTopology, Error>` | 只读 |
| `cpuAffinity` | `CpuAffinity` | `Result<CpuAffinity, Error>` | 控制器 |
| `physicalMemory` | `PhysicalMemory` | `Result<PhysicalMemory, Error>` | 只读 |
| `hardwareInventory` | `Pci`/`Usb`/`Sensors` | `Result<HardwareInventory, Error>` | 只读 |
| `storageInventory` | `Storage` | `Result<StorageInventory, Error>` | 只读 |
| `gpuAdapters` | `Gpu` | `Result<List<GpuAdapter>, Error>` | 只读 |
| `firewall` | `Firewall` | `Result<FirewallController, Error>` | 控制器，特权 |
| `containers` | `Container` | `Result<ContainerHost, Error>` | 控制器 |
| `virtualization` | `Virtualization` | `Result<VirtualizationHost, Error>` | 控制器 |
| `services` | `ServiceManager` | `Result<ServiceManager, Error>` | 控制器，特权 |
| `sensors` | `Sensors` | `Result<List<SensorReading>, Error>` | 只读 |

规则：

- 先 `profile.has(capability)`，再调用；缺失返回 `Unsupported`。
- 能力存在也可能 `PermissionDenied`。
- 控制器由调用方 `close()`；`OsHost.close()` 不替调用方关闭。
- 列表为空 = 支持但当前无设备；`Unsupported` = 能力不存在。

---

## 8. 平台适配器

```text
xdk.os.* 公开 API
  → OsHost（protocol）
  → NativeOsHost（internal，按 OS 选择）
  → *Raw 原语（FFI）
  → Linux / Windows / macOS / Android / iOS / WASM
```

| OS | CPU/内存/硬件 | GPU | 防火墙 | 服务 |
| --- | --- | --- | --- | --- |
| Linux | `/proc`、`/sys`、udev、netlink | Vulkan/Mesa/DRM | nftables/iptables | systemd |
| Windows | WMI/SetupAPI/registry | DXGI/D3D12 | WFP | SCM |
| macOS | sysctl/IOKit | Metal | PF | launchd |
| Android | HAL/JNI | Vulkan/GLES | 无/不暴露 | init |
| iOS | Darwin/IOKit 子集 | Metal | 无/不暴露 | launchd 子集 |
| WASM | 宿主导入 | WebGPU（可选） | 无 | 无 |

规则：

- 适配器只做 OS 调用 + 错误映射；不决定业务策略。
- 适配器名称/错误不进入公开签名。
- 不支持的能力返回 `Unsupported`，不 panic、不模拟。
- 公开 API 不出现 OS 头文件类型/裸句柄。

---

## 9. 客户端/服务器用法

### 9.1 无头服务器

```xnull
OsHost host = Os.host()
OsProfile profile = host.profile()
if profile.has(OsCapability.CpuTopology) {
    Result<CpuTopology, Error> cpu = host.cpuTopology(ctx)
}
if profile.has(OsCapability.Firewall) {
    Result<FirewallController, Error> firewall = host.firewall(ctx)
}
if profile.has(OsCapability.Container) {
    Result<ContainerHost, Error> containers = host.containers(ctx)
}
```

### 9.3 CLI 诊断

```xnull
OsInfo info = Os.info()
print(info.describe())
OsProfile profile = Os.profile()
print(profile.describe())
```

---

## 10. 安全与权限

| 能力 | 默认 | 失败 | 审计 |
| --- | --- | --- | --- |
| CPU/内存/硬件/存储读取 | 允许 | `PermissionDenied`/`Unsupported` | 敏感字段脱敏 |
| GPU 枚举/打开 | 允许 | `Unsupported` | 记录后端/驱动 |
| 显示/音频/输入读取 | 允许 | `Unsupported` | 桌面隐私提示 |
| 剪贴板/通知/URI | 按需 | `PermissionDenied` | 不记录内容 |
| CPU 亲和性 | 允许读 | `PermissionDenied` | 写操作记录 |
| 防火墙 | 只读默认 | `PermissionDenied`/`Unsupported` | 写操作必须审计 |
| 容器/cgroup | 只读默认 | `PermissionDenied`/`Unsupported` | 不写控制 |
| 虚拟化 | 只读默认 | `PermissionDenied`/`Unsupported` | 写操作 X |
| 系统服务 | 只读默认 | `PermissionDenied`/`Unsupported` | 写操作必须审计 |
| 裸设备 | 禁止 | `Unsupported`/`PermissionDenied` | 必须审计 |

规则：

- 不提权、不自动重试 `PermissionDenied`。
- 不把序列号、MAC、UUID、防火墙规则、剪贴板内容、服务环境写入日志/错误详情。
- 所有特权句柄 `close()`；关闭失败只诊断。
- 容器内返回可见资源，不承诺宿主全部。

---

## 11. 场景

### O1：服务器启动

`Os.profile()` → CPU 拓扑/物理内存/PCI → 防火墙状态 → 容器/cgroup → 调整资源池与监听。

### O2：安装器/运维 CLI

`ServiceManager` 启停服务；`FirewallController` 应用最小规则；失败回滚并审计。

### O3：GPU 计算节点

无头 Linux；`Gpu`/`GpuCompute`；打开设备/队列；不要求显示能力。

### O4：WASM/沙箱

`OsKind.Wasm`；CPU/内存/硬件/防火墙均 `Unsupported`；只提供宿主暴露的 CPU/GPU/存储子集。

---

## 12. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 硬件驱动/固件 | 不做；ecosystem/FFI |
| 裸设备 | 不公开；`RawDevice` 能力只表示目标支持 |
| 显示模式切换/亮度 | X |
| 音频流/输入事件 | X |
| 防火墙完整表达式 | X；基线类型化规则 |
| 容器创建/编排 | ecosystem |
| VM 生命周期 | X |
| 服务日志/单元写入 | X/ecosystem |
| mmap/共享内存 | X `MappedRegion` |
| 设备热插拔事件 | X `DeviceWatcher` |
| 全局驱动/服务注册 | 不做 |

---

## 13. 验收谓词

- `xdk.core`/`xdk.net` 不依赖 `xdk.os`。
- 不导入 `xdk.os` 时，core 程序行为不变。
- 每个服务方法先查能力；缺失返回 `Unsupported`。
- 无权限返回 `PermissionDenied`；取消返回 `Cancelled`；不 panic。
- 所有控制器/设备 `close()` 幂等；关闭后 `Unavailable`。
- 公开签名不出现 OS 头文件/裸 fd/指针/`nftables`/`WFP`/`X11` 等平台类型。
- 客户端默认不要求入站/服务/防火墙能力；服务器默认不要求显示/音频/输入。
- 敏感字段不入日志；写操作可审计。
- Linux/Windows/macOS/Android/iOS/WASM 差异只在适配器实现。

---

## 14. 变更记录

- 2026-11-21：首版。定义 `xdk.os`  包、`OsHost` 服务面、CPU/内存/硬件/存储/GPU/桌面/防火墙/容器/虚拟化/服务域，以及适配器与安全边界。
