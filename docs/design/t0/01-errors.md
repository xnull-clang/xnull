# xdk.errors —— T0 核心包详细设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.errors` |
| 层级 | T0 |
| 稳定性 | 核心 `stable`；扩展 `preview` |
| 依赖 | L2 诊断、L2 FFI 错误码（不依赖其他 T0 包） |
| 被依赖 | 所有 T0 包 |
| 对应源码 | `src/xdk/core/errors/Errors.x`、`BasicError.x`、`ErrorReport.x` |
| 阶段 | T0-01（E1–E4 四个可提交切片） |

---

## 1. 能力声明

`xdk.errors` 让调用方能够：

| 能力 | 说明 | 承载类型/函数 |
| --- | --- | --- |
| C1 分类 | 把失败归入稳定、跨包的类别 | `ErrorKind` |
| C2 构造 | 创建简单错误，不依赖异常 | `BasicError` |
| C3 结构化上下文 | 给错误附加 key/value 细节与原因链 | `ErrorDetail`、`BasicError.withDetail/withCause` |
| C4 包装与报告 | 在不丢失分类的前提下记录“在哪一步失败” | `ErrorReport`、`report`、`wrap` |
| C5 聚合 | 一次返回多个失败（校验、并行任务） | `ErrorGroup` |
| C6 Result 组合 | 对 `Result` 做 map/andThen/collect，不手写样板 | `mapResult`、`mapError`、`andThen`、`collectOk` |
| C7 重试分类 | 判断某错误是否“通常可重试” | `isRetryable` |
| C8 FFI 映射 | 在 L2 错误码与 `ErrorKind` 之间稳定转换 | `errorKindFromCode`、`errorKindCode` |

**非目标**：

- 不做日志输出（`xdk.log`）；
- 不做重试调度/退避（调用方或 T1）；
- 不做异常栈/回溯（语言不承诺）；
- 不做本地化消息（T1 i18n）；
- 不把业务错误码塞进 `ErrorKind`（用 `code` 字符串）。

---

## 2. 类型与文件

| 文件 | 类型/函数 | 公开性 |
| --- | --- | --- |
| `Errors.x` | `ErrorKind`、`Error`、`ErrorDetail`、`isRetryable`、`errorKindFromCode`、`errorKindCode` | 公开 |
| `BasicError.x` | `BasicError` | 公开 |
| `ErrorReport.x` | `ErrorReport`、`report`、`wrap` | 公开 |
| `ErrorGroup.x` | `ErrorGroup` | 公开 |
| `ResultOps.x` | `mapResult`、`mapError`、`andThen`、`unwrapOr`、`collectOk`、`flatten`、`check` | 公开 |
| `KindNames.x` | `errorKindName`、`errorKindFromName` | 公开（内部实现可合并） |

---

## 3. `ErrorKind`（enum）

### 3.1 表示与不变量

- 14 个固定成员；不得由应用扩展。
- 每个值有稳定序号（用于 FFI/持久化）；序号一经发布不得改变。
- `ErrorKind` 是值语义；可比较、可作为 Map 键。

### 3.2 分类表

| 值 | 含义 | 典型产生者 | 默认可重试 | 备注 |
| --- | --- | --- | --- | --- |
| `InvalidArgument` | 调用参数/状态不合法 | 所有包的前置检查 | 否 | 调用方 bug，不应自动重试 |
| `NotFound` | 目标不存在 | fs、resource | 否 | 可能出现竞态，策略由调用方定 |
| `AlreadyExists` | 目标已存在/重复创建 | fs、tasks | 否 | 含“重复 close”合同错误 |
| `PermissionDenied` | 权限不足 | fs、sys | 否 | 不应吞掉 |
| `Io` | 底层 I/O 失败 | fs、io | 条件 | 由调用方按场景决定 |
| `Network` | 网络失败 | T1 net | 是 | 首版 T0 不产生 |
| `Timeout` | 截止时间到 | tasks、io | 是 | 只由 deadline 产生 |
| `Cancelled` | 协作取消 | tasks、所有可阻塞点 | 否 | 必须向上传播 |
| `Busy` | 资源忙/队列满 | sync | 是 | `trySend` 满等 |
| `Unavailable` | 暂时不可用/已关闭 | io、fs、sync | 是 | 关闭后操作常返回此值 |
| `DataCorrupted` | 数据损坏/编码非法 | text、bytes | 否 | 不可静默修复 |
| `Unsupported` | 平台/实现不支持 | sys、io | 否 | 不用 `Internal` 代替 |
| `OutOfMemory` | 分配失败 | L2 | 否 | 不应伪装成 Io |
| `Internal` | 实现不变量被破坏 | 所有包 | 否 | 不是“没实现” |

