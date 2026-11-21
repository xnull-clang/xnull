# `GpuDevice`

| 项 | 值 |
| --- | --- |
| 类型 | `class GpuDevice` |
| 包 | `xdk.os.gpu` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`GpuBackend`、`GpuMemoryInfo`、`GpuQueue`、`GpuQueueKind` |

---

## 1. 定位

已打开的 GPU 设备句柄：适配器 ID、后端、显存快照、队列创建、关闭、是否可用。

不做：适配器枚举（`GpuAdapter`）、着色器/渲染管线/命令缓冲/计算内核、显存分配、命令提交/同步。设备只表示一个已打开的生命周期句柄。

---

## 2. 设计逻辑

- 由 `GpuAdapter.open(context)` 创建；构造器主要供宿主/测试使用。
- `_handle` 是 `Long` 不透明句柄；不暴露后端设备指针/文件描述符。
- `adapterId` 与 `GpuAdapter.id()` 一致；`backend` 在打开时固定。
- 打开后可用；`close()` 幂等；关闭后 `memoryInfo`/`createQueue` 返回 `Unavailable`，`adapterId`/`backend`/`isOpen` 仍可读。
- 设备持有已创建的 `GpuQueue`；`close()` 先关闭全部队列，再关闭设备句柄。
- 队列可以独立关闭；设备关闭使队列失效；队列关闭后再次关闭返回 `Ok(unit)`。
- `memoryInfo` 是值快照；`0` 表示未知/不支持；不用于精确分配。
- `createQueue` 显式请求 kind；`ComputeOnly` + `Graphics` 返回 `Unsupported`；计算队列受 `GpuCompute` 能力门控，缺失由适配器/原生层返回 `Unsupported`；其它后端能力差异同样显式失败。
- 不提供命令提交/同步；这些是 X。
- 非线程安全；调用方必须串行化 `memoryInfo`/`createQueue`/`close`，或确保关闭时没有其它调用。
- 无全局注册表；设备由调用方持有并关闭。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | >0；不透明句柄 |
| `_adapterId` | `String` | final | 非空；与适配器一致 |
| `_backend` | `GpuBackend` | final | 非 null |
| `_queues` | `List<GpuQueue>` | final | 已创建队列引用；内部注册表 |
| `_open` | `Bool` | 内部 | 是否可用 |

不变量：handle>0；adapterId 非空；backend 非 null；`_queues` 非 null；队列都由本设备创建；close 后 open=false 且队列全部关闭；close 幂等。

---

## 4. 生命周期

由 `GpuAdapter.open(context)` 创建；调用方持有；`close()` 关闭队列与设备；close 幂等；无 `deinit` 依赖。
关闭后只允许 `adapterId`/`backend`/`isOpen`/`close`；其余方法返回 `Unavailable`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `GpuDevice(Long handle, String adapterId, GpuBackend backend)` | handle、adapterId、backend | handle>0；adapterId 非空；backend 非 null | 非法 → panic |

构造器创建空队列注册表并置为 open；业务代码通过 `GpuAdapter.open(context)` 获取。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `adapterId` | 适配器 ID | 无 | `String` | 无 |
| `backend` | 后端 | 无 | `GpuBackend` | 无 |
| `memoryInfo` | 显存快照 | `Context context` | `Result<GpuMemoryInfo, Error>` | `Unavailable`/`Cancelled` |
| `createQueue` | 创建队列 | `Context context, GpuQueueKind kind` | `Result<GpuQueue, Error>` | `Unavailable`/`Unsupported`/`Cancelled` |
| `close` | 关闭设备与队列 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

说明：

- `adapterId`/`backend` 是纯读取；关闭后仍返回打开时的值。
- `memoryInfo`：`context == null` panic；关闭后返回 `Unavailable`；成功返回独立值快照，设备关闭后快照仍可读。
- `createQueue`：`context == null` 或 `kind == null` panic；关闭后返回 `Unavailable`；`ComputeOnly` + `Graphics` 返回 `Unsupported`；`GpuCompute` 缺失时由适配器/原生层返回 `Unsupported`；原生创建也可能返回 `Unsupported`；成功后队列登记到设备。
- 同一 kind 多次创建由实现决定；不得假设单例或固定队列数。
- `close`：第一次调用标记关闭，关闭全部队列，再关闭设备；所有资源都尝试关闭，单个队列失败不阻止设备关闭；返回设备 `Io`（若有），否则第一个队列 `Io`；后续调用返回 `Ok(unit)`。
- `isOpen` 不触碰原生句柄；设备关闭后为 false。
- 不提供 `describe`/`equals`/`copy`；设备是资源，不是值对象。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- 队列注册表；
- `Context`/`Result`；
- 幂等关闭；
- 关闭错误聚合。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、String、List、Bool、Result；
- 运行时/适配器：
  - `gpuMemoryInfoRaw(Context context, Long handle) -> Result<GpuMemoryInfo, Error>`；
  - `gpuQueueCreateRaw(Context context, Long handle, GpuQueueKind kind) -> Result<Long, Error>`；
  - `gpuDeviceCloseRaw(Long handle) -> Result<Unit, Error>`；
