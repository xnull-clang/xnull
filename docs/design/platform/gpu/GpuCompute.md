# `GpuCompute`

| 项 | 值 |
| --- | --- |
| 类型 | `class GpuCompute`（静态入口） |
| 包 | `xdk.gpu` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`GpuDevice`、`GpuQueue`、`GpuQueueKind`、`GpuBufferUsage`、`GpuProgramKind`、`Bytes`、`Error` |

---

## 1. 定位

`xdk.gpu` 的静态工厂入口：在已打开的 `GpuDevice` 上创建计算 buffer、program、pipeline、command buffer、fence。

只做：

- 参数校验、能力/状态检查、错误映射；
- 调用原生适配器创建资源；
- 返回调用方拥有的资源对象；
- 统一 `Context` 取消与 `Result` 失败通道。

不做：

- 设备枚举、设备打开、队列创建（属于 `xdk.os.gpu`）；
- 命令录制/提交（属于 `GpuCommandBuffer`）；
- 着色器语言、编译器、反射、入口点；
- 渲染/纹理/交换链/UI；
- 全局注册表、全局设备、自动关闭。

---

## 2. 设计逻辑

- 无状态静态类；构造器私有；没有实例字段、没有全局设备表。
- 所有工厂都接收已打开的 `GpuDevice`；设备能力门控在上游完成（`OsProfile.has(OsCapability.Gpu)` + `GpuDevice` 打开/队列创建），本类不重复探测。
- `createBuffer` 固定 usage 与逻辑大小；大小 > 0；usage 非 null。
- `createProgram` 接收不透明 `Bytes` 代码；基线只接受 `GpuProgramKind.Compute`；`Vertex`/`Fragment` 返回 `Unsupported`。
- `createPipeline` 绑定一个 Compute 程序与有序 `List<GpuBufferUsage>` 布局；布局元素非 null、不能含 `Indirect`；程序必须打开且属于同一设备。
- `createCommandBuffer` 绑定一个 `GpuDevice` 与一个 Compute 队列；非 Compute 队列返回 `Unsupported`。
- `createFence` 绑定一个尚未提交的命令缓冲；命令缓冲关闭/已提交时拒绝创建。
- 每个工厂返回新资源；调用方拥有并必须 `close()`；工厂不保留资源引用（资源内部保留设备/程序/队列非拥有引用）。
- 所有会触碰原生的方法检查 `Context` 取消；取消返回 `Cancelled`，不产生半初始化资源。
- 原生句柄必须 > 0；适配器返回 0/负数视为内部错误，工厂返回 `Internal`，不 panic。
- 静态类本身无状态，但对同一 `GpuDevice` 的并发工厂调用继承设备的非线程安全约束；调用方必须串行化。
- 不提供 `submit`/`dispatch`；提交入口是 `GpuCommandBuffer.submit`。

---

## 3. 表示与不变量

无实例字段。

不变量：

- 静态类不可实例化；构造器私有。
- 所有工厂返回的资源都属于传入的 `GpuDevice`；不跨设备。
- 工厂不保留资源引用、不注册全局表、不自动关闭。
- 任一工厂失败时不返回半初始化对象；原生资源已创建但构造失败时，适配器必须回收。
- 公开方法不出现后端原生句柄、驱动类型、着色器语言类型。

---

## 4. 生命周期

静态类；无实例、无 close；不拥有设备或资源。

每次工厂调用：

1. 校验 `Context`/参数/设备状态；
2. 检查取消；
3. 调用原生创建；
4. 校验原生句柄 > 0；
5. 构造资源对象并返回。

