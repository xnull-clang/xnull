# `Locale`

| 项 | 值 |
| --- | --- |
| 类型 | `class Locale` |
| 包 | `xdk.i18n` |
| 稳定性 | `preview` |
| 依赖 | `BasicError`、`ErrorKind`、`xdk.text` |

---

## 1. 定位

语言/国家/变体值对象：`language[-country][-variant]`，用于消息目录、复数、数字和日期格式。

不做：全局默认 locale、脚本子标签、BCP 47 扩展/私有段、文本方向、排序规则、运行时语言协商。

---

## 2. 设计逻辑

- 字段只有 `_language`、`_country`、`_variant`；不可变。
- `language` 归一为小写；`country` 归一为大写；`variant` 归一为大写。
- `und` 表示 root；root 不允许带 country/variant。
- `parse` 接受 `-` 或 `_` 分隔；只接受 2–3 位语言、2 位字母或 3 位数字国家、合法变体。
- 构造器校验失败是编程错误，直接抛；用户输入走 `parse`，返回 `Result`。
- 不读取环境变量/系统默认值；没有 `Locale.default()`。
- 相等按规范化后的三个字段比较。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_language` | `String` | 2–3 位 ASCII 字母或 `und`；小写 |
| `_country` | `String` | 空、2 位 ASCII 字母或 3 位数字；大写 |
| `_variant` | `String` | 空、4 位数字开头或 5–8 位字母数字；大写 |

不变量：`_language` 合法；`_country`/`_variant` 合法；`und` 只能与空 country/variant 组合；值不可变。

---

## 4. 生命周期

不可变；无 close；可自由共享；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Locale(String language, String country, String variant)` | 三个子标签 | 见 §3 | 非法 → panic |
| `Locale.of(String language, String country)` | language/country | 见 §3 | 非法 → panic |
| `Locale.of(String language)` | language | 见 §3 | 非法 → panic |
| `Locale.root()` | 无 | `und` | 无 |
| `Locale.parse(String tag)` | 语言标签 | BCP 47 子集 | `InvalidArgument` |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `language` | 语言 | 无 | `String` | 无 |
| `country` | 国家/地区 | 无 | `String` | 无 |
| `variant` | 变体 | 无 | `String` | 无 |
| `isRoot` | 是否 root | 无 | `Bool` | 无 |
| `equals` | 值相等 | `Locale other` | `Bool` | 无 |
| `toString` | 规范标签 | 无 | `String` | 无 |
| `parse` | 解析标签 | `String tag` | `Result<Locale, Error>` | `InvalidArgument` |
| `of` | 构造两段 | `String language, String country` | `Locale` | 非法 → panic |
| `of` | 构造一段 | `String language` | `Locale` | 非法 → panic |
| `root` | root locale | 无 | `Locale` | 无 |

说明：

- `parse` 先 `trim`，再把 `_` 替换为 `-`；空标签报错。
- 两个子标签时，第二段若是国家则作为 country；若符合变体规则则作为 variant。
- 三个子标签时，第二段必须是 country，第三段必须是 variant；variant 不能脱离 country 出现在三段形式中。
- `zh-Hans-CN` 的第二段 `Hans` 既不是国家也不是合法变体，返回 `InvalidArgument`。
- 超过三个子标签（扩展/私有段）返回 `InvalidArgument`。
- `toString` 对 root 返回 `und`；其余按 `language[-country][-variant]` 拼接。
- `equals` 对 null 返回 false。

---

## 8. 使用的技术

- BCP 47 子集解析；
- 大小写归一；
- ASCII 字母/数字校验；
- 标签分段与重组；
- 值语义比较。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Result、List；
- 运行时：无；
- 接口：`trim`、`replaceAll`、`split`、`toLower`、`toUpper`、`isAscii`、`isAlpha`、`isNumeric`、`isAlnum`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`String`、`List<String>`、`Result`、`BasicError`、`ErrorKind`、`xdk.text` 的字符串判断与变换函数。

---

## 11. 所有权与并发

不可变值对象；可跨任务共享；无资源；无锁。

---

## 12. 示例与反例

正确：`Locale.parse("en-us").value().toString()` → `en-US`。  
正确：`Locale.parse("de_CH_1901").value().toString()` → `de-CH-1901`。  
正确：`Locale.parse("es-419").value().toString()` → `es-419`。  
正确：`Locale.root().toString()` → `und`。  
反例：期望 `Locale.parse("zh-Hans-CN")` 保留脚本；期望空标签返回系统默认 locale；把 `en-US` 与 `en-us` 当成不同值；用可变全局 locale 做格式化。

