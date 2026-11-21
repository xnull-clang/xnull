# `GpuProgram`

| 项 | 值 |
| --- | --- |
| 类型 | `class GpuProgram` |
| 包 | `xdk.gpu` |
| 稳定性 | `preview` |
| 依赖 | `GpuDevice`、`GpuProgramKind`、`GpuBackend`、`Error` |

---

## 1. 定位

已加载的 GPU 程序不透明句柄：程序阶段、后端、关闭、是否可用。

基线只支持计算程序（`GpuProgramKind.Compute`）；`Vertex`/`Fragment` 是 X 渲染。

不做：

- 着色器语言、源码解析、编译、链接、反射；
- 入口点选择、工作组大小、特化常量；
- 绑定布局推导、纹理/采样器/渲染状态；
- 程序代码的读取/导出；
- 设备枚举/队列创建/命令提交。

---

## 2. 设计逻辑

- 由 `GpuCompute.createProgram(context, device, code, programKind)` 创建；构造器主要供宿主/测试使用。
- `_handle` 是 `Long` 不透明句柄；不暴露后端 program/module/library 指针。
- `_programKind` 在创建时固定；基线工厂只接受 `Compute`；`Vertex`/`Fragment` 返回 `Unsupported`。
- `_backend` 来自设备并在创建时固定；构造器要求它与 `device.backend()` 一致，防止跨后端混用。
- `code` 是 `Bytes`，内容由后端定义；本包不解释、不编译、不保留源码。程序创建后不再提供代码访问器。
- 程序不拥有设备；设备必须比程序活得久。程序先关闭时，已创建的管线不可再用；调用方必须先关闭管线再关闭程序。
- 关闭后纯元数据（ID、设备、kind、backend、isOpen）仍可读；GPU 操作（管线创建/绑定）返回 `Unavailable`。
- 设备先关闭时，`close()` 标记关闭后跳过原生关闭，视为设备回收，返回 `Ok(unit)`。
- 无 `equals`/`copy`；程序是资源，不是值对象。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | > 0；不透明句柄 |
| `_device` | `GpuDevice` | final | 非 null；非拥有引用 |
| `_programKind` | `GpuProgramKind` | final | 非 null；创建后固定 |
| `_backend` | `GpuBackend` | final | 非 null；等于 `device.backend()` |
| `_open` | `Bool` | 内部 | 构造后 true；close 后 false |

不变量：

- `handle > 0`；`device`/`programKind`/`backend` 非 null。
- `backend == device.backend()`；不允许跨后端构造。
- program kind 创建后不可变；不存在切换阶段的路径。
- 构造后 `open = true`；`close()` 后 `open = false`；close 幂等。
- 关闭后不再调用任何原生 program 原语。
- 不持有源码/字节码副本；`code` 只在创建调用期间使用。
- 不拥有设备；不关闭管线；管线生命周期由调用方管理。

---

## 4. 生命周期

由 `GpuCompute.createProgram` 创建；调用方拥有并必须 `close()`；close 幂等；无 `deinit` 依赖。

设备必须比程序活得久。若设备先关闭：

- 后续管线创建/绑定返回 `Unavailable`；
- `close()` 标记关闭后跳过原生关闭，返回 `Ok(unit)`；
- ID/设备/kind/backend/isOpen 仍可读；设备关闭不会自动把 program 标记为 closed，`isOpen()` 仍为 true 直到调用方 `close()`。

程序创建的管线借用程序；关闭顺序必须是管线 → 程序。程序先关闭会使管线不可用，命令缓冲提交返回 `Unavailable`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `GpuProgram(Long handle, GpuDevice device, GpuProgramKind programKind, GpuBackend backend)` | handle、device、programKind、backend | handle > 0；device/programKind/backend 非 null；backend 与设备一致 | 非法 → panic |

构造器主要供宿主/测试使用；业务代码通过 `GpuCompute.createProgram` 获取。构造器允许保存 `Vertex`/`Fragment` 以支持未来兼容，但不构成基线支持；公开工厂只接受 `Compute`。

---

## 6. 字段表

见 §3；字段私有。不暴露后端 program/module/library 指针、源码或反射信息。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `programId` | 不透明句柄 | 无 | `Long` | 无 | O(1)；不持久 |
| `device` | 所属设备 | 无 | `GpuDevice` | 无 | 非拥有引用 |
| `programKind` | 程序阶段 | 无 | `GpuProgramKind` | 无 | O(1)；固定 |
| `backend` | 后端 | 无 | `GpuBackend` | 无 | O(1)；固定 |
| `close` | 关闭程序 | 无 | `Result<Unit, Error>` | `Io`（诊断） | O(1)；幂等 |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 | O(1) |

说明：

