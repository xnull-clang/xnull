# `GpuFence`

| 项 | 值 |
| --- | --- |
| 类型 | `class GpuFence` |
| 包 | `xdk.gpu` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`GpuDevice`、`GpuCommandBuffer`、`Error` |

---

## 1. 定位

一次 GPU 计算提交的完成栅栏不透明句柄：等待提交完成、非阻塞查询是否已信号、关闭、是否可用。

只做：

- 绑定一个尚未提交的 `GpuCommandBuffer`；
- 在该命令缓冲 `submit` 后等待/查询完成；
- 关闭与生命周期查询。

不做：

- 手动 signal/reset；
- 可重置栅栏、timeline semaphore、多等待者/多提交合并；
- 查询 GPU 时间戳/性能计数；
- 显示/呈现同步；
- 跨设备/跨进程同步。

---

## 2. 设计逻辑

- 由 `GpuCompute.createFence(context, device, commandBuffer)` 创建；构造器主要供宿主/测试使用。
- fence 在创建时绑定一个命令缓冲；该命令缓冲的 `submit` 必须传入同一个 fence。这样每次提交都有明确的完成信号，避免无栅栏 fire-and-forget。
- `_handle` 是 `Long` 不透明句柄；不暴露后端 fence/semaphore 对象。
- fence 创建时未信号；提交前 `wait` 会等待或返回 `Timeout`，`isSignaled` 返回 false。未信号不是合同错误；`wait` 用 `Timeout` 表示期限内未信号。
- 命令缓冲提交成功后，fence 在 GPU 完成该次提交时变为 signaled。
- fence 一次性：无 reset、无手动 signal、不能用于第二个命令缓冲；这些是 X。
- `wait` 的 `timeoutMillis`：0 表示非阻塞轮询；> 0 表示最多等待毫秒；< 0 返回 `InvalidArgument`。信号返回 `Ok(unit)`，超时返回 `Timeout`；取消返回 `Cancelled`。
- `isSignaled` 是非阻塞查询；不缓存结果；关闭/设备关闭返回 `Unavailable`。
- fence 不拥有命令缓冲；基线要求命令缓冲保持到 fence signaled，之后才能关闭命令缓冲。
- 关闭后纯元数据（ID、设备、命令缓冲、isOpen）仍可读；`wait`/`isSignaled` 返回 `Unavailable`。
- 设备先关闭时，`close()` 标记关闭后跳过原生关闭，视为设备回收，返回 `Ok(unit)`。
- 无 `equals`/`copy`；fence 是资源，不是值对象。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | > 0；不透明句柄 |
| `_device` | `GpuDevice` | final | 非 null；非拥有引用 |
| `_commandBuffer` | `GpuCommandBuffer` | final | 非 null；创建时打开且未提交 |
| `_open` | `Bool` | 内部 | 构造后 true；close 后 false |

不变量：

- `handle > 0`；`device`/`commandBuffer` 非 null。
- `commandBuffer.device() == device`；创建时命令缓冲打开且 `isSubmitted()` 为 false。
- 构造后 `open = true`；`close()` 后 `open = false`；close 幂等。
- fence 创建时未信号；只有对应命令缓冲提交且 GPU 完成后才可能信号。
- fence 绑定唯一命令缓冲；不能复用/重绑定。
- 关闭后不再调用任何原生 fence 原语。
- fence 不拥有设备或命令缓冲；不关闭它们。

---

## 4. 生命周期

由 `GpuCompute.createFence` 创建；调用方拥有并必须 `close()`；close 幂等；无 `deinit` 依赖。

创建约束：

- 命令缓冲必须打开且尚未提交；
- 同一命令缓冲可以创建多个 fence；一次 `submit` 只能传一个，未传入的 fence 不会被信号，调用方应关闭它；推荐一次提交只创建一个 fence。
- 命令缓冲在提交前关闭时，fence 永远不会信号；调用方应关闭它。
- 提交失败时 fence 不保证信号；调用方应关闭它，不得依赖失败提交的完成通知。
- fence 创建后、提交前可以 `wait`/`isSignaled`，结果未信号；`wait` 超时返回 `Timeout`，不是未定义行为。

提交后：

- 命令缓冲必须保持到 fence signaled；等待期间 fence 可独立查询；
- `wait` 返回 `Ok(unit)` 后，才能安全读取/关闭命令缓冲引用的 GPU 资源；
- `wait` 超时返回 `Timeout`，不取消 GPU 工作，可再次等待；
- `close` 应在等待完成或确定放弃后用；提前关闭可能丢失完成信号，调用方承担风险。

