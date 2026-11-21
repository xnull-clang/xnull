# `Schema`

| 项 | 值 |
| --- | --- |
| 类型 | `class Schema implements Validator` |
| 包 | `xdk.validate` |
| 稳定性 | `preview` |
| 依赖 | `Validator`、`FieldRule`、`ValidationContext`、`ValidationResult`、`JsonValue`、`JsonObject` |

---

## 1. 定位

对象字段 Schema：字段名 → 校验器/必填；校验 `JsonValue` 对象并聚合路径错误。

不做：JSON Schema 标准全集、跨字段表达式、类型映射、配置来源。

---

## 2. 设计逻辑

- 字段按添加顺序保存；重复字段 panic。
- `required(name)` 只标记已有字段，不存在的字段 panic。
- `validate` 要求 value 是非 null 对象；否则报 `object` 错误。
- 缺失或 JSON null 且 required → `required` 错误；否则交给字段 validator。
- 子上下文使用字段名路径；数组元素由 `Rules.arrayOf` 添加下标。
- 构建后可复用；构建过程非线程安全；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_fields` | `Map<String, FieldRule>` | 字段规则 |
| `_order` | `List<String>` | 添加顺序 |
| `_failFast` | `Bool` | 默认 failFast |

不变量：order 无重复；每个 order 键存在于 fields；fields 的 FieldRule.name 与键一致。

---

## 4. 生命周期

构造后可变（field/required）；校验时只读；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Schema()` | 无 | failFast=false | 无 |
| `Schema(Bool failFast)` | failFast | 任意 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `field` | 添加字段 | `String name, Validator validator` | `Schema` | 空/重复/null → panic |
| `required` | 标记必填 | `String name` | `Schema` | 不存在 → panic |
| `validate` | 协议校验 | `JsonValue value, ValidationContext context` | `void` | null context → panic |
| `validateValue` | 校验为结果 | `JsonValue value` | `ValidationResult` | 无 |
| `validateField` | 单字段 | `String name, JsonValue value` | `ValidationResult` | 未知字段 → panic |
| `fields` | 字段快照 | 无 | `List<FieldRule>` | 无 |
| `isFailFast` | 默认失败模式 | 无 | `Bool` | 无 |
| `describe` | 描述 | 无 | `String` | 无 |

说明：

- `validateValue` 使用 `_failFast` 创建上下文。
- `validateField` 的路径以字段名开头；用于局部校验。
- `fields` 返回新列表，FieldRule 不可变。

---

## 8. 使用的技术

- 字段表；
- 顺序遍历；
- 子路径上下文；
- 错误聚合；
- 协议实现。

---

## 9. 需要的支撑

- 语言：class、Map、List、String、Bool、protocol 实现；
- 运行时：无；
- 接口：`Validator`、`FieldRule`、`ValidationContext`、`ValidationResult`、`JsonObject`。

---

## 10. 依赖的特性/接口/类

`Validator`、`FieldRule`、`ValidationContext`、`ValidationResult`、`JsonValue`、`JsonObject`。

---

## 11. 所有权与并发

引用语义；构建后只读；可共享；构建/修改非线程安全；无资源。

---

## 12. 示例与反例

正确：`new Schema().field("name", Rules.string()).required("name")`。  
反例：重复字段；required 不存在字段；用 Schema 校验非对象；并发 field/validate。

---

## 13. 测试/场景义务

空 Schema；必填/可选；缺失/null；非对象；嵌套 Schema；数组元素；failFast；validateField；重复字段；字段顺序；describe。

---

## 14. XNull 伪代码

```xnull
class Schema implements Validator {
    final Map<String, FieldRule> _fields
    final List<String> _order
    final Bool _failFast

    Schema() {
        _fields = new Map<String, FieldRule>()
        _order = []
        _failFast = false
    }

    Schema(Bool failFast) {
        _fields = new Map<String, FieldRule>()
        _order = []
        _failFast = failFast
    }

    Schema field(String name, Validator validator) {
        if name == null || name == "" { throw "Schema.field: empty name" }
        if validator == null { throw "Schema.field: null validator" }
        if _fields.has(name) { throw "Schema.field: duplicate name" }
        _fields.put(name, new FieldRule(name, validator, false))
        _order.push(name)
        return self
    }

    Schema required(String name) {
        if name == null || name == "" { throw "Schema.required: empty name" }
        if !_fields.has(name) { throw "Schema.required: unknown field" }
        FieldRule existing = _fields.get(name)
        _fields.put(name, existing.withRequired(true))
        return self
    }

    void validate(JsonValue value, ValidationContext context) {
        if context == null { throw "Schema.validate: null context" }
        if value == null || !value.isObject() {
            context.addError("object", "expected object")
            return
        }
        JsonObject object = value.asObject() as JsonObject
        Int index = 0
        while index < _order.length() {
            if context.isStopped() { return }
            String name = _order.get(index)
            FieldRule rule = _fields.get(name)
            JsonValue? fieldValue = object.getOrNull(name)
            if fieldValue == null || fieldValue.isNull() {
                if rule.isRequired() {
                    context.child(name).addError("required", "field is required")
                }
            } else {
                rule.validator().validate(fieldValue, context.child(name))
            }
            index = index + 1
        }
    }

    ValidationResult validateValue(JsonValue value) {
        ValidationContext context = new ValidationContext(_failFast)
        self.validate(value, context)
        return ValidationResult.fromContext(context)
    }

    ValidationResult validateField(String name, JsonValue value) {
        if name == null || name == "" { throw "Schema.validateField: empty name" }
        if !_fields.has(name) { throw "Schema.validateField: unknown field" }
        ValidationContext context = new ValidationContext(_failFast)
        FieldRule rule = _fields.get(name)
        if value == null || value.isNull() {
            if rule.isRequired() {
                context.child(name).addError("required", "field is required")
            }
        } else {
            rule.validator().validate(value, context.child(name))
        }
        return ValidationResult.fromContext(context)
    }

    List<FieldRule> fields() {
        List<FieldRule> result = []
        Int index = 0
        while index < _order.length() {
            result.push(_fields.get(_order.get(index)))
            index = index + 1
        }
        return result
    }

    Bool isFailFast() { return _failFast }

    String describe() {
        return "schema(" + str(_fields.length()) + " fields)"
    }
}
```
