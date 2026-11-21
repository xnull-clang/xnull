# xdk.errors ——  核心包详细设计 v1.4

> **1.x legacy**：本文件是旧 core 包级设计/状态账本，不是 2.x 类型合同。2.x 以 [`core/`](README.md) 的逐包目录与 [`../PACKAGE-MAP.md`](../PACKAGE-MAP.md) 为准；执行层统一为 `xdk.execution`。

> **状态（2026-11-21）**：本文件是  v1 包级设计/实现状态账本。
> 公开类型与方法形态以 [`core/`](README.md) 为准；状态汇总见 [`STATUS.md`](STATUS.md)；
> 本文件的 `当前状态`、源码路径与 K/X 明细继续保留。

> 本版与 mini 实现对齐：`Error` 保持 `kind/describe` 两方法；`DetailedError`
> 是独立的丰富错误协议；`wrap/mapErr/report` 保留 S4 语义；步骤记录用
> `toErrorReport/annotate/withStep`。当前实现为单文件 `Errors.x`，文件拆分
> 在编译器支持多文件包后再做。

| 项 | 值 |
| --- | --- |
| 包 | `xdk.errors` |
| 层级 |  |
| 稳定性 | 核心 `stable`；扩展 `preview` |
| 依赖 | L2 诊断、L2 FFI 错误码（不依赖其他  包） |
| 被依赖 | 所有  包 |
| 对应源码 | `src/xdk/core/errors/Errors.x`（单文件；目标拆分见 §2） |
| 阶段 | -01（一个包一个验收门；批内条目不单独提交） |
| 当前状态 | Verified（mini） |

---

## 1. 能力声明

| 能力 | 说明 | 承载 | 层级 |
| --- | --- | --- | --- |
| CAP-1 分类 | 把失败归入稳定、跨包的类别 | `ErrorKind` | K |
| CAP-2 构造 | 创建简单错误，不依赖异常 | `BasicError` | K |
| CAP-3 结构化上下文 | 给错误附加 key/value 细节与原因链 | `ErrorDetail`、`BasicError` | K |
| CAP-4 步骤报告 | 记录“在哪一步失败”，不改变错误分类 | `ErrorReport`、`toErrorReport`、`annotate` | K |
| CAP-5 聚合 | 一次返回多个失败 | `ErrorGroup` | K |
| CAP-6 Result 组合 | 对 `Result` 做同类型映射/串联/兜底 | `mapOk`、`mapErr`、`andThen`、`unwrapOr`、`check` | K |
| CAP-7 重试分类 | 判断错误是否“通常可重试” | `isRetryable`、`isRetryableError` | K |
| CAP-8 FFI 映射 | L2 错误码与 `ErrorKind` 稳定转换 | `errorKindCode`、`errorKindFromCode` | K |
| CAP-9 收集/展平/映射 | `collectOk`、`flatten`、跨类型 `mapOk/mapErr` | 无 | K |

**非目标**：

- 不做日志输出（`xdk.log`）；
- 不做重试调度/退避；
- 不做异常栈/回溯；
- 不做本地化消息；
- 不把业务错误码塞进 `ErrorKind`（用 `code` 字符串）；
- 不重新定义 S4 的 `wrap` / `mapErr` / `report`。

---

## 2. 类型与文件

当前实现把以下声明放在一个 `Errors.x` 中；文件拆分是内部组织，不改变符号名：

| 目标文件 | 类型/函数 |
| --- | --- |
| `Errors.x` | `ErrorKind`、`Error`、`DetailedError`、`ErrorDetail` |
| `BasicError.x` | `BasicError` |
| `ErrorReport.x` | `ErrorReport`、`toErrorReport`、`annotate` |
| `ErrorGroup.x` | `ErrorGroup` |
| `ResultOps.x` | `mapOk`、`mapErr`、`andThen`、`unwrapOr`、`check` |
| `KindNames.x` | `errorKindName`、`errorKindFromName`、`errorKindCode`、`errorKindFromCode` |

