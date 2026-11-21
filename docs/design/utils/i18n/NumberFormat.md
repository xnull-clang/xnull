# `NumberFormat`

| 项 | 值 |
| --- | --- |
| 类型 | `class NumberFormat` |
| 包 | `xdk.i18n` |
| 稳定性 | `preview` |
| 依赖 | `Locale`、`Decimal`、`RoundingMode`、`BasicError`、`ErrorKind` |

---

## 1. 定位

locale 驱动的数字格式化/解析：模式决定最少整数位、最少/最多小数位、分组；locale 决定分组符与小数符。

不做：货币/百分比/科学计数法、完整 CLDR 数字系统、印度分组、负数子模式、任意精度、全局默认 locale。

---

## 2. 设计逻辑

- 字段：locale、pattern、前缀/后缀、最少整数位、最少/最多小数位、是否分组、分组符、小数符；不可变。
- 模式子集：`#` 可选数字、`0` 必选数字、`,` 分组、`.` 小数；其他字符作为字面前缀/后缀。
- 构造期校验模式；非法模式抛。合法示例：`#,##0.###`、`#,##0.00`、`0`、`0.0`、`USD #,##0.00`。
- `format(Long)` 精确；`format(Double)` 先转 `Decimal`，按 `HalfUp` 舍入到最大小数位，再按最少/最多小数位裁剪。
- `format(Double)` 的 NaN/Infinity 返回 `NaN`/`Infinity`/`-Infinity`；超出 `Decimal` 范围时回退 `str(value)`（可能含指数），不分组。
- `parse` 严格校验分组、单个小数符、前缀/后缀；返回 `Double`，非有限结果报错。
- 分隔符由 language/country 子集决定；不读全局 locale。
- 没有全局 pattern 注册表。

| locale 子集 | 分组符 | 小数符 |
| --- | --- | --- |
| `en`、`ja`、`ko`、`zh`、`th`、`vi`、`id`、`ms`、`tr` | `,` | `.` |
| `de`、`es`、`it`、`nl`、`pt` | `.` | `,` |
| `fr-FR` | U+202F | `,` |
| `fr-CA` | U+00A0 | `,` |
| `ru`、`uk`、`pl` | U+00A0 | `,` |
| `de-CH` | `'` | `.` |
| `es-MX` | `,` | `.` |
| `pt-PT` | U+00A0 | `,` |

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_locale` | `Locale` | 格式 locale |
| `_pattern` | `String` | 原始模式 |
| `_prefix` | `String` | 字面前缀 |
| `_suffix` | `String` | 字面后缀 |
| `_minIntegerDigits` | `Int` | ≥1 |
| `_minFractionDigits` | `Int` | ≥0，≤ `_maxFractionDigits` |
| `_maxFractionDigits` | `Int` | ≥0 |
| `_grouping` | `Bool` | 是否启用分组 |
| `_groupingSeparator` | `String` | 分组符 |
| `_decimalSeparator` | `String` | 小数符 |

不变量：模式至少一个数字占位符；最多一个小数点；分组段合法；前缀/后缀不含数字占位符、`%`、`‰`、`¤`、`+`、`-`、`.`、`,`；0 ≤ 最少小数位 ≤ 最大小数位 ≤ 18。

---

## 4. 生命周期

不可变；构造期完成模式解析；无 close；可共享；`withPattern` 返回新实例。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `NumberFormat(Locale locale, String pattern)` | locale/pattern | 见 §2/§3 | 非法 → panic |
| `NumberFormat.ofPattern(Locale, String)` | 同上 | 同上 | 同上 |
| `NumberFormat.decimal(Locale)` | locale | 非 null | null → panic；模式 `#,##0.###` |
| `withPattern(String pattern)` | pattern | 见 §2/§3 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `format` | 格式化 Long | `Long value` | `String` | 无 |
| `format` | 格式化 Double | `Double value` | `String` | 无；非有限有固定文本 |
| `parse` | 解析数字 | `String text` | `Result<Double, Error>` | `InvalidArgument` |
| `withPattern` | 换模式 | `String pattern` | `NumberFormat` | 非法 → panic |
| `ofPattern` | 静态构造 | `Locale, String` | `NumberFormat` | 非法 → panic |
| `decimal` | 通用小数格式 | `Locale` | `NumberFormat` | null → panic |
| `locale` | locale | 无 | `Locale` | 无 |
| `pattern` | 模式 | 无 | `String` | 无 |
| `groupingSeparator` | 分组符 | 无 | `String` | 无 |
| `decimalSeparator` | 小数符 | 无 | `String` | 无 |

