// xdk.errors —— S6-06 源码单元（对齐 S4 错误处理标准）
// Tier: T0；依赖：xdk.runtime.diagnose；稳定性：stable。
//
// 约定：
//   - Error 协议只含 kind()/describe()（S4 §2.2）。
//   - DetailedError 是非泛型扩展协议：message/code/details/causes。
//   - ErrorKind 14 项为跨版本稳定集合（只追加）。
//   - wrap：失败丢弃原错误换新；mapErr：失败以调用方函数映射。
//   - report：失败时经 xdk.runtime.diagnose 输出 `[Kind] describe`。
//   - 步骤记录用 toErrorReport/annotate，不复用 wrap/report。
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

protocol DetailedError {
    ErrorKind kind();
    String describe();
    String message();
    String code();
}

class ErrorDetail {
    final String key
    final String value

    ErrorDetail(String key, String value) {
        if !isValidDetailKey(key) {
            throw "ErrorDetail: invalid key"
        }
        if !isValidDetailValue(value) {
            throw "ErrorDetail: invalid value"
        }
        self.key = key
        self.value = value
    }
}

Result<ErrorDetail, Error> tryErrorDetail(String key, String value) {
    if !isValidDetailKey(key) {
        return Err(new BasicError(ErrorKind.InvalidArgument, "invalid detail key"))
    }
    if !isValidDetailValue(value) {
        return Err(new BasicError(ErrorKind.InvalidArgument, "invalid detail value"))
    }
    return Ok(new ErrorDetail(key, value))
}

Bool isValidDetailKey(String key) {
    if key == "" {
        return false
    }
    Int index = 0
    while index < key.length() {
        String character = key.substring(index, 1)
        if !isLowerAsciiLetter(character) && !isAsciiDigit(character) &&
           character != "_" && character != "." && character != "-" {
            return false
        }
        index = index + 1
    }
    return true
}

Bool isValidDetailValue(String value) {
    if value.indexOf("\n") >= 0 || value.indexOf("\r") >= 0 || value.indexOf("\t") >= 0 {
        return false
    }
    return true
}

Bool isValidErrorCode(String code) {
    if code == "" {
        return true
    }
    Int index = 0
    while index < code.length() {
        String character = code.substring(index, 1)
        if !isLowerAsciiLetter(character) && !isAsciiDigit(character) &&
           character != "_" && character != "." && character != "-" {
            return false
        }
        index = index + 1
    }
    return true
}

static Bool isLowerAsciiLetter(String character) {
    return character == "a" || character == "b" || character == "c" ||
        character == "d" || character == "e" || character == "f" ||
        character == "g" || character == "h" || character == "i" ||
        character == "j" || character == "k" || character == "l" ||
        character == "m" || character == "n" || character == "o" ||
        character == "p" || character == "q" || character == "r" ||
        character == "s" || character == "t" || character == "u" ||
        character == "v" || character == "w" || character == "x" ||
        character == "y" || character == "z"
}

static Bool isUpperAsciiLetter(String character) {
    return character == "A" || character == "B" || character == "C" ||
        character == "D" || character == "E" || character == "F" ||
        character == "G" || character == "H" || character == "I" ||
        character == "J" || character == "K" || character == "L" ||
        character == "M" || character == "N" || character == "O" ||
        character == "P" || character == "Q" || character == "R" ||
        character == "S" || character == "T" || character == "U" ||
        character == "V" || character == "W" || character == "X" ||
        character == "Y" || character == "Z"
}

static Bool isAsciiDigit(String character) {
    return character == "0" || character == "1" || character == "2" ||
        character == "3" || character == "4" || character == "5" ||
        character == "6" || character == "7" || character == "8" ||
        character == "9"
}

// wrap：失败时丢弃原错误、返回新错误；成功原样通过。
Result<T, E> wrap<T, E>(Result<T, E> result, E error) {
    if result.isErr() {
        return Err(error)
    }
    return result
}

