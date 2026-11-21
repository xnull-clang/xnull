# `AcceleratorProgram`

| 项 | 值 |
| --- | --- |
| 类型 | `class AcceleratorProgram` |
| 包 | `xdk.accel` |
| 稳定性 | `preview` |
| 依赖 | `AcceleratorDevice`、`AcceleratorBackend`、`Error` |

---

## 1. 定位

已加载的加速器程序不透明句柄：后端固定的预编译代码产物、代码字节数、代码格式标记、关闭、是否可用。

程序是“后端可加载的不透明字节”，不是源码、模型、计算图、算子集合或可反射的模块。本包不编译、不链接、不优化、不列举内核。

不做：

- 源码编译、链接、优化、特化常量；
- 模型/算子/图/权重解析；
- 内核枚举、反射、入口点发现；
- 代码字节回读、反汇编、调试信息；
- 原生模块/库/SDK 句柄暴露；
- 自动选择内核或后端。

---

## 2. 设计逻辑

- 由 [`AcceleratorDevice.createProgram`](AcceleratorDevice.md) 创建；构造器主要供宿主/测试使用。
- `_handle` 是 `Long` 不透明句柄；不暴露模块/库/原生二进制句柄。
- `_codeSizeBytes` 是调用方提交的字节数，`Long`，>0；程序不保留代码字节，只保留大小与格式标记。
- `_codeFormat` 是创建时请求的标记；空串表示后端自动识别；非空为后端约定 token；程序不解析、不验证内容。
- 代码必须是预编译产物；`"source"` 等源码格式不在基线；需要源码编译的路径属于 ecosystem 工具链。
- 程序绑定一个设备；`backend()` 委托设备后端；程序与设备同生命周期，设备先关闭使程序不可用。
- 一个程序可创建多个内核；程序不拥有内核；内核必须先用完并关闭，再关闭程序。
- 关闭后纯元数据（句柄、设备、后端、大小、格式、isOpen）仍可读；创建内核返回 `Unavailable`。
- 设备先关闭时，`close()` 标记关闭后跳过原生关闭，返回 `Ok(unit)`。
- 无 `equals`/`copy`/`describe`；程序是资源，不是值对象。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | >0；不透明句柄 |
| `_device` | `AcceleratorDevice` | final | 非 null；非拥有引用 |
| `_codeSizeBytes` | `Long` | final | >0；提交的代码字节数 |
| `_codeFormat` | `String` | final | 非 null；可空串 = 后端自动识别 |
| `_open` | `Bool` | 内部 | 构造后 true；close 后 false |

不变量：

- `handle > 0`；`device` 非 null；`codeSizeBytes > 0`；`codeFormat` 非 null。
- 程序代码不被保留/回读；只保留大小与格式标记。
- 程序不拥有设备、内核或内存。
- 构造后 `open = true`；`close()` 后 `open = false`；close 幂等。
- 关闭后不再调用任何原生程序原语。
- 程序不能跨设备使用；内核创建时验证程序与设备一致。
- 程序格式标记不等于实际格式；实际兼容性由后端决定。

---

## 4. 生命周期

由 `AcceleratorDevice.createProgram` 创建；调用方拥有并必须 `close()`；close 幂等；无 `deinit` 依赖。

顺序：

- 设备 → 程序 → 内核 → 命令缓冲 → fence；
- 内核必须比程序先关闭；程序必须比设备先关闭（或随设备关闭失效）；
- 程序关闭后，已创建内核的操作返回 `Unavailable`；内核 `close()` 标记关闭并跳过原生关闭。

设备先关闭时：

- `createKernel`/`close` 等操作按规则返回 `Unavailable`/`Ok(unit)`；
- 程序元数据仍可读；`isOpen()` 仍为 true 直到调用方 `close()`；
- 关闭跳过原生程序原语，视为设备回收。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `AcceleratorProgram(Long handle, AcceleratorDevice device, Long codeSizeBytes, String codeFormat)` | handle、device、codeSizeBytes、codeFormat | handle >0；device 非 null；codeSizeBytes >0；codeFormat 非 null | 非法 → panic |

构造器主要供宿主/测试使用；业务代码通过 `AcceleratorDevice.createProgram` 获取。工厂对空代码返回 `InvalidArgument`；未知格式返回 `Unsupported`；加载失败映射 `Io`/`OutOfMemory`/`PermissionDenied`。

---

## 6. 字段表

见 §3；字段私有。不暴露原生模块、库、二进制、指针或驱动 SDK 对象。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `programHandle` | 不透明句柄 | 无 | `Long` | 无 |
| `device` | 所属设备 | 无 | `AcceleratorDevice` | 无 |
| `backend` | 后端家族 | 无 | `AcceleratorBackend` | 无 |
| `codeSizeBytes` | 代码字节数 | 无 | `Long` | 无 |
| `codeFormat` | 代码格式标记 | 无 | `String` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

说明：

