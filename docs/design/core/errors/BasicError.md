# `BasicError`

### 1. 定位

基础错误值：kind/message/code/details/causes；不可变；`with*` 返回新实例。

### 2. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_kind` | `ErrorKind` | final | 非空 |
| `_message` | `String` | final | 非空；空输入按 kind 显示名归一 |
| `_code` | `String` | final | 空或合法码 |
| `_details` | `List<ErrorDetail>` | 内部 | 最多 64 |
| `_causes` | `List<BasicError>` | 内部 | 最多 8；不含 self |

不变量：kind/message 非空；code 合法；details/causes 有上限；describe 单行。

### 3. 使用的技术

- 不可变对象 + copy-on-write；
- 快照列表；
- 原因链；
- 合同错误（panic）与 checked 双通道。

### 4. 需要的支撑

- 语言：class、protocol 实现、final 字段、List、String、Result、Int、Bool；
- 运行时：无（除 allocator）；
- 接口：`isValidErrorCode`、`errorKindDisplayName`、`ErrorDetail`、`ErrorMatcher`、`contains`。

### 5. 依赖的特性/接口/类

`ErrorKind`、`ErrorDetail`、`ErrorMatcher`、`isValidErrorCode`、`errorKindDisplayName`、`contains`、`List`、`Result`。

### 6. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `BasicError(kind,message)` | 构造 | kind；message（空归一） | `BasicError` | 无 |
| `kind/message/code/describe` | 读取 | 无 | 对应值 | 无 |
| `details/causes` | 快照 | 无 | 列表 | 无 |
| `hasCode/hasDetails/hasCauses` | 判定 | 无 | `Bool` | 无 |
| `detailCount/causeCount` | 数量 | 无 | `Int` | 无 |
| `withCode` / `tryWithCode` | 派生带码 | `String code` | `BasicError` / `Result` | 非法 → panic / `InvalidArgument` |
| `withMessage` | 派生消息 | `String message` | `BasicError` | 无 |
| `withDetail` / `tryWithDetail` | 追加细节 | key/value | `BasicError` / `Result` | 非法/超 64 → panic / `InvalidArgument` |
| `withDetails` / `tryWithDetails` | 追加多个 | `List<ErrorDetail>` | `BasicError` / `Result` | 非法/超限 → panic / `InvalidArgument` |
| `withCause` / `tryWithCause` | 追加原因 | `BasicError` | `BasicError` / `Result` | null/self/超 8 → panic / `InvalidArgument` |
| `withCauses` / `tryWithCauses` | 追加多个 | `List<BasicError>` | `BasicError` / `Result` | 非法/超限 → panic / `InvalidArgument` |
| `copy` | 复制 | 无 | `BasicError` | 无 |
| `rootCause` | 最深原因 | 无 | `BasicError` | 无 |
| `chain` | 原因链 | 无 | `List<BasicError>` | 无 |
| `matches` | 匹配 | `ErrorMatcher` | `Bool` | null → panic |

### 7. XNull 伪代码

