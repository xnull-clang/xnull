# `xdk.core` 与平台/硬件边界设计

| 项 | 值 |
| --- | --- |
| 文档性质 | 核心层边界设计；回答“哪些进 core、哪些进平台层、哪些进生态” |
| 范围 | Linux/Windows/macOS/Android/iOS/WASM；CPU/内存/主板/GPU/防火墙/容器/虚拟化 |
| 目标 | 让 `xdk.core` 保持可移植；让硬件/OS 差异有明确归属；不把驱动/SDK 塞进核心 |
| 规则 | 只写设计与 XNull 声明；不写实现；不改变语言语法 |
| 状态 | 2.x Draft；UI/desktop/显示/音频/输入/电源服务不在本基线 |
| 落地文档 | [`../platform/os/README.md`](../platform/os/README.md)、[`../PACKAGE-MAP.md`](../PACKAGE-MAP.md) |

---

## 1. 结论

### 1.1 四句话

1. **`xdk.core` 不是硬件抽象层（HAL）。** core 只拥有“所有程序都需要的可移植合同 + 只读摘要”。
2. **OS/硬件差异由平台适配器吸收。** 适配器属于 runtime/FFI 的内部实现，不是公开 XDK 类型。
3. **可选硬件/OS 服务属于 `xdk.os.*`。** 按需导入，不进入 core。
4. **驱动、厂商 SDK、裸设备访问属于 ecosystem。** 不进 XDK，最多通过 FFI 适配。

### 1.2 一句话归属

```text
core        = 可移植合同 + 只读摘要（时间/文件/进程/环境/基础系统信息）
platform    = 可选硬件/OS 服务（CPU 拓扑/物理内存/主板/PCI/GPU/防火墙/容器/虚拟化）
network     = 网络传输与协议（TCP/UDP/TLS/HTTP/WS）
runtime/FFI = OS 适配器与原生句柄（不公开）
ecosystem   = 驱动、厂商 SDK、发行版集成
```

### 1.3 关键决策

- `xdk.sys.SystemInfo` 保留在 core，但只承诺**只读、粗粒度、跨平台尽力**的摘要；
- `xdk.runtime.MemoryStats` 是**堆/GC**统计，不是物理内存条；
- 物理内存/DIMM/NUMA 归 `xdk.os.memory`；
- CPU 摘要归 `xdk.sys.SystemInfo`；拓扑/亲和性/ISA 特性归 `xdk.os.cpu`；
- 主板/BIOS/SMBIOS/PCI/USB/传感器归 `xdk.os.hardware`；
- GPU 归 `xdk.os.gpu`；core 只给 `bytes/time/execution` 和不透明句柄；
- 防火墙归 `xdk.os.firewall`；core 只给 `Capability.Firewall` 和错误映射；
- 容器/cgroup/namespace 归 `xdk.os.container`；
- 虚拟化/hypervisor 归 `xdk.os.virt`；
- 系统服务管理归 `xdk.os.service`；
- 显示/窗口/音频/输入/电源/剪贴板/通知/托盘/文件对话框**不在 2.x 基线**；
- `xdk.os.OsInfo.desktop` 只保留为 OS 会话标识字符串，不是 UI 服务；
- 驱动/裸设备/厂商 SDK 归 ecosystem。

---

## 2. 两条轴：XDK 分层轴与平台轴

不要把“层”和“平台”混成一个编号。

### 2.1 XDK 分层轴

```text
L8  solutions            api/db/ml/agent/numerics/jsonrpc/mcp/accel/embedded
L7  services             validate/cache/queue/schedule/event/resilience/
                         metrics/trace/audit/terminal/i18n/test
L6  platform             os.* + gpu/tensor/linalg/geo/serial/device
L5  network              net/uri/mime/tls/http/websocket/net.service/jwt/sql
L4  data/encoding        codec/crypto/compress/random/uuid/stats/
                         functional/graph/reflect/toml/yaml/xml
L3  core system          io/fs/sys/log/config/cli
L2  core foundation      errors/meta/bytes/text/collections/math/time
L1  runtime/execution    RuntimeMonitor/Context/tasks/sync
L0  language/compiler    annotations
```

### 2.2 平台轴

平台轴描述“代码跑在什么宿主上”，与 XDK 层正交：

