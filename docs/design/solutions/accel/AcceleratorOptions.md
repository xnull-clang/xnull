# `AcceleratorOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class AcceleratorOptions` |
| 包 | `xdk.accel` |
| 稳定性 | `preview` |
| 依赖 | `Error`、`BasicError`、`ErrorKind` |

---

## 1. 定位

加速器打开、程序加载与队列创建的不可变选项值：诊断标签、性能分析、校验、内存上限、代码格式、加载选项、队列优先级。

只做显式配置；不编译代码、不调度、不探测能力、不改变设备默认能力。选项字段按操作分组适用；不适用的非默认字段必须显式失败，不能静默忽略。

不做：

- 编译器/链接器选项语义；
- 调度/抢占/亲和性；
- 权限提升；
- 驱动安装/环境变量注入；
- 模型运行时/图优化；
- 自动回退或模拟。

---

## 2. 设计逻辑

- 不可变值对象；所有字段 final；列表复制；可共享。
- `AcceleratorOptions.defaults()` 提供全默认值；构造函数公开，主要供宿主/集成层使用。
- 字段按操作适用：
  - `Accel.open`：`label`、`enableProfiling`、`enableValidation`、`memoryLimitBytes`；
  - `AcceleratorDevice.createProgram`：`label`、`codeFormat`、`loadOptions`；
  - `AcceleratorDevice.createQueue`：`label`、`queuePriority`。
- 不适用字段保持默认值；非默认且不适用 → `InvalidArgument`，防止“传了却被忽略”。
- 适用字段若后端不支持 → `Unsupported`（如 profiling/validation/memory limit/priority），不得静默降级。
- `codeFormat` 为空表示后端自动识别；非空为后端定义的预编译产物标记，不接受源码格式。
- `loadOptions` 是后端加载器接受的 opaque 字符串；不做 shell 展开、变量替换、通配符或文件路径解释。
- `queuePriority` 是提示，不是调度合同；后端可不支持，非零时必须显式失败。
- `memoryLimitBytes` 是设备内存上限合同；0 表示不设显式上限；后端无法执行时在 `open` 返回 `Unsupported`。
- 值语义；选项不绑定设备、不缓存、不持久化。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 默认值 | 说明 |
| --- | --- | --- | --- | --- |
| `_label` | `String` | final | `""` | 诊断标签；可空 |
| `_enableProfiling` | `Bool` | final | false | 打开时启用性能分析 |
| `_enableValidation` | `Bool` | final | false | 打开时启用调试校验 |
| `_memoryLimitBytes` | `Long` | final | 0 | ≥0；0 不设显式上限 |
| `_codeFormat` | `String` | final | `""` | 空 = 后端自动识别；非空 = 预编译产物标记 |
| `_loadOptions` | `List<String>` | final | 空列表 | 非空字符串；加载器 opaque 选项 |
| `_queuePriority` | `Int` | final | 0 | -100..100；0 默认；提示而非合同 |

不变量：

- 所有字符串非 null；`loadOptions` 非 null 且每个元素非空。
- `memoryLimitBytes ≥ 0`；`queuePriority` 在 -100..100。
- `codeFormat` 不做大小写归一；空串有“自动识别”特殊含义。
- `loadOptions` 构造时复制；`loadOptions()` 返回副本。
- 不可变；`copy()` 返回独立值；`equals` 逐字段（列表逐元素）比较。
- 选项不包含任何原生句柄、指针、文件描述符或 SDK 对象。

---

## 4. 生命周期

构造后不可变；无 close；可共享。选项可被多次传给不同设备/程序/队列；实现不得修改选项。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `AcceleratorOptions(String label, Bool enableProfiling, Bool enableValidation, Long memoryLimitBytes, String codeFormat, List<String> loadOptions, Int queuePriority)` | 7 个字段 | 字符串/列表非 null；`loadOptions` 元素非空；`memoryLimitBytes ≥ 0`；`queuePriority ∈ [-100, 100]` | 非法 → panic |
| `AcceleratorOptions.defaults()` | 无 | 无 | 无 |

构造器主要供宿主/集成层使用；业务代码可用 `defaults()` 后通过构造器创建变体。

---

## 6. 字段表

