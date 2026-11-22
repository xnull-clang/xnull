# `xdk.accel` 统一加速器抽象

| 项 | 值 |
| --- | --- |
| 包 | `xdk.accel` |
| 层 | L8 solutions |
| 依赖 | `xdk.core`、`xdk.os.gpu`、`xdk.gpu`、`xdk.tensor` |
| 被依赖 | `xdk.ml`、应用、嵌入式/计算产品 |
| 稳定性 | `preview` |
| 类型 | 14（13 个类型 + 1 个静态入口） |
| 基线 | GPU/NPU/DSP/FPGA/ASIC/LPU/IPU/HPU/DPU/VPU/MCU 统一抽象；无渲染/显示、无模型运行时、无调度器、无设备发现魔法 |

> 本 README 只做包索引、跨类型规则、场景、缺口、安全与调研；每个类型的完整契约在对应类型文件。 总览见 [`../README.md`](../README.md)，工作分配见 [`../WORK-ALLOCATION.md`](../WORK-ALLOCATION.md)。

---

## 1. 包定位

`xdk.accel` 是建立在 core/net/os/utils 之上的**统一加速器对象模型**：

```text
应用 / xdk.ml / 数值库
  │
  ├─ xdk.accel          统一：descriptor/device/memory/program/kernel/queue/command buffer/fence
  │    │
  │    ├─ xdk.gpu        GPU 专用便利层：buffer/program/pipeline/command buffer/fence
  │    ├─ xdk.os.gpu     低层：GpuAdapter/GpuDevice/GpuQueue
  │    ├─ xdk.tensor     CPU 稠密张量（本包不重复）
  │    └─ xdk.core       Context/Bytes/Error/Result/Long
  │
  └─ runtime / FFI / 驱动（ecosystem；不是公共 API）
```

只做：

- 描述加速器（类别、后端、厂商、容量提示、能力集合）；
- 显式打开设备；
- 设备内存分配与主机可见读写；
- 预编译程序的 opaque 字节加载；
- 按名称创建内核；
- 队列、一次性命令缓冲、工作组派发；
- 完成栅栏与幂等关闭。

不做：

- 渲染、窗口、合成、纹理/采样器、交换链、present、显示提交；
- 模型/算子/图/权重/量化编译器；模型运行时与 execution provider 分区；
- 调度器、放置、抢占、负载均衡、实时保证；
- 设备发现/枚举/热插拔/全局注册表；
- 多设备/P2P/跨设备共享/分布式；
- 编译器、链接器、位流生成工具链；
- 裸指针、寄存器、门铃、DMA 描述符、驱动 SDK、原生句柄；
- 自动回退/静默降级/模拟。

### 1.1 与 `xdk.gpu`、`xdk.os.gpu` 的关系

- [`xdk.gpu`](../../platform/gpu/README.md) 仍是 **GPU 专用便利层**：当应用只做 GPU 计算、需要管线布局/缓冲绑定时，优先用它。
- [`xdk.os.gpu`](../../platform/os/gpu/README.md) 仍是 **GPU 低层**：适配器清单、设备打开、队列创建、显存快照。
- `xdk.accel` 不重定义 `GpuAdapter`/`GpuDevice`/`GpuQueue`/`GpuBackend`，也不把 `GpuDevice` 包装成 `AcceleratorDevice`；两者是独立打开、独立关闭的路径。
- [`Accel.fromGpuAdapter`](Accel.md) 只读取 `GpuAdapter` 的只读元数据生成 [`Accelerator`](Accelerator.md)，不打开、不共享句柄、不自动映射后端。
- `xdk.accel` 的 `AcceleratorMemory` 是无类型字节，不是 [`Tensor`](../../platform/tensor/Tensor.md)；张量布局/数值语义由程序/内核或上层负责。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 统一对象模型 | descriptor → device → memory/program/kernel/queue/command buffer/fence，跨类别一致 |
| 描述与打开分离 | `Accelerator` 只读；打开统一走 `Accel.open`；无 `Accelerator.open` 旁路 |
| 复用低层 | GPU 元数据来自 `xdk.os.gpu`；不复制其设备/队列类型，不共享原生句柄 |
| 显式描述 | 描述符由平台集成层/桥接显式提供；无设备发现魔法、无全局注册表 |
| 能力门控 | 只用 `AcceleratorCapability`；不从 kind/vendor/backend 推导能力 |
| 不透明句柄 | 所有资源句柄是 `Long`；不暴露指针、fd、寄存器、SDK 对象 |
| 显式生命周期 | 调用方 `close()`；close 幂等；设备持有队列；其他资源调用方拥有 |
| 显式同步 | 每次提交必须带 fence；无 fire-and-forget；无隐式屏障 |
| 预编译程序 | 程序是后端可加载的 opaque 字节；不编译、不反射、不回读 |
| 无静默降级 | 不支持 → `Unsupported`；不换后端、不换设备、不模拟 |
| 有序单队列语义 | 队列内按提交顺序；跨队列需 fence；无调度器/抢占保证 |
| 平台透明 | 公开 API 只出现枚举/值对象；不出现 CUDA/Vulkan/Metal/Level Zero 头文件类型 |