```text
P0  语言/VM            内存、GC、线程、调度、FFI 原语
P1  可移植合同          xdk.core / xdk.net 的公开面
P2  平台适配器          runtime/FFI 内部的 Linux/Windows/macOS/Android/WASM 实现
P3  OS/原生世界         syscalls、驱动、系统服务、厂商 SDK
```

关系：

```text
L0..L8 XDK 层
   │ 公开 API 只通过 P1
   ▼
P2 平台适配器（internal）
   │ 只通过 FFI 合同
   ▼
P3 OS/硬件
```

规则：

- **P2 不是公开包。** 不写 `import xdk.os.linux` 去拿 syscall；Linux 实现隐藏在 `systemInfoRaw`/`fileOpenRaw`/`firewallRaw` 等原语后面。
- **P3 不进 core。** 驱动/厂商 SDK 不产生 XDK 公共类型。
- **P1 不依赖 P2 的具体类型。** 只依赖 internal 原语和 portable 值。

---

## 3. 判定规则

一个能力要进哪一层，按顺序回答：

| # | 问题 | 是 → | 否 → |
| --- | --- | --- | --- |
| 1 | 每个程序在每类目标上运行都需要它吗？ | core | 下一问 |
| 2 | 它是只读、粗粒度、跨平台语义可统一的摘要吗？ | core（如 `SystemInfo`） | 下一问 |
| 3 | 它需要 OS 特权、驱动、厂商 SDK 或裸设备吗？ | platform / ecosystem | 下一问 |
| 4 | 它是网络传输/协议吗？ | L5 `xdk.net.*` | 下一问 |
| 5 | 它是数据编码/压缩/加密/统计/图/缓存等通用能力吗？ | L4/L7 | 下一问 |
| 6 | 它是容器/虚拟化/服务管理/防火墙吗？ | `xdk.os.*` | 下一问 |
| 7 | 它只服务某个应用/厂商/发行版吗？ | ecosystem | 重新评估 |

补充规则：

- **只读摘要进 core，控制面进 platform。** 例：`SystemInfo.cpuCores()` 进 core；`CpuAffinity.set()` 进 platform。
- **跨平台语义能统一才进 core。** 不能统一的（防火墙规则、GPU 命令队列）不要伪装成 core。
- **特权操作必须显式能力 + 失败分类。** 无权限返回 `PermissionDenied`，无实现返回 `Unsupported`。
- **不提供全局探测/全局驱动注册。** 由调用方持有 `OsHost`/`HardwareInventory`。
- **不把 OS 字符串当能力。** 用 `OsCapability`/`Capability`，不用 `if os == "linux"` 散落业务。
- **不做 UI/desktop 抽象。** 窗口/合成器/控件树/剪贴板/通知/托盘/文件对话框不在 2.x。

---

## 4. 归属总表

| 关注点 | 典型内容 | 公开 API 位置 | 实现位置 | 层级 |
| --- | --- | --- | --- | --- |
| 堆/GC 内存 | heap used/total、peak、GC 次数 | `xdk.runtime.MemoryStats` | runtime | core |
| 物理内存 | 总量/可用、DIMM、ECC、NUMA | `xdk.os.memory` | FFI/OS | platform |
| 地址空间/映射 | mmap、共享内存、锁定页 | `xdk.os.memory` | FFI/OS | platform |
| CPU 摘要 | 核数、型号、频率、使用率 | `xdk.sys.SystemInfo` | FFI/OS | core |
| CPU 拓扑 | socket/core/thread、NUMA、缓存层级 | `xdk.os.cpu.CpuTopology` | FFI/OS | platform |
| CPU 亲和性 | 绑核、优先级、实时策略 | `xdk.os.cpu.CpuAffinity` | FFI/OS | platform |
| CPU 特性 | SSE/AVX/NEON/RISC-V 扩展 | `xdk.os.cpu` | FFI/OS | platform |
| 主板/BIOS | 厂商、型号、序列号、SMBIOS | `xdk.os.hardware.BoardInfo/BiosInfo` | FFI/OS | platform |
| PCI/USB/雷电 | 设备树、厂商/设备 ID、驱动 | `xdk.os.hardware.PciDevice/UsbDevice` | FFI/OS | platform |
| 传感器 | 温度、风扇、电压 | `xdk.os.hardware.SensorReading` | FFI/OS | platform |
| GPU | 适配器、显存、队列、后端 | `xdk.os.gpu` + `xdk.gpu` | FFI/厂商 SDK | platform |
| 防火墙 | 规则、状态、审计 | `xdk.os.firewall` | FFI/OS 特权 | platform |
| 网络接口/地址 | 网卡、IP、MTU、统计 | `xdk.net.NetworkInterface` | FFI/OS | network |
| 网络传输/协议 | TCP/UDP/TLS/HTTP/WS | `xdk.net.*` | FFI/runtime | network |
| 容器 | cgroup/namespace/容器信息 | `xdk.os.container` | FFI/OS | platform |
| 虚拟化 | hypervisor/VM/设备直通 | `xdk.os.virt` | FFI/OS | platform |
| 系统服务 | 服务状态/启停 | `xdk.os.service` | FFI/OS 特权 | platform |
| 驱动/裸设备 | `/dev/*`、厂商 ioctl、内核模块 | ecosystem/FFI | vendor | 生态 |
| 文件/进程/信号/时钟 | 通用 OS 服务 | `xdk.fs`/`xdk.sys`/`xdk.io`/`xdk.time` | FFI/OS | core |
| 显示/窗口/音频/输入/电源 | 桌面/UI/媒体 | 不做 | 应用/生态 | 生态 |
| 桌面 UI 框架 | 控件、布局、渲染树 | 不做 | 应用/生态 | 生态 |

