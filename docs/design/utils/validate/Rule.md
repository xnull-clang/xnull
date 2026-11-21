# `Rule`

| 项 | 值 |
| --- | --- |
| 类型 | `class Rule implements Validator` |
| 包 | `xdk.validate` |
| 稳定性 | `preview` |
| 依赖 | `Validator`、`ValidationContext`、`JsonValue` |

---

## 1. 定位

单规则实现：稳定码、消息、描述和一个检查函数；将失败写入上下文。

不做：字段 Schema、组合策略（由 `Rules` 构造）、异步、资源。

---

## 2. 设计逻辑

- 不可变：code/message/description/check 构造后只读。
- `validate` 在 context stopped 时直接返回；否则调用 check。
- check 负责判定并调用 `context.addError`，不返回值。
- 单规则可复用；check 不应保留可变状态。
- 无 close；可共享（check 线程安全由调用方保证）。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_code` | `String` | 稳定错误码 |
| `_message` | `String` | 可读消息 |
| `_description` | `String` | 规则描述 |
| `_check` | `void(JsonValue, ValidationContext)` | 检查函数 |

不变量：字段非 null；code/message/description 非空；check 非 null。

---

## 4. 生命周期

不可变；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Rule(String code, String message, String description, void(JsonValue,ValidationContext) check)` | 全部 | 见不变量 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `validate` | 执行检查 | `JsonValue value, ValidationContext context` | `void` | null context → panic |
| `describe` | 描述 | 无 | `String` | 无 |
| `code` | 错误码 | 无 | `String` | 无 |
| `message` | 消息 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变规则；
- 函数字段；
- 上下文写入；
- 组合基础。

---

## 9. 需要的支撑

- 语言：class、String、函数类型、protocol 实现；
- 运行时：无；
- 接口：`Validator`、`JsonValue`、`ValidationContext`。

---

## 10. 依赖的特性/接口/类

`Validator`、`JsonValue`、`ValidationContext`。

---

## 11. 所有权与并发

不可变；可共享；check 函数线程安全由调用方保证；无资源。

---

## 12. 示例与反例

正确：`new Rule("min", "too small", "min(1)", (JsonValue v, ValidationContext c) -> {...})`。  
反例：check 抛业务异常；check 修改 value；code 为空；复用一个带可变状态的 check。

---

## 13. 测试/场景义务

通过/失败；stopped；describe/code/message；null context；自定义 check；组合使用。

---

## 14. XNull 伪代码

```xnull
class Rule implements Validator {
    final String _code
    final String _message
    final String _description
    final void(JsonValue, ValidationContext) _check

    Rule(String code, String message, String description,
         void(JsonValue, ValidationContext) check) {
        if code == null || code == "" { throw "Rule: empty code" }
        if message == null || message == "" { throw "Rule: empty message" }
        if description == null || description == "" {
            throw "Rule: empty description"
        }
        if check == null { throw "Rule: null check" }
        _code = code
        _message = message
        _description = description
        _check = check
    }

    void validate(JsonValue value, ValidationContext context) {
        if context == null { throw "Rule.validate: null context" }
        if context.isStopped() { return }
        _check(value, context)
    }

    String describe() { return _description }
    String code() { return _code }
    String message() { return _message }
}
```
