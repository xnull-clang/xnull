# `xdk.gpu` GPU 计算高层包

| 项 | 值 |
| --- | --- |
| 包 | `xdk.gpu` |
| 层 |  计算层 |
| 依赖 | `xdk.core`、`xdk.os.gpu` |
| 被依赖 | 应用、计算库；core/net/os 不依赖本包 |
| 稳定性 | `preview` |
| 基线 | 只做 GPU 计算；无 UI、窗口、渲染、纹理、交换链 |
| 类型 | 8（2 个 enum + 6 个 class） |

> 本 README 只做包索引、跨类型规则、场景与缺口；每个类型的完整契约在对应类型文件。
> 低层适配器、设备、队列、后端枚举见 [`xdk.os.gpu`](../os/gpu/README.md)，本包不重复定义。

---

## 1. 包定位

`xdk.gpu` 是建立在 [`xdk.os.gpu`](../os/gpu/README.md) 之上的**高层 GPU 计算 API**：

```text
应用 / 计算库
  │
  ├─ xdk.gpu           高层计算：buffer/program/pipeline/command/fence
  │    │
  │    └─ xdk.os.gpu   低层：adapter/device/queue/backend
  │         │
  │         └─ runtime / FFI / 驱动
  │
  └─ xdk.core          Context/Bytes/Error/Result
```

只做：

- 计算缓冲区（buffer）的创建、CPU 写入/读取、关闭；
- 计算程序（program）的创建、关闭；程序代码是后端可接受的不透明字节；
- 计算管线（pipeline）：程序 + 有序缓冲布局；
- 计算命令缓冲（command buffer）：begin、绑定、dispatch、end、提交；
- 完成栅栏（fence）：等待一次提交完成；
- 静态工厂入口 `GpuCompute`。

不做：

- UI、窗口、合成器、桌面集成；
- 渲染管线、render pass、纹理/图像/采样器、交换链、present；
- 顶点/索引缓冲、着色器语言、编译器、反射、入口点选择；
- 显存分配策略、驻留/驱逐、内存别名、精确预算；
- 设备枚举、设备打开、队列创建（属于 [`xdk.os.gpu`](../os/gpu/README.md)）；
- 驱动/厂商 SDK、裸设备 ioctl、后端原生句柄；
- 显示提交或任何把命令提交到显示表面的能力。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 计算优先 | 基线只覆盖计算；渲染/UI 明确留到 X |
| 不重复低层 | 设备、队列、后端枚举直接复用 `xdk.os.gpu`；本包只加计算资源 |
| 不透明句柄 | buffer/program/pipeline/command buffer/fence 都用 `Long` 句柄；不暴露裸指针、映射地址、fd |
| 显式生命周期 | 所有资源由调用方 `close()`；close 幂等；设备/队列必须先于资源创建，资源必须先于设备关闭 |
| 显式同步 | CPU 读写不插入 GPU 屏障；提交必须带完成栅栏；资源在栅栏信号前不得关闭 |
| 失败显式 | 不支持 → `Unsupported`；已关闭 → `Unavailable`；状态/参数错 → `InvalidArgument`；取消 → `Cancelled` |
| 能力门控在上游 | 先用 `OsProfile.has(OsCapability.Gpu)` 与 `GpuDevice` 打开设备/队列；`GpuCompute` 不重复探测 |
| 无全局状态 | 无全局设备注册表、无全局命令队列；工厂只返回调用方拥有的资源 |
| 平台透明 | 公开 API 不出现 Vulkan/Metal/D3D12/WebGPU 头文件类型或扩展字符串；后端只用 `GpuBackend` |
| 单队列基线 | 一个命令缓冲绑定一个 Compute 队列；多队列/多设备协同是 X |

---

## 3. 类型索引

| 类型 | 种类 | 角色 | 文件 |
| --- | --- | --- | --- |
| `GpuBufferUsage` | enum | 缓冲区使用/绑定意图 | [`GpuBufferUsage.md`](GpuBufferUsage.md) |
| `GpuBuffer` | class | 计算缓冲区句柄与 CPU 读写 | [`GpuBuffer.md`](GpuBuffer.md) |
| `GpuProgramKind` | enum | 程序阶段；基线只支持 Compute | [`GpuProgramKind.md`](GpuProgramKind.md) |
| `GpuProgram` | class | 不透明程序句柄 | [`GpuProgram.md`](GpuProgram.md) |
| `GpuPipeline` | class | 程序 + 有序缓冲布局 | [`GpuPipeline.md`](GpuPipeline.md) |
| `GpuCommandBuffer` | class | 计算命令录制与提交 | [`GpuCommandBuffer.md`](GpuCommandBuffer.md) |
| `GpuFence` | class | 一次提交的完成栅栏 | [`GpuFence.md`](GpuFence.md) |
| `GpuCompute` | class（静态入口） | 创建计算资源的静态工厂 | [`GpuCompute.md`](GpuCompute.md) |

