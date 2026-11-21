# `TlsServer`

| 项 | 值 |
| --- | --- |
| 类型 | `class TlsServer` |
| 包 | `xdk.net.tls` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`SocketAddress`、`TcpListener`、`TcpServerOptions`、`TlsConfig`、`TlsHandler`、`Error` |

---

## 1. 定位

TLS 服务端角色：TCP 监听 + TLS 握手 + 连接分派。

不做：HTTP、WebSocket、证书链管理、自动重载。

---

## 2. 设计逻辑

- 字段 `_listener`、`_tlsConfig`、`_options`、`_open`。
- `bind` 创建 TCP listener；`serve` accept 后握手，再交给 TlsHandler。
- Context 取消/close 停止 accept；在途连接由 handler close。
- close 幂等；无全局。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_listener` | `TcpListener` | TCP 监听 |
| `_tlsConfig` | `TlsConfig` | 服务端 TLS |
| `_options` | `TcpServerOptions` | 连接选项 |
| `_open` | `Bool` | 是否监听 |

---

## 4. 生命周期

bind 创建；必须 close；close 幂等。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TlsServer.bind(Context, SocketAddress, TlsConfig)` | 非 null | 证书/私钥已配置 | 绑定/TLS 失败 |
| `TlsServer.bind(Context, SocketAddress, TlsConfig, TcpServerOptions)` | 全部 | 非 null | 同上 |

构造器私有。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `bind` | 绑定 | `Context, SocketAddress, TlsConfig` | `Result<TlsServer, Error>` | `InvalidArgument`/绑定/TLS |
| `bind` | 带选项 | `Context, SocketAddress, TlsConfig, TcpServerOptions` | `Result<TlsServer, Error>` | 同上 |
| `serve` | accept/握手/分派 | `Context, TlsHandler` | `Result<Unit, Error>` | `Cancelled`/`Unavailable`/`Network` |
| `localAddress` | 地址 | 无 | `SocketAddress` | 无 |
| `isOpen` | 是否监听 | 无 | `Bool` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- TCP accept；
- TLS 握手；
- 每连接任务；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、Bool、Result；
- 运行时：`tlsServerServeRaw`；
- 接口：`Context`、`SocketAddress`、`TcpListener`、`TcpServerOptions`、`TlsConfig`、`TlsHandler`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`SocketAddress`、`TcpListener`、`TcpServerOptions`、`TlsConfig`、`TlsHandler`、`Error`、`BasicError`、`ErrorKind`、`tlsServerServeRaw`。

---

## 11. 所有权与并发

引用语义；拥有 listener；一个 serve 循环；close 可并发；无全局。

---

## 12. 示例与反例

正确：`TlsServer.bind(ctx, local, config).value().serve(ctx, handler)`。  
反例：无服务端证书；多 serve 循环；close 后 serve。

---

## 13. 测试/场景义务

绑定；握手；多连接；证书失败；取消；close 幂等；地址；handler 错误。

---

## 14. XNull 伪代码

```xnull
class TlsServer {
    final TcpListener _listener
    final TlsConfig _tlsConfig
    final TcpServerOptions _options
    Bool _open

    private TlsServer(TcpListener listener, TlsConfig tlsConfig, TcpServerOptions options) {
        _listener = listener
        _tlsConfig = tlsConfig
        _options = options
        _open = true
    }

    static Result<TlsServer, Error> bind(Context context, SocketAddress local, TlsConfig config) {
        return TlsServer.bind(context, local, config, new TcpServerOptions())
    }

    static Result<TlsServer, Error> bind(Context context, SocketAddress local,
                                          TlsConfig config, TcpServerOptions options) {
        if context == null || local == null || config == null || options == null {
            throw "TlsServer.bind: null argument"
        }
        if config.serverCertificate() == null || config.serverKey() == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "missing server certificate"))
        }
        Result<TcpListener, Error> listener = TcpListener.bind(
            context, local, options.getConnectionOptions())
        if listener.isErr() { return Err(listener.error()) }
        return Ok(new TlsServer(listener.value(), config, options.copy()))
    }

    Result<Unit, Error> serve(Context context, TlsHandler handler) {
        if context == null || handler == null {
            throw "TlsServer.serve: null argument"
        }
        if !_open { return Err(unavailableError("tls server")) }
        return tlsServerServeRaw(_listener, context, _tlsConfig, handler, _options)
    }

    SocketAddress localAddress() { return _listener.localAddress() }
    Bool isOpen() { return _open }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return _listener.close()
    }
}
```

> `tlsServerServeRaw` 是运行时 accept/TLS 分派原语；不是 XDK 公共类型。