### 3.3 契约

| 方法/函数 | 签名 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- | --- |
| `errorKindName` | `String errorKindName(ErrorKind)` | 无 | 返回稳定小写名（`invalid_argument` 等） | 无 | O(1) |
| `errorKindFromName` | `Result<ErrorKind, Error> errorKindFromName(String)` | 无 | 大小写不敏感匹配；未知 → `InvalidArgument` | `InvalidArgument` | O(1) |
| `errorKindCode` | `Int32 errorKindCode(ErrorKind)` | 无 | 返回稳定 FFI 码 | 无 | O(1) |
| `errorKindFromCode` | `ErrorKind errorKindFromCode(Int32)` | 无 | 未知码 → `Internal`，不 panic | 无 | O(1) |

---

## 4. `Error`（protocol）

### 4.1 能力声明

`Error` 是**只读、可观察**的失败值。任何跨包错误边界只依赖它；调用方不得
对具体错误类做类型判断来决定业务分支。

### 4.2 协议

```text
protocol Error {
    ErrorKind kind()
    String message()
    String code()                 // 稳定机器码；无则 ""
    List<ErrorDetail> details()    // 有序、只读快照
    List<Error> causes()           // 直接原因；无则空
    String describe()              // 单行人类可读文本
}
```

### 4.3 方法契约

| 方法 | 前置 | 后置 | 说明 |
| --- | --- | --- | --- |
| `kind()` | 无 | 返回稳定分类；不得返回 null | 纯读取；不得有副作用 |
| `message()` | 无 | 返回人类可读基础消息；不得为空 | 不含敏感数据；不含换行 |
| `code()` | 无 | 返回 `[a-z0-9_.-]*`；无则 `""` | 用于机器分支/指标；不用于显示 |
| `details()` | 无 | 返回不可变/只读列表；元素有序 | 调用方不得修改；实现可返回副本 |
| `causes()` | 无 | 返回直接原因列表；不得有环 | 原因链深度建议 ≤ 8，超过由实现截断 |
| `describe()` | 无 | 单行文本；包含 `kind` 与 `message` | 不得抛错；不得包含控制字符 |

### 4.4 不变量

- `kind()` 在一次错误对象的生命周期内不变。
- `causes()` 不得包含自身；实现必须检测/截断环。
- `details()`/`causes()` 返回的列表不得暴露内部可变状态。
- `describe()` 不得依赖当前时间、环境或全局状态。

---

## 5. `ErrorDetail`（struct）

### 5.1 表示

```text
struct ErrorDetail {
    String key
    String value
}
```

| 项 | 契约 |
| --- | --- |
| 值语义 | 复制即独立；无 close |
| key | 非空；建议 `[a-z0-9_.-]`；不得含 `:`/换行 |
| value | 可为空；不得含换行/控制字符 |
| 排序 | 由错误实现决定；同一错误内保持稳定顺序 |
| 用途 | 诊断/日志/报告；不得用于业务分支 |

### 5.2 构造

- 直接构造 `ErrorDetail(key, value)`；非法 key 由使用方（`BasicError.withDetail`）
  校验并返回 `InvalidArgument`，struct 本身不做隐式校验。

---

## 6. `BasicError`（class）

### 6.1 能力与表示

`BasicError` 是最常用的不可变错误实现：分类 + 消息 + 可选机器码 + 细节 + 原因。

```text
class BasicError implements Error {
    final ErrorKind kind
    final String message
    final String code
    final List<ErrorDetail> details
    final List<Error> causes

    BasicError(ErrorKind kind, String message)
    BasicError full(ErrorKind kind, String message, String code,
                    List<ErrorDetail> details, List<Error> causes)

    ErrorKind kind()
    String message()
    String code()
    List<ErrorDetail> details()
    List<Error> causes()
    String describe()

    BasicError withDetail(String key, String value)
    BasicError withCause(Error cause)
    BasicError withCode(String code)
}
```

### 6.2 不变量

- `kind` 非空；`message` 非空（空串按 `kind` 名生成，不保留空消息）。
- `code` 为空或匹配 `[a-z0-9_.-]+`。
- `details`/`causes` 构造时复制；之后不可变。
- `causes` 不含 `self`；总深度 ≤ 8（超出截断）。
- `describe()` 输出：`[code] KIND: message`（code 为空则 `KIND: message`），
  不包含 details 内容（details 由 `chainText`/日志展开）。