---

## 4. 跨类型规则

### 4.1 依赖与分层

- 本包只依赖 `xdk.core` 与 `xdk.os.gpu`；UI/桌面/渲染/图像/字体/输入/剪贴板不在 XDK 范围。
- 设备/队列/后端类型不重定义：使用 [`GpuDevice`](../os/gpu/GpuDevice.md)、[`GpuQueue`](../os/gpu/GpuQueue.md)、[`GpuQueueKind`](../os/gpu/GpuQueueKind.md)、[`GpuBackend`](../os/gpu/GpuBackend.md)。
- `GpuCompute` 是静态工厂，不拥有设备、不枚举设备、不创建队列；设备与 Compute 队列由调用方通过 `xdk.os.gpu` 获取。

### 4.2 句柄与关闭

- 所有资源句柄是 `Long`，必须大于 0；不透明、不跨进程、不持久化、不得写入日志作为长期 ID。
- 所有资源由调用方持有并 `close()`；`close()` 幂等；重复调用返回 `Ok(unit)`。
- 设备/队列先关闭时，资源上的阻塞操作返回 `Unavailable`；资源 `close()` 标记关闭后跳过原生关闭，视为设备回收，返回 `Ok(unit)`。
- 关闭顺序：等待 fence → command buffer → pipeline → program → buffer → fence → queue → device。提交后，command buffer、pipeline、program、buffer 都必须保持到 fence 信号。

### 4.3 程序与管线

- `GpuProgramKind` 基线只支持 `Compute`；`Vertex`/`Fragment` 由 `GpuCompute.createProgram` 返回 `Unsupported`，属于 X 渲染。
- `GpuProgram` 的代码参数是 `Bytes`，内容由后端定义；本包不提供着色器语言、编译器、反射或入口点选择。
- `GpuPipeline` 绑定一个 Compute `GpuProgram` 和一个有序 `List<GpuBufferUsage>` 布局；索引即绑定槽。
- 管线不拥有程序；调用方必须先用完管线并关闭管线，再关闭程序。程序先关闭会使管线不可用。

### 4.4 缓冲使用与绑定兼容

- `GpuBufferUsage` 固定于 buffer 创建时；不能把 buffer 的 usage 当作可变提示。
- 管线槽的声明 usage 与实际 buffer usage 必须兼容；兼容矩阵在 [`GpuBufferUsage.md`](GpuBufferUsage.md) §3。
- `Uniform` 只接受 `Uniform`；`Indirect` 基线只允许创建/读写，不允许绑定到管线（`dispatchIndirect` 是 X）。
- `Storage` 是未限定访问的 storage 通配；不是默认值；优先声明具体访问模式。
- 基线没有顶点/索引 usage；渲染用途是 X。

### 4.5 命令录制与提交

- `GpuCommandBuffer` 创建时绑定一个 `GpuDevice` 和一个 `GpuQueueKind.Compute` 队列；其他队列 kind 返回 `Unsupported`。
- 状态机：Created → Recording → Ended → Submitted。`begin` 只允许一次；`end` 要求至少一次 dispatch 且当前管线布局全部绑定；`submit` 只能一次。
- `bindPipeline` 会清空当前缓冲绑定；一个命令缓冲可以在多次 dispatch 之间切换管线，但每次 dispatch 前必须重新绑定当前布局所需的缓冲。
- `dispatch` 的参数是工作组数量，三个维度都必须 > 0；工作组大小由程序/后端决定，`GpuPipeline` 不暴露。
- 每次 `submit` 必须带一个为该命令缓冲创建的 `GpuFence`；无栅栏 fire-and-forget 提交不在基线。
- 提交只到 Compute 队列；不提交到显示表面、交换链或渲染队列。

### 4.6 栅栏与资源生存期

- `GpuFence` 在创建时绑定到一个尚未提交的 command buffer；`submit` 必须传入同一个 fence。
- fence 在 GPU 完成该次提交时变为 signaled；`wait` 超时返回 `Timeout`；取消返回 `Cancelled`；`isSignaled` 用于非阻塞轮询。
- fence 一次性；无 reset、无手动 signal、无 timeline、无多 fence 合并；这些是 X。
- 提交成功后，command buffer、pipeline、program、buffer 都必须保持打开，直到 fence signaled 或设备关闭。
- 提前关闭仍可能被 GPU 使用的资源是调用方合同错误；实现无法完全阻止，文档与测试必须覆盖关闭顺序。

