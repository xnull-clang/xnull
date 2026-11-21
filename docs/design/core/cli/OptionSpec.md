# `OptionSpec`

| 项 | 值 |
| --- | --- |
| 类型 | `class OptionSpec` |
| 包 | `xdk.cli` |
| 稳定性 | `preview` |
| 依赖 | `ValueParser` |

---

## 1. 定位

不可变选项规格：长名、短名、是否带值、必填、可重复、默认值、值名、描述、隐藏、值解析器。

不做：解析 argv、命令树、帮助布局、配置来源。

---

## 2. 设计逻辑

- 字段全部 `final`；所有 `with*` 返回新实例。
- 长名使用 lower-kebab（`output-dir`），不带 `--`；短名是单个 ASCII 字母/数字。
- 默认是 flag（不带值）；`withValue` / `withValueName` 切换为值选项。
- flag 不允许默认值/值解析器；必填与默认值互斥。
- 值选项的 `defaultValue` 是原始字符串；是否合法由 `ValueParser` 在解析时判断。
- 规格非法是合同错误（panic）；用户输入非法由 `Parser` 转 `UsageError`。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 长名，lower-kebab |
| `_shortName` | `String?` | 单字符短名 |
| `_hasValue` | `Bool` | 是否带值 |
| `_isRequired` | `Bool` | 是否必须出现 |
| `_isRepeatable` | `Bool` | 是否允许重复 |
| `_defaultValue` | `String?` | 默认原始值 |
| `_valueName` | `String` | help 中的值名 |
| `_description` | `String` | 单行描述 |
| `_isHidden` | `Bool` | help 中隐藏 |
| `_valueParser` | `ValueParser?` | 值校验/归一化 |

不变量：name 合法；shortName 合法或 null；valueName 非空；flag 的 default/parser 为 null；required 与 default 不同时成立；不可变。

---

## 4. 生命周期

不可变；无 close；可共享；线程安全。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `OptionSpec(String name)` | name | 合法 lower-kebab | 非法 → panic |

派生方法也只接受合法值；非法组合（flag + default、required + default、flag + parser）在私有构造中 panic。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 长名 | 无 | `String` | 无 |
| `shortName` | 短名/无 | 无 | `String?` | 无 |
| `hasValue` | 是否带值 | 无 | `Bool` | 无 |
| `isRequired` | 是否必填 | 无 | `Bool` | 无 |
| `isRepeatable` | 是否可重复 | 无 | `Bool` | 无 |
| `defaultValue` | 默认值/无 | 无 | `String?` | 无 |
| `valueName` | help 值名 | 无 | `String` | 无 |
| `description` | 描述 | 无 | `String` | 无 |
| `isHidden` | 是否隐藏 | 无 | `Bool` | 无 |
| `valueParser` | 值解析器/无 | 无 | `ValueParser?` | 无 |
| `isFlag` | 是否 flag | 无 | `Bool` | 无 |
| `longToken` | `--name` | 无 | `String` | 无 |
| `shortToken` | `-s`/无 | 无 | `String?` | 无 |
| `withShortName` | 派生短名 | `String shortName` | `OptionSpec` | 非法 → panic |
| `withValue` | 派生为值选项 | 无 | `OptionSpec` | 无 |
| `withValueName` | 派生值名 | `String valueName` | `OptionSpec` | 空/null → panic |
| `withRequired` | 派生必填 | `Bool value` | `OptionSpec` | 与 default 冲突 → panic |
| `withRepeatable` | 派生可重复 | `Bool value` | `OptionSpec` | 无 |
| `withDefault` | 派生默认值 | `String value` | `OptionSpec` | flag/required/null → panic |
| `withDescription` | 派生描述 | `String value` | `OptionSpec` | null → panic |
| `withHidden` | 派生隐藏 | `Bool value` | `OptionSpec` | 无 |
| `withValueParser` | 派生解析器 | `ValueParser value` | `OptionSpec` | flag/null → panic |
| `toString` | 诊断文本 | 无 | `String` | 无 |

说明：

- `withValueName` 同时把选项变为值选项。
- `withRequired(true)` 后不能再 `withDefault`；反过来也一样。
- flag 的 `withDefault`/`withValueParser` 直接 panic，不静默忽略。
- `toString` 只用于诊断；不保证可逆。

---

## 8. 使用的技术

- 不可变值对象；
- builder 风格派生；
- 名称校验；
- 互斥规则；
- 可选协议引用。

---

## 9. 需要的支撑

- 语言：class、String、Bool、List、Result；
- 运行时：无；
- 接口：`ValueParser`、`isValidLongName`、`isValidOptionShortName`。

---

## 10. 依赖的特性/接口/类

`ValueParser`、`isValidLongName`、`isValidOptionShortName`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`new OptionSpec("output").withShortName("o").withValueName("file")`。  
反例：`new OptionSpec("--output")`；flag 调用 `withDefault`；required + default；`-abc` 短名。

---

## 13. 测试/场景义务

长名/短名合法与非法；flag/值选项；默认；required；repeatable；parser；隐藏；互斥规则；派生独立性。

---