---

## 3. 类型索引

| 类型 | 种类 | 角色 | 文件 |
| --- | --- | --- | --- |
| `AcceleratorKind` | enum | 加速器功能类别 | [`AcceleratorKind.md`](AcceleratorKind.md) |
| `AcceleratorBackend` | enum | 编程/运行时后端家族 | [`AcceleratorBackend.md`](AcceleratorBackend.md) |
| `AcceleratorVendor` | enum | 厂商/IP 提供方 | [`AcceleratorVendor.md`](AcceleratorVendor.md) |
| `AcceleratorCapability` | enum | 能力门控类别 | [`AcceleratorCapability.md`](AcceleratorCapability.md) |
| `Accelerator` | class | 只读适配器/加速器描述符 | [`Accelerator.md`](Accelerator.md) |
| `AcceleratorDevice` | class | 已打开设备；创建资源 | [`AcceleratorDevice.md`](AcceleratorDevice.md) |
| `AcceleratorMemory` | class | 无类型设备内存对象 | [`AcceleratorMemory.md`](AcceleratorMemory.md) |
| `AcceleratorProgram` | class | opaque 预编译程序句柄 | [`AcceleratorProgram.md`](AcceleratorProgram.md) |
| `AcceleratorKernel` | class | 按名称选择的内核入口 | [`AcceleratorKernel.md`](AcceleratorKernel.md) |
| `AcceleratorQueue` | class | 有序提交目标句柄 | [`AcceleratorQueue.md`](AcceleratorQueue.md) |
| `AcceleratorCommandBuffer` | class | 一次性命令录制/提交 | [`AcceleratorCommandBuffer.md`](AcceleratorCommandBuffer.md) |
| `AcceleratorFence` | class | 一次提交的完成栅栏 | [`AcceleratorFence.md`](AcceleratorFence.md) |
| `AcceleratorOptions` | class | 打开/程序/队列选项值 | [`AcceleratorOptions.md`](AcceleratorOptions.md) |
| `Accel` | class（静态入口） | 打开、CPU 描述符、GPU 桥接 | [`Accel.md`](Accel.md) |

---

## 4. 跨类型规则

### 4.1 分层与复用

- 依赖方向：`xdk.accel` → `xdk.core`/`xdk.os.gpu`/`xdk.gpu`/`xdk.tensor`；反向依赖禁止。
- `xdk.gpu` 的 `GpuBuffer`/`GpuProgram`/`GpuPipeline`/`GpuCommandBuffer`/`GpuFence` **不**被 `xdk.accel` 接受；两套对象模型不混用。
- `xdk.os.gpu` 的 `GpuDevice`/`GpuQueue` **不**被 `xdk.accel` 包装或共享；GPU 桥接只读适配器元数据。
- `xdk.tensor` 的 CPU 张量不进入本包；`AcceleratorMemory` 只描述字节，不描述 dtype/shape/stride。
- 模型运行时/EP 分区/图优化属于 `xdk.ml` 或 ecosystem；本包只提供设备与内核抽象，不解析模型。
-  包之间按需依赖，不得成环；本包不依赖 `xdk.ml`/`xdk.embedded`/`xdk.db`。

