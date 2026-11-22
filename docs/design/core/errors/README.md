# `xdk.errors` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.errors` |
| 层 | `xdk.core` / L1 |
| 依赖 | `xdk.runtime.diagnose`（仅 `report` 使用） |
| 被依赖 | 所有 core/net/utils 包 |
| 稳定性 | 核心类型 `stable`；报告/重试/匹配 `preview` |
| 文档原则 | 本包所有设计、类、方法、技术、支撑、依赖、伪代码、场景、缺口都写在本文件 |

---

## 1. 包定位

`xdk.errors` 只解决失败如何表达、分类、聚合、观测、重试：

- 用 `Result` 表达可恢复失败；
- 用 `ErrorKind` 做粗分类；
- 用 `BasicError` 表达基础错误；
- 用 `ErrorReport` 记录步骤链；
- 用 `ErrorGroup` 聚合多个失败；
- 用 `RetryPolicy` / `RetryState` 做重试决策；
- 用 `ErrorSink` 做显式观测；
- 用 `ErrorCode` / `ErrorCodeRegistry` 管理稳定业务码。

不做：日志、重试循环/休眠、异常栈、i18n、全局错误处理器、业务错误继承体系。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 最小协议 | `Error` 只有 `kind`/`describe`；结构化信息放扩展协议/类 |
| 不可变错误 | 错误一旦创建，kind/message/code/details/causes 稳定 |
| 失败通道唯一 | `Result` / 合同错误 / 无失败，三选一 |
| 取消不可掩盖 | `ErrorGroup.kind()` 遇到 `Cancelled` 必须返回 `Cancelled` |
| 无全局状态 | 无全局错误处理器、全局码表、全局 sink |
| 无依赖环 | errors 不依赖 time/text/collections；重试用 `Long` 毫秒，不用 `Duration` |
| 显式观测 | Sink 由调用方持有，`reportTo` 才写入 |
| 业务码分离 | `ErrorKind` 是粗分类，`ErrorCode` 是稳定业务码 |

---

## 3. 类型总览

| 类型 | 种类 | 能力 | 稳定性 |
| --- | --- | --- | --- |
| `ErrorKind` | enum | 14 类跨包失败分类 | stable |
| `Error` | protocol | `kind` + `describe` | stable |
| `DetailedError` | protocol | `message` + `code` | stable |
| `ErrorDetail` | class | 不可变 key/value 细节 | stable |
| `BasicError` | class | 基础错误 + code/details/causes | stable |
| `ErrorReport` | class | 步骤链 | preview |
| `ErrorGroup` | class | 多错误聚合 | preview |
| `RetryPolicy` | class | 不可变重试策略 | preview |
| `RetryState` | class | 可变重试状态 | preview |
| `ErrorMatcher` | class | 错误匹配 | preview |
| `ErrorCollector` | class | 错误收集 | preview |
| `ErrorSink` | protocol | 显式观测出口 | preview |
| `DiagnosticErrorSink` | class | stderr 观测 | preview |
| `MemoryErrorSink` | class | 内存观测 | preview |
| `ErrorCode` | class | 稳定业务码 | preview |
| `ErrorCodeRegistry` | class | 显式码表 | preview |

---

## 4. 类设计索引

每个类/类型一个 PascalCase 文件；包级说明、顶层函数、场景、缺口保留在本 README。

| 类型 | 文件 |
| --- | --- |
| `ErrorKind` | [`ErrorKind.md`](ErrorKind.md) |
| `Error` | [`Error.md`](Error.md) |
| `DetailedError` | [`DetailedError.md`](DetailedError.md) |
| `ErrorDetail` | [`ErrorDetail.md`](ErrorDetail.md) |
| `BasicError` | [`BasicError.md`](BasicError.md) |
| `ErrorReport` | [`ErrorReport.md`](ErrorReport.md) |
| `ErrorGroup` | [`ErrorGroup.md`](ErrorGroup.md) |
| `RetryPolicy` | [`RetryPolicy.md`](RetryPolicy.md) |
| `RetryState` | [`RetryState.md`](RetryState.md) |
| `ErrorMatcher` | [`ErrorMatcher.md`](ErrorMatcher.md) |
| `ErrorCollector` | [`ErrorCollector.md`](ErrorCollector.md) |
| `ErrorSink` | [`ErrorSink.md`](ErrorSink.md) |
| `DiagnosticErrorSink` | [`DiagnosticErrorSink.md`](DiagnosticErrorSink.md) |
| `MemoryErrorSink` | [`MemoryErrorSink.md`](MemoryErrorSink.md) |
| `ErrorCode` | [`ErrorCode.md`](ErrorCode.md) |
| `ErrorCodeRegistry` | [`ErrorCodeRegistry.md`](ErrorCodeRegistry.md) |

## 5. 顶层函数 / ResultOps