### 4.7 失败、取消与并发

- 可阻塞方法首参 `Context`；`context == null` 是合同错误（panic）。
- 失败统一 `Result<T, Error>`；无权限返回 `PermissionDenied`，不重试、不提权；无能力返回 `Unsupported`。
- 关闭后除纯元数据读取（ID/kind/usage/size/device 等）与 `isOpen` 外，操作返回 `Unavailable`。
- 所有资源非线程安全；`begin`/`bind`/`dispatch`/`end`/`submit`/`close` 必须串行化。`close` 幂等指重复调用安全，不承诺并发 close 安全。
- `GpuCompute` 本身无状态，但对同一 `GpuDevice` 的工厂调用继承设备的非线程安全约束，必须由调用方串行化。

---

## 5. 场景

### G1：无头计算初始化

`OsProfile.has(OsCapability.Gpu)` → `gpuAdapters(context)` 选择设备 → `GpuAdapter.open(context)` 得到 `GpuDevice` → `createQueue(context, GpuQueueKind.Compute)` → `GpuCompute.createBuffer` / `createProgram` / `createPipeline` / `createCommandBuffer` / `createFence` → `GpuBuffer.write` → `begin` / `bindPipeline` / `bindBuffer` / `dispatch` / `end` → `submit(fence)` → `fence.wait` → `GpuBuffer.read` → 按 §4.2 的关闭顺序关闭。全程不要求显示输出/窗口系统。

### G2：一个命令缓冲内多次 dispatch

同一命令缓冲内可以 `bindPipeline` → 绑定 → `dispatch`，再切换管线/重新绑定 → 再 `dispatch`；`bindPipeline` 清空旧绑定，`dispatch` 前必须满足当前布局。最后只 `end` 一次、`submit` 一次、等待一个 fence。

### G3：失败、取消与不支持

无 `Gpu` 能力 → `Unsupported`；`Vertex`/`Fragment` 程序 → `Unsupported`；`Transfer`/`Graphics` 队列 → `Unsupported`；usage 与管线槽不兼容 → `InvalidArgument`；设备/队列/资源已关闭 → `Unavailable`；`Context` 取消 → `Cancelled`；fence 超时 → `Timeout`。

### G4：资源生命周期与关闭顺序

提交后等 fence signaled，再依次关闭 command buffer、pipeline、program、buffer、fence；队列和设备最后关闭。资源先于设备关闭时，资源 `close()` 跳过原生关闭并返回 `Ok(unit)`；所有 close 重复调用安全。

### G5：容器、WASM 与 ComputeOnly

只使用宿主可见的 `GpuDevice`；WebGPU 可选；`ComputeOnly` 后端只请求 Compute 队列；不请求图形/显示输出；不支持的设备/队列/程序 kind 显式返回 `Unsupported`，不模拟、不静默降级。

---

## 6. 缺口

| 缺口 | 决策 |
| --- | --- |
| 渲染管线、render pass、纹理/图像/采样器、交换链、present | UI/桌面/渲染不在 XDK 范围；本包只做计算 |
| 顶点/索引缓冲与 `GpuBufferUsage.Vertex`/`Index` | X 渲染；基线枚举不包含 |
| 着色器语言、编译器、反射、入口点、工作组大小、特化常量 | 不做；程序代码是后端可接受的不透明 `Bytes` |
| `dispatchIndirect` | X；`GpuBufferUsage.Indirect` 仅保留创建/读写 |
| 多队列、多设备、P2P、跨设备共享 | X |
| 可重置/时间线/多等待 fence | X；基线 fence 一次性 |
| 无栅栏 fire-and-forget 提交 | 不在基线；每次提交必须有 fence |
| 命令缓冲复用、重录制、次级命令缓冲 | X；基线一次性 |
| 查询池、时间戳、性能计数 | X |
| 显存预算、驻留、驱逐、别名 | X |
| 设备丢失/热插拔事件 | X `DeviceWatcher`（`xdk.os.gpu` 缺口） |
| `GpuDevice` 的公开不透明句柄访问器 | 不新增；`xdk.gpu` 适配器内部解析设备，公共 API 不暴露 |
| 显示/呈现提交 | 明确不做；本包只提交计算命令 |
