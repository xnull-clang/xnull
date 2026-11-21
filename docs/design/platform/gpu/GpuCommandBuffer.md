# `GpuCommandBuffer`

| 项 | 值 |
| --- | --- |
| 类型 | `class GpuCommandBuffer` |
| 包 | `xdk.gpu` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`GpuDevice`、`GpuQueue`、`GpuQueueKind`、`GpuPipeline`、`GpuBuffer`、`GpuFence`、`Error` |

---

## 1. 定位

绑定到一个 Compute 队列的 GPU 计算命令缓冲：录制 `begin` / `bindPipeline` / `bindBuffer` / `dispatch` / `end`，然后 `submit` 到队列，并用 `GpuFence` 等待完成。

只做：

- 计算命令录制与一次提交；
- 显式管线/缓冲绑定校验；
- 与完成栅栏关联；
- 关闭与生命周期查询。

不做：

- 渲染 pass、draw call、纹理/采样器/交换链；
- copy/blit、indirect dispatch、查询池、时间戳；
- 多队列/多设备提交、次级命令缓冲、命令缓冲复用/重录制；
- 显示/呈现提交；
- 隐式资源同步或自动 fence。

---

## 2. 设计逻辑

- 由 `GpuCompute.createCommandBuffer(context, device, queue)` 创建；构造器主要供宿主/测试使用。
- 命令缓冲固定一个 `GpuDevice` 与一个 `GpuQueue`；队列 kind 必须是 `Compute`，其他 kind 在工厂返回 `Unsupported`。
- `_handle` 是 `Long` 不透明句柄；不暴露后端 command buffer 对象。
- 状态机：Created → Recording → Ended → Submitted；一次性，不允许重录制/复用。
- `begin` 只允许从 Created 进入 Recording；`end` 要求至少一次 dispatch，且当前管线布局全部绑定；`submit` 只允许一次。
- `bindPipeline` 会清空当前缓冲绑定；同一个命令缓冲可以在多次 dispatch 之间切换管线。每次 dispatch 前必须满足当前布局。
- `dispatch` 的参数是工作组数量，三个维度都必须 > 0；工作组大小由程序/后端决定，管线不暴露。
- 每次 `submit` 必须带一个为该命令缓冲创建的 `GpuFence`；无栅栏 fire-and-forget 提交不在基线。
- 命令缓冲保存已 dispatch 的管线/缓冲引用，用于提交前检查它们仍然打开；它不拥有这些资源。
- 提交后 command buffer、pipeline、program、buffer 都必须保持打开直到 fence signaled。
- 关闭后纯元数据（ID、设备、isOpen、isSubmitted）仍可读；录制/提交返回 `Unavailable`。
- 设备先关闭时，`close()` 标记关闭后跳过原生关闭，视为设备回收，返回 `Ok(unit)`。
- 无 `equals`/`copy`；命令缓冲是资源，不是值对象。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | > 0；不透明句柄 |
| `_device` | `GpuDevice` | final | 非 null；非拥有引用 |
| `_queue` | `GpuQueue` | final | 非 null；非拥有引用；Compute |
| `_bindings` | `Map<Int, GpuBuffer>` | final | 当前管线的绑定；键 ≥ 0；值非 null |
| `_usedPipelines` | `List<GpuPipeline>` | final | 已 dispatch 的管线；可重复 |
| `_usedBuffers` | `List<GpuBuffer>` | final | 已 dispatch 的缓冲；可重复 |
| `_pipeline` | `GpuPipeline?` | 内部 | 当前绑定的管线；可为 null |
| `_dispatchCount` | `Int` | 内部 | ≥ 0；成功 dispatch 次数 |
| `_recording` | `Bool` | 内部 | 正在录制 |
| `_ended` | `Bool` | 内部 | 已完成 end |
| `_submitted` | `Bool` | 内部 | 已尝试 submit |
| `_open` | `Bool` | 内部 | 构造后 true；close 后 false |

不变量：