见 §3；字段私有。不暴露原生配置对象或 SDK 结构。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `label` | 诊断标签 | 无 | `String` | 无 |
| `isProfilingEnabled` | 是否启用性能分析 | 无 | `Bool` | 无 |
| `isValidationEnabled` | 是否启用调试校验 | 无 | `Bool` | 无 |
| `memoryLimitBytes` | 内存上限 | 无 | `Long` | 无 |
| `codeFormat` | 预编译产物标记 | 无 | `String` | 无 |
| `loadOptions` | 加载器选项副本 | 无 | `List<String>` | 无 |
| `queuePriority` | 队列优先级提示 | 无 | `Int` | 无 |
| `equals` | 值比较 | `AcceleratorOptions other` | `Bool` | null → false |
| `copy` | 复制 | 无 | `AcceleratorOptions` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `defaults`（静态） | 全默认选项 | 无 | `AcceleratorOptions` | 无 |

包内校验函数：

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `acceleratorOptionsCheckOpen` | 校验打开适用字段 | `AcceleratorOptions options` | `Result<Unit, Error>` | `InvalidArgument` |
| `acceleratorOptionsCheckProgram` | 校验程序适用字段 | `AcceleratorOptions options` | `Result<Unit, Error>` | `InvalidArgument` |
| `acceleratorOptionsCheckQueue` | 校验队列适用字段 | `AcceleratorOptions options` | `Result<Unit, Error>` | `InvalidArgument` |

说明：

- `label` 只用于日志/诊断；不参与能力、权限或调度；不得包含敏感信息。
- `isProfilingEnabled`/`isValidationEnabled` 在 `open` 时消费；不支持 → `Unsupported`。
- `memoryLimitBytes` 在 `open` 时消费；0 不设显式上限；>0 且后端无法执行 → `Unsupported`；分配超限 → `OutOfMemory`。
- `codeFormat` 在 `createProgram` 时消费；示例 token 包括 `"spirv"`、`"ptx"`、`"cubin"`、`"fatbin"`、`"metallib"`、`"opencl-binary"`、`"native"`、`"bitstream"`；这些只是后端约定，不是本包支持的完整列表。
- `loadOptions` 在 `createProgram` 时消费；原样传给后端加载器，不执行 shell；实现可拒绝未知选项（`Unsupported`）或非法内容（`InvalidArgument`）。
- `queuePriority` 在 `createQueue` 时消费；正数更高、负数更低、0 默认；不保证顺序、抢占或延迟。
- `equals` 比较所有字段，包括 `loadOptions` 顺序；`copy` 深复制列表。
- `describe` 输出 label/codeFormat/priority/limit/profiling/validation，不输出 `loadOptions`，避免泄漏路径或密钥。
- 校验函数只检查“字段是否适用于该操作”；具体值是否被后端支持由对应操作返回 `Unsupported`。

---

## 8. 使用的技术

- 不可变值对象；
- 列表防御性复制；
- 字段适用性校验；
- 值比较；
- 安全日志过滤；
- `Context` 无关的纯值。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Long、Int、Bool、List、Result；
- 辅助：`unit` 值；
- 运行时：无；
- 接口：`Error`、`BasicError`、`ErrorKind`、`Accel`、`AcceleratorDevice`。

---

## 10. 依赖的特性/接口/类

[`Accel`](Accel.md)、[`AcceleratorDevice`](AcceleratorDevice.md)、[`AcceleratorProgram`](AcceleratorProgram.md)、[`AcceleratorQueue`](AcceleratorQueue.md)、`Context`、`Error`。

---

## 11. 所有权与并发

不可变值；可跨任务共享；无资源；无取消点。`loadOptions()` 返回副本，调用方修改副本不影响选项。

相等：`equals` 值比较；`==` 仍是引用身份；可作 `Map`/`Set` 键（哈希需按字段实现，若运行时提供）。

---

## 12. 示例与反例

正确：`AcceleratorOptions.defaults()` 打开设备；带 `label` 的诊断；`memoryLimitBytes` 限制设备分配；`codeFormat = "spirv"` + `loadOptions` 加载预编译程序；`queuePriority = 10` 请求高优先级并在 `Unsupported` 时降级到默认队列（重新创建，不静默）。

反例：把源码传给 `codeFormat`；把编译器 `-O2` 当加载选项依赖；把 `queuePriority` 当实时保证；在 `createProgram` 传 `memoryLimitBytes` 期望生效；在 `open` 传 `codeFormat` 被静默忽略；把 `loadOptions` 拼成 shell 命令；在日志打印 `loadOptions`；修改 `loadOptions()` 返回列表期望改变选项。

---

## 13. 测试/场景义务

