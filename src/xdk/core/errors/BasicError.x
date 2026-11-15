// xdk.errors —— 基础错误类型（T0）
// Tier: T0；依赖：无（随 xdk.errors 编入）；稳定性：stable。
package xdk.errors

// 带原因链的基础错误值；cause == null 表示无原因。
final class BasicError implements Error {
    final ErrorKind _kind
    final String _message
    final Error? cause

    BasicError(ErrorKind kind, String message) {
        _kind = kind
        _message = message
    }

    BasicError(ErrorKind kind, String message, Error cause) {
        _kind = kind
        _message = message
        self.cause = cause
    }

    ErrorKind kind() {
        return self._kind
    }

    String describe() {
        return self._message
    }
}
