# `TextFormatter`

| 项 | 值 |
| --- | --- |
| 类型 | `class TextFormatter implements Formatter` |
| 包 | `xdk.log` |
| 稳定性 | `stable` |
| 依赖 | `LogRecord`、`Field` |

---

## 1. 定位

文本格式化：`[LEVEL] name: message key=value ...`。

不做：JSON、颜色、locale、脱敏。

---

## 2. 设计逻辑

- 字段 `_includeFields: Bool`（默认 true）。
- 输出级别大写、logger 名、消息、字段 `key=value`。
- 单行；字段按记录顺序。
- 无状态（除 flag）；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_includeFields` | `Bool` | 是否输出字段 |

不变量：输出单行；不可变。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TextFormatter()` | 无 | 默认含字段 | 无 |
| `TextFormatter(Bool includeFields)` | includeFields | 任意 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `format` | 格式化 | `LogRecord` | `String` | null → panic |

---

## 8. 使用的技术

- 字符串拼接；
- 字段遍历；
- 单行归一。

---

## 9. 需要的支撑

- 语言：class、String、Bool；
- 运行时：无；
- 接口：`Formatter`、`LogRecord`、`Field`、`levelName`。

---

## 10. 依赖的特性/接口/类

`Formatter`、`LogRecord`、`Field`、`levelName`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`[INFO] app: started request.id=abc`。  
反例：多行消息；字段含换行；期望 JSON。

---

## 13. 测试/场景义务

级别/名称/消息；字段顺序；includeFields；空字段；单行。

---

## 14. XNull 伪代码

```xnull
class TextFormatter implements Formatter {
    final Bool _includeFields

    TextFormatter() {
        _includeFields = true
    }

    TextFormatter(Bool includeFields) {
        _includeFields = includeFields
    }

    String format(LogRecord record) {
        if record == null { throw "TextFormatter.format: null" }
        String result = "[" + levelName(record.level()) + "] "
            + record.loggerName() + ": " + record.message()
        if _includeFields {
            List<Field> fields = record.fields()
            Int index = 0
            while index < fields.length() {
                result = result + " " + fields.get(index).toString()
                index = index + 1
            }
        }
        return result
    }
}
```
