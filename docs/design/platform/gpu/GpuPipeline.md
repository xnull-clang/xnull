# `GpuPipeline`

| 项 | 值 |
| --- | --- |
| 类型 | `class GpuPipeline` |
| 包 | `xdk.gpu` |
| 稳定性 | `preview` |
| 依赖 | `GpuDevice`、`GpuProgram`、`GpuBufferUsage`、`List`、`Error` |

---

## 1. 定位

已创建的计算管线不透明句柄：绑定一个 `GpuProgram` 与一个有序缓冲布局。

只做：

- 固定程序与绑定槽布局；
- 为命令缓冲提供 `bindPipeline` 目标；
- 关闭与是否可用查询。

不做：

- 工作组大小、入口点、特化常量；
- 着色器反射、自动推导布局、纹理/采样器/渲染状态；
- push constants、动态偏移、绑定别名；
- 拥有或关闭程序；
- 命令录制/提交。

---

## 2. 设计逻辑

- 由 `GpuCompute.createPipeline(context, device, program, bufferLayout)` 创建；构造器主要供宿主/测试使用。
- `_handle` 是 `Long` 不透明句柄；不暴露后端 pipeline 对象。
- `_program` 是 `GpuProgram` 的非拥有引用；管线不关闭程序，调用方必须先关闭管线再关闭程序。
- `_bufferLayout` 是有序 `List<GpuBufferUsage>`；索引即绑定槽，元素声明该槽需要的访问方式。
- 布局是显式的：本包不做着色器反射，也不从代码推断绑定；调用方必须提供与程序一致的布局。
- 布局不能包含 `Indirect`；基线没有 `dispatchIndirect`。布局可以为空，表示程序不绑定缓冲。
- 管线创建后不可变；没有“改布局/换程序”的 API。
- 程序必须是 `Compute`、打开、且与管线属于同一设备；否则创建失败。
- 关闭后纯元数据（ID、设备、程序、布局、isOpen）仍可读；绑定/使用返回 `Unavailable`。
- 设备先关闭时，`close()` 标记关闭后跳过原生关闭，视为设备回收，返回 `Ok(unit)`。
- 无 `equals`/`copy`；管线是资源，不是值对象。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | > 0；不透明句柄 |
| `_device` | `GpuDevice` | final | 非 null；非拥有引用 |
| `_program` | `GpuProgram` | final | 非 null；非拥有引用；Compute |
| `_bufferLayout` | `List<GpuBufferUsage>` | final | 非 null；元素非 null；无 `Indirect`；副本 |
| `_open` | `Bool` | 内部 | 构造后 true；close 后 false |

不变量：

- `handle > 0`；`device`/`program`/`bufferLayout` 非 null。
- `program.programKind() == Compute`；`program.device() == device`；创建时程序打开。
- 布局元素非 null；不含 `Indirect`；索引从 0 开始连续映射绑定槽。
- 布局是副本：调用方修改传入列表不影响管线。
- 程序必须比管线活得久；管线不拥有程序。
- 构造后 `open = true`；`close()` 后 `open = false`；close 幂等。
- 关闭后不再调用任何原生 pipeline 原语。

---

## 4. 生命周期

由 `GpuCompute.createPipeline` 创建；调用方拥有并必须 `close()`；close 幂等；无 `deinit` 依赖。

程序必须比管线活得久。若程序先关闭：

- 管线元数据仍可读，但绑定/提交返回 `Unavailable`；
- 管线 `close()` 仍标记关闭并尝试原生关闭；结果可能是 `Ok(unit)` 或诊断错误。

设备必须比管线活得久。设备先关闭时：

- 后续绑定/提交返回 `Unavailable`；
- `close()` 标记关闭后跳过原生关闭，返回 `Ok(unit)`；
- 设备关闭不会自动把 pipeline 标记为 closed，`isOpen()` 仍为 true 直到调用方 `close()`。

提交后，管线必须保持打开直到关联 `GpuFence` signaled。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `GpuPipeline(Long handle, GpuDevice device, GpuProgram program, List<GpuBufferUsage> bufferLayout)` | handle、device、program、bufferLayout | handle > 0；device/program 非 null；program 打开且为 Compute；program 属于同一设备；布局非 null、元素非 null、无 `Indirect` | 非法 → panic |

构造器主要供宿主/测试使用；业务代码通过 `GpuCompute.createPipeline` 获取。工厂对用户输入错误返回 `InvalidArgument`/`Unsupported`，不依赖构造器 panic。

---

## 6. 字段表

见 §3；字段私有。不暴露后端 pipeline 对象、着色器反射或程序内部句柄。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `pipelineId` | 不透明句柄 | 无 | `Long` | 无 | O(1)；不持久 |
| `device` | 所属设备 | 无 | `GpuDevice` | 无 | 非拥有引用 |
| `program` | 绑定的程序 | 无 | `GpuProgram` | 无 | 非拥有引用 |
| `bufferLayout` | 缓冲布局副本 | 无 | `List<GpuBufferUsage>` | 无 | O(n) 复制 |
| `bufferCount` | 绑定槽数量 | 无 | `Int` | 无 | O(1) |
| `close` | 关闭管线 | 无 | `Result<Unit, Error>` | `Io`（诊断） | O(1)；幂等 |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 | O(1) |

说明：

