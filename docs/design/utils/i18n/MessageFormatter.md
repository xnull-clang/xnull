# `MessageFormatter`

| 项 | 值 |
| --- | --- |
| 类型 | `class MessageFormatter` |
| 包 | `xdk.i18n` |
| 稳定性 | `preview` |
| 依赖 | `Locale`、`PluralRules`、`Map`、`List`、`BasicError`、`ErrorKind` |

---

## 1. 定位

消息模板格式化：命名占位符 `{name}`、位置占位符 `{0}`、转义 `{{`/`}}`，以及显式 `plural`/`select` 辅助。

不做：ICU MessageFormat 内联语法（`{count, plural, ...}`）、嵌套消息、数字/日期占位符、HTML 转义、全局模板缓存。

---

## 2. 设计逻辑

- 字段 `_locale` 与 `_pluralRules`；不可变。
- `format` 处理命名 Map；`formatArgs` 把 List 下标转成 `"0"`、`"1"` 后复用 `format`。
- 占位符名允许字母、数字、`_`、`.`、`-`；空名/其他字符报错。
- 缺失占位符是 `InvalidArgument`，不保留原样、不替换空串、不忽略。
- 未使用的额外值被忽略；null 值报错。
- `{{` 输出 `{`，`}}` 输出 `}`；单个 `{`/`}` 报错。
- `plural` 委托 `PluralRules.select`；`select` 先精确匹配，再 `other`，都没有则报错。
- 没有全局 formatter；locale 由构造参数决定。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_locale` | `Locale` | 格式 locale |
| `_pluralRules` | `PluralRules` | 与 locale 绑定的复数规则 |

不变量：locale 非 null；PluralRules 的 locale 与 `_locale` 相同；不可变。

---

## 4. 生命周期

构造后不可变；无 close；可共享；`plural`/`select` 无状态。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `MessageFormatter(Locale locale)` | locale | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `format` | 命名占位符 | `String template, Map<String,String> values` | `Result<String, Error>` | 缺失/非法占位符 |
| `formatArgs` | 位置占位符 | `String template, List<String> arguments` | `Result<String, Error>` | 缺失/非法占位符 |
| `plural` | 复数形式 | `Double count, Map<String,String> forms` | `Result<String, Error>` | 非有限/缺形式 |
| `select` | 枚举分支 | `String value, Map<String,String> cases` | `Result<String, Error>` | 缺分支 |
| `locale` | 格式 locale | 无 | `Locale` | 无 |

说明：

- `format` 的参数 Map 不修改；缺失 key 的错误消息包含占位符名。
- `formatArgs` 的索引从 0 开始，必须是十进制数字；越界报缺失占位符。
- `plural` 的 `forms` 键是 `zero`/`one`/`two`/`few`/`many`/`other`；至少需要 `other`，否则缺失类别报错。
- `select` 的 `cases` 键是任意字符串；`other` 是兜底；没有 `other` 且无精确匹配则报错。
- 模板中的 `{0}` 在 `format` 中按普通命名键处理；在 `formatArgs` 中按位置处理。
- 不支持 format spec（如 `{count:number}`）、嵌套 `{}`、反斜杠转义；这些属于 X。

---

## 8. 使用的技术

- 单遍字符扫描；
- 花括号转义；
- Map/List 查表；
- 占位符名白名单；
- 复数规则委托；
- Result 错误传播。

---

## 9. 需要的支撑

- 语言：class、String、Int、Bool、Double、Result、Map、List；
- 运行时：无；
- 接口：`Locale`、`PluralRules`、`isNaN`、`isInf`、`str`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Locale`、`PluralRules`、`Map<String,String>`、`List<String>`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

不可变；引用语义；可跨任务共享；无资源；`format`/`formatArgs`/`plural`/`select` 可并发调用。

---

## 12. 示例与反例

正确：`new MessageFormatter(Locale.parse("en-US").value()).format("Hello, {name}", values)`。  
正确：`formatter.formatArgs("{0} of {1}", arguments)`。  
正确：`formatter.plural(2.0, ["one": "{0} file", "other": "{0} files"])`。  
正确：`formatter.select("admin", ["admin": "Administrator", "other": "User"])`。  
反例：缺失占位符期望保留 `{name}`；用 ICU `{count, plural, ...}`；把 null value 当空串；用单个 `}` 作为字面量；在模板里做数字格式化。