默认值/全字段构造；负内存上限/优先级越界 panic；空 loadOptions 元素 panic；
`loadOptions` 复制独立性；`equals`/`copy`；`describe` 不含 loadOptions；
open/program/queue 三类适用性校验；不适用非默认字段 → `InvalidArgument`；
后端不支持 profiling/validation/memory limit/priority → `Unsupported`；
`codeFormat` 空/非空/未知；`loadOptions` 原样传递/拒绝；memory limit 超限 → `OutOfMemory`；
并发共享选项；日志安全。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class AcceleratorOptions {
    final String _label
    final Bool _enableProfiling
    final Bool _enableValidation
    final Long _memoryLimitBytes
    final String _codeFormat
    final List<String> _loadOptions
    final Int _queuePriority

    AcceleratorOptions(String label, Bool enableProfiling, Bool enableValidation,
                       Long memoryLimitBytes, String codeFormat,
                       List<String> loadOptions, Int queuePriority) {
        if label == null || codeFormat == null || loadOptions == null {
            throw "AcceleratorOptions: null field"
        }
        if memoryLimitBytes < 0 {
            throw "AcceleratorOptions: negative memory limit"
        }
        if queuePriority < -100 || queuePriority > 100 {
            throw "AcceleratorOptions: priority out of range"
        }
        Int index = 0
        while index < loadOptions.length() {
            String option = loadOptions.get(index)
            if option == null || option == "" {
                throw "AcceleratorOptions: empty load option"
            }
            index = index + 1
        }
        _label = label
        _enableProfiling = enableProfiling
        _enableValidation = enableValidation
        _memoryLimitBytes = memoryLimitBytes
        _codeFormat = codeFormat
        _loadOptions = loadOptions.copy()
        _queuePriority = queuePriority
    }

    static AcceleratorOptions defaults() {
        return new AcceleratorOptions("", false, false, 0, "", [], 0)
    }

    String label() { return _label }
    Bool isProfilingEnabled() { return _enableProfiling }
    Bool isValidationEnabled() { return _enableValidation }
    Long memoryLimitBytes() { return _memoryLimitBytes }
    String codeFormat() { return _codeFormat }
    List<String> loadOptions() { return _loadOptions.copy() }
    Int queuePriority() { return _queuePriority }

    Bool equals(AcceleratorOptions other) {
        if other == null { return false }
        if _label != other.label()
            || _enableProfiling != other.isProfilingEnabled()
            || _enableValidation != other.isValidationEnabled()
            || _memoryLimitBytes != other.memoryLimitBytes()
            || _codeFormat != other.codeFormat()
            || _queuePriority != other.queuePriority() {
            return false
        }
        List<String> otherOptions = other.loadOptions()
        if _loadOptions.length() != otherOptions.length() { return false }
        Int index = 0
        while index < _loadOptions.length() {
            if _loadOptions.get(index) != otherOptions.get(index) { return false }
            index = index + 1
        }
        return true
    }

    AcceleratorOptions copy() {
        return new AcceleratorOptions(_label, _enableProfiling, _enableValidation,
            _memoryLimitBytes, _codeFormat, _loadOptions, _queuePriority)
    }

    String describe() {
        return "accel options label=" + _label
            + " format=" + _codeFormat
            + " priority=" + str(_queuePriority)
            + " limit=" + str(_memoryLimitBytes)
            + " profiling=" + str(_enableProfiling)
            + " validation=" + str(_enableValidation)
    }
}

Result<Unit, Error> acceleratorOptionsCheckOpen(AcceleratorOptions options) {
    if options == null { throw "acceleratorOptionsCheckOpen: null options" }
    if options.codeFormat() != "" || options.loadOptions().length() != 0
        || options.queuePriority() != 0 {
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "option not valid for open"))
    }
    return Ok(unit)
}

Result<Unit, Error> acceleratorOptionsCheckProgram(AcceleratorOptions options) {
    if options == null { throw "acceleratorOptionsCheckProgram: null options" }
    if options.isProfilingEnabled() || options.isValidationEnabled()
        || options.memoryLimitBytes() != 0 || options.queuePriority() != 0 {
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "option not valid for program"))
    }
    return Ok(unit)
}

Result<Unit, Error> acceleratorOptionsCheckQueue(AcceleratorOptions options) {
    if options == null { throw "acceleratorOptionsCheckQueue: null options" }
    if options.isProfilingEnabled() || options.isValidationEnabled()
        || options.memoryLimitBytes() != 0 || options.codeFormat() != ""
        || options.loadOptions().length() != 0 {
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "option not valid for queue"))
    }
    return Ok(unit)
}
```