- 原生设备/队列句柄必须 >0；0/负数视为适配器内部错误（构造器 panic）；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`GpuBackend`、`GpuMemoryInfo`、`GpuQueue`、`GpuQueueKind`。

---

## 10. 依赖的特性/接口/类

`GpuAdapter`、`GpuBackend`、`GpuMemoryInfo`、`GpuQueue`、`GpuQueueKind`、`OsHost`、`Context`、`Error`。

---

## 11. 所有权与并发

引用语义；设备由调用方持有；设备持有已创建队列并在 close 时关闭它们；队列可独立 close；无循环引用。
非线程安全：`memoryInfo`/`createQueue`/`close` 不得并发；调用方需串行化，或确保 close 时没有其它调用。`close` 幂等指重复调用安全，不承诺并发 close 安全。
无 `equals`/`copy`；不推荐作 `Map` 键；关闭后不得再用设备。

---

## 12. 示例与反例

正确：`adapter.open(context)` 成功后读取 `adapterId()`/`backend()`；用 `memoryInfo(context)` 记录诊断；创建 `Compute`/`Transfer` 队列；先关闭队列，再关闭设备。  
反例：close 后继续 `memoryInfo`/`createQueue`；在 `ComputeOnly` 后端请求 `Graphics`；假设所有 kind 都支持；把 `memoryInfo` 的 0 当零显存；设备 close 后继续使用队列；打开多个设备却不关闭；把 `close()` 的重试当恢复手段。

---

## 13. 测试/场景义务

打开/关闭；`adapterId`/`backend`；`memoryInfo` 成功/`Unavailable`/`Cancelled`；三种队列 kind；
`ComputeOnly` + `Graphics` 返回 `Unsupported`；不支持的后端/队列返回 `Unsupported`；
设备 close 关闭全部队列；队列先 close 再设备 close；设备 close 后队列 close 返回 `Ok(unit)`；
close 幂等；关闭后 `memoryInfo`/`createQueue` 返回 `Unavailable`；null context/kind panic；
多次 open 独立；队列 close 失败聚合；close 失败只诊断；关闭后不触碰原生句柄。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class GpuDevice {
    final Long _handle
    final String _adapterId
    final GpuBackend _backend
    final List<GpuQueue> _queues
    Bool _open

    GpuDevice(Long handle, String adapterId, GpuBackend backend) {
        if handle <= 0 || adapterId == null || adapterId == "" || backend == null {
            throw "GpuDevice: invalid field"
        }
        _handle = handle
        _adapterId = adapterId
        _backend = backend
        _queues = []
        _open = true
    }

    String adapterId() { return _adapterId }
    GpuBackend backend() { return _backend }
    Bool isOpen() { return _open }

    Result<GpuMemoryInfo, Error> memoryInfo(Context context) {
        if context == null { throw "GpuDevice.memoryInfo: null context" }
        if !_open { return Err(unavailableError("gpu device")) }
        return gpuMemoryInfoRaw(context, _handle)
    }

    Result<GpuQueue, Error> createQueue(Context context, GpuQueueKind kind) {
        if context == null || kind == null {
            throw "GpuDevice.createQueue: null argument"
        }
        if !_open { return Err(unavailableError("gpu device")) }
        if _backend == GpuBackend.ComputeOnly && kind == GpuQueueKind.Graphics {
            return Err(new BasicError(ErrorKind.Unsupported,
                "graphics queue on compute-only backend"))
        }
        Result<Long, Error> created = gpuQueueCreateRaw(context, _handle, kind)
        if created.isErr() { return Err(created.error()) }
        GpuQueue queue = new GpuQueue(created.value(), kind)
        _queues.push(queue)
        return Ok(queue)
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
        Result<Unit, Error> deviceResult = gpuDeviceCloseRaw(_handle)
        if deviceResult.isErr() { return Err(deviceResult.error()) }
        if hasError { return firstError }
        return Ok(unit)
    }
}
```