- `programHandle()` 返回不透明 `Long`；关闭后仍返回原值；不得当作跨进程/持久 ID。
- `device()` 返回非拥有引用；程序不关闭设备。
- `backend()` 委托 `device.backend()`；设备关闭后仍返回打开时的后端。
- `codeSizeBytes()` 返回创建时提交的字节数；关闭后仍可读。
- `codeFormat()` 返回创建时请求的标记；空串表示自动识别；不保证等于实际产物格式。
- `close`：第一次调用标记关闭；设备仍打开时调用原生关闭；设备已关闭时跳过；后续返回 `Ok(unit)`。关闭失败只作为诊断返回 `Io`，不改变“已关闭”状态。
- `isOpen()` 不触碰原生句柄。
- 不提供 `code`/`kernels`/`describe`/`equals`/`copy`；代码不可回读，内核不枚举。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- 预编译产物加载；
- 代码大小/格式元数据；
- `Context`/`Result`；
- 幂等关闭；
- 生命周期依赖。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、String、Bool、Bytes、Result；
- 辅助：`toLong`（Int → Long，用于 `Bytes.length()`）；
- 运行时/适配器：
  - `acceleratorProgramCreateRaw(Context context, Long deviceHandle, Bytes code, String codeFormat, List<String> loadOptions) -> Result<Long, Error>`；
  - `acceleratorProgramCloseRaw(Long programHandle) -> Result<Unit, Error>`；
- 原生程序句柄必须 >0；0/负数视为适配器内部错误（工厂返回 `Internal`，构造器 panic）；
- 适配器必须检查 `Context` 取消；不得把源码编译塞进 `createProgram`；
- 适配器解析 `AcceleratorDevice` 的内部句柄；公共 API 不暴露；
- 接口：`Context`、`Bytes`、`Error`、`BasicError`、`ErrorKind`、`AcceleratorDevice`、`AcceleratorKernel`、`AcceleratorOptions`。

---

## 10. 依赖的特性/接口/类

[`AcceleratorDevice`](AcceleratorDevice.md)、[`AcceleratorKernel`](AcceleratorKernel.md)、[`AcceleratorCommandBuffer`](AcceleratorCommandBuffer.md)、[`AcceleratorOptions`](AcceleratorOptions.md)、[`AcceleratorBackend`](AcceleratorBackend.md)、`Context`、`Bytes`、`Error`。

---

## 11. 所有权与并发

引用语义；程序由调用方拥有；设备是非拥有引用；程序不反向拥有设备。

程序不拥有内核；内核持有程序非拥有引用，必须比程序先关闭。

非线程安全：`close` 与内核创建/使用不得并发；调用方必须串行化。`close()` 幂等指重复调用安全，不承诺并发 close 安全。

无 `equals`/`copy`；`==` 是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：

- 从可信来源读取预编译 SPIR-V/PTX/cubin/metallib/位流字节 → `createProgram` → 创建一个或多个内核 → 录制/提交 → 等 fence → 关闭内核 → 关闭程序。
- `codeFormat` 为空让后端识别；未知格式显式 `Unsupported`。
- 程序加载失败时关闭设备并记录诊断；不重试无限循环。
- 同一预编译产物可为多个内核创建程序实例，各自关闭。

反例：

- 把 C/C++/OpenCL C 源码传给 `createProgram` 期望本包编译。
- 把 ONNX 模型文件当程序字节。
- 从程序回读代码或枚举内核名。
- 程序关闭后继续创建/使用内核。
- 设备关闭后仍调用程序原生关闭。
- 把程序句柄当跨进程 ID。
- 加载未签名/不可信位流到 FPGA 而不评估风险。

---

## 13. 测试/场景义务

空代码/负大小/null 设备 panic；格式空/已知/未知；加载成功/失败；
`codeSizeBytes`/`codeFormat`/`backend` 读取；关闭后元数据可读；
设备关闭后 `close` `Ok(unit)`、内核创建/使用 `Unavailable`；
内核先关闭再程序关闭；程序先关闭后内核操作 `Unavailable`；
取消/`Io`/`OutOfMemory`/`PermissionDenied`；多内核共享程序；
无代码回读/无内核枚举；预编译产物信任边界。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class AcceleratorProgram {
    final Long _handle
    final AcceleratorDevice _device
    final Long _codeSizeBytes
    final String _codeFormat
    Bool _open

    AcceleratorProgram(Long handle, AcceleratorDevice device,
                       Long codeSizeBytes, String codeFormat) {
        if handle <= 0 || device == null || codeSizeBytes <= 0 || codeFormat == null {
            throw "AcceleratorProgram: invalid field"
        }
        _handle = handle
        _device = device
        _codeSizeBytes = codeSizeBytes
        _codeFormat = codeFormat
        _open = true
    }

    Long programHandle() { return _handle }
    AcceleratorDevice device() { return _device }
    AcceleratorBackend backend() { return _device.backend() }
    Long codeSizeBytes() { return _codeSizeBytes }
    String codeFormat() { return _codeFormat }
    Bool isOpen() { return _open }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        if !_device.isOpen() { return Ok(unit) }
        return acceleratorProgramCloseRaw(_handle)
    }
}
```