### 4.2 句柄、所有权与关闭

- 所有资源句柄是 `Long`，必须 >0；不透明、不跨进程、不持久、不得作为长期日志 ID。
- 设备持有已创建队列；`AcceleratorDevice.close()` 先关闭全部队列，再关闭设备。
- 内存/程序/内核/命令缓冲/fence 由调用方拥有；设备不持有、不关闭它们。
- 设备关闭使其他资源不可用；这些资源的 `close()` 标记关闭后跳过原生关闭，返回 `Ok(unit)`。
- 推荐关闭顺序：

```text
等待 fence signaled（或明确放弃）
  → 命令缓冲
  → 内核
  → 程序
  → 内存
  → fence
  → 队列
  → 设备
```

- 提交后，命令缓冲、内核、程序、内存、队列必须保持打开直到 fence signaled；提前关闭是调用方合同错误。
- 所有 `close()` 幂等；重复调用返回 `Ok(unit)`。`close` 幂等指重复调用安全，不承诺并发 close 安全。
- 设备 `close()` **不等待** fence；调用方必须先等待或承担挂起工作被丢弃/完成的不确定性。

### 4.3 能力门控与不支持组合

能力门控只使用 `Accelerator.supports(capability)` / `capabilities()`。`kind`/`vendor`/`backend` 不推导能力。

典型能力（仅文档/测试参考，不是保证）：

| 类别 | 常见能力 | 不由此保证 |
| --- | --- | --- |
| `Cpu` | `Memory`、`Compute` | GPU 图形、量化格式、低功耗 |
| `Gpu` | `Memory`、`Compute`、`Graphics` | 量化、可重构、统一内存 |
| `Npu` | `Memory`、`Compute`、`Quantized`、`LowPower` | 通用图形、任意 dtype |
| `Dsp` | `Memory`、`Compute`、`LowPower` | MMU/虚拟内存、统一寻址 |
| `Fpga` | `Memory`、`Compute`、`Reconfigurable` | 固定量化路径、自动重配置 |
| `Asic` | `Memory`、`Compute` | 可重构、通用可编程性 |
| `Lpu` | `Memory`、`Compute`、`Quantized` | 通用训练、图形 |
| `Ipu` | `Memory`、`Compute` | AI 或基础设施用途的固定语义 |
| `Hpu` | `Memory`、`Compute`、`Quantized` | 通用计算、图形 |
| `Dpu` | `Memory`、`Compute` | 深度学习、图形 |
| `Vpu` | `Memory`、`Compute`、`LowPower` | 图形 API、通用计算 |
| `Mcu` | `Memory`、`Compute`、`LowPower` | 动态加载、多队列、MMU |
| `Other` | 仅显式声明 | 任何推导 |

不支持组合必须显式失败，不静默降级：

| 场景 | 结果 |
| --- | --- |
| 描述符无 `Compute`，调用 `createProgram`/`createKernel`/`createQueue`/`createCommandBuffer` | `Unsupported` |
| 描述符无 `Memory`，调用 `allocateMemory` | `Unsupported` |
| 描述符无 `Memory`，`memoryLimitBytes > 0` | `Unsupported`（`open`） |
| `hostVisible = false` 的内存调用 `read`/`write` | `Unsupported` |
| 无 `Reconfigurable`，加载位流程序 | `Unsupported` |
| 无 `Quantized`，加载量化程序 | `Unsupported`；具体格式仍由后端拒绝 |
| MCU/受限后端不支持动态程序加载 | `Unsupported`（后端决定，不按 kind 硬编码） |
| NPU/DSP/MCU 单队列，请求第二个队列 | `Unsupported` |
| 非零 `queuePriority` 不被支持 | `Unsupported` |
| `enableProfiling`/`enableValidation`/`memoryLimitBytes` 不被支持 | `Unsupported`（`open`） |
| `DirectMl` 非 Windows、`Metal` 非 Apple、`Cuda` 非 NVIDIA、`Rocm` 非 AMD | `Unsupported` |
| `Sycl` 不可用，期望自动换 `OneApi`（或反向） | 不自动；显式重新打开或 `Unsupported` |
| CUDA 代码给 Vulkan/Metal 程序 | `Unsupported` |
| `bindValue` 长度 0 或 >16 | `InvalidArgument` |
| fence 不属于当前命令缓冲 | `InvalidArgument` |
| 内存上限超出 | `OutOfMemory` |
| 内核名未知（后端可确定） | `NotFound`，否则 `Unsupported` |
| FPGA 重配置被占用 | `Busy` |
| 设备关闭后创建/查询/分配/提交 | `Unavailable` |
| 渲染/显示/呈现 | 本包无入口；不是“返回错误”，而是不存在 API |
| 模型/图/EP/调度/发现 | 本包无入口；属于 `xdk.ml`/上层/集成层 |

