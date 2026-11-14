// xdk.errors —— S6-06 源码单元（对齐 S4 已签行为）
// 约定：
//   - Error 协议：kind() + describe()（单行描述，不含控制字符）。
//   - ErrorKind 14 项为跨版本稳定集合（只追加）。
//   - wrap：失败丢弃原错误换新；mapErr：失败以调用方函数映射，二者均无日志副作用。
//   - report：失败时经 xdk.runtime.diagnose 输出 `[Kind] describe`（S4-OBS-01 已签格式），返回原 Result。
//   - cause：约定字段（Error?），由错误类型自带；协议不增成员。
package xdk.errors
import xdk.runtime.diagnose























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
