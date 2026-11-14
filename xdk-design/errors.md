# xdk.errors 详细设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.errors` |
| Tier | T0 核心 |
| 稳定性 | `stable`（`BasicError` 与 `isRetryable` 为 `stable`；后续新增为次版本） |
| 依赖 | L2 诊断通道；不依赖其他 XDK 包 |
| 权威 | 本文件定义合同；符号级签名以 `api.tsv` 与后续源码为准 |

## 1. 包职责

- 定义错误协议 `Error` 与分类 `ErrorKind`；
- 提供基础错误类型 `BasicError`；
- 提供错误变换与观测：`wrap`、`mapErr`、`report`；
- 提供粗粒度重试判断：`isRetryable`。

不负责：日志级别与 sink（`xdk.log`）、任务取消机制（`xdk.tasks`）、FFI 错误码映射（`xdk` 绑定层与第 7 部分）。

## 2. 类型

### 2.1 `protocol Error`

```x
protocol Error {
    ErrorKind kind();
    String describe();
}
```

合同：

- `kind()` 在错误值生命周期内不变。
- `describe()` 返回单行文本；不含换行、制表符、NUL；同一错误多次调用结果相同。
- 协议不包含 `cause` 成员；原因链用约定字段 `cause: Error?` 表达。
- 实现者必须是 `class`（S2 §4.3：协议实现只限 `class`）；枚举/结构体可以作为错误类型 `E`，但不实现 `Error` 协议，不能直接 `report`。
- 错误类型不得持有 OS 资源句柄。

### 2.2 `enum ErrorKind`

```x
enum ErrorKind {
    InvalidArgument,
    NotFound,
    AlreadyExists,
    PermissionDenied,
    Io,
    Network,
    Timeout,
    Cancelled,
    Busy,
    Unavailable,
    DataCorrupted,
    Unsupported,
    OutOfMemory,
    Internal,
}
```

- 枚举项集合是跨版本承诺：只能追加，不得改名或删除。
- `Timeout` / `Cancelled` 的错误面见第 4 部分 §5；本包只提供分类。
- `OutOfMemory` 的观测不得分配内存。
- `Internal` 只表示“不该发生”的兜底；未知原生错误码映射为 `Internal`。

### 2.3 `class BasicError implements Error`

```x
final class BasicError implements Error {
    final ErrorKind _kind
    final String _message
    final Error? cause

    BasicError(final ErrorKind kind, final String message) {
        _kind = kind
        _message = message
    }
    BasicError(final ErrorKind kind, final String message, final Error cause) {
        _kind = kind
        _message = message
        self.cause = cause
    }

    ErrorKind kind() { return self._kind }
    String describe() { return self._message }
}
```

合同：

- 字段只读；构造后不可变。
- `message` 是单行文本；调用方负责不含敏感信息。
- `cause` 可为 `null`；原因链由调用方用 `mapErr` 组装。
- 该类是 `class` 而不是 `struct`：它持有 `String` / `Error?` 引用字段。
- `BasicError` 不替代具体错误类型；需要结构化上下文的包应声明自己的错误类型。

### 2.4 `isRetryable(ErrorKind): Bool`

| 分类 | 可重试 |
| --- | --- |
| `Network`、`Timeout`、`Busy`、`Unavailable` | `true` |
| 其他 | `false` |

- 纯函数；不观测、不修改状态。
- 只是粗粒度建议；具体重试策略由调用方决定。

## 3. 函数

### 3.1 `wrap`

```x
<T,E>(Result<T,E>, E) -> Result<T,E>
```

- 成功：原样返回，不调用/不读取新错误。
- 失败：丢弃原错误，返回 `Err(newError)`。
- 用于把内部分类错误转换为对外契约错误；丢弃原因是显式决定。
- 不产生日志、不观测、不分配额外对象（除新错误本身）。

### 3.2 `mapErr`

```x
<T,E1,E2>(Result<T,E1>, (E1) -> E2) -> Result<T,E2>
```

