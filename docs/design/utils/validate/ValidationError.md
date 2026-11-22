# `ValidationError`

| 项 | 值 |
| --- | --- |
| 类型 | `class ValidationError` |
| 包 | `xdk.validate` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

> 注解合同（A8，implemented；限制见 S3 §5.7）：`@Value` 生成 `equals`/`toString`/`copy`（不生成 `hash`）；字段保持 `final`；引用字段按值语义比较。实现由处理器生成，不手写；实现时删除同名手写成员，避免生成冲突；伪代码中的 `equals`/`toString`/`copy` 只描述生成物行为，不是手写实现。

## 1. 定位

单条校验错误：字段路径、稳定错误码、可读消息。

不做：异常抛出、i18n、错误码注册、堆栈。

---

## 2. 设计逻辑

- 不可变值对象；path/code/message 非 null。
- path 可为空串（根值错误）；code/message 非空。
- `describe` 生成 `path: message (code)`；根路径省略前缀。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_path` | `String` | 路径，可为空 |
| `_code` | `String` | 稳定码 |
| `_message` | `String` | 可读消息 |

不变量：字段非 null；code/message 非空；path 不使用前导点。

---

## 4. 生命周期

不可变；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ValidationError(String path, String code, String message)` | path/code/message | path 可空串；code/message 非空 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `path` | 字段路径 | 无 | `String` | 无 |
| `code` | 错误码 | 无 | `String` | 无 |
| `message` | 可读消息 | 无 | `String` | 无 |
| `describe` | 单行描述 | 无 | `String` | 无 |
| `toString` | 描述 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变值对象；
- 路径/码/消息三元组；
- 单行格式化。

---

## 9. 需要的支撑

- 语言：class、String、Bool；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`new ValidationError("user.email", "pattern", "invalid email")`。  
反例：code 为空；message 为空；path 以 `.` 开头；把 message 当稳定码。

---

## 13. 测试/场景义务

根路径/嵌套/数组路径；空 code/message；describe；toString；相等语义（按引用）。

---

## 14. XNull 伪代码

```xnull
@Value
class ValidationError {
    final String _path
    final String _code
    final String _message

    ValidationError(String path, String code, String message) {
        if path == null { throw "ValidationError: null path" }
        if code == null || code == "" { throw "ValidationError: empty code" }
        if message == null || message == "" { throw "ValidationError: empty message" }
        if path.startsWith(".") { throw "ValidationError: leading dot path" }
        _path = path
        _code = code
        _message = message
    }

    String path() { return _path }
    String code() { return _code }
    String message() { return _message }

    String describe() {
        if _path == "" { return _message + " (" + _code + ")" }
        return _path + ": " + _message + " (" + _code + ")"
    }

    String toString() { return self.describe() }
}
```
