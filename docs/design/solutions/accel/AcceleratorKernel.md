# `AcceleratorKernel`

| 项 | 值 |
| --- | --- |
| 类型 | `class AcceleratorKernel` |
| 包 | `xdk.accel` |
| 稳定性 | `preview` |
| 依赖 | `AcceleratorProgram`、`AcceleratorDevice`、`AcceleratorBackend`、`Error` |

---

## 1. 定位

由加速器程序解析出的内核入口不透明句柄：内核名、所属程序/设备、后端、关闭、是否可用。

只做按名称选择入口与生命周期管理；不反射参数、不编译、不改变程序、不拥有内存。内核的绑定槽、参数布局、工作组语义由程序/后端契约定义。

不做：

- 内核枚举、反射、参数类型/数量查询；
- 内核特化、重命名、重编译；
- 参数默认值、自动绑定；
- 内核缓存/自动选择；
- 原生函数/内核对象暴露；
- 模型算子/图语义。

---

## 2. 设计逻辑

- 由 [`AcceleratorDevice.createKernel`](AcceleratorDevice.md) 创建；构造器主要供宿主/测试使用。
- `_handle` 是 `Long` 不透明句柄；不暴露原生函数/内核对象。
- `_kernelName` 是创建时请求的入口名；非空、区分大小写、不做 trim/别名/模糊匹配；后端可拒绝未知名称。
- 内核绑定一个程序；`device()`/`backend()` 委托程序；程序关闭使内核操作不可用。
- 一个程序可创建多个内核；内核不拥有程序；内核必须比程序先关闭。
- 内核不持有内存或命令缓冲；绑定发生在 [`AcceleratorCommandBuffer`](AcceleratorCommandBuffer.md)。
- 关闭后纯元数据（句柄、程序、设备、名称、后端、isOpen）仍可读；绑定/派发返回 `Unavailable`。
- 程序先关闭时，内核 `close()` 标记关闭后跳过原生关闭，返回 `Ok(unit)`；设备先关闭同理。
- 无 `equals`/`copy`/`describe`；内核是资源，不是值对象。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | >0；不透明句柄 |
| `_program` | `AcceleratorProgram` | final | 非 null；非拥有引用 |
| `_kernelName` | `String` | final | 非空；区分大小写 |
| `_open` | `Bool` | 内部 | 构造后 true；close 后 false |

不变量：

- `handle > 0`；`program` 非 null；`kernelName` 非空。
- 内核属于程序所在设备；不得跨设备使用。
- 内核不拥有程序、设备、内存、命令缓冲。
- 构造后 `open = true`；`close()` 后 `open = false`；close 幂等。
- 关闭后不再调用任何原生内核原语。
- 程序关闭后，内核不能用于新的绑定/派发。
- 同一程序可有多个内核；名称唯一性由后端决定，本包不承诺。

---

## 4. 生命周期

由 `AcceleratorDevice.createKernel` 创建；调用方拥有并必须 `close()`；close 幂等；无 `deinit` 依赖。

顺序：

- 程序创建 → 内核创建 → 命令缓冲绑定/派发 → 等 fence → 关闭内核 → 关闭程序；
- 内核必须比程序先关闭；程序关闭后内核元数据仍可读，但绑定/派发 `Unavailable`；
- 设备关闭后内核不可用；`close()` 跳过原生关闭。

未提交的内核可以随时关闭；已提交但未完成的命令缓冲仍引用内核时，调用方必须等 fence signaled 再关闭。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `AcceleratorKernel(Long handle, AcceleratorProgram program, String kernelName)` | handle、program、kernelName | handle >0；program 非 null；kernelName 非空 | 非法 → panic |

构造器主要供宿主/测试使用；业务代码通过 `AcceleratorDevice.createKernel` 获取。工厂对未知入口返回 `NotFound`（后端可确定时）或 `Unsupported`；程序关闭返回 `Unavailable`；跨设备程序返回 `InvalidArgument`。

---

## 6. 字段表

见 §3；字段私有。不暴露原生函数、内核对象、入口地址或驱动 SDK 句柄。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `kernelHandle` | 不透明句柄 | 无 | `Long` | 无 |
| `program` | 所属程序 | 无 | `AcceleratorProgram` | 无 |
| `device` | 所属设备 | 无 | `AcceleratorDevice` | 无 |
| `kernelName` | 入口名 | 无 | `String` | 无 |
| `backend` | 后端家族 | 无 | `AcceleratorBackend` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

说明：

