# `ConfigField`

| 项 | 值 |
| --- | --- |
| 类型 | `class ConfigField` |
| 包 | `xdk.config` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

配置字段规则：名称、必填、默认值、自定义校验。

不做：类型系统、UI、嵌套 schema。

---

## 2. 设计逻辑

- 不可变；`_name`、`_isRequired`、`_defaultValue: String?`、`_validator: Result<Unit,Error>(String)?`。
- `with*` 返回新实例。
- 校验器接收值，返回 `Result<Unit,Error>`。
- 无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 字段名 |
| `_isRequired` | `Bool` | 必填 |
| `_defaultValue` | `String?` | 默认 |
| `_validator` | 函数? | 校验 |

不变量：name 非空；不可变。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ConfigField(String name)` | name | 非空 | 空 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 名称 | 无 | `String` | 无 |
| `isRequired` | 必填 | 无 | `Bool` | 无 |
| `defaultValue` | 默认 | 无 | `String?` | 无 |
| `required` | 派生 | `Bool` | `ConfigField` | 无 |
| `withDefault` | 派生 | `String` | `ConfigField` | null → panic |
| `withValidator` | 派生 | 函数 | `ConfigField` | null → panic |
| `validate` | 校验值 | `String` | `Result<Unit, Error>` | 字段错误 |

---

## 8. 使用的技术

- 不可变 builder；
- 函数值校验；
- 默认值。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Result、函数类型；
- 运行时：无；
- 接口：`Error`。

---

## 10. 依赖的特性/接口/类

`Error`、`Result`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`new ConfigField("port").required(true).withValidator(...)`。  
反例：空名；validator 抛异常；默认值当必填。

---

## 13. 测试/场景义务

required/default/validator；validate 成功/失败；派生独立性。

---

## 14. XNull 伪代码

```xnull
class ConfigField {
    final String _name
    final Bool _isRequired
    final String? _defaultValue
    final Result<Unit, Error>(String)? _validator

    ConfigField(String name) {
        if name == "" { throw "ConfigField: empty name" }
        _name = name
        _isRequired = false
        _defaultValue = null
        _validator = null
    }

    String name() { return _name }
    Bool isRequired() { return _isRequired }
    String? defaultValue() { return _defaultValue }

    ConfigField required(Bool value) {
        ConfigField result = new ConfigField(_name)
        result._isRequired = value
        result._defaultValue = _defaultValue
        result._validator = _validator
        return result
    }

    ConfigField withDefault(String value) {
        if value == null { throw "ConfigField.withDefault: null" }
        ConfigField result = new ConfigField(_name)
        result._isRequired = _isRequired
        result._defaultValue = value
        result._validator = _validator
        return result
    }

    ConfigField withValidator(Result<Unit, Error>(String) validator) {
        if validator == null { throw "ConfigField.withValidator: null" }
        ConfigField result = new ConfigField(_name)
        result._isRequired = _isRequired
        result._defaultValue = _defaultValue
        result._validator = validator
        return result
    }

    Result<Unit, Error> validate(String value) {
        if _validator == null { return Ok(unit) }
        return _validator(value)
    }
}
```