调用方按“等待 fence → 命令缓冲 → pipeline → program → buffer → fence → queue → device”的顺序关闭。`GpuCompute` 不参与关闭。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `GpuCompute()` | 无 | 私有；禁止实例化 | 外部构造 → 编译错误/panic |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `createBuffer` | 创建计算缓冲 | `Context context, GpuDevice device, GpuBufferUsage usage, Long sizeBytes` | `Result<GpuBuffer, Error>` | `InvalidArgument`/`Unavailable`/`Unsupported`/`OutOfMemory`/`Cancelled`/`Internal` | sizeBytes > 0 |
| `createProgram` | 创建计算程序 | `Context context, GpuDevice device, Bytes code, GpuProgramKind programKind` | `Result<GpuProgram, Error>` | `InvalidArgument`/`Unavailable`/`Unsupported`/`OutOfMemory`/`Cancelled`/`Internal` | 仅 Compute |
| `createPipeline` | 创建计算管线 | `Context context, GpuDevice device, GpuProgram program, List<GpuBufferUsage> bufferLayout` | `Result<GpuPipeline, Error>` | `InvalidArgument`/`Unavailable`/`Unsupported`/`OutOfMemory`/`Cancelled`/`Internal` | 程序 Compute 且同设备 |
| `createCommandBuffer` | 创建命令缓冲 | `Context context, GpuDevice device, GpuQueue queue` | `Result<GpuCommandBuffer, Error>` | `InvalidArgument`/`Unavailable`/`Unsupported`/`OutOfMemory`/`Cancelled`/`Internal` | 队列必须 Compute |
| `createFence` | 创建完成栅栏 | `Context context, GpuDevice device, GpuCommandBuffer commandBuffer` | `Result<GpuFence, Error>` | `InvalidArgument`/`Unavailable`/`OutOfMemory`/`Cancelled`/`Internal` | 命令缓冲未提交 |

说明：

- `createBuffer`：
  - `context == null`、`device == null` 或 `usage == null` → panic。
  - `sizeBytes <= 0` → `InvalidArgument`。
  - 设备关闭 → `Unavailable`；取消 → `Cancelled`。
  - 原生失败可能返回 `Unsupported`（usage/后端限制）、`OutOfMemory`、`Io`/`Busy`；适配器映射。
  - 成功后返回新 `GpuBuffer`；`sizeBytes` 是逻辑大小。
- `createProgram`：
  - `context == null`、`device == null`、`code == null` 或 `programKind == null` → panic。
  - `code.length() == 0` → `InvalidArgument`。
  - 设备关闭 → `Unavailable`；取消 → `Cancelled`。
  - `programKind != Compute` → `Unsupported`（Vertex/Fragment 是 X 渲染）。
  - 原生代码格式/后端限制 → `Unsupported`；资源不足 → `OutOfMemory`。
  - 成功后返回新 `GpuProgram`；不保留 `code`。
- `createPipeline`：
  - `context == null`、`device == null`、`program == null` 或 `bufferLayout == null` → panic。
  - 设备/程序关闭 → `Unavailable`；取消 → `Cancelled`。
  - 程序 kind 非 Compute → `Unsupported`；程序不属于本设备 → `InvalidArgument`。
  - 布局元素 null 或含 `Indirect` → `InvalidArgument`；空布局允许。
  - 原生槽位/对齐限制 → `Unsupported`/`InvalidArgument`；资源不足 → `OutOfMemory`。
  - 成功后返回新 `GpuPipeline`；布局被复制。
- `createCommandBuffer`：
  - `context == null`、`device == null` 或 `queue == null` → panic。
  - 设备/队列关闭 → `Unavailable`；取消 → `Cancelled`。
  - 队列 kind 非 Compute → `Unsupported`。
  - 队列必须由同一设备创建；`GpuQueue` 不暴露所属设备，跨设备队列是调用方合同错误，适配器能检测时返回 `InvalidArgument`。
  - 成功后返回新 `GpuCommandBuffer`；命令缓冲固定该设备与队列。