`Graphics` 只描述设备具备图形流水线；本包不提供 render pass、draw、纹理、交换链、present。消费图形能力应使用图形栈，不得把 `xdk.accel` 当渲染 API。

### 4.4 程序、内核、内存与命令

- 程序是预编译 opaque 字节；`codeFormat`/`loadOptions` 只传给后端加载器；本包不编译源码、不做反射、不回读代码。
- 内核按名称创建；名称区分大小写；无自动入口选择、无参数反射、无默认绑定。
- 内存是无类型字节；`hostVisible` 固定；读写带 `Long` 偏移；不做 map/unmap、不暴露地址。
- 命令缓冲一次性：`begin` → 绑定 → `dispatch` → `end` → `submit(fence)`；不可重录制/复用。
- `bindKernel` 清空参数绑定；参数槽从 0 开始，`Int`；本包不检查参数总数/类型，后端拒绝非法槽。
- `dispatch` 同时给工作组数量与工作组大小，三个维度都 >0；无 indirect dispatch、无查询池、无时间戳。
- 每次提交必须带 fence；无 fence 的 fire-and-forget 不在基线。
- 队列内有序；跨队列无隐式顺序；没有独立传输/图形/显示队列；数据移动通过内核或主机可见内存完成。

### 4.5 失败、取消与并发

- 可阻塞方法首参 `Context`；`context == null` 是合同错误（panic）。
- 失败统一 `Result<T, Error>`；不抛异常表示运行时失败（构造器非法参数 panic 除外）。
- 错误分类：
  - `Unsupported`：能力/后端/格式/平台/选项不支持；
  - `PermissionDenied`：设备/系统权限不足；不重试、不提权；
  - `Cancelled`：`Context` 协作取消；
  - `Unavailable`：设备/资源已关闭或设备丢失；
  - `InvalidArgument`：状态/索引/偏移/跨设备资源/不适用选项；
  - `Timeout`：fence 等待超时；
  - `OutOfMemory`：分配/程序加载/内存上限；
  - `Busy`：队列满/FPGA 重配置占用；
  - `NotFound`：内核名未知；
  - `Io`：后端/驱动失败（诊断）。
- 无自动重试、无权限提升、无静默降级。`Timeout` 不取消设备工作；需要取消时用 `Context`（尽力而为）。
- `Accelerator`/`AcceleratorOptions`/枚举是值语义、可共享。
- `AcceleratorDevice`/`AcceleratorMemory`/`AcceleratorProgram`/`AcceleratorKernel`/`AcceleratorQueue`/`AcceleratorCommandBuffer`/`AcceleratorFence` 非线程安全；调用方必须串行化。
- 无全局设备注册表/全局队列/单例；工厂返回调用方拥有的对象。

### 4.6 与  包的边界

|  包 | 关系 |
| --- | --- |
| [`xdk.os.gpu`](../../platform/os/gpu/README.md) | 只读适配器元数据桥接；不共享 `GpuDevice`/`GpuQueue`/原生句柄 |
| [`xdk.gpu`](../../platform/gpu/README.md) | GPU 专用便利层；独立对象模型；不互相转换资源 |
| [`xdk.tensor`](../../platform/tensor/README.md) | CPU 张量；本包内存是无类型字节，不依赖张量类型 |
| [`CpuTopology`](../../platform/os/cpu/CpuTopology.md) | 不用于调度/绑核；本包无调度器 |