- 成功：原样返回，**不调用**转换函数。
- 失败：返回 `Err(f(oldError))`。
- 转换函数必须纯净：不得产生日志、I/O、全局状态修改。
- 保留原因链时，在 `f` 内用 `BasicError(kind, message, oldError)` 或自定义错误类型组装。

### 3.3 `report`

```x
<T>(Result<T, Error>) -> Result<T, Error>
```

- 只接受错误类型为 `Error` 的 `Result`；具体错误类型在边界用 `mapErr` 转成 `Error`（`class` 实现协议可上转），或用 `BasicError` 包装。
- 成功：原样返回，不输出。
- 失败：把 `kind()` 与 `describe()` 写成一行到诊断通道，返回**原 `Result` 不变**。
- 设计为返回原 `Result`，支持 `return report(r)` 链式写法；观测不是处理，错误仍必须传播或显式处置。
- 每次调用都会输出；不得在循环中重复 report 同一错误。
- 诊断输出不得包含敏感信息；`describe()` 的内容由错误类型负责。

## 4. 错误面规则

| 情形 | 路径 |
| --- | --- |
| 参数非法、目标缺失、权限、网络、超时、取消 | `Result` / `Err` |
| 编程错误（空引用、越界、失败的 `as`、除零） | panic / fatal |
| 分配失败 | fatal；`OutOfMemory` 可用于观测 |
| 未知原生错误码 | `Internal`，不得映射为 `Ok` |

`xdk.errors` 的函数本身不做可恢复失败：`wrap` / `mapErr` / `report` 不返回新的 `Result` 错误；`report` 只写诊断。

## 5. 示例

```x
import xdk.errors

class ConfigError implements Error {
    final String path
    ConfigError(final String path) { self.path = path }
    ErrorKind kind() { return ErrorKind.NotFound }
    String describe() { return "config not found: " + self.path }
}

static Result<Int, Error> load(final String path) {
    if path.length() == 0 {
        return Err(BasicError(ErrorKind.InvalidArgument, "empty path"))
    }
    return Ok(1)
}

static Int main() {
    Result<Int, Error> r = load("app.conf")
    Result<Int, Error> mapped = mapErr(r, (e) -> BasicError(ErrorKind.Internal, e.describe(), e))
    if mapped.isErr() {
        return 1
    }
    return 0
}
```

## 6. 合同用例

| 编号 | 输入 | 期望 |
| --- | --- | --- |
| ERR-01 | `BasicError(NotFound, "x")` | `kind()` = `NotFound`；`describe()` = `"x"` |
| ERR-02 | 同一 `BasicError` 调用 `describe()` 两次 | 返回相同文本 |
| ERR-03 | `wrap(Ok(1), err)` | 返回 `Ok(1)`，不读取 `err` |
| ERR-04 | `wrap(Err(old), new)` | 返回 `Err(new)`，`old` 被丢弃 |
| ERR-05 | `mapErr(Ok(1), f)` | 返回 `Ok(1)`，`f` 不被调用 |
| ERR-06 | `mapErr(Err(old), f)` | 返回 `Err(f(old))` |
| ERR-07 | `report(Ok(1))` | 返回 `Ok(1)`，无输出 |
| ERR-08 | `report(Err(e))` | 输出一行含 `kind` 与 `describe()`；返回原 `Err(e)` |
| ERR-09 | `isRetryable(Network)` / `isRetryable(InvalidArgument)` | `true` / `false` |
| ERR-10 | 错误类型实现 `Error` 但 `describe()` 含换行 | 违反合同；由测试拒绝 |

## 7. 版本与兼容

- `Error` 协议成员固定；新增成员是主版本。
- `ErrorKind` 只能追加；新增项是次版本。
- `BasicError` 字段固定；新增字段是主版本。
- `wrap` / `mapErr` / `report` / `isRetryable` 签名固定；变更走主版本。
- 新增辅助函数是次版本。