- `createFence`：
  - `context == null`、`device == null` 或 `commandBuffer == null` → panic。
  - 设备/命令缓冲关闭 → `Unavailable`；取消 → `Cancelled`。
  - 命令缓冲不属于本设备 → `InvalidArgument`。
  - 命令缓冲已提交（`isSubmitted()`）→ `InvalidArgument`；fence 必须在提交前创建。
  - 成功后返回新 `GpuFence`；fence 绑定该命令缓冲。
- 所有工厂：`context.isCancelled()` 在原生调用前检查；原生调用也应可取消。
- 不提供 `submit`/`waitIdle`/`createQueue`/`openDevice`：`submit` 属于 `GpuCommandBuffer`；`waitIdle` 不在基线；`createQueue`/`openDevice` 属于 `xdk.os.gpu`。
- 不提供 `describe`/`equals`/`copy`；静态类无实例。

---

## 8. 使用的技术

- 静态工厂；
- 参数/状态校验；
- 不透明 `Long` 句柄创建；
- `Context`/`Result` 错误映射；
- 取消检查；
- 无全局状态。

---

## 9. 需要的支撑

- 语言：class、static、private 构造器、Long、Int、Bool、List、Result；
- 运行时/适配器：
  - `gpuBufferCreateRaw(Context context, GpuDevice device, GpuBufferUsage usage, Long sizeBytes) -> Result<Long, Error>`；
  - `gpuProgramCreateRaw(Context context, GpuDevice device, Bytes code, GpuProgramKind programKind) -> Result<Long, Error>`；
  - `gpuPipelineCreateRaw(Context context, GpuDevice device, Long programHandle, List<GpuBufferUsage> bufferLayout) -> Result<Long, Error>`；
  - `gpuCommandBufferCreateRaw(Context context, GpuDevice device, GpuQueue queue) -> Result<Long, Error>`；
  - `gpuFenceCreateRaw(Context context, GpuDevice device, GpuCommandBuffer commandBuffer) -> Result<Long, Error>`；
- 原生句柄必须 > 0；0/负数返回 `Internal`；
- 适配器解析 `GpuDevice`/`GpuQueue`/`GpuCommandBuffer` 的内部句柄；公共 API 不暴露；
- 接口：`Context`、`Bytes`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`cancelledError`、`GpuDevice`、`GpuQueue`、`GpuQueueKind`、`GpuBufferUsage`、`GpuProgramKind`、`GpuBuffer`、`GpuProgram`、`GpuPipeline`、`GpuCommandBuffer`、`GpuFence`。

---

## 10. 依赖的特性/接口/类

[`GpuBuffer`](GpuBuffer.md)、[`GpuBufferUsage`](GpuBufferUsage.md)、[`GpuProgram`](GpuProgram.md)、[`GpuProgramKind`](GpuProgramKind.md)、[`GpuPipeline`](GpuPipeline.md)、[`GpuCommandBuffer`](GpuCommandBuffer.md)、[`GpuFence`](GpuFence.md)、[`GpuDevice`](../os/gpu/GpuDevice.md)、[`GpuQueue`](../os/gpu/GpuQueue.md)、[`GpuQueueKind`](../os/gpu/GpuQueueKind.md)、[`GpuBackend`](../os/gpu/GpuBackend.md)、`Context`、`Bytes`、`Error`。

---

## 11. 所有权与并发

静态无状态；不拥有设备或资源；工厂返回调用方拥有的新资源。

并发：`GpuCompute` 本身可并发调用，但对同一 `GpuDevice` 的工厂调用继承设备的非线程安全约束；调用方必须按设备串行化。不同设备之间可以并行，前提是适配器支持。

无全局注册表、无全局锁、无自动关闭；资源生命周期完全由调用方管理。

无 `equals`/`copy`；静态类不适用。

---

## 12. 示例与反例

正确：

