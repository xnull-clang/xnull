# `ErrorKind`

### 1. 定位

跨包、粗粒度、稳定的失败分类。用于重试建议、退出码映射、日志级别、边界转换；不用于业务细分支。

### 2. 表示与不变量

| 成员 | 码 | 含义 | 默认可重试 |
| --- | ---: | --- | --- |
| `InvalidArgument` | 0 | 参数/状态非法 | 否 |
| `NotFound` | 1 | 目标不存在 | 否 |
| `AlreadyExists` | 2 | 已存在/重复创建 | 否 |
| `PermissionDenied` | 3 | 权限不足 | 否 |
| `Io` | 4 | I/O 失败 | 条件 |
| `Network` | 5 | 网络失败 | 是 |
| `Timeout` | 6 | 截止时间到 | 是 |
| `Cancelled` | 7 | 协作取消 | 否 |
| `Busy` | 8 | 资源忙/队列满 | 是 |
| `Unavailable` | 9 | 暂时不可用/已关闭 | 是 |
| `DataCorrupted` | 10 | 数据损坏 | 否 |
| `Unsupported` | 11 | 不支持 | 否 |
| `OutOfMemory` | 12 | 分配失败 | 否 |
| `Internal` | 13 | 内部不变量破坏 | 否 |

不变量：14 项固定；只允许追加；码 0..13 固定；值语义，可作 Map 键。

### 3. 使用的技术

- 枚举值语义；
- 稳定码表；
- 名称表；
- 重试分类表。

### 4. 需要的支撑

- 语言：enum、Int、String、List；
- 运行时：无；
- 接口：无。

### 5. 依赖的特性/接口/类

无。`ErrorKind` 是 errors 包最底层类型。

### 6. 方法面

`ErrorKind` 没有实例方法。操作由顶层函数提供：

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `errorKindName` | 稳定小写名 | `ErrorKind kind` | `String` | 无 |
| `errorKindDisplayName` | 显示名 | `ErrorKind kind` | `String` | 无 |
| `errorKindCode` | 码 | `ErrorKind kind` | `Int` | 无 |
| `errorKindFromCode` | 码 → kind | `Int code` | `ErrorKind` | 无（未知 → Internal） |
| `errorKindFromName` | 名 → kind | `String name` | `Result<ErrorKind, Error>` | `InvalidArgument` |
| `isRetryable` | 是否可重试 | `ErrorKind kind` | `Bool` | 无 |

### 7. XNull 伪代码

