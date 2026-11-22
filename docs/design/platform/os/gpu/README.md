# `xdk.os.gpu` GPU 适配器与设备

| 项 | 值 |
| --- | --- |
| 包 | `xdk.os.gpu` |
| 层 | os / `xdk.os` |
| 依赖 | `xdk.core`、`xdk.os` |
| 能力 | `Gpu`、`GpuCompute` |
| 稳定性 | `preview` |

---

## 1. 定位

GPU 适配器/设备/显存/队列的只读清单与显式打开的句柄。

只做：

- 适配器清单快照：厂商/型号/后端/显存/驱动版本/独显集显标记；
- 显式打开设备；
- 显式创建图形/计算/传输队列；
- 显存值快照与队列/设备的生命周期关闭。

不做：

- 着色器、渲染管线、命令缓冲、计算内核、纹理/缓冲区；
- 命令提交/同步/栅栏、显存分配；
- GPU 驱动/厂商 SDK、Vulkan/Metal/Direct3D12 API 镜像；
- 显示模式、窗口/合成、桌面集成。

上述能力归 X（`GpuCommand`/`GpuBuffer`/`GpuFence`）、`xdk.gpu` 高层包或 ecosystem/FFI。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 清单只读 | 适配器清单只读；打开设备/创建队列显式命名 |
| 不透明句柄 | 设备/队列用 `Long`；不暴露裸指针/fd/后端句柄 |
| 后端显式 | `GpuBackend` 标明 Vulkan/Metal/Direct3D12/OpenGL/WebGpu/ComputeOnly/Unknown |
| 资源所有权 | `GpuDevice`/`GpuQueue` 必须 `close()`；close 幂等；设备关闭使队列失效 |
| 失败显式 | 无能力/无权限/取消返回 `Unsupported`/`PermissionDenied`/`Cancelled` |
| 无全局 | 由 `OsHost.gpuAdapters` 返回；不提供全局设备注册 |
| 只做句柄 | 不提交命令/同步/分配；队列只表示生命周期句柄 |
| 平台透明 | 不出现 VkDevice/MTLDevice/ID3D12Device/EGL/GLX 头文件类型或扩展字符串；后端只用 `GpuBackend` 枚举名 |

---

## 3. 类型索引

| 类型 | 种类 | 角色 | 文件 |
| --- | --- | --- | --- |
| `GpuBackend` | enum | 后端家族 | [`GpuBackend.md`](GpuBackend.md) |
| `GpuAdapter` | class | 适配器只读快照 + 打开入口 | [`GpuAdapter.md`](GpuAdapter.md) |
| `GpuDevice` | class | 打开的 GPU 设备句柄 | [`GpuDevice.md`](GpuDevice.md) |
| `GpuMemoryInfo` | class | 显存值快照 | [`GpuMemoryInfo.md`](GpuMemoryInfo.md) |
| `GpuQueueKind` | enum | 队列用途 | [`GpuQueueKind.md`](GpuQueueKind.md) |
| `GpuQueue` | class | 已创建的队列句柄 | [`GpuQueue.md`](GpuQueue.md) |

---

## 4. 跨类型规则

