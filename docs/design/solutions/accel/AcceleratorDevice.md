# `AcceleratorDevice`

| 项 | 值 |
| --- | --- |
| 类型 | `class AcceleratorDevice` |
| 包 | `xdk.accel` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Bytes`、`Error`、`Accelerator`、`AcceleratorKind`、`AcceleratorBackend`、`AcceleratorVendor`、`AcceleratorCapability`、`AcceleratorOptions`、`AcceleratorMemory`、`AcceleratorProgram`、`AcceleratorKernel`、`AcceleratorQueue`、`AcceleratorCommandBuffer`、`AcceleratorFence` |

---

## 1. 定位

已打开的加速器设备句柄：描述符、后端/厂商/类别、打开选项、内存查询、队列/程序/内核/内存/命令缓冲/栅栏的创建入口、关闭、是否可用。

只表示一个已打开的生命周期句柄；不做设备发现、跨设备协同、调度、模型运行时或原生句柄暴露。

不做：

- 设备枚举/热插拔/设备选择；
- 原生设备指针/fd/驱动 SDK；
- 多设备/P2P/跨设备共享；
- 调度/抢占/负载均衡/亲和性；
- 模型/算子/图/权重；
- 渲染/显示/呈现；
- 自动 fallback/模拟；
- 等待在飞工作再关闭（`close` 无 `Context`）。

---

## 2. 设计逻辑

- 由 [`Accel.open`](Accel.md) 创建；构造器主要供宿主/测试使用。
- `_handle` 是 `Long` 不透明句柄；不暴露后端设备指针、索引、fd 或驱动句柄。
- `_accelerator` 是打开时的描述符快照；设备字段委托它，不重新枚举。
- `_options` 是打开选项的独立副本；`options()` 返回副本，修改不影响设备。
- 一个设备对应一个描述符/后端；不支持一个 `AcceleratorDevice` 跨多个物理设备。
- 设备持有已创建的队列；`close()` 先关闭全部队列，再关闭设备句柄。其他资源（内存/程序/内核/命令缓冲/fence）由调用方拥有，设备不持有。
- 设备关闭使其他资源不可用；资源的 `close()` 标记关闭后跳过原生关闭，视为设备回收。
- 设备关闭不等待 fence；调用方必须先等待或明确放弃在飞工作。关闭期间的挂起工作可能被后端丢弃/完成，不提供保证。
- 能力门控：`createProgram`/`createKernel`/`createQueue`/`createCommandBuffer`/`dispatch` 需要 `Compute`；`allocateMemory` 需要 `Memory`；缺失返回 `Unsupported`。
- 打开选项校验由 `Accel.open` 完成；`createProgram`/`createQueue` 再按各自适用字段校验。
- 内存查询返回 `Long` 字节；0 未知/不支持；不用于精确预算。
- 无全局注册表；设备由调用方持有并关闭。
- 非线程安全；调用方必须串行化。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | >0；不透明句柄 |
| `_accelerator` | `Accelerator` | final | 非 null；打开时快照 |
| `_options` | `AcceleratorOptions` | final | 非 null；独立副本 |
| `_queues` | `List<AcceleratorQueue>` | final | 已创建队列引用；内部注册表 |
| `_open` | `Bool` | 内部 | 是否可用 |

不变量：

- `handle > 0`；`accelerator`/`options` 非 null；`_queues` 非 null。
- 队列都由本设备创建；队列列表可包含已独立关闭的队列。
- 构造后 `open = true`；`close()` 后 `open = false` 且全部队列关闭；close 幂等。
- 设备关闭后不再调用任何原生设备原语。
- 设备不拥有内存/程序/内核/命令缓冲/fence；不关闭它们。
- 设备不重新枚举适配器；描述符字段在设备生命周期内不变。
- 设备不暴露原生句柄；公共 API 只有 `Long` 设备句柄。

---

## 4. 生命周期

由 `Accel.open` 创建；调用方持有；`close()` 关闭队列与设备；close 幂等；无 `deinit` 依赖。

关闭顺序（推荐）：

1. 等待所有 fence signaled 或明确放弃；
2. 关闭命令缓冲；
3. 关闭内核；
4. 关闭程序；
5. 关闭内存；
6. 关闭 fence；
7. 关闭队列（或让设备 close 关闭）；
8. `device.close()`。

关闭后只允许纯元数据读取（句柄、描述符、选项、kind/backend/vendor、memoryLimitBytes、isOpen）与 `close`；创建/查询/分配返回 `Unavailable`。

设备先关闭时，其他资源的 `close()` 标记关闭后跳过原生关闭，返回 `Ok(unit)`；资源 `isOpen()` 仍为 true 直到调用方 `close()`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `AcceleratorDevice(Long handle, Accelerator accelerator, AcceleratorOptions options)` | handle、accelerator、options | handle >0；accelerator/options 非 null | 非法 → panic |

构造器创建空队列注册表并置为 open；业务代码通过 `Accel.open` 获取。工厂校验能力/选项，并将原生打开失败映射为 `Unsupported`/`PermissionDenied`/`Cancelled`/`Io`。

---

## 6. 字段表

见 §3；字段私有。不暴露原生设备、队列族、门铃/寄存器或驱动 SDK 句柄。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `deviceHandle` | 不透明句柄 | 无 | `Long` | 无 |
| `accelerator` | 描述符快照 | 无 | `Accelerator` | 无 |
| `acceleratorId` | 描述符 ID | 无 | `String` | 无 |
| `kind` | 功能类别 | 无 | `AcceleratorKind` | 无 |
| `backend` | 后端家族 | 无 | `AcceleratorBackend` | 无 |
| `vendor` | 厂商枚举 | 无 | `AcceleratorVendor` | 无 |
| `options` | 打开选项副本 | 无 | `AcceleratorOptions` | 无 |
| `memoryLimitBytes` | 内存上限 | 无 | `Long` | 无 |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |
| `totalMemoryBytes` | 总内存提示 | `Context context` | `Result<Long, Error>` | `Unavailable`/`Cancelled`/`Unsupported`/`Io` |
| `availableMemoryBytes` | 可用内存提示 | `Context context` | `Result<Long, Error>` | `Unavailable`/`Cancelled`/`Unsupported`/`Io` |
| `allocateMemory` | 分配设备内存 | `Context context, Long sizeBytes, Bool hostVisible` | `Result<AcceleratorMemory, Error>` | `InvalidArgument`/`Unsupported`/`Unavailable`/`Cancelled`/`OutOfMemory`/`Io` |
| `createQueue` | 创建队列 | `Context context, AcceleratorOptions options` | `Result<AcceleratorQueue, Error>` | `InvalidArgument`/`Unsupported`/`Unavailable`/`Cancelled`/`Io` |
| `createProgram` | 加载程序 | `Context context, Bytes code, AcceleratorOptions options` | `Result<AcceleratorProgram, Error>` | `InvalidArgument`/`Unsupported`/`Unavailable`/`Cancelled`/`OutOfMemory`/`PermissionDenied`/`Io` |
| `createKernel` | 创建内核 | `Context context, AcceleratorProgram program, String kernelName` | `Result<AcceleratorKernel, Error>` | `InvalidArgument`/`Unsupported`/`NotFound`/`Unavailable`/`Cancelled`/`Io` |
| `createCommandBuffer` | 创建命令缓冲 | `Context context, AcceleratorQueue queue` | `Result<AcceleratorCommandBuffer, Error>` | `InvalidArgument`/`Unsupported`/`Unavailable`/`Cancelled`/`Io` |
| `createFence` | 创建栅栏 | `Context context, AcceleratorCommandBuffer commandBuffer` | `Result<AcceleratorFence, Error>` | `InvalidArgument`/`Unavailable`/`Cancelled`/`Io` |
| `close` | 关闭设备与队列 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

说明：

- 纯读取方法（`deviceHandle`/`accelerator`/`acceleratorId`/`kind`/`backend`/`vendor`/`options`/`memoryLimitBytes`/`isOpen`）关闭后仍返回打开时的值；无阻塞/取消点。
- `options()` 返回独立副本；不暴露内部实例。
- `totalMemoryBytes`/`availableMemoryBytes`：`context == null` panic；关闭 → `Unavailable`；0 表示未知/不支持；不是精确预算；取消 → `Cancelled`。
- `allocateMemory`：`context == null` panic；`sizeBytes <= 0` → `InvalidArgument`；关闭 → `Unavailable`；缺少 `Memory` → `Unsupported`；`hostVisible` 不支持 → `Unsupported`；超限 → `OutOfMemory`；成功返回新内存，调用方关闭。`unified` 仅在 CPU 后端/host-visible 时保守置 true；其它设备为 false 表示“未声明统一”，不表示一定不统一。
- `createQueue`：`context == null` 或 `options == null` panic；关闭 → `Unavailable`；缺少 `Compute` → `Unsupported`；选项不适用 → `InvalidArgument`；优先级不支持 → `Unsupported`；成功后队列登记到设备。
- `createProgram`：`context == null`、`code == null` 或 `options == null` panic；关闭 → `Unavailable`；`code.length() == 0` → `InvalidArgument`；缺少 `Compute` → `Unsupported`；选项不适用 → `InvalidArgument`；未知 `codeFormat` → `Unsupported`；加载失败 → `Io`/`OutOfMemory`/`PermissionDenied`；成功返回新程序。不编译源码；不保留/暴露代码字节。
- `createKernel`：`context == null`、`program == null` 或 `kernelName == null` panic；关闭 → `Unavailable`；`kernelName == ""` → `InvalidArgument`；程序关闭 → `Unavailable`；程序不属于本设备 → `InvalidArgument`；缺少 `Compute` → `Unsupported`；未知入口 → `NotFound`/`Unsupported`；成功返回新内核。
- `createCommandBuffer`：`context == null` 或 `queue == null` panic；关闭 → `Unavailable`；队列关闭 → `Unavailable`；队列不属于本设备 → `InvalidArgument`；缺少 `Compute` → `Unsupported`；成功返回一次性命令缓冲。
- `createFence`：`context == null` 或 `commandBuffer == null` panic；关闭 → `Unavailable`；命令缓冲关闭 → `Unavailable`；命令缓冲不属于本设备 → `InvalidArgument`；命令缓冲已提交 → `InvalidArgument`；成功返回未信号 fence。
- `close`：第一次调用标记关闭，关闭全部队列，再关闭设备；所有资源都尝试关闭，单个队列失败不阻止设备关闭；返回设备 `Io`（若有），否则第一个队列 `Io`；后续调用返回 `Ok(unit)`。
- `close` 不等待 fence；不关闭调用方拥有的内存/程序/内核/命令缓冲/fence；这些资源在设备关闭后不可用。
- 不提供 `describe`/`equals`/`copy`；设备是资源，不是值对象。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- 队列注册表；
- 描述符/选项快照；
- 能力门控；
- `Context`/`Result`；
- 幂等关闭；
- 关闭错误聚合。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、Int、Bool、String、Bytes、List、Result；
- 辅助：`toLong`（Int → Long，用于代码大小）；`unit` 值；
- 运行时/适配器：
  - `acceleratorDeviceTotalMemoryRaw(Context context, Long deviceHandle) -> Result<Long, Error>`；
  - `acceleratorDeviceAvailableMemoryRaw(Context context, Long deviceHandle) -> Result<Long, Error>`；
  - `acceleratorMemoryAllocateRaw(Context context, Long deviceHandle, Long sizeBytes, Bool hostVisible) -> Result<Long, Error>`；
  - `acceleratorQueueCreateRaw(Context context, Long deviceHandle, Int priority) -> Result<Long, Error>`；
  - `acceleratorProgramCreateRaw(Context context, Long deviceHandle, Bytes code, String codeFormat, List<String> loadOptions) -> Result<Long, Error>`；
  - `acceleratorKernelCreateRaw(Context context, Long programHandle, String kernelName) -> Result<Long, Error>`；
  - `acceleratorCommandBufferCreateRaw(Context context, Long deviceHandle, Long queueHandle) -> Result<Long, Error>`；
  - `acceleratorFenceCreateRaw(Context context, Long commandBufferHandle) -> Result<Long, Error>`；
  - `acceleratorDeviceCloseRaw(Long deviceHandle) -> Result<Unit, Error>`；
- 原生设备/队列/程序/内核/命令缓冲/fence/内存句柄必须 >0；0/负数视为适配器内部错误（工厂返回 `Internal`，构造器 panic）；
- 适配器必须检查 `Context` 取消；不得无限阻塞忽略取消；
- 接口：`Context`、`Bytes`、`Error`、`BasicError`、`ErrorKind`、`Accelerator`、`AcceleratorOptions`、`AcceleratorMemory`、`AcceleratorProgram`、`AcceleratorKernel`、`AcceleratorQueue`、`AcceleratorCommandBuffer`、`AcceleratorFence`。

---

## 10. 依赖的特性/接口/类

[`Accel`](Accel.md)、[`Accelerator`](Accelerator.md)、[`AcceleratorKind`](AcceleratorKind.md)、[`AcceleratorBackend`](AcceleratorBackend.md)、[`AcceleratorVendor`](AcceleratorVendor.md)、[`AcceleratorCapability`](AcceleratorCapability.md)、[`AcceleratorOptions`](AcceleratorOptions.md)、[`AcceleratorMemory`](AcceleratorMemory.md)、[`AcceleratorProgram`](AcceleratorProgram.md)、[`AcceleratorKernel`](AcceleratorKernel.md)、[`AcceleratorQueue`](AcceleratorQueue.md)、[`AcceleratorCommandBuffer`](AcceleratorCommandBuffer.md)、[`AcceleratorFence`](AcceleratorFence.md)、`Context`、`Bytes`、`Error`。

---

## 11. 所有权与并发

引用语义；设备由调用方持有；设备持有已创建队列并在 close 时关闭它们；队列可独立 close；无循环引用。

设备不拥有内存/程序/内核/命令缓冲/fence；这些资源由调用方拥有并关闭。设备关闭使它们不可用，但不自动标记 closed。

非线程安全：`allocateMemory`/`createQueue`/`createProgram`/`createKernel`/`createCommandBuffer`/`createFence`/`totalMemoryBytes`/`availableMemoryBytes`/`close` 不得并发；调用方需串行化，或确保 close 时没有其它调用。`close` 幂等指重复调用安全，不承诺并发 close 安全。

无 `equals`/`copy`；不推荐作 `Map` 键；关闭后不得再用设备。

---

## 12. 示例与反例

正确：

- `Accel.open(context, accelerator, options)` → `createQueue` → `allocateMemory` → `createProgram` → `createKernel` → `createCommandBuffer` → 录制 → `createFence` → `submit` → `fence.wait` → 读取 → 按 §4 顺序关闭。
- 用 `totalMemoryBytes`/`availableMemoryBytes` 记录诊断；分配失败按 `OutOfMemory` 处理。
- 用 `supports(Compute)` 预检；设备创建入口仍做能力门控。
- 设备关闭前等待/放弃所有 fence；关闭后不再使用设备或资源。

反例：

- 在设备上找 `submit`/`dispatch`；这些在命令缓冲。
- 关闭设备后继续 `createProgram`/`allocateMemory`。
- 假设设备关闭会自动关闭调用方拥有的内存/程序/内核/命令缓冲/fence。
- 把 `memoryLimitBytes` 当精确预算；把 `availableMemoryBytes` 0 当零内存。
- 在 NPU/DSP/MCU 上假设多队列/优先级一定可用。
- 用设备句柄做跨进程 ID。
- 设备 close 时不等待在飞 fence。
- 期望设备发现/自动选择。

---

## 13. 测试/场景义务

打开/关闭；`accelerator`/`options` 快照独立性；元数据关闭后可读；
`totalMemoryBytes`/`availableMemoryBytes` 0/大值/`Unavailable`/`Cancelled`；
`allocateMemory` 大小 0/负/主机可见/不可见/超限/`Unsupported`/`OutOfMemory`；
`createQueue` 多队列/单队列/优先级/选项不适用/`Unsupported`；
`createProgram` 空代码/格式/加载选项/`OutOfMemory`/`PermissionDenied`；
`createKernel` 未知入口/大小写/跨设备/关闭程序；
`createCommandBuffer` 跨设备队列/关闭队列；`createFence` 已提交缓冲/跨设备；
设备 close 关闭全部队列；队列先 close 再设备 close；设备 close 后资源 `close` `Ok(unit)`；
close 幂等/错误聚合；null context/参数 panic；并发合同；无设备发现。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class AcceleratorDevice {
    final Long _handle
    final Accelerator _accelerator
    final AcceleratorOptions _options
    final List<AcceleratorQueue> _queues
    Bool _open

    AcceleratorDevice(Long handle, Accelerator accelerator,
                      AcceleratorOptions options) {
        if handle <= 0 || accelerator == null || options == null {
            throw "AcceleratorDevice: invalid field"
        }
        _handle = handle
        _accelerator = accelerator
        _options = options.copy()
        _queues = []
        _open = true
    }

    Long deviceHandle() { return _handle }
    Accelerator accelerator() { return _accelerator }
    String acceleratorId() { return _accelerator.acceleratorId() }
    AcceleratorKind kind() { return _accelerator.kind() }
    AcceleratorBackend backend() { return _accelerator.backend() }
    AcceleratorVendor vendor() { return _accelerator.vendor() }
    AcceleratorOptions options() { return _options.copy() }
    Long memoryLimitBytes() { return _options.memoryLimitBytes() }
    Bool isOpen() { return _open }

    Result<Long, Error> totalMemoryBytes(Context context) {
        if context == null { throw "AcceleratorDevice.totalMemoryBytes: null context" }
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator device"))
        }
        return acceleratorDeviceTotalMemoryRaw(context, _handle)
    }

    Result<Long, Error> availableMemoryBytes(Context context) {
        if context == null { throw "AcceleratorDevice.availableMemoryBytes: null context" }
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator device"))
        }
        return acceleratorDeviceAvailableMemoryRaw(context, _handle)
    }

    Result<AcceleratorMemory, Error> allocateMemory(Context context,
                                                    Long sizeBytes,
                                                    Bool hostVisible) {
        if context == null { throw "AcceleratorDevice.allocateMemory: null context" }
        if sizeBytes <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid memory size"))
        }
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator device"))
        }
        if !_accelerator.supports(AcceleratorCapability.Memory) {
            return Err(new BasicError(ErrorKind.Unsupported, "memory unsupported"))
        }
        Result<Long, Error> allocated = acceleratorMemoryAllocateRaw(
            context, _handle, sizeBytes, hostVisible)
        if allocated.isErr() { return Err(allocated.error()) }
        if allocated.value() <= 0 {
            return Err(new BasicError(ErrorKind.Internal, "invalid memory handle"))
        }
        Bool unified = hostVisible && _accelerator.backend() == AcceleratorBackend.Cpu
        AcceleratorMemory memory = new AcceleratorMemory(
            allocated.value(), this, sizeBytes, hostVisible, unified)
        return Ok(memory)
    }

    Result<AcceleratorQueue, Error> createQueue(Context context,
                                                AcceleratorOptions options) {
        if context == null || options == null {
            throw "AcceleratorDevice.createQueue: null argument"
        }
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator device"))
        }
        if !_accelerator.supports(AcceleratorCapability.Compute) {
            return Err(new BasicError(ErrorKind.Unsupported, "compute unsupported"))
        }
        Result<Unit, Error> checked = acceleratorOptionsCheckQueue(options)
        if checked.isErr() { return Err(checked.error()) }
        Result<Long, Error> created = acceleratorQueueCreateRaw(
            context, _handle, options.queuePriority())
        if created.isErr() { return Err(created.error()) }
        if created.value() <= 0 {
            return Err(new BasicError(ErrorKind.Internal, "invalid queue handle"))
        }
        AcceleratorQueue queue = new AcceleratorQueue(
            created.value(), options.queuePriority())
        _queues.push(queue)
        return Ok(queue)
    }

    Result<AcceleratorProgram, Error> createProgram(Context context, Bytes code,
                                                    AcceleratorOptions options) {
        if context == null || code == null || options == null {
            throw "AcceleratorDevice.createProgram: null argument"
        }
        if code.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "empty program code"))
        }
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator device"))
        }
        if !_accelerator.supports(AcceleratorCapability.Compute) {
            return Err(new BasicError(ErrorKind.Unsupported, "compute unsupported"))
        }
        Result<Unit, Error> checked = acceleratorOptionsCheckProgram(options)
        if checked.isErr() { return Err(checked.error()) }
        Result<Long, Error> created = acceleratorProgramCreateRaw(
            context, _handle, code, options.codeFormat(), options.loadOptions())
        if created.isErr() { return Err(created.error()) }
        if created.value() <= 0 {
            return Err(new BasicError(ErrorKind.Internal, "invalid program handle"))
        }
        AcceleratorProgram program = new AcceleratorProgram(
            created.value(), this, toLong(code.length()), options.codeFormat())
        return Ok(program)
    }

    Result<AcceleratorKernel, Error> createKernel(Context context,
                                                  AcceleratorProgram program,
                                                  String kernelName) {
        if context == null || program == null || kernelName == null {
            throw "AcceleratorDevice.createKernel: null argument"
        }
        if kernelName == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "empty kernel name"))
        }
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator device"))
        }
        if program.device() != this {
            return Err(new BasicError(ErrorKind.InvalidArgument, "program from another device"))
        }
        if !program.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator program"))
        }
        if !_accelerator.supports(AcceleratorCapability.Compute) {
            return Err(new BasicError(ErrorKind.Unsupported, "compute unsupported"))
        }
        Result<Long, Error> created = acceleratorKernelCreateRaw(
            context, program.programHandle(), kernelName)
        if created.isErr() { return Err(created.error()) }
        if created.value() <= 0 {
            return Err(new BasicError(ErrorKind.Internal, "invalid kernel handle"))
        }
        AcceleratorKernel kernel = new AcceleratorKernel(
            created.value(), program, kernelName)
        return Ok(kernel)
    }

    Result<AcceleratorCommandBuffer, Error> createCommandBuffer(
            Context context, AcceleratorQueue queue) {
        if context == null || queue == null {
            throw "AcceleratorDevice.createCommandBuffer: null argument"
        }
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator device"))
        }
        if !queue.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator queue"))
        }
        Bool found = false
        Int index = 0
        while index < _queues.length() {
            if _queues.get(index) == queue { found = true; break }
            index = index + 1
        }
        if !found {
            return Err(new BasicError(ErrorKind.InvalidArgument, "queue from another device"))
        }
        if !_accelerator.supports(AcceleratorCapability.Compute) {
            return Err(new BasicError(ErrorKind.Unsupported, "compute unsupported"))
        }
        Result<Long, Error> created = acceleratorCommandBufferCreateRaw(
            context, _handle, queue.queueHandle())
        if created.isErr() { return Err(created.error()) }
        if created.value() <= 0 {
            return Err(new BasicError(ErrorKind.Internal, "invalid command buffer handle"))
        }
        AcceleratorCommandBuffer commandBuffer = new AcceleratorCommandBuffer(
            created.value(), this, queue)
        return Ok(commandBuffer)
    }

    Result<AcceleratorFence, Error> createFence(
            Context context, AcceleratorCommandBuffer commandBuffer) {
        if context == null || commandBuffer == null {
            throw "AcceleratorDevice.createFence: null argument"
        }
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator device"))
        }
        if commandBuffer.device() != this {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "command buffer from another device"))
        }
        if !commandBuffer.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator command buffer"))
        }
        if commandBuffer.isSubmitted() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "command buffer submitted"))
        }
        Result<Long, Error> created = acceleratorFenceCreateRaw(
            context, commandBuffer.commandBufferHandle())
        if created.isErr() { return Err(created.error()) }
        if created.value() <= 0 {
            return Err(new BasicError(ErrorKind.Internal, "invalid fence handle"))
        }
        AcceleratorFence fence = new AcceleratorFence(created.value(), commandBuffer)
        return Ok(fence)
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        Result<Unit, Error> firstError = Ok(unit)
        Bool hasError = false
        Int index = 0
        while index < _queues.length() {
            Result<Unit, Error> queueResult = _queues.get(index).close()
            if queueResult.isErr() && !hasError {
                firstError = Err(queueResult.error())
                hasError = true
            }
            index = index + 1
        }
        Result<Unit, Error> deviceResult = acceleratorDeviceCloseRaw(_handle)
        if deviceResult.isErr() { return Err(deviceResult.error()) }
        if hasError { return firstError }
        return Ok(unit)
    }
}
```