- `handle > 0`；`device`/`queue` 非 null；`queue.kind() == Compute`。
- `_bindings` 的键必须在当前管线布局范围内；`bindPipeline` 清空 `_bindings`。
- `_usedPipelines`/`_usedBuffers` 只记录成功 dispatch 使用过的资源；可含重复项。
- `_dispatchCount` 等于成功 dispatch 次数；`end` 要求 > 0。
- 状态单调：`_recording` 与 `_ended` 不同时为 true；`_ended` 为 true 时 `_recording` 为 false；`_submitted` 为 true 时 `_ended` 为 true。
- `_open` 为 false 时 `_recording` 为 false；关闭后不再调用原生 command buffer 原语。
- 命令缓冲不拥有管线/缓冲/队列/设备；只持有引用用于校验。
- 提交后命令缓冲、pipeline、program、buffer 都必须保持打开直到 fence signaled。

---

## 4. 生命周期

由 `GpuCompute.createCommandBuffer` 创建；调用方拥有并必须 `close()`；close 幂等；无 `deinit` 依赖。

录制阶段：

- Created → `begin` → Recording；
- Recording → `bindPipeline`/`bindBuffer`/`dispatch`（可多次）；
- Recording → `end` → Ended；
- Ended → `submit(fence)` → Submitted。

关闭：

- Created/Recording/Ended 都可以 `close()`；Recording 中关闭会丢弃未提交命令；
- Submitted 后必须等 fence signaled 才能 `close()`；提前关闭可能释放 GPU 仍在使用的命令记录；
- 设备先关闭时，`close()` 标记关闭后跳过原生关闭，返回 `Ok(unit)`；设备关闭不会自动把命令缓冲标记为 closed，`isOpen()` 仍为 true 直到调用方 `close()`。

设备/队列必须比命令缓冲活得久。队列先关闭时，录制可以继续，但 `submit` 返回 `Unavailable`。fence 绑定原生完成事件；基线要求 fence signaled 后再关闭命令缓冲。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `GpuCommandBuffer(Long handle, GpuDevice device, GpuQueue queue)` | handle、device、queue | handle > 0；device/queue 非 null；queue 打开且 `kind == Compute` | 非法 → panic |

构造器主要供宿主/测试使用；业务代码通过 `GpuCompute.createCommandBuffer` 获取。工厂对已关闭设备/队列返回 `Unavailable`，对非 Compute 队列返回 `Unsupported`。

---

## 6. 字段表

见 §3；字段私有。不暴露后端 command buffer、队列句柄或原生命令编码器。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `commandBufferId` | 不透明句柄 | 无 | `Long` | 无 | O(1)；不持久 |
| `device` | 所属设备 | 无 | `GpuDevice` | 无 | 非拥有引用 |
| `isSubmitted` | 是否已尝试提交 | 无 | `Bool` | 无 | O(1)；状态查询 |
| `begin` | 开始录制 | `Context context` | `Result<Unit, Error>` | `InvalidArgument`/`Unavailable`/`Cancelled` | 仅 Created → Recording |
| `bindPipeline` | 绑定管线 | `Context context, GpuPipeline pipeline` | `Result<Unit, Error>` | `InvalidArgument`/`Unavailable`/`Cancelled` | 清空缓冲绑定 |
| `bindBuffer` | 绑定缓冲 | `Context context, Int bindingIndex, GpuBuffer buffer` | `Result<Unit, Error>` | `InvalidArgument`/`Unavailable`/`Cancelled` | 需先绑定管线 |
| `dispatch` | 工作组派发 | `Context context, Int groupCountX, Int groupCountY, Int groupCountZ` | `Result<Unit, Error>` | `InvalidArgument`/`Unavailable`/`Cancelled` | 三个计数 > 0 |
| `end` | 结束录制 | `Context context` | `Result<Unit, Error>` | `InvalidArgument`/`Unavailable`/`Cancelled` | 至少一次 dispatch；布局完整 |
| `submit` | 提交到队列 | `Context context, GpuFence fence` | `Result<Unit, Error>` | `InvalidArgument`/`Unavailable`/`Unsupported`/`Cancelled` | 一次性；fence 必须属于本缓冲 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） | O(1)；幂等 |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 | O(1) |

