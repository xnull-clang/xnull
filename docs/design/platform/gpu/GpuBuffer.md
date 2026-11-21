# `GpuBuffer`

| 项 | 值 |
| --- | --- |
| 类型 | `class GpuBuffer` |
| 包 | `xdk.gpu` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Bytes`、`GpuDevice`、`GpuBufferUsage`、`Error` |

---

## 1. 定位

已创建的 GPU 计算缓冲区不透明句柄：逻辑大小、使用方式、CPU 写入/读取、关闭、是否可用。

不做：

- 显存分配策略、内存类型、驻留/驱逐、精确预算；
- 持久映射、裸指针、映射地址、文件描述符；
- 纹理/图像/采样器/交换链；
- 顶点/索引缓冲（X 渲染）；
- GPU 命令提交或隐式同步。

---

## 2. 设计逻辑

- 由 `GpuCompute.createBuffer(context, device, usage, sizeBytes)` 创建；构造器主要供宿主/测试使用。
- `_handle` 是 `Long` 不透明句柄；不暴露映射地址、后端指针或 fd。
- `_sizeBytes` 是调用方请求的逻辑大小，必须 > 0；适配器可以向上取整原生分配，但 `sizeBytes()` 始终返回逻辑大小，读写边界按逻辑大小计算。
- `_usage` 在创建时固定；只影响 GPU 绑定兼容性，不限制 CPU `write`/`read`。
- `write` 从偏移 0 写整个 `source`；基线没有“带偏移的部分写”。`read` 从 `offset` 读入 `target`，必须完整填充。
- `write`/`read` 是宿主拷贝，不插入 GPU 屏障、不等待在飞的 GPU 工作。调用方必须先用 `GpuFence.wait` 或其它同步手段确认 buffer 不再被使用。
- 关闭后纯元数据（ID、设备、大小、usage、isOpen）仍可读，`write`/`read` 返回 `Unavailable`。
- 设备先关闭时，buffer `close()` 标记关闭后跳过原生关闭，视为设备回收，返回 `Ok(unit)`。
- 无 `equals`/`copy`；buffer 是资源，不是值对象。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | > 0；不透明句柄 |
| `_device` | `GpuDevice` | final | 非 null；非拥有引用 |
| `_usage` | `GpuBufferUsage` | final | 非 null；创建后固定 |
| `_sizeBytes` | `Long` | final | > 0；逻辑大小 |
| `_open` | `Bool` | 内部 | 构造后 true；close 后 false |

不变量：

- `handle > 0`；`device`/`usage` 非 null；`sizeBytes > 0`。
- usage 创建后不可变；不存在“临时改 usage”的路径。
- 构造后 `open = true`；`close()` 后 `open = false`；close 幂等。
- 关闭后不再调用任何原生 buffer 原语。
- 原生分配可能大于逻辑大小，但所有公开边界只使用 `_sizeBytes`。
- 不持有裸指针或映射地址；CPU 读写通过拷贝完成。

---

## 4. 生命周期

由 `GpuCompute.createBuffer` 创建；调用方拥有并必须 `close()`；close 幂等；无 `deinit` 依赖。

设备必须比 buffer 活得久。若设备先关闭：

- `write`/`read` 返回 `Unavailable`；
- `close()` 标记关闭后跳过原生关闭，返回 `Ok(unit)`；
- ID/设备/大小/usage/isOpen 仍可读；设备关闭不会自动把 buffer 标记为 closed，`isOpen()` 仍为 true 直到调用方 `close()`。

提交给 GPU 后，buffer 必须保持打开，直到关联的 `GpuFence` signaled；提前关闭可能造成 GPU 使用已释放资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `GpuBuffer(Long handle, GpuDevice device, GpuBufferUsage usage, Long sizeBytes)` | handle、device、usage、sizeBytes | handle > 0；device/usage 非 null；sizeBytes > 0 | 非法 → panic |

构造器主要供宿主/测试使用；业务代码通过 `GpuCompute.createBuffer` 获取。工厂对 `sizeBytes <= 0` 返回 `InvalidArgument`，不依赖构造器 panic。

---

## 6. 字段表

见 §3；字段私有。不暴露原生指针、映射地址、fd 或后端分配句柄。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `bufferId` | 不透明句柄 | 无 | `Long` | 无 | O(1)；不持久、不跨进程 |
| `device` | 所属设备 | 无 | `GpuDevice` | 无 | 非拥有引用 |
| `sizeBytes` | 逻辑大小 | 无 | `Long` | 无 | O(1) |
| `usage` | 使用方式 | 无 | `GpuBufferUsage` | 无 | O(1)；固定 |
| `write` | CPU 写入 | `Context context, Bytes source` | `Result<Unit, Error>` | `InvalidArgument`/`Unavailable`/`Cancelled`/`Busy`/`Io` | O(n) 拷贝；阻塞；从偏移 0 写 |
| `read` | CPU 读取 | `Context context, Long offset, Bytes target` | `Result<Unit, Error>` | `InvalidArgument`/`Unavailable`/`Cancelled`/`Busy`/`Io` | O(n) 拷贝；阻塞；完整填充 target |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） | O(1)；幂等 |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 | O(1) |

说明：

- `bufferId()` 返回不透明 `Long`，仅用于诊断/关联；关闭后仍返回原值；不得当作跨进程或持久 ID。
- `device()` 返回非拥有引用；buffer 不关闭设备。
- `sizeBytes()` 返回创建时请求的逻辑大小，不等于适配器实际分配大小。
- `usage()` 返回创建时固定的 usage；关闭后仍可读。
- `write`：
  - `context == null` 或 `source == null` → panic。
  - buffer 关闭或设备关闭 → `Unavailable`。
  - `source.length() > sizeBytes` → `InvalidArgument`；`source.length() == 0` → `Ok(unit)`，不调用原生。
  - 取消 → `Cancelled`；适配器可能在原生拷贝中返回 `Busy`/`Io`。
  - 写入从偏移 0 开始；没有 offset 参数；基线不支持带偏移的部分写；`source` 之后的字节保持不变。
  - 失败时内容可能部分写入；不保证原子性。
  - 不插入 GPU 屏障；不得与在飞 GPU 使用并发。
- `read`：
  - `context == null` 或 `target == null` → panic。
  - `offset < 0` 或 `offset > sizeBytes` → `InvalidArgument`。
  - `target.length() > sizeBytes - offset` → `InvalidArgument`；`target.length() == 0` → `Ok(unit)`，不调用原生。
  - 成功时 `target` 被完整填充；不返回部分读取。
  - 取消 → `Cancelled`；适配器可能返回 `Busy`/`Io`。
  - 失败时 `target` 内容未定义；不保证部分填充。
  - 不插入 GPU 屏障；必须在 fence signaled 后读取，否则内容未定义。
- `close`：第一次调用标记关闭；设备仍打开时调用原生关闭；设备已关闭时跳过；后续调用返回 `Ok(unit)`。关闭失败只作为诊断返回 `Io`，不改变“已关闭”状态。
- `isOpen()` 不触碰原生句柄。
- 不提供 `describe`/`equals`/`copy`；buffer 是资源，不是值对象。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- 逻辑大小与原生分配大小分离；
- CPU 拷贝式读写；
- 边界检查；
- `Context`/`Result`；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、Int、Bool、Bytes、Result；
- 辅助：`toLong`（Int → Long，用于比较 `Bytes.length()` 与逻辑大小）；
- 运行时/适配器：
  - `gpuBufferCreateRaw(Context context, GpuDevice device, GpuBufferUsage usage, Long sizeBytes) -> Result<Long, Error>`；
  - `gpuBufferWriteRaw(Context context, Long bufferHandle, Bytes source) -> Result<Unit, Error>`；
  - `gpuBufferReadRaw(Context context, Long bufferHandle, Long offset, Bytes target) -> Result<Unit, Error>`；
  - `gpuBufferCloseRaw(Long bufferHandle) -> Result<Unit, Error>`；
- 原生 buffer 句柄必须 > 0；0/负数视为适配器内部错误（工厂返回 `Internal`，构造器 panic）；
- 适配器解析 `GpuDevice` 的内部设备句柄；公共 API 不暴露该句柄；
- 接口：`Context`、`Bytes`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`cancelledError`、`GpuDevice`、`GpuBufferUsage`、`GpuFence`。

---

## 10. 依赖的特性/接口/类

[`GpuCompute`](GpuCompute.md)、[`GpuBufferUsage`](GpuBufferUsage.md)、[`GpuDevice`](../os/gpu/GpuDevice.md)、[`GpuPipeline`](GpuPipeline.md)、[`GpuCommandBuffer`](GpuCommandBuffer.md)、[`GpuFence`](GpuFence.md)、`Context`、`Bytes`、`Error`。

---

## 11. 所有权与并发

引用语义；buffer 由调用方拥有；设备是非拥有引用；buffer 不反向拥有设备。

非线程安全：`write`/`read`/`close` 不得并发；调用方必须串行化。`close()` 幂等指重复调用安全，不承诺并发 close 安全。

CPU 读写不得与在飞 GPU 使用并发；提交后必须等 fence signaled 再 `read` 或关闭 buffer。若多个命令缓冲引用同一 buffer，调用方必须等所有相关提交完成。

无 `equals`/`copy`；`==` 是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：

- `GpuCompute.createBuffer(context, device, GpuBufferUsage.ReadWrite, 4096)`；`write` 输入数据；绑定到 `Read` 或 `ReadWrite` 管线槽；提交后 `fence.wait`；再 `read`。
- 写入前检查 `source.length()`；读取前检查 `offset + target.length()`；不越过逻辑大小。
- 提交后等 fence signaled，再关闭 command buffer、pipeline/program/buffer。

反例：

- 在 GPU 仍在读取 buffer 时调用 `write` 或 `close`。
- 提交后没有 fence 就 `read`，并把结果当归一化数据。
- `read` 的 target 大于剩余范围却期望截断。
- 认为 `sizeBytes()` 等于原生分配大小，按它计算对齐或越界写入。
- 设备关闭后继续 `write`/`read`。
- 把 `bufferId()` 当持久 ID 写入配置文件。
- 关闭后重试 `close` 并期望再次调用原生。

---

## 13. 测试/场景义务

- 构造非法 handle/device/usage/size panic；工厂 `sizeBytes <= 0` 返回 `InvalidArgument`。
- 创建不同 usage/size 的 buffer；`sizeBytes`/`usage`/`device` 正确；usage 不可变。
- `write`：精确大小、较小大小、空 source、超大 source；offset 0 语义；内容可被后续 `read` 观察。
- `read`：offset 0、中间、末尾、空 target、越界 offset、越界 target；target 完整填充。
- 关闭后 `write`/`read` 返回 `Unavailable`；纯元数据仍可读。
- 设备关闭后 `write`/`read` 返回 `Unavailable`；`close()` 返回 `Ok(unit)`。
- `Context` 取消：`write`/`read` 返回 `Cancelled`；不产生部分写入/读取承诺。
- `close` 幂等；关闭失败只诊断；关闭后不调用原生原语。
- 大 buffer、跨页/对齐、后端拒绝分配（`OutOfMemory`/`Unsupported`）；容器/WASM 可见显存受限。
- 与 `GpuFence` 组合：未 signaled 时读取是调用方错误；signaled 后读取成功。
- 并发误用不在保证范围；测试只验证串行契约。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class GpuBuffer {
    final Long _handle
    final GpuDevice _device
    final GpuBufferUsage _usage
    final Long _sizeBytes
    Bool _open

    GpuBuffer(Long handle, GpuDevice device, GpuBufferUsage usage,
              Long sizeBytes) {
        if handle <= 0 || device == null || usage == null || sizeBytes <= 0 {
            throw "GpuBuffer: invalid field"
        }
        _handle = handle
        _device = device
        _usage = usage
        _sizeBytes = sizeBytes
        _open = true
    }

    Long bufferId() { return _handle }
    GpuDevice device() { return _device }
    Long sizeBytes() { return _sizeBytes }
    GpuBufferUsage usage() { return _usage }
    Bool isOpen() { return _open }

    Result<Unit, Error> write(Context context, Bytes source) {
        if context == null || source == null {
            throw "GpuBuffer.write: null argument"
        }
        if !_open { return Err(unavailableError("gpu buffer")) }
        if !_device.isOpen() { return Err(unavailableError("gpu device")) }
        if toLong(source.length()) > _sizeBytes {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "source exceeds buffer size"))
        }
        if source.length() == 0 { return Ok(unit) }
        if context.isCancelled() {
            return Err(cancelledError("gpu buffer write"))
        }
        return gpuBufferWriteRaw(context, _handle, source)
    }

    Result<Unit, Error> read(Context context, Long offset, Bytes target) {
        if context == null || target == null {
            throw "GpuBuffer.read: null argument"
        }
        if !_open { return Err(unavailableError("gpu buffer")) }
        if !_device.isOpen() { return Err(unavailableError("gpu device")) }
        if offset < 0 || offset > _sizeBytes {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "offset out of range"))
        }
        if toLong(target.length()) > _sizeBytes - offset {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "target exceeds buffer range"))
        }
        if target.length() == 0 { return Ok(unit) }
        if context.isCancelled() {
            return Err(cancelledError("gpu buffer read"))
        }
        return gpuBufferReadRaw(context, _handle, offset, target)
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        if !_device.isOpen() { return Ok(unit) }
        return gpuBufferCloseRaw(_handle)
    }
}
```