设备先关闭时，`wait`/`isSignaled` 返回 `Unavailable`；`close()` 标记关闭后跳过原生关闭，返回 `Ok(unit)`；设备关闭不会自动把 fence 标记为 closed，`isOpen()` 仍为 true 直到调用方 `close()`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `GpuFence(Long handle, GpuDevice device, GpuCommandBuffer commandBuffer)` | handle、device、commandBuffer | handle > 0；device/commandBuffer 非 null；命令缓冲打开、未提交、属于同一设备 | 非法 → panic |

构造器主要供宿主/测试使用；业务代码通过 `GpuCompute.createFence` 获取。工厂对已关闭命令缓冲返回 `Unavailable`、跨设备返回 `InvalidArgument`、已提交命令缓冲返回 `InvalidArgument`。

---

## 6. 字段表

见 §3；字段私有。不暴露后端 fence/semaphore 句柄。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `fenceId` | 不透明句柄 | 无 | `Long` | 无 | O(1)；不持久 |
| `device` | 所属设备 | 无 | `GpuDevice` | 无 | 非拥有引用 |
| `commandBuffer` | 绑定的命令缓冲 | 无 | `GpuCommandBuffer` | 无 | 非拥有引用 |
| `wait` | 等待信号 | `Context context, Long timeoutMillis` | `Result<Unit, Error>` | `Timeout`/`InvalidArgument`/`Unavailable`/`Cancelled` | 信号 = Ok(unit)；超时 = Timeout |
| `isSignaled` | 非阻塞查询 | 无 | `Result<Bool, Error>` | `Unavailable` | 不缓存 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） | O(1)；幂等 |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 | O(1) |

说明：

- `fenceId()` 返回不透明 `Long`；关闭后仍返回原值；不得当作跨进程或持久 ID。
- `device()`/`commandBuffer()` 返回非拥有引用；fence 不关闭它们。
- `wait`：
  - `context == null` → panic；fence 关闭或设备关闭 → `Unavailable`。
  - `timeoutMillis < 0` → `InvalidArgument`。
  - `timeoutMillis == 0` → 非阻塞轮询；未信号立即返回 `Timeout`，已信号返回 `Ok(unit)`。
  - `timeoutMillis > 0` → 最多等待该毫秒数；未信号返回 `Timeout`；信号返回 `Ok(unit)`。
  - 取消 → `Cancelled`；适配器必须支持协作取消，不得无限阻塞忽略 `Context`。
  - `Timeout` 不改变 fence 状态；可再次 `wait`；需要布尔轮询用 `isSignaled`。
- `isSignaled`：
  - fence 关闭或设备关闭 → `Unavailable`；否则返回原生查询结果。
  - 不缓存；每次调用都查询原生状态。
  - 提交前返回 false；不是错误。
- `close`：第一次调用标记关闭；设备仍打开时调用原生关闭；设备已关闭时跳过；后续调用返回 `Ok(unit)`。关闭失败只作为诊断返回 `Io`，不改变“已关闭”状态。
- `isOpen()` 不触碰原生句柄。
- 不提供 `reset`/`signal`/`waitAny`/`waitAll`；这些是 X。
- 不提供 `describe`/`equals`/`copy`；fence 是资源，不是值对象。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- 一次性完成栅栏；
- 超时映射/可取消等待；
- `Context`/`Result`；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、Bool、Result；
- 运行时/适配器：
  - `gpuFenceCreateRaw(Context context, GpuDevice device, GpuCommandBuffer commandBuffer) -> Result<Long, Error>`；
  - `gpuFenceWaitRaw(Context context, Long fenceHandle, Long timeoutMillis) -> Result<Bool, Error>`；
  - `gpuFenceIsSignaledRaw(Long fenceHandle) -> Result<Bool, Error>`；
  - `gpuFenceCloseRaw(Long fenceHandle) -> Result<Unit, Error>`；
- 原生 fence 句柄必须 > 0；0/负数视为适配器内部错误（工厂返回 `Internal`，构造器 panic）；
- `gpuFenceWaitRaw` 返回 true = signaled、false = timeout；`wait` 将 false 映射为 `Timeout`；取消返回 `Cancelled`；必须检查 `Context`；
- 适配器解析 `GpuDevice`/`GpuCommandBuffer` 的内部句柄；公共 API 不暴露这些句柄；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`cancelledError`、`GpuDevice`、`GpuCommandBuffer`。

---

## 10. 依赖的特性/接口/类

[`GpuCompute`](GpuCompute.md)、[`GpuCommandBuffer`](GpuCommandBuffer.md)、[`GpuDevice`](../os/gpu/GpuDevice.md)、[`GpuPipeline`](GpuPipeline.md)、[`GpuBuffer`](GpuBuffer.md)、`Context`、`Error`。

---

## 11. 所有权与并发

引用语义；fence 由调用方拥有；设备与命令缓冲都是非拥有引用。