说明：

- `commandBufferId()` 返回不透明 `Long`；关闭后仍返回原值；不得当作跨进程或持久 ID。
- `device()` 返回非拥有引用；命令缓冲不关闭设备。
- `isSubmitted()` 在第一次 `submit` 尝试前置为 true；即使 `submit` 返回错误，命令缓冲也已消费，不能重试。校验失败（未进入原生提交）时保持 false。
- `begin`：
  - `context == null` → panic；关闭 → `Unavailable`；设备关闭 → `Unavailable`。
  - 非 Created 状态（已录制/已 end/已 submit）→ `InvalidArgument`。
  - 取消 → `Cancelled`；原生失败保持 Created。
  - 成功后 `_recording = true`。
- `bindPipeline`：
  - `context == null` 或 `pipeline == null` → panic；关闭/设备关闭 → `Unavailable`。
  - 非 Recording → `InvalidArgument`。
  - 管线关闭、程序关闭 → `Unavailable`；管线不属于本设备 → `InvalidArgument`。
  - 取消 → `Cancelled`；原生失败保持原管线/绑定不变。
  - 成功后设置当前管线并清空 `_bindings`；重复绑定同一管线也会清空。
- `bindBuffer`：
  - `context == null` 或 `buffer == null` → panic；关闭/设备关闭 → `Unavailable`。
  - 非 Recording 或没有当前管线 → `InvalidArgument`。
  - `bindingIndex < 0` 或 `bindingIndex >= pipeline.bufferCount()` → `InvalidArgument`。
  - buffer 关闭 → `Unavailable`；buffer 不属于本设备 → `InvalidArgument`。
  - usage 与当前槽不兼容（`gpuBufferUsageAllowsBinding`）→ `InvalidArgument`。
  - 取消 → `Cancelled`；原生失败保持该索引的旧绑定不变。
  - 成功后写入/替换 `_bindings[bindingIndex]`。
- `dispatch`：
  - `context == null` → panic；关闭/设备关闭 → `Unavailable`。
  - 非 Recording 或无当前管线 → `InvalidArgument`。
  - 任一 `groupCount <= 0` → `InvalidArgument`。
  - 当前布局任一槽未绑定或绑定 buffer 已关闭 → `InvalidArgument`/`Unavailable`。
  - 取消 → `Cancelled`；原生失败不增加 `_dispatchCount`、不记录使用资源。
  - 成功后 `_dispatchCount++`，并把当前管线与绑定 buffer 追加到 `_usedPipelines`/`_usedBuffers`。
- `end`：
  - `context == null` → panic；关闭/设备关闭 → `Unavailable`。
  - 非 Recording → `InvalidArgument`；`_dispatchCount == 0` → `InvalidArgument`。
  - 当前管线/程序关闭 → `Unavailable`；当前布局有未绑定槽 → `InvalidArgument`。
  - 取消 → `Cancelled`；原生失败保持 Recording，可修复后重试或关闭。
  - 成功后 `_recording = false`、`_ended = true`。
- `submit`：
  - `context == null` 或 `fence == null` → panic；关闭/设备/队列关闭 → `Unavailable`。
  - 队列 kind 非 Compute → `Unsupported`（构造已保证，防御性检查）。
  - 非 Ended 或已 submit → `InvalidArgument`。
  - `_usedPipelines` 中任一管线/程序关闭，或 `_usedBuffers` 中任一 buffer 关闭 → `Unavailable`。
  - fence 关闭 → `Unavailable`；fence 不属于本设备或不属于本命令缓冲 → `InvalidArgument`。
  - 调用前取消 → `Cancelled`，不消费命令缓冲；进入原生提交后返回 `Cancelled`/失败 → 命令缓冲已消费，不能重试。
  - 校验通过后先置 `_submitted = true`，再调用原生提交；原生失败也保持已消费。失败提交的 fence 不保证信号；调用方应关闭 fence，不得依赖其完成通知。
  - 提交只到 Compute 队列；不涉及显示/呈现。