### 6.3 构造契约

| 构造 | 前置 | 后置 | 失败 |
| --- | --- | --- | --- |
| `BasicError(kind, message)` | `kind` 合法 | code="", details=[], causes=[] | 无（非法输入由调用方保证） |
| `BasicError.full(...)` | 同上；code 合法；列表非 null | 复制列表；截断原因深度 | 无（非法 code 归一为 ""） |

> 构造函数不返回 `Result`，避免“构造错误也要错误处理”的循环；非法输入在
> XDK 内部由调用方校验。公共 API 若接收外部字符串，使用 `withCode` 的严格版
> `tryWithCode`（返回 `Result`）。

### 6.4 方法契约

| 方法 | 前置 | 后置 | 失败 | 复杂度 | 并发 |
| --- | --- | --- | --- | --- | --- |
| `withDetail(key, value)` | key 非空、无控制字符 | 返回新实例；原实例不变；追加 detail | 非法 key → `InvalidArgument`（严格版） | O(n) 复制 | 只读安全 |
| `withCause(cause)` | cause 非 null、非 self | 返回新实例；追加 cause；深度截断 | 环/超深 → 截断 | O(n) | 只读安全 |
| `withCode(code)` | code 合法或空 | 返回新实例 | 非法 → 归一为 "" | O(n) | 只读安全 |
| `describe()` | 无 | 单行文本 | 无 | O(1) | 只读安全 |

### 6.5 示例

```text
Error e = new BasicError(ErrorKind.NotFound, "config file missing")
    .withCode("config.missing")
    .withDetail("path", "app.conf")
print(e.kind())        // NotFound
print(e.code())        // config.missing
print(e.describe())    // [config.missing] NOT_FOUND: config file missing
```

### 6.6 反例

- 把用户输入直接拼进 `message` 并包含换行 → 日志注入；
- 用 `describe()` 做 `if` 分支 → 文本变化导致逻辑变化；
- 在 `details` 里放密码/token → 泄漏；
- 修改 `details()` 返回的列表 → 破坏不可变契约。

---

## 7. `ErrorReport`（class）

### 7.1 能力

在不改变根错误分类的前提下，记录“经过了哪些步骤”，用于跨层传播和诊断。

```text
class ErrorReport implements Error {
    ErrorReport(Error root)
    ErrorReport wrap(String step)

    ErrorKind kind()
    String message()
    String code()
    List<ErrorDetail> details()
    List<Error> causes()
    String describe()
    String chainText()
}
```

### 7.2 不变量

- `root` 非空；`steps` 非空元素，最多 16 步（超出丢弃最内层并保留根）。
- `kind()` 永远等于 `root.kind()`；包装不得改变分类。
- `code()` 优先 `root.code()`；为空时返回 `""`。
- `describe()`：`step1 -> step2 -> root.describe()`；单行。
- `chainText()`：多行渲染 root 的 details；用于诊断输出；不用于业务判断。
- 不可变；`wrap` 返回新实例。

### 7.3 方法契约

| 方法 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- |
| `wrap(step)` | step 非空、无换行 | 返回新报告；步骤追加到最外层 | 非法 step → 原样返回/`InvalidArgument`（严格版） | O(n) |
| `kind()` | 无 | 等于 root.kind() | 无 | O(1) |
| `chainText()` | 无 | 多行文本；总长度上限 4096 | 无 | O(n) |

### 7.4 示例

```text
Result<Int, Error> r = parseInt(raw)
if r.isErr() {
    ErrorReport rep = report(r.error()).wrap("parse port").wrap("load config")
    print(rep.describe())   // load config -> parse port -> INVALID_ARGUMENT: ...
}
```

---

## 8. `ErrorGroup`（class）

### 8.1 能力

把多个错误作为一个错误返回（表单校验、批量任务、并行失败）。

```text
class ErrorGroup implements Error {
    ErrorGroup()
    Void add(Error e)
    Int length()
    Bool isEmpty()
    Error? first()
    List<ErrorKind> kinds()
    ErrorKind kind()
    String message()
    String code()
    List<ErrorDetail> details()
    List<Error> causes()
    String describe()
}
```

### 8.2 不变量与聚合规则

- `errors` 有序；`add` 追加；不复制错误对象（GC 引用）。
- `kind()` 规则：返回**第一个非 `Cancelled`** 的错误分类；若全部为
  `Cancelled` → `Cancelled`；空组 → `Internal`。
