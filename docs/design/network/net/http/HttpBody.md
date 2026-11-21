# `HttpBody`

| 项 | 值 |
| --- | --- |
| 类型 | `class HttpBody` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Bytes`、`ByteStream`、`Error` |

---

## 1. 定位

HTTP 请求/响应 body：空、缓冲字节、文本、流式 body；读取/写出/关闭。

不做：表单/multipart 编码、内容编码、JSON 解析、自动压缩。

---

## 2. 设计逻辑

- 字段 `_bytes: Bytes?`、`_stream: ByteStream?`、`_contentLength: Long?`、`_closed`；缓冲与流二选一。
- 缓冲 body 拥有副本；流式 body 拥有流，close 释放。
- `contentLength` 可选；流式未知长度 null。
- `readAll` 有最大字节保护；缓冲超限 `InvalidArgument`；流式读满/EOF。
- `writeTo` 缓冲一次写出；流式用 `copyStream`。
- `close` 幂等；关闭后读取 `Unavailable`。
- 无 `form`/multipart；X。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_bytes` | `Bytes?` | 缓冲 |
| `_stream` | `ByteStream?` | 流式 |
| `_contentLength` | `Long?` | 已知长度 |
| `_closed` | `Bool` | 是否关闭 |

不变量：bytes 与 stream 不同时非 null；length ≥0 或 null；不可变结构 + close 状态。

---

## 4. 生命周期

构造；流式必须 close；close 幂等；缓冲 close 无操作。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `empty()` | 无 | 无 | 无 |
| `fromBytes(Bytes data)` | data | 非 null | null → panic |
| `fromText(String text)` | text | 非 null | null → panic |
| `fromStream(ByteStream stream, Long? contentLength)` | stream/length | stream 非 null；length ≥0 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `isEmpty` | 是否空 | 无 | `Bool` | 无 |
| `contentLength` | 长度/未知 | 无 | `Long?` | 无 |
| `bytes` | 缓冲/无 | 无 | `Bytes?` | 无 |
| `stream` | 流/无 | 无 | `ByteStream?` | 无 |
| `readAll` | 读全 | `Context, Long maximumBytes` | `Result<Bytes, Error>` | `InvalidArgument`/`Io`/`Cancelled` |
| `readText` | 读文本 | `Context, Long maximumBytes` | `Result<String, Error>` | 同上 |
| `writeTo` | 写到流 | `Context, ByteStream target` | `Result<Unit, Error>` | `Io`/`Cancelled` |
| `close` | 关闭流 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- 缓冲/流二选一；
- 最大字节保护；
- copyStream；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、Bytes、Long、Bool、Result；
- 运行时：`copyStream`、`readAllStreamLimited`、`toUtf8`、`fromUtf8`；
- 接口：`Context`、`ByteStream`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Context`、`Bytes`、`ByteStream`、`Error`、`copyStream`、`readAllStreamLimited`、`toUtf8`、`fromUtf8`。

---

## 11. 所有权与并发

拥有缓冲副本或流；流式单读者；close 可并发；无共享可变缓冲区。

---

## 12. 示例与反例

正确：`HttpBody.fromText("hi")`；流式下载 `body.readAll(ctx, max)`。  
反例：同时设 bytes/stream；忘记 close 流；把未知长度当 0；超限不报错。

---

## 13. 测试/场景义务

空/字节/文本/流；contentLength；readAll 超限/EOF；readText；writeTo；close 幂等；关闭后读。

---

## 14. XNull 伪代码

```xnull
class HttpBody {
    final Bytes? _bytes
    final ByteStream? _stream
    final Long? _contentLength
    Bool _closed

    private HttpBody(Bytes? bytes, ByteStream? stream, Long? contentLength) {
        _bytes = bytes
        _stream = stream
        _contentLength = contentLength
        _closed = false
    }

    static HttpBody empty() { return new HttpBody(Bytes.empty(), null, 0) }

    static HttpBody fromBytes(Bytes data) {
        if data == null { throw "HttpBody.fromBytes: null" }
        return new HttpBody(data.copy(), null, toLong(data.length()))
    }

    static HttpBody fromText(String text) {
        if text == null { throw "HttpBody.fromText: null" }
        return HttpBody.fromBytes(fromUtf8(text))
    }

    static HttpBody fromStream(ByteStream stream, Long? contentLength) {
        if stream == null { throw "HttpBody.fromStream: null" }
        if contentLength != null {
            Long value = contentLength as Long
            if value < 0 { throw "HttpBody.fromStream: negative length" }
        }
        return new HttpBody(null, stream, contentLength)
    }

    Bool isEmpty() {
        if _bytes == null { return false }
        return (_bytes as Bytes).length() == 0
    }

    Long? contentLength() { return _contentLength }
    Bytes? bytes() { if _bytes == null { return null }; return (_bytes as Bytes).copy() }
    ByteStream? stream() { return _stream }

    Result<Bytes, Error> readAll(Context context, Long maximumBytes) {
        if context == null { throw "HttpBody.readAll: null context" }
        if maximumBytes < 0 { throw "HttpBody.readAll: negative maximum" }
        if _closed { return Err(unavailableError("http body")) }
        if _bytes != null {
            Bytes data = _bytes as Bytes
            if toLong(data.length()) > maximumBytes {
                return Err(new BasicError(ErrorKind.InvalidArgument, "body exceeds maximum"))
            }
            return Ok(data.copy())
        }
        if _stream == null {
            return Ok(Bytes.empty())
        }
        return readAllStreamLimited(context, _stream as ByteStream, maximumBytes)
    }

    Result<String, Error> readText(Context context, Long maximumBytes) {
        Result<Bytes, Error> data = self.readAll(context, maximumBytes)
        if data.isErr() { return Err(data.error()) }
        return Ok(toUtf8(data.value()))
    }

    Result<Unit, Error> writeTo(Context context, ByteStream target) {
        if context == null || target == null { throw "HttpBody.writeTo: null argument" }
        if _closed { return Err(unavailableError("http body")) }
        if _bytes != null {
            return target.writeAll(context, _bytes as Bytes)
        }
        if _stream == null { return Ok(unit) }
        Result<Long, Error> copied = copyStream(context, _stream as ByteStream, target, 32768)
        if copied.isErr() { return Err(copied.error()) }
        return Ok(unit)
    }

    Result<Unit, Error> close() {
        if _closed { return Ok(unit) }
        _closed = true
        if _stream == null { return Ok(unit) }
        return (_stream as ByteStream).close()
    }
}
```

> `readAllStream` 是 `net` 顶层辅助；`unavailableError` 来自执行层/错误辅助。
