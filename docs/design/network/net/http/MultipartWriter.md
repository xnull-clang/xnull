# `MultipartWriter`

| 项 | 值 |
| --- | --- |
| 类型 | `class MultipartWriter` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`ByteStream`、`HttpHeaders`、`HttpBody`、`MediaType`、`Error` |

---

## 1. 定位

multipart 流式写出：写 part、文件 part、结束边界、关闭。

不做：解析 multipart、内存聚合、自动 Content-Length。

---

## 2. 设计逻辑

- 字段 `_target`、`_boundary`、`_finished`、`_closed`。
- writer 拥有 target；`close` 关闭 target。
- `addPart`/`addFile` 写边界/头/body；`finish` 写结束边界。
- `finish` 后不能再加 part；`close` 幂等。
- Context 取消；写失败传播。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_target` | `ByteStream` | 输出 |
| `_boundary` | `String` | 边界 |
| `_finished` | `Bool` | 已结束 |
| `_closed` | `Bool` | 已关闭 |

---

## 4. 生命周期

构造；必须 finish/close；close 幂等。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `MultipartWriter(ByteStream target, String boundary)` | target/boundary | 非 null；boundary 非空 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `addPart` | 添加 part | `Context, String name, HttpHeaders headers, HttpBody body` | `Result<Unit, Error>` | `Unavailable`/`Io`/`Cancelled` |
| `addFile` | 添加文件 | `Context, String name, String fileName, MediaType type, HttpBody body` | `Result<Unit, Error>` | 同上 |
| `finish` | 写结束边界 | `Context` | `Result<Unit, Error>` | 同上 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- multipart 边界；
- 流式写出；
- 资源关闭。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Result；
- 运行时：`multipartWriterPartRaw`、`multipartWriterFinishRaw`、`multipartWriterCloseRaw`；
- 接口：`Context`、`ByteStream`、`HttpHeaders`、`HttpBody`、`MediaType`、`Error`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`ByteStream`、`HttpHeaders`、`HttpBody`、`MediaType`、`Error`、multipart 运行时原语。

---

## 11. 所有权与并发

引用语义；拥有 target；发送串行化；close 可并发；无全局。

---

## 12. 示例与反例

正确：`writer.addPart(ctx,"field",headers,body); writer.finish(ctx); writer.close()`。  
反例：finish 后加 part；不 close；多个任务并发写同一 writer。

---

## 13. 测试/场景义务

单/多 part；文件 part；空 body；finish/close；取消；写失败；幂等。

---

## 14. XNull 伪代码

```xnull
class MultipartWriter {
    final ByteStream _target
    final String _boundary
    Bool _finished
    Bool _closed

    MultipartWriter(ByteStream target, String boundary) {
        if target == null { throw "MultipartWriter: null target" }
        if boundary == null || boundary == "" { throw "MultipartWriter: empty boundary" }
        _target = target
        _boundary = boundary
        _finished = false
        _closed = false
    }

    Result<Unit, Error> addPart(Context context, String name,
                                HttpHeaders headers, HttpBody body) {
        if context == null || name == null || headers == null || body == null {
            throw "MultipartWriter.addPart: null argument"
        }
        if _closed || _finished { return Err(unavailableError("multipart writer")) }
        return multipartWriterPartRaw(_target, context, _boundary, name, null, headers, body)
    }

    Result<Unit, Error> addFile(Context context, String name, String fileName,
                                MediaType type, HttpBody body) {
        if context == null || name == null || fileName == null || type == null || body == null {
            throw "MultipartWriter.addFile: null argument"
        }
        if _closed || _finished { return Err(unavailableError("multipart writer")) }
        HttpHeaders headers = new HttpHeaders()
        headers.add("Content-Type", type.text())
        return multipartWriterPartRaw(_target, context, _boundary, name, fileName, headers, body)
    }

    Result<Unit, Error> finish(Context context) {
        if context == null { throw "MultipartWriter.finish: null context" }
        if _closed { return Err(unavailableError("multipart writer")) }
        if !_finished {
            _finished = true
            return multipartWriterFinishRaw(_target, context, _boundary)
        }
        return Ok(unit)
    }

    Result<Unit, Error> close() {
        if _closed { return Ok(unit) }
        _closed = true
        return multipartWriterCloseRaw(_target)
    }
}
```

> `multipartWriter*Raw` 是运行时 multipart 原语；不是 XDK 公共类型。