---

## 5. 内存到底放哪

“内存”至少有三层，不能混：

| 含义 | 归属 | 说明 |
| --- | --- | --- |
| 语言堆/GC | runtime（L0）+ `xdk.runtime.MemoryStats` | 对象分配、GC、峰值；不暴露分配器指针 |
| 物理内存 | `xdk.os.memory` | 总量/可用/DIMM/NUMA/ECC；只读为主 |
| 地址空间/映射 | `xdk.os.memory` | mmap、共享内存、锁定页；OS 特定 |
| 缓冲/字节 | `xdk.bytes` | `Bytes`/`BytesBuilder`/`ByteBuffer`，纯堆内存 |
| 分配器策略 | runtime（L0） | arena/GC/池；不进入 XDK 公共 API |

规则：

- core 不提供“物理内存条列表”；那是 `xdk.os.memory`。
- core 不提供 `malloc/free`；语言对象由运行时管理。
- `MemoryStats` 不能用于计费/硬配额；只是诊断快照。
- mmap/共享内存需要 `close`/解除映射，放平台层并显式生命周期。
- NUMA 亲和性属于 CPU/内存平台层，不属于 core。

---

## 6. CPU、主板、GPU、防火墙

### 6.1 CPU

| 能力 | 归属 | 理由 |
| --- | --- | --- |
| 核数/型号/频率/使用率 | core `xdk.sys.SystemInfo` | 只读摘要，跨平台可尽力统一 |
| 拓扑/缓存/NUMA | `xdk.os.cpu` | OS/架构差异大 |
| 亲和性/优先级/实时策略 | `xdk.os.cpu` | 特权/OS 特定 |
| ISA 特性/向量宽度 | `xdk.os.cpu` | 编译器/运行时也关心，但不属于通用 core |
| 调度器/线程池 | runtime | 语言执行层 |

### 6.2 主板/BIOS/PCI/USB

- `xdk.os.hardware` 提供**只读清单**：`HardwareInventory`、`BoardInfo`、`BiosInfo`、`PciDevice`、`UsbDevice`、`SensorReading`。
- 设备写入、固件升级、驱动绑定、ioctl 属于 ecosystem/FFI；不提供公共“写寄存器”API。
- 序列号/UDID/MAC 等敏感标识默认脱敏；需要时显式 `withSensitive()`，并记录审计。
- Linux 实现通常读 `/sys`、`/proc`、udev；Windows 用 SetupAPI/WMI；macOS 用 IOKit。

### 6.3 GPU

- `xdk.os.gpu` 提供：
  - `GpuAdapter`：厂商/型号/后端/显存；
  - `GpuDevice`：逻辑设备/队列/能力；
  - `GpuBackend`：Vulkan/Metal/Direct3D/WebGPU/Compute-only；
  - `GpuMemoryInfo`、`GpuQueue`。
