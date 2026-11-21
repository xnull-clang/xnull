# `LineReader`

| 项 | 值 |
| --- | --- |
| 类型 | `class LineReader implements Closer` |
| 包 | `xdk.io` |
| 稳定性 | `preview` |
| 依赖 | `Reader` |

---

## 1. 定位

按行读取：`readLine` 返回一行或 null（EOF）。

不做：行号、编码检测、异步。

---

## 2. 设计逻辑

- 包装 Reader；逐字节读到 `\n` 或 EOF。
- 丢弃 `\r`（兼容 CRLF）。
- EOF 且无内容 → null；空行 → 空串。
- close 关闭源；单 reader。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_source` | `Reader` | 底层 |
| `_open` | `Bool` | 可用 |

不变量：无内部行缓冲；每次调用完整读取一行。

---

## 4. 生命周期

构造后使用；close 关闭源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `LineReader(Reader source)` | source | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `readLine` | 读一行 | `Context` | `Result<String?, Error>` | `Io`/`Unavailable` |
| `tryReadLine` | checked 读行 | `Context` | `Result<String?, Error>` | 同上 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io` |
| `isOpen` | 可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 单字节读取；
- 行尾归一；
- EOF 空行区分。

---

## 9. 需要的支撑

- 语言：class、String、Bytes、Result；
- 运行时：底层 Reader；
- 接口：`Reader`、`Closer`。

---

## 10. 依赖的特性/接口/类

`Reader`、`Closer`、`Bytes`。

---

## 11. 所有权与并发

包装源；close 传递；单 reader。

---

## 12. 示例与反例

正确：循环 readLine 直到 null。  
反例：把空串当 EOF；期望保留 `\r`；多任务共享。

---

## 13. 测试/场景义务

空源；单行；多行；空行；CRLF；末尾无换行；close。

---

## 14. XNull 伪代码

```xnull
class LineReader implements Closer {
    Reader _source
    Bool _open

    LineReader(Reader source) {
        if source == null { throw "LineReader: null source" }
        _source = source
        _open = true
    }

    Result<String?, Error> readLine(Context context) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "reader closed"))
        }
        Bytes line = Bytes.empty()
        Bytes one = Bytes.alloc(1)
        while true {
            Result<Int, Error> read = _source.read(context, one)
            if read.isErr() { return Err(read.error()) }
            if read.value() == 0 {
                if line.isEmpty() { return Ok(null) }
                return Ok(toUtf8(line))
            }
            if one.get(0) == 10 {
                return Ok(toUtf8(line))
            }
            if one.get(0) != 13 {
                line.push(one.get(0))
            }
        }
    }

    Result<String?, Error> tryReadLine(Context context) {
        return self.readLine(context)
    }

    Result<Unit, Error> close() {
        _open = false
        return _source.close()
    }

    Bool isOpen() { return _open }
}
```
