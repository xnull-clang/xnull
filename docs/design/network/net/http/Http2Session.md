# `Http2Session`

| 项 | 值 |
| --- | --- |
| 类型 | `class Http2Session` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`ByteStream`、`Http2Settings`、`Http2SessionState`、`Http2Stream`、`Http2ErrorCode`、`Bytes`、`Error` |

---

## 1. 定位

HTTP/2 会话：握手、开流、SETTINGS、PING、GOAWAY、对端设置、关闭。

不做：HTTP/1 报文、TLS 握手、HTTP/3、流表调度细节。

---

## 2. 设计逻辑

- 字段 `_handle`、`_settings`、`_state`、`_open`。
- `connect`/`accept` 在已有 `ByteStream` 上做 HTTP/2 握手；session 拥有 transport。
- `newStream` 创建双向流；`sendSettings` 更新；`ping` 保活；`goAway` 优雅关闭。
- `peerSettings` 返回对端 SETTINGS 快照。
- Context 取消；close 幂等；关闭后开流 `Unavailable`。
- 握手失败不创建 session；transport 由调用方关闭。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_handle` | `Http2SessionHandle` | 运行时会话 |
| `_settings` | `Http2Settings` | 本地设置 |
| `_state` | `Http2SessionState` | 状态 |
| `_open` | `Bool` | 是否可用 |

不变量：handle/settings 非 null；close 后 open=false。

---

## 4. 生命周期

connect/accept 创建；必须 close；close 幂等；握手失败调用方关闭 transport。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Http2Session.connect(Context, ByteStream, Http2Settings)` | 非 null | 非 null | `Network`/`DataCorrupted`/`Timeout`/`Cancelled` |
| `Http2Session.accept(Context, ByteStream, Http2Settings)` | 非 null | 非 null | 同上 |

构造器私有。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `connect` | 客户端握手 | `Context, ByteStream, Http2Settings` | `Result<Http2Session, Error>` | 握手失败 |
| `accept` | 服务端握手 | `Context, ByteStream, Http2Settings` | `Result<Http2Session, Error>` | 握手失败 |
| `newStream` | 开流 | `Context` | `Result<Http2Stream, Error>` | `Unavailable`/`Timeout`/`Cancelled` |
| `sendSettings` | 发 SETTINGS | `Http2Settings settings` | `Result<Unit, Error>` | `Unavailable`/`Io` |
| `ping` | PING | `Context, Bytes payload` | `Result<Unit, Error>` | 同上 |
| `goAway` | GOAWAY | `Context, Http2ErrorCode code, String debug` | `Result<Unit, Error>` | 同上 |
| `peerSettings` | 对端设置 | 无 | `Http2Settings` | 无 |
| `state` | 会话状态 | 无 | `Http2SessionState` | 无 |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- HTTP/2 二进制帧；
- SETTINGS/PING/GOAWAY；
- 多路复用；
- 流创建；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、Bool、String、Result；
- 运行时：`http2SessionConnectRaw`、`http2SessionAcceptRaw`、`http2SessionNewStreamRaw`、`http2SessionSettingsRaw`、`http2SessionPingRaw`、`http2SessionGoAwayRaw`、`http2SessionPeerSettingsRaw`、`http2SessionCloseRaw`、`Http2SessionHandle`；
- 接口：`Context`、`ByteStream`、`Http2Settings`、`Http2SessionState`、`Http2Stream`、`Http2ErrorCode`、`Bytes`、`Error`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`ByteStream`、`Http2Settings`、`Http2SessionState`、`Http2Stream`、`Http2ErrorCode`、`Bytes`、`Error`、HTTP/2 运行时原语。

---

## 11. 所有权与并发

引用语义；拥有 session 和 transport；可并发开流；close 可并发；无全局。

---

## 12. 示例与反例

正确：`Http2Session.connect(ctx, tls, settings).value().newStream(ctx)`。  
反例：握手失败后让 session 关闭 transport；close 后开流；把 HTTP/2 会话当 HTTP/1 连接。

---

## 13. 测试/场景义务

客户端/服务端握手；SETTINGS/PING/GOAWAY；多流；并发流；取消；close 幂等；对端设置；握手失败所有权。

---

## 14. XNull 伪代码

```xnull
class Http2Session {
    final Http2SessionHandle _handle
    final Http2Settings _settings
    Http2SessionState _state
    Bool _open

    private Http2Session(Http2SessionHandle handle, Http2Settings settings) {
        _handle = handle
        _settings = settings
        _state = Http2SessionState.Open
        _open = true
    }

    static Result<Http2Session, Error> connect(Context context, ByteStream transport,
                                                Http2Settings settings) {
        if context == null || transport == null || settings == null {
            throw "Http2Session.connect: null argument"
        }
        Result<Http2SessionHandle, Error> raw = http2SessionConnectRaw(context, transport, settings)
        if raw.isErr() { return Err(raw.error()) }
        return Ok(new Http2Session(raw.value(), settings))
    }

    static Result<Http2Session, Error> accept(Context context, ByteStream transport,
                                               Http2Settings settings) {
        if context == null || transport == null || settings == null {
            throw "Http2Session.accept: null argument"
        }
        Result<Http2SessionHandle, Error> raw = http2SessionAcceptRaw(context, transport, settings)
        if raw.isErr() { return Err(raw.error()) }
        return Ok(new Http2Session(raw.value(), settings))
    }

    Result<Http2Stream, Error> newStream(Context context) {
        if context == null { throw "Http2Session.newStream: null context" }
        if !_open { return Err(unavailableError("http2 session")) }
        return http2SessionNewStreamRaw(_handle, context)
    }

    Result<Unit, Error> sendSettings(Http2Settings settings) {
        if settings == null { throw "Http2Session.sendSettings: null" }
        if !_open { return Err(unavailableError("http2 session")) }
        return http2SessionSettingsRaw(_handle, settings)
    }

    Result<Unit, Error> ping(Context context, Bytes payload) {
        if context == null || payload == null {
            throw "Http2Session.ping: null argument"
        }
        if !_open { return Err(unavailableError("http2 session")) }
        return http2SessionPingRaw(_handle, context, payload)
    }

    Result<Unit, Error> goAway(Context context, Http2ErrorCode code, String debug) {
        if context == null || debug == null {
            throw "Http2Session.goAway: null argument"
        }
        if !_open { return Ok(unit) }
        _state = Http2SessionState.Closing
        Result<Unit, Error> result = http2SessionGoAwayRaw(_handle, context, code, debug)
        if result.isOk() { _state = Http2SessionState.Closed }
        return result
    }

    Http2Settings peerSettings() { return http2SessionPeerSettingsRaw(_handle) }
    Http2SessionState state() { return _state }
    Bool isOpen() { return _open }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        _state = Http2SessionState.Closed
        return http2SessionCloseRaw(_handle)
    }
}
```

> `Http2SessionHandle`、`http2Session*Raw` 是运行时 HTTP/2 原语；不是 XDK 公共类型。