- `message()`：`"N error(s); first: <first.message>"`；空组为 `"empty error group"`。
- `describe()`：单行摘要，最多列前 3 条；其余以 `...` 省略。
- `details()`：聚合所有子错误 details，键加 `#<index>.` 前缀。
- `causes()`：返回子错误列表（只读快照）。
- 空组合法，但 `kind()==Internal`，调用方应避免返回空组。

### 8.3 方法契约

| 方法 | 前置 | 后置 | 失败 | 复杂度 | 并发 |
| --- | --- | --- | --- | --- | --- |
| `add(e)` | e 非 null | 追加；长度 +1 | null → 忽略或 `InvalidArgument`（固定为忽略并记录） | O(1) | 非线程安全 |
| `kind()` | 无 | 按聚合规则 | 无 | O(n) 首次 | 非线程安全 |
| `details()` | 无 | 新列表；不改内部 | 无 | O(total) | 非线程安全 |

> `ErrorGroup` 是可变构建期类型；构建完成后只读共享需外部同步。需要跨任务
> 聚合时，每个任务返回自己的错误，由父任务串行 `add`。

### 8.4 示例

```text
ErrorGroup g = new ErrorGroup()
g.add(new BasicError(ErrorKind.InvalidArgument, "name is empty"))
g.add(new BasicError(ErrorKind.InvalidArgument, "age < 0"))
Err(g)   // 调用方只看到 kind=InvalidArgument + 两条细节
```

---

## 9. Result 组合（`ResultOps.x`）

### 9.1 函数契约

| 函数 | 签名 | 前置 | 后置 | 失败 |
| --- | --- | --- | --- | --- |
| `mapResult` | `Result<U,E> mapResult<T,U,E>(Result<T,E> r, U(T) f)` | f 纯函数（建议） | Ok → Ok(f(v))；Err → 原样 | f 抛错由语言边界处理 |
| `mapError` | `Result<T,F> mapError<T,E,F>(Result<T,E> r, F(E) f)` | f 不返回 null | Ok → 原样；Err → Err(f(e)) | f 抛错由语言边界处理 |
| `andThen` | `Result<U,E> andThen<T,U,E>(Result<T,E> r, Result<U,E>(T) f)` | f 不返回 null | Ok → f(v)；Err → 原样 | 同左 |
| `unwrapOr` | `T unwrapOr<T,E>(Result<T,E> r, T fallback)` | 无 | Ok → value；Err → fallback | 无 |
| `collectOk` | `Result<List<T>, ErrorGroup> collectOk<T,E>(List<Result<T,E>> rs)` | 无 | 全部 Ok → Ok(list)；否则 Err(所有错误) | 无 |
| `flatten` | `Result<T,E> flatten<T,E>(Result<Result<T,E>,E> r)` | 无 | 外层 Ok 取内层；外层 Err 原样 | 无 |
| `check` | `Result<Unit,Error> check(Bool cond, ErrorKind kind, String message)` | kind 合法 | true → Ok；false → Err(BasicError) | 无 |

### 9.2 设计说明

- 命名避免与语言内建 `Result` 成员冲突：统一用顶层函数 + `Result` 前缀/动词。
- `collectOk` 保留**所有**错误，不短路；这与并行任务/表单校验一致。
- `mapError` 不改变成功值；类型参数允许错误类型转换。
- 这些函数不引入新的错误分类；分类由调用方提供。

### 9.3 示例

```text
Result<Int, Error> a = parseInt("42")
Result<Int, Error> b = mapResult(a, (Int v) -> v + 1)
Int n = unwrapOr(b, 0)
```

---

## 10. 重试分类与 FFI 映射

### 10.1 重试

```text
Bool isRetryable(ErrorKind kind)
Bool isRetryable(Error e)
```

- 规则见 §3.2；`Io` 返回 false（条件重试由调用方判断），避免库替业务做决定。
- 不提供退避/次数/抖动；这些属于调用方或 T1。

### 10.2 FFI 错误码

```text
Int32 errorKindCode(ErrorKind kind)
ErrorKind errorKindFromCode(Int32 code)
```

映射表（与 L2 `XRT_ERR_*` 对齐，发布后冻结）：