---

## 13. 测试/场景义务

命名占位符/位置占位符；多个占位符；重复占位符；`{{`/`}}`；未闭合 `{`；孤立 `}`；空名；非法字符；缺失键；null 值；额外值；空模板；`formatArgs` 越界/非数字名；`plural` 各形式/缺 `other`/非有限 count；`select` 精确/`other`/缺失；并发只读。

---

## 14. XNull 伪代码

```xnull
class MessageFormatter {
    final Locale _locale
    final PluralRules _pluralRules

    MessageFormatter(Locale locale) {
        if locale == null {
            throw "MessageFormatter: null locale"
        }
        _locale = locale
        _pluralRules = new PluralRules(locale)
    }

    Result<String, Error> format(String template, Map<String, String> values) {
        if template == null || values == null {
            throw "MessageFormatter.format: null argument"
        }
        String result = ""
        Int index = 0
        while index < template.length() {
            String current = template.substring(index, 1)
            if current == "{" {
                if index + 1 < template.length()
                    && template.substring(index + 1, 1) == "{" {
                    result = result + "{"
                    index = index + 2
                } else {
                    Int close = index + 1
                    while close < template.length() && template.charAt(close) != '}' {
                        close = close + 1
                    }
                    if close >= template.length() {
                        return Err(new BasicError(ErrorKind.InvalidArgument,
                            "unclosed placeholder"))
                    }
                    String name = template.substring(index + 1, close - index - 1)
                    if !MessageFormatter.isPlaceholderName(name) {
                        return Err(new BasicError(ErrorKind.InvalidArgument,
                            "invalid placeholder: " + name))
                    }
                    if !values.has(name) {
                        return Err(new BasicError(ErrorKind.InvalidArgument,
                            "missing placeholder: " + name))
                    }
                    String value = values.get(name)
                    if value == null {
                        return Err(new BasicError(ErrorKind.InvalidArgument,
                            "null placeholder: " + name))
                    }
                    result = result + value
                    index = close + 1
                }
            } else if current == "}" {
                if index + 1 < template.length()
                    && template.substring(index + 1, 1) == "}" {
                    result = result + "}"
                    index = index + 2
                } else {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "unmatched '}'"))
                }
            } else {
                result = result + current
                index = index + 1
            }
        }
        return Ok(result)
    }

    Result<String, Error> formatArgs(String template, List<String> arguments) {
        if template == null || arguments == null {
            throw "MessageFormatter.formatArgs: null argument"
        }
        Map<String, String> values = new Map<String, String>()
        Int index = 0
        while index < arguments.length() {
            String value = arguments.get(index)
            if value == null {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "null argument: " + str(index)))
            }
            values.put(str(index), value)
            index = index + 1
        }
        return self.format(template, values)
    }

    Result<String, Error> plural(Double count, Map<String, String> forms) {
        if forms == null {
            throw "MessageFormatter.plural: null forms"
        }
        if isNaN(count) || isInf(count) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "non-finite plural count"))
        }
        return _pluralRules.select(count, forms)
    }

    Result<String, Error> select(String value, Map<String, String> cases) {
        if value == null || cases == null {
            throw "MessageFormatter.select: null argument"
        }
        if cases.has(value) {
            String selected = cases.get(value)
            if selected == null {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "null select case: " + value))
            }
            return Ok(selected)
        }
        if cases.has("other") {
            String fallback = cases.get("other")
            if fallback == null {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "null select fallback"))
            }
            return Ok(fallback)
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "missing select case: " + value))
    }

    Locale locale() { return _locale }

    private static Bool isPlaceholderName(String name) {
        if name == "" { return false }
        Int index = 0
        while index < name.length() {
            Char character = name.charAt(index)
            Bool valid = (character >= 'a' && character <= 'z')
                || (character >= 'A' && character <= 'Z')
                || (character >= '0' && character <= '9')
                || character == '_' || character == '.' || character == '-'
            if !valid { return false }
            index = index + 1
        }
        return true
    }
}
```
