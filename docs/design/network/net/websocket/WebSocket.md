# `WebSocket`

| 项 | 值 |
| --- | --- |
| 类型 | `class WebSocket` |
| 包 | `xdk.net.websocket` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Uri`、`HttpRequest`、`ByteStream`、`WebSocketOptions`、`WebSocketMessage`、`WebSocketState`、`WebSocketCloseCode`、`Error` |

---

## 1. 定位

WebSocket 连接：客户端/服务端握手、文本/二进制/控制帧、接收、关闭、状态。

不做：HTTP/2 WebSocket、压缩、重连（`WebSocketClient`）、消息重放。

---

## 2. 设计逻辑

- 字段 `_handle`、`_options`、`_state`、`_subprotocol`、`_open`。
- `connect` 走 ws/wss + HTTP upgrade；`accept` 包装已升级 ByteStream。
- 发送内部串行化；接收单消费者；ping/pong 自动/显式。
- 正常 Close 不是 `Err`；关闭后 `Unavailable`。
- Context 取消；close 幂等。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_handle` | `WebSocketHandle` | 运行时连接 |
| `_options` | `WebSocketOptions` | 配置副本 |
| `_state` | `WebSocketState` | 状态 |
| `_subprotocol` | `String?` | 协商子协议 |
| `_open` | `Bool` | 是否可用 |

---

## 4. 生命周期

connect/accept 创建；必须 close；close 幂等；握手失败调用方关闭 transport。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `WebSocket.connect(Context, Uri, WebSocketOptions)` | 非 null | 非 null | `InvalidArgument`/`Network`/`PermissionDenied`/`Timeout`/`Cancelled` |
| `WebSocket.accept(Context, HttpRequest, ByteStream, WebSocketOptions)` | 非 null | 非 null | 同上 |

构造器私有。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `connect` | 客户端握手 | `Context, Uri, WebSocketOptions` | `Result<WebSocket, Error>` | 握手失败 |
| `accept` | 服务端握手 | `Context, HttpRequest, ByteStream, WebSocketOptions` | `Result<WebSocket, Error>` | 握手失败 |
| `sendText` | 发文本 | `Context, String` | `Result<Unit, Error>` | `Unavailable`/`Busy`/`Timeout`/`Cancelled` |
| `sendBinary` | 发二进制 | `Context, Bytes` | `Result<Unit, Error>` | 同上 |
| `sendPing` | Ping | `Context, Bytes` | `Result<Unit, Error>` | 同上 |
| `sendPong` | Pong | `Context, Bytes` | `Result<Unit, Error>` | 同上 |
| `trySendText` | 非阻塞文本 | `String` | `Result<Unit, Error>` | `Busy`/`Unavailable` |
| `trySendBinary` | 非阻塞二进制 | `Bytes` | `Result<Unit, Error>` | 同上 |
| `receive` | 收消息 | `Context` | `Result<WebSocketMessage, Error>` | `Unavailable`/`Network`/`Timeout`/`Cancelled` |
| `close` | 关闭 | `Context, WebSocketCloseCode, String` | `Result<Unit, Error>` | 同上 |
| `close` | 正常关闭 | `Context` | `Result<Unit, Error>` | 同上 |
| `state` | 状态 | 无 | `WebSocketState` | 无 |
| `isOpen` | 是否 Open | 无 | `Bool` | 无 |
| `subprotocol` | 子协议 | 无 | `String?` | 无 |
| `setReadDeadline` | 读截止 | `Long` | `Result<Unit, Error>` | `Unavailable` |
| `setWriteDeadline` | 写截止 | `Long` | `Result<Unit, Error>` | 同上 |

---

## 8. 使用的技术

- HTTP upgrade；
- WebSocket 帧/掩码/分片；
- ping/pong；
- 关闭握手；
- 背压。

---

## 9. 需要的支撑

- 语言：class、Bool、String、Long、Result；
- 运行时：`websocketConnectRaw`、`websocketAcceptRaw`、`websocketSendRaw`、`websocketTrySendRaw`、`websocketReceiveRaw`、`websocketCloseRaw`、`websocketDeadlineRaw`、`WebSocketHandle`；
- 接口：`Context`、`Uri`、`HttpRequest`、`ByteStream`、`WebSocketOptions`、`WebSocketMessage`、`WebSocketState`、`WebSocketCloseCode`、`Error`、`unavailableError`、`fromUtf8`。

---

## 10. 依赖的特性/接口/类

`Context`、`Uri`、`HttpRequest`、`ByteStream`、`WebSocketOptions`、`WebSocketMessage`、`WebSocketState`、`WebSocketCloseCode`、`Error`、`fromUtf8`、WebSocket 运行时原语。

---

## 11. 所有权与并发

引用语义；一个 receiver；发送串行化；close 可并发；无全局。

---

## 12. 示例与反例

正确：`socket.sendText(ctx,"hi"); WebSocketMessage m = socket.receive(ctx).value()`。  
反例：多 receiver；Close 后发送；把 Close 当 Err；忽略 Busy。