- `xdk.gpu` 在 `xdk.os.gpu` 之上提供计算用 buffer/program/pipeline/command/fence；不做渲染/显示/交换链。
- core 只提供 `Bytes`/`Time`/`Execution`/`Context` 和错误；不提供 GPU 类型、着色器、命令缓冲。
- 后端实现由 FFI/厂商 SDK 提供；不把 Vulkan/DX12/Metal 头文件塞进 core。
- GPU 句柄必须 `close()`；显存所有权显式；禁止把裸指针暴露给应用。

### 6.4 防火墙

- 防火墙是**特权安全策略**，不是 core 原语。
- `xdk.os.firewall` 提供：
  - `FirewallController`：查询/添加/删除规则、启用/禁用、审计；
  - `FirewallRule`：方向、协议、地址/端口、动作、优先级；
  - `FirewallStatus`：启用状态、默认策略、规则数、后端。
- Linux 后端：nftables（首选）/iptables；Windows：WFP；macOS：PF。
- core 只提供 `Capability.Firewall`、`PermissionDenied`/`Unsupported` 错误映射；不提供规则字符串。
- 默认拒绝危险操作：需要显式权限/管理员/审计；不得静默修改防火墙。
- 不把防火墙规则写进日志/错误详情；敏感地址脱敏。

---

## 7. 服务器与 Linux 的实际差异

### 7.1 无头服务器

```text
core.server()
  + xdk.os.cpu/memory/hardware（只读）
  + xdk.os.firewall
  + xdk.os.container（可选）
  + xdk.net.tcp/tls/http/websocket（入站）
```

需要：

- CPU/内存/网卡/磁盘摘要；
- 防火墙/容器/cgroup；
- 监听、TLS 服务端、优雅停机；
- 健康/就绪/指标。

不需要：GPU 渲染、显示、音频、输入、桌面通知。

### 7.2 WASM/沙箱

```text
core.client()
  + 宿主暴露的 xdk.os.* 子集
  + xdk.net.http/websocket（出站）
```

规则：

- CPU/内存/硬件/防火墙/容器/虚拟化通常 `Unsupported`；
- 不模拟原生句柄；
- 只暴露宿主明确提供的能力；
- 无全局探测。

### 7.3 Linux 发行版差异

Linux 内部也不统一：

| 关注点 | 可能的实现 | 公开边界 |
| --- | --- | --- |
| 系统信息 | `/proc`、`/sys`、`sysinfo` | core `SystemInfo` 摘要 |
| 设备树 | sysfs、udev、netlink | `xdk.os.hardware` |
| 防火墙 | nftables、iptables、eBPF | `xdk.os.firewall` |
| 容器 | cgroup v1/v2、namespace | `xdk.os.container` |
| GPU | Mesa、厂商驱动、Vulkan | `xdk.os.gpu` / `xdk.gpu` |
| 文件/进程/信号 | POSIX、`/proc` | `xdk.fs`/`xdk.sys` |

规则：发行版差异由适配器处理；公开 API 不出现 `nftables`/`/sys`/`X11` 类型。

---

## 8. 公开 API 与适配器

### 8.1 公开面

- `xdk.core`：可移植合同 + 只读摘要。
- `xdk.net`：网络传输/协议。
- `xdk.os.*`：可选硬件/OS 服务。
- `xdk.gpu`/`xdk.tensor`/`xdk.linalg`/`xdk.geo`/`xdk.serial`/`xdk.device`：平台/计算能力。

### 8.2 适配器面（internal）

适配器原语不是公共 API，不出现在公开签名：

| 原语 | 用途 | 返回 | 失败 |
| --- | --- | --- | --- |
| `systemInfoRaw()` | 系统摘要 | `SystemInfoSnapshot` | 无；缺失字段 0/空 |
| `cpuTopologyRaw()` | CPU 拓扑 | `CpuTopologySnapshot` | `Unsupported`/`PermissionDenied` |
| `physicalMemoryRaw()` | 物理内存 | `MemoryInventorySnapshot` | 同上 |
| `hardwareInventoryRaw()` | 主板/PCI/USB | `HardwareSnapshot` | 同上 |
| `gpuAdaptersRaw()` | GPU 清单 | `List<GpuAdapterSnapshot>` | 同上 |
| `firewallStatusRaw()` | 防火墙状态 | `FirewallStatusSnapshot` | 同上 |
| `firewallApplyRaw(rule)` | 应用规则 | `Unit` | `PermissionDenied`/`Unsupported` |