> 单文件是当前编译器的包加载约束；多文件包加载完成后再拆，不能把“文件已拆”
> 当成阶段完成条件。

---

## 3. `ErrorKind`（enum，stable）

### 3.1 表示与不变量

- 14 个固定成员；不得由应用扩展。
- 每个值有稳定序号（0..13，用于 FFI/持久化）；序号一经发布不得改变。
- `ErrorKind` 是值语义；可比较、可作为 `Map` 键。

### 3.2 分类表

| 值 | 码 | 含义 | 默认可重试 | 备注 |
| --- | ---: | --- | --- | --- |
| `InvalidArgument` | 0 | 调用参数/状态不合法 | 否 | 调用方 bug |
| `NotFound` | 1 | 目标不存在 | 否 | 竞态策略由调用方定 |
| `AlreadyExists` | 2 | 目标已存在/重复创建 | 否 | 不用于重复 close |
| `PermissionDenied` | 3 | 权限不足 | 否 | 不应吞掉 |
| `Io` | 4 | 底层 I/O 失败 | 条件 | 由调用方按场景决定 |
| `Network` | 5 | 网络失败 | 是 |  不产生 |
| `Timeout` | 6 | 截止时间到 | 是 | 只由 deadline 产生 |
| `Cancelled` | 7 | 协作取消 | 否 | 必须向上传播 |
| `Busy` | 8 | 资源忙/队列满 | 是 | `trySend` 满等 |
| `Unavailable` | 9 | 暂时不可用/已关闭 | 是 | 关闭后操作常返回此值 |
| `DataCorrupted` | 10 | 数据损坏/编码非法 | 否 | 不可静默修复 |
| `Unsupported` | 11 | 平台/实现不支持 | 否 | 不用 `Internal` 代替 |
| `OutOfMemory` | 12 | 分配失败 | 否 | 观测路径不得再分配大对象 |
| `Internal` | 13 | 实现不变量被破坏 | 否 | 不是“没实现” |

### 3.3 关闭与 `AlreadyExists`

-  资源 `close()` 幂等：第一次成功关闭后，第二次返回 `Ok(unit)`，不做事。
- `AlreadyExists` 只表示创建/注册冲突，不用于重复 close。
- 关闭失败与未关闭是两种状态；`Err` 只报告诊断，不等于句柄未释放。

### 3.4 名称与代码契约

| 函数 | 签名 | 后置 | 失败 |
| --- | --- | --- | --- |
| `errorKindName` | `String errorKindName(ErrorKind kind)` | 稳定小写名（`invalid_argument`） | 无 |
| `errorKindFromName` | `Result<ErrorKind, Error> errorKindFromName(String name)` | 大小写不敏感匹配稳定名 | 未知 → `InvalidArgument` |
| `errorKindCode` | `Int errorKindCode(ErrorKind kind)` | 返回 0..13 | 无 |
| `errorKindFromCode` | `ErrorKind errorKindFromCode(Int code)` | 已知码映射 | 未知 → `Internal` |

- `errorKindCode` 使用 `Int`（32 位），不使用 `Int32` 别名。
- 未知 FFI 码映射 `Internal`，不 panic，不静默当成功。

---

## 4. `Error`（protocol，stable）

```text
protocol Error {
    ErrorKind kind()
    String describe()
}
```

- 与 S4 §2.2 完全一致；只有 `class` 可以实现。
- `kind()` 纯读取，生命周期内不变。
- `describe()` 单行、稳定、不含换行/控制字符；不包含结构化字段。
- `cause` 不是基础协议成员；原因链由 `BasicError.causes()` 暴露。

---

## 5. `DetailedError`（protocol，preview）

```text
protocol DetailedError {
    ErrorKind kind()
    String describe()
    String message()
    String code()
}
```

**冻结说明**：

- `DetailedError` 是**独立协议**，不继承 `Error`；实现类必须同时声明
  `implements Error, DetailedError`。这是为了避开当前编译器对泛型/协议继承
  和运行期 `is` 的缺口，不改变调用方的类型契约。
