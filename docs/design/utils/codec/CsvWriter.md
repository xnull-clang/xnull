# `CsvWriter`

| 项 | 值 |
| --- | --- |
| 类型 | `class CsvWriter` |
| 包 | `xdk.codec` |
| 稳定性 | `preview` |
| 依赖 | `Writer`、`CsvOptions`、`Error` |

---

## 1. 定位

逐条写 CSV 记录；关闭 Writer。

不做：读 CSV、类型映射、自动表头。

---

## 2. 设计逻辑

- 字段 `_writer`、`_options`、`_closed`。
- `writeRecord` 写一行；`writeAll` 循环；`flush` 刷新。
- `close` 幂等并关闭 Writer。
- 非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_writer` | `Writer` | 输出 |
| `_options` | `CsvOptions` | 配置 |
| `_closed` | `Bool` | 关闭 |

---

## 4. 生命周期

构造；必须 close；close 幂等。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CsvWriter(Writer writer, CsvOptions options)` | 非 null | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `writeRecord` | 写一行 | `List<String>` | `Result<Unit, Error>` | `Unavailable`/`Io` |
| `writeAll` | 写多行 | `List<List<String>>` | `Result<Unit, Error>` | 同上 |
| `flush` | 刷新 | 无 | `Result<Unit, Error>` | `Io` |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- CSV 记录格式化；
- Writer 所有权。

---

## 9. 需要的支撑

- 语言：class、List、String、Bool、Result；
- 运行时：`csvWriterWriteRaw`、`csvWriterFlushRaw`、`csvWriterCloseRaw`；
- 接口：`Writer`、`CsvOptions`、`Error`。

---

## 10. 依赖的特性/接口/类

`Writer`、`CsvOptions`、`Error`、CSV Writer 原语。

---

## 11. 所有权与并发

拥有 Writer；单写者；close 可并发；无全局。

---

## 12. 示例与反例

正确：`writer.writeRecord(["a","b"]); writer.close()`。  
反例：close 后写；多写者；忽略 flush。

---

## 13. 测试/场景义务

空行/空字段；引号/转义；表头；flush；close 幂等；写失败。

---

## 14. XNull 伪代码

```xnull
class CsvWriter {
    final Writer _writer
    final CsvOptions _options
    Bool _closed

    CsvWriter(Writer writer, CsvOptions options) {
        if writer == null || options == null { throw "CsvWriter: null argument" }
        _writer = writer
        _options = options.copy()
        _closed = false
    }

    Result<Unit, Error> writeRecord(List<String> record) {
        if record == null { throw "CsvWriter.writeRecord: null" }
        if _closed { return Err(unavailableError("csv writer")) }
        return csvWriterWriteRaw(_writer, _options, record)
    }

    Result<Unit, Error> writeAll(List<List<String>> rows) {
        Int index = 0
        while index < rows.length() {
            Result<Unit, Error> written = self.writeRecord(rows.get(index))
            if written.isErr() { return Err(written.error()) }
            index = index + 1
        }
        return Ok(unit)
    }

    Result<Unit, Error> flush() {
        if _closed { return Err(unavailableError("csv writer")) }
        return csvWriterFlushRaw(_writer)
    }

    Result<Unit, Error> close() {
        if _closed { return Ok(unit) }
        _closed = true
        return csvWriterCloseRaw(_writer)
    }
}
```

> `csvWriter*Raw` 是运行时 CSV 原语；`unavailableError` 来自执行层/错误辅助。
