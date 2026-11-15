// xdk.errors —— S6-06 源码单元（对齐 S4 错误处理标准）
// Tier: T0；依赖：xdk.runtime.diagnose；稳定性：stable。
// 约定：
//   - Error 协议：kind() + describe()（单行描述，不含控制字符）。
//   - ErrorKind 14 项为跨版本稳定集合（只追加）。
//   - wrap：失败丢弃原错误换新；mapErr：失败以调用方函数映射，二者均无日志副作用。
//   - report：失败时经 xdk.runtime.diagnose 输出 `[Kind] describe`（S4 §5 的单行格式），返回原 Result。
//   - cause：约定字段（Error?），由错误类型自带；协议不增成员。
package xdk.errors
import xdk.runtime.diagnose

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

protocol Error {
    ErrorKind kind();
    String describe();
}

// BasicError 在 BasicError.x；本单元保留协议、组合函数与重试建议。

// wrap：失败时丢弃原错误、返回新错误；成功原样通过。
Result<T, E> wrap<T, E>(Result<T, E> r, E err) {
    if (r.isErr()) {
        return Err(err)
    }
    return r
}

// mapErr：失败时用调用方函数映射错误；成功原样通过（转换无副作用）。
Result<T, E2> mapErr<T, E1, E2>(Result<T, E1> r, E2(E1) f) {
    if (r.isErr()) {
        return Err(f(r.error()))
    }
    return Ok(r.value())
}

// report：边界观测；失败单行输出 `[Kind] describe`，成功零输出；返回原 Result。
Result<T, Error> report<T>(Result<T, Error> r) {
    if (r.isErr()) {
        diagnose($"[{r.error().kind()}] {r.error().describe()}")
    }
    return r
}

// isRetryable：粗粒度重试建议；具体策略由调用方决定。
Bool isRetryable(ErrorKind kind) {
    if kind == ErrorKind.Network {
        return true
    }
    if kind == ErrorKind.Timeout {
        return true
    }
    if kind == ErrorKind.Busy {
        return true
    }
    if kind == ErrorKind.Unavailable {
        return true
    }
    return false
}