- `close`：
  - 第一次调用标记关闭并清 `_recording`；设备仍打开时调用原生关闭；设备已关闭时跳过；后续返回 `Ok(unit)`。
  - 关闭失败只作为诊断返回 `Io`；不改变已关闭状态；不关闭管线/缓冲/队列/fence。
  - `close` 不检查 fence 状态；提交后提前关闭是调用方合同错误，可能释放 GPU 仍在使用的命令记录。
- `isOpen()` 不触碰原生句柄。
- 不提供 `reset`/`reuse`/`submitAndWait`；这些是 X 或调用方组合。
- 不提供 `describe`/`equals`/`copy`；命令缓冲是资源，不是值对象。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- 显式状态机；
- 绑定表（`Map<Int, GpuBuffer>`）；
- 已使用资源追踪；
- 显式完成栅栏；
- `Context`/`Result`；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、Int、Bool、Map、List、Result；
- 运行时/适配器：
  - `gpuCommandBufferCreateRaw(Context context, GpuDevice device, GpuQueue queue) -> Result<Long, Error>`；
  - `gpuCommandBufferBeginRaw(Context context, Long commandBufferHandle) -> Result<Unit, Error>`；
  - `gpuCommandBufferBindPipelineRaw(Context context, Long commandBufferHandle, Long pipelineHandle) -> Result<Unit, Error>`；
  - `gpuCommandBufferBindBufferRaw(Context context, Long commandBufferHandle, Int bindingIndex, Long bufferHandle) -> Result<Unit, Error>`；
  - `gpuCommandBufferDispatchRaw(Context context, Long commandBufferHandle, Int groupCountX, Int groupCountY, Int groupCountZ) -> Result<Unit, Error>`；
  - `gpuCommandBufferEndRaw(Context context, Long commandBufferHandle) -> Result<Unit, Error>`；
  - `gpuCommandBufferSubmitRaw(Context context, Long commandBufferHandle, Long fenceHandle) -> Result<Unit, Error>`；
  - `gpuCommandBufferCloseRaw(Long commandBufferHandle) -> Result<Unit, Error>`；
- 原生 command buffer 句柄必须 > 0；0/负数视为适配器内部错误（工厂返回 `Internal`，构造器 panic）；
- 适配器必须检查 `Context` 取消，不得无限阻塞忽略取消；
- 适配器解析 `GpuDevice`/`GpuQueue` 的内部句柄；公共 API 不暴露这些句柄；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`cancelledError`、`gpuBufferUsageAllowsBinding`、`GpuDevice`、`GpuQueue`、`GpuQueueKind`、`GpuPipeline`、`GpuBuffer`、`GpuFence`。

---

## 10. 依赖的特性/接口/类

[`GpuCompute`](GpuCompute.md)、[`GpuPipeline`](GpuPipeline.md)、[`GpuBuffer`](GpuBuffer.md)、[`GpuFence`](GpuFence.md)、[`GpuDevice`](../os/gpu/GpuDevice.md)、[`GpuQueue`](../os/gpu/GpuQueue.md)、[`GpuQueueKind`](../os/gpu/GpuQueueKind.md)、[`GpuBufferUsage`](GpuBufferUsage.md)、`Context`、`Error`。

---

## 11. 所有权与并发

引用语义；命令缓冲由调用方拥有；设备、队列、管线、缓冲、fence 都是非拥有引用（fence 由调用方创建并传入）。

非线程安全：`begin`/`bindPipeline`/`bindBuffer`/`dispatch`/`end`/`submit`/`close` 不得并发；调用方必须串行化。`close()` 幂等指重复调用安全，不承诺并发 close 安全。

提交后，命令缓冲、pipeline、program、buffer 都必须保持打开直到 fence signaled。命令缓冲持有已使用资源的强引用用于校验，但不延长其原生生命周期；显式 `close()` 仍然有效。

