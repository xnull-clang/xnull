# `PluralRules`

| 项 | 值 |
| --- | --- |
| 类型 | `class PluralRules` |
| 包 | `xdk.i18n` |
| 稳定性 | `preview` |
| 依赖 | `Locale`、`Map`、`BasicError`、`ErrorKind` |

---

## 1. 定位

按 locale 选择复数类别：`category(Double)` 返回 `zero`/`one`/`two`/`few`/`many`/`other`，`select(count, forms)` 从消息形式表中取文本。

不做：完整 CLDR 规则、任意语言/方言、序数规则、区间规则、货币复数、全局规则注册表。

---

## 2. 设计逻辑

- 字段只有 `_locale`；不可变；country/variant 不参与规则，只看 language。
-  支持四个文档化子集：
  - `oneOther`：`en`、`de`、`nl`、`sv`、`da`、`no`、`nb`、`es`、`it`、`fi`、`et`、`el`；
  - `zeroOne`：`fr`（整数部分 0 或 1 为 `one`）；
  - `slavic`：`ru`、`uk`（1 / 2–4 / 其他整数；非整数 `other`）；
  - `otherOnly`：`ja`、`ko`、`zh`、`th`、`vi`、`id`、`ms`、`tr`。
- 未知语言回退到 `oneOther`（英语型），文档明确这是近似。
- count 取绝对值；NaN/Infinity 是合同错误，`category` 抛。
- `select` 优先精确类别，其次 `other`；两者都缺返回 `InvalidArgument`。
- 不返回 `zero`/`two`/`few`/`many` 的语言，不强行伪造这些类别；调用方可以只提供 `one`/`other`。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_locale` | `Locale` | 规则 locale |

不变量：locale 非 null；规则只由 language 决定；不可变。

---

## 4. 生命周期

不可变；无 close；可共享；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `PluralRules(Locale locale)` | locale | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `category` | 复数类别 | `Double count` | `String` | 非有限 → panic |
| `select` | 选择形式 | `Double count, Map<String,String> forms` | `Result<String, Error>` | 缺 `other`/缺类别 |
| `locale` | 规则 locale | 无 | `Locale` | 无 |

说明：

- `category` 返回六个字符串之一；调用方不要假设某个语言一定产生全部类别。
- `count` 为负数时按绝对值处理；`-1` 与 `1` 同类别。
- `count` 为小数时按整数部分/规则判断：英语型只有精确 `1.0` 是 `one`；法语型整数部分 0/1 是 `one`；斯拉夫型非整数是 `other`。
- `select` 的 `forms` 不修改；缺失类别但存在 `other` 时用 `other`。
- `forms` 可以有 `zero`/`two`/`few`/`many` 等额外键；规则不产生的键不会被选中。
- 完整 CLDR 规则、`ordinal`、`range` 属于 X。

---

## 8. 使用的技术

- CLDR 复数子集；
- 模 10 / 模 100 判断；
- 整数/小数分离；
- 绝对值；
- Map 形式选择。

---

## 9. 需要的支撑

- 语言：class、String、Double、Long、Bool、Result、Map；
- 运行时：浮点取模、类型转换；
- 接口：`Locale`、`isNaN`、`isInf`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Locale`、`Map<String,String>`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

不可变；引用语义；可跨任务共享；无资源；无锁。

---

## 12. 示例与反例

正确：`new PluralRules(Locale.parse("en").value()).category(1.0)` → `one`。  
正确：`category(2.0)` → `other`；`category(1.5)` → `other`。  
正确：俄语 `category(1.0)` → `one`，`category(2.0)` → `few`，`category(5.0)` → `many`，`category(1.5)` → `other`。  
正确：法语 `category(0.0)` → `one`，`category(1.5)` → `one`。  
反例：期望英语 `0` 返回 `zero`；期望所有语言都有六类；用负数触发不同类别；把 `many` 当成“大于 1”；期望完整 CLDR 的阿拉伯语规则。

---

## 13. 测试/场景义务

英语 0/1/2/1.5/-1；法语 0/1/1.5/2；俄语 1/2/4/5/11/12/21/22/25/1.5；乌克兰语同型；日语/中文/韩语/泰语/越南语/印尼语/马来语/土耳其语始终 `other`；未知语言英语型；`select` 精确/回退 `other`/缺 `other`/额外键；非有限 count panic；locale 访问。

---

## 14. XNull 伪代码

```xnull
class PluralRules {
    final Locale _locale

    PluralRules(Locale locale) {
        if locale == null {
            throw "PluralRules: null locale"
        }
        _locale = locale
    }

    String category(Double count) {
        if isNaN(count) || isInf(count) {
            throw "PluralRules.category: non-finite count"
        }
        Double value = count
        if value < 0.0 {
            value = 0.0 - value
        }
        String profile = self.profile()
        if profile == "other" {
            return "other"
        }
        if profile == "zeroOne" {
            Double integerPart = value - (value % 1.0)
            if integerPart == 0.0 || integerPart == 1.0 {
                return "one"
            }
            return "other"
        }
        if profile == "slavic" {
            if value % 1.0 != 0.0 {
                return "other"
            }
            if value >= 9223372036854775808.0 {
                return "many"
            }
            Long number = value as Long
            Long mod10 = number % 10
            Long mod100 = number % 100
            if mod10 == 1 && mod100 != 11 {
                return "one"
            }
            if mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14) {
                return "few"
            }
            return "many"
        }
        if value == 1.0 {
            return "one"
        }
        return "other"
    }

    Result<String, Error> select(Double count, Map<String, String> forms) {
        if forms == null {
            throw "PluralRules.select: null forms"
        }
        String category = self.category(count)
        if forms.has(category) {
            return Ok(forms.get(category))
        }
        if forms.has("other") {
            return Ok(forms.get("other"))
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "missing plural form: " + category))
    }

    Locale locale() { return _locale }

    private String profile() {
        String language = _locale.language()
        if language == "ru" || language == "uk" {
            return "slavic"
        }
        if language == "ja" || language == "ko" || language == "zh"
            || language == "th" || language == "vi" || language == "id"
            || language == "ms" || language == "tr" {
            return "other"
        }
        if language == "fr" {
            return "zeroOne"
        }
        return "oneOther"
    }
}
```