---

## 13. 测试/场景义务

握手；文本/二进制；ping/pong；关闭握手；状态；背压/Busy；deadline；取消；close 幂等；子协议。

---

## 14. XNull 伪代码

```xnull
class WebSocket {
    final WebSocketHandle _handle
    final WebSocketOptions _options
    WebSocketState _state
    final String? _subprotocol
    Bool _open

    private WebSocket(WebSocketHandle handle, WebSocketOptions options, String? subprotocol) {
        _handle = handle
        _options = options
        _state = WebSocketState.Open
        _subprotocol = subprotocol
        _open = true
    }

    static Result<WebSocket, Error> connect(Context context, Uri uri, WebSocketOptions options) {
        if context == null || uri == null || options == null {
            throw "WebSocket.connect: null argument"
        }
        Result<WebSocketHandshakeRaw, Error> raw = websocketConnectRaw(context, uri, options.copy())
        if raw.isErr() { return Err(raw.error()) }
        WebSocketHandshakeRaw value = raw.value()
        return Ok(new WebSocket(value.handle(), options.copy(), value.subprotocol()))
    }

    static Result<WebSocket, Error> accept(Context context, HttpRequest request,
                                           ByteStream stream, WebSocketOptions options) {
        if context == null || request == null || stream == null || options == null {
            throw "WebSocket.accept: null argument"
        }
        Result<WebSocketHandshakeRaw, Error> raw = websocketAcceptRaw(
            context, request, stream, options.copy())
        if raw.isErr() { return Err(raw.error()) }
        WebSocketHandshakeRaw value = raw.value()
        return Ok(new WebSocket(value.handle(), options.copy(), value.subprotocol()))
    }

    Result<Unit, Error> sendText(Context context, String text) {
        if context == null || text == null { throw "WebSocket.sendText: null" }
        if !_open { return Err(unavailableError("websocket")) }
        return websocketSendRaw(_handle, context, WebSocketMessageKind.Text, fromUtf8(text), null, "")
    }

    Result<Unit, Error> sendBinary(Context context, Bytes data) {
        if context == null || data == null { throw "WebSocket.sendBinary: null" }
        if !_open { return Err(unavailableError("websocket")) }
        return websocketSendRaw(_handle, context, WebSocketMessageKind.Binary, data, null, "")
    }

    Result<Unit, Error> sendPing(Context context, Bytes payload) {
        if context == null || payload == null { throw "WebSocket.sendPing: null" }
        if !_open { return Err(unavailableError("websocket")) }
        return websocketSendRaw(_handle, context, WebSocketMessageKind.Ping, payload, null, "")
    }

    Result<Unit, Error> sendPong(Context context, Bytes payload) {
        if context == null || payload == null { throw "WebSocket.sendPong: null" }
        if !_open { return Err(unavailableError("websocket")) }
        return websocketSendRaw(_handle, context, WebSocketMessageKind.Pong, payload, null, "")
    }

    Result<Unit, Error> trySendText(String text) {
        if text == null { throw "WebSocket.trySendText: null" }
        if !_open { return Err(unavailableError("websocket")) }
        return websocketTrySendRaw(_handle, WebSocketMessageKind.Text, fromUtf8(text), null, "")
    }

    Result<Unit, Error> trySendBinary(Bytes data) {
        if data == null { throw "WebSocket.trySendBinary: null" }
        if !_open { return Err(unavailableError("websocket")) }
        return websocketTrySendRaw(_handle, WebSocketMessageKind.Binary, data, null, "")
    }

    Result<WebSocketMessage, Error> receive(Context context) {
        if context == null { throw "WebSocket.receive: null context" }
        if !_open { return Err(unavailableError("websocket")) }
        return websocketReceiveRaw(_handle, context)
    }

    Result<Unit, Error> close(Context context, WebSocketCloseCode code, String reason) {
        if context == null || reason == null { throw "WebSocket.close: null" }
        if !_open { return Ok(unit) }
        _open = false
        _state = WebSocketState.Closing
        Result<Unit, Error> result = websocketCloseRaw(_handle, context, code, reason)
        if result.isOk() { _state = WebSocketState.Closed }
        return result
    }

    Result<Unit, Error> close(Context context) {
        return self.close(context, WebSocketCloseCode.Normal, "")
    }

    WebSocketState state() { return _state }
    Bool isOpen() { return _open }
    String? subprotocol() { return _subprotocol }

    Result<Unit, Error> setReadDeadline(Long deadlineMonoMillis) {
        if !_open { return Err(unavailableError("websocket")) }
        return websocketDeadlineRaw(_handle, true, deadlineMonoMillis)
    }

    Result<Unit, Error> setWriteDeadline(Long deadlineMonoMillis) {
        if !_open { return Err(unavailableError("websocket")) }
        return websocketDeadlineRaw(_handle, false, deadlineMonoMillis)
    }
}
```

> `WebSocketHandle`、`WebSocketHandshakeRaw`、`websocket*Raw` 是运行时 WebSocket 原语；不是 XDK 公共类型。