无 `equals`/`copy`；`==` 是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：

- 创建 Compute 队列与命令缓冲；`begin` → `bindPipeline` → 按布局逐个 `bindBuffer` → `dispatch` → 可切换管线/重新绑定 → `end`；创建 fence；`submit(fence)`；`fence.wait`；按 §4 的关闭顺序关闭。
- 一个命令缓冲内多次 dispatch；每次 `bindPipeline` 后重新绑定；`end` 只调用一次。
- 提交后等 fence signaled，再关闭 command buffer、pipeline、program、buffer，最后关闭 fence。
- 提交前检查 `isSubmitted()`；为 fence 创建时确保命令缓冲尚未提交。

反例：

- 未 `begin` 就 `bindPipeline`；未绑定管线就 `bindBuffer`；布局槽未绑满就 `dispatch`/`end`。
- `dispatch(0, 1, 1)` 或负数工作组数量。
- 绑定 usage 不兼容的 buffer（`Read` 到 `Write` 槽）。
- 提交前关闭 pipeline/program/buffer；或 fence 还没 signaled 就读取/关闭 buffer。
- 用另一个命令缓冲的 fence 提交；提交后再次 `submit`。
- 把 `GpuCommandBuffer` 当可复用对象；`end` 后再次 `begin`。
- 把命令提交到 `Transfer`/`Graphics` 队列，或期望本包做显示/呈现。
- 关闭后继续录制/提交，或并发调用 `dispatch`/`close`。

---

## 13. 测试/场景义务