### 1. 方法面

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `tryErrorDetail` | checked 细节 | key/value | `Result<ErrorDetail, Error>` | `InvalidArgument` |
| `isValidDetailKey` | 校验 key | key | `Bool` | 无 |
| `isValidDetailValue` | 校验 value | value | `Bool` | 无 |
| `isValidErrorCode` | 校验码 | code | `Bool` | 无 |
| `wrap` | 失败换新错误 | result/error | `Result<T,E>` | null → panic |
| `report` | 诊断观测 | result | `Result<T,Error>` | 无 |
| `reportTo` | 指定 sink 观测 | sink/result | `Result<T,Error>` | sink null → panic |
| `toErrorReport` | 创建报告 | error | `ErrorReport` | null → panic |
| `annotate` | 报告+一步 | error/step | `ErrorReport` | 非法 → panic |
| `isRetryable` | 分类建议 | kind | `Bool` | 无 |
| `isRetryableError` | 错误建议 | error | `Bool` | null → panic |
| `mapOk/mapErr/andThen/orElse/unwrapOr/expect/inspect/inspectErr/filterOk/collectOk/collectAll/flattenResult/check/mapBoth` | Result 组合 | 见伪代码 | 见伪代码 | 回调 panic 终止 |

### 2. 使用的技术

- Result 组合；
- 纯函数回调；
- 错误聚合；
- 临界失败 panic。

### 3. 需要的支撑

- 语言：泛型函数、Result、List、Bool、String、Int；
- 运行时：`diagnose`（report）；
- 接口：`ErrorGroup`、`BasicError`、`ErrorDetail`、`ErrorSink`。

### 4. 依赖的特性/接口/类

`ErrorGroup`、`BasicError`、`ErrorDetail`、`ErrorSink`、`Result`、`List`。

### 5. XNull 伪代码

```xnull
Result<ErrorDetail, Error> tryErrorDetail(String key, String value) {
    if !isValidDetailKey(key) {
        return Err(new BasicError(ErrorKind.InvalidArgument, "invalid detail key"))
    }
    if !isValidDetailValue(value) {
        return Err(new BasicError(ErrorKind.InvalidArgument, "invalid detail value"))
    }
    return Ok(new ErrorDetail(key, value))
}

Bool isValidErrorCode(String code) {
    if code == "" {
        return true
    }
    Int index = 0
    while index < code.length() {
        String character = code.substring(index, 1)
        if !isLowerAsciiLetter(character)
            && !isAsciiDigit(character)
            && character != "_"
            && character != "."
            && character != "-" {
            return false
        }
        index = index + 1
    }
    return true
}

Result<T, E> wrap<T, E>(Result<T, E> result, E error) {
    if error == null {
        throw "wrap: null error"
    }
    if result.isErr() {
        return Err(error)
    }
    return result
}

Result<T, Error> report<T>(Result<T, Error> result) {
    if result.isErr() {
        diagnose("[" + errorKindDisplayName(result.error().kind()) + "] " + result.error().describe())
    }
    return result
}

ErrorReport toErrorReport(BasicError error) {
    if error == null {
        throw "toErrorReport: null error"
    }
    return new ErrorReport(error)
}

ErrorReport annotate(BasicError error, String step) {
    return toErrorReport(error).withStep(step)
}

Bool isRetryableError(Error error) {
    if error == null {
        throw "isRetryableError: null error"
    }
    return isRetryable(error.kind())
}

Result<U, E> mapOk<T, U, E>(Result<T, E> result, U(T) transform) {
    if result.isErr() {
        return Err(result.error())
    }
    return Ok(transform(result.value()))
}

Result<T, F> mapErr<T, E, F>(Result<T, E> result, F(E) transformError) {
    if result.isErr() {
        return Err(transformError(result.error()))
    }
    return Ok(result.value())
}

Result<U, E> andThen<T, U, E>(Result<T, E> result, Result<U, E>(T) next) {
    if result.isErr() {
        return Err(result.error())
    }
    return next(result.value())
}

Result<T, E> orElse<T, E>(Result<T, E> result, Result<T, E>(E) fallback) {
    if result.isOk() {
        return result
    }
    return fallback(result.error())
}

T unwrapOr<T, E>(Result<T, E> result, T fallback) {
    if result.isOk() {
        return result.value()
    }
    return fallback
}

T expect<T, E>(Result<T, E> result, String message) {
    if result.isOk() {
        return result.value()
    }
    throw message
}

Result<T, E> inspect<T, E>(Result<T, E> result, void(T) callback) {
    if result.isOk() {
        callback(result.value())
    }
    return result
}

Result<T, E> inspectErr<T, E>(Result<T, E> result, void(E) callback) {
    if result.isErr() {
        callback(result.error())
    }
    return result
}

Result<T, E> filterOk<T, E>(Result<T, E> result, Bool(T) predicate, E error) {
    if error == null {
        throw "filterOk: null error"
    }
    if result.isOk() && !predicate(result.value()) {
        return Err(error)
    }
    return result
}

Result<U, F> mapBoth<T, U, E, F>(Result<T, E> result, U(T) onOk, F(E) onErr) {
    if result.isOk() {
        return Ok(onOk(result.value()))
    }
    return Err(onErr(result.error()))
}

Result<List<T>, ErrorGroup> collectOk<T>(List<Result<T, Error>> results) {
    List<T> values = []
    ErrorGroup group = new ErrorGroup()
    Int index = 0
    while index < results.length() {
        Result<T, Error> current = results.get(index)
        if current.isErr() {
            Error error = current.error()
            group.add(new BasicError(error.kind(), error.describe()))
        } else {
            values.push(current.value())
        }
        index = index + 1
    }
    if group.isEmpty() {
        return Ok(values)
    }
    return Err(group)
}

Result<List<T>, List<E>> collectAll<T, E>(List<Result<T, E>> results) {
    List<T> values = []
    List<E> errors = []
    Int index = 0
    while index < results.length() {
        Result<T, E> current = results.get(index)
        if current.isErr() {
            errors.push(current.error())
        } else {
            values.push(current.value())
        }
        index = index + 1
    }
    if errors.length() == 0 {
        return Ok(values)
    }
    return Err(errors)
}

Result<T, E> flattenResult<T, E>(Result<Result<T, E>, E> nestedResult) {
    if nestedResult.isErr() {
        return Err(nestedResult.error())
    }
    return nestedResult.value()
}

Result<Unit, Error> check(Bool condition, ErrorKind kind, String message) {
    if condition {
        return Ok(unit)
    }
    return Err(new BasicError(kind, message))
}
```

