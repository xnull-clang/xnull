# `AcceleratorCommandBuffer`

| 项 | 值 |
| --- | --- |
| 类型 | `class AcceleratorCommandBuffer` |
| 包 | `xdk.accel` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Bytes`、`Error`、`AcceleratorDevice`、`AcceleratorQueue`、`AcceleratorKernel`、`AcceleratorMemory`、`AcceleratorFence` |

---

## 1. 定位

绑定到一个加速器队列的计算命令缓冲：录制 `begin` / `bindKernel` / `bindMemory` / `bindValue` / `dispatch` / `end`，然后 `submit` 到队列，并用 [`AcceleratorFence`](AcceleratorFence.md) 等待完成。

只做：

- 一次性的计算命令录制与一次提交；
- 当前内核与参数槽绑定；
- 工作组数量/大小的显式派发；
- 与完成栅栏关联；
- 关闭与生命周期查询。

不做：

- 渲染 pass、draw call、纹理/采样器/交换链/显示；
- 拷贝/填充/归约等命令类型；
- indirect dispatch、查询池、时间戳、性能计数；
- 多队列/多设备提交、次级命令缓冲、复用/重录制；
- 隐式资源同步、自动 fence、自动参数绑定；
- 内核反射/参数类型检查；
- 模型图/算子调度。

---

## 2. 设计逻辑

- 由 [`AcceleratorDevice.createCommandBuffer`](AcceleratorDevice.md) 创建；构造器主要供宿主/测试使用。
- 命令缓冲固定一个设备与一个队列；队列必须由同一设备创建；其他设备队列返回 `InvalidArgument`。
- `_handle` 是 `Long` 不透明句柄；不暴露后端 command buffer/命令编码器。
- 状态机：Created → Recording → Ended → Submitted；一次性，不允许重录制/复用。
- `begin` 只允许从 Created 进入 Recording；`end` 要求至少一次成功 dispatch；`submit` 只允许一次。
- `bindKernel` 会清空当前内存/标量绑定；一个命令缓冲可以在多次 dispatch 之间切换内核，但每次 dispatch 前必须重新绑定所需参数。
- 参数槽用 `Int argumentIndex` 标识，从 0 开始；没有反射，本包不校验参数总数/类型/布局；后端在绑定或派发时拒绝不合法槽。
- `bindMemory` 绑定一个内存对象 + 字节偏移；`bindValue` 绑定 1..16 字节的标量/常量；同一个槽后绑定的类型覆盖先前的类型。
- `dispatch` 同时给出工作组数量（group count）与工作组大小（work-group size），三个维度都必须 >0；总工作项 = 三者乘积，由后端执行；不支持多维/工作组的后端可要求 `1,1,1`。
- 每次 `submit` 必须带一个为该命令缓冲创建的 fence；无栅栏 fire-and-forget 提交不在基线。
- 命令缓冲保存当前绑定与已成功 dispatch 的内核/内存的非拥有引用；它不拥有它们，但调用方必须保持到 fence signaled。
- 提交后命令缓冲、内核、程序、内存、队列都必须保持打开直到 fence signaled。
- 关闭后纯元数据（句柄、设备、队列、isRecording、isSubmitted、isOpen）仍可读；录制/提交返回 `Unavailable`。
- 设备先关闭时，`close()` 标记关闭后跳过原生关闭，视为设备回收，返回 `Ok(unit)`。
- 无 `equals`/`copy`/`describe`；命令缓冲是资源，不是值对象。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | >0；不透明句柄 |
| `_device` | `AcceleratorDevice` | final | 非 null；非拥有引用 |
| `_queue` | `AcceleratorQueue` | final | 非 null；由同一设备创建 |
| `_memoryBindings` | `Map<Int, AcceleratorMemory>` | final | 当前内存槽；键 ≥0 |
| `_valueBindings` | `Map<Int, Bytes>` | final | 当前标量槽；值 1..16 字节 |
| `_usedKernels` | `List<AcceleratorKernel>` | final | 已成功 dispatch 的内核；可重复 |
| `_usedMemories` | `List<AcceleratorMemory>` | final | 已成功 dispatch 绑定的内存；可重复 |
| `_kernel` | `AcceleratorKernel?` | 内部 | 当前内核；可为 null |
| `_dispatchCount` | `Int` | 内部 | ≥0；成功 dispatch 次数 |
| `_recording` | `Bool` | 内部 | 正在录制 |
| `_ended` | `Bool` | 内部 | 已完成 end |
| `_submitted` | `Bool` | 内部 | 已尝试 submit |
| `_open` | `Bool` | 内部 | 构造后 true；close 后 false |

不变量：

- `handle > 0`；`device`/`queue` 非 null；队列属于本设备。
- 同一个 `argumentIndex` 至多存在于一个绑定 map；`bindKernel` 清空两个 map。
- `_valueBindings` 的值长度 1..16；内存绑定偏移在目标大小内。
- `_usedKernels`/`_usedMemories` 只记录成功 dispatch 使用过的资源；可含重复项。
- `_dispatchCount` 等于成功 dispatch 次数；`end` 要求 >0。
- 状态单调：`_recording` 与 `_ended` 不同时为 true；`_ended` 为 true 时 `_recording` 为 false；`_submitted` 为 true 时 `_ended` 为 true。
- `_open` 为 false 时 `_recording` 为 false；关闭后不再调用原生 command buffer 原语。
- 命令缓冲不拥有内核/内存/队列/设备；只持有非拥有引用用于校验。
- 提交后内核/程序/内存/队列必须保持打开直到 fence signaled。

---

## 4. 生命周期

由 `AcceleratorDevice.createCommandBuffer` 创建；调用方拥有并必须 `close()`；close 幂等；无 `deinit` 依赖。

录制阶段：

- Created → `begin` → Recording；
- Recording → `bindKernel` / `bindMemory` / `bindValue` / `dispatch`（可多次）；
- Recording → `end` → Ended；
- Ended → `submit(fence)` → Submitted。

关闭：

- Created/Recording/Ended 都可以 `close()`；Recording 中关闭会丢弃未提交命令；
- Submitted 后必须等 fence signaled 才能 `close()`；提前关闭可能释放设备仍在使用的命令记录；
- 设备先关闭时，`close()` 标记关闭后跳过原生关闭，返回 `Ok(unit)`；设备关闭不会自动把命令缓冲标记为 closed，`isOpen()` 仍为 true 直到调用方 `close()`。

设备必须比命令缓冲活得久。队列先关闭时，录制可继续，但 `submit` 返回 `Unavailable`。fence 绑定原生完成事件；基线要求 fence signaled 后再关闭命令缓冲。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `AcceleratorCommandBuffer(Long handle, AcceleratorDevice device, AcceleratorQueue queue)` | handle、device、queue | handle >0；device/queue 非 null；队列打开 | 非法 → panic |

构造器主要供宿主/测试使用；业务代码通过 `AcceleratorDevice.createCommandBuffer` 获取。构造器无法从队列读取设备归属；队列归属由工厂校验：已关闭设备/队列返回 `Unavailable`，不属于本设备的队列返回 `InvalidArgument`。

---

## 6. 字段表

见 §3；字段私有。不暴露后端 command buffer、队列句柄、门铃/寄存器或命令编码器。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `commandBufferHandle` | 不透明句柄 | 无 | `Long` | 无 |
| `device` | 所属设备 | 无 | `AcceleratorDevice` | 无 |
| `queue` | 提交队列 | 无 | `AcceleratorQueue` | 无 |
| `isRecording` | 是否录制中 | 无 | `Bool` | 无 |
| `isSubmitted` | 是否已尝试提交 | 无 | `Bool` | 无 |
| `begin` | 开始录制 | `Context context` | `Result<Unit, Error>` | `InvalidArgument`/`Unavailable`/`Cancelled` |
| `bindKernel` | 绑定内核 | `Context context, AcceleratorKernel kernel` | `Result<Unit, Error>` | `InvalidArgument`/`Unavailable`/`Cancelled` |
| `bindMemory` | 绑定内存槽 | `Context context, Int argumentIndex, AcceleratorMemory memory, Long offsetBytes` | `Result<Unit, Error>` | `InvalidArgument`/`Unavailable`/`Cancelled` |
| `bindValue` | 绑定标量槽 | `Context context, Int argumentIndex, Bytes value` | `Result<Unit, Error>` | `InvalidArgument`/`Unavailable`/`Cancelled` |
| `dispatch` | 派发工作组 | `Context context, Int groupCountX, Int groupCountY, Int groupCountZ, Int workGroupSizeX, Int workGroupSizeY, Int workGroupSizeZ` | `Result<Unit, Error>` | `InvalidArgument`/`Unsupported`/`Unavailable`/`Cancelled`/`Busy` |
| `end` | 结束录制 | `Context context` | `Result<Unit, Error>` | `InvalidArgument`/`Unavailable`/`Cancelled` |
| `submit` | 提交到队列 | `Context context, AcceleratorFence fence` | `Result<Unit, Error>` | `InvalidArgument`/`Unavailable`/`Unsupported`/`Cancelled`/`Busy`/`Io` |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

说明：

- `commandBufferHandle()` 返回不透明 `Long`；关闭后仍返回原值；不得当作跨进程/持久 ID。
- `device()`/`queue()` 返回非拥有引用；命令缓冲不关闭它们。
- `isRecording()`/`isSubmitted()` 是状态查询；关闭后仍可读。
- `begin`：
  - `context == null` → panic；关闭/设备关闭 → `Unavailable`。
  - 非 Created 状态（已录制/已 end/已 submit）→ `InvalidArgument`。
  - 取消 → `Cancelled`；原生失败保持 Created。
  - 成功后 `_recording = true`。
- `bindKernel`：
  - `context == null` 或 `kernel == null` → panic；关闭/设备关闭 → `Unavailable`。
  - 非 Recording → `InvalidArgument`；内核/程序/设备关闭 → `Unavailable`；内核不属于本设备 → `InvalidArgument`。
  - 取消 → `Cancelled`；原生失败保持原内核/绑定不变。
  - 成功后设置当前内核并清空 `_memoryBindings`/`_valueBindings`；重复绑定同一内核也会清空。
- `bindMemory`：
  - `context == null` 或 `memory == null` → panic；关闭/设备关闭 → `Unavailable`。
  - 非 Recording 或没有当前内核 → `InvalidArgument`。
  - `argumentIndex < 0` → `InvalidArgument`；没有反射，不检查上界。
  - `memory` 关闭 → `Unavailable`；不属于本设备 → `InvalidArgument`。
  - `offsetBytes < 0` 或 `offsetBytes >= memory.sizeBytes()` → `InvalidArgument`。
  - 取消 → `Cancelled`；原生失败保持该槽旧绑定不变。
  - 成功后写入 `_memoryBindings[argumentIndex]`，并移除同槽 `_valueBindings`。
- `bindValue`：
  - `context == null` 或 `value == null` → panic；关闭/设备关闭 → `Unavailable`。
  - 非 Recording 或没有当前内核 → `InvalidArgument`。
  - `argumentIndex < 0` → `InvalidArgument`；`value.length()` 不在 1..16 → `InvalidArgument`。
  - 值按小端序解释；不检查 dtype/参数类型；调用方不得编码裸设备地址/指针。
  - 取消 → `Cancelled`；原生失败保持该槽旧绑定不变。
  - 成功后写入 `_valueBindings[argumentIndex]`（复制），并移除同槽 `_memoryBindings`。
- `dispatch`：
  - `context == null` → panic；关闭/设备关闭 → `Unavailable`。
  - 非 Recording、没有当前内核、内核/程序关闭 → `InvalidArgument`/`Unavailable`。
  - 任一 `groupCount* <= 0` 或 `workGroupSize* <= 0` → `InvalidArgument`。
  - 后端不支持给定维度/工作组大小 → `Unsupported`/`InvalidArgument`。
  - 取消 → `Cancelled`；原生失败不增加 `_dispatchCount`、不记录使用资源。
  - 成功后 `_dispatchCount++`，并把当前内核与当前绑定的内存追加到 `_usedKernels`/`_usedMemories`；当前内核与绑定保持，可继续绑定/派发。
- `end`：
  - `context == null` → panic；关闭/设备关闭 → `Unavailable`。
  - 非 Recording → `InvalidArgument`；`_dispatchCount == 0` → `InvalidArgument`。
  - 当前内核/程序关闭 → `Unavailable`。
  - 取消 → `Cancelled`；原生失败保持 Recording，可修复后重试或关闭。
  - 成功后 `_recording = false`、`_ended = true`。
- `submit`：
  - `context == null` 或 `fence == null` → panic；关闭/设备/队列关闭 → `Unavailable`。
  - 非 Ended 或已 submit → `InvalidArgument`。
  - `fence` 关闭 → `Unavailable`；fence 不属于本命令缓冲 → `InvalidArgument`。
  - 任一已 dispatch 的内核/程序/内存关闭 → `Unavailable`。
  - 调用前取消无法区分；进入原生提交后任何失败（含 `Cancelled`）都使命令缓冲已消费，不能重试。
  - 校验通过后先置 `_submitted = true`，再调用原生提交；原生失败也保持已消费。
  - 提交只到计算队列；不涉及显示/呈现。
- `close`：
  - 第一次调用标记关闭并清 `_recording`、绑定、当前内核与已用资源引用；设备仍打开时调用原生关闭；设备已关闭时跳过；后续返回 `Ok(unit)`。
  - 关闭失败只作为诊断返回 `Io`；不改变已关闭状态；不关闭内核/内存/队列/fence。
  - `close` 不检查 fence 状态；提交后提前关闭是调用方合同错误，可能释放设备仍在使用的命令记录。
- `isOpen()` 不触碰原生句柄。
- 不提供 `reset`/`reuse`/`submitAndWait`/`dispatchIndirect`；这些是 X 或调用方组合。
- 不提供 `describe`/`equals`/`copy`；命令缓冲是资源，不是值对象。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- 显式状态机；
- 参数槽绑定表；
- 已使用资源校验；
- 显式完成栅栏；
- `Context`/`Result`；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、Int、Bool、Bytes、Map、Result；
- 运行时/适配器：
  - `acceleratorCommandBufferCreateRaw(Context context, Long deviceHandle, Long queueHandle) -> Result<Long, Error>`；
  - `acceleratorCommandBufferBeginRaw(Context context, Long commandBufferHandle) -> Result<Unit, Error>`；
  - `acceleratorCommandBufferBindKernelRaw(Context context, Long commandBufferHandle, Long kernelHandle) -> Result<Unit, Error>`；
  - `acceleratorCommandBufferBindMemoryRaw(Context context, Long commandBufferHandle, Int argumentIndex, Long memoryHandle, Long offsetBytes) -> Result<Unit, Error>`；
  - `acceleratorCommandBufferBindValueRaw(Context context, Long commandBufferHandle, Int argumentIndex, Bytes value) -> Result<Unit, Error>`；
  - `acceleratorCommandBufferDispatchRaw(Context context, Long commandBufferHandle, Int groupCountX, Int groupCountY, Int groupCountZ, Int workGroupSizeX, Int workGroupSizeY, Int workGroupSizeZ) -> Result<Unit, Error>`；
  - `acceleratorCommandBufferEndRaw(Context context, Long commandBufferHandle) -> Result<Unit, Error>`；
  - `acceleratorCommandBufferSubmitRaw(Context context, Long commandBufferHandle, Long fenceHandle) -> Result<Unit, Error>`；
  - `acceleratorCommandBufferCloseRaw(Long commandBufferHandle) -> Result<Unit, Error>`；
- 原生 command buffer 句柄必须 >0；0/负数视为适配器内部错误（工厂返回 `Internal`，构造器 panic）；
- 适配器必须检查 `Context` 取消，不得无限阻塞忽略取消；
- 适配器解析 `AcceleratorDevice`/`AcceleratorQueue` 的内部句柄；公共 API 不暴露；
- 接口：`Context`、`Bytes`、`Error`、`BasicError`、`ErrorKind`、`AcceleratorDevice`、`AcceleratorQueue`、`AcceleratorKernel`、`AcceleratorMemory`、`AcceleratorFence`。

---

## 10. 依赖的特性/接口/类

[`AcceleratorDevice`](AcceleratorDevice.md)、[`AcceleratorQueue`](AcceleratorQueue.md)、[`AcceleratorKernel`](AcceleratorKernel.md)、[`AcceleratorMemory`](AcceleratorMemory.md)、[`AcceleratorFence`](AcceleratorFence.md)、[`AcceleratorProgram`](AcceleratorProgram.md)、`Context`、`Bytes`、`Error`。

---

## 11. 所有权与并发

引用语义；命令缓冲由调用方拥有；设备、队列、内核、内存都是非拥有引用；fence 由调用方创建并传入。

非线程安全：`begin`/`bindKernel`/`bindMemory`/`bindValue`/`dispatch`/`end`/`submit`/`close` 不得并发；调用方必须串行化。`close()` 幂等指重复调用安全，不承诺并发 close 安全。

提交后，命令缓冲、内核、程序、内存、队列都必须保持打开直到 fence signaled。命令缓冲持有当前绑定与已 dispatch 引用的强引用用于校验，但不延长其原生生命周期；显式 `close()` 仍然有效。

无 `equals`/`copy`；`==` 是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：

- 创建命令缓冲 → `begin` → `bindKernel(kernel)` → `bindMemory(0, input, 0)` / `bindMemory(1, output, 0)` / `bindValue(2, sizeBytes)` → `dispatch(64, 1, 1, 256, 1, 1)` → `end` → 创建 fence → `submit(fence)` → `fence.wait`。
- 同一命令缓冲内切换内核：`bindKernel` 清空旧绑定，重新绑定后再次 dispatch；最后只 `end`/`submit` 一次。
- 后端只支持一维/工作组 1 时传 `1,1,1` 维度。
- 参数数量/类型由程序契约保证；本包不做反射，后端拒绝非法槽。

反例：

- 未 `begin` 就 `bindKernel`/`dispatch`。
- `bindKernel` 后不重新绑定参数就 dispatch，期望沿用上一个内核的绑定。
- `dispatch(0, 1, 1, ...)` 或工作组大小为 0。
- 把大于 16 字节的结构体塞进 `bindValue`，而不是内存对象。
- 用 `bindValue` 编码设备地址/指针。
- 把命令缓冲重用于第二次提交。
- 不等 fence 就关闭命令缓冲/内存。
- 把不同命令缓冲的 fence 传给 `submit`。
- 期望本包做渲染/显示或模型图调度。

---

## 13. 测试/场景义务

构造非法 handle/null 设备/队列 panic；跨设备队列 `InvalidArgument`；
状态机全路径：begin 两次、未 begin 绑定、end 零 dispatch、submit 两次；
`bindKernel` 清空绑定；同槽内存/标量覆盖；负索引；16 字节边界/空值；
内存偏移 0/末尾/越界；内存关闭/跨设备；
dispatch 各维度 0/负值/大值；工作组各维度 0/负值；后端不支持维度；
`end` 当前内核/程序关闭；`submit` fence 归属/关闭/队列关闭/已 dispatch 内核或程序关闭/已 dispatch 内存关闭；
切换内核后保留先前内核/内存并在 submit 校验；
提交失败消费；取消/`Busy`/`Io`；关闭幂等；设备关闭后 `close` `Ok(unit)`；
不等 fence 关闭的合同错误；无显示/无模型/无复用。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class AcceleratorCommandBuffer {
    final Long _handle
    final AcceleratorDevice _device
    final AcceleratorQueue _queue
    final Map<Int, AcceleratorMemory> _memoryBindings
    final Map<Int, Bytes> _valueBindings
    final List<AcceleratorKernel> _usedKernels
    final List<AcceleratorMemory> _usedMemories
    AcceleratorKernel? _kernel
    Int _dispatchCount
    Bool _recording
    Bool _ended
    Bool _submitted
    Bool _open

    AcceleratorCommandBuffer(Long handle, AcceleratorDevice device,
                             AcceleratorQueue queue) {
        if handle <= 0 || device == null || queue == null || !queue.isOpen() {
            throw "AcceleratorCommandBuffer: invalid field"
        }
        _handle = handle
        _device = device
        _queue = queue
        _memoryBindings = new Map<Int, AcceleratorMemory>()
        _valueBindings = new Map<Int, Bytes>()
        _usedKernels = []
        _usedMemories = []
        _kernel = null
        _dispatchCount = 0
        _recording = false
        _ended = false
        _submitted = false
        _open = true
    }

    Long commandBufferHandle() { return _handle }
    AcceleratorDevice device() { return _device }
    AcceleratorQueue queue() { return _queue }
    Bool isRecording() { return _recording }
    Bool isSubmitted() { return _submitted }
    Bool isOpen() { return _open }

    Result<Unit, Error> begin(Context context) {
        if context == null { throw "AcceleratorCommandBuffer.begin: null context" }
        if !_open || !_device.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator command buffer"))
        }
        if _recording || _ended || _submitted {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid state"))
        }
        Result<Unit, Error> begun = acceleratorCommandBufferBeginRaw(context, _handle)
        if begun.isErr() { return Err(begun.error()) }
        _recording = true
        return Ok(unit)
    }

    Result<Unit, Error> bindKernel(Context context, AcceleratorKernel kernel) {
        if context == null || kernel == null {
            throw "AcceleratorCommandBuffer.bindKernel: null argument"
        }
        if !_open || !_device.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator command buffer"))
        }
        if !_recording || _ended || _submitted {
            return Err(new BasicError(ErrorKind.InvalidArgument, "not recording"))
        }
        if !kernel.isOpen() || !kernel.program().isOpen()
            || !kernel.device().isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator kernel"))
        }
        if kernel.device() != _device {
            return Err(new BasicError(ErrorKind.InvalidArgument, "kernel from another device"))
        }
        Result<Unit, Error> bound = acceleratorCommandBufferBindKernelRaw(
            context, _handle, kernel.kernelHandle())
        if bound.isErr() { return Err(bound.error()) }
        _kernel = kernel
        _memoryBindings.clear()
        _valueBindings.clear()
        return Ok(unit)
    }

    Result<Unit, Error> bindMemory(Context context, Int argumentIndex,
                                   AcceleratorMemory memory, Long offsetBytes) {
        if context == null || memory == null {
            throw "AcceleratorCommandBuffer.bindMemory: null argument"
        }
        if !_open || !_device.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator command buffer"))
        }
        if !_recording || _ended || _submitted || _kernel == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "no current kernel"))
        }
        if argumentIndex < 0 || offsetBytes < 0 || offsetBytes >= memory.sizeBytes() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid binding"))
        }
        if !memory.isOpen() || !memory.device().isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator memory"))
        }
        if memory.device() != _device {
            return Err(new BasicError(ErrorKind.InvalidArgument, "memory from another device"))
        }
        Result<Unit, Error> bound = acceleratorCommandBufferBindMemoryRaw(
            context, _handle, argumentIndex, memory.memoryHandle(), offsetBytes)
        if bound.isErr() { return Err(bound.error()) }
        _memoryBindings.put(argumentIndex, memory)
        _valueBindings.remove(argumentIndex)
        return Ok(unit)
    }

    Result<Unit, Error> bindValue(Context context, Int argumentIndex, Bytes value) {
        if context == null || value == null {
            throw "AcceleratorCommandBuffer.bindValue: null argument"
        }
        if !_open || !_device.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator command buffer"))
        }
        if !_recording || _ended || _submitted || _kernel == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "no current kernel"))
        }
        if argumentIndex < 0 || value.length() == 0 || value.length() > 16 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid value binding"))
        }
        Bytes storedValue = value.copy()
        Result<Unit, Error> bound = acceleratorCommandBufferBindValueRaw(
            context, _handle, argumentIndex, storedValue)
        if bound.isErr() { return Err(bound.error()) }
        _valueBindings.put(argumentIndex, storedValue)
        _memoryBindings.remove(argumentIndex)
        return Ok(unit)
    }

    Result<Unit, Error> dispatch(Context context, Int groupCountX, Int groupCountY,
                                 Int groupCountZ, Int workGroupSizeX,
                                 Int workGroupSizeY, Int workGroupSizeZ) {
        if context == null { throw "AcceleratorCommandBuffer.dispatch: null context" }
        if !_open || !_device.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator command buffer"))
        }
        if !_recording || _ended || _submitted || _kernel == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "not recording"))
        }
        if !_kernel.isOpen() || !_kernel.program().isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator kernel"))
        }
        if groupCountX <= 0 || groupCountY <= 0 || groupCountZ <= 0
            || workGroupSizeX <= 0 || workGroupSizeY <= 0 || workGroupSizeZ <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid dispatch size"))
        }
        Result<Unit, Error> dispatched = acceleratorCommandBufferDispatchRaw(
            context, _handle, groupCountX, groupCountY, groupCountZ,
            workGroupSizeX, workGroupSizeY, workGroupSizeZ)
        if dispatched.isErr() { return Err(dispatched.error()) }
        _dispatchCount = _dispatchCount + 1
        _usedKernels.push(_kernel)
        List<AcceleratorMemory> boundMemories = _memoryBindings.values()
        Int memoryIndex = 0
        while memoryIndex < boundMemories.length() {
            _usedMemories.push(boundMemories.get(memoryIndex))
            memoryIndex = memoryIndex + 1
        }
        return Ok(unit)
    }

    Result<Unit, Error> end(Context context) {
        if context == null { throw "AcceleratorCommandBuffer.end: null context" }
        if !_open || !_device.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator command buffer"))
        }
        if !_recording || _ended || _submitted {
            return Err(new BasicError(ErrorKind.InvalidArgument, "not recording"))
        }
        if _dispatchCount == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "no dispatch recorded"))
        }
        if _kernel == null || !_kernel.isOpen() || !_kernel.program().isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator kernel"))
        }
        Result<Unit, Error> ended = acceleratorCommandBufferEndRaw(context, _handle)
        if ended.isErr() { return Err(ended.error()) }
        _recording = false
        _ended = true
        return Ok(unit)
    }

    Result<Unit, Error> submit(Context context, AcceleratorFence fence) {
        if context == null || fence == null {
            throw "AcceleratorCommandBuffer.submit: null argument"
        }
        if !_open || !_device.isOpen() || !_queue.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator command buffer"))
        }
        if !_ended || _submitted {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid state"))
        }
        if !fence.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "accelerator fence"))
        }
        if fence.commandBuffer() != this {
            return Err(new BasicError(ErrorKind.InvalidArgument, "fence from another buffer"))
        }
        Int kernelIndex = 0
        while kernelIndex < _usedKernels.length() {
            AcceleratorKernel kernel = _usedKernels.get(kernelIndex)
            if !kernel.isOpen() || !kernel.program().isOpen()
                || !kernel.device().isOpen() {
                return Err(new BasicError(ErrorKind.Unavailable, "accelerator kernel"))
            }
            kernelIndex = kernelIndex + 1
        }
        Int memoryIndex = 0
        while memoryIndex < _usedMemories.length() {
            AcceleratorMemory memory = _usedMemories.get(memoryIndex)
            if !memory.isOpen() || !memory.device().isOpen() {
                return Err(new BasicError(ErrorKind.Unavailable, "accelerator memory"))
            }
            memoryIndex = memoryIndex + 1
        }
        _submitted = true
        return acceleratorCommandBufferSubmitRaw(context, _handle, fence.fenceHandle())
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        _recording = false
        _kernel = null
        _memoryBindings.clear()
        _valueBindings.clear()
        _usedKernels.clear()
        _usedMemories.clear()
        if !_device.isOpen() { return Ok(unit) }
        return acceleratorCommandBufferCloseRaw(_handle)
    }
}
```