- 构造非法 handle/device/queue panic；非 Compute 队列 panic；工厂对已关闭设备/队列 `Unavailable`、非 Compute `Unsupported`。
- 状态机：Created 下 bind/dispatch/end/submit 失败；begin 后重复 begin 失败；end 后 begin 失败；submit 后 begin/end/submit 失败；`isSubmitted` 状态正确。
- `begin`/`end` 的取消；原生 begin/end 失败后的状态保持。
- `bindPipeline`：关闭管线、关闭程序、跨设备、重复绑定清空绑定。
- `bindBuffer`：未绑管线、索引越界、buffer 关闭、跨设备、每种 usage 兼容/不兼容组合、替换同一索引。
- `dispatch`：三个维度 0/负数；布局未绑满；绑定 buffer 关闭；多次 dispatch；成功后 `_dispatchCount`/使用资源追踪。
- `end`：空命令缓冲；当前布局未绑满；当前管线/程序关闭；成功后 `_ended`。
- `submit`：未 end、重复 submit、队列关闭、设备关闭、已关闭资源、fence 关闭/跨设备/跨命令缓冲；成功提交；调用前取消不消费；原生提交中取消/失败已消费；fence 信号。
- `close`：Created/Recording/Ended 可关闭；Recording 中关闭丢弃；Submitted 后必须等 fence 再关闭；幂等；设备先关返回 `Ok(unit)`。
- 资源生命周期：提交后等 fence，再关 command buffer 与资源；提前关资源导致 submit 失败，提前关 command buffer 可能不安全。
- 空布局管线 dispatch；多管线切换；一个命令缓冲只提交一次。
- 并发误用不在保证范围；测试只验证串行契约。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class GpuCommandBuffer {
    final Long _handle
    final GpuDevice _device
    final GpuQueue _queue
    final Map<Int, GpuBuffer> _bindings
    final List<GpuPipeline> _usedPipelines
    final List<GpuBuffer> _usedBuffers
    GpuPipeline? _pipeline
    Int _dispatchCount
    Bool _recording
    Bool _ended
    Bool _submitted
    Bool _open

    GpuCommandBuffer(Long handle, GpuDevice device, GpuQueue queue) {
        if handle <= 0 || device == null || queue == null {
            throw "GpuCommandBuffer: invalid field"
        }
        if !queue.isOpen() {
            throw "GpuCommandBuffer: closed queue"
        }
        if queue.kind() != GpuQueueKind.Compute {
            throw "GpuCommandBuffer: requires compute queue"
        }
        _handle = handle
        _device = device
        _queue = queue
        _bindings = [:]
        _usedPipelines = []
        _usedBuffers = []
        _pipeline = null
        _dispatchCount = 0
        _recording = false
        _ended = false
        _submitted = false
        _open = true
    }

    Long commandBufferId() { return _handle }
    GpuDevice device() { return _device }
    Bool isSubmitted() { return _submitted }
    Bool isOpen() { return _open }

    Result<Unit, Error> begin(Context context) {
        if context == null {
            throw "GpuCommandBuffer.begin: null context"
        }
        if !_open { return Err(unavailableError("gpu command buffer")) }
        if !_device.isOpen() { return Err(unavailableError("gpu device")) }
        if _recording || _ended || _submitted {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "command buffer is not fresh"))
        }
        if context.isCancelled() {
            return Err(cancelledError("gpu command buffer begin"))
        }
        Result<Unit, Error> started = gpuCommandBufferBeginRaw(
            context, _handle)
        if started.isErr() { return Err(started.error()) }
        _recording = true
        return Ok(unit)
    }

    Result<Unit, Error> bindPipeline(Context context, GpuPipeline pipeline) {
        if context == null || pipeline == null {
            throw "GpuCommandBuffer.bindPipeline: null argument"
        }
        if !_open { return Err(unavailableError("gpu command buffer")) }
        if !_device.isOpen() { return Err(unavailableError("gpu device")) }
        if !_recording {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "command buffer is not recording"))
        }
        if !pipeline.isOpen() || !pipeline.program().isOpen() {
            return Err(unavailableError("gpu pipeline"))
        }
        if pipeline.device() != _device {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "pipeline from another device"))
        }
        if context.isCancelled() {
            return Err(cancelledError("gpu command buffer bind pipeline"))
        }
        Result<Unit, Error> bound = gpuCommandBufferBindPipelineRaw(
            context, _handle, pipeline.pipelineId())
        if bound.isErr() { return Err(bound.error()) }
        _pipeline = pipeline
        _bindings.clear()
        return Ok(unit)
    }

    Result<Unit, Error> bindBuffer(Context context, Int bindingIndex,
                                   GpuBuffer buffer) {
        if context == null || buffer == null {
            throw "GpuCommandBuffer.bindBuffer: null argument"
        }
        if !_open { return Err(unavailableError("gpu command buffer")) }
        if !_device.isOpen() { return Err(unavailableError("gpu device")) }
        if !_recording {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "command buffer is not recording"))
        }
        if _pipeline == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "no pipeline bound"))
        }
        if bindingIndex < 0 || bindingIndex >= _pipeline.bufferCount() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "binding index out of range"))
        }
        if !buffer.isOpen() {
            return Err(unavailableError("gpu buffer"))
        }
        if buffer.device() != _device {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "buffer from another device"))
        }
        GpuBufferUsage declaredUsage = _pipeline.bufferLayout().get(bindingIndex)
        if !gpuBufferUsageAllowsBinding(declaredUsage, buffer.usage()) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "buffer usage is not compatible with binding"))
        }
        if context.isCancelled() {
            return Err(cancelledError("gpu command buffer bind buffer"))
        }
        Result<Unit, Error> bound = gpuCommandBufferBindBufferRaw(
            context, _handle, bindingIndex, buffer.bufferId())
        if bound.isErr() { return Err(bound.error()) }
        _bindings.put(bindingIndex, buffer)
        return Ok(unit)
    }

    Result<Unit, Error> dispatch(Context context, Int groupCountX,
                                 Int groupCountY, Int groupCountZ) {
        if context == null {
            throw "GpuCommandBuffer.dispatch: null context"
        }
        if !_open { return Err(unavailableError("gpu command buffer")) }
        if !_device.isOpen() { return Err(unavailableError("gpu device")) }
        if !_recording {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "command buffer is not recording"))
        }
        if _pipeline == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "no pipeline bound"))
        }
        if groupCountX <= 0 || groupCountY <= 0 || groupCountZ <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "workgroup count must be positive"))
        }
        List<GpuBufferUsage> layout = _pipeline.bufferLayout()
        Int index = 0
        while index < layout.length() {
            if !_bindings.has(index) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "pipeline buffer is not bound"))
            }
            if !_bindings.get(index).isOpen() {
                return Err(unavailableError("gpu buffer"))
            }
            index = index + 1
        }
        if context.isCancelled() {
            return Err(cancelledError("gpu command buffer dispatch"))
        }
        Result<Unit, Error> dispatched = gpuCommandBufferDispatchRaw(
            context, _handle, groupCountX, groupCountY, groupCountZ)
        if dispatched.isErr() { return Err(dispatched.error()) }
        _usedPipelines.push(_pipeline)
        index = 0
        while index < layout.length() {
            _usedBuffers.push(_bindings.get(index))
            index = index + 1
        }
        _dispatchCount = _dispatchCount + 1
        return Ok(unit)
    }

    Result<Unit, Error> end(Context context) {
        if context == null {
            throw "GpuCommandBuffer.end: null context"
        }
        if !_open { return Err(unavailableError("gpu command buffer")) }
        if !_device.isOpen() { return Err(unavailableError("gpu device")) }
        if !_recording {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "command buffer is not recording"))
        }
        if _dispatchCount == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "command buffer has no dispatch"))
        }
        if _pipeline == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "no pipeline bound"))
        }
        if !_pipeline.isOpen() || !_pipeline.program().isOpen() {
            return Err(unavailableError("gpu pipeline"))
        }
        List<GpuBufferUsage> layout = _pipeline.bufferLayout()
        Int index = 0
        while index < layout.length() {
            if !_bindings.has(index) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "pipeline buffer is not bound"))
            }
            if !_bindings.get(index).isOpen() {
                return Err(unavailableError("gpu buffer"))
            }
            index = index + 1
        }
        if context.isCancelled() {
            return Err(cancelledError("gpu command buffer end"))
        }
        Result<Unit, Error> ended = gpuCommandBufferEndRaw(context, _handle)
        if ended.isErr() { return Err(ended.error()) }
        _recording = false
        _ended = true
        return Ok(unit)
    }

    Result<Unit, Error> submit(Context context, GpuFence fence) {
        if context == null || fence == null {
            throw "GpuCommandBuffer.submit: null argument"
        }
        if !_open { return Err(unavailableError("gpu command buffer")) }
        if !_device.isOpen() { return Err(unavailableError("gpu device")) }
        if !_queue.isOpen() { return Err(unavailableError("gpu queue")) }
        if _queue.kind() != GpuQueueKind.Compute {
            return Err(new BasicError(ErrorKind.Unsupported,
                "submission requires a compute queue"))
        }
        if !_ended || _submitted {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "command buffer is not ready for submission"))
        }
        Int index = 0
        while index < _usedPipelines.length() {
            GpuPipeline usedPipeline = _usedPipelines.get(index)
            if !usedPipeline.isOpen() || !usedPipeline.program().isOpen() {
                return Err(unavailableError("gpu pipeline"))
            }
            index = index + 1
        }
        index = 0
        while index < _usedBuffers.length() {
            if !_usedBuffers.get(index).isOpen() {
                return Err(unavailableError("gpu buffer"))
            }
            index = index + 1
        }
        if !fence.isOpen() {
            return Err(unavailableError("gpu fence"))
        }
        if fence.device() != _device {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "fence from another device"))
        }
        if fence.commandBuffer() != self {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "fence belongs to another command buffer"))
        }
        if context.isCancelled() {
            return Err(cancelledError("gpu command buffer submit"))
        }
        _submitted = true
        return gpuCommandBufferSubmitRaw(context, _handle, fence.fenceId())
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        _recording = false
        if !_device.isOpen() { return Ok(unit) }
        return gpuCommandBufferCloseRaw(_handle)
    }
}
```