说明：

- 模式只允许一个小数点；小数点后不能为空；最多 18 位小数（`Decimal` 限制）。
- 分组模式中，第一段 1–3 个占位符，后续每段恰好 3 个；`#,##0` 合法，`0,00` 非法。
- 没有 `,` 的模式不分组；`#` 只控制可选性，最少整数位由 `0` 的数量决定，至少 1。
- 负号固定放在前缀之前；不支持 `;` 负数子模式。
- `format(Double)` 的小数位按最大位数四舍五入，再裁掉多于最少位数的尾零。
- `parse` 接受可选 `+`/`-`、模式前缀/后缀、可选分组；不接受货币符号、百分号、指数、空白夹在数字中。
- `parse` 先 `trim` 输入；pattern 的前缀/后缀不要依赖首尾空白。
- `parse` 的分组若出现，必须是 1–3 位首段 + 每段 3 位；不强制必须有分组。
- `parse` 不限制小数位数；模式只影响格式化。
- `parse` 溢出为 Infinity 时返回 `InvalidArgument`。

---

## 8. 使用的技术

- 模式解析与校验；
- `Decimal` 十进制舍入；
- 三位分组插入；
- locale 分隔符子集；
- 严格分组/小数符校验；
- 前缀/后缀匹配。

---

## 9. 需要的支撑

- 语言：class、String、Int、Bool、Double、Long、Result、List；
- 运行时：`Decimal`、`RoundingMode`、`str`、`contains`、`startsWith`、`endsWith`、`indexOf`、`split`、`replaceAll`、`isNumeric`、`trim`、`parseDouble`、`isNaN`、`isInf`；
- 接口：`Locale`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Locale`、`Decimal`、`RoundingMode`、`BasicError`、`ErrorKind`、`xdk.text` 数字/字符串函数。

---

## 11. 所有权与并发

不可变；引用语义；可跨任务共享；无资源；`format`/`parse` 无内部可变状态。

---

## 12. 示例与反例

正确：`NumberFormat.ofPattern(Locale.parse("en-US").value(), "#,##0.00").format(12345.678)` → `12,345.68`。  
正确：同一模式在 `de-DE` → `12.345,68`。  
正确：`format(42 as Long)` → `42.00`。  
正确：`parse("12.345,68")`（de-DE）→ `12345.68`。  
反例：期望 `%` 自动乘 100；期望 `¤` 货币符号；期望印度 `12,34,567` 分组；用 Double 做精确金额；用全局默认 locale；把 `"1,23,456"` 当合法分组。

---

## 13. 测试/场景义务

模式 `#,##0.###`/`#,##0.00`/`0`/`0.0`/`#`；非法模式（空、无占位符、两个小数点、空小数、坏分组、非法字符、`%`/`¤`/符号前缀）；Long 正/负/0/MIN；Double 0/正/负/小数/四舍五入/尾零裁剪/NaN/Infinity/超 Decimal 范围；en-US/de-DE/fr-FR/ru-RU/de-CH/es-MX/pt-PT 分隔符；parse 正/负/前缀/后缀/分组/无分组/多小数符/坏分组/非数字/空/溢出；withPattern；并发只读。

---

## 14. XNull 伪代码

