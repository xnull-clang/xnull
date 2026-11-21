# `Http2Stream`

| 项 | 值 |
| --- | --- |
| 类型 | `class Http2Stream` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`HttpHeaders`、`Http2Event`、`Http2StreamState`、`Http2ErrorCode`、`Bytes`、`Error` |

---

## 1. 定位

HTTP/2 单流：发头、发数据、收事件、RST、关闭。

不做：连接级 SETTINGS/PING/GOAWAY、流表调度、HPACK 细节。

---

## 2. 设计逻辑

- 字段 `_handle`、`_id`、`_state`、`_closed`。
- `sendHeaders` 可结束本地方向；`sendData` 可结束本地方向。
- `receive` 返回该流事件（Headers/Data/Reset/Error）；连接级事件由 Session 处理。
- `reset` 发 RST_STREAM；`close` 幂等。
- 一个 reader；发送内部串行化；Context 可取消。
- 流由 `Http2Session.newStream` 创建。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_handle` | `Http2StreamHandle` | 运行时流 |
| `_id` | `Int` | 流 ID |
| `_state` | `Http2StreamState` | 状态 |
| `_closed` | `Bool` | 是否关闭 |

不变量：id >0；state/closed 一致；不可重复关闭。

---

## 4. 生命周期

`newStream` 创建；必须 `reset` 或 `close`；close 幂等。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Http2Stream(Http2StreamHandle handle, Int id)` | handle/id | id >0 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `id` | 流 ID | 无 | `Int` | 无 |
| `state` | 状态 | 无 | `Http2StreamState` | 无 |
| `sendHeaders` | 发头 | `Context, HttpHeaders, Bool endStream` | `Result<Unit, Error>` | `Unavailable`/`Io`/`Cancelled` |
| `sendData` | 发数据 | `Context, Bytes, Bool endStream` | `Result<Unit, Error>` | 同上 |
| `receive` | 收事件 | `Context` | `Result<Http2Event, Error>` | 同上 |
| `reset` | RST_STREAM | `Context, Http2ErrorCode` | `Result<Unit, Error>` | 同上 |
| `close` | 关闭流 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- HTTP/2 流；
- HEADERS/DATA/RST；
- 流状态。

---

## 9. 需要的支撑

- 语言：class、Int、Bool、Result；
- 运行时：`http2StreamSendHeadersRaw`、`http2StreamSendDataRaw`、`http2StreamReceiveRaw`、`http2StreamResetRaw`、`http2StreamCloseRaw`、`Http2StreamHandle`；
- 接口：`Context`、`HttpHeaders`、`Http2Event`、`Http2StreamState`、`Http2ErrorCode`、`Bytes`、`Error`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`HttpHeaders`、`Http2Event`、`Http2StreamState`、`Http2ErrorCode`、`Bytes`、`Error`、HTTP/2 运行时原语。

---

## 11. 所有权与并发

引用语义；一个 reader；发送串行化；close 可并发；无全局。

---

## 12. 示例与反例

正确：`stream.sendHeaders(ctx, headers, false); stream.sendData(ctx, data, true)`。  
反例：关闭后发送；两个 reader；忽略 RST；把流事件当连接事件。

---

## 13. 测试/场景义务

发头/数据/结束；收 Headers/Data/Reset；RST；取消；close 幂等；状态迁移；并发发送。

---

## 14. XNull 伪代码

```xnull
class Http2Stream {
    final Http2StreamHandle _handle
    final Int _id
    Http2StreamState _state
    Bool _closed

    Http2Stream(Http2StreamHandle handle, Int streamId) {
        if handle == null { throw "Http2Stream: null handle" }
        if streamId <= 0 { throw "Http2Stream: invalid id" }
        _handle = handle
        _id = streamId
        _state = Http2StreamState.Open
        _closed = false
    }

    Int id() { return _id }
    Http2StreamState state() { return _state }

    Result<Unit, Error> sendHeaders(Context context, HttpHeaders headers, Bool endStream) {
        if context == null || headers == null { throw "Http2Stream.sendHeaders: null" }
        if _closed { return Err(unavailableError("http2 stream")) }
        return http2StreamSendHeadersRaw(_handle, context, headers.copy(), endStream)
    }

    Result<Unit, Error> sendData(Context context, Bytes data, Bool endStream) {
        if context == null || data == null { throw "Http2Stream.sendData: null" }
        if _closed { return Err(unavailableError("http2 stream")) }
        return http2StreamSendDataRaw(_handle, context, data, endStream)
    }

    Result<Http2Event, Error> receive(Context context) {
        if context == null { throw "Http2Stream.receive: null context" }
        if _closed { return Err(unavailableError("http2 stream")) }
        return http2StreamReceiveRaw(_handle, context)
    }

    Result<Unit, Error> reset(Context context, Http2ErrorCode code) {
        if context == null { throw "Http2Stream.reset: null context" }
        if _closed { return Ok(unit) }
        Result<Unit, Error> result = http2StreamResetRaw(_handle, context, code)
        if result.isErr() { return result }
        _closed = true
        _state = Http2StreamState.Closed
        return Ok(unit)
    }

    Result<Unit, Error> close() {
        if _closed { return Ok(unit) }
        _closed = true
        _state = Http2StreamState.Closed
        return http2StreamCloseRaw(_handle)
    }
}
```

> `Http2StreamHandle`、`http2Stream*Raw` 是运行时 HTTP/2 原语；不是 XDK 公共类型。
