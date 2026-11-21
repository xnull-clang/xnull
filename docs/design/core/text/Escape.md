# `Escape`

| 项 | 值 |
| --- | --- |
| 类型 | `class Escape` |
| 包 | `xdk.text` |
| 稳定性 | `preview` |
| 依赖 | `StringBuilder`、`errors` |

---

## 1. 定位

文本转义/反转义：JSON、HTML、XML、CSV、shell、引号。

不做：完整序列化（codec）、HTML sanitizer、shell 安全策略。

---

## 2. 设计逻辑

- 静态工具类；无实例状态。
- 转义返回新字符串；不修改入参。
- `unescapeJson`/`unquote` 对非法输入返回 `Result`，不 panic。
- HTML/XML 转义只处理 `& < > " '`；不处理完整实体表。
- shell 转义用单引号包裹并转义单引号；不保证跨平台 shell 语义完全一致。

---

## 3. 表示与不变量

无实例字段。

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
| `json` | JSON 字符串转义 | `String text` | `String` | null → panic |
| `unescapeJson` | JSON 反转义 | `String text` | `Result<String, Error>` | `InvalidArgument` |
| `html` | HTML 转义 | `String text` | `String` | null → panic |
| `xml` | XML 转义 | `String text` | `String` | null → panic |
| `csv` | CSV 字段转义 | `String text` | `String` | null → panic |
| `shell` | shell 参数转义 | `String text` | `String` | null → panic |
| `quoted` | 加双引号并转义 | `String text` | `String` | null → panic |
| `unquote` | 去引号/反转义 | `String text` | `Result<String, Error>` | `InvalidArgument` |

---

## 8. 使用的技术

- 字符扫描；
- 转义表；
- `StringBuilder`；
- 十六进制 `\uXXXX`；
- 引号/单引号处理。

---

## 9. 需要的支撑

- 语言：class、String、Char、Bool、Int、Result；
- 运行时：字符串拼接/字符访问；
- 接口：`StringBuilder`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`StringBuilder`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

静态只读；返回新字符串；无资源。

---

## 12. 示例与反例

正确：`Escape.json("a\nb")` → `a\\nb`；`unescapeJson` 返回原文。  
反例：用 `html` 做完整 sanitizer；用 `shell` 保证安全；非法 `\u` 期望静默。

---

## 13. 测试/场景义务

JSON 控制字符/引号/反斜杠/`\u`；HTML/XML 五字符；CSV 逗号/引号/换行；shell 单引号；quoted/unquote；非法反转义。

---

## 14. XNull 伪代码

```xnull
class Escape {
    static String json(String text) {
        if text == null {
            throw "Escape.json: null"
        }
        StringBuilder builder = new StringBuilder()
        Int index = 0
        while index < text.length() {
            Char character = text.charAt(index)
            if character == '"' {
                builder.append("\\\"")
            } else if character == '\\' {
                builder.append("\\\\")
            } else if character == '\n' {
                builder.append("\\n")
            } else if character == '\r' {
                builder.append("\\r")
            } else if character == '\t' {
                builder.append("\\t")
            } else if character == '\b' {
                builder.append("\\b")
            } else if character == '\f' {
                builder.append("\\f")
            } else if (character as Int) < 32 {
                builder.append("\\u")
                builder.append(hex4(character as Int))
            } else {
                builder.appendChar(character)
            }
            index = index + 1
        }
        return builder.build()
    }

    static Result<String, Error> unescapeJson(String text) {
        if text == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null text"))
        }
        StringBuilder builder = new StringBuilder()
        Int index = 0
        while index < text.length() {
            Char character = text.charAt(index)
            if character != '\\' {
                builder.appendChar(character)
                index = index + 1
            } else {
                if index + 1 >= text.length() {
                    return Err(new BasicError(ErrorKind.InvalidArgument, "truncated escape"))
                }
                Char next = text.charAt(index + 1)
                if next == '"' { builder.appendChar('"') }
                else if next == '\\' { builder.appendChar('\\') }
                else if next == '/' { builder.appendChar('/') }
                else if next == 'n' { builder.appendChar('\n') }
                else if next == 'r' { builder.appendChar('\r') }
                else if next == 't' { builder.appendChar('\t') }
                else if next == 'b' { builder.appendChar('\b') }
                else if next == 'f' { builder.appendChar('\f') }
                else if next == 'u' {
                    if index + 5 >= text.length() {
                        return Err(new BasicError(ErrorKind.InvalidArgument, "truncated unicode escape"))
                    }
                    Result<Int, Error> code = parseHex4(text.substring(index + 2, 4))
                    if code.isErr() {
                        return Err(code.error())
                    }
                    builder.appendChar(code.value() as Char)
                    index = index + 4
                } else {
                    return Err(new BasicError(ErrorKind.InvalidArgument, "invalid escape"))
                }
                index = index + 2
            }
        }
        return Ok(builder.build())
    }

    static String html(String text) {
        if text == null {
            throw "Escape.html: null"
        }
        String result = text
        result = replace(result, "&", "&amp;")
        result = replace(result, "<", "&lt;")
        result = replace(result, ">", "&gt;")
        result = replace(result, "\"", "&quot;")
        result = replace(result, "'", "&#39;")
        return result
    }

    static String xml(String text) {
        return html(text)
    }

    static String csv(String text) {
        if text == null {
            throw "Escape.csv: null"
        }
        Bool needQuote = false
        Int index = 0
        while index < text.length() {
            Char character = text.charAt(index)
            if character == ',' || character == '"' || character == '\n' || character == '\r' {
                needQuote = true
            }
            index = index + 1
        }
        if !needQuote {
            return text
        }
        String result = "\""
        index = 0
        while index < text.length() {
            Char character = text.charAt(index)
            if character == '"' {
                result = result + "\"\""
            } else {
                result = result + str(character)
            }
            index = index + 1
        }
        return result + "\""
    }

    static String shell(String text) {
        if text == null {
            throw "Escape.shell: null"
        }
        String result = "'"
        Int index = 0
        while index < text.length() {
            Char character = text.charAt(index)
            if character == '\'' {
                result = result + "'\\''"
            } else {
                result = result + str(character)
            }
            index = index + 1
        }
        return result + "'"
    }

    static String quoted(String text) {
        return "\"" + replace(replace(text, "\\", "\\\\"), "\"", "\\\"") + "\""
    }

    static Result<String, Error> unquote(String text) {
        if text == null || text.length() < 2 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "not quoted"))
        }
        if text.charAt(0) != '"' || text.charAt(text.length() - 1) != '"' {
            return Err(new BasicError(ErrorKind.InvalidArgument, "not quoted"))
        }
        return unescapeJson(text.substring(1, text.length() - 2))
    }
}
```

> `hex4`、`parseHex4`、`replace` 是文本包内部辅助函数；`replace` 是字面量替换。