- `details()` / `causes()` 不在协议里；它们是 `BasicError`、`ErrorReport`、
  `ErrorGroup` 的**类方法**，因为当前编译器不支持协议方法返回 `List<...>`。
- `message()` 非空、单行、不含控制字符；`code()` 为空串或
  `[a-z0-9_.-]+`。
- `describe()` 的固定格式：
  - 有 `code`：`[code] KindName: message`
  - 无 `code`：`KindName: message`
  - `KindName` 使用枚举名（如 `NotFound`）。
-  的 `ErrorReport`/`ErrorGroup` 以 `BasicError` 为承载；自定义
  `DetailedError` 在聚合/报告前必须先转成 `BasicError`。这是  限制，
  不是永久语言限制。

---

## 6. `ErrorDetail`（class）

```text
class ErrorDetail {
    final String key
    final String value
    ErrorDetail(String key, String value)
}
```

| 项 | 契约 |
| --- | --- |
| 语义 | 不可变引用对象；key/value 构造后不变 |
| key | 非空；`[a-z0-9_.-]`；不得含 `:`/换行/控制字符 |
| value | 可为空；不得含换行/控制字符 |
| 排序 | 同一错误内保持插入顺序 |
| 用途 | 诊断/日志/报告；不得用于业务分支 |

- 构造器校验 key/value；非法为合同错误（panic）。
- `Result<ErrorDetail, Error> tryErrorDetail(String key, String value)`
  供外部输入使用；非法返回 `InvalidArgument`。
- 选择 class 而不是 struct：当前多文件/工具链的 `List<struct>` 支持不完整；
  class 的不可变字段仍满足  语义。

---

## 7. `BasicError`（class，stable）

### 7.1 表示

```text
class BasicError implements Error, DetailedError {
    ErrorKind _kind
    String _message
    String _code
    List<ErrorDetail> _details
    List<BasicError> _causes

    BasicError(ErrorKind kind, String message)

    ErrorKind kind()
    String message()
    String code()
    String describe()
    List<ErrorDetail> details()
    List<BasicError> causes()

    BasicError withCode(String code)
    BasicError withDetail(String key, String value)
    BasicError withCause(BasicError cause)
}
```

### 7.2 不变量

- `kind` 非空；`message` 非空（空串按 kind 名生成）。
- `code` 为空或匹配 `[a-z0-9_.-]+`。
- `_details`/`_causes` 在 `with*` 时复制；外部只能拿到快照。
- `_causes` 不含 `self`；最多 8 条；超出丢弃新增。
- `describe()` 格式见 §5。

### 7.3 构造与方法契约

| 方法 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- |
| `BasicError(kind, message)` | kind 合法 | code="", details=[], causes=[] | 无 | O(1) |
| `withCode(code)` | code 合法或空 | 返回新实例 | 非法 → panic | O(n) |
| `withDetail(key, value)` | key/value 合法 | 返回新实例，追加 detail | 非法 → panic | O(n) |
| `withCause(cause)` | cause 非 null、非 self | 返回新实例，追加 cause | null/self → panic | O(n) |

- 不提供“全量构造器”重载：当前编译器不支持构造器重载；用构造器 + `with*`
  组合。这个限制不改变语义。
- 构造函数不返回 `Result`；外部字符串先用 `isValidErrorCode`/`tryErrorDetail` 校验，再调用 `with*`。
- `tryWith*` 方法在当前 mini 代码生成上仍有缺口，归入 X blocked； 不提供假实现。

### 7.4 示例

```text
BasicError error = new BasicError(ErrorKind.NotFound, "config file missing")
    .withCode("config.missing")
    .withDetail("path", "app.conf")
print(error.describe())    // [config.missing] NotFound: config file missing
print(error.details().length()) // 1
```

---

## 8. `ErrorReport`（class，preview）

```text
class ErrorReport implements Error, DetailedError {
    ErrorReport(BasicError root)

    ErrorKind kind()
    String message()
    String code()
    String describe()
    List<ErrorDetail> details()
    List<BasicError> causes()
    List<String> steps()

    ErrorReport withStep(String step)
    Result<ErrorReport, Error> tryWithStep(String step)
}
```