- 先通过 `xdk.os.gpu` 打开设备、创建 Compute 队列；再调用 `createBuffer`/`createProgram`/`createPipeline`/`createCommandBuffer`/`createFence`；最后用命令缓冲录制/提交。
- `createProgram` 只传 `GpuProgramKind.Compute`；`Vertex`/`Fragment` 直接按 X 拒绝。
- `createPipeline` 的布局与程序显式匹配；不含 `Indirect`。
- `createFence` 在 `submit` 前调用；fence 绑定对应命令缓冲。
- 工厂失败时检查错误分类；`Cancelled` 不重试，`Unavailable` 检查设备生命周期。

反例：

- 期望 `GpuCompute` 枚举/打开设备或创建队列。
- 设备关闭后继续调用工厂。
- 用 `Vertex`/`Fragment` 创建程序并期望成功。
- 传空代码、负大小、`Indirect` 布局。
- 用 `Transfer`/`Graphics` 队列创建命令缓冲。
- 命令缓冲提交后再创建 fence。
- 认为工厂会提交命令或自动等待。
- 工厂返回资源后不关闭；或跨设备混用资源。

---

## 13. 测试/场景义务

- 每个工厂：成功路径；null 参数 panic；设备关闭 `Unavailable`；取消 `Cancelled`；原生句柄 0/负 `Internal`。
- `createBuffer`：size 0/负；不同 usage；`OutOfMemory`/`Unsupported` 映射。
- `createProgram`：Compute 成功；Vertex/Fragment `Unsupported`；空代码 `InvalidArgument`；不支持代码格式 `Unsupported`；不保留输入 `Bytes`。
- `createPipeline`：空/单/多槽；`Indirect`/null 元素 `InvalidArgument`；程序关闭 `Unavailable`；非 Compute `Unsupported`；跨设备 `InvalidArgument`；布局复制。
- `createCommandBuffer`：Compute 成功；Transfer/Graphics `Unsupported`；设备/队列关闭 `Unavailable`；跨设备队列（可检测时）`InvalidArgument`。
- `createFence`：命令缓冲打开且未提交时成功；关闭 `Unavailable`；跨设备 `InvalidArgument`；已提交 `InvalidArgument`。
- 多个设备/多个资源并存；工厂无全局状态；重复调用返回独立资源。
- 与 `GpuCommandBuffer.submit`、`GpuFence.wait`、资源关闭顺序组合。
- 并发误用不在保证范围；测试只验证按设备串行契约。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class GpuCompute {
    private GpuCompute() {}

    static Result<GpuBuffer, Error> createBuffer(Context context,
                                                 GpuDevice device,
                                                 GpuBufferUsage usage,
                                                 Long sizeBytes) {
        if context == null || device == null || usage == null {
            throw "GpuCompute.createBuffer: null argument"
        }
        if sizeBytes <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "buffer size must be positive"))
        }
        if !device.isOpen() {
            return Err(unavailableError("gpu device"))
        }
        if context.isCancelled() {
            return Err(cancelledError("gpu buffer create"))
        }
        Result<Long, Error> created = gpuBufferCreateRaw(
            context, device, usage, sizeBytes)
        if created.isErr() { return Err(created.error()) }
        if created.value() <= 0 {
            return Err(new BasicError(ErrorKind.Internal,
                "invalid gpu buffer handle"))
        }
        return Ok(new GpuBuffer(created.value(), device, usage, sizeBytes))
    }

    static Result<GpuProgram, Error> createProgram(Context context,
                                                   GpuDevice device,
                                                   Bytes code,
                                                   GpuProgramKind programKind) {
        if context == null || device == null || code == null
            || programKind == null {
            throw "GpuCompute.createProgram: null argument"
        }
        if programKind != GpuProgramKind.Compute {
            return Err(new BasicError(ErrorKind.Unsupported,
                "program kind requires X rendering"))
        }
        if code.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "empty program code"))
        }
        if !device.isOpen() {
            return Err(unavailableError("gpu device"))
        }
        if context.isCancelled() {
            return Err(cancelledError("gpu program create"))
        }
        Result<Long, Error> created = gpuProgramCreateRaw(
            context, device, code, programKind)
        if created.isErr() { return Err(created.error()) }
        if created.value() <= 0 {
            return Err(new BasicError(ErrorKind.Internal,
                "invalid gpu program handle"))
        }
        return Ok(new GpuProgram(created.value(), device, programKind,
            device.backend()))
    }

    static Result<GpuPipeline, Error> createPipeline(Context context,
                                                     GpuDevice device,
                                                     GpuProgram program,
                                                     List<GpuBufferUsage> bufferLayout) {
        if context == null || device == null || program == null
            || bufferLayout == null {
            throw "GpuCompute.createPipeline: null argument"
        }
        if !device.isOpen() || !program.isOpen() {
            return Err(unavailableError("gpu pipeline dependency"))
        }
        if program.device() != device {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "program from another device"))
        }
        if program.programKind() != GpuProgramKind.Compute {
            return Err(new BasicError(ErrorKind.Unsupported,
                "pipeline requires a compute program"))
        }
        Int index = 0
        while index < bufferLayout.length() {
            GpuBufferUsage usage = bufferLayout.get(index)
            if usage == null {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "null buffer usage"))
            }
            if usage == GpuBufferUsage.Indirect {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "indirect layout is X"))
            }
            index = index + 1
        }
        if context.isCancelled() {
            return Err(cancelledError("gpu pipeline create"))
        }
        Result<Long, Error> created = gpuPipelineCreateRaw(
            context, device, program.programId(), bufferLayout)
        if created.isErr() { return Err(created.error()) }
        if created.value() <= 0 {
            return Err(new BasicError(ErrorKind.Internal,
                "invalid gpu pipeline handle"))
        }
        return Ok(new GpuPipeline(created.value(), device, program,
            bufferLayout))
    }

    static Result<GpuCommandBuffer, Error> createCommandBuffer(Context context,
                                                               GpuDevice device,
                                                               GpuQueue queue) {
        if context == null || device == null || queue == null {
            throw "GpuCompute.createCommandBuffer: null argument"
        }
        if !device.isOpen() || !queue.isOpen() {
            return Err(unavailableError("gpu command buffer dependency"))
        }
        if queue.kind() != GpuQueueKind.Compute {
            return Err(new BasicError(ErrorKind.Unsupported,
                "command buffer requires a compute queue"))
        }
        if context.isCancelled() {
            return Err(cancelledError("gpu command buffer create"))
        }
        Result<Long, Error> created = gpuCommandBufferCreateRaw(
            context, device, queue)
        if created.isErr() { return Err(created.error()) }
        if created.value() <= 0 {
            return Err(new BasicError(ErrorKind.Internal,
                "invalid gpu command buffer handle"))
        }
        return Ok(new GpuCommandBuffer(created.value(), device, queue))
    }

    static Result<GpuFence, Error> createFence(Context context,
                                               GpuDevice device,
                                               GpuCommandBuffer commandBuffer) {
        if context == null || device == null || commandBuffer == null {
            throw "GpuCompute.createFence: null argument"
        }
        if !device.isOpen() || !commandBuffer.isOpen() {
            return Err(unavailableError("gpu fence dependency"))
        }
        if commandBuffer.device() != device {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "command buffer from another device"))
        }
        if commandBuffer.isSubmitted() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "fence must be created before submission"))
        }
        if context.isCancelled() {
            return Err(cancelledError("gpu fence create"))
        }
        Result<Long, Error> created = gpuFenceCreateRaw(
            context, device, commandBuffer)
        if created.isErr() { return Err(created.error()) }
        if created.value() <= 0 {
            return Err(new BasicError(ErrorKind.Internal,
                "invalid gpu fence handle"))
        }
        return Ok(new GpuFence(created.value(), device, commandBuffer))
    }
}
```
