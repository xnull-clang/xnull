// xdk.errors —— S6-06 源码单元（对齐 S4 已签行为）
// 约定：
//   - Error 协议：kind() + describe()（单行描述，不含控制字符）。
//   - ErrorKind 14 项为跨版本稳定集合（只追加）。
//   - wrap：失败丢弃原错误换新；mapErr：失败以调用方函数映射，二者均无日志副作用。
//   - report：失败时经 xdk.runtime.diagnose 输出 `[Kind] describe`（S4-OBS-01 已签格式），返回 void。
//   - cause：约定字段（Error?），由错误类型自带；协议不增成员。

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

// 带原因链的错误值：错误类型可复用，cause == null 表示无原因。
class CauseError implements Error {
    final ErrorKind errorKind;
    final String message;
    final Error? cause;

    CauseError(ErrorKind kind, String message, Error? cause) {
        self.errorKind = kind
        self.message = message
        self.cause = cause
    }

    ErrorKind kind() { return self.errorKind }

    String describe() { return self.message }
}

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

// report：边界观测；失败单行输出 `[Kind] describe`，成功零输出；返回 void。
void report<T>(Result<T, Error> r) {
    if (r.isErr()) {
        diagnose($"[{r.error().kind()}] {r.error().describe()}")
    }
}