- `root` 非空；`steps` 最多 16 条。
- `kind/message/code/describe` 委托根错误；`details()` 返回根 details 副本；
  `causes()` 返回 `[root]`。
- `steps()` 按加入顺序返回副本（第一条最靠近根）。
- `describe()`：`stepN -> ... -> step1 -> root.describe()`，单行。
- `withStep` 在 16 条时 panic；`tryWithStep` 返回 `InvalidArgument`，不静默丢弃。
- `toErrorReport(BasicError error)` 总是创建新报告；不嵌套检测（当前 `is`
  不可靠，不能用假语义做优化）。
- `annotate(BasicError error, String step)` = `toErrorReport(error).withStep(step)`。
- **不定义** `report(Error)`；S4 的 `report(Result<T,Error>)` 保持不变。

示例：

```text
ErrorReport report = annotate(error, "parse port").withStep("load config")
print(report.describe())    // load config -> parse port -> ...
```

---

## 9. `ErrorGroup`（class，preview）

```text
class ErrorGroup implements Error, DetailedError {
    ErrorGroup()
    void add(BasicError error)
    Int length()
    Bool isEmpty()
    BasicError? first()
    ErrorKind kind()
    String message()
    String code()
    String describe()
    List<ErrorDetail> details()
    List<BasicError> causes()
}
```

**聚合规则（冻结）**：

- 存储 `BasicError`；自定义 `DetailedError` 先转 `BasicError` 再 add。
- `add(error)` 要求非 null；`add(self)` 为合同错误（panic）。
- `kind()`：只要包含 `Cancelled` 就返回 `Cancelled`；否则返回第一个非
  `Cancelled`；空组返回 `InvalidArgument`。
- `message()`：`"N errors; first: <first.describe>"`；空组
  `"empty error group"`。
- `code()`：`""`。
- `details()`：聚合所有子错误 details，键加 `<index>.` 前缀（如 `0.path`）。
- `causes()`：子错误快照。
- `describe()`：单行摘要，最多列前 3 条；其余 `...`。
- 可变构建期类型，非线程安全；构建完成后只读共享需外部同步。

---

## 10. Result 组合（`ResultOps`）

| 函数 | 签名 | 语义 | 失败 |
| --- | --- | --- | --- |
| `mapOk` | `Result<U,E> mapOk<T,U,E>(Result<T,E> result, U(T) transform)` | Ok → Ok(transform(value))；Err 原样 | transform panic 由进程终止 |
| `mapErr` | `Result<T,F> mapErr<T,E,F>(Result<T,E> result, F(E) transformError)` | Ok 原样；Err → Err(transformError(error)) | 同上 |
| `andThen` | `Result<T,E> andThen<T,E>(Result<T,E> result, Result<T,E>(T) next)` | Ok → next(value)；Err 原样 | next 返回 Err 时传播 |
| `unwrapOr` | `T unwrapOr<T,E>(Result<T,E> result, T fallback)` | Ok → value；Err → fallback | 无 |
| `collectOk` | `Result<List<T>, ErrorGroup> collectOk<T>(List<Result<T,Error>> results)` | 全部 Ok → Ok(list)；否则 Err(所有错误) | 无 |
| `flatten` | `Result<T,E> flatten<T,E>(Result<Result<T,E>,E> nestedResult)` | 外层 Ok 取内层；外层 Err 原样 | 无 |
| `check` | `Result<Unit,Error> check(Bool condition, ErrorKind kind, String message)` | true → Ok(unit)；false → Err(BasicError) | 无 |

**冻结说明**：

- `mapOk<U>`/`mapErr<F>` 支持跨类型：编译器从 lambda 参数与返回表达式
  推断 `U`/`F`，覆盖字面量、二元表达式、`new`、`str`、类/协议方法和常见
  `Result`/`List`/`Map`/`Set` 成员。