非线程安全：`wait`/`isSignaled`/`close` 不得并发；调用方必须串行化。`close()` 幂等指重复调用安全，不承诺并发 close 安全。

fence 一次性；不得用于第二个命令缓冲或第二次提交。提交后，fence 必须保持打开直到 `wait` 返回 `Ok(unit)` 或调用方决定放弃；提前关闭可能丢失完成信号。

无 `equals`/`copy`；`==` 是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：

- 创建命令缓冲 → 录制 → `end`；创建 fence；`submit(fence)`；`fence.wait(context, 1000)` 返回 `Ok(unit)` 后读取/关闭 buffer。
- 需要非阻塞轮询时用 `isSignaled`；`wait(0)` 未信号会返回 `Timeout`，不是 `Ok(false)`。
- 取消后关闭 fence；GPU 工作可能仍在执行，调用方按设备生命周期处理。
- 提交后等 fence signaled，再关闭命令缓冲与它引用的 GPU 资源，最后关闭 fence。

反例：

- 提交前 `wait` 并期望马上 `Ok(unit)`。
- 创建 fence 后不传给 `submit`，却等待它。
- 用命令缓冲 A 的 fence 提交命令缓冲 B。
- 同一个 fence 重复用于多次提交。
- `timeoutMillis < 0`；把 `Timeout` 当取消或致命错误；把 `isSignaled` 的 false 当错误。
- fence 未信号就关闭 pipeline/buffer。
- 在 fence 关闭后继续 `wait`/`isSignaled`。
- 把 fence 当可重置/时间线栅栏。

---

## 13. 测试/场景义务

- 构造非法 handle/device/commandBuffer panic；命令缓冲关闭/已提交/跨设备 panic。
- 工厂：命令缓冲关闭 `Unavailable`；跨设备 `InvalidArgument`；已提交 `InvalidArgument`；取消 `Cancelled`；句柄错误 `Internal`。
- 创建后 `isSignaled` false；`wait(0)` 返回 `Timeout`；`wait(短超时)` 返回 `Timeout`。
- 提交后 fence 最终 signaled；`wait` 返回 `Ok(unit)`；`isSignaled` true；可多次 `wait`。
- `timeoutMillis` 0/正/负；取消；设备关闭；fence 关闭。
- 提交后等 fence signaled 再关闭命令缓冲；fence 关闭后 `wait`/`isSignaled` 返回 `Unavailable`。
- 多个 fence 并存；一个提交一个 fence；未传入的 fence 不信号。
- `close` 幂等；设备先关时 `close` 返回 `Ok(unit)`；关闭后不调用原生原语。
- 与 `GpuCommandBuffer.submit`、`GpuBuffer.read`、资源关闭顺序组合。
- 并发误用不在保证范围；测试只验证串行契约。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class GpuFence {
    final Long _handle
    final GpuDevice _device
    final GpuCommandBuffer _commandBuffer
    Bool _open

    GpuFence(Long handle, GpuDevice device, GpuCommandBuffer commandBuffer) {
        if handle <= 0 || device == null || commandBuffer == null {
            throw "GpuFence: invalid field"
        }
        if !commandBuffer.isOpen() {
            throw "GpuFence: closed command buffer"
        }
        if commandBuffer.isSubmitted() {
            throw "GpuFence: command buffer already submitted"
        }
        if commandBuffer.device() != device {
            throw "GpuFence: command buffer from another device"
        }
        _handle = handle
        _device = device
        _commandBuffer = commandBuffer
        _open = true
    }

    Long fenceId() { return _handle }
    GpuDevice device() { return _device }
    GpuCommandBuffer commandBuffer() { return _commandBuffer }
    Bool isOpen() { return _open }

    Result<Unit, Error> wait(Context context, Long timeoutMillis) {
        if context == null { throw "GpuFence.wait: null context" }
        if !_open { return Err(unavailableError("gpu fence")) }
        if !_device.isOpen() { return Err(unavailableError("gpu device")) }
        if timeoutMillis < 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "negative timeout"))
        }
        if context.isCancelled() {
            return Err(cancelledError("gpu fence wait"))
        }
        Result<Bool, Error> signaled = gpuFenceWaitRaw(
            context, _handle, timeoutMillis)
        if signaled.isErr() { return Err(signaled.error()) }
        if !signaled.value() {
            return Err(new BasicError(ErrorKind.Timeout,
                "gpu fence wait timed out"))
        }
        return Ok(unit)
    }

    Result<Bool, Error> isSignaled() {
        if !_open { return Err(unavailableError("gpu fence")) }
        if !_device.isOpen() { return Err(unavailableError("gpu device")) }
        return gpuFenceIsSignaledRaw(_handle)
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        if !_device.isOpen() { return Ok(unit) }
        return gpuFenceCloseRaw(_handle)
    }
}
```
