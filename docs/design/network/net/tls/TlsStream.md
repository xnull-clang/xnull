# `TlsStream`

| 项 | 值 |
| --- | --- |
| 类型 | `class TlsStream implements ByteStream` |
| 包 | `xdk.net.tls` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Bytes`、`ByteStream`、`TlsConfig`、`TlsSessionInfo`、`Error` |

---

## 1. 定位

TLS 字节流：在任意 `ByteStream` 上做客户端/服务端握手，提供加密读写、截止时间、协商信息和关闭。

不做：HTTP、WebSocket、证书链验证策略、会话缓存、裸 TLS 上下文、重新协商。

---

## 2. 设计逻辑

- 字段 `_handle`、`_transport`、`_session`、`_open`。
- `connect` 要求 `TlsConfig.serverName` 非空；`accept` 要求服务端证书/私钥。
- 成功握手后 `TlsStream` 拥有底层 `ByteStream`；`close` 同时关闭 TLS 句柄和底层流。
- 握手失败时不创建 `TlsStream`；底层流仍由调用方关闭。
- `read`/`write` 语义同 `ByteStream`；`writeAll` 循环。
- Context 取消/超时；关闭后 `Unavailable`。
- 一个 reader + 一个 writer 可并发；close 可并发。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_handle` | `TlsHandle` | 运行时 TLS 句柄 |
| `_transport` | `ByteStream` | 底层流 |
| `_session` | `TlsSessionInfo` | 协商信息 |
| `_open` | `Bool` | 是否打开 |

不变量：handle/transport/session 非 null；close 后 open=false；TlsStream 拥有 transport。

---

## 4. 生命周期

握手成功创建；必须 close；close 幂等；握手失败调用方关闭 transport。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TlsStream.connect(Context, ByteStream, TlsConfig)` | 非 null；serverName 非空 | 非 null | `InvalidArgument`/`Network`/`PermissionDenied`/`DataCorrupted`/`Timeout`/`Cancelled` |
| `TlsStream.accept(Context, ByteStream, TlsConfig)` | 非 null；服务端证书/私钥 | 非 null | 同上 |

构造器私有。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `connect` | 客户端握手 | `Context, ByteStream, TlsConfig` | `Result<TlsStream, Error>` | 握手失败 |
| `accept` | 服务端握手 | `Context, ByteStream, TlsConfig` | `Result<TlsStream, Error>` | 握手失败 |
| `read` | 读 | `Context, Bytes buffer` | `Result<Int, Error>` | `Unavailable`/`Network`/`Timeout`/`Cancelled` |
| `write` | 写 | `Context, Bytes data` | `Result<Int, Error>` | 同上 |
| `writeAll` | 写全 | `Context, Bytes data` | `Result<Unit, Error>` | 同上 |
| `setReadDeadline` | 读截止 | `Long deadlineMonoMillis` | `Result<Unit, Error>` | `Unavailable` |
| `setWriteDeadline` | 写截止 | `Long deadlineMonoMillis` | `Result<Unit, Error>` | 同上 |
| `sessionInfo` | 协商信息 | 无 | `TlsSessionInfo` | 无 |
| `isOpen` | 是否打开 | 无 | `Bool` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- TLS 1.2/1.3 握手；
- SNI/ALPN；
- 证书校验；
- 流封装；
- 单调截止；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、protocol 实现、Bytes、Long、Bool、Result；
- 运行时：`tlsConnectRaw`、`tlsAcceptRaw`、`tlsReadRaw`、`tlsWriteRaw`、`tlsSetDeadlineRaw`、`tlsCloseRaw`、`TlsHandle`、`TlsHandshakeRaw`；
- 接口：`Context`、`ByteStream`、`TlsConfig`、`TlsSessionInfo`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`ByteStream`、`TlsConfig`、`TlsSessionInfo`、`Error`、`BasicError`、`ErrorKind`、`TlsHandle`、TLS 运行时原语、`unavailableError`。

---

## 11. 所有权与并发

拥有 TLS 句柄和底层流；必须 close；一个 reader + 一个 writer；close 可并发；握手失败不接管 transport。

---

## 12. 示例与反例

正确：`TlsStream.connect(ctx, tcp, config.withServerName("example.com"))`。  
反例：未设 serverName；握手失败后让 TlsStream 关闭 transport；close 后继续读；多 reader 并发。

---

## 13. 测试/场景义务

客户端/服务端握手；证书失败；SNI；ALPN；mTLS 配置；读写/EOF/短写；截止；取消；close 幂等；底层关闭；握手失败所有权。

---

## 14. XNull 伪代码

```xnull
class TlsStream implements ByteStream {
    final TlsHandle _handle
    final ByteStream _transport
    final TlsSessionInfo _session
    Bool _open