---

## 5. 场景

### A1：跨类别统一派发

平台集成层显式构造 NPU/GPU 描述符（或 GPU 走 `Accel.fromGpuAdapter`）→ 按能力筛选 → `Accel.open` → `createQueue` → `allocateMemory` → `createProgram`（预编译字节）→ `createKernel` → `createCommandBuffer` → `bindKernel`/`bindMemory`/`bindValue` → `dispatch` → `end` → `createFence` → `submit` → `wait` → 读取/关闭。全程无模型运行时、无自动设备选择。

### A2：GPU 两条路径

只做 GPU 且需要管线布局：使用 `xdk.gpu` 的 `GpuCompute`/`GpuPipeline`。需要跨 GPU/NPU/DSP 的统一对象模型：使用 `xdk.accel`，GPU 描述符可由 `xdk.os.gpu` 适配器桥接。两条路径各自打开设备、各自关闭，不共享句柄。

### A3：FPGA 可重构

描述符声明 `Reconfigurable`；`createProgram` 加载位流；同一时刻只允许一个重配置会话；占用时返回 `Busy`；关闭程序/设备释放。无自动重配置、无部分重配置、无工具链。

### A4：NPU/DSP 量化与低功耗

描述符声明 `Quantized`/`LowPower`；程序是厂商预编译产物；内存常为统一/主机可见；常见单队列；无 MMU 的 DSP 只使用显式内存对象。具体量化格式、skel 库、FastRPC 等细节不进入公共 API。

### A5：MCU/嵌入式受限目标

MCU 常见无动态加载、无多队列、内存极小；`createProgram`/`createQueue` 可能返回 `Unsupported`。本包不写寄存器、不刷固件、不映射外设；这些属于 `xdk.embedded`/`xdk.device` 或 ecosystem。

### A6：显式 CPU 目标

`Accel.cpu()` 返回合成描述符；`Accel.open` 在 CPU 后端可用时打开，否则 `Unsupported`。CPU 不是自动回退目标；调用方必须显式选择并处理失败。

---

## 6. 缺口

| 缺口 | 决策 |
| --- | --- |
| 设备发现/枚举/热插拔/设备丢失事件 | 不做；由平台集成层或 `xdk.os.gpu` 显式提供；设备丢失用 `Unavailable`/`Io` |
| 多设备/P2P/跨设备共享/分布式 | X；本包单设备 |
| 调度/放置/抢占/负载均衡/实时保证 | 不做；队列只表达有序提交 |
| 模型运行时/EP 分区/图优化/算子融合 | `xdk.ml`/ecosystem；本包只到内核 |
| 编译器/链接器/位流生成/特化常量 | ecosystem 工具链；本包只加载预编译产物 |
| 内存别名/驻留/驱逐/精确预算/页表 | X；本包只有容量提示与逻辑分配 |
| 命令缓冲复用/次级缓冲/indirect dispatch | X；基线一次性 |
| 时间戳/性能计数/查询池/调试层 | X；选项仅 profiling/validation 开关 |
| 设备限制查询（max workgroup size/dimensions、local memory、subgroup） | X；基线由后端以 `Unsupported`/`InvalidArgument` 表达 |
| 内核参数反射/局部内存参数/特化常量 | 不做；程序/内核契约与后端负责 |
| 队列类型/传输队列/乱序队列/多队列同步 | X；基线有序单类型 |
| 异步主机回调/事件循环集成 | X；用 fence 轮询/等待 |
| 图形/显示/纹理/交换链/present | 不做；属于图形栈/X |
| 训练/自动微分/分布式训练 | `xdk.ml`/X |
| 电源/频率/热/实时调度 | 不做；`LowPower` 仅描述 |
| 厂商 SDK/驱动安装/固件/寄存器 | ecosystem/FFI；公共 API 不暴露 |
| ONNX Runtime EP 的 provider options/图分区 | 不做；研究仅用于能力门控与“无自动回退”决策 |

---

## 7. 安全