- `pipelineId()` 返回不透明 `Long`，仅用于诊断/关联；关闭后仍返回原值；不得当作跨进程或持久 ID。
- `device()`/`program()` 返回非拥有引用；管线不关闭设备或程序。
- `bufferLayout()` 返回副本；修改返回值不影响管线；关闭后仍可读。
- `bufferCount()` 等于布局长度；索引合法域 `[0, bufferCount - 1]`。
- `close()`：第一次调用标记关闭；设备仍打开时调用原生关闭；设备已关闭时跳过；后续调用返回 `Ok(unit)`。关闭失败只作为诊断返回 `Io`，不改变“已关闭”状态。
- `isOpen()` 不触碰原生句柄。
- 不提供 `workgroupSize()`/`entryPoint()`/`reflect()`/`setProgram()`；这些属于 X 或后端私有。
- 不提供 `describe`/`equals`/`copy`；管线是资源，不是值对象。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- 显式有序绑定布局；
- 程序借用；
- 列表复制；
- `Context`/`Result`；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、Int、Bool、List、Result；
- 运行时/适配器：
  - `gpuPipelineCreateRaw(Context context, GpuDevice device, Long programHandle, List<GpuBufferUsage> bufferLayout) -> Result<Long, Error>`；
  - `gpuPipelineCloseRaw(Long pipelineHandle) -> Result<Unit, Error>`；
- 原生 pipeline 句柄必须 > 0；0/负数视为适配器内部错误（工厂返回 `Internal`，构造器 panic）；
- 适配器负责后端布局限制/对齐/槽位上限；不支持时返回 `Unsupported`/`InvalidArgument`；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`GpuDevice`、`GpuProgram`、`GpuBufferUsage`。

---

## 10. 依赖的特性/接口/类

[`GpuCompute`](GpuCompute.md)、[`GpuProgram`](GpuProgram.md)、[`GpuBufferUsage`](GpuBufferUsage.md)、[`GpuDevice`](../os/gpu/GpuDevice.md)、[`GpuCommandBuffer`](GpuCommandBuffer.md)、[`GpuBuffer`](GpuBuffer.md)、`Context`、`Error`。

---

## 11. 所有权与并发

引用语义；管线由调用方拥有；设备与程序都是非拥有引用。

非线程安全：`close` 与绑定/提交不得并发；调用方必须串行化。`close()` 幂等指重复调用安全，不承诺并发 close 安全。

关闭顺序：等待 fence → 命令缓冲 → 管线 → 程序。管线关闭不关闭程序；程序关闭使管线不可用。提交后，管线必须保持打开直到 fence signaled。

无 `equals`/`copy`；`==` 是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：

- 用 Compute 程序创建布局为 `[Read, Uniform]` 的管线；命令缓冲按索引 0/1 绑定对应 buffer；关闭管线后再关闭程序。
- `bufferLayout()` 只读用于诊断/校验；修改返回值不影响管线。
- 布局为空表示程序不绑定 buffer；dispatch 仍然可以执行。
- `Vertex`/`Fragment` 程序在创建管线前就被拒绝。

反例：

- 布局包含 `Indirect`，或包含顶点/索引用途（X）。
- 用非 Compute 程序创建管线。
- 用另一个设备的程序创建管线。
- 程序先 close，再绑定管线。
- 修改传入的布局列表并期望管线变化。
- 认为管线拥有程序，关闭管线时程序也被关闭。
- 认为管线暴露工作组大小/入口点/反射信息。

---

## 13. 测试/场景义务

- 构造非法 handle/device/program/布局 panic；程序关闭/非 Compute/跨设备 panic。
- `GpuCompute.createPipeline`：空布局、单槽、多槽成功；`Indirect` 返回 `InvalidArgument`；null 元素返回 `InvalidArgument`；程序关闭 `Unavailable`；程序 kind 非 Compute `Unsupported`；设备/程序不匹配 `InvalidArgument`；取消 `Cancelled`。
- `bufferLayout()` 副本独立性；`bufferCount()` 正确；关闭后元数据仍可读。
- `close` 幂等；设备先关时 `close` 返回 `Ok(unit)`；关闭后不调用原生原语。
- 关闭顺序：管线先关、程序后关成功；程序先关后绑定/提交返回 `Unavailable`。
- 同一程序创建多个管线；不同布局共存；后端槽位上限/对齐错误显式返回。
- 与 `GpuBufferUsage` 兼容矩阵、`GpuCommandBuffer.bindPipeline`/`bindBuffer` 组合。
- 并发误用不在保证范围；测试只验证串行契约。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class GpuPipeline {
    final Long _handle
    final GpuDevice _device
    final GpuProgram _program
    final List<GpuBufferUsage> _bufferLayout
    Bool _open

    GpuPipeline(Long handle, GpuDevice device, GpuProgram program,
                List<GpuBufferUsage> bufferLayout) {
        if handle <= 0 || device == null || program == null
            || bufferLayout == null {
            throw "GpuPipeline: invalid field"
        }
        if !program.isOpen() {
            throw "GpuPipeline: closed program"
        }
        if program.programKind() != GpuProgramKind.Compute {
            throw "GpuPipeline: program is not compute"
        }
        if program.device() != device {
            throw "GpuPipeline: program from another device"
        }
        List<GpuBufferUsage> copiedLayout = []
        Int index = 0
        while index < bufferLayout.length() {
            GpuBufferUsage usage = bufferLayout.get(index)
            if usage == null {
                throw "GpuPipeline: null buffer usage"
            }
            if usage == GpuBufferUsage.Indirect {
                throw "GpuPipeline: indirect layout is X"
            }
            copiedLayout.push(usage)
            index = index + 1
        }
        _handle = handle
        _device = device
        _program = program
        _bufferLayout = copiedLayout
        _open = true
    }

    Long pipelineId() { return _handle }
    GpuDevice device() { return _device }
    GpuProgram program() { return _program }
    List<GpuBufferUsage> bufferLayout() { return _bufferLayout.copy() }
    Int bufferCount() { return _bufferLayout.length() }
    Bool isOpen() { return _open }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        if !_device.isOpen() { return Ok(unit) }
        return gpuPipelineCloseRaw(_handle)
    }
}
```
