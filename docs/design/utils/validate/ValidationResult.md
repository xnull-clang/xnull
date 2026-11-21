# `ValidationResult`

| 项 | 值 |
| --- | --- |
| 类型 | `class ValidationResult` |
| 包 | `xdk.validate` |
| 稳定性 | `preview` |
| 依赖 | `ValidationError`、`ValidationContext`、`BasicError`、`Error` |

---

## 1. 定位

校验结果：错误集合、是否有效、首错、聚合、按字段分组、转 `Result`。

不做：异常控制流、i18n、错误码注册、线程安全。

---

## 2. 设计逻辑

- 可变错误集合；`add`/`addAll`/`merge` 返回 self，便于链式。
- `isValid` 等价于错误为空。
- `toResult` 成功返回 `Ok(unit)`，失败返回 `InvalidArgument`，消息取首错描述。
- `errorsByField` 按 path 分组，保持错误出现顺序；Map 键顺序不承诺。
- 无 close；可复制。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_errors` | `List<ValidationError>` | 错误列表 |

不变量：`_errors` 非 null；元素非 null；列表顺序为发现顺序。

---

## 4. 生命周期

可变；无 close；可共享读取（非并发写）。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ValidationResult()` | 无 | 空 | 无 |
| `ValidationResult(List<ValidationError> errors)` | errors | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `fromContext` | 从上下文构建 | `ValidationContext context` | `ValidationResult` | null → panic |
| `isValid` | 是否有效 | 无 | `Bool` | 无 |
| `errors` | 错误快照 | 无 | `List<ValidationError>` | 无 |
| `firstError` | 首错/无 | 无 | `ValidationError?` | 无 |
| `errorCount` | 错误数 | 无 | `Int` | 无 |
| `add` | 添加 | `ValidationError error` | `ValidationResult` | null → panic |
| `addAll` | 批量添加 | `List<ValidationError> errors` | `ValidationResult` | null → panic |
| `merge` | 合并 | `ValidationResult other` | `ValidationResult` | null → panic |
| `errorsByField` | 按路径分组 | 无 | `Map<String,List<ValidationError>>` | 无 |
| `toResult` | 转 Result | 无 | `Result<Unit, Error>` | 无 |
| `toString` | 摘要 | 无 | `String` | 无 |

说明：

- `toResult` 失败消息只包含首错；完整错误用 `errors()`。
- `merge` 把 other 的错误追加到当前结果。
- `errorsByField` 的值为独立列表。

---

## 8. 使用的技术

- 错误聚合；
- 首错短路；
- 分组；
- Result 转换。

---

## 9. 需要的支撑

- 语言：class、List、Map、Int、Bool、Result、String；
- 运行时：无；
- 接口：`ValidationError`、`ValidationContext`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`ValidationError`、`ValidationContext`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

引用语义；可变；非线程安全；无资源。

---

## 12. 示例与反例

正确：`result.toResult()`；`result.errorsByField().getOrNull("email")`。  
反例：只看 isValid 丢掉错误；并发 add；把首错当全部错误。

---

## 13. 测试/场景义务

空/单/多错误；fromContext；add/addAll/merge；firstError；errorCount；errorsByField；toResult 成功/失败；toString。

---

## 14. XNull 伪代码

```xnull
class ValidationResult {
    final List<ValidationError> _errors

    ValidationResult() {
        _errors = []
    }

    ValidationResult(List<ValidationError> errors) {
        if errors == null { throw "ValidationResult: null errors" }
        _errors = errors.copy()
    }

    static ValidationResult fromContext(ValidationContext context) {
        if context == null { throw "ValidationResult.fromContext: null" }
        return new ValidationResult(context.errors())
    }

    Bool isValid() { return _errors.isEmpty() }

    List<ValidationError> errors() { return _errors.copy() }

    ValidationError? firstError() {
        if _errors.isEmpty() { return null }
        return _errors.get(0)
    }

    Int errorCount() { return _errors.length() }

    ValidationResult add(ValidationError error) {
        if error == null { throw "ValidationResult.add: null" }
        _errors.push(error)
        return self
    }

    ValidationResult addAll(List<ValidationError> errors) {
        if errors == null { throw "ValidationResult.addAll: null" }
        Int index = 0
        while index < errors.length() {
            self.add(errors.get(index))
            index = index + 1
        }
        return self
    }

    ValidationResult merge(ValidationResult other) {
        if other == null { throw "ValidationResult.merge: null" }
        return self.addAll(other._errors)
    }

    Map<String, List<ValidationError>> errorsByField() {
        Map<String, List<ValidationError>> result = new Map<String, List<ValidationError>>()
        Int index = 0
        while index < _errors.length() {
            ValidationError error = _errors.get(index)
            if result.has(error.path()) {
                result.get(error.path()).push(error)
            } else {
                List<ValidationError> bucket = []
                bucket.push(error)
                result.put(error.path(), bucket)
            }
            index = index + 1
        }
        return result
    }

    Result<Unit, Error> toResult() {
        if _errors.isEmpty() { return Ok(unit) }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "validation failed: " + _errors.get(0).describe()))
    }

    String toString() {
        if _errors.isEmpty() { return "valid" }
        return "invalid(" + str(_errors.length()) + "): " + _errors.get(0).describe()
    }
}
```
