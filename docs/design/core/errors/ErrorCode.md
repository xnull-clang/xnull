# `ErrorCode`

| 项 | 值 |
| --- | --- |
| 类型 | `class ErrorCode` |
| 包 | `xdk.errors` |
| 稳定性 | `preview` |
| 依赖 | `ErrorKind`、`BasicError` |

---

## 1. 定位

应用/库的稳定业务错误码 + 粗分类 + 默认消息；不是 `ErrorKind` 的替代。

---

## 2. 设计逻辑

- `ErrorKind` 是 14 项粗分类；业务需要细码（`config.missing`）。
- 值对象；kind/code/message 相同即相等。
- 可转 `BasicError`；不直接实现 `Error`。
- 码格式 `[a-z0-9_.-]+`；命名空间用点。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_kind` | `ErrorKind` | final | 粗分类 |
| `_code` | `String` | final | 非空合法码 |
| `_message` | `String` | final | 非空、单行 |

不变量：code 非空合法；message 非空；不可变；值语义。

---

## 4. 生命周期

- 不可变；无 close；可跨任务共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ErrorCode(ErrorKind kind, String code, String message)` | kind/code/message | code 非空合法；message 非空 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `kind` | 分类 | 无 | `ErrorKind` | 无 |
| `code` | 稳定码 | 无 | `String` | 无 |
| `message` | 默认消息 | 无 | `String` | 无 |
| `describe` | 单行文本 | 无 | `String` | 无 |
| `withMessage` | 派生 | `String message` | `ErrorCode` | 非法 → panic |
| `toBasicError` | 转基础错误 | 无 | `BasicError` | 无 |
| `equals` | 值相等 | `ErrorCode other` | `Bool` | 无 |
| `compare` | 排序 | `ErrorCode other` | `Int` | 无 |
| `toString` | 文本 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 值对象；
- 稳定码校验；
- 分类 + 码排序；
- 错误转换。

---

## 9. 需要的支撑

- 语言：class、String、ErrorKind、Bool、Int；
- 运行时：无；
- 接口：`isValidErrorCode`、`errorKindDisplayName`、`errorKindCode`、`BasicError`。

---

## 10. 依赖的特性/接口/类

`ErrorKind`、`BasicError`、`isValidErrorCode`、`errorKindDisplayName`、`errorKindCode`。

---

## 11. 所有权与并发

- 不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`new ErrorCode(NotFound,"config.missing","config file missing")`；`toBasicError()`。  
反例：空码/大写码 → panic；用 `ErrorKind` 代替业务码；把码当消息。

---

## 13. 测试/场景义务

合法/非法码；空消息；withMessage；toBasicError；equals/compare；排序稳定。

---

## 14. XNull 伪代码

```xnull
class ErrorCode {
    ErrorKind _kind
    String _code
    String _message

    ErrorCode(ErrorKind kind, String code, String message) {
        if code == "" || !isValidErrorCode(code) {
            throw "ErrorCode: invalid code"
        }
        if message == "" {
            throw "ErrorCode: empty message"
        }
        _kind = kind
        _code = code
        _message = message
    }

    ErrorKind kind() { return _kind }
    String code() { return _code }
    String message() { return _message }

    String describe() {
        return "[" + _code + "] " + errorKindDisplayName(_kind) + ": " + _message
    }

    ErrorCode withMessage(String message) {
        return new ErrorCode(_kind, _code, message)
    }

    BasicError toBasicError() {
        BasicError error = new BasicError(_kind, _message)
        return error.withCode(_code)
    }

    Bool equals(ErrorCode other) {
        if other == null {
            return false
        }
        return _kind == other._kind
            && _code == other._code
            && _message == other._message
    }

    Int compare(ErrorCode other) {
        Int selfKind = errorKindCode(_kind)
        Int otherKind = errorKindCode(other._kind)
        if selfKind < otherKind { return -1 }
        if selfKind > otherKind { return 1 }
        if _code < other._code { return -1 }
        if _code > other._code { return 1 }
        if _message < other._message { return -1 }
        if _message > other._message { return 1 }
        return 0
    }

    String toString() {
        return self.describe()
    }
}
```