## 14. XNull 伪代码

```xnull
class OptionSpec {
    final String _name
    final String? _shortName
    final Bool _hasValue
    final Bool _isRequired
    final Bool _isRepeatable
    final String? _defaultValue
    final String _valueName
    final String _description
    final Bool _isHidden
    final ValueParser? _valueParser

    OptionSpec(String name) {
        if !isValidLongName(name) { throw "OptionSpec: invalid name" }
        _name = name
        _shortName = null
        _hasValue = false
        _isRequired = false
        _isRepeatable = false
        _defaultValue = null
        _valueName = "value"
        _description = ""
        _isHidden = false
        _valueParser = null
    }

    private OptionSpec(String name, String? shortName, Bool hasValue, Bool isRequired,
                       Bool isRepeatable, String? defaultValue, String valueName,
                       String description, Bool isHidden, ValueParser? valueParser) {
        if !isValidLongName(name) { throw "OptionSpec: invalid name" }
        if shortName != null && !isValidOptionShortName(shortName) {
            throw "OptionSpec: invalid short name"
        }
        if valueName == null || valueName == "" {
            throw "OptionSpec: empty value name"
        }
        if description == null { throw "OptionSpec: null description" }
        if !hasValue && defaultValue != null {
            throw "OptionSpec: flag cannot have default"
        }
        if !hasValue && valueParser != null {
            throw "OptionSpec: flag cannot have parser"
        }
        if isRequired && defaultValue != null {
            throw "OptionSpec: required cannot have default"
        }
        _name = name
        _shortName = shortName
        _hasValue = hasValue
        _isRequired = isRequired
        _isRepeatable = isRepeatable
        _defaultValue = defaultValue
        _valueName = valueName
        _description = description
        _isHidden = isHidden
        _valueParser = valueParser
    }

    String name() { return _name }
    String? shortName() { return _shortName }
    Bool hasValue() { return _hasValue }
    Bool isRequired() { return _isRequired }
    Bool isRepeatable() { return _isRepeatable }
    String? defaultValue() { return _defaultValue }
    String valueName() { return _valueName }
    String description() { return _description }
    Bool isHidden() { return _isHidden }
    ValueParser? valueParser() { return _valueParser }
    Bool isFlag() { return !_hasValue }

    String longToken() { return "--" + _name }

    String? shortToken() {
        if _shortName == null { return null }
        String shortName = _shortName as String
        return "-" + shortName
    }

    OptionSpec withShortName(String shortName) {
        OptionSpec result = new OptionSpec(
            _name, shortName, _hasValue, _isRequired, _isRepeatable,
            _defaultValue, _valueName, _description, _isHidden, _valueParser)
        return result
    }

    OptionSpec withValue() {
        OptionSpec result = new OptionSpec(
            _name, _shortName, true, _isRequired, _isRepeatable,
            _defaultValue, _valueName, _description, _isHidden, _valueParser)
        return result
    }

    OptionSpec withValueName(String valueName) {
        OptionSpec result = new OptionSpec(
            _name, _shortName, true, _isRequired, _isRepeatable,
            _defaultValue, valueName, _description, _isHidden, _valueParser)
        return result
    }

    OptionSpec withRequired(Bool value) {
        OptionSpec result = new OptionSpec(
            _name, _shortName, _hasValue, value, _isRepeatable,
            _defaultValue, _valueName, _description, _isHidden, _valueParser)
        return result
    }

    OptionSpec withRepeatable(Bool value) {
        OptionSpec result = new OptionSpec(
            _name, _shortName, _hasValue, _isRequired, value,
            _defaultValue, _valueName, _description, _isHidden, _valueParser)
        return result
    }

    OptionSpec withDefault(String value) {
        if !_hasValue { throw "OptionSpec.withDefault: flag" }
        if value == null { throw "OptionSpec.withDefault: null" }
        OptionSpec result = new OptionSpec(
            _name, _shortName, _hasValue, _isRequired, _isRepeatable,
            value, _valueName, _description, _isHidden, _valueParser)
        return result
    }

    OptionSpec withDescription(String value) {
        if value == null { throw "OptionSpec.withDescription: null" }
        OptionSpec result = new OptionSpec(
            _name, _shortName, _hasValue, _isRequired, _isRepeatable,
            _defaultValue, _valueName, value, _isHidden, _valueParser)
        return result
    }

    OptionSpec withHidden(Bool value) {
        OptionSpec result = new OptionSpec(
            _name, _shortName, _hasValue, _isRequired, _isRepeatable,
            _defaultValue, _valueName, _description, value, _valueParser)
        return result
    }

    OptionSpec withValueParser(ValueParser value) {
        if !_hasValue { throw "OptionSpec.withValueParser: flag" }
        if value == null { throw "OptionSpec.withValueParser: null" }
        OptionSpec result = new OptionSpec(
            _name, _shortName, _hasValue, _isRequired, _isRepeatable,
            _defaultValue, _valueName, _description, _isHidden, value)
        return result
    }

    String toString() {
        String result = self.longToken()
        if _hasValue { result = result + " <" + _valueName + ">" }
        return result
    }
}
```