    private TlsStream(TlsHandle handle, ByteStream transport, TlsSessionInfo session) {
        _handle = handle
        _transport = transport
        _session = session
        _open = true
    }

    static Result<TlsStream, Error> connect(Context context, ByteStream transport, TlsConfig config) {
        if context == null || transport == null || config == null {
            throw "TlsStream.connect: null argument"
        }
        if config.serverName() == null || config.serverName() == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "missing server name"))
        }
        Result<TlsHandshakeRaw, Error> raw = tlsConnectRaw(context, transport, config)
        if raw.isErr() { return Err(raw.error()) }
        TlsHandshakeRaw value = raw.value()
        return Ok(new TlsStream(value.handle(), transport, value.session()))
    }

    static Result<TlsStream, Error> accept(Context context, ByteStream transport, TlsConfig config) {
        if context == null || transport == null || config == null {
            throw "TlsStream.accept: null argument"
        }
        if config.serverCertificate() == null || config.serverKey() == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "missing server certificate"))
        }
        Result<TlsHandshakeRaw, Error> raw = tlsAcceptRaw(context, transport, config)
        if raw.isErr() { return Err(raw.error()) }
        TlsHandshakeRaw value = raw.value()
        return Ok(new TlsStream(value.handle(), transport, value.session()))
    }

    Result<Int, Error> read(Context context, Bytes buffer) {
        if context == null || buffer == null {
            throw "TlsStream.read: null argument"
        }
        if !_open { return Err(unavailableError("tls stream")) }
        return tlsReadRaw(_handle, context, buffer)
    }

    Result<Int, Error> write(Context context, Bytes data) {
        if context == null || data == null {
            throw "TlsStream.write: null argument"
        }
        if !_open { return Err(unavailableError("tls stream")) }
        return tlsWriteRaw(_handle, context, data)
    }

    Result<Unit, Error> writeAll(Context context, Bytes data) {
        if context == null || data == null {
            throw "TlsStream.writeAll: null argument"
        }
        Int total = 0
        while total < data.length() {
            Bytes part = slice(data, total, data.length())
            Result<Int, Error> written = self.write(context, part)
            if written.isErr() { return Err(written.error()) }
            if written.value() == 0 {
                return Err(unavailableError("tls write"))
            }
            total = total + written.value()
        }
        return Ok(unit)
    }

    Result<Unit, Error> setReadDeadline(Long deadlineMonoMillis) {
        if !_open { return Err(unavailableError("tls stream")) }
        return tlsSetDeadlineRaw(_handle, true, deadlineMonoMillis)
    }

    Result<Unit, Error> setWriteDeadline(Long deadlineMonoMillis) {
        if !_open { return Err(unavailableError("tls stream")) }
        return tlsSetDeadlineRaw(_handle, false, deadlineMonoMillis)
    }

    TlsSessionInfo sessionInfo() { return _session }
    Bool isOpen() { return _open }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        Result<Unit, Error> tlsClosed = tlsCloseRaw(_handle)
        Result<Unit, Error> transportClosed = _transport.close()
        if tlsClosed.isErr() { return Err(tlsClosed.error()) }
        return transportClosed
    }
}
```

> `TlsHandle`、`TlsHandshakeRaw` 和 `tls*Raw` 是运行时 TLS 原语；不是 XDK 公共类型。