```xnull
class BasicError implements Error, DetailedError {
    ErrorKind _kind
    String _message
    String _code = ""
    List<ErrorDetail> _details = []
    List<BasicError> _causes = []

    BasicError(ErrorKind kind, String message) {
        _kind = kind
        if message == "" {
            _message = errorKindDisplayName(kind)
        } else {
            _message = message
        }
    }

    ErrorKind kind() { return _kind }
    String message() { return _message }
    String code() { return _code }
    Bool hasCode() { return _code != "" }
    Bool hasDetails() { return _details.length() > 0 }
    Bool hasCauses() { return _causes.length() > 0 }
    Int detailCount() { return _details.length() }
    Int causeCount() { return _causes.length() }

    String describe() {
        String prefix = ""
        if _code != "" {
            prefix = "[" + _code + "] "
        }
        return prefix + errorKindDisplayName(_kind) + ": " + _message
    }

    List<ErrorDetail> details() {
        List<ErrorDetail> result = []
        Int index = 0
        while index < _details.length() {
            result.push(_details.get(index))
            index = index + 1
        }
        return result
    }

    List<BasicError> causes() {
        List<BasicError> result = []
        Int index = 0
        while index < _causes.length() {
            result.push(_causes.get(index))
            index = index + 1
        }
        return result
    }

    BasicError withCode(String code) {
        if !isValidErrorCode(code) {
            throw "BasicError.withCode: invalid code"
        }
        BasicError result = new BasicError(_kind, _message)
        result._code = code
        result._details = self.details()
        result._causes = self.causes()
        return result
    }

    Result<BasicError, Error> tryWithCode(String code) {
        if !isValidErrorCode(code) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid code"))
        }
        return Ok(self.withCode(code))
    }

    BasicError withMessage(String message) {
        BasicError result = new BasicError(_kind, message)
        result._code = _code
        result._details = self.details()
        result._causes = self.causes()
        return result
    }

    BasicError withDetail(String key, String value) {
        if _details.length() >= 64 {
            throw "BasicError.withDetail: too many details"
        }
        ErrorDetail detail = new ErrorDetail(key, value)
        BasicError result = new BasicError(_kind, _message)
        result._code = _code
        result._details = self.details()
        result._details.push(detail)
        result._causes = self.causes()
        return result
    }

    Result<BasicError, Error> tryWithDetail(String key, String value) {
        if _details.length() >= 64 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "too many details"))
        }
        if !isValidDetailKey(key) || !isValidDetailValue(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid detail"))
        }
        return Ok(self.withDetail(key, value))
    }

    BasicError withDetails(List<ErrorDetail> details) {
        if _details.length() + details.length() > 64 {
            throw "BasicError.withDetails: too many details"
        }
        BasicError result = new BasicError(_kind, _message)
        result._code = _code
        result._details = self.details()
        Int index = 0
        while index < details.length() {
            result._details.push(details.get(index))
            index = index + 1
        }
        result._causes = self.causes()
        return result
    }

    Result<BasicError, Error> tryWithDetails(List<ErrorDetail> details) {
        if _details.length() + details.length() > 64 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "too many details"))
        }
        return Ok(self.withDetails(details))
    }

    BasicError withCause(BasicError cause) {
        if cause == null {
            throw "BasicError.withCause: null"
        }
        if cause == self {
            throw "BasicError.withCause: self"
        }
        if _causes.length() >= 8 {
            throw "BasicError.withCause: too many causes"
        }
        BasicError result = new BasicError(_kind, _message)
        result._code = _code
        result._details = self.details()
        result._causes = self.causes()
        result._causes.push(cause)
        return result
    }

    Result<BasicError, Error> tryWithCause(BasicError cause) {
        if cause == null || cause == self {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid cause"))
        }
        if _causes.length() >= 8 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "too many causes"))
        }
        return Ok(self.withCause(cause))
    }

    BasicError withCauses(List<BasicError> causes) {
        if _causes.length() + causes.length() > 8 {
            throw "BasicError.withCauses: too many causes"
        }
        BasicError result = new BasicError(_kind, _message)
        result._code = _code
        result._details = self.details()
        result._causes = self.causes()
        Int index = 0
        while index < causes.length() {
            BasicError cause = causes.get(index)
            if cause == null || cause == self {
                throw "BasicError.withCauses: invalid cause"
            }
            result._causes.push(cause)
            index = index + 1
        }
        return result
    }

    Result<BasicError, Error> tryWithCauses(List<BasicError> causes) {
        if _causes.length() + causes.length() > 8 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "too many causes"))
        }
        Int index = 0
        while index < causes.length() {
            BasicError cause = causes.get(index)
            if cause == null || cause == self {
                return Err(new BasicError(ErrorKind.InvalidArgument, "invalid cause"))
            }
            index = index + 1
        }
        return Ok(self.withCauses(causes))
    }

    BasicError copy() {
        BasicError result = new BasicError(_kind, _message)
        result._code = _code
        result._details = self.details()
        result._causes = self.causes()
        return result
    }

    BasicError rootCause() {
        BasicError current = self
        Int depth = 0
        while current._causes.length() > 0 && depth < 8 {
            current = current._causes.get(0)
            depth = depth + 1
        }
        return current
    }

    List<BasicError> chain() {
        List<BasicError> result = []
        BasicError current = self
        Int depth = 0
        while current != null && depth < 8 {
            result.push(current)
            if current._causes.length() == 0 {
                break
            }
            current = current._causes.get(0)
            depth = depth + 1
        }
        return result
    }

    Bool matches(ErrorMatcher matcher) {
        if matcher == null {
            throw "BasicError.matches: null matcher"
        }
        if matcher.kind() != null && _kind != matcher.kind() {
            return false
        }
        if matcher.code() != null && _code != matcher.code() {
            return false
        }
        if matcher.messageContains() != null {
            if !contains(self.describe(), matcher.messageContains()) {
                return false
            }
        }
        return true
    }
}
```

---