- 能力门控：先 `OsProfile.has(OsCapability.Gpu)`，再调用 `OsHost.gpuAdapters(context)`；缺失返回 `Unsupported`。`GpuCompute` 门控计算队列；实现必须在缺失时让 `createQueue(context, GpuQueueKind.Compute)` 返回 `Unsupported`。
- 清单为空 = 能力存在但当前无适配器；`Unsupported` = 能力不存在。二者不得混淆。
- `GpuAdapter` 不可变、无 close；`GpuAdapter.open(context)` 是业务打开入口，每次返回独立 `GpuDevice`，调用方分别关闭。
- `GpuDevice.adapterId()` 与 `GpuAdapter.id()` 关联；`backend()` 与适配器一致。`GpuDevice` 不重新枚举适配器。
- `GpuDevice.memoryInfo(context)` 返回独立 `GpuMemoryInfo` 快照；`0` 表示未知/不支持；不用于精确预算。
- `GpuDevice.createQueue(context, kind)` 显式请求队列；`ComputeOnly` + `Graphics` 返回 `Unsupported`；其它不支持组合也必须显式失败，不静默降级。
- 队列 kind 创建后固定；同一 kind 多次创建由实现决定；不得假设单例。
- 设备持有已创建队列；`GpuDevice.close()` 先关闭队列再关闭设备；队列可独立 `close()`；设备关闭后队列 `isOpen()` 为 false，队列 `close()` 返回 `Ok(unit)`。
- `GpuQueue` 只表示句柄；不提供提交/同步/栅栏；这些是 X。
- 阻塞方法首参 `Context`；`context == null` 是合同错误（panic）；取消返回 `Cancelled`；`PermissionDenied` 不重试、不提权。
- 句柄规则：设备/队列句柄是 `Long`，不透明、不跨进程、不持久；不暴露裸指针/fd/后端句柄；close 幂等。
- 并发：`GpuBackend`/`GpuQueueKind`/`GpuAdapter`/`GpuMemoryInfo` 可共享；`GpuDevice`/`GpuQueue` 不承诺线程安全，必须串行化使用；`close` 幂等指重复调用安全，并发 close 仍需串行化。
- 容器/WASM：只返回可见适配器；WebGPU 可选；不支持的设备/队列返回 `Unsupported`，不模拟。

---

## 5. 场景

### G1：桌面适配器选择

`OsProfile.has(OsCapability.Gpu)` → `gpuAdapters(context)` → 按 `backend()`/`isDiscrete()`/`isIntegrated()`/`memoryBytes()` 选择 → `open(context)` → 把 `GpuDevice` 交给渲染层。渲染层如何使用设备属于 X/`xdk.gpu`。

### G2：无头 GPU 计算

无显示输出要求；`Gpu` + `GpuCompute` 能力；打开 `ComputeOnly`/Vulkan/Metal 适配器；创建 `Compute`/`Transfer` 队列；不请求 `Graphics`。

### G3：诊断/资产清单

枚举适配器并记录 `describe()`、后端、驱动版本、显存快照；用于日志/兼容性检查，不用于精确计费或分配保证。

### G4：失败/取消/关闭

无能力 → `Unsupported`；无权限 → `PermissionDenied`；`Context` 取消 → `Cancelled`；适配器消失 → `open` 返回 `Unsupported`；所有设备/队列关闭；close 失败只诊断。

### G5：多 GPU

打开多个适配器/设备；设备/队列独立关闭；不提供跨 GPU 协同、P2P、PCI 拓扑，这些是 X。

---

## 6. 缺口

- 命令缓冲/提交/同步/栅栏：X `GpuCommand`/`GpuFence`。
- 缓冲区/纹理/显存分配：X `GpuBuffer`。
- 着色器/管线/计算内核：X 或 `xdk.gpu` 高层包。
- 多 GPU 协同/P2P/PCI 拓扑：X。
- 设备热插拔/设备丢失事件：X `DeviceWatcher`。
- 队列优先级/抢占/队列族索引：X。
- 精确显存预算/驻留/驱逐：X。
- 厂商 SDK/驱动特性/驱动安装：ecosystem/FFI。
- 显示/窗口/合成集成：已从 2.x 基线移除；不在本包。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Value` |
| 处理器 | 标准 A8 |
| 生成物 | 适配器/设备/显存/队列值语义；GpuDevice/GpuQueue 若持原生句柄则按资源 class 处理 |
| 状态 | 无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `GpuAdapter`/`GpuMemoryInfo` | `@Value` | 值语义成员 |
| `GpuDevice`/`GpuQueue` | — | 若持原生句柄，保持资源 class |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../../ANNOTATION-CATALOG.md)。