- `andThen` 仍保持同类型 `Result<T,E>`，不改变 `T`/`E`。
- 复杂接收者表达式的返回值推断仍为 X；无法推断时显式拆辅助函数。
- `collectOk` 已通过 `xn_arr_r`（`List<Result<...>>`）落地；`flatten` 通过
  嵌套 Result 的类型分解和 boxing 落地（要求内层 Result 由函数返回，不写
  直接嵌套的 `Ok(Ok(...))` 表达式）。
- 回调必须是纯函数且不产生日志副作用；需要失败时返回 `Result`。

---

## 11. 重试分类与 FFI 映射

```text
Bool isRetryable(ErrorKind kind)
Bool isRetryableError(Error error)
```

- `Network/Timeout/Busy/Unavailable` → true；`Io` → false（条件重试由调用方判断）；
  其余 false。
- 不提供退避/次数/抖动。
- `errorKindCode(ErrorKind) -> Int`；`errorKindFromCode(Int) -> ErrorKind`。
- 映射表与 L2 `XRT_ERR_*` 对齐（0..13），发布后冻结。
- 未知码 → `Internal`；跨 FFI 不传 `Error` 对象，只传码 + 可选字符串。

---

## 12. 所有权、并发与生命周期

| 项 | 契约 |
| --- | --- |
| 所有权 | 错误对象是 GC 引用；方法借用，不消费 |
| close | 错误无资源，无 `close()` |
| 线程安全 | `BasicError`/`ErrorReport` 只读，可跨任务共享；`ErrorGroup` 可变，非线程安全 |
| 别名 | `details()`/`causes()`/`steps()` 返回快照 |
| 循环 | `BasicError` 不可变；`ErrorGroup.add(self)` panic |
| OOM | `OutOfMemory` 路径使用最小错误，不分配 details/causes |

---

## 13. 测试义务与场景

| 类别 | 断言 |
| --- | --- |
| 分类 | 14 个 kind 的名称/码/可重试性表驱动 |
| 构造 | 空消息归一、code/details/cause、非法输入的 checked 路径 |
| 报告 | 步骤顺序、16 条上限、tryWithStep 失败 |
| 聚合 | Cancelled 优先、首个非 Cancelled、空组、self 拒绝、details 前缀 |
| ResultOps | mapOk/mapErr/andThen/unwrapOr/check 的 Ok/Err 两侧 |
| FFI | 码→kind→码 往返；未知码 → Internal |
| 兼容 | S4 `wrap`/`report` 语义未变 |
| 反例 | 换行/控制字符被拒绝；describe 不含 details |

场景：

- `tests/xdk_errors.x`：基础分类。
- `tests/xdk_errors_full.x`：DetailedError/Report/Group/ResultOps/码表。
- `xdk.sh`：mini。
- `m10_parity.sh`：mini base/full。

---

## 14. 阶段交付与验收（-01）

- `Error` 保持 `kind/describe`；`DetailedError` 独立；
- `BasicError`、`ErrorDetail`、`ErrorReport`、`ErrorGroup`、ResultOps 与实现一致；
- `wrap`/`mapErr`/`report` 的 S4 语义未被改变；
- mini 场景通过；
- 文档、场景、回归、实现同批交付；批内条目不单独提交、不宣称包完成。

**已登记缺口**：

- 复杂接收者表达式的跨类型推断仍为 X；
- `xdk_errors_full.x` 为 mini 专用；没有第二引擎。
- 自定义 `DetailedError` 聚合： 先转 `BasicError`， 再泛化。

---

## 15. 评审结论（本包）

- `Error` 最小协议与 S4 一致；`DetailedError` 独立且可验证；
- `wrap`/`mapErr`/`report` 没有同名换义；
- 聚合/报告以 `BasicError` 为  承载，限制写清楚；
- 所有失败有明确通道：unchecked panic、checked `Result`；
- 没有“或/待定/严格版本”双义条目；blocked 项不是待定，是明确不支持。

下一阶段：`02-runtime.md`（诊断、退出、时钟、stdio、运行时信息）。