// report：边界观测；失败单行输出 `[Kind] describe`，成功零输出；返回原 Result。
Result<T, Error> report<T>(Result<T, Error> result) {
    if result.isErr() {
        diagnose($"[{errorKindDisplayName(result.error().kind())}] {result.error().describe()}")
    }
    return result
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

Bool isRetryableError(Error error) {
    return isRetryable(error.kind())
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

Result<ErrorKind, Error> errorKindFromName(String name) {
    String lower = toLowerAscii(name)
    if lower == "invalid_argument" { return Ok(ErrorKind.InvalidArgument) }
    if lower == "not_found" { return Ok(ErrorKind.NotFound) }
    if lower == "already_exists" { return Ok(ErrorKind.AlreadyExists) }
    if lower == "permission_denied" { return Ok(ErrorKind.PermissionDenied) }
    if lower == "io" { return Ok(ErrorKind.Io) }
    if lower == "network" { return Ok(ErrorKind.Network) }
    if lower == "timeout" { return Ok(ErrorKind.Timeout) }
    if lower == "cancelled" { return Ok(ErrorKind.Cancelled) }
    if lower == "busy" { return Ok(ErrorKind.Busy) }
    if lower == "unavailable" { return Ok(ErrorKind.Unavailable) }
    if lower == "data_corrupted" { return Ok(ErrorKind.DataCorrupted) }
    if lower == "unsupported" { return Ok(ErrorKind.Unsupported) }
    if lower == "out_of_memory" { return Ok(ErrorKind.OutOfMemory) }
    if lower == "internal" { return Ok(ErrorKind.Internal) }
    return Err(new BasicError(ErrorKind.InvalidArgument, "unknown error kind"))
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
    return ErrorKind.Internal
}

static String toLowerAscii(String text) {
    String result = ""
    Int index = 0
    while index < text.length() {
        String character = text.substring(index, 1)
        if isUpperAsciiLetter(character) {
            result = result + lowerAscii(character)
        } else {
            result = result + character
        }
        index = index + 1
    }
    return result
}

static String lowerAscii(String character) {
    if character == "A" { return "a" }
    if character == "B" { return "b" }
    if character == "C" { return "c" }
    if character == "D" { return "d" }
    if character == "E" { return "e" }
    if character == "F" { return "f" }
    if character == "G" { return "g" }
    if character == "H" { return "h" }
    if character == "I" { return "i" }
    if character == "J" { return "j" }
    if character == "K" { return "k" }
    if character == "L" { return "l" }
    if character == "M" { return "m" }
    if character == "N" { return "n" }
    if character == "O" { return "o" }
    if character == "P" { return "p" }
    if character == "Q" { return "q" }
    if character == "R" { return "r" }
    if character == "S" { return "s" }
    if character == "T" { return "t" }
    if character == "U" { return "u" }
    if character == "V" { return "v" }
    if character == "W" { return "w" }
    if character == "X" { return "x" }
    if character == "Y" { return "y" }
    if character == "Z" { return "z" }
    return character
}

// xdk.errors —— 基础错误类型（T0）
// Tier: T0；依赖：无（随 xdk.errors 编入）；稳定性：stable。

// 不可变错误值；with* 返回新实例。
class BasicError implements Error, DetailedError {
    ErrorKind _kind
    String _message
    String _code = ""
    List<ErrorDetail> _details = []
    List<BasicError> _causes = []

    BasicError(ErrorKind kind, String message) {
        self._kind = kind
        if message == "" {
            self._message = errorKindDisplayName(kind)
        } else {
            self._message = message
        }
    }

    ErrorKind kind() {
        return self._kind
    }

    String message() {
        return self._message
    }

    String code() {
        return self._code
    }

    List<ErrorDetail> details() {
        List<ErrorDetail> result = []
        Int index = 0
        while index < self._details.length() {
            result.push(self._details.get(index))
            index = index + 1
        }
        return result
    }

    List<BasicError> causes() {
        List<BasicError> result = []
        Int index = 0
        while index < self._causes.length() {
            result.push(self._causes.get(index))
            index = index + 1
        }
        return result
    }

    String describe() {
        String prefix = ""
        if self._code != "" {
            prefix = "[" + self._code + "] "
        }
        return prefix + errorKindDisplayName(self._kind) + ": " + self._message
    }

    BasicError withCode(String code) {
        if !isValidErrorCode(code) {
            throw "BasicError.withCode: invalid code"
        }
        BasicError result = new BasicError(self._kind, self._message)
        result._code = code
        result._details = self.details()
        result._causes = self.causes()
        return result
    }

    BasicError withDetail(String key, String value) {
        BasicError result = new BasicError(self._kind, self._message)
        result._code = self._code
        result._details = self.details()
        result._details.push(new ErrorDetail(key, value))
        result._causes = self.causes()
        return result
    }

    BasicError withCause(BasicError cause) {
        if cause == self {
            throw "BasicError.withCause: self cause"
        }
        BasicError result = new BasicError(self._kind, self._message)
        result._code = self._code
        result._details = self.details()
        result._causes = self.causes()
        if result._causes.length() < 8 {
            result._causes.push(cause)
        }
        return result
    }

}

// xdk.errors —— 错误步骤报告（T0）
// Tier: T0；依赖：xdk.errors；稳定性：preview。

class ErrorReport implements Error, DetailedError {
    BasicError _root
    List<String> _steps = []

    ErrorReport(BasicError root) {
        self._root = root
    }

    ErrorKind kind() {
        return self._root.kind()
    }

    String message() {
        return self._root.message()
    }

    String code() {
        return self._root.code()
    }

    List<ErrorDetail> details() {
        return self._root.details()
    }

    List<BasicError> causes() {
        List<BasicError> result = []
        result.push(self._root)
        return result
    }

    String describe() {
        String result = ""
        Int index = self._steps.length() - 1
        while index >= 0 {
            result = result + self._steps.get(index) + " -> "
            index = index - 1
        }
        return result + self._root.describe()
    }

    List<String> steps() {
        List<String> result = []
        Int index = 0
        while index < self._steps.length() {
            result.push(self._steps.get(index))
            index = index + 1
        }
        return result
    }

    ErrorReport withStep(String step) {
        if !isValidStep(step) {
            throw "ErrorReport.withStep: invalid step"
        }
        if self._steps.length() >= 16 {
            throw "ErrorReport.withStep: too many steps"
        }
        ErrorReport result = new ErrorReport(self._root)
        result._steps = self.steps()
        result._steps.push(step)
        return result
    }

    Result<ErrorReport, Error> tryWithStep(String step) {
        if !isValidStep(step) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid report step"))
        }
        if self._steps.length() >= 16 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "too many report steps"))
        }
        return Ok(self.withStep(step))
    }
}