- **无原生暴露**：不返回裸指针、设备地址、fd、寄存器、门铃、DMA 描述符、驱动 SDK 对象；所有资源是 `Long` 句柄。
- **预编译代码信任**：程序字节由调用方提供；本包不验证签名/来源；只加载可信产物。不可信程序可能崩溃、挂起或破坏设备状态。
- **加载选项**：`loadOptions` 原样传给后端加载器；不做 shell 展开/变量替换/通配符；不得把用户输入拼成命令；日志不打印 `loadOptions`（可能含路径/密钥）。
- **边界与溢出**：内存大小/偏移/代码大小用 `Long`；读写前检查 `offset + length`；`Bytes.length()` 是 `Int`，比较时转 `Long`；分配上限由 `memoryLimitBytes` 与后端共同约束。
- **权限**：设备访问失败返回 `PermissionDenied`；不重试、不提权、不绕过 OS/容器策略。
- **FPGA 位流**：重配置可改变硬件功能；仅加载可信位流；独占会话，占用返回 `Busy`；不提供部分重配置/回滚。
- **MCU/嵌入式**：不写寄存器、不刷固件、不映射外设；程序加载仅在 backend 明确支持时可用。
- **拒绝服务**：不可信内核可能长时间运行；`fence.wait` 超时只停止等待，不保证终止设备工作；需要隔离时用进程/容器/设备分区。
- **句柄日志**：句柄是不透明关联键，不是认证凭据；不得跨进程/持久化；日志避免记录完整 `codeFormat`/`loadOptions`/厂商路径。
- **厂商二进制**：驱动/运行时/固件是信任边界；本包不审计其行为；版本/来源由部署方负责。
- **无模型解析**：本包不解析 ONNX/权重/图，减少模型解析攻击面；模型安全由 `xdk.ml`/运行时负责。
- **无调度承诺**：队列优先级是提示；不能用于安全隔离、实时保证或资源配额强制。

---

## 8. 行业调研