规则：

- 适配器只返回**值快照/句柄**；不返回裸指针。
- 句柄必须有不透明类型 + `close()`；关闭幂等。
- 适配器不决定业务策略；只做 OS 调用 + 错误映射。
- 适配器可以按平台编译，但公开签名不出现平台类型。

### 8.3 能力拆分

`xdk.meta.Capability` 保持“构建目标支持”的粗粒度语义，不膨胀为硬件清单。OS 能力使用 `xdk.os.OsCapability`，成员见 [`platform/os/OsCapability.md`](../platform/os/OsCapability.md)。不要在本文件复制第二份枚举。

`xdk.os.OsProfile` 是平台画像，与 `CoreProfile` 组合，不替代它：

```xnull
class OsProfile {
    final OsKind _kind
    final List<OsCapability> _capabilities
    final String _name

    OsProfile(OsKind kind, List<OsCapability> capabilities, String name) {
        if kind == null || capabilities == null || name == null || name == "" {
            throw "OsProfile: invalid argument"
        }
        _kind = kind
        _name = name
        _capabilities = []
        Int index = 0
        while index < capabilities.length() {
            OsCapability capability = capabilities.get(index)
            if capability == null { throw "OsProfile: null capability" }
            if !self.has(capability) { _capabilities.push(capability) }
            index = index + 1
        }
    }

    Bool has(OsCapability capability) {
        if capability == null { throw "OsProfile.has: null" }
        Int index = 0
        while index < _capabilities.length() {
            if _capabilities.get(index) == capability { return true }
            index = index + 1
        }
        return false
    }

    List<OsCapability> capabilities() {
        List<OsCapability> result = []
        Int index = 0
        while index < _capabilities.length() {
            result.push(_capabilities.get(index))
            index = index + 1
        }
        return result
    }

    OsKind kind() { return _kind }
    String name() { return _name }

    OsProfile withCapability(OsCapability capability) {
        if capability == null { throw "OsProfile.withCapability: null" }
        List<OsCapability> next = self.capabilities()
        if !self.has(capability) { next.push(capability) }
        return new OsProfile(_kind, next, _name)
    }

    String describe() {
        return "os " + _name
            + " kind=" + osKindName(_kind)
            + " capabilities=" + str(_capabilities.length())
    }
}
```

> 这段是设计草案，不是冻结 API；具体文件在 `platform/os` 批次按“一类型一文件”落地。

---

## 9. 建议的包图

> `xdk.os` 的正式包设计见 [`../platform/os/README.md`](../platform/os/README.md)；本节保留边界分析中的包图摘要。

| 包 | 类型（示例） | 说明 |
| --- | --- | --- |
| `xdk.os` | `OsKind`、`OsFamily`、`OsCapability`、`OsInfo`、`OsProfile` | 平台公共基座 |
| `xdk.os.host` | `OsHost`、`Os` | 宿主聚合与静态入口 |
| `xdk.os.cpu` | `CpuTopology`、`CpuCore`、`CpuCache`、`CpuAffinity` | 拓扑/亲和性/缓存 |
| `xdk.os.memory` | `PhysicalMemory`、`MemoryModule`、`NumaNode` | 物理内存/NUMA |
| `xdk.os.hardware` | `HardwareInventory`、`BoardInfo`、`BiosInfo`、`PciDevice`、`UsbDevice`、`SensorReading` | 主板/总线/传感器 |
| `xdk.os.storage` | `StorageInventory`、`StorageDevice`、`Partition`、`SmartHealth`、`SmartInfo` | 磁盘/分区/SMART |
| `xdk.os.gpu` | `GpuAdapter`、`GpuDevice`、`GpuBackend`、`GpuMemoryInfo`、`GpuQueue` | GPU 适配器/设备/队列 |
| `xdk.os.firewall` | `FirewallController`、`FirewallRule`、`FirewallStatus` | 防火墙 |
| `xdk.os.container` | `ContainerInfo`、`Cgroup`、`Namespace`、`ContainerHost` | 容器 |
| `xdk.os.virt` | `Hypervisor`、`VirtualMachine`、`VirtualizationHost` | 虚拟化 |
| `xdk.os.service` | `ServiceState`、`ServiceInfo`、`ServiceManager` | 系统服务 |
| `xdk.gpu` | `GpuBuffer`、`GpuProgram`、`GpuPipeline`、`GpuCommandBuffer`、`GpuFence`、`GpuCompute` | 高层 GPU 计算 |

