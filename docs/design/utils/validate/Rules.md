# `Rules`

| 项 | 值 |
| --- | --- |
| 类型 | `class Rules` |
| 包 | `xdk.validate` |
| 稳定性 | `preview` |
| 依赖 | `Rule`、`Validator`、`JsonValue`、`JsonNumber`、`Regex` |

---

## 1. 定位

常用校验规则静态工厂：必填、类型、长度、范围、模式、枚举、数组元素、组合、自定义。

不做：Schema 字段管理、错误结果聚合、异步规则、i18n。

---

## 2. 设计逻辑

- 全部返回 `Validator`；底层是 `Rule` 或组合 Rule。
- 类型规则只报告 `type`；长度/范围/模式规则假定类型已由前置规则保证，否则也报 `type`。
- `all` 顺序执行并保留全部错误；`any` 用 fork 探测且只报一个 `any` 错误；`not` 用 fork 取反。
- `arrayOf` 为每个元素创建 `[index]` 子路径。
- 无全局规则表；每次工厂调用创建新 Rule。
- 无 close；规则不可变，可复用。

---

## 3. 表示与不变量

无实例字段。

不变量：返回的 Validator 非 null；正则/列表参数非 null；`range` 的 min ≤ max。

---

## 4. 生命周期

静态命名空间；返回的规则无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Rules()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `required` | 非 null/非 JSON null | 无 | `Validator` | 无 |
| `string` | 字符串类型 | 无 | `Validator` | 无 |
| `number` | 数字类型 | 无 | `Validator` | 无 |
| `integer` | 整数类型 | 无 | `Validator` | 无 |
| `bool` | 布尔类型 | 无 | `Validator` | 无 |
| `array` | 数组类型 | 无 | `Validator` | 无 |
| `object` | 对象类型 | 无 | `Validator` | 无 |
| `minLength` | 最小长度 | `Int length` | `Validator` | 负数 → panic |
| `maxLength` | 最大长度 | `Int length` | `Validator` | 负数 → panic |
| `pattern` | 正则匹配 | `Regex regex` | `Validator` | null → panic |
| `range` | 数值范围 | `Double min, Double max` | `Validator` | min>max/NaN → panic |
| `oneOf` | 字符串枚举 | `List<String> allowed` | `Validator` | null/空 → panic |
| `email` | 邮箱格式 | 无 | `Validator` | 无 |
| `url` | URL 格式 | 无 | `Validator` | 无 |
| `uuid` | UUID 格式 | 无 | `Validator` | 无 |
| `arrayOf` | 数组元素规则 | `Validator element` | `Validator` | null → panic |
| `all` | 全部通过 | `List<Validator> validators` | `Validator` | null/空 → panic |
| `any` | 任一通过 | `List<Validator> validators` | `Validator` | null/空 → panic |
| `not` | 取反 | `Validator validator` | `Validator` | null → panic |
| `custom` | 自定义谓词 | `String code, String message, Bool(JsonValue) predicate` | `Validator` | 空码/消息/null → panic |

---

## 8. 使用的技术

- 工厂 + 不可变规则；
- 组合（all/any/not）；
- 路径子上下文；
- 正则；
- fork 探测。

---

## 9. 需要的支撑

- 语言：class、List、String、Int、Double、Bool、函数类型；
- 运行时：`str`、`Regex.compile`；
- 接口：`Rule`、`Validator`、`JsonValue`、`JsonNumber`、`ValidationContext`。

---

## 10. 依赖的特性/接口/类

`Rule`、`Validator`、`JsonValue`、`JsonNumber`、`Regex`、`ValidationContext`。

---

## 11. 所有权与并发

无状态；规则不可变；可跨任务共享；无资源。

---

## 12. 示例与反例

正确：`Rules.all([Rules.string(), Rules.minLength(3), Rules.email()])`。  
反例：把 `any` 的分支错误全部保留；`range` min>max；对 null 调 asString；用正则做完整 RFC 校验。

---

## 13. 测试/场景义务