| 来源 | 关键概念 | 采纳 | 拒绝/留边界 |
| --- | --- | --- | --- |
| [SYCL 2020](https://registry.khronos.org/SYCL/specs/sycl-2020/html/sycl-2020.html) | device/context/queue/kernel_bundle/kernel/event、buffer/accessor、USM | device→queue→program(kernel bundle)→kernel→event(fence)；context 显式 | C++ 模板/accessor/后端互操作；不作为公共 API |
| [oneAPI Level Zero](https://www.intel.com/content/www/us/en/docs/dpcpp-cpp-compiler/developer-guide-reference/2025-0/intel-oneapi-level-zero-backend-specification.html) | module/kernel/command queue/fence、显式设备 | `OneApi` 与 `Sycl` 区分；模块→程序、内核→内核、队列/栅栏 | 原生 `ze_*` 句柄/扩展；不暴露 |
| [CUDA Programming Guide](https://docs.nvidia.com/cuda/cuda-programming-guide/index.html) | context/module/function/stream/event、device memory | 程序=module、内核=function、队列=stream、栅栏=event；显式内存 | stream callback/CUDA graph/统一寻址细节；不暴露 |
| [OpenCL 3.0](https://registry.khronos.org/OpenCL/specs/3.0-unified/html/OpenCL_API.html) | platform/device/context/command-queue/program/kernel/memory/event/command-buffer | 完整对象映射；命令缓冲一次提交；事件→fence | image/sampler/pipe/SVM/原生 kernel；不做 |
| [Vulkan compute](https://docs.vulkan.org/spec/latest/chapters/cmdbuffers.html) | command buffer、queue submit、fence、descriptor set、compute pipeline | 命令缓冲录制/提交/fence；工作组数量+大小 | render pass/swapchain/surface/查询池；不做 |
| [ONNX Runtime Execution Providers](https://onnxruntime.ai/docs/execution-providers/) | EP 能力分区、provider 顺序、CPU fallback | “能力门控 + 显式选择 + 无静默回退” | 模型图/会话/EP provider options/自动 fallback；属于 `xdk.ml` |
| [Qualcomm QNN/Hexagon](https://developer.seco.com/clea-os/scarthgap_2-05-00/npu/qcom-npu) | HTP backend、量化、FastRPC、skel 库 | NPU 描述符/Custom 后端/Quantized 能力；不暴露私有栈 | skel 库/FastRPC/寄存器；不进入 API |
| [Arm Ethos-U / CMSIS-NN](https://arm-software.github.io/CMSIS-Ethos-U/main/general/index.html) | microNPU 命令流、内存映射、低功耗、无动态 OS | MCU/LowPower/受限加载；`Unsupported` 显式 | 寄存器编程/固件烧录/命令流格式；不做 |
| [AMD Vitis AI](https://docs.amd.com/r/en-US/Vitis-AI) | 自适应 SoC、位流/overlay、NPU IP | FPGA 的 `Reconfigurable`/位流程序/独占 `Busy` | 编译器/量化工具链/overlay 细节；ecosystem |
| [Cerebras](https://www.cerebras.ai/)、[Hailo](https://www.hailo.ai/) 等 ASIC 资料 | 固定功能/晶圆级/边缘 ASIC、预编译与量化 | `Asic`/`Npu` 分类、`Quantized`/`Compute` 门控、预编译程序 | 编译器/模型运行时/厂商栈；不进入本包 |
| [Groq LPU](https://groq.com/)、[Graphcore IPU](https://www.graphcore.ai/)、[Habana HPU](https://habana.ai/)、[NVIDIA DPU](https://www.nvidia.com/en-us/networking/products/data-processing-unit/)、[Intel VPU](https://www.intel.com/content/www/us/en/products/details/processors/movidius-vpu.html) | 厂商专用类别、全称歧义 | 保留 kind 枚举，但以描述符名称/厂商/能力为准 | 性能/代际/营销结论；不写入契约 |

结论：

- 行业 API 的共同骨架是 **device/context → queue/stream → program/module → kernel/function → memory → event/fence**；本包据此统一。
- 图形 API 的 command buffer/fence 语义适合跨后端抽象；render pass/swapchain 明确排除。
- NPU/DSP/FPGA/MCU 的差异主要在**可编程性、量化、内存模型、队列数量、动态加载**；用 capability + 显式 `Unsupported` 表达，不用 kind 硬编码。
- ONNX Runtime EP 的“能力分区/优先级/fallback”只采纳“显式能力门控 + 无静默回退”；模型图与会话不进入本包。
- 所有厂商原生句柄/寄存器/SDK 类型保持在 ecosystem；公共 API 只有枚举、值对象和 `Long` 句柄。

---

## 9. 验收与链接

- 14 个类型文件均为 14 段；一类型一文件；公开签名只用 XNull 语法；无泛型协议/泛型枚举。
- 阻塞方法首参 `Context`；失败 `Result`；资源 `close` 幂等；`Long` 句柄/大小、`Int` 计数。
- 相对链接：本 README 的类型链接、[`../README.md`](../README.md)、[`../WORK-ALLOCATION.md`](../WORK-ALLOCATION.md)、[`xdk.gpu`](../../platform/gpu/README.md)、[`xdk.os.gpu`](../../platform/os/gpu/README.md)、[`xdk.tensor`](../../platform/tensor/README.md)、[`GpuAdapter`](../../platform/os/gpu/GpuAdapter.md)、[`GpuBackend`](../../platform/os/gpu/GpuBackend.md)、[`CpuTopology`](../../platform/os/cpu/CpuTopology.md)。
- 不修改 `../../platform/README.md` 或 `../README.md`；不新增代码/测试/脚本。
- 设计完成不等于实现完成；实现批次另排。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Builder`、`@GpuKernel`、`@TensorOp` |
| 处理器 | 无自有处理器；消费 GPU/Tensor 生成物 |
| 生成物 | 设备/程序/队列是句柄/服务；kernel 入口复用 GPU/Tensor 处理器 |
| 状态 | 无领域注解；A8 派生 planned；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Accelerator`/`AcceleratorDevice`/`AcceleratorProgram`/`AcceleratorQueue` | — | 句柄/服务，保持显式 class/close |
| kernel 方法 | `@GpuKernel`/`@TensorOp` | 复用 GPU/Tensor 处理器 |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
