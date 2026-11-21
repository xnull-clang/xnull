# `CsvReader`

| 项 | 值 |
| --- | --- |
| 类型 | `class CsvReader` |
| 包 | `xdk.codec` |
| 稳定性 | `preview` |
| 依赖 | `Reader`、`CsvOptions`、`Error` |

---

## 1. 定位

逐条读取 CSV 记录；可选表头；关闭 Reader。

不做：类型映射、写 CSV、自动方言。

---

## 2. 设计逻辑

- 字段 `_reader`、`_options`、`_headers`、`_closed`。
- 构造读取表头（若 hasHeader）。
- `readRecord` 返回 `List<String>?`（EOF null）；`readAll` 读剩余。
- `close` 关闭 Reader；幂等。
- 非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_reader` | `Reader` | 输入 |
| `_options` | `CsvOptions` | 配置 |
| `_headers` | `List<String>` | 表头 |
| `_closed` | `Bool` | 关闭 |

---

## 4. 生命周期

构造；必须 close；close 幂等。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CsvReader(Reader reader, CsvOptions options)` | 非 null | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `readRecord` | 下一条/EOF | 无 | `Result<List<String>?, Error>` | `Io`/`DataCorrupted`/`Unavailable` |
| `readAll` | 剩余全部 | 无 | `Result<List<List<String>>, Error>` | 同上 |
| `headers` | 表头 | 无 | `List<String>` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- CSV 记录解析；
- Reader 所有权。

---

## 9. 需要的支撑

- 语言：class、List、String、Bool、Result；
- 运行时：`csvReaderReadRaw`、`csvReaderCloseRaw`；
- 接口：`Reader`、`CsvOptions`、`Error`。

---

## 10. 依赖的特性/接口/类

`Reader`、`CsvOptions`、`Error`、CSV Reader 原语。

---

## 11. 所有权与并发

拥有 Reader；单读者；close 可并发；无全局。

---

## 12. 示例与反例

正确：`while reader.readRecord() != null { ... }`。  
反例：EOF 当空记录；close 后读；多读者。

---

## 13. 测试/场景义务

表头；记录；EOF；空行；引号/换行；close 幂等；取消。

---

## 14. XNull 伪代码

```xnull
class CsvReader {
    final Reader _reader
    final CsvOptions _options
    List<String> _headers = []
    Bool _closed

    CsvReader(Reader reader, CsvOptions options) {
        if reader == null || options == null { throw "CsvReader: null argument" }
        _reader = reader
        _options = options.copy()
        _closed = false
        if _options.isHasHeader() {
            Result<List<String>, Error> header = self.readRecordRaw()
            if header.isErr() { throw "CsvReader: header failed" }
            _headers = header.value()
        }
    }

    Result<List<String>?, Error> readRecord() {
        if _closed { return Err(unavailableError("csv reader")) }
        Result<List<String>?, Error> result = csvReaderReadRaw(_reader, _options)
        return result
    }

    Result<List<List<String>>, Error> readAll() {
        List<List<String>> rows = []
        while true {
            Result<List<String>?, Error> record = self.readRecord()
            if record.isErr() { return Err(record.error()) }
            if record.value() == null { break }
            rows.push(record.value() as List<String>)
        }
        return Ok(rows)
    }

    List<String> headers() { return _headers.copy() }

    Result<Unit, Error> close() {
        if _closed { return Ok(unit) }
        _closed = true
        return _reader.close()
    }

    private Result<List<String>, Error> readRecordRaw() {
        Result<List<String>?, Error> record = csvReaderReadRaw(_reader, _options)
        if record.isErr() { return Err(record.error()) }
        if record.value() == null {
            return Err(new BasicError(ErrorKind.DataCorrupted, "missing header"))
        }
        return Ok(record.value() as List<String>)
    }
}
```

> `csvReaderReadRaw` 是运行时 CSV 原语；`unavailableError` 来自执行层/错误辅助。