规则：

- 这些包是**可选平台服务**，不是 core；应用按需导入。
- `xdk.core` 不得依赖 `xdk.os.*`。
- `xdk.os.*` 可以依赖 core/net/L4 服务，但不得反向依赖应用。
- OS 专用适配器（`linux`/`windows`/`macos`）是 **internal 实现**，不是公开包名。
- 驱动/厂商 SDK 不进表；它们通过 FFI 适配，属于 ecosystem。

---

## 10. 与客户端/服务器画像结合

`CoreProfile` 保持“语言/运行时/网络能力”；`OsProfile` 表达“这台服务器/这个沙箱有什么硬件/OS 服务”。

无头服务器：

```xnull
CoreProfile coreProfile = CoreProfile.server()
OsProfile platformProfile = new OsProfile(
    OsKind.Linux,
    [OsCapability.CpuTopology, OsCapability.PhysicalMemory,
     OsCapability.Pci, OsCapability.Firewall,
     OsCapability.Container],
    "linux-server"
)
```

GPU 计算节点：

```xnull
OsProfile platformProfile = new OsProfile(
    OsKind.Linux,
    [OsCapability.CpuTopology, OsCapability.PhysicalMemory,
     OsCapability.Gpu, OsCapability.GpuCompute],
    "linux-gpu-compute"
)
```

启动校验：

```text
CoreProfile.isCoherent()
  + OsProfile 能力与 TargetInfo 对账
  + 缺少必需平台能力 → Unsupported / 配置错误
```

注意：

- 服务器画像默认不声明显示/音频/输入/电源能力；这些服务不在 2.x 基线。
- 无头服务器仍可有 `GpuCompute`（计算卡），但没有显示能力；
- WASM 沙箱只声明宿主明确提供的能力。

---

## 11. 安全与权限

| 能力 | 默认 | 失败 | 审计 |
| --- | --- | --- | --- |
| 防火墙修改 | 禁止 | `PermissionDenied` | 必须 |
| 裸设备/驱动 | 禁止 | `Unsupported`/`PermissionDenied` | 必须 |
| GPU 设备创建 | 允许读清单 | `Unsupported` | 记录后端/驱动 |
| 物理内存/主板序列号 | 脱敏 | `Unsupported` | 读取敏感字段需显式 |
| 系统服务启停 | 禁止 | `PermissionDenied` | 必须 |
| 容器/虚拟化控制 | 禁止 | `PermissionDenied` | 必须 |

规则：

- core 不提供“提权”API；权限由 OS/宿主决定。
- 不在日志/错误详情写防火墙规则、密钥、序列号、MAC。
- 平台包默认只读；写操作必须显式命名（`apply`/`set`/`remove`）并返回 `Result`。
- 所有特权句柄必须 `close()`；关闭失败只诊断，资源视为释放。

---

## 12. 验收谓词

- `xdk.core` 公开签名不出现 `PciDevice`、`GpuDevice`、`FirewallRule`、`X11`、`Wayland`、`nftables` 等平台类型/字符串。
- `xdk.sys.SystemInfo` 只承诺只读摘要；物理内存/主板/GPU/防火墙不在 core。
- `xdk.runtime.MemoryStats` 只表示堆/GC；不代表物理内存。
- 平台包可独立不导入；未导入不影响 core 程序。
- 不支持的能力返回 `Unsupported`；无权限返回 `PermissionDenied`；不 panic。
- 平台适配器不暴露裸指针/裸 fd；句柄有 `close()` 且幂等。
- 服务器/沙箱画像与平台画像分离；不把 UI/desktop 能力塞进服务器默认。
- Linux/Windows/macOS/Android/iOS/WASM 的差异只出现在适配器实现，不进入公开 API。
- 0 个 UI/desktop 服务类型；`OsInfo.desktop` 仅作为会话字符串。

---

## 13. 变更记录

- 2026-11-21：首版。确定 core 不承载硬件/驱动；新增 `xdk.os.*` 边界、平台轴、CPU/内存/主板/GPU/防火墙归属与安全规则。
- 2026-11-22：2.x 架构整理；移除 UI/desktop/显示/音频/输入/电源服务；包名归一为 `xdk.*`；计数改为 75 包/698 类型。