```xnull
class NumberFormat {
    final Locale _locale
    final String _pattern
    final String _prefix
    final String _suffix
    final Int _minIntegerDigits
    final Int _minFractionDigits
    final Int _maxFractionDigits
    final Bool _grouping
    final String _groupingSeparator
    final String _decimalSeparator

    NumberFormat(Locale locale, String pattern) {
        if locale == null || pattern == null {
            throw "NumberFormat: null argument"
        }
        if pattern == "" {
            throw "NumberFormat: empty pattern"
        }
        Int first = -1
        Int last = -1
        Int index = 0
        while index < pattern.length() {
            Char character = pattern.charAt(index)
            if character == '0' || character == '#' {
                if first < 0 { first = index }
                last = index
            }
            index = index + 1
        }
        if first < 0 {
            throw "NumberFormat: pattern has no digit placeholder"
        }
        String prefix = pattern.substring(0, first)
        String suffix = pattern.substring(last + 1, pattern.length() - last - 1)
        NumberFormat.validateAffix(prefix)
        NumberFormat.validateAffix(suffix)
        String body = pattern.substring(first, last - first + 1)
        Int dot = indexOf(body, ".")
        String integerPattern = body
        String fractionPattern = ""
        if dot >= 0 {
            if indexOf(body.substring(dot + 1, body.length() - dot - 1), ".") >= 0 {
                throw "NumberFormat: multiple decimal points"
            }
            integerPattern = body.substring(0, dot)
            fractionPattern = body.substring(dot + 1, body.length() - dot - 1)
            if fractionPattern == "" {
                throw "NumberFormat: empty fraction pattern"
            }
        }
        if integerPattern == "" {
            throw "NumberFormat: empty integer pattern"
        }
        Bool grouping = false
        Int minInteger = 0
        index = 0
        while index < integerPattern.length() {
            Char character = integerPattern.charAt(index)
            if character == '0' {
                minInteger = minInteger + 1
            } else if character == ',' {
                grouping = true
            } else if character != '#' {
                throw "NumberFormat: invalid integer pattern"
            }
            index = index + 1
        }
        if minInteger == 0 {
            minInteger = 1
        }
        if grouping {
            List<String> groups = split(integerPattern, ",")
            if groups.length() < 2 {
                throw "NumberFormat: invalid grouping"
            }
            index = 0
            while index < groups.length() {
                String group = groups.get(index)
                if group == "" {
                    throw "NumberFormat: empty grouping segment"
                }
                Int digitCount = 0
                Int groupIndex = 0
                while groupIndex < group.length() {
                    Char character = group.charAt(groupIndex)
                    if character == '0' || character == '#' {
                        digitCount = digitCount + 1
                    } else {
                        throw "NumberFormat: invalid grouping"
                    }
                    groupIndex = groupIndex + 1
                }
                if index == 0 {
                    if digitCount < 1 || digitCount > 3 {
                        throw "NumberFormat: invalid first group"
                    }
                } else if digitCount != 3 {
                    throw "NumberFormat: invalid group width"
                }
                index = index + 1
            }
        }
        Int minFraction = 0
        Int maxFraction = fractionPattern.length()
        if maxFraction > 18 {
            throw "NumberFormat: too many fraction digits"
        }
        index = 0
        while index < fractionPattern.length() {
            Char character = fractionPattern.charAt(index)
            if character == '0' {
                minFraction = minFraction + 1
            } else if character != '#' {
                throw "NumberFormat: invalid fraction pattern"
            }
            index = index + 1
        }
        _locale = locale
        _pattern = pattern
        _prefix = prefix
        _suffix = suffix
        _minIntegerDigits = minInteger
        _minFractionDigits = minFraction
        _maxFractionDigits = maxFraction
        _grouping = grouping
        _groupingSeparator = NumberFormat.groupingFor(locale)
        _decimalSeparator = NumberFormat.decimalFor(locale)
    }

    static NumberFormat ofPattern(Locale locale, String pattern) {
        return new NumberFormat(locale, pattern)
    }

    static NumberFormat decimal(Locale locale) {
        return new NumberFormat(locale, "#,##0.###")
    }

    Locale locale() { return _locale }
    String pattern() { return _pattern }
    String groupingSeparator() { return _groupingSeparator }
    String decimalSeparator() { return _decimalSeparator }

    String format(Long value) {
        String text = str(value)
        Bool negative = false
        if startsWith(text, "-") {
            negative = true
            text = text.substring(1, text.length() - 1)
        }
        String integerPart = text
        String fractionPart = ""
        Int dot = indexOf(text, ".")
        if dot >= 0 {
            integerPart = text.substring(0, dot)
            fractionPart = text.substring(dot + 1, text.length() - dot - 1)
        }
        while integerPart.length() < _minIntegerDigits {
            integerPart = "0" + integerPart
        }
        while fractionPart.length() < _minFractionDigits {
            fractionPart = fractionPart + "0"
        }
        return self.render(negative, integerPart, fractionPart)
    }

    String format(Double value) {
        if isNaN(value) {
            return "NaN"
        }
        if isInf(value) {
            if value < 0.0 {
                return "-Infinity"
            }
            return "Infinity"
        }
        Result<Decimal, Error> converted = Decimal.fromDouble(value)
        if converted.isErr() {
            return str(value)
        }
        Result<Decimal, Error> scaled = converted.value().setScale(
            _maxFractionDigits, RoundingMode.HalfUp)
        if scaled.isErr() {
            return str(value)
        }
        String text = scaled.value().toString()
        Bool negative = false
        if startsWith(text, "-") {
            negative = true
            text = text.substring(1, text.length() - 1)
        }
        String integerPart = text
        String fractionPart = ""
        Int dot = indexOf(text, ".")
        if dot >= 0 {
            integerPart = text.substring(0, dot)
            fractionPart = text.substring(dot + 1, text.length() - dot - 1)
        }
        while fractionPart.length() > _minFractionDigits && endsWith(fractionPart, "0") {
            fractionPart = fractionPart.substring(0, fractionPart.length() - 1)
        }
        while integerPart.length() < _minIntegerDigits {
            integerPart = "0" + integerPart
        }
        while fractionPart.length() < _minFractionDigits {
            fractionPart = fractionPart + "0"
        }
        return self.render(negative, integerPart, fractionPart)
    }

    Result<Double, Error> parse(String text) {
        if text == null {
            throw "NumberFormat.parse: null text"
        }
        String working = trim(text)
        if working == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "empty number"))
        }
        Bool negative = false
        if startsWith(working, "-") {
            negative = true
            working = working.substring(1, working.length() - 1)
        } else if startsWith(working, "+") {
            working = working.substring(1, working.length() - 1)
        }
        if _prefix != "" {
            if !startsWith(working, _prefix) {
                return Err(new BasicError(ErrorKind.InvalidArgument, "missing number prefix"))
            }
            working = working.substring(_prefix.length(), working.length() - _prefix.length())
        }
        if _suffix != "" {
            if !endsWith(working, _suffix) {
                return Err(new BasicError(ErrorKind.InvalidArgument, "missing number suffix"))
            }
            working = working.substring(0, working.length() - _suffix.length())
        }
        if working == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "empty number body"))
        }
        String integerText = working
        String fractionText = ""
        Int dot = indexOf(working, _decimalSeparator)
        if dot >= 0 {
            Int afterDot = dot + _decimalSeparator.length()
            if indexOf(working.substring(afterDot, working.length() - afterDot),
                _decimalSeparator) >= 0 {
                return Err(new BasicError(ErrorKind.InvalidArgument, "multiple decimal separators"))
            }
            integerText = working.substring(0, dot)
            fractionText = working.substring(afterDot, working.length() - afterDot)
            if fractionText == "" {
                return Err(new BasicError(ErrorKind.InvalidArgument, "missing fraction digits"))
            }
        }
        if integerText == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "missing integer digits"))
        }
        if _grouping && contains(integerText, _groupingSeparator) {
            List<String> groups = split(integerText, _groupingSeparator)
            if groups.length() < 2 {
                return Err(new BasicError(ErrorKind.InvalidArgument, "invalid grouping"))
            }
            Int groupIndex = 0
            while groupIndex < groups.length() {
                String group = groups.get(groupIndex)
                if group == "" || !isNumeric(group) {
                    return Err(new BasicError(ErrorKind.InvalidArgument, "invalid grouping"))
                }
                if groupIndex == 0 {
                    if group.length() < 1 || group.length() > 3 {
                        return Err(new BasicError(ErrorKind.InvalidArgument, "invalid first group"))
                    }
                } else if group.length() != 3 {
                    return Err(new BasicError(ErrorKind.InvalidArgument, "invalid group width"))
                }
                groupIndex = groupIndex + 1
            }
        }
        String normalizedInteger = integerText
        if _grouping {
            normalizedInteger = replaceAll(integerText, _groupingSeparator, "")
        }
        if normalizedInteger == "" || !isNumeric(normalizedInteger) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid integer digits"))
        }
        if fractionText != "" && !isNumeric(fractionText) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid fraction digits"))
        }
        String normalized = normalizedInteger
        if fractionText != "" {
            normalized = normalized + "." + fractionText
        }
        if negative {
            normalized = "-" + normalized
        }
        Result<Double, Error> parsed = parseDouble(normalized)
        if parsed.isErr() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid number: " + text))
        }
        if isNaN(parsed.value()) || isInf(parsed.value()) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "number out of range"))
        }
        return parsed
    }

    NumberFormat withPattern(String pattern) {
        return new NumberFormat(_locale, pattern)
    }

    private String render(Bool negative, String integerPart, String fractionPart) {
        String grouped = integerPart
        if _grouping {
            grouped = self.group(integerPart)
        }
        String body = grouped
        if fractionPart.length() > 0 {
            body = body + _decimalSeparator + fractionPart
        }
        String result = _prefix + body + _suffix
        if negative {
            result = "-" + result
        }
        return result
    }

    private String group(String digits) {
        Int firstGroup = digits.length() % 3
        if firstGroup == 0 {
            firstGroup = 3
        }
        String result = digits.substring(0, firstGroup)
        Int index = firstGroup
        while index < digits.length() {
            result = result + _groupingSeparator + digits.substring(index, 3)
            index = index + 3
        }
        return result
    }

    private static void validateAffix(String text) {
        if contains(text, "%") || contains(text, "\u2030") || contains(text, "\u00A4") {
            throw "NumberFormat: unsupported pattern symbol"
        }
        if contains(text, "+") || contains(text, "-") {
            throw "NumberFormat: sign in affix is not supported"
        }
        if contains(text, ".") || contains(text, ",") {
            throw "NumberFormat: separator in affix is not supported"
        }
    }

    private static String groupingFor(Locale locale) {
        String language = locale.language()
        String country = locale.country()
        if language == "de" && country == "CH" {
            return "'"
        }
        if language == "fr" {
            if country == "CA" {
                return "\u00A0"
            }
            return "\u202F"
        }
        if language == "ru" || language == "uk" || language == "pl" {
            return "\u00A0"
        }
        if language == "es" && country == "MX" {
            return ","
        }
        if language == "pt" && country == "PT" {
            return "\u00A0"
        }
        if language == "de" || language == "es" || language == "it"
            || language == "nl" || language == "pt" {
            return "."
        }
        return ","
    }

    private static String decimalFor(Locale locale) {
        String language = locale.language()
        String country = locale.country()
        if language == "de" && country == "CH" {
            return "."
        }
        if language == "es" && country == "MX" {
            return "."
        }
        if language == "de" || language == "es" || language == "it"
            || language == "nl" || language == "pt" || language == "fr"
            || language == "ru" || language == "uk" || language == "pl" {
            return ","
        }
        return "."
    }
}
```
