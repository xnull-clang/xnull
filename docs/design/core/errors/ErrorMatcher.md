# `ErrorMatcher`

| 项 | 值 |
| --- | --- |
| 类型 | `class ErrorMatcher` |
| 包 | `xdk.errors` |
| 稳定性 | `preview` |
| 依赖 | `Error`、`DetailedError`、`ErrorKind` |

---

## 1. 定位

不可变错误匹配条件：按 `kind`、`code`、`describe` 子串匹配。

不做：正则匹配、业务分支、重试、日志。

---

## 2. 设计逻辑

- 条件可组合；所有非 null 条件同时满足才匹配。
- 不可变；`with*` 返回新实例。
- `messageContains` 是大小写敏感子串匹配，不依赖 regex。
- 只依赖 `Error`/`DetailedError` 协议，不依赖具体错误类。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_kind` | `ErrorKind?` | final | null = 不限制 |
| `_code` | `String?` | final | null = 不限制 |
| `_messageContains` | `String?` | final | null = 不限制 |

不变量：全 null 匹配所有；code 非 null 时错误必须是 `DetailedError`；messageContains 空串匹配所有。

---

## 4. 生命周期

- 不可变；无 close；可跨任务共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ErrorMatcher()` | 无 | 匹配所有 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `kind` | kind 条件 | 无 | `ErrorKind?` | 无 |
| `code` | code 条件 | 无 | `String?` | 无 |
| `messageContains` | 文本条件 | 无 | `String?` | 无 |
| `withKind` | 派生 | `ErrorKind kind` | `ErrorMatcher` | 无 |
| `withCode` | 派生 | `String code` | `ErrorMatcher` | null → panic |
| `withMessageContains` | 派生 | `String text` | `ErrorMatcher` | null → panic |
| `matches` | 匹配 | `Error error` | `Bool` | null → panic |
| `copy` | 复制 | 无 | `ErrorMatcher` | 无 |
| `describe` | 摘要 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变过滤条件；
- 子串匹配；
- 协议类型判断。

---

## 9. 需要的支撑

- 语言：class、String、Bool、ErrorKind；
- 运行时：无；
- 接口：`Error`、`DetailedError`、`contains`、`errorKindDisplayName`。

---

## 10. 依赖的特性/接口/类

`Error`、`DetailedError`、`ErrorKind`、`contains`、`errorKindDisplayName`。

---

## 11. 所有权与并发

- 不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`withKind(NotFound)`；`withCode("config.missing")`；`withMessageContains("timeout")`。  
反例：用 matcher 做业务分支；对非 DetailedError 期望 code 匹配；热路径反复构造。

---

## 13. 测试/场景义务

kind/code/message 单独/组合；非 DetailedError 的 code；全 null；空串；复制独立性。

---

## 14. XNull 伪代码

```xnull
class ErrorMatcher {
    ErrorKind? _kind = null
    String? _code = null
    String? _messageContains = null

    ErrorMatcher() {
    }

    ErrorKind? kind() { return _kind }
    String? code() { return _code }
    String? messageContains() { return _messageContains }

    ErrorMatcher withKind(ErrorKind kind) {
        ErrorMatcher result = self.copy()
        result._kind = kind
        return result
    }

    ErrorMatcher withCode(String code) {
        if code == null {
            throw "ErrorMatcher.withCode: null"
        }
        ErrorMatcher result = self.copy()
        result._code = code
        return result
    }

    ErrorMatcher withMessageContains(String text) {
        if text == null {
            throw "ErrorMatcher.withMessageContains: null"
        }
        ErrorMatcher result = self.copy()
        result._messageContains = text
        return result
    }

    Bool matches(Error error) {
        if error == null {
            throw "ErrorMatcher.matches: null error"
        }
        if _kind != null && error.kind() != _kind {
            return false
        }
        if _code != null {
            if !(error is DetailedError) {
                return false
            }
            if error.code() != _code {
                return false
            }
        }
        if _messageContains != null {
            if !contains(error.describe(), _messageContains) {
                return false
            }
        }
        return true
    }

    ErrorMatcher copy() {
        ErrorMatcher result = new ErrorMatcher()
        result._kind = _kind
        result._code = _code
        result._messageContains = _messageContains
        return result
    }

    String describe() {
        String result = "match"
        if _kind != null {
            result = result + " kind=" + errorKindDisplayName(_kind)
        }
        if _code != null {
            result = result + " code=" + _code
        }
        if _messageContains != null {
            result = result + " text=" + _messageContains
        }
        return result
    }
}
```