| ErrorKind | L2 码 | 说明 |
| --- | --- | --- |
| InvalidArgument | 0 | L2 的 0 是“参数错误”，不是成功 |
| NotFound | 1 | |
| AlreadyExists | 2 | |
| PermissionDenied | 3 | |
| Io | 4 | |
| Network | 5 | |
| Timeout | 6 | |
| Cancelled | 7 | |
| Busy | 8 | |
| Unavailable | 9 | |
| DataCorrupted | 10 | |
| Unsupported | 11 | |
| OutOfMemory | 12 | |
| Internal | 13 | |

- 未知码 → `Internal`；`errorKindCode` 不产生未知码。
- 跨 FFI 不传递 `Error` 对象，只传码 + 可选字符串；XDK 负责还原。

---

## 11. 所有权、并发与生命周期

| 项 | 契约 |
| --- | --- |
| 所有权 | 错误对象是 GC 引用；方法借用，不消费；`Result.error()` 返回借用 |
| close | 错误无资源，无 `close()` |
| 线程安全 | `BasicError`/`ErrorReport` 构造后只读，可跨任务共享；`ErrorGroup` 可变，非线程安全 |
| 别名 | `details()`/`causes()` 返回只读快照；修改返回列表不影响错误 |
| 循环 | 原因链不得成环；实现必须截断 |
| 泄漏 | 错误持有 detail/cause 引用；长生命周期错误不应持有大对象（文档警告） |

---

## 12. 测试义务与场景

### 12.1 必须覆盖

| 类别 | 断言 |
| --- | --- |
| 分类 | 14 个 kind 的名称/码/可重试性表驱动 |
| 构造 | 空消息归一、非法 code 归一、details 复制 |
| 包装 | `wrap` 不改变 kind；步骤顺序正确；长度上限 |
| 聚合 | 优先级（首个非 Cancelled）、全 Cancelled、空组 |
| ResultOps | Ok/Err 两侧；`collectOk` 收集全部错误 |
| FFI | 码→kind→码 往返；未知码 → Internal |
| 反例 | 日志注入（换行/控制字符）被拒绝或转义 |
| 并发 | BasicError 跨任务只读；ErrorGroup 串行 add |

### 12.2 场景与回归

- `tests/xdk_errors.x`：扩展 wrap/report/group/collectOk/码映射。
- `xdk.sh`：mini + legacy 差分；错误文本稳定。
- `m10_parity.sh`：base/full 一致。
- 新增 `tests/xdk_errors_ffi.x`（或并入现有）：错误码往返。

---

## 13. 阶段切片（T0-01）

| 切片 | 交付 | 出口 |
| --- | --- | --- |
| E1 | `ErrorKind`、`Error`、`ErrorDetail`、`BasicError` | 现有错误场景不回归；kind 表测试 |
| E2 | `ErrorReport`、`report`、`wrap` | 包装不改变 kind；文本稳定 |
| E3 | `ErrorGroup`、`ResultOps` | 聚合/collectOk 场景 |
| E4 | FFI 码映射、重试分类 | 码往返；kind 表冻结 |

每一切片独立提交；E1 可以替换当前 `BasicError`，但必须保持
`kind()/describe()` 旧签名可用（迁移期兼容）。

---

## 14. 开放问题

1. **协议方法扩张**：当前 `Error` 只有 `kind()/describe()`；v1.1 增加
   `message/code/details/causes` 会破坏现有实现。方案：先加 `DetailedError`
   协议，或一次性迁移并在同一提交更新全部实现。需确认编译器对多协议实现的支持。
2. **错误码注册**：`code()` 的命名空间由谁拥有？建议包前缀（`fs.`、`net.`），
   跨包唯一性由评审保证，不引入全局注册表。
3. **原因链深度**：8 层是否足够？建议可配置但默认 8，避免日志爆炸。
4. **本地化**：`message()` 固定英文/源码语言？T0 不做 i18n；T1 通过错误码映射。
5. **ErrorGroup 可变性**：是否需要不可变 builder；首版用可变 + 文档约束。
6. **`describe()` 格式稳定性**：人类文本不做兼容承诺；机器分支只用 `kind/code`。

---

## 15. 评审结论（本包）

- 每个类均给出能力、表示、不变量、构造、方法前置/后置/失败/复杂度/并发；
- 每个失败点有 `ErrorKind`；
- 无资源/取消面（错误本身不阻塞）；
- 有示例、反例、测试义务、阶段切片；
- 满足 v1.1 类级设计标准。

下一步：按同一标准写 `04-bytes.md`（`Bytes`、`ByteBuffer`、`ByteReader`、
`ByteWriter` 的完整方法契约），随后 `06-collections.md`。
