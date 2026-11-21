# `Unicode`

| 项 | 值 |
| --- | --- |
| 类型 | `class Unicode` |
| 包 | `xdk.text` |
| 稳定性 | `preview` |
| 依赖 | `NormalizationForm` |

---

## 1. 定位

Unicode 字符分类、大小写、码点、规范化入口。

不做：完整 ICU、locale 敏感规则、字素簇分割、双向文本。

---

## 2. 设计逻辑

- 静态工具类；无实例状态。
- 分类/大小写依赖 Unicode 表；表版本由构建固定。
- 码点 API 使用字节索引；非法序列 panic。
- `normalize` 支持 NFC/NFD/NFKC/NFKD；完整表为 X， 只保证常用字符。
- `caseFold` 用于大小写无关比较；不替代 locale 规则。

---

## 3. 表示与不变量

无实例字段；只读 Unicode 表。

---

## 4. 生命周期

无实例；无 close。

---

## 5. 构造契约

静态类，不公开构造。

---

## 6. 字段表

无。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `isLetter` | 字母 | `Char character` | `Bool` | 无 |
| `isDigit` | 数字 | `Char character` | `Bool` | 无 |
| `isWhitespace` | 空白 | `Char character` | `Bool` | 无 |
| `isUpper` | 大写 | `Char character` | `Bool` | 无 |
| `isLower` | 小写 | `Char character` | `Bool` | 无 |
| `isTitle` | 标题大小写 | `Char character` | `Bool` | 无 |
| `toUpper` | 转大写 | `String text` | `String` | 无 |
| `toLower` | 转小写 | `String text` | `String` | 无 |
| `caseFold` | 大小写折叠 | `String text` | `String` | 无 |
| `normalize` | 规范化 | `String text, NormalizationForm form` | `String` | null form → panic |
| `codePointAt` | 码点 | `String text, Int byteIndex` | `Int` | 越界/非法 → panic |
| `charCount` | 码点字符数 | `Int codePoint` | `Int` | 非法 → panic |
| `isSurrogate` | 是否代理 | `Char character` | `Bool` | 无 |
| `decode` | UTF-8→码点 | `Bytes source` | `List<Int>` | 无（非法替换） |
| `encode` | 码点→UTF-8 | `String text` | `Bytes` | 非法 → panic |

---

## 8. 使用的技术

- Unicode 分类表；
- 大小写映射表；
- UTF-8/UTF-16 解码；
- 规范化表（ 子集）；
- 码点/代理对。

---

## 9. 需要的支撑

- 语言：class、Char、String、Int、Bool、List、Bytes；
- 运行时：Unicode 表、UTF-8 编解码；
- 接口：`Bytes`、`Utf16`、`NormalizationForm`、`BasicError`（规范化错误）。

---

## 10. 依赖的特性/接口/类

`Bytes`、`Utf16`、`NormalizationForm`、`BasicError`。

---

## 11. 所有权与并发

静态只读；可共享；无资源。

---

## 12. 示例与反例

正确：`isLetter('A')`；`toUpper("abc")`；`codePointAt(text,0)`。  
反例：把字节索引当码点索引；用 `toUpper` 做 locale 规则；依赖完整 ICU 行为。

---

## 13. 测试/场景义务

ASCII/BMP/补充平面；代理对；大小写；caseFold；normalize 常用形式；非法码点；UTF-8 解码。

---

## 14. XNull 伪代码

```xnull
class Unicode {
    static Bool isLetter(Char character) {
        return unicodeCategory(character) == UnicodeCategory.Letter
    }

    static Bool isDigit(Char character) {
        return unicodeCategory(character) == UnicodeCategory.Digit
    }

    static Bool isWhitespace(Char character) {
        return unicodeCategory(character) == UnicodeCategory.Space
    }

    static Bool isUpper(Char character) {
        return unicodeCategory(character) == UnicodeCategory.Upper
    }

    static Bool isLower(Char character) {
        return unicodeCategory(character) == UnicodeCategory.Lower
    }

    static Bool isTitle(Char character) {
        return unicodeCategory(character) == UnicodeCategory.Title
    }

    static String toUpper(String text) {
        String result = ""
        Int index = 0
        while index < text.length() {
            result = result + unicodeToUpper(text.charAt(index))
            index = index + 1
        }
        return result
    }

    static String toLower(String text) {
        String result = ""
        Int index = 0
        while index < text.length() {
            result = result + unicodeToLower(text.charAt(index))
            index = index + 1
        }
        return result
    }

    static String caseFold(String text) {
        return unicodeCaseFold(text)
    }

    static String normalize(String text, NormalizationForm form) {
        if form == null {
            throw "Unicode.normalize: null form"
        }
        return unicodeNormalize(text, form)
    }

    static Int codePointAt(String text, Int byteIndex) {
        if byteIndex < 0 || byteIndex >= text.length() {
            throw "Unicode.codePointAt: out of range"
        }
        return unicodeDecodeCodePoint(text, byteIndex)
    }

    static Int charCount(Int codePoint) {
        if codePoint < 0 || codePoint > 1114111 {
            throw "Unicode.charCount: invalid code point"
        }
        if codePoint <= 65535 {
            return 1
        }
        return 2
    }

    static Bool isSurrogate(Char character) {
        Int value = character as Int
        return value >= 55296 && value <= 57343
    }

    static List<Int> decode(Bytes source) {
        List<Int> result = []
        Int index = 0
        while index < source.length() {
            Int codePoint = decodeUtf8CodePoint(source, index)
            result.push(codePoint)
            index = index + codePointByteLength(source, index)
        }
        return result
    }

    static Bytes encode(String text) {
        return fromUtf8(text)
    }
}
```

> `unicodeCategory/unicodeToUpper/unicodeToLower/unicodeCaseFold/unicodeNormalize/unicodeDecodeCodePoint/decodeUtf8CodePoint/codePointByteLength` 是文本包内部 Unicode 原语。
