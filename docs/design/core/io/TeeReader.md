# `TeeReader`

| 项 | 值 |
| --- | --- |
| 类型 | `class TeeReader implements Reader, Closer` |
| 包 | `xdk.io` |
| 稳定性 | `preview` |
| 依赖 | `Reader`、`Writer` |

---

## 1. 定位

边读边复制：读到数据同时写一份到 copy Writer。

不做：双向 tee、异步、缓冲。

---

## 2. 设计逻辑

- 字段 `_source: Reader`、`_copy: Writer`、`_open`。
- `read` 先读源；有数据则 `copy.writeAll`；copy 失败传播。
- `close` 关闭 source 和 copy。
- 单 reader；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_source` | `Reader` | 源 |
| `_copy` | `Writer` | 副本目标 |
| `_open` | `Bool` | 可用 |

不变量：copy 写入数据 = read 返回数据。

---

## 4. 生命周期

构造后使用；close 关闭两者。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TeeReader(Reader source, Writer copy)` | source/copy | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `read` | 读并复制 | `Context, Bytes buffer` | `Result<Int, Error>` | `Io`/`Unavailable` |
| `close` | 关闭两者 | 无 | `Result<Unit, Error>` | `Io` |
| `isOpen` | 可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 读后复制；
- 失败传播；
- 关闭传播。

---

## 9. 需要的支撑

- 语言：class、Bytes、Int、Bool、Result；
- 运行时：Reader/Writer；
- 接口：`Reader`、`Writer`、`Closer`。

---

## 10. 依赖的特性/接口/类

`Reader`、`Writer`、`Closer`、`Bytes`。

---

## 11. 所有权与并发

持有源/副本；close 两者；单 reader。

---

## 12. 示例与反例

正确：读网络流同时写日志/缓存。  
反例：期望 copy 不阻塞；copy 失败继续读；多任务共享。

---

## 13. 测试/场景义务

读复制一致；copy 失败；close 两者；EOF；空读。

---

## 14. XNull 伪代码

```xnull
class TeeReader implements Reader, Closer {
    Reader _source
    Writer _copy
    Bool _open

    TeeReader(Reader source, Writer copy) {
        if source == null || copy == null { throw "TeeReader: null argument" }
        _source = source
        _copy = copy
        _open = true
    }

    Result<Int, Error> read(Context context, Bytes buffer) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "reader closed"))
        }
        Result<Int, Error> read = _source.read(context, buffer)
        if read.isErr() { return Err(read.error()) }
        if read.value() > 0 {
            Bytes data = slice(buffer, 0, read.value())
            Result<Unit, Error> write = _copy.writeAll(context, data)
            if write.isErr() { return Err(write.error()) }
        }
        return read
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        Result<Unit, Error> sourceClosed = _source.close()
        Result<Unit, Error> copyClosed = _copy.close()
        if sourceClosed.isErr() { return sourceClosed }
        return copyClosed
    }

    Bool isOpen() { return _open }
}
```