- `programId()` 返回不透明 `Long`，仅用于诊断/关联；关闭后仍返回原值；不得当作跨进程或持久 ID。
- `device()` 返回非拥有引用；程序不关闭设备。
- `programKind()`/`backend()` 是纯读取；关闭后仍返回创建时的值。
- `close()`：第一次调用标记关闭；设备仍打开时调用原生关闭；设备已关闭时跳过；后续调用返回 `Ok(unit)`。关闭失败只作为诊断返回 `Io`，不改变“已关闭”状态。
- `isOpen()` 不触碰原生句柄。
- 不提供 `code()`/`entryPoint()`/`workgroupSize()`/`reflect()`；这些属于 X 或后端私有。
- 不提供 `describe`/`equals`/`copy`；程序是资源，不是值对象。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- 后端固定元数据；
- 不透明 `Bytes` 代码输入；
- `Context`/`Result`；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、Bool、Bytes、Result；
- 运行时/适配器：
  - `gpuProgramCreateRaw(Context context, GpuDevice device, Bytes code, GpuProgramKind programKind) -> Result<Long, Error>`；
  - `gpuProgramCloseRaw(Long programHandle) -> Result<Unit, Error>`；
- 原生 program 句柄必须 > 0；0/负数视为适配器内部错误（工厂返回 `Internal`，构造器 panic）；
- 适配器解析 `GpuDevice` 的内部设备句柄；公共 API 不暴露该句柄；
- 适配器负责代码格式识别/加载/编译产物校验；本包不提供编译器；
- 接口：`Context`、`Bytes`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`GpuDevice`、`GpuProgramKind`、`GpuBackend`。

---

## 10. 依赖的特性/接口/类

[`GpuCompute`](GpuCompute.md)、[`GpuProgramKind`](GpuProgramKind.md)、[`GpuBackend`](../os/gpu/GpuBackend.md)、[`GpuDevice`](../os/gpu/GpuDevice.md)、[`GpuPipeline`](GpuPipeline.md)、[`GpuCommandBuffer`](GpuCommandBuffer.md)、`Bytes`、`Error`。

---

## 11. 所有权与并发

引用语义；程序由调用方拥有；设备是非拥有引用；管线借用程序。

非线程安全：`close` 与管线创建/绑定不得并发；调用方必须串行化。`close()` 幂等指重复调用安全，不承诺并发 close 安全。

关闭顺序：等待 fence → 命令缓冲 → 管线 → 程序；程序关闭后不得再创建/使用管线。提交后，程序必须保持打开直到 fence signaled。

无 `equals`/`copy`；`==` 是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：

- `GpuCompute.createProgram(context, device, computeCode, GpuProgramKind.Compute)`；用返回的程序创建计算管线；关闭管线后再关闭程序。
- 诊断日志记录 `programKind()` 与 `backend()`；不记录代码内容。
- 对 `Vertex`/`Fragment` 直接按 X 处理，不调用 `createProgram`。

反例：

- 把着色器源码直接传给 `createProgram` 并期望本包编译。
- 用 `Vertex`/`Fragment` 创建计算管线。
- 程序先 close，再 `GpuCompute.createPipeline` 或 `bindPipeline`。
- 设备关闭后继续使用程序。
- 把 `programId()` 当持久资源 ID。
- 在程序关闭后继续使用其管线并期望 `Unavailable` 之外的行为。

---

## 13. 测试/场景义务

- 构造非法 handle/device/kind/backend panic；backend 与设备不一致 panic。
- `GpuCompute.createProgram`：Compute 成功；Vertex/Fragment 返回 `Unsupported`；空代码 `InvalidArgument`；设备关闭 `Unavailable`；取消 `Cancelled`；后端不支持的代码格式返回 `Unsupported`。
- `programId`/`device`/`programKind`/`backend` 正确；关闭后元数据仍可读。
- `close` 幂等；设备先关时 `close` 返回 `Ok(unit)`；关闭后不调用原生原语。
- 关闭顺序：管线先关、程序后关成功；程序先关后管线绑定/提交返回 `Unavailable`。
- 同一程序创建多个管线；多个程序并存；后端 `Unknown`/`ComputeOnly` 的行为由原生返回。
- 不保留源码：创建后修改输入 `Bytes` 不影响程序。
- 并发误用不在保证范围；测试只验证串行契约。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class GpuProgram {
    final Long _handle
    final GpuDevice _device
    final GpuProgramKind _programKind
    final GpuBackend _backend
    Bool _open

    GpuProgram(Long handle, GpuDevice device, GpuProgramKind programKind,
               GpuBackend backend) {
        if handle <= 0 || device == null || programKind == null
            || backend == null {
            throw "GpuProgram: invalid field"
        }
        if backend != device.backend() {
            throw "GpuProgram: backend mismatch"
        }
        _handle = handle
        _device = device
        _programKind = programKind
        _backend = backend
        _open = true
    }

    Long programId() { return _handle }
    GpuDevice device() { return _device }
    GpuProgramKind programKind() { return _programKind }
    GpuBackend backend() { return _backend }
    Bool isOpen() { return _open }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        if !_device.isOpen() { return Ok(unit) }
        return gpuProgramCloseRaw(_handle)
    }
}
```