每种类型规则；缺失/null；边界长度/范围；正则；枚举；email/url/uuid 正反例；arrayOf 路径；all/any/not；custom；failFast。

---

## 14. XNull 伪代码

```xnull
class Rules {
    private Rules() {
    }

    static Validator required() {
        return new Rule("required", "value is required", "required",
            (JsonValue value, ValidationContext context) -> {
                if value == null || value.isNull() {
                    context.addError("required", "value is required")
                }
            })
    }

    static Validator string() {
        return new Rule("type", "expected string", "string",
            (JsonValue value, ValidationContext context) -> {
                if value != null && !value.isNull() && !value.isString() {
                    context.addError("type", "expected string")
                }
            })
    }

    static Validator number() {
        return new Rule("type", "expected number", "number",
            (JsonValue value, ValidationContext context) -> {
                if value != null && !value.isNull() && !value.isNumber() {
                    context.addError("type", "expected number")
                }
            })
    }

    static Validator integer() {
        return new Rule("type", "expected integer", "integer",
            (JsonValue value, ValidationContext context) -> {
                if value == null || value.isNull() { return }
                if !value.isNumber() {
                    context.addError("type", "expected integer")
                    return
                }
                JsonNumber number = value.asNumber() as JsonNumber
                if !number.isInteger() {
                    context.addError("type", "expected integer")
                }
            })
    }

    static Validator bool() {
        return new Rule("type", "expected boolean", "bool",
            (JsonValue value, ValidationContext context) -> {
                if value != null && !value.isNull() && !value.isBool() {
                    context.addError("type", "expected boolean")
                }
            })
    }

    static Validator array() {
        return new Rule("type", "expected array", "array",
            (JsonValue value, ValidationContext context) -> {
                if value != null && !value.isNull() && !value.isArray() {
                    context.addError("type", "expected array")
                }
            })
    }

    static Validator object() {
        return new Rule("type", "expected object", "object",
            (JsonValue value, ValidationContext context) -> {
                if value != null && !value.isNull() && !value.isObject() {
                    context.addError("type", "expected object")
                }
            })
    }

    static Validator minLength(Int length) {
        if length < 0 { throw "Rules.minLength: negative length" }
        return new Rule("min_length", "value is too short", "minLength(" + str(length) + ")",
            (JsonValue value, ValidationContext context) -> {
                if value == null || value.isNull() { return }
                if value.isString() {
                    if (value.asString() as String).length() < length {
                        context.addError("min_length", "value is too short")
                    }
                } else if value.isArray() {
                    if (value.asArray() as JsonArray).length() < length {
                        context.addError("min_length", "array is too short")
                    }
                } else {
                    context.addError("type", "expected string or array")
                }
            })
    }

    static Validator maxLength(Int length) {
        if length < 0 { throw "Rules.maxLength: negative length" }
        return new Rule("max_length", "value is too long", "maxLength(" + str(length) + ")",
            (JsonValue value, ValidationContext context) -> {
                if value == null || value.isNull() { return }
                if value.isString() {
                    if (value.asString() as String).length() > length {
                        context.addError("max_length", "value is too long")
                    }
                } else if value.isArray() {
                    if (value.asArray() as JsonArray).length() > length {
                        context.addError("max_length", "array is too long")
                    }
                } else {
                    context.addError("type", "expected string or array")
                }
            })
    }

    static Validator pattern(Regex regex) {
        if regex == null { throw "Rules.pattern: null regex" }
        return new Rule("pattern", "value does not match pattern", "pattern",
            (JsonValue value, ValidationContext context) -> {
                if value == null || value.isNull() { return }
                if !value.isString() {
                    context.addError("type", "expected string")
                    return
                }
                if !regex.isMatch(value.asString() as String) {
                    context.addError("pattern", "value does not match pattern")
                }
            })
    }

    static Validator range(Double min, Double max) {
        if isNaN(min) || isNaN(max) { throw "Rules.range: NaN bound" }
        if min > max { throw "Rules.range: min > max" }
        return new Rule("range", "value out of range", "range(" + str(min) + "," + str(max) + ")",
            (JsonValue value, ValidationContext context) -> {
                if value == null || value.isNull() { return }
                if !value.isNumber() {
                    context.addError("type", "expected number")
                    return
                }
                Result<Double, Error> parsed = (value.asNumber() as JsonNumber).asDouble()
                if parsed.isErr() {
                    context.addError("number", "invalid number")
                    return
                }
                Double number = parsed.value()
                if number < min || number > max {
                    context.addError("range", "value out of range")
                }
            })
    }

    static Validator oneOf(List<String> allowed) {
        if allowed == null || allowed.length() == 0 {
            throw "Rules.oneOf: empty allowed list"
        }
        return new Rule("one_of", "value is not allowed", "oneOf",
            (JsonValue value, ValidationContext context) -> {
                if value == null || value.isNull() { return }
                if !value.isString() {
                    context.addError("type", "expected string")
                    return
                }
                String text = value.asString() as String
                Int index = 0
                while index < allowed.length() {
                    if text == allowed.get(index) { return }
                    index = index + 1
                }
                context.addError("one_of", "value is not allowed")
            })
    }

    static Validator email() {
        Result<Regex, Error> compiled = Regex.compile("^[^@ ]+@[^@ ]+[.][^@ ]+$")
        if compiled.isErr() { throw "Rules.email: invalid pattern" }
        return Rules.pattern(compiled.value())
    }

    static Validator url() {
        Result<Regex, Error> compiled = Regex.compile("^https?://[^ ]+$")
        if compiled.isErr() { throw "Rules.url: invalid pattern" }
        return Rules.pattern(compiled.value())
    }

    static Validator uuid() {
        Result<Regex, Error> compiled = Regex.compile(
            "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
        if compiled.isErr() { throw "Rules.uuid: invalid pattern" }
        return Rules.pattern(compiled.value())
    }

    static Validator arrayOf(Validator element) {
        if element == null { throw "Rules.arrayOf: null element" }
        return new Rule("array", "invalid array element", "arrayOf",
            (JsonValue value, ValidationContext context) -> {
                if value == null || value.isNull() { return }
                if !value.isArray() {
                    context.addError("type", "expected array")
                    return
                }
                JsonArray array = value.asArray() as JsonArray
                Int index = 0
                while index < array.length() {
                    if context.isStopped() { return }
                    element.validate(array.get(index), context.child("[" + str(index) + "]"))
                    index = index + 1
                }
            })
    }

    static Validator all(List<Validator> validators) {
        if validators == null || validators.length() == 0 {
            throw "Rules.all: empty validators"
        }
        return new Rule("all", "one or more rules failed", "all",
            (JsonValue value, ValidationContext context) -> {
                Int index = 0
                while index < validators.length() {
                    if context.isStopped() { return }
                    validators.get(index).validate(value, context)
                    index = index + 1
                }
            })
    }

    static Validator any(List<Validator> validators) {
        if validators == null || validators.length() == 0 {
            throw "Rules.any: empty validators"
        }
        return new Rule("any", "no alternative matched", "any",
            (JsonValue value, ValidationContext context) -> {
                Int index = 0
                while index < validators.length() {
                    ValidationContext probe = context.fork()
                    validators.get(index).validate(value, probe)
                    if !probe.isFailed() { return }
                    index = index + 1
                }
                context.addError("any", "no alternative matched")
            })
    }

    static Validator not(Validator validator) {
        if validator == null { throw "Rules.not: null validator" }
        return new Rule("not", "value matches forbidden rule", "not",
            (JsonValue value, ValidationContext context) -> {
                ValidationContext probe = context.fork()
                validator.validate(value, probe)
                if !probe.isFailed() {
                    context.addError("not", "value matches forbidden rule")
                }
            })
    }

    static Validator custom(String code, String message, Bool(JsonValue) predicate) {
        if predicate == null { throw "Rules.custom: null predicate" }
        return new Rule(code, message, "custom",
            (JsonValue value, ValidationContext context) -> {
                if !predicate(value) {
                    context.addError(code, message)
                }
            })
    }
}
```