---

## 6. 场景

### E1：CLI 错误映射

参数缺失 → `InvalidArgument`；文件缺失 → `NotFound` + `withDetail("path",...)`；解析失败 → `DataCorrupted` + `withCode("input.invalid")`；输出 `report`；退出码按 kind 映射。

### E2：API 多字段校验

每个字段 `BasicError(InvalidArgument).withDetail("field",...)`；`ErrorCollector.addResult`；`toGroup()`；`ErrorGroup.details()` 带 `<index>.field`；Cancelled 优先。

### E3：批量采集

每个目标 `Result`；失败 `ErrorCollector.add`；成功结果列表；`toGroup()` 判断 `isEmpty`；`reportTo(MemoryErrorSink)` 断言。

### E4：重试

失败 → `RetryPolicy.shouldRetry(error, attempt)`；`RetryState.nextDelay(error)`；调用方 `time.sleepMs`；取消立即停止；耗尽返回最后错误。

### E5：错误观测

生产 `DiagnosticErrorSink`；测试 `MemoryErrorSink`；`reportTo` 不改变原 Result；sink 失败只诊断。

### E6：码表

启动 `ErrorCodeRegistry.register`；失败 `lookup`；`ErrorCode.toBasicError`；`all()` 导出；无全局单例。

---

## 7. 缺口与决策

| 项 | 决策/缺口 |
| --- | --- |
| 错误链环检测 | `BasicError` 拒绝 self；深度上限 8；不提供 `hasCycle` |
| `ErrorGroup` 自定义错误 | `ErrorGroup.addDetailed(DetailedError)` 是唯一转换点；只复制 kind/message/code；details/causes 不进入 T0 聚合 |
| `ErrorReport` 转 BasicError | steps 不进入 BasicError；调用方先 `describe()`/日志 |
| `MemoryErrorSink` 结构化字段 | 只存 `BasicError(kind,describe)`；丢失自定义字段 |
| `ErrorSink` 线程安全 | 实现声明；默认非线程安全 |
| `RetryPolicy` 按码重试 |  只按 `ErrorKind`；按码重试为 X |
| 全局码表 | 禁止；应用显式持有 Registry |
| `collectAll` 错误类型 | 返回 `List<E>`；不聚合 |
| `ErrorKind` 扩展 | 只允许追加；新码需版本决策 |

## 9. 1.x 兼容合同（C7）

| 1.x API | 2.x 合同 | 失败/边界 |
| --- | --- | --- |
| `BasicError.tryWithCode(String)` | [`BasicError.md`](BasicError.md) 同名；非法 code → `InvalidArgument` | 不修改原实例 |
| `BasicError.tryWithDetail(String, String)` | `tryWithDetail`；非法 key/value 或超 64 → `InvalidArgument` | 不修改原实例 |
| `BasicError.tryWithCause(BasicError)` | `tryWithCause`；null/self/超 8 → `InvalidArgument` | 不修改原实例 |
| `ErrorReport.tryWithStep(String)` | [`ErrorReport.md`](ErrorReport.md) 同名；非法/超 16 → `InvalidArgument` | 不修改原报告 |
| `ErrorGroup.addDetailed(DetailedError)` | [`ErrorGroup.md`](ErrorGroup.md) 同名；经 `basicErrorOf` 转 `BasicError` | null → panic；只复制 kind/message/code |
| `collectOk` / `report` / `toErrorReport` / `annotate` | 见 §5 顶层函数表 | 保持 1.x 语义 |

示例：

```xnull
Result<BasicError, Error> coded = error.tryWithCode("value.invalid")
ErrorGroup group = new ErrorGroup()
group.addDetailed(customDetailedError)
ErrorReport report = toErrorReport(error).withStep("load config")
```

测试义务：`tryWith*` 成功/失败两侧；`addDetailed` 自定义错误转换；`Cancelled` 优先；`collectOk` 聚合；`report` 不改变 Result；`toErrorReport`/`annotate` 步骤顺序。