```xnull
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

String errorKindName(ErrorKind kind) {
    if kind == ErrorKind.InvalidArgument { return "invalid_argument" }
    if kind == ErrorKind.NotFound { return "not_found" }
    if kind == ErrorKind.AlreadyExists { return "already_exists" }
    if kind == ErrorKind.PermissionDenied { return "permission_denied" }
    if kind == ErrorKind.Io { return "io" }
    if kind == ErrorKind.Network { return "network" }
    if kind == ErrorKind.Timeout { return "timeout" }
    if kind == ErrorKind.Cancelled { return "cancelled" }
    if kind == ErrorKind.Busy { return "busy" }
    if kind == ErrorKind.Unavailable { return "unavailable" }
    if kind == ErrorKind.DataCorrupted { return "data_corrupted" }
    if kind == ErrorKind.Unsupported { return "unsupported" }
    if kind == ErrorKind.OutOfMemory { return "out_of_memory" }
    return "internal"
}

String errorKindDisplayName(ErrorKind kind) {
    if kind == ErrorKind.InvalidArgument { return "InvalidArgument" }
    if kind == ErrorKind.NotFound { return "NotFound" }
    if kind == ErrorKind.AlreadyExists { return "AlreadyExists" }
    if kind == ErrorKind.PermissionDenied { return "PermissionDenied" }
    if kind == ErrorKind.Io { return "Io" }
    if kind == ErrorKind.Network { return "Network" }
    if kind == ErrorKind.Timeout { return "Timeout" }
    if kind == ErrorKind.Cancelled { return "Cancelled" }
    if kind == ErrorKind.Busy { return "Busy" }
    if kind == ErrorKind.Unavailable { return "Unavailable" }
    if kind == ErrorKind.DataCorrupted { return "DataCorrupted" }
    if kind == ErrorKind.Unsupported { return "Unsupported" }
    if kind == ErrorKind.OutOfMemory { return "OutOfMemory" }
    return "Internal"
}

Int errorKindCode(ErrorKind kind) {
    if kind == ErrorKind.InvalidArgument { return 0 }
    if kind == ErrorKind.NotFound { return 1 }
    if kind == ErrorKind.AlreadyExists { return 2 }
    if kind == ErrorKind.PermissionDenied { return 3 }
    if kind == ErrorKind.Io { return 4 }
    if kind == ErrorKind.Network { return 5 }
    if kind == ErrorKind.Timeout { return 6 }
    if kind == ErrorKind.Cancelled { return 7 }
    if kind == ErrorKind.Busy { return 8 }
    if kind == ErrorKind.Unavailable { return 9 }
    if kind == ErrorKind.DataCorrupted { return 10 }
    if kind == ErrorKind.Unsupported { return 11 }
    if kind == ErrorKind.OutOfMemory { return 12 }
    return 13
}

ErrorKind errorKindFromCode(Int code) {
    if code == 0 { return ErrorKind.InvalidArgument }
    if code == 1 { return ErrorKind.NotFound }
    if code == 2 { return ErrorKind.AlreadyExists }
    if code == 3 { return ErrorKind.PermissionDenied }
    if code == 4 { return ErrorKind.Io }
    if code == 5 { return ErrorKind.Network }
    if code == 6 { return ErrorKind.Timeout }
    if code == 7 { return ErrorKind.Cancelled }
    if code == 8 { return ErrorKind.Busy }
    if code == 9 { return ErrorKind.Unavailable }
    if code == 10 { return ErrorKind.DataCorrupted }
    if code == 11 { return ErrorKind.Unsupported }
    if code == 12 { return ErrorKind.OutOfMemory }
    if code == 13 { return ErrorKind.Internal }
    return ErrorKind.Internal
}

Result<ErrorKind, Error> errorKindFromName(String name) {
    String normalized = toLowerAscii(name)
    if normalized == "invalid_argument" { return Ok(ErrorKind.InvalidArgument) }
    if normalized == "not_found" { return Ok(ErrorKind.NotFound) }
    if normalized == "already_exists" { return Ok(ErrorKind.AlreadyExists) }
    if normalized == "permission_denied" { return Ok(ErrorKind.PermissionDenied) }
    if normalized == "io" { return Ok(ErrorKind.Io) }
    if normalized == "network" { return Ok(ErrorKind.Network) }
    if normalized == "timeout" { return Ok(ErrorKind.Timeout) }
    if normalized == "cancelled" { return Ok(ErrorKind.Cancelled) }
    if normalized == "busy" { return Ok(ErrorKind.Busy) }
    if normalized == "unavailable" { return Ok(ErrorKind.Unavailable) }
    if normalized == "data_corrupted" { return Ok(ErrorKind.DataCorrupted) }
    if normalized == "unsupported" { return Ok(ErrorKind.Unsupported) }
    if normalized == "out_of_memory" { return Ok(ErrorKind.OutOfMemory) }
    if normalized == "internal" { return Ok(ErrorKind.Internal) }
    return Err(new BasicError(ErrorKind.InvalidArgument, "unknown error kind: " + name))
}

Bool isRetryable(ErrorKind kind) {
    return kind == ErrorKind.Network
        || kind == ErrorKind.Timeout
        || kind == ErrorKind.Busy
        || kind == ErrorKind.Unavailable
}
```

---