---

## 13. 测试/场景义务

一段/两段/三段标签；`-` 与 `_`；大小写归一；2 位字母国家；3 位数字国家；4 位数字开头变体；5–8 位字母数字变体；语言+变体（无国家）；root；空标签；空子标签；脚本子标签拒绝；扩展拒绝；非法字符；equals；toString 往返。

---

## 14. XNull 伪代码

```xnull
class Locale {
    final String _language
    final String _country
    final String _variant

    Locale(String language, String country, String variant) {
        if language == null || country == null || variant == null {
            throw "Locale: null argument"
        }
        String normalizedLanguage = toLower(trim(language))
        String normalizedCountry = toUpper(trim(country))
        String normalizedVariant = toUpper(trim(variant))
        if !Locale.isValidLanguage(normalizedLanguage) {
            throw "Locale: invalid language"
        }
        if !Locale.isValidCountry(normalizedCountry) {
            throw "Locale: invalid country"
        }
        if !Locale.isValidVariant(normalizedVariant) {
            throw "Locale: invalid variant"
        }
        if normalizedLanguage == "und"
            && (normalizedCountry != "" || normalizedVariant != "") {
            throw "Locale: root locale cannot have country or variant"
        }
        _language = normalizedLanguage
        _country = normalizedCountry
        _variant = normalizedVariant
    }

    static Locale of(String language, String country) {
        return new Locale(language, country, "")
    }

    static Locale of(String language) {
        return new Locale(language, "", "")
    }

    static Locale root() {
        return new Locale("und", "", "")
    }

    static Result<Locale, Error> parse(String tag) {
        if tag == null { throw "Locale.parse: null tag" }
        String normalized = trim(tag)
        if normalized == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "empty locale tag"))
        }
        normalized = replaceAll(normalized, "_", "-")
        List<String> parts = split(normalized, "-")
        if parts.length() > 3 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "locale extensions are not supported"))
        }
        String language = toLower(parts.get(0))
        if !Locale.isValidLanguage(language) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid language: " + language))
        }
        String country = ""
        String variant = ""
        if parts.length() >= 2 {
            String second = parts.get(1)
            if second == "" {
                return Err(new BasicError(ErrorKind.InvalidArgument, "empty locale subtag"))
            }
            if Locale.isValidCountry(second) {
                country = toUpper(second)
            } else if parts.length() == 2 && Locale.isValidVariant(second) {
                variant = toUpper(second)
            } else {
                return Err(new BasicError(ErrorKind.InvalidArgument, "unsupported locale subtag: " + second))
            }
        }
        if parts.length() == 3 {
            if country == "" {
                return Err(new BasicError(ErrorKind.InvalidArgument, "variant requires country"))
            }
            String third = parts.get(2)
            if !Locale.isValidVariant(third) {
                return Err(new BasicError(ErrorKind.InvalidArgument, "invalid variant: " + third))
            }
            variant = toUpper(third)
        }
        if language == "und" && (country != "" || variant != "") {
            return Err(new BasicError(ErrorKind.InvalidArgument, "root locale cannot have country or variant"))
        }
        return Ok(new Locale(language, country, variant))
    }

    String language() { return _language }
    String country() { return _country }
    String variant() { return _variant }

    Bool isRoot() {
        return _language == "und" && _country == "" && _variant == ""
    }

    Bool equals(Locale other) {
        if other == null { return false }
        return _language == other._language
            && _country == other._country
            && _variant == other._variant
    }

    String toString() {
        if self.isRoot() { return "und" }
        String result = _language
        if _country != "" {
            result = result + "-" + _country
        }
        if _variant != "" {
            result = result + "-" + _variant
        }
        return result
    }

    private static Bool isValidLanguage(String language) {
        if !isAscii(language) || !isAlpha(language) {
            return false
        }
        return language.length() >= 2 && language.length() <= 3
    }

    private static Bool isValidCountry(String country) {
        if country == "" { return true }
        if !isAscii(country) { return false }
        if country.length() == 2 {
            return isAlpha(country)
        }
        if country.length() == 3 {
            return isNumeric(country)
        }
        return false
    }

    private static Bool isValidVariant(String variant) {
        if variant == "" { return true }
        if !isAscii(variant) || !isAlnum(variant) {
            return false
        }
        if variant.length() >= 5 && variant.length() <= 8 {
            return true
        }
        if variant.length() == 4 {
            Char first = variant.charAt(0)
            return first >= '0' && first <= '9'
        }
        return false
    }
}
```