- `kernelHandle()` 返回不透明 `Long`；关闭后仍返回原值；不得当作跨进程/持久 ID。
- `program()`/`device()` 返回非拥有引用；内核不关闭它们。
- `device()` 委托 `_program.device()`；`backend()` 委托 `_program.backend()`。
- `kernelName()` 返回创建时请求的名称；关闭后仍可读；不保证后端内部名称一致。
- `close`：第一次调用标记关闭；程序与设备仍打开时调用原生关闭；程序或设备已关闭时跳过；后续返回 `Ok(unit)`。关闭失败只作为诊断返回 `Io`，不改变“已关闭”状态。
- `isOpen()` 不触碰原生句柄。
- 不提供 `arguments`/`metadata`/`workGroupSize`/`describe`；参数布局由程序/后端契约定义，工作组大小由命令缓冲 dispatch 参数给出。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- 按名称选择入口；
- 非拥有程序引用；
- `Context`/`Result`；
- 幂等关闭；
- 生命周期依赖。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、String、Bool、Result；
- 运行时/适配器：
  - `acceleratorKernelCreateRaw(Context context, Long programHandle, String kernelName) -> Result<Long, Error>`；
  - `acceleratorKernelCloseRaw(Long kernelHandle) -> Result<Unit, Error>`；
- 原生内核句柄必须 >0；0/负数视为适配器内部错误（工厂返回 `Internal`，构造器 panic）；
- 适配器必须检查 `Context` 取消；不得在本包做内核反射/编译；
- 适配器解析 `AcceleratorProgram` 的内部句柄；公共 API 不暴露；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`AcceleratorProgram`、`AcceleratorDevice`、`AcceleratorCommandBuffer`。

---

## 10. 依赖的特性/接口/类

[`AcceleratorDevice`](AcceleratorDevice.md)、[`AcceleratorProgram`](AcceleratorProgram.md)、[`AcceleratorCommandBuffer`](AcceleratorCommandBuffer.md)、[`AcceleratorMemory`](AcceleratorMemory.md)、[`AcceleratorBackend`](AcceleratorBackend.md)、`Context`、`Error`。

---

## 11. 所有权与并发

引用语义；内核由调用方拥有；程序与设备是非拥有引用；内核不反向拥有它们。

内核不拥有内存或命令缓冲；绑定由命令缓冲持有非拥有引用。

非线程安全：`close` 与绑定/派发不得并发；调用方必须串行化。`close()` 幂等指重复调用安全，不承诺并发 close 安全。

无 `equals`/`copy`；`==` 是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：

- `createProgram` → `createKernel(context, program, "vector_add")` → 命令缓冲 `bindKernel` → 绑定内存/标量 → `dispatch`。
- 同一程序创建多个内核，分别关闭。
- 未知入口返回 `NotFound`/`Unsupported`，记录名称并关闭程序。
- 提交后等 fence 再关闭内核与程序。

反例：

- 期望 `createKernel` 自动选择唯一入口。
- 传入空名称/大小写不匹配并期望模糊匹配。
- 内核关闭后继续绑定/派发。
- 程序关闭后继续使用内核。
- 把内核句柄当函数指针。
- 用内核名做跨版本稳定 ABI 保证。

---

## 13. 测试/场景义务

空名称/非法 handle/null 程序 panic；已知/未知入口；大小写敏感；
`program`/`device`/`backend`/`kernelName` 读取；关闭后元数据可读；
程序先关闭/设备先关闭后的 `close`/绑定行为；多内核同程序；
取消/`NotFound`/`Unsupported`/`Io`；已提交未完成时关闭的合同错误；
无反射/无参数查询；跨设备程序 `InvalidArgument`。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class AcceleratorKernel {
    final Long _handle
    final AcceleratorProgram _program
    final String _kernelName
    Bool _open

    AcceleratorKernel(Long handle, AcceleratorProgram program, String kernelName) {
        if handle <= 0 || program == null || kernelName == null || kernelName == "" {
            throw "AcceleratorKernel: invalid field"
        }
        _handle = handle
        _program = program
        _kernelName = kernelName
        _open = true
    }

    Long kernelHandle() { return _handle }
    AcceleratorProgram program() { return _program }
    AcceleratorDevice device() { return _program.device() }
    String kernelName() { return _kernelName }
    AcceleratorBackend backend() { return _program.backend() }
    Bool isOpen() { return _open }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        if !_program.isOpen() || !_program.device().isOpen() {
            return Ok(unit)
        }
        return acceleratorKernelCloseRaw(_handle)
    }
}
```
