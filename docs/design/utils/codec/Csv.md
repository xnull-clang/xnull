# `Csv`

| 项 | 值 |
| --- | --- |
| 类型 | `class Csv` |
| 包 | `xdk.codec` |
| 稳定性 | `preview` |
| 依赖 | `CsvOptions`、`CsvReader`、`CsvWriter`、`Reader`、`Writer`、`Error` |

---

## 1. 定位

CSV 静态入口：文本/Reader 解析、文本写出。

不做：类型映射、Excel、多字符分隔符、自动方言。

---

## 2. 设计逻辑

- 无实例状态；构造器私有。
- `parse` 使用 `CsvReader` 读全；`write` 使用 `CsvWriter`。
- 行是 `List<List<String>>`；表头由 options 控制。
- 失败 `DataCorrupted`；资源由 Reader/Writer 关闭。
- 无 close；可并发。

---

## 3. 表示与不变量

无实例字段。

---

## 4. 生命周期

静态命名空间；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Csv()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `parse` | 文本解析 | `String, CsvOptions` | `Result<List<List<String>>, Error>` | `DataCorrupted` |
| `parseReader` | Reader 解析 | `Context, Reader, CsvOptions` | `Result<List<List<String>>, Error>` | `Io`/`Cancelled`/`DataCorrupted` |
| `write` | 文本写出 | `List<List<String>>, CsvOptions` | `String` | 无 |
| `writeTo` | 写 Writer | `Context, Writer, List<List<String>>, CsvOptions` | `Result<Unit, Error>` | `Io`/`Cancelled` |

---

## 8. 使用的技术

- CSV 记录解析/格式化；
- Reader/Writer。

---

## 9. 需要的支撑

- 语言：class、List、String、Result；
- 运行时：`csvParseAllRaw`、`csvWriteAllRaw`；
- 接口：`CsvOptions`、`CsvReader`、`CsvWriter`、`Reader`、`Writer`、`Context`、`Error`。

---

## 10. 依赖的特性/接口/类

`CsvOptions`、`CsvReader`、`CsvWriter`、`Reader`、`Writer`、`Context`、`Error`。

---

## 11. 所有权与并发

无状态；无资源；可并发。

---

## 12. 示例与反例

正确：`Csv.parse(text, options)`。  
反例：忽略引号内换行；把空行当记录；类型映射。

---

## 13. 测试/场景义务

引号/转义/换行；表头；空行；空字段；CRLF；非法；Reader 取消。

---

## 14. XNull 伪代码

```xnull
class Csv {
    private Csv() {
    }

    static Result<List<List<String>>, Error> parse(String text, CsvOptions options) {
        if text == null || options == null { throw "Csv.parse: null argument" }
        return csvParseAllRaw(text, options.copy())
    }

    static Result<List<List<String>>, Error> parseReader(Context context, Reader reader,
                                                          CsvOptions options) {
        if context == null || reader == null || options == null {
            throw "Csv.parseReader: null argument"
        }
        CsvReader csv = new CsvReader(reader, options)
        return csv.readAll()
    }

    static String write(List<List<String>> rows, CsvOptions options) {
        if rows == null || options == null { throw "Csv.write: null argument" }
        return csvWriteAllRaw(rows, options.copy())
    }

    static Result<Unit, Error> writeTo(Context context, Writer writer,
                                       List<List<String>> rows, CsvOptions options) {
        if context == null || writer == null || rows == null || options == null {
            throw "Csv.writeTo: null argument"
        }
        CsvWriter csv = new CsvWriter(writer, options)
        Result<Unit, Error> written = csv.writeAll(rows)
        if written.isErr() { return written }
        return csv.flush()
    }
}
```

> `csvParseAllRaw`、`csvWriteAllRaw` 是运行时 CSV 原语；不是 XDK 公共类型。
