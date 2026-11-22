# `HttpStatus`

| 项 | 值 |
| --- | --- |
| 类型 | `class HttpStatus` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

> 注解合同（A8，implemented；限制见 S3 §5.7）：`@Value` 生成 `equals`/`toString`/`copy`（不生成 `hash`）；字段保持 `final`；引用字段按值语义比较。实现由处理器生成，不手写；实现时删除同名手写成员，避免生成冲突；伪代码中的 `equals`/`toString`/`copy` 只描述生成物行为，不是手写实现。

## 1. 定位

HTTP 状态码与原因短语：码、标准 reason、类别判断、相等。

不做：业务错误映射、响应 body、重定向策略。

---

## 2. 设计逻辑

- 字段 `_code: Int`、`_reason: String`；码 100..599。
- `of` 使用运行时标准 reason；未知码 reason 空串。
- `isInformational` 1xx、`isSuccess` 2xx、`isRedirect` 3xx、`isClientError` 4xx、`isServerError` 5xx。
- 不可变；无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_code` | `Int` | 100..599 |
| `_reason` | `String` | 原因短语，可空 |

不变量：code 合法；不可变。

---

## 4. 生命周期

不可变；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HttpStatus.of(Int code)` | code | 100..599 | 越界 → panic |

构造器私有。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `of` | 构造 | `Int code` | `HttpStatus` | 越界 → panic |
| `code` | 状态码 | 无 | `Int` | 无 |
| `reason` | 原因 | 无 | `String` | 无 |
| `isInformational` | 1xx | 无 | `Bool` | 无 |
| `isSuccess` | 2xx | 无 | `Bool` | 无 |
| `isRedirect` | 3xx | 无 | `Bool` | 无 |
| `isClientError` | 4xx | 无 | `Bool` | 无 |
| `isServerError` | 5xx | 无 | `Bool` | 无 |
| `equals` | 值相等 | `HttpStatus other` | `Bool` | 无 |
| `toString` | 文本 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 标准 reason 表；
- 百位分类。

---

## 9. 需要的支撑

- 语言：class、Int、Bool、String；
- 运行时：`httpStatusReasonRaw`；
- 接口：无。

---

## 10. 依赖的特性/接口/类

`httpStatusReasonRaw`。

---

## 11. 所有权与并发

不可变；无资源；可共享。

---

## 12. 示例与反例

正确：`HttpStatus.of(404).isClientError()`。  
反例：把 4xx 当传输错误；接受 0/600；依赖 reason 做业务判断。

---

## 13. 测试/场景义务

100/199/200/299/300/399/400/499/500/599；越界；reason；equals/toString。

---

## 14. XNull 伪代码

```xnull
@Value
class HttpStatus {
    final Int _code
    final String _reason

    private HttpStatus(Int code, String reason) {
        _code = code
        _reason = reason
    }

    static HttpStatus of(Int code) {
        if code < 100 || code > 599 {
            throw "HttpStatus.of: invalid code"
        }
        return new HttpStatus(code, httpStatusReasonRaw(code))
    }

    Int code() { return _code }
    String reason() { return _reason }
    Bool isInformational() { return _code >= 100 && _code <= 199 }
    Bool isSuccess() { return _code >= 200 && _code <= 299 }
    Bool isRedirect() { return _code >= 300 && _code <= 399 }
    Bool isClientError() { return _code >= 400 && _code <= 499 }
    Bool isServerError() { return _code >= 500 && _code <= 599 }

    Bool equals(HttpStatus other) {
        if other == null { return false }
        return _code == other.code()
    }

    String toString() {
        if _reason == "" { return str(_code) }
        return str(_code) + " " + _reason
    }
}
```
