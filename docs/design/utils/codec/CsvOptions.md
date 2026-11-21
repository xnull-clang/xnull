# `CsvOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class CsvOptions` |
| 包 | `xdk.codec` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

CSV 解析/写出选项：分隔符、引号、转义、表头、空行、trim。

不做：类型映射、多字符分隔符、Excel 方言自动识别。

---

## 2. 设计逻辑

- 可变 builder；解析/写出时复制。
- 默认 `,`、`"`、`\`、无表头、跳过空行、不 trim。
- 分隔符/引号/转义必须是单 Char；非法 panic。
- 无 close；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_delimiter` | `Char` | 分隔符 |
| `_quote` | `Char` | 引号 |
| `_escape` | `Char` | 转义 |
| `_hasHeader` | `Bool` | 首行表头 |
| `_skipEmptyLines` | `Bool` | 跳过空行 |
| `_trim` | `Bool` | trim 字段 |

---

## 4. 生命周期

可变；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CsvOptions()` | 无 | 默认 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `delimiter` | 设置 | `Char` | `CsvOptions` | 无 |
| `quote` | 设置 | `Char` | `CsvOptions` | 无 |
| `escape` | 设置 | `Char` | `CsvOptions` | 无 |
| `hasHeader` | 设置 | `Bool` | `CsvOptions` | 无 |
| `skipEmptyLines` | 设置 | `Bool` | `CsvOptions` | 无 |
| `trim` | 设置 | `Bool` | `CsvOptions` | 无 |
| `getDelimiter` | 读取 | 无 | `Char` | 无 |
| `getQuote` | 读取 | 无 | `Char` | 无 |
| `getEscape` | 读取 | 无 | `Char` | 无 |
| `isHasHeader` | 读取 | 无 | `Bool` | 无 |
| `isSkipEmptyLines` | 读取 | 无 | `Bool` | 无 |
| `isTrim` | 读取 | 无 | `Bool` | 无 |
| `copy` | 快照 | 无 | `CsvOptions` | 无 |

---

## 8. 使用的技术

- builder；
- 单字符分隔。

---

## 9. 需要的支撑

- 语言：class、Char、Bool；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

可变；非线程安全；无资源。

---

## 12. 示例与反例

正确：`new CsvOptions().hasHeader(true)`。  
反例：多字符分隔符；修改 options 期望已有 reader 变化。

---

## 13. 测试/场景义务

默认；setter；copy；表头；空行；trim。

---

## 14. XNull 伪代码

```xnull
class CsvOptions {
    Char _delimiter = ','
    Char _quote = '"'
    Char _escape = '\\'
    Bool _hasHeader = false
    Bool _skipEmptyLines = true
    Bool _trim = false

    CsvOptions() {
    }

    CsvOptions delimiter(Char value) { _delimiter = value; return self }
    CsvOptions quote(Char value) { _quote = value; return self }
    CsvOptions escape(Char value) { _escape = value; return self }
    CsvOptions hasHeader(Bool value) { _hasHeader = value; return self }
    CsvOptions skipEmptyLines(Bool value) { _skipEmptyLines = value; return self }
    CsvOptions trim(Bool value) { _trim = value; return self }

    Char getDelimiter() { return _delimiter }
    Char getQuote() { return _quote }
    Char getEscape() { return _escape }
    Bool isHasHeader() { return _hasHeader }
    Bool isSkipEmptyLines() { return _skipEmptyLines }
    Bool isTrim() { return _trim }

    CsvOptions copy() {
        CsvOptions result = new CsvOptions()
        result.delimiter(_delimiter).quote(_quote).escape(_escape)
        result.hasHeader(_hasHeader).skipEmptyLines(_skipEmptyLines).trim(_trim)
        return result
    }
}
```