ErrorReport toErrorReport(BasicError error) {
    return new ErrorReport(error)
}

ErrorReport annotate(BasicError error, String step) {
    return toErrorReport(error).withStep(step)
}

static Bool isValidStep(String step) {
    if step == "" {
        return false
    }
    if step.indexOf("\n") >= 0 || step.indexOf("\r") >= 0 || step.indexOf("\t") >= 0 {
        return false
    }
    return true
}

// xdk.errors —— 错误聚合（T0）
// Tier: T0；依赖：xdk.errors；稳定性：preview。

class ErrorGroup implements Error, DetailedError {
    List<BasicError> _errors = []

    ErrorGroup() {
    }

    Void add(BasicError error) {
        if error == self {
            throw "ErrorGroup.add: self"
        }
        self._errors.push(error)
    }

    Int length() {
        return self._errors.length()
    }

    Bool isEmpty() {
        return self._errors.length() == 0
    }

    BasicError? first() {
        if self.isEmpty() {
            return null
        }
        return self._errors.get(0)
    }

    ErrorKind kind() {
        if self.isEmpty() {
            return ErrorKind.InvalidArgument
        }
        Bool sawCancelled = false
        ErrorKind firstKind = ErrorKind.InvalidArgument
        Bool hasFirst = false
        Int index = 0
        while index < self._errors.length() {
            BasicError error = self._errors.get(index)
            ErrorKind currentKind = error.kind()
            if currentKind == ErrorKind.Cancelled {
                sawCancelled = true
            } else if !hasFirst {
                firstKind = currentKind
                hasFirst = true
            }
            index = index + 1
        }
        if sawCancelled {
            return ErrorKind.Cancelled
        }
        if hasFirst {
            return firstKind
        }
        return ErrorKind.InvalidArgument
    }

    String message() {
        if self.isEmpty() {
            return "empty error group"
        }
        BasicError firstError = self._errors.get(0)
        return $"{self._errors.length()} errors; first: {firstError.describe()}"
    }

    String code() {
        return ""
    }

    List<ErrorDetail> details() {
        List<ErrorDetail> result = []
        Int index = 0
        while index < self._errors.length() {
            BasicError error = self._errors.get(index)
            List<ErrorDetail> childDetails = error.details()
            Int childIndex = 0
            while childIndex < childDetails.length() {
                ErrorDetail detail = childDetails.get(childIndex)
                String key = $"{index}." + detail.key
                result.push(new ErrorDetail(key, detail.value))
                childIndex = childIndex + 1
            }
            index = index + 1
        }
        return result
    }

    List<BasicError> causes() {
        List<BasicError> result = []
        Int index = 0
        while index < self._errors.length() {
            result.push(self._errors.get(index))
            index = index + 1
        }
        return result
    }

    String describe() {
        if self.isEmpty() {
            return "empty error group"
        }
        String result = ""
        Int limit = 3
        if self._errors.length() < limit {
            limit = self._errors.length()
        }
        Int index = 0
        while index < limit {
            if index > 0 {
                result = result + "; "
            }
            BasicError error = self._errors.get(index)
            result = result + error.describe()
            index = index + 1
        }
        if self._errors.length() > limit {
            result = result + " ..."
        }
        return result
    }
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

T unwrapOr<T, E>(Result<T, E> result, T fallback) {
    if result.isErr() {
        return fallback
    }
    return result.value()
}

Result<List<T>, ErrorGroup> collectOk<T>(List<Result<T, Error>> results) {
    List<T> values = []
    ErrorGroup group = new ErrorGroup()
    Int index = 0
    while index < results.length() {
        Result<T, Error> current = results.get(index)
        if current.isErr() {
            Error error = current.error()
            BasicError detailed = new BasicError(error.kind(), error.describe())
            group.add(detailed)
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

Result<T, E> flatten<T, E>(Result<Result<T, E>, E> nestedResult) {
    if nestedResult.isErr() {
        return Err(nestedResult.error())
    }
    return nestedResult.value()
}

Result<Unit, Error> check(Bool condition, ErrorKind kind, String message) {
    if condition {
        return Ok()
    }
    return Err(new BasicError(kind, message))
}
